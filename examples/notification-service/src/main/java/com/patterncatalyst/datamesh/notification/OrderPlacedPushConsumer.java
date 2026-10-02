package com.patterncatalyst.datamesh.notification;

import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.jboss.logging.Logger;

import capstone.order.v1.OrderPlaced;
import io.quarkus.websockets.next.OpenConnections;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

/**
 * Consumes the SAME Avro-encoded {@code OrderPlaced} events as
 * {@link OrderPlacedConsumer}, off the SAME {@code order.placed} Kafka
 * topic, but via a SECOND Reactive Messaging channel
 * ({@code order-placed-push}, see {@code application.properties}) bound to a
 * per-replica UNIQUE consumer group id derived from the pod's
 * {@code HOSTNAME} instead of the shared {@code notification-service} group
 * {@link OrderPlacedConsumer} uses.
 *
 * <p>Per Kafka's consumer-group semantics, a shared group id splits a
 * topic's partitions across its members -- correct for "persist each order
 * exactly once," and exactly wrong for a push that needs every replica to
 * see every event. A unique group id makes every member a group of one, and
 * Kafka hands a group of one a copy of every record on every partition, so
 * every replica's {@code order-placed-push} consumer sees every
 * {@code OrderPlaced} event regardless of which replica (if any) owns the
 * partition it landed on. See {@code _docs/16-websocket-scaling.md} for the
 * full rationale.
 *
 * <p>This consumer does ONLY the WebSocket push: it checks its own local
 * {@link OpenConnections} (the WebSockets.Next registry of sockets open
 * in THIS JVM) and pushes a freshly built, never-persisted
 * {@link Notification} view to each one via the non-blocking
 * {@code sendText(...).subscribe()} pattern -- fire-and-forget, so a slow or
 * absent listener never blocks this consumer. It never writes to the
 * database and is deliberately not {@code @Transactional}; persistence
 * remains {@link OrderPlacedConsumer}'s sole responsibility, so a replica
 * that only owns a push-channel event (and not the persisting partition)
 * never races the writer.
 */
@ApplicationScoped
public class OrderPlacedPushConsumer {

    private static final Logger LOG = Logger.getLogger(OrderPlacedPushConsumer.class);

    @Inject
    OpenConnections wsConnections;

    @Incoming("order-placed-push")
    public void consume(OrderPlaced event) {
        Notification notification = Notification.from(event);
        wsConnections.listAll().forEach(connection -> connection.sendText(notification)
                .subscribe().with(
                        ignored -> {
                        },
                        failure -> LOG.warnf(failure,
                                "failed to push notification for order %s to a WebSocket client",
                                notification.orderId)));
    }
}
