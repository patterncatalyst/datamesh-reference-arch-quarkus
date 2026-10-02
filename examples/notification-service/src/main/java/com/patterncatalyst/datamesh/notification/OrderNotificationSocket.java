package com.patterncatalyst.datamesh.notification;

import io.quarkus.websockets.next.OnOpen;
import io.quarkus.websockets.next.WebSocket;

/**
 * NEW for demos/demo-websocket.sh ("WebSockets.Next"
 * capability) — a minimal push-notification socket for the order/shipping
 * domain: a client connects here to be told, in real time, when
 * notification-service persists a new {@link Notification} (i.e. when it
 * has consumed an {@code order.placed} event off Kafka — see
 * {@link OrderPlacedConsumer}).
 *
 * <p>Intentionally minimal: this endpoint itself only acknowledges the
 * connection ({@code @OnOpen}); the actual push happens from
 * {@link OrderPlacedPushConsumer}, a second, independent Kafka consumer of
 * the same {@code order.placed} topic (channel {@code order-placed-push},
 * per-replica unique consumer group) that pushes a freshly built
 * {@link Notification} to every connection open in this JVM via the
 * injected {@code io.quarkus.websockets.next.OpenConnections} bean, for
 * every {@code OrderPlaced} event this replica consumes -- which, thanks to
 * its unique group id, is every event on the topic, regardless of which
 * replica (possibly a different one) is the partition owner that persists
 * it via {@link OrderPlacedConsumer}. Persistence and push are deliberately
 * two independent consumers of the same topic (see
 * {@code _docs/16-websocket-scaling.md}) rather than one method doing both:
 * a shared, partition-balanced consumer group is correct for "persist each
 * order exactly once" but wrong for a push that needs every replica to see
 * every event, so the push channel instead uses a per-replica unique group.
 */
@WebSocket(path = "/ws/notifications")
public class OrderNotificationSocket {

    @OnOpen
    public String onOpen() {
        return "{\"type\":\"connected\"}";
    }
}
