///usr/bin/env jbang "$0" "$@" ; exit $?
//JAVA 25+

// demos/jbang/WsReconnectClient.java — a WebSocket client for
// notification-service that survives the loss of the replica it is connected
// to, implementing the three client behaviours chapter 16 recommends:
//
//   1. A close or error is a signal to reconnect, not a terminal failure.
//   2. Each reconnect waits with exponential backoff and jitter
//      (1 s, 2 s, 4 s ... capped at 16 s, each scaled by a random 0.5–1.5),
//      so a replica loss does not cause a synchronized reconnect storm.
//   3. After every (re)connect, it fetches GET /notifications to close the
//      gap left while it was disconnected, and de-duplicates by orderId
//      across both paths.
//
// JDK only (java.net.http), no //DEPS. Runs with `jbang WsReconnectClient.java`
// or, on any JDK 25, the single-file launcher `java WsReconnectClient.java`;
// tooling/ws-failover/verify-ws-failover.sh runs it in-cluster that way.
//
// Usage: WsReconnectClient <ws-url> <notifications-url> <run-seconds>
//
// Output (one event per line, for scripts to grep):
//   WS_OPEN attempt=<n>
//   WS_CLOSED code=<c> | WS_ERROR <message>
//   WS_RECONNECT attempt=<n> delay_ms=<ms>
//   CATCHUP fetched=<n> new=<n>
//   ORDER <orderId> via=<push|catchup>        (first sighting only)
//   DUPLICATE <orderId> via=<push|catchup>    (already seen; dropped)
//   RUN_DONE seen=<n> reconnects=<n>
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.WebSocket;
import java.time.Duration;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class WsReconnectClient {

    private static final Pattern ORDER_ID = Pattern.compile("\"orderId\"\\s*:\\s*\"([^\"]+)\"");
    private static final long BASE_DELAY_MS = 1_000;
    private static final long MAX_DELAY_MS = 16_000;

    private static final Set<String> seen = ConcurrentHashMap.newKeySet();
    private static final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5)).build();

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("usage: WsReconnectClient <ws-url> <notifications-url> <run-seconds>");
            System.exit(2);
        }
        URI wsUri = URI.create(args[0]);
        URI restUri = URI.create(args[1]);
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(Long.parseLong(args[2]));

        int attempt = 0;
        int reconnects = 0;
        while (System.nanoTime() < deadline) {
            attempt++;
            CompletableFuture<String> closed = new CompletableFuture<>();
            WebSocket ws;
            try {
                ws = http.newWebSocketBuilder()
                        .connectTimeout(Duration.ofSeconds(5))
                        .buildAsync(wsUri, listener(closed))
                        .get(10, TimeUnit.SECONDS);
            } catch (Exception e) {
                log("WS_ERROR connect failed: " + rootMessage(e));
                reconnects++;
                backoff(reconnects, deadline);
                continue;
            }
            log("WS_OPEN attempt=" + attempt);
            catchUp(restUri);
            // A successful connection resets the backoff sequence.
            reconnects = 0;

            String reason = awaitClose(closed, deadline);
            if (reason == null) {
                ws.sendClose(WebSocket.NORMAL_CLOSURE, "run complete");
                break;
            }
            log(reason);
            reconnects++;
            backoff(reconnects, deadline);
        }
        log("RUN_DONE seen=" + seen.size() + " reconnects=" + (attempt - 1));
        System.exit(0);
    }

    private static WebSocket.Listener listener(CompletableFuture<String> closed) {
        return new WebSocket.Listener() {
            private final StringBuilder buffer = new StringBuilder();

            @Override
            public CompletionStage<?> onText(WebSocket ws, CharSequence data, boolean last) {
                buffer.append(data);
                if (last) {
                    record(buffer.toString(), "push");
                    buffer.setLength(0);
                }
                ws.request(1);
                return null;
            }

            @Override
            public CompletionStage<?> onClose(WebSocket ws, int statusCode, String reason) {
                closed.complete("WS_CLOSED code=" + statusCode);
                return null;
            }

            @Override
            public void onError(WebSocket ws, Throwable error) {
                closed.complete("WS_ERROR " + rootMessage(error));
            }
        };
    }

    /** Returns the close/error line, or null when the run deadline passes first. */
    private static String awaitClose(CompletableFuture<String> closed, long deadline) throws Exception {
        long remaining = deadline - System.nanoTime();
        if (remaining <= 0) {
            return null;
        }
        try {
            return closed.get(remaining, TimeUnit.NANOSECONDS);
        } catch (java.util.concurrent.TimeoutException e) {
            return null;
        }
    }

    private static void catchUp(URI restUri) {
        try {
            HttpResponse<String> response = http.send(
                    HttpRequest.newBuilder(restUri).timeout(Duration.ofSeconds(10)).GET().build(),
                    HttpResponse.BodyHandlers.ofString());
            int before = seen.size();
            Matcher m = ORDER_ID.matcher(response.body());
            int fetched = 0;
            while (m.find()) {
                fetched++;
                if (seen.add(m.group(1))) {
                    log("ORDER " + m.group(1) + " via=catchup");
                }
            }
            log("CATCHUP fetched=" + fetched + " new=" + (seen.size() - before));
        } catch (Exception e) {
            log("CATCHUP_FAILED " + rootMessage(e));
        }
    }

    private static void record(String message, String via) {
        Matcher m = ORDER_ID.matcher(message);
        if (!m.find()) {
            return; // the {"type":"connected"} acknowledgement carries no orderId
        }
        String orderId = m.group(1);
        log((seen.add(orderId) ? "ORDER " : "DUPLICATE ") + orderId + " via=" + via);
    }

    private static void backoff(int failures, long deadline) throws InterruptedException {
        long exp = Math.min(MAX_DELAY_MS, BASE_DELAY_MS << Math.min(failures - 1, 4));
        long delay = (long) (exp * ThreadLocalRandom.current().nextDouble(0.5, 1.5));
        long remainingMs = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime());
        delay = Math.max(0, Math.min(delay, remainingMs));
        log("WS_RECONNECT attempt=" + (failures + 1) + " delay_ms=" + delay);
        Thread.sleep(delay);
    }

    private static String rootMessage(Throwable t) {
        while (t.getCause() != null) {
            t = t.getCause();
        }
        return t.getClass().getSimpleName() + ": " + t.getMessage();
    }

    private static void log(String line) {
        System.out.println(line);
        System.out.flush();
    }
}
