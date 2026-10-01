package com.patterncatalyst.datamesh.notification;

import java.math.BigDecimal;
import java.time.Instant;

import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.jboss.logging.Logger;

import capstone.order.v1.OrderPlaced;
import io.quarkus.websockets.next.OpenConnections;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
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
 */
@ApplicationScoped
public class OrderPlacedConsumer {

    private static final Logger LOG = Logger.getLogger(OrderPlacedConsumer.class);

    // NEW for demos/demo-websocket.sh (Phase D step 10.6, "WebSockets.Next"):
    // every open /ws/notifications connection (see OrderNotificationSocket)
    // gets the freshly persisted Notification pushed to it as soon as this
    // consumer commits it -- a real, event-driven push, not a poll.
    @Inject
    OpenConnections wsConnections;

    @Incoming("order-placed")
    @Transactional
    public void consume(OrderPlaced event) {
        String orderId = event.getOrderId();
        if (Notification.findByOrderId(orderId) != null) {
            LOG.infof("skipping duplicate delivery for order %s", orderId);
            return;
        }

        Notification notification = new Notification();
        notification.orderId = orderId;
        notification.eventType = event.getEventType();
        notification.customerId = event.getCustomerId();
        notification.itemSku = event.getItemSku();
        notification.quantity = event.getQuantity();
        notification.amount = parseAmount(event.getAmount());
        notification.status = event.getStatus();
        notification.createdAt = parseCreatedAt(event.getCreatedAt());
        notification.persist();

        LOG.infof("persisted notification for order %s (%s)", orderId, event.getEventType());

        // Push to every open WebSocket client -- see OrderNotificationSocket.
        // WebSockets.Next serializes the Notification entity to JSON the
        // same way the REST layer does (Jackson). Best-effort like the rest
        // of this consumer's side effects: a client that isn't listening
        // right now simply misses this push (no retry/queue), which is the
        // expected semantics for a live notification feed.
        wsConnections.listAll().forEach(connection -> connection.sendTextAndAwait(notification));
    }

    private static BigDecimal parseAmount(String amount) {
        return amount == null ? null : new BigDecimal(amount);
    }

    private static Instant parseCreatedAt(String createdAt) {
        return createdAt == null ? Instant.now() : Instant.parse(createdAt);
    }
}
