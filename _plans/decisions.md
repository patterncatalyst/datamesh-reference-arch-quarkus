---
title: Decision Log
description: Architecture and tooling decisions for the Quarkus DataMesh reference architecture
---

# Decision Log — datamesh-reference-arch-quarkus

Records the settled decisions (DRQ-NNN) for this build. Convert relative dates to absolute.

## Version matrix (DRQ-001)

| Component | Version | Notes |
|-----------|---------|-------|
| Quarkus | **3.39.5** | Current latest **stable** (4.0.0 is Beta only). User's pin confirmed correct. |
| JDK | **25** (`25-tem`) | Supported on Quarkus 3.39.x; seed pom already compiles source/target 25. |
| Camel | **platform-aligned** | Import `quarkus-camel-bom:3.39.5`; do NOT pin standalone Camel. |
| langchain4j (Quarkiverse) | **1.14.1** | Bump from seed's 1.7.4; re-validate Ollama tool-calling path. |
| Maven | 3.9.x | |
| Base images | UBI (`ubi10/openjdk-25` builder + `-runtime`) | Multi-stage; docker toolchain, NOT podman. |

## Settled decisions

- **DRQ-002 — Repo creation:** Build locally first. GitHub remote (github.com/patterncatalyst/datamesh-reference-arch-quarkus, **PUBLIC**) created + pushed ONLY after user approval.
- **DRQ-003 — Container toolchain:** New skill `lgtm-docker-stack` (docker, docker compose, Testcontainers/Dev Services, devcontainers, minikube). No podman. Multi-stage images, prefer UBI.
- **DRQ-004 — Quarkus/JDK:** Latest stable Quarkus (3.39.5) + JDK 25.
- **DRQ-005 — OIDC demo:** Attempt live (Keycloak Dev Service); if laptop budget too tight, document conceptually + log deferral here (mirrors python CAP-047 pattern).
- **DRQ-006 — Spring Boot comparison:** Ship ONE runnable Spring Boot twin service for real side-by-side startup/memory/native numbers, plus comparison chapter + slides.
- **DRQ-007 — lgtm-quarkus skill:** Already targets latest stable Quarkus + JDK 25 (no retarget). Optional ancillary pin refresh (Maven 3.9.9→3.9.16; evaluate Citrus 4.10.3→5.0.2) is low priority.
- **DRQ-008 — Domain:** Same shipping/order domain used across the user's repos (order/inventory/payment/shipping/notification/review + GraphQL gateway).

- **DRQ-009 — Event serialization (Avro + Apicurio, up front):** ALL Kafka events use Avro with the Apicurio Schema Registry from the start — NOT JSON. Rationale: user directive — do it up front so we never have to retrofit serialization later (historically missed if deferred). `contracts` module owns the `.avsc` schemas (`order-placed.avsc`, `payment-captured.avsc`, `shipment-dispatched.avsc`); Quarkus Avro codegen generates the record classes; producers/consumers use `apicurio-registry-avro` serde. Apicurio registry provided via Quarkus Dev Services (Testcontainers) in dev/test; standalone in Docker Compose (Phase C). Supersedes the planner's Phase-B JSON shortcut.
- **DRQ-010 — payment/shipping services:** Real event-driven choreography processors (NOT the Python stubs). `order.placed` → payment-service emits `payment-captured` → shipping-service emits `shipment-dispatched`. Each Avro over Kafka per DRQ-009.

## Deferrals

_(none yet)_
