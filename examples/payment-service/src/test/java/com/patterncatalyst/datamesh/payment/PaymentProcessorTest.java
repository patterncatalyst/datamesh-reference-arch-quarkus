package com.patterncatalyst.datamesh.payment;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import jakarta.inject.Inject;

import org.junit.jupiter.api.Test;

import capstone.order.v1.OrderPlaced;
import capstone.payment.v1.PaymentCaptured;

import io.quarkus.test.junit.QuarkusTest;

/**
 * Written but NOT run as part of this build batch (see build-plan.md).
 *
 * <p>Exercises the {@link PaymentProcessor#process(OrderPlaced)} choreography
 * transform directly: given an {@code OrderPlaced} Avro record, it must
 * produce a {@code PaymentCaptured} Avro record that carries the same order
 * id, customer id, and amount, with a {@code CAPTURED} status. The CDI bean
 * is invoked as a plain method call rather than routed through the Kafka +
 * Apicurio wiring, which Quarkus Dev Services stand up end-to-end whenever
 * this module is actually run (`quarkus:dev` / `quarkus:test` / integration
 * tests), independently of this fast, broker-free unit test.
 */
@QuarkusTest
public class PaymentProcessorTest {

    @Inject
    PaymentProcessor paymentProcessor;

    @Inject
    PaymentStore paymentStore;

    @Test
    public void capturesPaymentForPlacedOrder() {
        OrderPlaced orderPlaced = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId("order-123")
                .setCustomerId("customer-456")
                .setItemSku("sku-789")
                .setQuantity(2)
                .setAmount("49.98")
                .setStatus("PLACED")
                .setCreatedAt("2026-09-30T00:00:00Z")
                .build();

        PaymentCaptured captured = paymentProcessor.process(orderPlaced);

        assertNotNull(captured);
        assertEquals("payment.captured", captured.getEventType());
        assertEquals("order-123", captured.getOrderId());
        assertEquals("customer-456", captured.getCustomerId());
        assertEquals("49.98", captured.getAmount());
        assertEquals("CAPTURED", captured.getStatus());
        assertNotNull(captured.getCreatedAt());
    }

    @Test
    public void recordsCapturedPaymentInTheStore() {
        int before = paymentStore.size();

        OrderPlaced orderPlaced = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId("order-999")
                .setCustomerId("customer-111")
                .setItemSku("sku-222")
                .setQuantity(1)
                .setAmount("10.00")
                .setStatus("PLACED")
                .setCreatedAt("2026-09-30T00:00:00Z")
                .build();

        paymentProcessor.process(orderPlaced);

        assertEquals(before + 1, paymentStore.size());
    }
}
