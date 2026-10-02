package com.patterncatalyst.datamesh.order;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
import org.apache.kafka.common.serialization.ByteArrayDeserializer;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.kafka.KafkaContainer;
import org.testcontainers.utility.DockerImageName;

import capstone.order.v1.OrderPlaced;
import io.apicurio.registry.resolver.config.SchemaResolverConfig;
import io.apicurio.registry.serde.avro.AvroKafkaDeserializer;
import io.apicurio.registry.serde.avro.AvroKafkaSerializer;
import io.apicurio.registry.serde.avro.AvroSerdeConfig;

/**
 * Byte-level proof that {@code order.placed} is Avro on
 * the wire, not JSON. Self-provisions its own Kafka + Apicurio Registry
 * Testcontainers (pinned to the exact tags step 8a validated in
 * {@code infra/README.md} / {@code compose.yaml} -- {@code apache/kafka-native:4.2.0}
 * and {@code quay.io/apicurio/apicurio-registry:3.1.7} -- so the broker and
 * registry behavior this test exercises matches both Quarkus Dev Services
 * and the standalone compose stack, matching the wire-compat requirement).
 *
 * <p>Unlike {@link OrderResourceTest} (a {@code @QuarkusTest} that relies on
 * Dev Services and the application's own Reactive Messaging wiring), this
 * test drives a raw {@link KafkaProducer}/{@link KafkaConsumer} pair
 * directly: it produces one real {@code capstone.order.v1.OrderPlaced}
 * record through the same {@code io.apicurio.registry.serde.avro.AvroKafkaSerializer}
 * the application uses (see {@code application.properties}'s
 * {@code mp.messaging.outgoing.order-placed.value.serializer}), then reads
 * the raw bytes back with a vanilla {@code KafkaConsumer<byte[], byte[]>}
 * that has NO Avro deserializer configured. If the producer-side serde ever
 * regresses to Quarkus's autodetected Jackson/JSON fallback (the exact
 * split-package failure mode documented in {@link OrderEventProducer}'s
 * class-level Javadoc), the byte assertions below fail loudly
 * instead of silently accepting JSON.
 *
 * <p>Hermetic: does NOT require {@code docker compose up} / the standing
 * infra stack. Both containers are started and torn down per test-class
 * run by Testcontainers/Ryuk.
 */
@Testcontainers
class OrderPlacedAvroWireIT {

    private static final String TOPIC = "order.placed";

    @Container
    static KafkaContainer kafka = new KafkaContainer("apache/kafka-native:4.2.0");

    @Container
    static GenericContainer<?> apicurio = new GenericContainer<>(
            DockerImageName.parse("quay.io/apicurio/apicurio-registry:3.1.7"))
            .withExposedPorts(8080)
            // infra/README.md ("Apicurio Registry storage"): 3.1.7 removed the
            // plain in-memory "mem" storage kind used by older 3.0.x images
            // (IllegalStateException: No Registry storage variant defined for
            // value mem, confirmed by step 8a actually running the pinned
            // image). sql/h2 is the ephemeral-equivalent replacement and is
            // exactly what compose.yaml's apicurio service uses.
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
                .setOrderId("order-avro-wire-it-1")
                .setCustomerId("cust-avro-wire-it")
                .setItemSku("sku-avro-wire-it")
                .setQuantity(3)
                .setAmount("42.50")
                .setStatus("PLACED")
                .setCreatedAt(DateTimeFormatter.ISO_INSTANT.format(Instant.now()))
                .build();
    }

    @Test
    void orderPlaced_isAvroOnTheWire_notJson() throws Exception {
        OrderPlaced produced = sampleOrderPlaced();

        // --- Produce with the SAME serializer the application uses ---
        Properties producerProps = new Properties();
        producerProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers());
        producerProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        producerProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, AvroKafkaSerializer.class.getName());
        producerProps.put(SchemaResolverConfig.REGISTRY_URL, apicurioRegistryUrl());
        producerProps.put(SchemaResolverConfig.AUTO_REGISTER_ARTIFACT, "true");

        try (KafkaProducer<String, OrderPlaced> producer = new KafkaProducer<>(producerProps)) {
            producer.send(new ProducerRecord<>(TOPIC, produced.getOrderId().toString(), produced))
                    .get(30, TimeUnit.SECONDS);
            producer.flush();
        }

        // --- Consume with a VANILLA byte[] consumer: no Avro deserializer at all ---
        Properties rawConsumerProps = new Properties();
        rawConsumerProps.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers());
        rawConsumerProps.put(ConsumerConfig.GROUP_ID_CONFIG, "avro-wire-it-raw");
        rawConsumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        rawConsumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        rawConsumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());

        byte[] rawValue;
        try (KafkaConsumer<byte[], byte[]> rawConsumer = new KafkaConsumer<>(rawConsumerProps)) {
            rawConsumer.subscribe(Collections.singletonList(TOPIC));
            ConsumerRecord<byte[], byte[]> record = pollForOneRecord(rawConsumer);
            rawValue = record.value();
        }

        // --- Byte-level assertions: Avro magic byte + schema id, and explicitly NOT JSON ---
        assertTrue(rawValue.length > 5,
                "record value too short to carry an Apicurio/Confluent Avro schema id: " + rawValue.length + " bytes");
        assertEquals((byte) 0x0, rawValue[0],
                "expected Apicurio/Confluent Avro wire-format magic byte 0x0 as the first byte");
        assertTrue(rawValue[0] != 0x7B,
                "record value starts with '{' (0x7B) -- serde has regressed to JSON (Avro wire format expected)");

        // --- Optional round-trip: deserialize with AvroKafkaDeserializer and
        //     confirm the fields survive the real Avro wire encoding. ---
        Properties avroConsumerProps = new Properties();
        avroConsumerProps.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers());
        avroConsumerProps.put(ConsumerConfig.GROUP_ID_CONFIG, "avro-wire-it-typed");
        avroConsumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        avroConsumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        avroConsumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, AvroKafkaDeserializer.class.getName());
        avroConsumerProps.put(SchemaResolverConfig.REGISTRY_URL, apicurioRegistryUrl());
        avroConsumerProps.put(AvroSerdeConfig.USE_SPECIFIC_AVRO_READER, "true");

        try (KafkaConsumer<String, OrderPlaced> avroConsumer = new KafkaConsumer<>(avroConsumerProps)) {
            avroConsumer.subscribe(Collections.singletonList(TOPIC));
            ConsumerRecord<String, OrderPlaced> record = pollForOneRecord(avroConsumer);
            OrderPlaced roundTripped = record.value();

            assertNotNull(roundTripped);
            assertEquals(produced.getOrderId(), roundTripped.getOrderId());
            assertEquals(produced.getCustomerId(), roundTripped.getCustomerId());
            assertEquals(produced.getItemSku(), roundTripped.getItemSku());
            assertEquals(produced.getQuantity(), roundTripped.getQuantity());
            assertEquals(produced.getAmount(), roundTripped.getAmount());
            assertEquals(produced.getStatus(), roundTripped.getStatus());
            assertEquals(produced.getCreatedAt(), roundTripped.getCreatedAt());
        }
    }

    private static <K, V> ConsumerRecord<K, V> pollForOneRecord(KafkaConsumer<K, V> consumer) {
        long deadline = System.currentTimeMillis() + Duration.ofSeconds(30).toMillis();
        while (System.currentTimeMillis() < deadline) {
            ConsumerRecords<K, V> records = consumer.poll(Duration.ofMillis(500));
            if (!records.isEmpty()) {
                return records.iterator().next();
            }
        }
        throw new AssertionError("no record received on topic " + TOPIC + " within the poll deadline");
    }
}
