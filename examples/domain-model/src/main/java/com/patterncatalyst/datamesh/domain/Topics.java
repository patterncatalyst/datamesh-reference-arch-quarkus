package com.patterncatalyst.datamesh.domain;

/**
 * Single source of truth for Kafka topic names and Reactive Messaging
 * channel ids used across the reference architecture. Per DRQ-009, every
 * event on these topics is Avro-serialized against the Apicurio Schema
 * Registry from the start -- see the {@code contracts} module for the
 * {@code .avsc} schemas ({@code order-placed.avsc}, {@code
 * payment-captured.avsc}, {@code shipment-dispatched.avsc}).
 *
 * <p>Topic constants name the physical Kafka topic. Channel constants name
 * the logical Reactive Messaging channel that each service module wires to
 * a topic via {@code mp.messaging.[incoming|outgoing].<channel>.topic} in
 * its own {@code application.properties}.
 */
public final class Topics {

    // Kafka topics
    public static final String ORDER_PLACED_TOPIC = "order.placed";
    public static final String PAYMENT_CAPTURED_TOPIC = "payment.captured";
    public static final String SHIPMENT_DISPATCHED_TOPIC = "shipment.dispatched";

    // Reactive Messaging channel ids
    public static final String ORDER_PLACED_CHANNEL = "order-placed";
    public static final String PAYMENT_CAPTURED_CHANNEL = "payment-captured";
    public static final String SHIPMENT_DISPATCHED_CHANNEL = "shipment-dispatched";

    private Topics() {
    }
}
