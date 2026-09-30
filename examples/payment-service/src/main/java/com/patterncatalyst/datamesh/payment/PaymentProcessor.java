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
 * Real event-driven choreography processor (DRQ-009, DRQ-010).
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
        String paymentId = "pay-" + UUID.randomUUID();

        LOG.infof("Capturing payment %s for order %s (customer=%s, amount=%s)",
                paymentId, orderPlaced.getOrderId(), orderPlaced.getCustomerId(), orderPlaced.getAmount());

        PaymentCaptured captured = PaymentCaptured.newBuilder()
                .setEventType(PAYMENT_CAPTURED_EVENT_TYPE)
                .setOrderId(orderPlaced.getOrderId())
                .setCustomerId(orderPlaced.getCustomerId())
                .setAmount(orderPlaced.getAmount())
                .setStatus(CAPTURED_STATUS)
                .setCreatedAt(Instant.now().toString())
                .build();

        paymentStore.record(paymentId, captured);

        return captured;
    }
}
