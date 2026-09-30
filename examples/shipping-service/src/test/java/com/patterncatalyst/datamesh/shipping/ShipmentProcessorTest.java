package com.patterncatalyst.datamesh.shipping;

import static org.awaitility.Awaitility.await;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.List;

import org.eclipse.microprofile.reactive.messaging.Message;
import org.eclipse.microprofile.reactive.messaging.spi.Connector;
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

    @Test
    void assignsTheSameCarrierAndTrackingNumberForTheSameOrder() {
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
        paymentsIn.send(PaymentCaptured.newBuilder(template).build());

        await().<List<? extends Message<ShipmentDispatched>>>until(shipmentsOut::received, received -> received.size() == 2);

        ShipmentDispatched first = shipmentsOut.received().get(0).getPayload();
        ShipmentDispatched second = shipmentsOut.received().get(1).getPayload();
        assertEquals(first.getCarrier(), second.getCarrier());
        assertEquals(first.getTrackingNumber(), second.getTrackingNumber());
        assertEquals(first.getItemSku(), second.getItemSku());
        assertEquals(first.getQuantity(), second.getQuantity());
    }
}
