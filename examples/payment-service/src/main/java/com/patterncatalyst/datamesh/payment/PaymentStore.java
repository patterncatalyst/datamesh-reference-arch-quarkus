package com.patterncatalyst.datamesh.payment;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import jakarta.enterprise.context.ApplicationScoped;

import capstone.payment.v1.PaymentCaptured;

/**
 * Minimal, real in-memory record of captured payments, keyed by the
 * generated payment id. This is bookkeeping only -- it is not a database and
 * is not the point of this module; the required, "real" part of DRQ-010 is
 * the Kafka/Avro choreography in {@link PaymentProcessor}. Kept deliberately
 * small: a thread-safe map, nothing more.
 */
@ApplicationScoped
public class PaymentStore {

    private final Map<String, PaymentCaptured> payments = new ConcurrentHashMap<>();

    public void record(String paymentId, PaymentCaptured payment) {
        payments.put(paymentId, payment);
    }

    public PaymentCaptured find(String paymentId) {
        return payments.get(paymentId);
    }

    public int size() {
        return payments.size();
    }
}
