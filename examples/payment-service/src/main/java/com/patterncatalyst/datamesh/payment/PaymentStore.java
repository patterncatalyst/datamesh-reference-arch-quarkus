package com.patterncatalyst.datamesh.payment;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import jakarta.enterprise.context.ApplicationScoped;

import capstone.payment.v1.PaymentCaptured;

/**
 * Minimal, real in-memory record of captured payments, keyed by the
 * generated payment id. This is bookkeeping only -- it is not a database and
 * is not the point of this module; the required, "real" part is
 * the Kafka/Avro choreography in {@link PaymentProcessor}. Kept deliberately
 * small: a thread-safe map, nothing more.
 *
 * <p>At-least-once delivery means the same {@code order.placed} event can be
 * redelivered; a second map keyed by order id lets {@link PaymentProcessor}
 * recognize a redelivery and avoid minting a second payment for the same
 * order (mirrors notification-service's {@code findByOrderId} redelivery
 * guard).
 */
@ApplicationScoped
public class PaymentStore {

    private final Map<String, PaymentCaptured> payments = new ConcurrentHashMap<>();
    private final Map<String, PaymentCaptured> paymentsByOrderId = new ConcurrentHashMap<>();

    public void record(String paymentId, PaymentCaptured payment) {
        payments.put(paymentId, payment);
        paymentsByOrderId.put(payment.getOrderId(), payment);
    }

    public PaymentCaptured find(String paymentId) {
        return payments.get(paymentId);
    }

    public PaymentCaptured findByOrderId(String orderId) {
        return paymentsByOrderId.get(orderId);
    }

    public int size() {
        return payments.size();
    }
}
