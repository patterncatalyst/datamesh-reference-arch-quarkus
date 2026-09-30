package com.patterncatalyst.datamesh.notification;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.math.BigDecimal;

import org.junit.jupiter.api.Test;

import capstone.order.v1.OrderPlaced;
import io.quarkus.test.TestTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;

/**
 * Exercises {@link OrderPlacedConsumer#consume(OrderPlaced)} directly (as a
 * CDI bean method) rather than round-tripping through a live Kafka broker --
 * this keeps the test fast and dependency-free while still verifying the
 * Avro-record-to-Notification mapping and the idempotent-write behavior that
 * matter for at-least-once delivery. The Reactive Messaging wiring itself
 * (topic <-> channel <-> Avro deserializer) is declarative configuration in
 * application.properties, verified separately against a live Dev Services
 * broker.
 */
@QuarkusTest
class OrderPlacedConsumerTest {

    @Inject
    OrderPlacedConsumer consumer;

    @Test
    @TestTransaction
    void persistsNotificationFromOrderPlacedEvent() {
        OrderPlaced event = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId("order-1")
                .setCustomerId("customer-1")
                .setItemSku("sku-42")
                .setQuantity(3)
                .setAmount("19.99")
                .setStatus("PLACED")
                .setCreatedAt("2026-01-01T00:00:00Z")
                .build();

        consumer.consume(event);

        Notification saved = Notification.findByOrderId("order-1");
        assertNotNull(saved);
        assertEquals("order.placed", saved.eventType);
        assertEquals("customer-1", saved.customerId);
        assertEquals("sku-42", saved.itemSku);
        assertEquals(3, saved.quantity);
        assertEquals(0, new BigDecimal("19.99").compareTo(saved.amount));
        assertEquals("PLACED", saved.status);
        assertNotNull(saved.createdAt);
    }

    @Test
    @TestTransaction
    void redeliveryOfSameOrderIsIdempotent() {
        OrderPlaced event = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId("order-2")
                .setCustomerId("customer-2")
                .setItemSku("sku-7")
                .setQuantity(1)
                .setAmount("5.00")
                .setStatus("PLACED")
                .setCreatedAt("2026-01-01T00:00:00Z")
                .build();

        consumer.consume(event);
        consumer.consume(event);

        long count = Notification.count("orderId", "order-2");
        assertEquals(1, count);
    }
}
