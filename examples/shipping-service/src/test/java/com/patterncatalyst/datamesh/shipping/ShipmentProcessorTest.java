package com.patterncatalyst.datamesh.shipping;

import static org.awaitility.Awaitility.await;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.List;

import org.eclipse.microprofile.reactive.messaging.Message;
import org.eclipse.microprofile.reactive.messaging.spi.Connector;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import capstone.payment.v1.PaymentCaptured;
import capstone.shipping.v1.ShipmentDispatched;
import com.patterncatalyst.datamesh.domain.Topics;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import io.smallrye.reactive.messaging.memory.InMemoryConnector;
import io.smallrye.reactive.messaging.memory.InMemorySink;
import io.smallrye.reactive.messaging.memory.InMemorySource;
import jakarta.inject.Inject;

/**
 * Unit-tests {@link ShipmentProcessor}'s choreography step (consume
 * PaymentCaptured, produce ShipmentDispatched) against the in-memory
 * connector, per the Quarkus Kafka reference guide's "Testing without a
 * broker" pattern (verified via quarkus_searchDocs) -- no Kafka broker or
 * Apicurio Registry required.
 *
 * <p>NOT RUN as part of this build batch (write-only per the EXECUTE phase
 * instructions); intended to be run with {@code mvn test} once a JVM/Docker
 * environment is available (Postgres Dev Services still starts for the
 * optional {@link Shipment} persistence in {@link ShipmentProcessor#process}).
 */
@QuarkusTest
@QuarkusTestResource(InMemoryChannelsTestResource.class)
class ShipmentProcessorTest {

    @Inject
    @Connector("smallrye-in-memory")
    InMemoryConnector connector;

    /**
     * The in-memory sink accumulates every message received during the
     * @QuarkusTest instance's lifetime, so without clearing it between methods
     * one test sees the other's emissions (the size assertions below would see
     * 3 instead of the expected 1). Reset the outgoing sink before each test to
     * keep the two methods independent regardless of execution order.
     */
    @BeforeEach
    void clearShipmentSink() {
        connector.sink(Topics.SHIPMENT_DISPATCHED_CHANNEL).clear();
    }

    @Test
    void processesPaymentCapturedIntoShipmentDispatched() {
        InMemorySource<PaymentCaptured> paymentsIn = connector.source(Topics.PAYMENT_CAPTURED_CHANNEL);
        InMemorySink<ShipmentDispatched> shipmentsOut = connector.sink(Topics.SHIPMENT_DISPATCHED_CHANNEL);

        PaymentCaptured paymentCaptured = PaymentCaptured.newBuilder()
                .setEventType("payment.captured")
                .setOrderId("order-123")
                .setCustomerId("customer-456")
                .setAmount("42.00")
                .setStatus("captured")
                .setCreatedAt(Instant.now().toString())
                .build();

        paymentsIn.send(paymentCaptured);

        await().<List<? extends Message<ShipmentDispatched>>>until(shipmentsOut::received, received -> received.size() == 1);

        ShipmentDispatched dispatched = shipmentsOut.received().get(0).getPayload();
        assertEquals("shipment.dispatched", dispatched.getEventType());
        assertEquals("order-123", dispatched.getOrderId());
        assertEquals("customer-456", dispatched.getCustomerId());
        assertEquals("dispatched", dispatched.getStatus());
        assertFalse(dispatched.getCarrier().isBlank());
        assertFalse(dispatched.getTrackingNumber().isBlank());
        assertFalse(dispatched.getItemSku().isBlank());
        assertTrue(dispatched.getQuantity() >= 1 && dispatched.getQuantity() <= 5);
    }

    /**
     * At-least-once delivery means the same {@code PaymentCaptured} event can
     * be redelivered. A redelivery for an order that already has a {@link
     * Shipment} must not insert a second row -- {@link
     * ShipmentProcessor#process} looks the order up first and treats it as
     * already-dispatched (mirrors notification-service's
     * redelivery-is-idempotent guard). The redelivery may still re-emit a
     * dispatch (reactive-messaging processors always produce an outgoing
     * message per invocation), so this also asserts that redelivery's
     * carrier/tracking/sku/quantity are identical to the first, i.e. it
     * reflects the one persisted {@link Shipment}, not a freshly re-derived
     * one.
     */
    @Test
    void redeliveryOfSameOrderIsIdempotent() {
        InMemorySource<PaymentCaptured> paymentsIn = connector.source(Topics.PAYMENT_CAPTURED_CHANNEL);
        InMemorySink<ShipmentDispatched> shipmentsOut = connector.sink(Topics.SHIPMENT_DISPATCHED_CHANNEL);

        PaymentCaptured template = PaymentCaptured.newBuilder()
                .setEventType("payment.captured")
                .setOrderId("order-789")
                .setCustomerId("customer-000")
                .setAmount("10.00")
                .setStatus("captured")
                .setCreatedAt(Instant.now().toString())
                .build();

        paymentsIn.send(PaymentCaptured.newBuilder(template).build());

        await().<List<? extends Message<ShipmentDispatched>>>until(shipmentsOut::received, received -> received.size() == 1);

        paymentsIn.send(PaymentCaptured.newBuilder(template).build());

        // The redelivery is still processed and still re-emits a dispatch
        // (reactive-messaging processors always produce an outgoing message
        // per invocation); waiting for the second message is therefore a
        // reliable sync point for "the redelivery has been fully handled".
        await().<List<? extends Message<ShipmentDispatched>>>until(shipmentsOut::received, received -> received.size() == 2);

        // The core correctness property: the redelivery must not persist a
        // second Shipment row for the same order.
        assertEquals(1, Shipment.count("orderId", "order-789"));

        ShipmentDispatched first = shipmentsOut.received().get(0).getPayload();
        ShipmentDispatched second = shipmentsOut.received().get(1).getPayload();
        assertEquals(first.getCarrier(), second.getCarrier());
        assertEquals(first.getTrackingNumber(), second.getTrackingNumber());
        assertEquals(first.getItemSku(), second.getItemSku());
        assertEquals(first.getQuantity(), second.getQuantity());
    }
}
