---
title: "Appendix: scaling WebSocket push with Kafka"
order: 16
part: Appendices
description: "Why notification-service's single-process WebSocket push would break across more than one replica, and how Kafka-backed fan-out across per-replica consumer groups fixes it."
duration: "20 minutes"
marker: "16"
---

Chapter 11 introduced `notification-service`'s `/ws/notifications` endpoint as a
WebSockets.Next capability demo: a client connects, and the consumer side of
`notification-service` pushes it a `Notification` moments after the
corresponding `order.placed` event lands on Kafka. That demo runs, and is
genuinely real-time rather than polling, but it originally ran as **exactly
one process**. This appendix covers the gap between that and a deployment with
more than one replica, the normal shape for anything KEDA scales — naming the
problem precisely and walking through the two-consumer, two-Kafka-group
pattern `notification-service` now implements to solve it.

{% include excalidraw.html file="16-websocket-scaling" alt="N replicas of notification-service behind a Kubernetes Service/load balancer. Each replica holds its own local set of WebSocket client connections (a per-JVM OpenConnections registry) and its own Kafka consumer in a unique consumer group on the order.placed topic, so every replica receives every message. A client is pinned to the one replica it connected to; when that replica's consumer reads an OrderPlaced/Notification event, it checks its own local connection registry and pushes to whichever of its clients care, while the other replicas do the same independently for their own clients. Kafka is drawn as the shared fan-out bus all replicas read from in parallel, replacing the single in-process broadcast the one-replica version relies on." caption="Figure A1.1 — Scaling WebSocket push across replicas with Kafka fan-out" %}

## What the repo does today

Everything here traces back to three classes in
`examples/notification-service/src/main/java/com/patterncatalyst/datamesh/notification/`.

`OrderNotificationSocket` is deliberately minimal — it only acknowledges the
connection:

```java
@WebSocket(path = "/ws/notifications")
public class OrderNotificationSocket {

    @OnOpen
    public String onOpen() {
        return "{% raw %}{\"type\":\"connected\"}{% endraw %}";
    }
}
```

Persistence and push are two independent Kafka consumers of the same
`order.placed` topic, each with its own Reactive Messaging channel and its
own consumer group. `OrderPlacedConsumer` does the persistence: deserialize
the Avro `OrderPlaced` event, and persist it as a `Notification` row inside
one `@Transactional` `@Incoming("order-placed")` method (skipping it if
`Notification.findByOrderId` already finds one, since Kafka delivery is
at-least-once):

```java
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
```

`OrderPlacedPushConsumer` does the push, off a second channel
(`order-placed-push`) bound to the same `order.placed` topic:

```java
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
```

`wsConnections` is an injected `io.quarkus.websockets.next.OpenConnections` —
the WebSockets.Next registry of every socket currently open **in this JVM**.
`listAll()` iterates whichever clients happen to be connected to *this*
replica; it never needs to know about sockets held by any other replica,
because every replica runs its own `OrderPlacedPushConsumer` against the
same topic (see "The fan-out pattern" below for why that's safe to do
without racing `OrderPlacedConsumer`'s write). `demos/demo-websocket.sh`
proves the single-replica case of this chain end to end — order placed,
consumed, persisted, pushed — by running exactly one `notification-service`
JVM, where persistence and push happen to be observed by that same one
process either way.

## Why a second replica would break the old single-channel design

Put two replicas of `notification-service` behind a Kubernetes `Service` (or
any load balancer) and two independent problems show up — one inherent to
WebSockets, and one that the two-channel split above exists to solve.

**The socket is pinned to one replica.** A WebSocket starts as an HTTP
upgrade and then holds one long-lived TCP connection for its whole life. The
`Service`/load balancer picks a backend pod once, at connect time, and that
connection can't hop to a different pod mid-life — there's no protocol-level
mechanism for it to. So if a client opens `/ws/notifications` and lands on
replica A, replica A is the *only* process in the fleet holding that socket;
`OpenConnections` on replica B knows nothing about it — a plain in-memory
registry scoped to the JVM it lives in, with no clustering extension wired up
(this module's `pom.xml` depends on `quarkus-websockets-next` and nothing
else — no Infinispan, no Vert.x cluster manager). This is an unavoidable
property of what a WebSocket is, not something the fan-out pattern below
removes — see "Sticky sessions vs. broadcast."

**A single shared consumer group would only deliver the push to whichever
replica wins the partition.** `order-placed`'s `application.properties`
entry sets `mp.messaging.incoming.order-placed.connector=smallrye-kafka` and
`mp.messaging.incoming.order-placed.topic=order.placed`, but sets no
`group.id`. Per Quarkus's Kafka reference guide, the consumer group id
defaults to `quarkus.application.name`, which is `notification-service` — and
`k8s/keda/consumer-scaledobject.yaml` says so explicitly in its header
comment, pointing its `consumerGroup: notification-service` KEDA trigger at
that same default. A Kafka consumer group's defining behavior is that its
members **split the topic's partitions among themselves** — each partition
is read by exactly one member at a time. That's correct for a group whose
only job is "persist each order exactly once": two replicas sharing
`notification-service` as their group id divide the partitions, so the write
workload scales and no row is processed twice. It's exactly wrong for a push
that needs every replica to see every event — if `OrderPlacedPushConsumer`
read from that same shared group instead of its own, only the
partition-owning replica would ever see a given event and fire the push,
and if the client who needs to see it is connected to a different replica,
it would never arrive, silently: the order would still be persisted
correctly (`GET /notifications` would show it), and the socket would stay
open and healthy — it would just never receive that message. That's exactly
the failure mode `order-placed-push`'s separate, per-replica unique group
(below) exists to avoid.

## The fan-out pattern: every replica sees every message

The implementation keeps Kafka in its usual role — a durable, ordered log —
but changes *who subscribes to it and how*, by splitting
`OrderPlacedConsumer`'s old single `@Incoming("order-placed")` method into
two independent consumers of the same `order.placed` topic:

- `OrderPlacedConsumer` keeps the **existing shared, partition-balanced
  group** (`notification-service`, defaulted from
  `quarkus.application.name`) on its `order-placed` channel — one logical
  writer per partition across the whole replica set, unchanged from before,
  and still relying on `Notification.findByOrderId` plus the entity's
  `@Column(unique = true)` on `order_id` to make at-least-once redelivery
  idempotent.
- `OrderPlacedPushConsumer` subscribes independently, on a second channel
  (`order-placed-push`) bound to the *same* topic but with its own
  **per-replica unique** group id, so from Kafka's point of view each
  replica is a group of one, and a group of one assigned to a topic gets a
  copy of *every* record on every partition. Kafka becomes the broadcast
  bus for this channel: every replica, on consuming an event, checks only
  its own local `OpenConnections` and pushes to whichever of its own
  clients care — the same non-blocking `sendText(...).subscribe()` pattern
  the original single-consumer design used, just no longer dependent on
  that replica having "won" the partition, and never touching the database.

The per-replica unique group id is built from `HOSTNAME`, which Kubernetes
sets to the pod name for every container in a Deployment — unique per
replica by construction:

```properties
mp.messaging.incoming.order-placed-push.connector=smallrye-kafka
mp.messaging.incoming.order-placed-push.topic=order.placed
{% raw %}mp.messaging.incoming.order-placed-push.group.id=notification-push-${HOSTNAME:notification-service-push}{% endraw %}
mp.messaging.incoming.order-placed-push.auto.offset.reset=earliest
mp.messaging.incoming.order-placed-push.enable.auto.commit=false
mp.messaging.incoming.order-placed-push.value.deserializer=io.apicurio.registry.serde.avro.AvroKafkaDeserializer
mp.messaging.incoming.order-placed-push.apicurio.registry.use-specific-avro-reader=true
```

The `:notification-service-push` default (Quarkus property-expression
syntax, {% raw %}`${expression:default}`{% endraw %}) only matters when `HOSTNAME` isn't present
— for example a bare `mvn test` run outside a container — and keeps that
case correct for a single replica too, since one fixed group id still
receives every record on its own.

A separate channel name, `order-placed-push`, matters here rather than
simply rewriting `order-placed`'s existing `group.id`, because
`OrderPlacedConsumer.consume` used to do two jobs in one method gated by one
`@Incoming` channel: persist the row *and* fire the push. Simply replacing
that one channel's group id with a per-replica unique value would have
broken persistence along with fixing the fan-out: every replica would then
see every `OrderPlaced` event and race to persist the same row, and
`findByOrderId`'s check-then-insert isn't transactionally safe against a
concurrent insert from a sibling replica — both can find nothing, both
attempt the insert, and one loses to the unique constraint with a database
exception instead of a quiet no-op. Keeping persistence on its own channel
and group, and adding push as a second, independent subscription with no
database write at all, separates "exactly one writer per partition" from
"every replica sees everything" — the reason this is an architectural split
into two consumers rather than a one-line `group.id` edit.

Note that `OpenConnections` itself doesn't need to become distributed for
this to work: each replica keeps owning only its own sockets, and the
pattern centralizes the *event stream* rather than the connection registry —
no shared Redis set of "who's connected where," no cross-replica RPC to ask
"do you have this client." That's a materially smaller change than building
a distributed connection directory, and it's why Kafka, already the event
bus this project uses everywhere else, is a natural fit rather than new
infrastructure bolted on just for WebSockets.

## Sticky sessions vs. broadcast

"Sticky sessions" usually means a load balancer routes repeated *requests*
from the same client back to the same backend pod across separate
connections — a cookie-based affinity rule layered on otherwise-stateless
HTTP. A WebSocket gets the same effect for its own lifetime without that
configuration: the upgrade handshake picks one backend once, and the TCP
connection that follows stays pinned there for as long as it's open, sticky
rule or not. So the "client pinned to one replica" half of the scaling
problem isn't a configuration choice — it's a property of what a WebSocket
is.

Sticky-session thinking would otherwise matter for **reconnects**: if a
client drops and reconnects, should the load balancer land it back on the
same replica? With the Kafka fan-out pattern in place, it doesn't need to —
every replica is subscribed to the same broadcast and can serve any client
equally, so a reconnect landing on a different replica loses nothing. That's
the actual payoff of broadcasting over Kafka instead of engineering smarter
affinity rules: it removes the need to care which replica a client ends up
on, rather than guaranteeing it stays on the one it started with.

## Backpressure on slow clients

`OrderPlacedPushConsumer.consume` pushes with
`connection.sendText(notification).subscribe().with(ignored -> {}, failure -> ...)`
— fire-and-forget by design, per the method's own Javadoc: this runs
synchronously on the Reactive Messaging consumer thread for the
`order-placed-push` channel, and blocking that thread per client would be
worse than a best-effort push. That's reasonable for a single-client demo,
but it assumes away something that doesn't survive many concurrent, possibly
slow clients: nothing bounds how much data can be in flight to a
slow-reading connection, and nothing disconnects a client that never reads
at all. The one-replica demo never shows this, since it has exactly one
short-lived client per run; at real scale, an unbounded number of pending
sends per slow connection is a memory leak triggered by a client's own
reading speed. The fan-out pattern above multiplies this risk by the number
of replicas, since it's now every replica's `OrderPlacedPushConsumer`
holding this exposure independently rather than just the one process the
single-replica demo runs.

A scaled deployment would need a bound per connection — a fixed-size outbound
queue, with an explicit policy for what happens when it fills: drop the
oldest pending message (acceptable here, since a newer `Notification` for a
*different* order doesn't supersede an older one the way a live dashboard
tick might, so dropping isn't free the way it would be for a status gauge)
or close the connection and let the client reconnect and miss nothing it
couldn't re-fetch from `GET /notifications`. Nothing in `OrderNotificationSocket`
or `OrderPlacedPushConsumer` does either today; both the bound and the policy
would be new code, not a configuration flag that already exists on
`OpenConnections` or `sendText`.

## KEDA and scale-to-zero: a socket pins a replica up

`k8s/keda/consumer-scaledobject.yaml` configures `notification-service` to
scale on Kafka consumer lag for the `notification-service` group, with
`minReplicaCount: 0` — the deployment can go to zero replicas when there's no
lag, and KEDA's Kafka trigger brings a replica back up once lag accrues past
`lagThreshold: "5"`. That scale-to-zero story is written entirely in terms of
**consumer lag on the shared `notification-service` group** — i.e. the
persistence path, `OrderPlacedConsumer`'s `order-placed` channel. It says
nothing about the per-replica `order-placed-push` groups
`OrderPlacedPushConsumer` now also holds (each one, by construction, a group
of one that catches up to the head of the topic as fast as its replica can
read, so it wouldn't accrue meaningful lag at this traffic volume even if it
were wired into the same trigger) or about open WebSocket connections,
because neither exists in that ScaledObject's model of the workload.

That gap becomes a real conflict once a replica also holds live client
sockets. A replica with zero consumer lag but three open `/ws/notifications`
connections is, by this lag-only metric, a candidate for scale-down to
zero — and scaling it to zero drops every connection it holds, with no
replacement replica to reconnect to until the next `order.placed` event
causes lag and a cold start. An idle-but-open socket, simply waiting for the
next order, looks identical to KEDA as "no work happening" and identical to
the client as a connection about to be killed for no reason it caused.
Fixing this isn't a `group.id` change like the fan-out problem above; it
needs the deployment to also account for in-flight connections — for
example, a second scaler input (KEDA supports multiple triggers per
`ScaledObject`) keyed on open-connection count, a
`PodDisruptionBudget`/termination-grace-period posture that drains sockets
gracefully rather than dropping them, or simply pairing a WebSocket-serving
replica with `minReplicaCount: 1` instead of `0`. None of that is configured
in `consumer-scaledobject.yaml` today — it's written for a purely
consume-and-persist workload, accurate for what runs there now but not for a
scaled, socket-holding variant of this service.

## What you learned

- `notification-service` persists and pushes via two independent Kafka
  consumers of the same `order.placed` topic — `OrderPlacedConsumer` (shared
  group, `order-placed` channel) and `OrderPlacedPushConsumer` (per-replica
  unique group, `order-placed-push` channel) — specifically so the push
  works correctly across more than one replica, each still only touching
  its own in-JVM `OpenConnections` registry (no clustering extension behind
  it).
- A shared Kafka consumer group (`notification-service`, taken from
  `quarkus.application.name`, still what `order-placed` uses) splits
  partitions across replicas — correct for exactly-once persistence, and
  exactly wrong for a push that needs every replica to see every event.
- The push channel is Kafka-as-broadcast-bus: its per-replica unique group
  id (`notification-push-{% raw %}${HOSTNAME}{% endraw %}`, see "The
  fan-out pattern" above) makes every replica a group of one, so each one
  receives every message and fans out only to its own locally-connected
  sockets — without needing a distributed connection registry.
- That's implemented as two separate channels/consumers rather than
  relabeling `order-placed`'s existing `group.id`, because the same change
  that fixes fan-out on a single channel would otherwise break the
  persistence path's duplicate-write safety.
- A WebSocket's own connection semantics already pin a client to one replica
  for the socket's life; broadcasting over Kafka removes the need to engineer
  sticky-session affinity for *reconnects* on top of that.
- The current fire-and-forget push has no backpressure bound per connection,
  and the current KEDA `ScaledObject` scales purely on consumer lag — neither
  accounts for a replica holding live sockets, which is new risk a scaled
  deployment would have to design for explicitly.

---

*Verification status: <span class="status status--verified">verified</span>. The multi-replica fan-out was driven on the minikube substrate with two `notification-service` replicas. Each replica's push consumer registered its own unique Kafka group (`notification-push-${HOSTNAME}` resolved to the two distinct pod names, confirmed alongside the shared `notification-service` persistence group), so every replica received every `order.placed` record. A WebSocket client was connected to each replica; a single order was placed, and both clients independently received the push for that same order id — the Kafka-backed broadcast across per-replica consumer groups working as described. (`OrderPlacedConsumer` persists on the shared group; `OrderPlacedPushConsumer` pushes on the per-replica group.)*
