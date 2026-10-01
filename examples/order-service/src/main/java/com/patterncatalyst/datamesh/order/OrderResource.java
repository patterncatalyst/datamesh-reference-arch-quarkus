package com.patterncatalyst.datamesh.order;

import java.time.format.DateTimeFormatter;
import java.util.List;

import org.jboss.logging.Logger;

import com.patterncatalyst.datamesh.domain.OrderCreate;
import com.patterncatalyst.datamesh.domain.OrderDto;

import capstone.inventory.v1.Inventory.CheckStockResponse;
import io.grpc.StatusRuntimeException;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.event.Event;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * Order data product REST endpoints. Mirrors {@code app/main.py} in the
 * Python reference architecture (r21 REST + Postgres, r23 gRPC stock check,
 * r25 order.placed event emission):
 *
 * <ul>
 *   <li>{@code POST /orders} -- check inventory over gRPC, persist with
 *       status {@code PLACED} if available (409 otherwise), then publish
 *       {@code order.placed}.</li>
 *   <li>{@code GET /orders} -- list orders, most recent first.</li>
 *   <li>{@code GET /orders/{id}} -- fetch a single order (404 if absent).</li>
 * </ul>
 */
@Path("/orders")
@Produces(MediaType.APPLICATION_JSON)
public class OrderResource {

    private static final Logger LOG = Logger.getLogger(OrderResource.class);

    @Inject
    InventoryClient inventoryClient;

    // Fired after order.persist() below and observed by OrderEventProducer
    // ONLY once this method's surrounding transaction has committed (see
    // OrderEventProducer#onOrderPlaced) -- this is what makes the
    // order.placed Kafka publish happen strictly after the order is
    // durable, instead of racing ahead of the commit from inside this
    // @Transactional method.
    @Inject
    Event<Order> orderPlacedEvent;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Transactional
    public Response placeOrder(@Valid OrderCreate payload) {
        CheckStockResponse stock;
        try {
            stock = inventoryClient.checkStock(payload.itemSku(), payload.quantity());
        } catch (StatusRuntimeException e) {
            // Fail closed: never place an order we couldn't validate against
            // inventory (mirrors the Python InventoryUnreachable case).
            LOG.warnf("inventory-service unreachable: %s", e.getMessage());
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                    .entity("inventory-service unreachable: " + e.getMessage())
                    .build();
        }

        if (!stock.getAvailable()) {
            return Response.status(Response.Status.CONFLICT)
                    .entity("insufficient stock for %s (%d on hand)"
                            .formatted(payload.itemSku(), stock.getQuantityOnHand()))
                    .build();
        }

        Order order = Order.create(payload.customerId(), payload.itemSku(), payload.quantity(), payload.amount());
        order.persist();

        // r25: fire a CDI event rather than publishing to Kafka directly
        // here. OrderEventProducer observes this event with
        // @Observes(during = TransactionPhase.AFTER_SUCCESS), so the actual
        // publish only runs once the transaction wrapping this method has
        // committed -- the order is genuinely durable by the time anyone
        // downstream sees order.placed. A publish failure must not fail
        // this (already-committed) order; see OrderEventProducer. The
        // dual-write gap this leaves (commit succeeds, process crashes
        // before the observer runs) is the transactional outbox pattern's
        // job in production, not this example.
        orderPlacedEvent.fire(order);

        return Response.status(Response.Status.CREATED).entity(toDto(order)).build();
    }

    // Explicit WILDCARD so this bodyless GET isn't matched against the
    // sibling POST method's @Consumes(APPLICATION_JSON) -- without it,
    // RESTEasy Reactive 415s any request whose Content-Type isn't JSON
    // (e.g. hey's default text/html) even though GET has no body to parse.
    @GET
    @Consumes(MediaType.WILDCARD)
    public List<OrderDto> listOrders() {
        return Order.<Order>listAll(Sort.by("createdAt").descending())
                .stream()
                .map(OrderResource::toDto)
                .toList();
    }

    @GET
    @Path("/{id}")
    @Consumes(MediaType.WILDCARD)
    public Response getOrder(@PathParam("id") String id) {
        Order order = Order.findById(id);
        if (order == null) {
            return Response.status(Response.Status.NOT_FOUND).build();
        }
        return Response.ok(toDto(order)).build();
    }

    private static OrderDto toDto(Order order) {
        return new OrderDto(
                order.id,
                order.customerId,
                order.itemSku,
                order.quantity,
                order.amount,
                order.status,
                DateTimeFormatter.ISO_INSTANT.format(order.createdAt));
    }
}
