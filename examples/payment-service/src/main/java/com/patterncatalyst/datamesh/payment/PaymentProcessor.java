package com.patterncatalyst.datamesh.payment;

import java.time.Instant;
import java.util.UUID;

import jakarta.enterprise.context.ApplicationScoped;

import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.eclipse.microprofile.reactive.messaging.Outgoing;
import org.jboss.logging.Logger;

import com.patterncatalyst.datamesh.domain.Topics;

import capstone.order.v1.OrderPlaced;
import capstone.payment.v1.PaymentCaptured;

/**
 * Real event-driven choreography processor.
 *
 * <p>Consumes {@link OrderPlaced} Avro events from the {@code order.placed}
 * Kafka topic (wired via the {@link Topics#ORDER_PLACED_CHANNEL} Reactive
 * Messaging channel) and, for every placed order, captures a payment and
 * publishes a {@link PaymentCaptured} Avro event to the {@code
 * payment.captured} Kafka topic (via {@link Topics#PAYMENT_CAPTURED_CHANNEL}).
 * Both channels are Avro-serialized against the Apicurio Schema Registry --
 * see {@code application.properties} for the {@code mp.messaging.*} wiring
 * and {@code README.md} for the verified Apicurio serde keys.
 *
 * <p>Capture logic is deliberately simple and deterministic for this
 * reference example: every order is captured immediately with a freshly
 * generated payment id, mirroring the order's amount and customer. A real
 * payment service would call out to a payment gateway and could fail/decline
 * a capture; that branching is out of scope for this capstone slice.
 *
 * <p>At-least-once delivery means the same {@code OrderPlaced} event can be
 * redelivered; capture is idempotent on the order id -- a redelivery returns
 * the payment already captured for that order instead of minting a second
 * one (mirrors notification-service's {@code OrderPlacedConsumer} redelivery
 * guard).
 */
@ApplicationScoped
public class PaymentProcessor {

    private static final Logger LOG = Logger.getLogger(PaymentProcessor.class);

    private static final String PAYMENT_CAPTURED_EVENT_TYPE = "payment.captured";
    private static final String CAPTURED_STATUS = "CAPTURED";

    private final PaymentStore paymentStore;

    public PaymentProcessor(PaymentStore paymentStore) {
        this.paymentStore = paymentStore;
    }

    @Incoming(Topics.ORDER_PLACED_CHANNEL)
    @Outgoing(Topics.PAYMENT_CAPTURED_CHANNEL)
    public PaymentCaptured process(OrderPlaced orderPlaced) {
        String orderId = orderPlaced.getOrderId();

        PaymentCaptured existing = paymentStore.findByOrderId(orderId);
        if (existing != null) {
            LOG.infof("skipping duplicate delivery for order %s (already captured)", orderId);
            return existing;
        }

        String paymentId = "pay-" + UUID.randomUUID();

        LOG.infof("Capturing payment %s for order %s (customer=%s, amount=%s)",
                paymentId, orderId, orderPlaced.getCustomerId(), orderPlaced.getAmount());

        PaymentCaptured captured = PaymentCaptured.newBuilder()
                .setEventType(PAYMENT_CAPTURED_EVENT_TYPE)
                .setOrderId(orderId)
                .setCustomerId(orderPlaced.getCustomerId())
                .setAmount(orderPlaced.getAmount())
                .setStatus(CAPTURED_STATUS)
                .setCreatedAt(Instant.now().toString())
                .build();

        paymentStore.record(paymentId, captured);

        return captured;
    }
}
