package com.patterncatalyst.datamesh.notification;

import io.quarkus.websockets.next.OnOpen;
import io.quarkus.websockets.next.WebSocket;

/**
 * NEW for demos/demo-websocket.sh (Phase D step 10.6, "WebSockets.Next"
 * capability) — a minimal push-notification socket for the order/shipping
 * domain: a client connects here to be told, in real time, when
 * notification-service persists a new {@link Notification} (i.e. when it
 * has consumed an {@code order.placed} event off Kafka — see
 * {@link OrderPlacedConsumer}).
 *
 * <p>Intentionally minimal: this endpoint itself only acknowledges the
 * connection ({@code @OnOpen}); the actual push happens from
 * {@link OrderPlacedConsumer#consume}, which broadcasts the persisted
 * {@link Notification} to every open connection via the injected
 * {@code io.quarkus.websockets.next.OpenConnections} bean once the Kafka
 * event has actually landed and been persisted — i.e. this socket reports a
 * real, already-committed domain event, not just "a request arrived".
 */
@WebSocket(path = "/ws/notifications")
public class OrderNotificationSocket {

    @OnOpen
    public String onOpen() {
        return "{\"type\":\"connected\"}";
    }
}
