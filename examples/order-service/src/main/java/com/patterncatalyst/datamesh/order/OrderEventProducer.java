package com.patterncatalyst.datamesh.order;

import java.time.format.DateTimeFormatter;
import java.util.concurrent.CompletionStage;

import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;

import capstone.order.v1.OrderPlaced;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

/**
 * Publishes {@code order.placed} as Avro against the Apicurio Schema
 * Registry (DRQ-009) after an order has been durably persisted. Mirrors
 * {@code app/events.py::publish_order_placed} in the Python reference
 * architecture: publishing happens strictly after commit, and a publish
 * failure must never fail the already-committed order -- the caller
 * ({@link OrderResource}) treats this as best-effort and only logs on
 * failure. The dual-write gap this leaves is the outbox pattern's job in
 * production, not this example.
 *
 * <p>The outgoing channel ({@code order-placed}, mapped to the
 * {@code order.placed} Kafka topic in {@code application.properties}) uses
 * the Apicurio Avro serializer. Note: {@code value.serializer} is set
 * EXPLICITLY in {@code application.properties} rather than left to Quarkus
 * autodetection. Autodetection was proven to silently fall back to a
 * Jackson/JSON serializer here because two Apicurio artifacts share the
 * {@code io.apicurio.registry.serde.avro} package (split-package), which
 * defeats it. The explicit key keeps events Avro on the wire (DRQ-009).
 */
@ApplicationScoped
public class OrderEventProducer {

    @Inject
    @Channel("order-placed")
    Emitter<OrderPlaced> emitter;

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
