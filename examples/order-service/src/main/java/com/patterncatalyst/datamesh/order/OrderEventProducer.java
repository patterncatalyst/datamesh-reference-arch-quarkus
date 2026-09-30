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
 * the Apicurio Avro serializer, auto-detected by Quarkus from the
 * {@code @Channel} declaration's {@code OrderPlaced} (Avro
 * {@code SpecificRecord}) type plus the presence of
 * {@code quarkus-apicurio-registry-avro} -- no explicit
 * {@code value.serializer} property is required.
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
