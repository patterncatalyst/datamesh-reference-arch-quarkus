// demos/jbang/WsNotificationClient.java — demos/demo-websocket.sh's real WS
// client ("WebSockets.Next" capability).
//
// A tiny, dependency-free WebSocket client: plain JDK `java.net.http.WebSocket`
// (no extra jars to resolve -- jbang just compiles and runs this file
// directly), connecting to notification-service's new `/ws/notifications`
// endpoint (see examples/notification-service's OrderNotificationSocket).
//
// Usage: jbang WsNotificationClient.java <ws-url> <timeout-seconds> <expected-message-count>
//
// Prints one line per received text message, prefixed "WS_MSG:" (the raw
// JSON payload follows, consumed by demo-websocket.sh via jq) — plus
// "WS_OPEN" the moment the handshake completes (the caller polls for this
// before triggering the event that produces the real message), and exits 0
// once <expected-message-count> messages have been received (or non-zero on
// timeout/error, with a diagnostic line).
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public class WsNotificationClient {

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("usage: WsNotificationClient <ws-url> <timeout-seconds> <expected-message-count>");
            System.exit(2);
        }
        String url = args[0];
        int timeoutSeconds = Integer.parseInt(args[1]);
        int expectedMessages = Integer.parseInt(args[2]);

        AtomicInteger received = new AtomicInteger(0);
        CompletableFuture<Void> done = new CompletableFuture<>();
        StringBuilder buffer = new StringBuilder();

        HttpClient client = HttpClient.newHttpClient();
        WebSocket.Listener listener = new WebSocket.Listener() {
            @Override
            public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
                buffer.append(data);
                webSocket.request(1);
                if (last) {
                    System.out.println("WS_MSG:" + buffer);
                    System.out.flush();
                    buffer.setLength(0);
                    if (received.incrementAndGet() >= expectedMessages) {
                        done.complete(null);
                    }
                }
                return null;
            }

            @Override
            public void onError(WebSocket webSocket, Throwable error) {
                done.completeExceptionally(error);
            }

            @Override
            public CompletionStage<?> onClose(WebSocket webSocket, int statusCode, String reason) {
                if (!done.isDone()) {
                    done.completeExceptionally(
                            new IllegalStateException("server closed the connection early (code=" + statusCode + ", reason=" + reason + ")"));
                }
                return null;
            }
        };

        WebSocket ws;
        try {
            ws = client.newWebSocketBuilder()
                    .connectTimeout(java.time.Duration.ofSeconds(10))
                    .buildAsync(URI.create(url), listener)
                    .get(15, TimeUnit.SECONDS);
        } catch (Exception e) {
            System.out.println("WS_CONNECT_FAILED: " + e);
            System.exit(1);
            return;
        }
        System.out.println("WS_OPEN");
        System.out.flush();

        try {
            done.get(timeoutSeconds, TimeUnit.SECONDS);
            System.out.println("WS_DONE");
        } catch (Exception e) {
            System.out.println("WS_TIMEOUT_OR_ERROR: " + e);
            ws.abort();
            System.exit(1);
            return;
        }
        ws.sendClose(WebSocket.NORMAL_CLOSURE, "demo-websocket done").join();
    }
}
