package com.patterncatalyst.datamesh.order;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.Collections;
import java.util.Properties;
import java.util.concurrent.TimeUnit;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.kafka.KafkaContainer;
import org.testcontainers.utility.DockerImageName;

import capstone.order.v1.OrderPlaced;
import capstone.payment.v1.PaymentCaptured;
import capstone.shipping.v1.ShipmentDispatched;
import com.patterncatalyst.datamesh.domain.Topics;
import io.apicurio.registry.resolver.config.SchemaResolverConfig;
import io.apicurio.registry.serde.avro.AvroKafkaDeserializer;
import io.apicurio.registry.serde.avro.AvroKafkaSerializer;
import io.apicurio.registry.serde.avro.AvroSerdeConfig;

/**
 * Intended to prove the full {@code order.placed -> payment.captured ->
 * shipment.dispatched} choreography chain (DRQ-010): produce one real
 * {@code order.placed} Avro event against a self-provisioned Kafka +
 * Apicurio Registry (cloning {@link OrderPlacedAvroWireIT}'s Testcontainers
 * pattern), then assert a {@code PaymentCaptured} record appears on {@code
 * payment.captured}, followed by a {@code ShipmentDispatched} record on
 * {@code shipment.dispatched}.
 *
 * <p><b>Disabled -- cannot actually exercise the chain from this module.</b>
 * Unlike {@link OrderPlacedAvroWireIT} (which only has to prove order-service's
 * OWN producer is Avro-on-the-wire against a broker it fully controls), this
 * IT needs {@code payment-service}'s {@code PaymentProcessor} and {@code
 * shipping-service}'s {@code ShipmentProcessor} -- two OTHER Maven modules'
 * Reactive Messaging consumers -- to actually be running and
 * consuming/producing against this same broker. Neither service has a
 * container image or any other
 * already-built, independently-launchable artifact in this reactor (no
 * Dockerfile/Containerfile, no {@code quarkus-container-image-*} extension
 * configured for either module; confirmed by searching the reactor), and
 * standing one up here would mean either (a) building and running a
 * Testcontainers {@code GenericContainer} from an image this task has no
 * way to produce without a container build, or (b) starting
 * payment-service/shipping-service via {@code docker compose}, which this
 * EXECUTE task is explicitly scoped NOT to run. Forcing the chain by having
 * THIS test itself reimplement PaymentProcessor/ShipmentProcessor's logic
 * with raw Kafka clients would be circular -- it would only prove this
 * test's own stand-in logic, not the real services' choreography.
 *
 * <p>The test body below is left fully written and compiling (produce +
 * poll, Avro serde wiring identical to {@link OrderPlacedAvroWireIT}) so
 * that re-enabling it is a one-line change ({@code @Disabled} removal) once
 * payment-service and shipping-service have a real way to run standalone in
 * CI (e.g. packaged container images wired into a future Testcontainers
 * Compose-based harness) -- see the EXECUTE task note that this one "will
 * run in the consolidated verify" once that harness exists.
 */
@Testcontainers
@Disabled("Needs real payment-service/shipping-service processes consuming/producing on this broker; "
        + "neither module has a container image or other launchable artifact in this reactor, and "
        + "standing them up via docker compose is out of scope for this task -- see class Javadoc")
class OrderChoreographyChainIT {

    @Container
    static KafkaContainer kafka = new KafkaContainer("apache/kafka-native:4.2.0");

    @Container
    static GenericContainer<?> apicurio = new GenericContainer<>(
            DockerImageName.parse("quay.io/apicurio/apicurio-registry:3.1.7"))
            .withExposedPorts(8080)
            .withEnv("APICURIO_STORAGE_KIND", "sql")
            .withEnv("APICURIO_STORAGE_SQL_KIND", "h2")
            .waitingFor(Wait.forHttp("/apis/registry/v3/system/info")
                    .forStatusCode(200)
                    .withStartupTimeout(Duration.ofSeconds(120)));

    private static String apicurioRegistryUrl() {
        return "http://" + apicurio.getHost() + ":" + apicurio.getMappedPort(8080) + "/apis/registry/v3";
    }

    private static OrderPlaced sampleOrderPlaced() {
        return OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId("order-choreography-it-1")
                .setCustomerId("cust-choreography-it")
                .setItemSku("sku-choreography-it")
                .setQuantity(1)
                .setAmount("15.00")
                .setStatus("PLACED")
                .setCreatedAt(DateTimeFormatter.ISO_INSTANT.format(Instant.now()))
                .build();
    }

    @Test
    void orderPlaced_choreographsThroughPaymentAndShipment() throws Exception {
        OrderPlaced produced = sampleOrderPlaced();

        Properties producerProps = new Properties();
        producerProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers());
        producerProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        producerProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, AvroKafkaSerializer.class.getName());
        producerProps.put(SchemaResolverConfig.REGISTRY_URL, apicurioRegistryUrl());
        producerProps.put(SchemaResolverConfig.AUTO_REGISTER_ARTIFACT, "true");

        try (KafkaProducer<String, OrderPlaced> producer = new KafkaProducer<>(producerProps)) {
            producer.send(new ProducerRecord<>(Topics.ORDER_PLACED_TOPIC, produced.getOrderId().toString(), produced))
                    .get(30, TimeUnit.SECONDS);
            producer.flush();
        }

        PaymentCaptured captured = pollTypedRecord(Topics.PAYMENT_CAPTURED_TOPIC, PaymentCaptured.class).value();
        assertNotNull(captured);
        assertEquals(produced.getOrderId(), captured.getOrderId());

        ShipmentDispatched dispatched = pollTypedRecord(Topics.SHIPMENT_DISPATCHED_TOPIC, ShipmentDispatched.class).value();
        assertNotNull(dispatched);
        assertEquals(produced.getOrderId(), dispatched.getOrderId());
    }

    private static <V> ConsumerRecord<String, V> pollTypedRecord(String topic, Class<V> valueType) {
        Properties consumerProps = new Properties();
        consumerProps.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers());
        consumerProps.put(ConsumerConfig.GROUP_ID_CONFIG, "choreography-it-" + topic);
        consumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        consumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        consumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, AvroKafkaDeserializer.class.getName());
        consumerProps.put(SchemaResolverConfig.REGISTRY_URL, apicurioRegistryUrl());
        consumerProps.put(AvroSerdeConfig.USE_SPECIFIC_AVRO_READER, "true");

        try (KafkaConsumer<String, V> consumer = new KafkaConsumer<>(consumerProps)) {
            consumer.subscribe(Collections.singletonList(topic));
            long deadline = System.currentTimeMillis() + Duration.ofSeconds(30).toMillis();
            while (System.currentTimeMillis() < deadline) {
                ConsumerRecords<String, V> records = consumer.poll(Duration.ofMillis(500));
                if (!records.isEmpty()) {
                    return records.iterator().next();
                }
            }
            throw new AssertionError("no record received on topic " + topic + " within the poll deadline");
        }
    }
}
