package com.patterncatalyst.datamesh.notification;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.net.URI;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;

import io.quarkus.test.common.http.TestHTTPResource;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.websockets.next.BasicWebSocketConnector;
import io.quarkus.websockets.next.WebSocketClientConnection;
import jakarta.inject.Inject;

/**
 * Scoped to the on-open handshake only, per the EXECUTE task spec: confirms
 * a client connecting to {@code /ws/notifications} immediately receives the
 * {@code {"type":"connected"}} acknowledgment from
 * {@link OrderNotificationSocket#onOpen()}.
 *
 * <p>Does NOT exercise the push-on-persist path ({@link OrderPlacedConsumer}'s
 * transactional observer broadcasting a freshly committed {@link Notification}
 * to every open connection) -- that would require a second, concurrently
 * open client connection racing a Kafka consumer, which is both heavier to
 * set up and more flaky than this handshake-only check. It is left out of
 * this gap-filling pass; the handshake is the part that was completely
 * untested before this file.
 *
 * <p>Uses the {@code BasicWebSocketConnector} CDI bean ("basic connector")
 * from {@code quarkus-websockets-next} (already a main dependency of this
 * module) rather than declaring a separate {@code @WebSocketClient} endpoint
 * class -- the basic connector is documented as the simpler option when all
 * that's needed is to open a connection and read a message back. No new
 * test dependency is required.
 */
@QuarkusTest
class OrderNotificationSocketTest {

    @TestHTTPResource
    URI baseUri;

    @Inject
    BasicWebSocketConnector connector;

    @Test
    void onOpen_sendsConnectedHandshake() throws Exception {
        CompletableFuture<String> firstMessage = new CompletableFuture<>();

        WebSocketClientConnection connection = connector
                .baseUri(baseUri)
                .path("/ws/notifications")
                .onTextMessage((conn, message) -> firstMessage.complete(message))
                .connectAndAwait();
        try {
            assertEquals("{\"type\":\"connected\"}", firstMessage.get(10, TimeUnit.SECONDS));
        } finally {
            connection.closeAndAwait();
        }
    }
}
