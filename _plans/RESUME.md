---
title: RESUME — session state
description: Read this FIRST after a context compaction or restart to resume the build
---

# RESUME — datamesh-reference-arch-quarkus build

## Current state — 2026-10-06 (read this section first)

**Build is complete and public; recent work was a content/tooling hardening pass.**
`main` is clean at `76bf57a` with no open PRs in this repo.

### Done in the 2026-10-05/06 session (all merged)
- **Professional content pass** (#29–#33): voice pass over site, both decks
  (r1.1: 201 = 100 slides, 101 = 17), demo narration, READMEs; demo slides use
  title + subtitle with the script as an 8pt footnote; glossary bold terms;
  new diagrams (Panache patterns, Uni vs imperative, WebSockets.Next, JBang,
  startup paths, Panama, OIDC flow, WebSocket failover, Vert.x/Kafka
  messaging); A1/A3/A5/A6 diagram fixes; analytical-data close. Plan + log:
  [professional-content-pass.md](professional-content-pass.md).
- **New demo**: `demos/demo-panama.sh` (FFM getpid/strlen) — verified.
- **Leyden**: `scripts/compare-quarkus-springboot.sh --aot` (JDK 25 AOT cache,
  both frameworks) — measured once: startup Quarkus 2.05→0.99 s, Spring
  4.02→1.02 s; RSS Quarkus 337→372 MB, Spring 548→446 MB (ch12).
- **CLAUDE.md rules** (#34): load `lgtm-quarkus` AND `lgtm-camel` before any
  code/demo/JBang/dependency change; supported-stable pinned releases only;
  no JBang catalog aliases; never modify JBang or its trust store; Docker
  overrides the skills' Podman defaults.
- **Walkthrough** (#35): per-demo context + Enter pauses, `--list`,
  `--from <demo|actN>`; `--auto` for CI. `demo-jbang-prototype.sh` now runs a
  local `HelloRoute.java` with pinned `//DEPS` (Camel 4.22.1, slf4j-simple
  2.0.20) — no `camel@apache/camel` alias (it pulled GitHub `blob/HEAD`,
  added the snapshot repo, and popped a JBang GUI trust dialog).
- **Skills** (patterncatalyst/lgtm-skills #16, #18–#21): new
  `lgtm-professional-voice` (scanner `scripts/scan.sh`); stable-only rule and
  pinned installs in `lgtm-quarkus`/`lgtm-camel`; corrected `camel-mcp` setup.
- **MCP servers registered (user scope), both connect**:
  `quarkus-agent` = `jbang io.quarkus:quarkus-agent-mcp:1.2.11:runner`;
  `camel-mcp` = `jbang -Dcamel.mcp.transport=stdio org.apache.camel:camel-launcher:4.22.1 mcp`
  (one-time `camel plugin add mcp` already done; `~/.camel-jbang-plugins.json`).
  A new session loads them — use them per CLAUDE.md.

### Walkthrough status (`bash demos/walkthrough.sh --from act4 --with-native --auto`)
| Demo | Result |
|---|---|
| demo-jbang-prototype, demo-continuous-testing, demo-panama | passed |
| demo-native | **passed** (2026-10-06): Mandrel container build 136 s, 141 MB runner, **startup 0.081 s**, `GET /orders` served with no JVM |
| demo-keda-kafka, demo-keda-http (act 5) | **passed** (2026-10-06, #42): notification-service 0→1 on lag and back to 0; graphql-gateway 0→1 with 120/120 GraphQL requests 200 |

### Next steps (in order)
1. ~~Docker Desktop resize~~ — done 2026-10-06 (8 CPUs, ~31 GiB, 252 GB disk).
2. ~~Bootstrap full-size cluster~~ — done 2026-10-06 with `MINIKUBE_CPUS=8`
   (8/8 tiers, 50 pods). The host's global minikube config had `rootless: true`
   left from a podman profile; it is now set to `false` (docker is the default
   here). Build and load the service images with `scripts/load-images.sh`
   before the KEDA demos.
3. ~~Run act 5~~ — done 2026-10-06: demo-keda-kafka and demo-keda-http both
   passed (first end-to-end pass of keda-http) after fixing the interceptor
   port, the GET-vs-POST load, and the scale-from-zero starting state.
4. ~~Record the native result~~ — done 2026-10-06 with the native and AOT
   cache build figures (ch11 Figures 11.6 and 11.7, two new 201 slides,
   footers, deck notes, reconciliation).

### Session rules learned (also in memory)
- Agents never run demos that invoke remote JBang sources; run JBang work
  headless (`env -u DISPLAY -u WAYLAND_DISPLAY`, `JAVA_TOOL_OPTIONS=-Djava.awt.headless=true`, stdin `</dev/null`).
- Don't prune Docker images/named volumes or change Docker Desktop/system
  services without asking. The 2026-10-06 prune removed only anonymous
  volumes (3.3 GB) + build cache (1.1 GB); 8 named volumes kept.
- Voice: senior-engineer audience; run `~/.claude/skills/lgtm-professional-voice/scripts/scan.sh` on touched files.

---

## History (build phases)

**Read this first after any /compact or restart.** Then read
[build-plan.md](build-plan.md) (steps + status table) and
[decisions.md](decisions.md) (DRQ-001…015).

## What this is
Building NEW repo `datamesh-reference-arch-quarkus`: rebuild the Python DataMesh
reference arch (`../datamesh-reference-arch-python`) as Quarkus + Camel. Jekyll
site + runnable examples + demos aligned 1:1 to slides + tutorial + deck + Notion
1-hour talk abstract. Shipping/order domain. Seed code from
`../enterprise-integration-patterns-with-camel/examples/42-ai-mcp/quarkus`.

## How we work (relay + skills)
- **lgtm-relay**: Plan (Opus) → Execute (Sonnet, one agent per independent step,
  parallel where files disjoint) → Validate (Opus). Checkpoint-commit at each step.
- **lgtm-caveman** style ON for user-facing replies (terse). Subagent prompts stay explicit.
- Load the relevant `lgtm-*` skill IN each subagent prompt (subagents don't inherit skills).
- **No AI attribution** on any commit/PR (no `Co-authored-by`, no "Generated with").
- Use `git -C <path>` for all git (never `cd && git`).

## Repo location + git state
- Repo: `/home/rsedor/Dev/datamesh-reference-arch-quarkus`
- Default branch: `main`. **Repo is PUBLIC and live**:
  https://github.com/patterncatalyst/datamesh-reference-arch-quarkus (it was
  already public — no separate "flip" was needed at Step 17).
- Workflow: branch per step → commit (Conventional Commits, no attribution) →
  push → PR → squash-merge to `main`. All phases through Step 14 merged.
- Commit checkpoints per step; commit messages Conventional Commits, no attribution.

## Progress
- **Phase A — DONE** (steps 1–4): plan + decisions committed; Jekyll scaffold
  (builds 0 errors); CLAUDE.md + PRD + reconciliation; new `lgtm-docker-stack`
  skill created.
- **Skills sync — DONE**: `lgtm-skills` repo is source of truth. Added
  lgtm-docker-stack + lgtm-github no-attribution rule; PR
  patterncatalyst/lgtm-skills#13 MERGED to main; `~/.claude/skills` in sync
  (`scripts/install-all.sh --dry-run` clean). See memory
  reference_lgtm_skills_repo.
- **Phase B — DONE + VALIDATED** (steps 5–7): reactor `examples/` + shared
  `domain-model`/`contracts` (Avro codegen 3 events + gRPC) + all 8 modules
  (order, inventory, payment, shipping, notification, review, graphql-gateway,
  ai-mcp-service). `mvn verify -f examples/pom.xml` GREEN: 21 tests, 0 fail,
  0 error (timezone pin baked into parent pom — no -D needed).
  Opus validation caught + fixed real defects: inventory `@Blocking` on gRPC
  handler (was BlockingOperationNotAllowedException), graphql un-mockable
  `@GrpcClient` (rewired to in-process mock gRPC server), test-isolation +
  route-assertion fixes. DRQ-009 config-verified on all 6 Kafka channels
  (explicit Avro serde; autodetection proven to silent-fall-back to JSON).
  DEF-001 resolved (langchain4j-bom 1.20.2 pinned → convergence).
  Decisions added: DRQ-009, DRQ-010; DEF-001 (resolved-pin, Ollama IT pending),
  DEF-002 (Avro wire-byte assertion pending real broker in Phase C).
- **Phase C — DONE + VALIDATED** (steps 8–9). Merged to main via PR (lgtm-github
  per-phase flow). Decisions added: DRQ-011 (Phase C infra choices).
  - **Step 8 (docker):** root `compose.yaml` live-validated healthy (postgres:18,
    apache/kafka-native:4.2.0, apicurio-registry:3.1.7, otel-lgtm:0.8.1;
    LGTM always-on baseline; ollama + kafka-ui profiled). `.env` pins tags ==
    Dev Services tags == IT Testcontainers tags. `%prod` env-driven config in all
    services (`${KAFKA_BOOTSTRAP_SERVERS}`/`${APICURIO_REGISTRY_URL}`/`${JDBC_URL}`);
    Dev Services image-names pinned. Multi-stage UBI Containerfiles (order test-built).
    `.devcontainer/` (JDK25/Maven3.9.9, DooD socket, joins `datamesh` network).
    `.dockerignore` added. **DEF-002 RESOLVED** — `OrderPlacedAvroWireIT` byte-asserts
    Avro magic byte, green in default `mvn verify`.
  - **Step 9 (minikube):** `scripts/` substrate (bootstrap + Strimzi/CNPG/KEDA/
    Apicurio/LGTM/Istio/Kiali, all flags ON per DRQ-011; KEDA HTTP add-on 0.15.0).
    `k8s/` kustomize (base + minikube overlay) for order/notification/graphql-gateway
    (real in-cluster DNS, securityContext, local images). `k8s/keda/` ScaledObject
    (Kafka-lag → notification-service, scale-from-zero) + HTTPScaledObject
    (graphql-gateway). CRD-schema-validated (KEDA 2.19.0 / http-add-on 0.15.0); NOT
    brought up on a live cluster (heavy — deferred to a real minikube run).
  - **Validation:** full `mvn verify -f examples/pom.xml` GREEN — 22 tests, 0 fail,
    0 error (21 Phase-B + DEF-002 IT). Ran with compose down + test-port overrides.
- **Phase D — DONE + VALIDATED** (steps 10–13), all merged to `main` via PRs #4–#10:
  - **Step 10 demos:** full `demos/` suite + `walkthrough.sh`. Step-10 review findings
    F1–F7 all resolved: F1/F1b (Avro `SERIALIZABLE_PACKAGES` via `JAVA_TOOL_OPTIONS`),
    F2 (order→inventory gRPC canonical **9000** + `k8s/base/inventory-service.yaml`),
    F3 (import.sql %prod — won't-fix/documented), F4/F5/F6/F7 (LOW, fixed).
  - **Step 11 chapters:** 16 tutorial chapters (`_docs/`) + 5 parts (`_parts/`), each
    ≥2000 prose words; includes DRQ-015 three-engines (ch13), AI+rules (ch14), and the
    **Spring Boot twin** `examples/spring-boot-compare` (DRQ-006, JVM-only, measured:
    Quarkus 1.54s/314MB vs Spring Boot 3.21s/494MB via `scripts/compare-quarkus-springboot.sh`).
  - **Step 12 diagrams:** 36 paired SVG+Excalidraw in `assets/diagrams/` (27 reused from
    the Python repo relabeled to the Quarkus/K8s stack, 5 adapted, 4 new), terracotta house
    style (`scripts/svglib.js`); embedded across the chapters.
  - **Step 13 decks:** `presentation/datamesh-101/` (17 slides) + `datamesh-201/` (81, with
    one-slide-per-demo + large appendix), pptxgenjs, Red Hat house style.
- **Phase E — in progress**, merged to `main`:
  - **Step 14 (DONE):** `tooling/newman/` Postman collection (49 assertions) + runner, and
    `tooling/load/load-orders.sh` (hey). PRs #11–#13.
  - **Step 15 (DONE):** Notion talk abstract — private draft, reframed as a dual "showroom"
    (teaches data mesh + demonstrates Quarkus; NO Quarkus background assumed). Both the
    Python and Quarkus data-mesh abstracts linked in the Notion Abstracts index. Open: moving
    the Quarkus page out of private-draft needs the `mcp__notion__notion-move-pages` permission
    (or a manual drag). See memory `reference_datamesh_quarkus_talk_abstract`.
  - **Pre-publish sweep (DONE):** reactor `mvn verify` green (35 tests, DEF-002 IT intact),
    `jekyll build` clean, live newman 37/37 + GraphQL REST+gRPC federation at 9000. 3 defects
    found + fixed: demo gRPC 9001→9000 drift (#12), `@Consumes`-on-GET 415 (#12 + #13
    WILDCARD + genuine `HttpClient` regression test), inventory stale-volume (documented, not
    a code bug — fresh `%prod` db POST /stock works).
- **Still open:** DEF-001 Ollama behavioral IT (needs Ollama running); live minikube
  bring-up of the step-9 substrate (scripts authored + schema-checked, not run); the Notion
  page move (permission); **Step 16** (optional lgtm-quarkus pin refresh).
- **IN FLIGHT (current session):** a critical re-evaluation via lgtm-relay — code review,
  site/README/markdown review, and a full test-suite plan (unit + integration + load + a
  single `scripts/run-all-tests.sh` runner). Findings to be triaged + executed.

## Settled scope answers (do not re-ask)
- Repo: local-first, PUBLIC, push only after approval.
- Container toolchain: docker (lgtm-docker-stack), no podman.
- Versions: Quarkus 3.39.5, JDK 25, platform-aligned Camel, langchain4j 1.14.1.
- OIDC demo: attempt live (Keycloak Dev Service), fall back to deferred + log in decisions.md.
- Spring Boot comparison: ONE runnable Spring Boot twin service + compare chapter/slides.
- Notion: 1-hour talk abstract in user's abstract format (Step 15).

## Checkpoint discipline for the rest of the run
Commit after every step that leaves the tree coherent; update the build-plan.md
status table as steps land; keep this RESUME.md current so a fresh session can
pick up without re-deriving progress.
