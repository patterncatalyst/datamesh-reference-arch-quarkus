---
title: Professional content pass
description: "Plan and progress log for the site/deck/diagram professionalization pass (branch docs/professional-content-pass)"
render_with_liquid: false
---

# Professional content pass

Branch: `docs/professional-content-pass`. Relay: Opus plan → Sonnet execute → Opus validate. No approval gate between phases (standing user instruction). Executors do not commit; the coordinator commits each step after each wave. Conventional Commits, no trailers. PR via lgtm-github at the end.

## Status

| Step | Owner files | Wave | Status |
|------|-------------|------|--------|
| P  | this plan | 0 | done |
| A  | `scripts/make-quarkus-diagrams.js`, new `scripts/make-appendix-diagrams.js`, figures 11,13,15–18,20,21 + new 16-websocket-failover, 20-vertx-in-memory, 20-kafka-messaging | 1 | done (3d97e38) |
| B  | new `scripts/make-capability-diagrams.js`, figures 11-panache-patterns, 11-uni-vs-imperative, 11-websockets-next, 11-jbang-tooling, 11-startup-paths, 11-panama-ffm, 11-oidc-token-flow | 1 | done (8002cb1) |
| C  | hand-coded / python-sourced SVGs (01-monolith-to-mesh, 02-capstone-data-mesh, 02-principles-to-pieces, 10-value-*, 05/06/07/08 scan), `assets/diagrams/README.md` | 1 | done (ab62c4e) |
| D  | new `demos/demo-panama.sh`, `demos/jbang/PanamaFfm.java`, `demos/walkthrough.sh`, `demos/README.md`, `demos.html`, `README.md` | 1 | done (c80f512) |
| E  | `scripts/compare-quarkus-springboot.sh` (`--aot`), `_docs/12-quarkus-vs-spring-boot.md` | 1 | done (828ce7e, a539cfc) |
| S1 | `_docs/00`–`05` (incl. both `01-*`), `_parts/foundations.md`, `_parts/data-products.md` | 1 | done (0213bde) |
| S2 | `_docs/06`–`10`, `_parts/operating-the-mesh.md`, `_parts/lessons-and-close.md` | 1 | done (70b76ce) |
| S3 | `_docs/16`–`21`, `_parts/appendices.md` | 1 | done (3ae8545) |
| S4 | `index.html`, `setup.html`, `_includes/*`, `demos/demo-*.sh` (except panama), `examples/order-service/README.md`, `k8s/keda/README.md` | 1 | done (c3133d1, 5ae441a) |
| S5 | `_docs/11`, `_docs/13`, `_docs/14`, `_parts/quarkus-deep-dive.md`, `_plans/reconciliation.md` | 2 | done |
| F1 | both `deck-lib.js` (identical), `build-deck.js`, `build-101.js`, `presentation/README.md`, pptx r1.1 | 2 | done |
| S6 | `examples/*/README.md`, `k8s/README.md`, `k8s/istio/README.md`, `10-trusted-supply-chain` | 2 | done |
| F2 | build + visual QA + acceptance checks + PR | 3 | done |
| V  | Opus validation against acceptance criteria | 3 | done — 1 repair round (10 defects fixed) |

## Findings that shape the plan

- No Ruby on host: Jekyll build runs in docker `ruby:3.3` (F2). CI also builds on push.
- Stale deck notes vs site: A1 notes / diagram 16 footer say per-replica fan-out is "recommended, not deployed" — ch16 footer + d4bed41 say implemented and verified with 2 replicas. Slide "Istio" notes say injection via pod annotation — site says pod-template label. Slide "mTLS" notes say v2 order-service + DestinationRule/VirtualService don't exist — `k8s/istio/order-service-v2.yaml` etc. exist and are verified.
- `deck-lib.js` is duplicated byte-identically in both deck dirs — keep identical.
- Both `raster.js` hardcode the absolute `assets/diagrams` path.
- Shell is zsh — wrap multi-file grep loops in `bash -c`.
- Capability count is ten today ("nine" is a miscount); becomes twelve with Leyden AOT cache + Panama.

## Approach

1. Diagrams split across three files to avoid clobbering: A owns `make-quarkus-diagrams.js` (+ new `make-appendix-diagrams.js`); B owns new `make-capability-diagrams.js`; C owns hand-coded/python-sourced SVGs. Nobody edits `scripts/svglib.js` — copy small helpers (`save`, `wrap`, `curveArrow`) locally.
2. One executor (F1) owns all deck files, sequentially, after diagram names are fixed and Panama/Leyden results exist.
3. Site wording split by chapter ranges (S1–S4); ch11/12/13–14 go to the executors that own their new content (E, S5).
4. Wording rules (section R) written once, quoted in every executor prompt with lgtm-presentation + lgtm-tutorial conventions.
5. Executors don't commit; coordinator commits per step.

Rejected: one executor for everything (too long); parallel edits to one builder file (clobbering); renaming `02-capstone-data-mesh`/`04-capstone-contracts` files (touches raster keys, decks, site for no reader gain — change visible labels only); divider lines between bullets (pptxgenjs can't measure paragraph heights — use paragraph spacing + shorter bullets); Quarkus REST endpoint for Panama (a JBang script is smaller and verifiable on bare JDK 25); Quarkus's own AOT integration for the comparison (asymmetric vs Spring — use plain JDK 25 flags on both; mention the Quarkus property only after confirming its name); dropping "DEMO n of N" counters (keep, renumber to 19).

## R. Wording rules (quote into every executor prompt)

**R1 — remove outright** (prose, slide text, notes, diagram labels, `demos/*.sh` comments and narrate/info/step text): honest/honestly/honesty; frankly; plainly ("stated plainly", "noted plainly"); "clear account(ing)", "plain accounting", "plain caveat"; "not hidden", "rather than hidden/hiding"; "worth noticing/stating/noting/naming"; "the thing to land"; "with your finger"; "teaching spine"; "stated precisely"; "showroom"/"doubles as a showroom"; "not a toy (snippet)"; "real, not synthetic"; "in disguise"; "masquerading"; "no ambiguity about"; "nothing invented"; "made real"; ", realized" as a title device; crucially; literally; simply; genuine/genuinely; "by name"; "the vocabulary …".

**R2 — reduce, keep only when meaningful:** "actually" (only where it contrasts reality with assumption); "deliberately" (only when the intent matters to the reader); "not just/not merely" (only when the contrast prevents a likely misreading); keep "silently" for real software behavior (e.g. serde silently falling back to JSON); "lie" only for a machine reporting a wrong value (lgtm-tutorial person-or-machine test).

**R3 — rewrite artificial phrasing** into what an engineer would say: meta-commentary about the deck/book ("the vocabulary the rest of this deck uses by name", "This is the deck's whole structure in one picture", "Promise the audience"); framing devices ("Cost and benefit, stated as the same fact", "Let the architecture correct against reality"); defensive contrasts ("a genuine gRPC client over HTTP/2, not a REST call in disguise"); build-history language ("step-9 substrate", "Phase", "PR #"); "this reactor" → "this project". Example: slide 6 caption → "Each principle maps to Kubernetes building blocks: namespaces, Deployments and CRDs, operators, and mesh and admission policy."

**R4 — minikube / capstone.** KEEP literal identifiers: `capstone.order.v1` etc., `capstone/inventory/v1/inventory.proto`, file names `02-capstone-data-mesh`/`04-capstone-contracts`, `--with-minikube`, `k8s/overlays/minikube`, `minikube` CLI commands, the `datamesh` profile, script internals/output reporting tool state. When prose must name the tool: code-format it (`` `minikube` ``) and pair it with "a local single-node Kubernetes cluster" on first mention per chapter. Everywhere else (prose, slide text, notes, captions, alt text, diagram labels): "minikube" → "Kubernetes"/"the local Kubernetes cluster"; "capstone" → "full project example" (or "reference architecture" where it reads better). Paraphrase (don't quote) the ch21 line-135 Javadoc ("…out of scope for this capstone slice").

**R5 — presentation (lgtm-presentation):** thick speaker notes on every slide (notes count = slide count); no positional/build language in slide-visible text ("section 05", "step-9", "slide N") — refer to concepts by name; logo/footer on every content slide; bump to r1.1 (`OUT` filenames; `git rm` r1.0 pptx).

**R6 — site (lgtm-tutorial):** figures via `{% include excalidraw.html file="…" alt="…" caption="Figure N.x — …" %}` numbered in order of appearance; quote front-matter descriptions containing a colon; every touched chapter keeps its verification-status footer, which states exactly what was run — new and not run = `unverified`/conceptual; wrap literal `{{ }}`/`{% %}` in raw tags.

**R7 — diagram legibility:** svglib palette/grammar; 1180px wide, ≤500 tall preferred (≤560 hard); text in boxes ≥14px, headings 16–18px; ≤~12 words per box; every arrow starts and ends on a box edge or another arrow; emit `.svg` + `.excalidraw`; curved paths also emit an excalidraw arrow element with ≥3 points (local `curveArrow` helper on `s._base`).

## Steps

### Wave 1 (parallel, disjoint files)

**A. Existing-figure edits** — owns `scripts/make-quarkus-diagrams.js` + new `scripts/make-appendix-diagrams.js`. Run both; validate (`JSON.parse` every `.excalidraw`; SVG well-formed).
1. 11-capability-tour: 12 cards, 6×2, ~1180×470; name 15px, desc 13px, anchor 12px; drop "ANCHORED TO" labels; title "Twelve Quarkus and JDK 25 capabilities, demonstrated"; cards/anchors: Panache—order-service; gRPC—inventory-service; GraphQL—graphql-gateway; Reactive Messaging—order-service; WebSockets.Next—notification-service; Vert.x: Uni + imperative—inventory-service; Continuous testing + Dev Services—order-service; Native image—demo-native.sh; JDK AOT cache (Leyden)—compare-quarkus-springboot.sh --aot; OIDC—review-service; JBang—demos/jbang; Panama FFM—demo-panama.sh. Footer without "toy"/"reactor".
2. 13: footer without "honest-limits".
3. 15: repair path ends on last exec row bottom edge (`… - execGap`); emit excalidraw arrow.
4. 16-websocket-scaling: redesign 1180×≤520. order-service → "publish (Avro)" → `order.placed` topic. Topic → persistence consumer box (shared group `notification-service`, one replica per partition → Postgres). Three arrows from three distinct x on the topic bottom edge → three replica boxes, each "push consumer, group `notification-push-<pod>`" + "OpenConnections (this JVM)", label "every replica receives every event". Arrows DOWN from each replica → two client pills, label "push". Note: "Each client connects once through the Service and stays on that replica." Footer: "Implemented: OrderPlacedConsumer (shared group) + OrderPlacedPushConsumer (per-replica group); verified with two replicas on Kubernetes."
5. 17: title "Gotchas: symptoms and the fixes that landed".
6. 18: replace dangling repair arrow with a curve from VALIDATE bottom edge → EXECUTE bottom edge (+ excalidraw element), label centered under curve.
7. 20-inmemory-vs-kafka: redesign as side-by-side ~1180×500. Columns "In-memory / Vert.x (one JVM)" | "Kafka (cluster)". Rows: scope; durability; ordering; how it scales (up across cores vs out across partitions/replicas); failure (lost on crash vs replay from offset); use here (tests vs `%prod`). Bottom band: "Same @Incoming/@Outgoing code; only connector config changes."
8. 21-three-engines-compare: redesign ~1180×480; header 18px, row labels 16px bold, cells 16px. Columns Kafka choreography | Camel orchestration | Quarkus Flow. Rows: Who owns the sequence (No one | The route | The workflow document); Coupling (Loose, via topics | Central, in Java | Central, in a document); Failure handling (Idempotent redelivery | Exceptions propagate | Task-level, declarative); Debugging (Trace across services | One route, one log | Inspect the task graph); Logic lives in (Each consumer | Route code | Workflow definition).
9. New in `make-appendix-diagrams.js`:
   - 16-websocket-failover: three panels L→R. (1) Normal: client ↔ replica 2. (2) Replica 2 fails: socket closes; client backs off with jitter (1s, 2s, 4s…). (3) Recover: Service routes reconnect to replica 1 or 3; it already receives every event via its own push group; client re-fetches missed events via `GET /notifications`. Footer: "Client reconnect/backoff is a recommended pattern; WsNotificationClient does not implement it (unverified)."
   - 20-vertx-in-memory: one JVM box: event-loop threads (~2× cores) + worker pool; Vert.x event bus with send / publish / request-reply; producers (`Emitter`/`@Outgoing`) and consumers (`@Incoming`/`@ConsumeEvent`); "scales up with cores; no network hop or wire serialization; back-pressure via Mutiny"; limits: one JVM, not durable, no replay. Footer: "This project uses the in-memory connector in shipping-service tests; event-bus usage shown is illustrative."
   - 20-kafka-messaging: producers → topic partitions P0–P3; consumer group A replicas owning partitions; group B reading independently (fan-out); retention + offsets for replay; Apicurio for schemas; "scale out: consumers up to the partition count; KEDA scales on lag".

**B. New capability figures** — owns new `scripts/make-capability-diagrams.js`. Run + validate. Confirm WebSockets.Next/legacy and execution-model claims with `quarkus_searchDocs` (or Quarkus guides) before drawing.
1. 11-panache-patterns: left "Active record (this project)": `Order extends PanacheEntityBase`, `Order.findById(id)`, `order.persist()`, flow resource → entity → DB. Right "Repository": `OrderRepository implements PanacheRepository<Order>` injected into resource, flow resource → repository → entity → DB. Band: "Same Hibernate ORM and SQL. Repository: easier to mock and layer. Active record: less code. Spring Data JPA is the twin's repository equivalent."
2. 11-uni-vs-imperative: imperative lane `StockDto get(sku)` → worker thread, blocking fine. Reactive lane `Uni<CheckStockResponse> checkStock(req)` → event loop, must not block; `@Blocking` moves to worker. Uni = lazy single async result, runs when subscribed; `onItem().transform()`, `onFailure().retry()`. Footer: "The signature and @Blocking/@NonBlocking (or @RunOnVirtualThread) choose the thread."
3. 11-websockets-next: left legacy `quarkus-websockets` (Jakarta WebSocket on Undertow): `@ServerEndpoint`, `Session`, callback API. Right `quarkus-websockets-next` (Vert.x): `@WebSocket(path)`, `@OnOpen`/`@OnTextMessage` returning values or `Uni`/`Multi`, execution model from signature, injectable `OpenConnections`, `@WebSocketClient`. Bottom band: Kafka `@Incoming` → `OpenConnections.listAll()` → `sendText`, per-replica group feeding each replica.
4. 11-jbang-tooling: single `.java` with `//DEPS` + `//JAVA 25` → jbang → resolves deps from Maven Central, downloads a JDK if missing, caches build; app catalog: `camel@apache/camel`, Quarkus CLI; uses here: HelloRoute.java, WsNotificationClient.java, PanamaFfm.java.
5. 11-startup-paths: three lanes. JVM: load, link, interpret, JIT warm-up. JVM + AOT cache (JDK 25, Project Leyden, JEPs 483/514/515): training run `-XX:AOTCacheOutput` → `app.aot`; production `-XX:AOTCache`; same jar, full JVM, JIT active. Native image (GraalVM/Mandrel): closed-world build (minutes), no JVM, reflection config. Qualitative rows: build cost, startup, memory, compatibility, peak throughput. NO numbers.
6. 11-panama-ffm: Java → `Linker.nativeLinker()` → `defaultLookup()` (libc) → `downcallHandle(FunctionDescriptor)` → `getpid`/`strlen`; `Arena` allocates off-heap `MemorySegment` (C string) freed when arena closes; contrast with JNI (C glue, headers, separate native build); `--enable-native-access` note.
7. 11-oidc-token-flow: Dev Services starts Keycloak (realm `quarkus`; alice = admin+user; bob = user), sets `auth-server-url`. (1) client POST token endpoint (password grant, client `quarkus-app`) → (2) JWT access token → (3) `DELETE /reviews/{id}` with `Authorization: Bearer` → review-service: quarkus-oidc verifies signature vs Keycloak JWKS, issuer, expiry → `@RolesAllowed("admin")`. Outcomes box: no token → 401; bob → 403; alice → 204, then GET → 404. Note: "Password grant for the demo only; browser apps use authorization code flow."

**C. Hand-edited/python-sourced figures** — owns those `.svg`/`.excalidraw` + `assets/diagrams/README.md`.
1. 01-monolith-to-mesh (both files, identical geometry): Domain A rect x620 w130 text cx685; B x770 w130 cx835; C x920 w130 cx985; arrows e1177/e1179 start x750/x900 (w20); excalidraw ids e1147/1157/1167 rects, e1149–e1155/e1159–e1165/e1169–e1175 text; outer 600–1070 unchanged.
2. 02-capstone-data-mesh (both): title → "Full project example — a data mesh on Kubernetes".
3. 02-principles-to-pieces.svg: "minikube — the substrate…" → "Kubernetes — the substrate where all four principles run"; title → "The four principles on Kubernetes".
4. 10-value-*.svg: "— realized" → "— in practice"; "REALIZED BY" → "IMPLEMENTED BY".
5. Scan other hand-coded SVGs (08-*, 05-api-implementations, 06-service-mesh, 07-keda-*) for R1–R4.
6. `assets/diagrams/README.md`: list the three generator scripts and their figures.

**D. Panama demo** — owns new `demos/demo-panama.sh`, new `demos/jbang/PanamaFfm.java`, `demos/walkthrough.sh`, `demos/README.md`, `demos.html`, `README.md` (R-rules apply to these).
- PanamaFfm.java: `///usr/bin/env jbang "$0" "$@" ; exit $?`, `//JAVA 25+`, `//JAVA_OPTIONS --enable-native-access=ALL-UNNAMED`; `getpid` via `FunctionDescriptor.of(JAVA_INT)`; `strlen` via `FunctionDescriptor.of(JAVA_LONG, ADDRESS)` with `Arena.ofConfined().allocateFrom(s)`; prints `PANAMA_GETPID=<n> JVM_PID=<n>` and `PANAMA_STRLEN=<n> JAVA_LENGTH=<utf8 bytes>`.
- demo-panama.sh: follow `demo-jbang-prototype.sh` (`_demo.sh`, jbang preflight + install hint); bare tier; assert both pairs equal; fail loudly otherwise. RUN it; record real output.
- walkthrough ACT4: add `panama` as default (ungated). Counts 18→19: walkthrough.sh (lines ~19, 133, 266), demos/README.md (matrix bare tier + ~line 135), demos.html (~line 16), README.md (~lines 58, 95). Add a demos.html card. Fix the "Async spine" card title. R4: "step-9 minikube substrate" → "the local Kubernetes cluster (`scripts/bootstrap.sh`)"; flag stays.

**E. Leyden / AOT comparison** — owns `scripts/compare-quarkus-springboot.sh`, `_docs/12-quarkus-vs-spring-boot.md` (incl. R-sweep of ch12). Feasible locally (Temurin 25.0.3, docker, mvn).
- Add `--aot`; default stays JVM-only. Quarkus training: `java -XX:AOTCacheOutput=target/order-service.aot … -jar quarkus-run.jar`; wait for started line → SIGTERM → `wait` (cache assembled at exit); assert `.aot` exists. Spring: `java -Djarmode=tools -jar app.jar extract --destination target/extracted` (nested jars can't be cached), same training on `target/extracted/*.jar`. Measured: `-XX:AOTCache=<f> -XX:AOTMode=on` (fail loudly if unusable). Report startup (wall + self-reported), RSS, cache size (`du -h`); keep `<measured-on-run>` placeholder rule. RUN `--aot` for real.
- ch12: add "Like-for-like with the JDK 25 AOT cache (Project Leyden)": method, measured table, caveats (same JDK + classpath required, mmapped cache affects RSS, single run); link to Figure 11.5; footer reflects exactly what ran.
- Hand numbers (or "not measured") to F1 via scratchpad note `aot-results.md`. Not run = unverified.

**S1. Site wording 1** — `_docs/00-index.md`, `01-concepts.md`, `01-data-architectures.md`, `02-kubernetes-substrate.md`, `03-services-and-data-products.md`, `04-contracts-and-catalog.md`, `05-data-planes.md`, `_parts/foundations.md`, `_parts/data-products.md`. Ch02 keeps `minikube` code-formatted in setup/substrate; line 13 "capstone diagram" → "full-project diagram"; update Fig 2.1 alt.

**S2. Site wording 2** — `_docs/06`–`10`, `_parts/operating-the-mesh.md`, `_parts/lessons-and-close.md`. Ch10 title → "Summary: the four principles in practice".

**S3. Site wording 3** — `_docs/16`–`21`, `_parts/appendices.md`. Ch16: Fig A1.1 (redesigned, new alt) + new section "Replica failure and client reconnect" with Fig A1.2 `16-websocket-failover` (conceptual, unverified). Ch20: new section "Vert.x in-memory messaging on its own" with A5.1 `20-vertx-in-memory`, then A5.2 `20-kafka-messaging`, then A5.3 `20-inmemory-vs-kafka` (renumber); `@ConsumeEvent` code labeled illustrative. Ch21: shorten A6.1 alt; paraphrase line-135 quote.

**S4. Site shell/scripts/READMEs** — `index.html`, `setup.html`, `_includes/*`, every `demos/demo-*.sh` except panama (comments + narrate/info/step strings only; no logic; `bash -n` each), `examples/order-service/README.md`, `k8s/keda/README.md`. Move removed-slide content into READMEs if absent: `OrderPlacedAvroWireIT` magic-byte assertion + `SERIALIZABLE_PACKAGES` → order-service README; `interceptor.replicas.waitTimeout` 180s rationale → KEDA README.

### Wave 2

**S5. Ch 11, 13, 14** (needs B, D, E) — owns `_docs/11`, `_docs/13`, `_docs/14`, `_parts/quarkus-deep-dive.md`, `_plans/reconciliation.md`. Ch11: "nine" → "twelve"; Fig 11.1 alt/caption. Sections/figures: Panache (Fig 11.2; illustrative `PanacheRepository` example); gRPC; GraphQL; Reactive Messaging; WebSockets.Next (Fig 11.3; legacy comparison + Kafka scaling link to A1); Vert.x with new subsection "Uni and imperative: what the signature tells Quarkus" (Fig 11.4); Continuous testing; "Startup: native image and the JDK AOT cache" (Fig 11.5; link to ch12 AOT section); OIDC (Fig 11.6); JBang (Fig 11.7); new "Panama: calling native code through the FFM API" (Fig 11.8; code from real `PanamaFfm.java`, demo output quoted). Update "What you learned" + footer (Panama verified only if D ran it; AOT per E; native still not exercised). Reconciliation entries for every new claim.

**F1. Decks** (needs A–E) — owns both `deck-lib.js` (identical), `build-deck.js`, `build-101.js`, `presentation/README.md`, pptx. r1.1: `Datamesh-201-Quarkus-r1.1.pptx`, `Datamesh_101-r1.1.pptx`; `git rm` r1.0; README filenames + "~100 slides".

### Wave 3

**F2. Build + visual QA:**

```bash
cd /home/rsedor/Dev/datamesh-reference-arch-quarkus
node scripts/make-quarkus-diagrams.js && node scripts/make-capability-diagrams.js && node scripts/make-appendix-diagrams.js
for d in presentation/datamesh-201 presentation/datamesh-101; do (cd $d && npm install && node raster.js); done
(cd presentation/datamesh-201 && node build-deck.js); (cd presentation/datamesh-101 && node build-101.js)
QA=$SCRATCH/qa; mkdir -p $QA
soffice --headless --convert-to pdf --outdir $QA presentation/datamesh-201/Datamesh-201-Quarkus-r1.1.pptx presentation/datamesh-101/Datamesh_101-r1.1.pptx
pdftoppm -png -r 80 $QA/Datamesh-201-Quarkus-r1.1.pdf $QA/d201; pdftoppm -png -r 80 $QA/Datamesh_101-r1.1.pdf $QA/d101
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/tmp/bundle -v "$PWD":/srv/site -w /srv/site ruby:3.3 bash -c 'bundle install && bundle exec jekyll build'
```

Eyeball every new/changed slide (diagram legibility, subtitle vs body overlap, 8pt demo ref vs page number/logo, bold leads, glossary overflow, monolith-to-mesh containment). Run acceptance checks. Push, `gh run watch`, open PR `docs: professional content pass for site, decks, and diagrams`.

Commit scopes: `fix(diagrams)` (A, C), `docs(§11)` (B, S5), `feat(demo)` (D), `feat(compare)` + `docs(§12)` (E), `docs(site)` (S1–S4), `docs(deck)` (F1).

## Deck spec (F1)

**deck-lib.js (both copies identical):**
- `head(s, eyebrow, title, {subtitle})`: with subtitle, title h 0.6in; subtitle y 1.36, h 0.4, 17pt, `F.body`, `C.gray`.
- New `addDemoRef(s, ref)`: x 1.6, y PH−0.47, w 7.5, h 0.25, **8pt**, `F.mono`, `C.gray2`, text `"Demo script: " + ref`.
- `diagramSlide`/`contentSlide`/`codeSlide`/`tableSlide` accept `subtitle` + `demoRef`; with subtitle shift body ~0.2–0.25in (diagram y0 2.05 maxH 4.05; bullets y 2.15; code py 2.1 ph −0.25; table ty 2.15).
- `addBullets`: `b.lead` = bold run (`C.ink`) in the same paragraph; paragraph props on first run, `breakLine` on last. Spacing: top level `paraSpaceAfter` 14, `paraSpaceBefore` 4; lvl1 8.
- New `glossarySlide({eyebrow, title, terms:[{term, def}], notes})`: two columns x 0.7 / 6.85, w 5.8, y 1.85, h 4.9; term `F.head` bold 15pt `C.ink` (`paraSpaceAfter` 2); def `F.body` 13pt `C.body` (`paraSpaceAfter` 14); left column gets `ceil(n/2)`.

**Demo-titled slides** (old # → title | subtitle | demoRef):

| Old # | Title | Subtitle | demoRef |
|---|---|---|---|
| 9 | Panache and REST: the template data product | One entity, one resource, one gRPC call, one event | `demos/demo-order.sh` |
| 11 | gRPC typed contracts | Generated at build time | `demos/demo-grpc.sh` |
| 12 | GraphQL: one query, two protocols | REST and gRPC resolved behind one endpoint | `demos/demo-graphql.sh` |
| 13 | Reactive and imperative on one reactor | Two execution models in the same JVM | `demos/demo-reactive-vertx.sh` |
| 14 | WebSocket push from Kafka | Clients receive only committed events | `demos/demo-websocket.sh` |
| 15 | Prototyping with JBang | A Camel route without a Maven module | `demos/demo-jbang-prototype.sh` |
| 16 | Continuous testing | Tests rerun on every save, against Dev Services | `demos/demo-continuous-testing.sh` |
| 19 | Avro on the wire | Verified at the byte level | `demos/demo-kafka.sh` |
| 29 | All three engines, back to back | Choreography, Camel, and Quarkus Flow on one domain | `demos/demo-orchestration-styles.sh` |
| 32 | Single-shot classification | One LLM call, outside the tool-calling limitation | `demos/demo-ai-classify.sh` |
| 33 | The AI and rules showcase | The same decision from both orchestration paths | `demos/demo-ai-triage.sh` |
| 34 | Camel EIP routing, tested in isolation | Content-based router verified independently of tool calling | `demos/demo-camel-integration.sh` |
| 35 | Tool calling through the MCP server | The working path alongside a known limitation | `demos/demo-ai-mcp.sh` |
| 43 | Scaling on Kafka lag | Zero to N replicas and back on Kubernetes | `demos/demo-keda-kafka.sh` |
| 46 | Scale to zero on HTTP | The KEDA HTTP add-on wakes graphql-gateway on demand | `demos/demo-keda-http.sh` |
| 52 | One request, one distributed trace | REST, gRPC, and Postgres spans in Tempo | `demos/demo-tracing.sh` |
| 55 | OIDC with live bearer tokens | 401, 403, and 204 against a Dev Services Keycloak | `demos/demo-oidc.sh` |
| 57 | Native executable: no JVM | order-service compiled ahead of time with Mandrel | `demos/demo-native.sh` |
| 64 | The five-act walkthrough | One presenter script runs every demo | `demos/walkthrough.sh` |
| new | Panama FFM in practice | getpid() and strlen() from libc | `demos/demo-panama.sh` |
| new | With the JDK 25 AOT cache on both | — | `scripts/compare-quarkus-springboot.sh --aot` |

**Bold leads:** any bullet opening with a named subject gets `lead` — e.g. **graphql-gateway**'s GatewayApi…, **inventory-service** answers…, **notification-service**'s /ws/notifications…, **demos/jbang/HelloRoute.java** is…, **mvn quarkus:dev**…, **order-service** publishes…, **payment-service**…, **notification-service** also…, **Act 1 — choreography:**…, **ai-mcp-service**'s OrderClassifierRoute…, **review-service** added…, **KEDA core** scales…, **ACT 1 — Data products & protocols:**…; matrix bullets lead = script name. Trim every top-level bullet to ≤2 lines; detail → notes.

**Final 201 order (~100 slides):**
1 Title · 2 Agenda (notes: correct section count) · 3 Div 00 · 4 Four principles · 5 Reference architecture · 6 From principles to Kubernetes and Quarkus pieces (R3 caption) ·
7 Div 01 (sub: "Twelve capabilities, each backed by running code in this project.") · 8 **Twelve capabilities demonstrated** · 9 Panache and REST · 10 NEW Panache: active record or repository [11-panache-patterns] · 11 Panache active record in order-service (code; retitled) · 12 gRPC · 13 GraphQL · 14 NEW Uni and imperative handlers [11-uni-vs-imperative] · 15 Reactive and imperative on one reactor · 16 NEW WebSockets.Next vs. Jakarta WebSockets [11-websockets-next] · 17 WebSocket push from Kafka · 18 NEW JBang as environment tooling [11-jbang-tooling] · 19 Prototyping with JBang · 20 Continuous testing · 21 NEW Three ways to start a Java service [11-startup-paths] · 22 NEW Panama: native calls without JNI [11-panama-ffm] · 23 NEW Panama FFM in practice (code) ·
24 Div 02 · 25 Where analytical sourcing would plug in · 26 Avro on the wire · 27 Runtime vs. discovery contracts · 28 Avro schema code · 29 "The full contract picture" ·
30 Div 03 · 31 Three coordination shapes · 32 Engine 1 (heading "Trade-off") · 33 Engine 2 · 34 Engine 3 · 35 When to reach for which · 36 All three engines ·
37 Div 04 · 38 Ollama classifies, Drools decides · 39 Single-shot classification · 40 AI and rules showcase · 41 Camel EIP routing · 42 Tool calling via MCP ·
43 Div 05 · 44 Same workload, same JVM · 45 "Startup and memory on the JVM" · 46 NEW With the JDK 25 AOT cache on both (table) — OMIT if E produced no numbers; never placeholders on a slide ·
47 Div 06 · 48 Three planes · 49 HPA vs KEDA · 50 Elastic products · 51 Scaling on Kafka lag · 52 HTTP add-on · 53 Elastic reads · 54 Scale to zero on HTTP ·
55 Div 07 · 56 Istio (notes: label-based injection) · 57 mTLS (notes: canary manifests exist and are verified) · 58 LGTM · 59 Three signals · 60 Tracing · 61 Supply chain ·
62 Div 08 · 63 NEW How OIDC protects review-service [11-oidc-token-flow] · 64 OIDC with live bearer tokens · 65 Div 09 · 66 Native ·
67 Div 10 · 68 Reference architecture assembled · 69–72 "Domain ownership in practice", "Data as a product in practice", "Self-serve platform in practice", "Federated governance in practice" · 73 Five-act walkthrough · 74 Adoption (heading "Verify each piece before adding the next") · 75 Closing: "Nineteen demos. Three orchestration engines." / "Every capability backed by running code." / tagline "Quarkus and Kubernetes give the four principles a working platform." ·
76 Div 11 · 77 A1 Scaling WebSocket push with Kafka (notes: implemented and verified) · 78 NEW A1 Surviving a replica failure [16-websocket-failover] · 79 A2 Gotchas · 80 A3 Agentic recommendations · 81 A4 Testing · 82 NEW A5 Vert.x in-memory messaging [20-vertx-in-memory] · 83 NEW A5 Kafka messaging [20-kafka-messaging] · 84 A5 In-memory vs. Kafka, side by side · 85 A6 Three engines compared ·
86 Appendix div (sub without "decision ledger"/"wiring detail") · 87 Matrix 1/2 (add demo-panama.sh to bare; "All 19 demos") · 88 Matrix 2/2 ("ollama, Kubernetes, orchestrator"; no "step-9") · 89 Known limitation · 90 compose.yaml · 91 Determinism · 92–94 Glossary 1–3 of 3 · 95 Two-up pipelines/warehouses · 96 Two-up lake/decentralization · 97 Two-up monolith-to-mesh/timeline · 98 "The full project example on Kubernetes" [02-capstone-data-mesh] · 99 "Operational vs. analytical data" [01-operational-vs-analytical] · 100 **"Analytical data: what it is and why it matters"** — local helper: diagram `05-analytical-data-composition` left (~55%), bullets right: **What it is:** historical, integrated, read-optimized views across domains for decisions and models. **How a mesh produces it:** domain-owned analytical data products derived from operational events, published with contracts. **Value:** trusted, discoverable data for decisions, ML features, and compliance — without a central bottleneck, reused by many consumers. **Here:** the operational half is built; the analytical half is designed (sourcing and composition) and not built.

Removed: Key design decisions; Avro/Apicurio wiring; KEDA 0.15.0 pin.

Notes counters: Panama becomes DEMO 8, later demos +1, "of 19"; every "eighteen" → "nineteen".

**Glossary** (3 slides; definitions ≤22 words): (1) Data mesh and architecture: Data product · Choreography · Orchestration · CNCF Serverless Workflow · Avro / Apicurio Registry · MCP · OIDC. (2) Quarkus and the JDK: Panache · Dev Services · Mutiny Uni · WebSockets.Next · JBang · Native image (GraalVM/Mandrel) · AOT cache (Project Leyden) · Panama FFM. (3) Platform and AI: KEDA / HPA · Istio, sidecar, mTLS · OTLP / OpenTelemetry · langchain4j · Drools KieBase / KieSession · UBI.

**101 deck:** "Domain ownership, made real: monolith to mesh" → "Domain ownership: from monolith to mesh"; "The capstone — a data mesh on minikube" → "The full project example: a data mesh on Kubernetes" (+ caption, notes); notes: remove "doubles as a showroom"; 12 capabilities.

## Acceptance criteria

Run from repo root inside `bash -c`.

- `SCOPE` = `_docs/*.md _parts/*.md index.html demos.html setup.html README.md demos/README.md demos/*.sh presentation/*/build*.js scripts/make-*.js assets/diagrams/*.svg`.
- R1 regex (case-insensitive, word-bounded): `honest|honestly|honesty|frankly|plainly|clear account(ing)?|plain (accounting|caveat)|not hidden|rather than hid(den|ing)|worth (noticing|stating|noting|naming)|the thing to land|with your finger|teaching spine|stated precisely|showroom|not a toy|in disguise|masquerading|no ambiguity|nothing invented|made real|crucially|literally|simply|genuine|genuinely|by name|the vocabulary|realized` → **0**. Baseline 149 (site 76, deck 41, demos 19, diagrams 13).
- `\bactually\b` ≤ 30 (baseline 140), 0 in slide-visible strings. `\bdeliberately\b` ≤ 12 (baseline 58). `\bnot (just|merely)\b` ≤ 12 (baseline 52). "uses by name" = 0.
- `grep -rniw capstone $SCOPE | grep -viE "capstone[./*-]"` → 0. In build-deck.js count(`minikube`) = count(`with-minikube`); build-101.js and SVGs `minikube` = 0. `grep -niw minikube _docs/*.md _parts/*.md README.md | grep -vE '`[^`]*minikube[^`]*`|overlays/minikube'` → 0.
- Files exist: `scripts/make-capability-diagrams.js`, `scripts/make-appendix-diagrams.js`, `demos/demo-panama.sh`, `demos/jbang/PanamaFfm.java`; svg+excalidraw pairs for 11-panache-patterns, 11-uni-vs-imperative, 11-websockets-next, 11-jbang-tooling, 11-startup-paths, 11-panama-ffm, 11-oidc-token-flow, 16-websocket-failover, 20-vertx-in-memory, 20-kafka-messaging. Every `.excalidraw` parses; `bash -n` on all `demos/*.sh` and the compare script.
- `demos/demo-panama.sh` exits 0 here with pids and lengths equal. `compare-quarkus-springboot.sh --help` lists `--aot`; `--aot` run produced numbers or ch12 marks the section unverified.
- Ch11 has `Figure 11.1`–`Figure 11.8` in order and "twelve"; ch16 A1.1–A1.2; ch20 A5.1–A5.3; every edited chapter ends with a verification footer. Jekyll docker build exits 0; CI green.
- build-deck.js: "of 18" = 0; "of 19" = 19; no `title:` matches `/demo-[a-z-]+\.sh/`; `demoRef:` ≥ 20; no titles "Key design decisions", "Avro / Apicurio wiring, in detail", "KEDA HTTP add-on — the 0.15.0 pin, in detail"; "Glossary (1 of 3)…(3 of 3)" exist; "Operational vs. analytical, and the full minikube capstone" gone, the two split titles exist; last slide "Analytical data: what it is and why it matters".
- r1.1 pptx exist; r1.0 removed from git; PDF page count = slide count; notesSlide count = slide count; the two `deck-lib.js` identical.
- Visual: monolith-to-mesh Domain C right edge (1050) inside outer (1070); fig 18 repair curve ends on EXECUTE; fig 16 push arrows point replica → clients; fig 21 readable at 80dpi; no subtitle/demo-ref overlaps.
- `git log main.. --format=%B | grep -ci co-authored` = 0; Conventional Commits.

## Risks

- AOT: training must exit cleanly or no cache — SIGTERM exit should work; fallback Spring `-Dspring.context.exit=onRefresh` / Quarkus shutdown, document asymmetry. Classpath mismatch silently falls back without `-XX:AOTMode=on`. RSS includes mmapped cache — report as measured. Confirm `quarkus.package.jar.aot.enabled` name before citing.
- FFM on JDK 25 warns without `--enable-native-access`; `defaultLookup` libc is Linux/macOS — say so in the demo header.
- pptxgenjs mixed runs: bullet props on first run; check visually.
- Factual claims on new diagrams (legacy WebSockets on Undertow, WebSockets.Next execution model, Uni threading) — confirm with Quarkus docs; event-bus and reconnect content marked illustrative/conceptual.
- ~100 slides; 12-card tour is dense — 6×2 with ≥13px; split if unreadable.
- Parallel executors + git → `index.lock`; only coordinator commits. zsh globbing — use `bash -c`.
- Jekyll docker build depends on Gemfile.lock platforms; CI is the fallback gate.
- Over-correction: remove R1 outright; judge R2 case by case.

## Wave 1 results (for wave 2)

- Panama demo real output (JDK 25.0.3, jbang 0.138.0): `PANAMA_GETPID=867684 JVM_PID=867684`, `PANAMA_STRLEN=31 JAVA_LENGTH=31` (test string `"data mesh on Quarkus — héllo"`; strlen counts UTF-8 bytes).
- AOT results (Temurin 25.0.3, 2026-10-05, single run, `--aot`): startup self-reported Quarkus 2.045 s → 0.992 s, Spring 4.018 s → 1.021 s; wall 2.22 → 1.21 s, 4.45 → 1.21 s; RSS Quarkus 337 → 372 MB, Spring 548 → 446 MB; cache 103 MB / 123 MB.
- Coordinator touch-ups: capability-tour band no longer claims "one JVM" (native is in the set); fig 15/18 "real diff/real build" wording; fig 18 canvas trimmed.
- KEDA demo headers: stale AUTHOR-ONLY block replaced; kafka-lag marked verified (5885b28), HTTP add-on unverified.

## Validation outcome

Opus validation found 2 unmet counts and 10 defects (wrong @Blocking failure mode in ch11; inconsistent plain-JVM numbers across fig 12 / ch12 / deck; gRPC threading overclaim in the Uni figure; stale A5.3 alt; "showroom"/"simply"; too many "not just"; meta-narration; agenda duplication; closing-slide overclaim; analytical-data slide buried in the appendix). All fixed in one repair round and re-checked: R1 = 0, `not (just|merely)` = 9, `actually` = 17, `deliberately` = 2; 201 deck 100 slides / 100 notes, 101 deck 17 / 17; deck-lib copies identical; all .excalidraw parse, all .svg well-formed; `bash -n` clean; Jekyll build exits 0. The analytical-data slide now closes the main talk (just before the closing statement).
