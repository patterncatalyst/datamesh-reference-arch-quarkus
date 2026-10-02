package com.patterncatalyst.datamesh.notification;

import java.math.BigDecimal;
import java.time.Instant;

import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.jboss.logging.Logger;

import capstone.order.v1.OrderPlaced;
import io.quarkus.websockets.next.OpenConnections;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Event;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.event.TransactionPhase;
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
 *
 * <p>The WebSocket push (see {@link #onNotificationPersisted}) is fired as a
 * CDI event right after {@code notification.persist()} and observed with
 * {@code @Observes(during = TransactionPhase.AFTER_SUCCESS)}, so it only
 * runs once this method's transaction has actually committed -- the same
 * transactional-observer pattern used for the {@code order.placed} Kafka
 * publish in order-service's {@code OrderEventProducer}. This is what makes
 * {@link OrderNotificationSocket}'s "reports an already-committed event"
 * claim true: before this, the push ran synchronously inside the
 * {@code @Transactional} method, i.e. strictly before commit.
 */
@ApplicationScoped
public class OrderPlacedConsumer {

    private static final Logger LOG = Logger.getLogger(OrderPlacedConsumer.class);

    // NEW for demos/demo-websocket.sh ("WebSockets.Next"):
    // every open /ws/notifications connection (see OrderNotificationSocket)
    // gets the freshly persisted Notification pushed to it as soon as this
    // consumer commits it -- a real, event-driven push, not a poll.
    @Inject
    OpenConnections wsConnections;

    @Inject
    Event<Notification> notificationPersistedEvent;

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

        // Fire rather than push directly: onNotificationPersisted below only
        // runs after THIS transaction commits (see class Javadoc), so the
        // WebSocket broadcast can never race ahead of the durable write.
        notificationPersistedEvent.fire(notification);
    }

    /**
     * Transactional observer: pushes {@code notification} to every open
     * {@code /ws/notifications} connection only after the transaction that
     * persisted it has committed successfully (JTA {@code AFTER_SUCCESS}
     * synchronization) -- see {@link OrderNotificationSocket}.
     *
     * <p>Uses the non-blocking {@code Sender#sendText} (a
     * {@code Uni<Void>}) rather than {@code sendTextAndAwait}: this observer
     * runs synchronously as part of transaction completion on the Reactive
     * Messaging consumer thread, and awaiting each client send in a loop
     * would block that thread for longer than necessary. Subscribing
     * fire-and-forget keeps the existing best-effort semantics (a client
     * that isn't listening right now simply misses this push -- no
     * retry/queue) without adding blocking I/O to the commit path.
     */
    void onNotificationPersisted(@Observes(during = TransactionPhase.AFTER_SUCCESS) Notification notification) {
        wsConnections.listAll().forEach(connection -> connection.sendText(notification)
                .subscribe().with(
                        ignored -> {
                        },
                        failure -> LOG.warnf(failure,
                                "failed to push notification for order %s to a WebSocket client",
                                notification.orderId)));
    }

    private static BigDecimal parseAmount(String amount) {
        return amount == null ? null : new BigDecimal(amount);
    }

    private static Instant parseCreatedAt(String createdAt) {
        return createdAt == null ? Instant.now() : Instant.parse(createdAt);
    }
}
