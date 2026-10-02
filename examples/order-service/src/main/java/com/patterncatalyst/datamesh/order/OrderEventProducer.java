package com.patterncatalyst.datamesh.order;

import java.time.format.DateTimeFormatter;
import java.util.concurrent.CompletionStage;

import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.jboss.logging.Logger;

import capstone.order.v1.OrderPlaced;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.event.TransactionPhase;
import jakarta.inject.Inject;

/**
 * Publishes {@code order.placed} as Avro against the Apicurio Schema
 * Registry after an order has been durably persisted. Mirrors
 * {@code app/events.py::publish_order_placed} in the Python reference
 * architecture: publishing happens strictly after commit, and a publish
 * failure must never fail the already-committed order -- this class treats
 * it as best-effort and only logs on failure. The dual-write gap this
 * leaves is the outbox pattern's job in production, not this example.
 *
 * <p>"Strictly after commit" is enforced, not just ordered-by-convention:
 * {@link OrderResource#placeOrder} fires a CDI {@code Event<Order>} right
 * after {@code order.persist()}, and {@link #onOrderPlaced} below observes
 * it with {@code @Observes(during = TransactionPhase.AFTER_SUCCESS)}, a
 * transactional observer that JTA only invokes once the surrounding
 * {@code @Transactional} method's transaction has actually committed. Only
 * that observer calls {@link #publish}; nothing calls it from inside the
 * transaction.
 *
 * <p>The outgoing channel ({@code order-placed}, mapped to the
 * {@code order.placed} Kafka topic in {@code application.properties}) uses
 * the Apicurio Avro serializer. Note: {@code value.serializer} is set
 * EXPLICITLY in {@code application.properties} rather than left to Quarkus
 * autodetection. Autodetection was proven to silently fall back to a
 * Jackson/JSON serializer here because two Apicurio artifacts share the
 * {@code io.apicurio.registry.serde.avro} package (split-package), which
 * defeats it. The explicit key keeps events Avro on the wire.
 */
@ApplicationScoped
public class OrderEventProducer {

    private static final Logger LOG = Logger.getLogger(OrderEventProducer.class);

    @Inject
    @Channel("order-placed")
    Emitter<OrderPlaced> emitter;

    /**
     * Transactional observer: fires only after the transaction that
     * persisted {@code order} has committed successfully (JTA
     * {@code AFTER_SUCCESS} synchronization), so by the time this runs the
     * order is already durable. A publish failure here must never roll
     * back or otherwise affect the (already-committed) order -- it is
     * logged and swallowed, same as before this was moved out of the
     * caller's transaction.
     */
    void onOrderPlaced(@Observes(during = TransactionPhase.AFTER_SUCCESS) Order order) {
        publish(order).exceptionally(ex -> {
            LOG.warnf(ex, "failed to publish order.placed for %s", order.id);
            return null;
        });
    }

    public CompletionStage<Void> publish(Order order) {
        OrderPlaced event = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId(order.id)
                .setCustomerId(order.customerId)
                .setItemSku(order.itemSku)
                .setQuantity(order.quantity)
                .setAmount(order.amount.toPlainString())
                .setStatus(order.status.name())
                .setCreatedAt(DateTimeFormatter.ISO_INSTANT.format(order.createdAt))
                .build();

        // Plain-payload send (verified against org.eclipse.microprofile.reactive.messaging.Emitter's
        // `CompletionStage<Void> send(T)` overload -- the Message-accepting overload is void-returning
        // and not needed here). The Kafka record key defaults to none; unlike the Python producer this
        // does not key by order id, since ordering across partitions is not a requirement of this example.
        return emitter.send(event);
    }
}
