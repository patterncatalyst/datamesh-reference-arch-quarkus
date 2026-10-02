package com.patterncatalyst.datamesh.notification;

import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.jboss.logging.Logger;

import capstone.order.v1.OrderPlaced;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;

/**
 * Consumes Avro-encoded {@code OrderPlaced} events (contracts module,
 * package {@code capstone.order.v1}) from the {@code order.placed} Kafka
 * topic via the {@code order-placed} Reactive Messaging channel (see
 * {@code application.properties}) and persists each one as a
 * {@link Notification} row.
 *
 * <p>{@code @Transactional} makes this method blocking automatically (per
 * SmallRye Reactive Messaging), so no separate {@code @Blocking} annotation
 * is needed for the Hibernate ORM / Panache write.
 *
 * <p>At-least-once delivery means the same order can be redelivered; the
 * write is idempotent -- if a {@link Notification} already exists for the
 * order id, the redelivery is a no-op (mirrors the Python reference's
 * {@code ON CONFLICT DO NOTHING} behavior).
 *
 * <p>This consumer is persistence-only. The {@code order-placed} channel
 * uses the shared, partition-balanced {@code notification-service} consumer
 * group (defaulted from {@code quarkus.application.name}), so across a
 * replica set exactly one replica persists any given event -- correct for
 * "write each order exactly once," but it means only that one replica would
 * ever observe the event if this class also drove the WebSocket push. The
 * push instead lives in {@link OrderPlacedPushConsumer}, a second,
 * independent consumer of the SAME {@code order.placed} topic via a second
 * channel ({@code order-placed-push}) bound to a per-replica UNIQUE
 * consumer group, so every replica receives every event and can push to its
 * own locally-connected {@link OrderNotificationSocket} clients. See
 * {@code _docs/16-websocket-scaling.md} for the full rationale.
 */
@ApplicationScoped
public class OrderPlacedConsumer {

    private static final Logger LOG = Logger.getLogger(OrderPlacedConsumer.class);

    @Incoming("order-placed")
    @Transactional
    public void consume(OrderPlaced event) {
        String orderId = event.getOrderId();
        if (Notification.findByOrderId(orderId) != null) {
            LOG.infof("skipping duplicate delivery for order %s", orderId);
            return;
        }

        Notification notification = Notification.from(event);
        notification.persist();

        LOG.infof("persisted notification for order %s (%s)", orderId, event.getEventType());
    }
}
