package com.patterncatalyst.datamesh.shipping;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.eclipse.microprofile.reactive.messaging.Outgoing;

import capstone.payment.v1.PaymentCaptured;
import capstone.shipping.v1.ShipmentDispatched;
import com.patterncatalyst.datamesh.domain.Topics;
import io.smallrye.common.annotation.Blocking;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;

/**
 * Real event-choreography saga participant (DRQ-009 / DRQ-010): continues the
 * order.placed -&gt; payment.captured -&gt; shipment.dispatched saga.
 *
 * <p>Consumes {@link PaymentCaptured} (Avro, {@code capstone.payment.v1}) from
 * the {@code payment.captured} topic, creates a shipment -- carrier and
 * tracking number are derived deterministically from the order id, so the
 * same order always dispatches identically, which keeps demos and tests
 * reproducible without a random-number source -- persists a minimal local
 * record of it, and emits {@link ShipmentDispatched} (Avro,
 * {@code capstone.shipping.v1}) on the {@code shipment.dispatched} topic.
 *
 * <p>{@code PaymentCaptured} does not carry line-item detail (sku/quantity);
 * a real system would enrich this step via an order-details lookup or carry
 * those fields through the saga end-to-end. Here they are derived
 * deterministically from the order id as well, which is sufficient for the
 * reference architecture without pulling in a cross-service query just for
 * this example.
 */
@ApplicationScoped
public class ShipmentProcessor {

    private static final List<String> CARRIERS = List.of("UPS", "FedEx", "DHL", "USPS");
    private static final List<String> SKUS = List.of("SKU-WIDGET", "SKU-GADGET", "SKU-GIZMO", "SKU-DOOHICKEY");
    private static final String DISPATCHED_STATUS = "dispatched";

    @Incoming(Topics.PAYMENT_CAPTURED_CHANNEL)
    @Outgoing(Topics.SHIPMENT_DISPATCHED_CHANNEL)
    @Blocking
    @Transactional
    public ShipmentDispatched process(PaymentCaptured paymentCaptured) {
        String orderId = paymentCaptured.getOrderId();
        String customerId = paymentCaptured.getCustomerId();
        String carrier = pick(CARRIERS, orderId, 0);
        String itemSku = pick(SKUS, orderId, 1);
        int quantity = Math.floorMod(hash(orderId, 2), 5) + 1;
        String trackingNumber = trackingNumberFor(orderId, carrier);
        Instant dispatchedAt = Instant.now();

        Shipment shipment = new Shipment();
        shipment.orderId = orderId;
        shipment.customerId = customerId;
        shipment.itemSku = itemSku;
        shipment.quantity = quantity;
        shipment.carrier = carrier;
        shipment.trackingNumber = trackingNumber;
        shipment.status = DISPATCHED_STATUS;
        shipment.dispatchedAt = dispatchedAt;
        shipment.persist();

        return ShipmentDispatched.newBuilder()
                .setEventType("shipment.dispatched")
                .setOrderId(orderId)
                .setCustomerId(customerId)
                .setItemSku(itemSku)
                .setQuantity(quantity)
                .setCarrier(carrier)
                .setTrackingNumber(trackingNumber)
                .setStatus(DISPATCHED_STATUS)
                .setCreatedAt(dispatchedAt.toString())
                .build();
    }

    /** Deterministically picks one of {@code options} based on {@code orderId} + {@code salt}. */
    private static String pick(List<String> options, String orderId, int salt) {
        return options.get(Math.floorMod(hash(orderId, salt), options.size()));
    }

    private static int hash(String orderId, int salt) {
        return (orderId + ":" + salt).hashCode();
    }

    /** Deterministic, carrier-prefixed pseudo-tracking number derived from the order id. */
    private static String trackingNumberFor(String orderId, String carrier) {
        String digest = UUID.nameUUIDFromBytes((carrier + ":" + orderId).getBytes(StandardCharsets.UTF_8))
                .toString()
                .replace("-", "")
                .toUpperCase();
        return carrier.substring(0, Math.min(2, carrier.length())).toUpperCase() + digest.substring(0, 12);
    }
}
