package com.patterncatalyst.datamesh.order;

import java.time.format.DateTimeFormatter;
import java.util.List;

import org.jboss.logging.Logger;

import com.patterncatalyst.datamesh.domain.OrderCreate;
import com.patterncatalyst.datamesh.domain.OrderDto;

import capstone.inventory.v1.Inventory.CheckStockResponse;
import io.grpc.StatusRuntimeException;
import io.quarkus.panache.common.Sort;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
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
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class OrderResource {

    private static final Logger LOG = Logger.getLogger(OrderResource.class);

    @Inject
    InventoryClient inventoryClient;

    @Inject
    OrderEventProducer eventProducer;

    @POST
    @Transactional
    public Response placeOrder(OrderCreate payload) {
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

        // r25: emit only after the order is durably persisted. A publish
        // failure must not fail the order -- it's already committed. The
        // dual-write gap this leaves is the outbox pattern's job in
        // production (see OrderEventProducer).
        eventProducer.publish(order).exceptionally(ex -> {
            LOG.warnf(ex, "failed to publish order.placed for %s", order.id);
            return null;
        });

        return Response.status(Response.Status.CREATED).entity(toDto(order)).build();
    }

    @GET
    public List<OrderDto> listOrders() {
        return Order.<Order>listAll(Sort.by("createdAt").descending())
                .stream()
                .map(OrderResource::toDto)
                .toList();
    }

    @GET
    @Path("/{id}")
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
