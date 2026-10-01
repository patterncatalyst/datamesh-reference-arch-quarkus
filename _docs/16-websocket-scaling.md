---
title: "Appendix: scaling WebSocket push with Kafka"
order: 16
part: Appendices
description: "Why notification-service's single-process WebSocket push breaks the moment it runs as more than one replica, and what Kafka-backed fan-out across per-replica consumer groups would need to look like to fix it."
duration: "20 minutes"
marker: "16"
---

Chapter 11 introduced `notification-service`'s `/ws/notifications` endpoint as a
WebSockets.Next capability demo: a client connects, and `OrderPlacedConsumer`
pushes it a `Notification` the instant the row that backs it commits. That demo
runs — and is genuinely real-time, not polling — but it runs as **exactly one
process**. This appendix is about the gap between that and a deployment with
more than one replica, which is the normal shape for anything KEDA scales. The
repo does not implement the scaled version described here; this chapter exists
to name the problem precisely and describe the pattern that solves it, not to
claim it is running.

{% include excalidraw.html file="16-websocket-scaling" alt="N replicas of notification-service behind a Kubernetes Service/load balancer. Each replica holds its own local set of WebSocket client connections (a per-JVM OpenConnections registry) and its own Kafka consumer in a unique consumer group on the order.placed topic, so every replica receives every message. A client is pinned to the one replica it connected to; when that replica's consumer reads an OrderPlaced/Notification event, it checks its own local connection registry and pushes to whichever of its clients care, while the other replicas do the same independently for their own clients. Kafka is drawn as the shared fan-out bus all replicas read from in parallel, replacing the single in-process broadcast the one-replica version relies on." caption="Figure A1.1 — Scaling WebSocket push across replicas with Kafka fan-out" %}

## What the repo actually does today

Everything here traces back to two classes in
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

The actual push happens elsewhere, in `OrderPlacedConsumer`, which does three
things in sequence inside one `@Transactional` `@Incoming("order-placed")`
method: deserialize the Avro `OrderPlaced` event, persist it as a
`Notification` row (skipping it if `Notification.findByOrderId` already finds
one, since Kafka delivery is at-least-once), and then fire a CDI event. A
separate `@Observes(during = TransactionPhase.AFTER_SUCCESS)` method only runs
once that transaction has actually committed, and that is the method that
touches WebSockets:

```java
void onNotificationPersisted(@Observes(during = TransactionPhase.AFTER_SUCCESS) Notification notification) {
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
That's the entire push mechanism: one process holds the Kafka consumer, the
same process holds the socket registry, and `listAll()` can iterate every
connected client because there is, by construction, only one process to ask.
`demos/demo-websocket.sh` proves this chain end to end — order placed,
consumed, persisted, pushed — but it does so by running exactly one
`notification-service` JVM. There is nothing in `OrderNotificationSocket`,
`OrderPlacedConsumer`, or `application.properties` that addresses more than one
replica, and nothing in this repo today does.

## Why a second replica breaks this

Put two replicas of `notification-service` behind a Kubernetes `Service` (or
any load balancer) and two independent problems appear at once.

**The socket is pinned to one replica.** A WebSocket starts as an HTTP
upgrade and then holds one long-lived TCP connection for its whole life. The
`Service`/load balancer picks a backend pod once, at connect time, and that
connection cannot hop to a different pod mid-life — there's no protocol-level
mechanism for it to. So if a client opens `/ws/notifications` and lands on
replica A, replica A is the *only* process in the fleet holding that socket.
`OpenConnections` on replica B knows nothing about it — it's a plain in-memory
registry scoped to the JVM it lives in, with no clustering extension wired up
(this module's `pom.xml` depends on `quarkus-websockets-next` and nothing
else — no Infinispan, no Vert.x cluster manager).

**The Kafka consumer that fires the push might be a different replica
entirely.** `application.properties` sets
`mp.messaging.incoming.order-placed.connector=smallrye-kafka` and
`mp.messaging.incoming.order-placed.topic=order.placed`, but sets no
`group.id`. Per Quarkus's Kafka reference guide, the consumer group id
defaults to `quarkus.application.name`, which is `notification-service` — and
the repo's own `k8s/keda/consumer-scaledobject.yaml` says so explicitly in its
header comment, pointing its `consumerGroup: notification-service` KEDA
trigger at that same default. A Kafka consumer group's defining behavior is
that its members **split the topic's partitions among themselves** — each
partition is read by exactly one member of the group at a time. That's
correct and desirable for a group whose only job is "persist each order
exactly once": two replicas sharing `notification-service` as their group id
divide the partitions, so the write workload scales and no row is processed
twice by two different processes.

It is exactly wrong for the push. If replica A's consumer happens to own the
partition the next `OrderPlaced` lands on, replica A's `OrderPlacedConsumer`
is the only one that ever sees that event and fires the CDI broadcast — and
if the client who needs to see it is connected to replica B, it never arrives.
There is no cross-replica communication of any kind in the current code, so
nothing compensates for this. The failure is silent, too: the order is still
persisted correctly (`GET /notifications` would show it), and the socket
stays open and healthy — it just never receives that message. That quiet
"REST says it happened, the socket never told you" gap is the whole scaling
problem in one sentence.

## The fan-out pattern: every replica sees every message

The fix the diagram above describes keeps Kafka in its usual role — a durable,
ordered log — but changes *who subscribes to it and how*. Instead of one
shared group dividing partitions across replicas, every replica needs its own
**unique** consumer group, so that from Kafka's point of view each replica is
a group of one, and a group of one assigned to a topic gets a copy of
*every* record on every partition. Kafka becomes the broadcast bus: any
replica, on consuming an event, checks only its own local `OpenConnections`
and pushes to whichever of its own clients care — exactly what `onNotificationPersisted`
already does, just no longer dependent on that replica being the one that
"won" the partition.

A unique group id per replica is ordinarily built from something the
orchestrator hands each pod at startup — a pod name via the Kubernetes
Downward API, for example:

```properties
# What a broadcast-style consumer group id would look like — NOT configured
# in this repo today. HOSTNAME is a Kubernetes Deployment default; a pod's
# hostname is its pod name unless overridden.
mp.messaging.incoming.order-placed-broadcast.connector=smallrye-kafka
mp.messaging.incoming.order-placed-broadcast.topic=order.placed
{% raw %}mp.messaging.incoming.order-placed-broadcast.group.id=notification-service-ws-${HOSTNAME}{% endraw %}
```

Note the separate channel name, `order-placed-broadcast`, rather than simply
rewriting `order-placed`'s existing `group.id`. This matters because
`OrderPlacedConsumer.consume` currently does two jobs in one method gated by
one `@Incoming` channel: it persists the row (relying on
`Notification.findByOrderId` plus the entity's `@Column(unique = true)` on
`order_id` to make at-least-once redelivery idempotent) *and* it fires the
push. If that same channel's group id were simply replaced with a
per-replica unique value, persistence would break along with the fan-out fix:
every replica would now see every `OrderPlaced` event and each would race to
persist the same row, and `findByOrderId`'s check-then-insert is not
transactionally safe against a concurrent insert from a sibling replica — two
replicas can both find nothing, then both attempt the insert, and one loses to
the unique constraint with a database exception instead of a quiet no-op.

The pattern that avoids that is to keep **persistence** on the existing
shared, partition-balanced group (one logical writer per partition across the
whole replica set — safe, and already what the repo has) and add a *second*,
independent subscription whose only job is the WebSocket push: either a
second `@Incoming` channel on the same `order.placed` topic with its own
unique group id and no database write at all, or a dedicated downstream
"notification-pushed" topic that the persisting consumer publishes to after a
successful commit, which every replica's unique-group consumer then taps
purely for fan-out. Either shape separates "exactly one writer per partition"
from "every replica sees everything" instead of asking one `@Incoming` method
to satisfy both constraints at once — which is what makes this an
architectural change, not a one-line `group.id` edit.

## Per-instance registry, not a shared one

It's worth being explicit that `OpenConnections` itself does **not** need to
become distributed for this to work. Each replica keeps owning only its own
sockets — that part of today's code is already correct for a scaled
deployment, it just needs a reliable way to learn about every event rather
than a partition-limited subset. The pattern doesn't centralize the
connection registry (no shared Redis set of "who's connected where," no
cross-replica RPC to ask "do you have this client"); it centralizes the
*event stream* instead, and lets each replica's existing local
`wsConnections.listAll()` decide locally whether anything it holds cares about
a given message. That's a meaningfully smaller change than building a
distributed connection directory, and it's why Kafka — already the event bus
this reactor uses everywhere else — is a natural fit rather than a new piece
of infrastructure bolted on just for WebSockets.

## Sticky sessions vs. broadcast

"Sticky sessions" usually means a load balancer is configured to route
repeated *requests* from the same client back to the same backend pod across
multiple separate connections — a cookie-based affinity rule layered on top
of otherwise-stateless HTTP. A WebSocket doesn't need that configuration to
get the same effect for its own lifetime: the upgrade handshake picks one
backend once, and the TCP connection that follows is inherently pinned there
for as long as it stays open, with or without a sticky-session rule. So the
"client pinned to one replica" half of the scaling problem isn't a
configuration choice to make — it's a property of what a WebSocket is.

Where sticky-session-style thinking *would* otherwise matter is
**reconnects**: if a client drops and reconnects, should the load balancer try
to land it back on the same replica it was using before? With the Kafka
fan-out pattern in place, the honest answer is that it doesn't need to —
every replica is subscribed to the same broadcast and can serve any client
equally, so a reconnect landing on a different replica loses nothing. That's
the actual payoff of broadcasting over Kafka instead of engineering smarter
affinity rules: it removes the need to care which replica a client ends up
on, rather than trying to guarantee it stays on the one it started with.

## Backpressure on slow clients

The current `onNotificationPersisted` pushes with
`connection.sendText(notification).subscribe().with(ignored -> {}, failure -> ...)`
— fire-and-forget, deliberately, per the method's own Javadoc: this observer
runs synchronously as part of transaction completion on the Reactive
Messaging consumer thread, and blocking that thread per client would be
worse than a best-effort push. That choice is reasonable for a single-client
demo, but it carries an unstated assumption that doesn't survive many
concurrent, possibly slow clients: nothing in this code bounds how much data
can be in flight to a connection that reads slowly, and nothing disconnects a
client that never reads at all. In the one-replica demo this is invisible
because there's exactly one short-lived client per run. At any real scale,
an unbounded number of pending sends per slow connection is a memory leak
with a client's reading speed as the trigger.

A scaled deployment would need a bound per connection — a fixed-size outbound
queue, with an explicit policy for what happens when it fills: drop the
oldest pending message (acceptable here, since a newer `Notification` for a
*different* order doesn't supersede an older one the way a live dashboard
tick might, so dropping isn't free the way it would be for a status gauge)
or close the connection and let the client reconnect and miss nothing it
couldn't re-fetch from `GET /notifications`. Nothing in `OrderNotificationSocket`
or `OrderPlacedConsumer` does either today; both the bound and the policy
would be new code, not a configuration flag that already exists on
`OpenConnections` or `sendText`.

## KEDA and scale-to-zero: a socket pins a replica up

`k8s/keda/consumer-scaledobject.yaml` configures `notification-service` to
scale on Kafka consumer lag for the `notification-service` group, with
`minReplicaCount: 0` — the deployment can go to zero replicas when there's no
lag, and KEDA's Kafka trigger brings a replica back up once lag accrues past
`lagThreshold: "5"`. That scale-to-zero story is written entirely in terms of
**consumer lag**, because today's only subscriber to `order.placed` is the
persistence path. It says nothing about open WebSocket connections, because
none exist in that ScaledObject's model of the workload at all.

That gap becomes a real conflict once a replica also holds live client
sockets. A replica with zero consumer lag but three open `/ws/notifications`
connections is, by this ScaledObject's lag-only metric, a candidate for
scale-down to zero — and scaling it to zero would drop every connection it
holds, with no replacement replica to reconnect to until the next `order.placed`
event causes lag and a cold start. A client sitting on an idle-but-open socket,
simply waiting for the next order, looks identical to KEDA as "no work
happening" and identical to the client as "my connection is about to be
killed for no reason I caused." Solving this is not a `group.id` change like
the fan-out problem above; it needs the deployment to also account for
in-flight connections — for example, a second scaler input (KEDA supports
multiple triggers per `ScaledObject`) keyed on open-connection count, or a
`PodDisruptionBudget`/termination-grace-period posture that drains sockets
gracefully rather than dropping them outright, or simply accepting that a
WebSocket-serving replica is not a good scale-to-zero candidate and pairing
it with `minReplicaCount: 1` instead of `0` for that specific role. None of
that is configured in this repo's `consumer-scaledobject.yaml` today — it's
written for a purely consume-and-persist workload, which is still an
accurate description of what runs there now, but it would stop being
accurate the moment a scaled, socket-holding variant of this service shipped.

## What you learned

- `notification-service`'s WebSocket push works today because one process
  holds both the Kafka consumer and the socket registry — `OpenConnections`
  is a per-JVM in-memory structure with no clustering extension behind it.
- A shared Kafka consumer group (today's default, `notification-service`,
  taken from `quarkus.application.name`) splits partitions across replicas —
  correct for exactly-once persistence, and exactly wrong for a push that
  needs every replica to see every event.
- The fix is Kafka-as-broadcast-bus: each replica subscribes with its own
  unique consumer group so it receives every message, then fans out only to
  its own locally-connected sockets — without needing a distributed
  connection registry.
- That requires separating the existing `order-placed` channel's two jobs
  (partition-balanced persistence, broadcast-style push) rather than simply
  relabeling its `group.id`, because the same change that fixes fan-out would
  otherwise break the persistence path's duplicate-write safety.
- A WebSocket's own connection semantics already pin a client to one replica
  for the socket's life; broadcasting over Kafka removes the need to engineer
  sticky-session affinity for *reconnects* on top of that.
- The current fire-and-forget push has no backpressure bound per connection,
  and the current KEDA `ScaledObject` scales purely on consumer lag — neither
  accounts for a replica holding live sockets, which is new risk a scaled
  deployment would have to design for explicitly.

---

*Verification status: <span class="status status--unverified">unverified</span>.
What's actually been run is the single-instance path: `demos/demo-websocket.sh`
passes against one `notification-service` JVM, proving the connect → persist
→ push chain described in the first section. Nothing in this chapter past
that point — the per-replica unique consumer group, the split
persistence/broadcast channels, the per-connection backpressure bound, or any
KEDA trigger beyond consumer lag — is implemented or deployed anywhere in this
repo; it is a recommended pattern reasoned from the real code and the real
`consumer-scaledobject.yaml`, not a measured result. If this is ever built,
the highest-risk things to confirm are: that a per-replica unique `group.id`
genuinely delivers every record to every replica rather than silently
reverting to shared behavior under a Kafka client default; that the
split-channel persistence path still dedups correctly under genuinely
concurrent multi-replica delivery (not just the single-process redelivery
this repo's tests cover); and that a connection-count-aware KEDA trigger
(or a `minReplicaCount: 1` posture) actually prevents a socket-holding
replica from being scaled to zero out from under a connected client.*
