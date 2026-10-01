package com.patterncatalyst.datamesh.springcompare;

import java.time.format.DateTimeFormatter;
import java.util.concurrent.CompletableFuture;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Component;

import com.patterncatalyst.datamesh.domain.Topics;

import capstone.order.v1.OrderPlaced;

/**
 * Publishes {@code order.placed} as Avro against the Apicurio Schema
 * Registry (DRQ-009) after an order has been durably persisted. Mirrors
 * {@code OrderEventProducer} in the Quarkus order-service: publishing
 * happens strictly after commit, and a publish failure must never fail the
 * already-committed order -- {@link OrderController} treats this as
 * best-effort and only logs on failure. The dual-write gap this leaves is
 * the outbox pattern's job in production, not this example.
 *
 * <p>The topic name comes from {@link Topics#ORDER_PLACED_TOPIC} (the same
 * shared constant the Quarkus side's channel-to-topic mapping resolves to),
 * and the value serializer is set explicitly in {@code application.properties}
 * to Apicurio's Avro serializer -- autodetection is not a concern on the
 * Spring side (there is exactly one Avro serde on this classpath), but the
 * explicit key is kept for parity/documentation with the Quarkus side's
 * split-package workaround.
 */
@Component
public class OrderEventProducer {

    private static final Logger LOG = LoggerFactory.getLogger(OrderEventProducer.class);

    private final KafkaTemplate<String, OrderPlaced> kafkaTemplate;

    public OrderEventProducer(KafkaTemplate<String, OrderPlaced> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public CompletableFuture<SendResult<String, OrderPlaced>> publish(OrderEntity order) {
        OrderPlaced event = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId(order.getId())
                .setCustomerId(order.getCustomerId())
                .setItemSku(order.getItemSku())
                .setQuantity(order.getQuantity())
                .setAmount(order.getAmount().toPlainString())
                .setStatus(order.getStatus().name())
                .setCreatedAt(DateTimeFormatter.ISO_INSTANT.format(order.getCreatedAt()))
                .build();

        // No explicit key, same as the Quarkus side: ordering across
        // partitions is not a requirement of this example.
        return kafkaTemplate.send(Topics.ORDER_PLACED_TOPIC, event)
                .exceptionally(ex -> {
                    LOG.warn("failed to publish order.placed for {}", order.getId(), ex);
                    return null;
                });
    }
}
