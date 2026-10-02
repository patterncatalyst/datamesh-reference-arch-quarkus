package com.patterncatalyst.datamesh.springcompare;

import java.time.format.DateTimeFormatter;
import java.util.concurrent.CompletableFuture;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import com.patterncatalyst.datamesh.domain.Topics;

import capstone.order.v1.OrderPlaced;

/**
 * Publishes {@code order.placed} as Avro against the Apicurio Schema
 * Registry after an order has been durably persisted. Mirrors
 * {@code OrderEventProducer} in the Quarkus order-service: publishing
 * happens strictly after commit, and a publish failure must never fail the
 * already-committed order -- this class treats it as best-effort and only
 * logs on failure. The dual-write gap this leaves is the outbox pattern's
 * job in production, not this example.
 *
 * <p>"Strictly after commit" is enforced, not just ordered-by-convention:
 * {@link OrderController#placeOrder} publishes an {@code ApplicationEvent}
 * (the raw {@link OrderEntity}) right after {@code orderRepository.save(...)},
 * and {@link #onOrderPlaced} below is a
 * {@code @TransactionalEventListener(phase = AFTER_COMMIT)}, which Spring
 * only invokes once the surrounding {@code @Transactional} method's
 * transaction has actually committed. Only that listener calls
 * {@link #publish}; nothing calls it from inside the transaction.
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

    /**
     * Transactional listener: invoked only after the transaction that
     * persisted {@code order} has committed successfully (Spring's
     * {@code AFTER_COMMIT} phase), so by the time this runs the order is
     * already durable. A publish failure here must never roll back or
     * otherwise affect the (already-committed) order -- it is logged and
     * swallowed by {@link #publish}, same as before this was moved out of
     * the caller's transaction.
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderPlaced(OrderEntity order) {
        publish(order);
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
