---
title: "How this was built — the agentic relay"
description: "The agentic development and testing method that built and validated this repo: a Plan/Execute/Validate model relay, fan-out parallelism across file-disjoint work, and the adversarial re-verification that caught the defects a subagent's own report missed."
---

> **Note.** This is a behind-the-scenes process document about how the repository
> was built and validated with an agentic workflow. It is intentionally **not**
> part of the published tutorial site — it lives here as a standalone reference.

Everywhere else in this tutorial, the showroom has two floors: a working
data mesh — domain-owned services, versioned contracts, an event backbone,
progressive delivery, autoscaling, observability — demonstrating Zhamak
Dehghani's four principles as a running system, and Quarkus itself,
exercised across Panache, gRPC, GraphQL, Reactive Messaging,
WebSockets.Next, native compilation, and two orchestration engines side by
side. This chapter is the third floor: how the other two got built, by an
agentic workflow, and how that workflow was checked.

The method has a name in this repo's planning files: the **lgtm-relay**. A
planning pass runs on the most expensive model available (Opus); the plan
is executed by a cheaper, faster model (Sonnet) working from its acceptance
criteria, often many execution agents in parallel across file-disjoint
work; a separate pass, back on Opus, verifies the result against those
criteria by reading the real diff and running the real build — not the
executor's summary. Every step after a plan is approved is
checkpoint-committed, so no hour of work is ever one dropped session from
gone.

The thesis is narrower than "agents can write code." It is this: **a
subagent's report is a claim, not evidence.** An agent that just wrote
fifty lines of REST-layer code is the worst-positioned party to find the
bug in it — not from carelessness, but because it is reporting on its own
intent, and intent and outcome drift apart in exactly the cases worth
catching. This project's value from agentic development didn't come from
the agents being right the first time; it came from a second, independent
pass that assumed they weren't, looked, and found real defects a "looks
good to me" summary would have let through. Figure 16.1 is the loop this
chapter walks through: a human-gated plan, a fan-out of file-disjoint
executors checkpointing their own commits, a validation pass reading the
diff rather than the report, a capped repair loop back to execution, and
the branch → PR → squash-merge rail every phase boundary here actually rode.

![The lgtm-relay loop: a human-gated Plan phase on Opus hands acceptance criteria to a fan-out of file-disjoint Sonnet executors, each checkpoint-committing on its own branch; a Validate phase on Opus reads the real diff and runs the real build against those criteria, independent of the executors' own reports; failures feed back to Execute for up to two repair rounds before escalating to a fresh plan; every phase lands through a branch, a PR, and a squash-merge to main](../assets/diagrams/15-agentic-relay.svg)

*Figure — Plan (Opus) → fan-out Execute (Sonnet) → Validate (Opus), with a capped repair loop and a PR rail.*

## Agentic development

### Three phases, two tiers, one asymmetry

The relay assigns each phase to the model tier suited to its failure mode,
with an explicit model override per phase so the tier is guaranteed rather
than whatever the ambient session happens to run on. **Plan** runs on
Opus: it decomposes the work, picks an approach, states what was rejected
and why, and writes checkable acceptance criteria rather than vibes —
"`mvn verify -f examples/pom.xml` green, N tests, 0 failures" is checkable
against a build log; "the reactor builds cleanly" is not. **Execute** runs
on Sonnet, one agent per independent step, each handed only its own step's
criteria and file paths — not the whole plan, since pasting in irrelevant
steps invites scope creep. **Validate** runs on Opus again, reading the
real diff and running the real checks, reporting met/not-met/not-checkable
per criterion.

The reason to spend Opus at both ends and Sonnet in the middle is an
asymmetry in how failure compounds, not a belief Sonnet writes worse code.
A wrong plan wastes the entire execution that follows — every hour of
Sonnet's work inherits whatever mistake Opus made at the top. An
unvalidated execution ships its defect silently; the cost is paid later, by
whoever hits the bug, or in a tutorial repo's case by a reader whose
`mvn verify` fails with no way to know the chapter ever worked. Turning an
already-unambiguous plan into code is where a fast model earns its keep,
because the plan did the hard thinking. Both ends deserve the stronger
model; the middle usually doesn't — and Opus on both ends of every step is
not free, so this project's own discipline is to skip the relay entirely
for one-line edits, lookups, and mechanical find-and-replace rather than
relay a typo fix.

### Fan-out: parallel execution across file-disjoint work

Execution is fan-out wherever steps don't share files. The clearest real
example here is Phase B of the reactor: once the shared `domain-model` and
`contracts` modules existed, the eight service modules —
`notification-service`, `payment-service`, `inventory-service` and
`review-service`, `shipping-service`, `ai-mcp-service`,
`graphql-gateway`, and `order-service` — were each a self-contained Maven
submodule under its own package, touching no file any other module
touched. `git log` shows seven consecutive `feat(examples):` commits, each
scoped to exactly one module's directory, each a checkpoint in its own
right — a dropped session between any two loses only the module in
flight. Where two steps *do* touch the same files, the answer is to
sequence them or isolate one in its own worktree; parallel agents racing on
one file is a guaranteed clobber, not a time saving.

Checkpoint discipline is what makes a multi-hour relay survivable. A plan
that exists only in conversation context dies with the context, so it gets
written to a file (`_plans/decisions.md`, `_plans/build-plan.md`,
`_plans/RESUME.md` here) and committed before execution starts. Each landed
step gets its own commit, explicitly allowed to be a mid-flight "WIP
checkpoint" rather than a claim of correctness — validation decides that.
This build's git history is the artifact: fourteen PRs (`#1`–`#14`) carry
Phases A through E from scaffold to pre-publish sweep, each riding the same
branch → checkpoint commits → PR → squash-merge-to-`main` rail, so the
relay never had more than one phase's work exposed to loss, and the squash
means the WIP commits cost nothing in the permanent history.

### Subagents don't inherit skills, and the human gate

A subagent spawned mid-relay starts with none of the orchestrating
session's loaded context — it doesn't know this repo's conventions unless
its own prompt says so. Every executor prompt here re-states the relevant
rules explicitly (chapter front-matter shape, codetab syntax, the
verification-footer wording) rather than assuming an inherited
understanding. The same applies one level up: a sub-orchestrator spawning
its own executors must pass `model` explicitly on every nested call, since
an `Agent` call that omits the override silently inherits the caller's
model — a validator that quietly degrades from Opus to Sonnet because a
prompt forgot one parameter defeats the whole point of tiering, invisibly.

Two points stay deliberately un-automated. The plan — approach, steps,
criteria, risks — is shown to a human before execution starts, because
catching a wrong assumption there is the cheapest place to catch it; this
build's `RESUME.md` records that as a standing convention: proceed on
approval, or on a standing instruction not to ask between phases, but never
silently. The second gate sits at publication — this repo was built on the
constraint that pushing to a public remote happens only after human
approval, tracked as its own settled decision (`DRQ-002`). Neither
substitutes for the other; some decisions have a blast radius no acceptance
criterion captures.

### Honest trade-offs

There's a class of mistake the relay doesn't prevent by construction:
coordination drift between file-disjoint workstreams that each encode the
same fact independently. The concrete instance here is a port number.
`order-service`'s gRPC client and `inventory-service`'s gRPC server need to
agree on one port; an earlier workaround pinned several demo scripts to
`9001` while the actual source default on both sides had already moved to
the canonical `9000`. Nothing in any single file was wrong — seven demo
scripts and two services were each internally consistent, and the defect
lived in the gap between them. It shipped, survived until a pre-publish
sweep ran the demos against a fresh build instead of trusting an earlier fix
had propagated, and was corrected in PR `#12`. The lesson: a value repeated
across file-disjoint artifacts needs an explicit single-source-of-truth
check in validation, not an assumption that file-disjointness alone
guarantees consistency. A related cost is staleness: a stale build artifact
or Docker volume can hide a defect in exactly the run checking for it — the
next section covers one real case.

## Agentic testing

### Validation is adversarial, not confirmatory

Validate is not "ask the model if it thinks the work is correct." It's
handed the acceptance criteria and file paths — deliberately **not** the
executor's own summary, which only anchors a reviewer toward agreeing with
it rather than checking it. The validator reads the actual diff, runs the
actual build, and reports met/not-met/not-checkable per criterion — never
upgraded to met because the rest looked plausible. "Looks right" is not a
verdict; it's the thing a verdict replaces. A failure goes back to a Sonnet
executor and gets re-validated, capped at two repair rounds — a third
failure on the same criterion means the *plan* was wrong, not the
execution, and the honest move is to stop, not keep patching a plan that
was never going to land.

### The defect catalog: what independent re-verification actually caught

**A false pass behind a real fix.** Every REST resource here carried a
class-level `@Consumes(APPLICATION_JSON)`, which JAX-RS applies to every
method on the class — including bodyless `GET`/`DELETE` methods with no
business rejecting a body they don't read. A load tool defaulting its
`Content-Type` to `text/html`, `GET` included, turned every such request
into a 415; nothing in the existing suite caught it, because nothing sent a
`GET` with a non-JSON content type. The first fix (PR `#12`) moved
`@Consumes` onto the POST-body methods and added a regression test
asserting `GET /orders` returns `200` under `text/html`. A less adversarial
process stops there. It wasn't done: a second pass (PR `#13`) found that
test used RestAssured, which strips `Content-Type` from a bodyless `GET`
before it reaches the wire — the test never exercised the bug it was named
for. Green, and meaningless. The corrected test switched to
`java.net.http.HttpClient`, which actually sends the header, live-verified
(`GET`+`text/html` → `200`, `POST`+`text/html` → `415`, a `hey` load run
clean at 160k/160k), with an explicit `@Consumes(MediaType.WILDCARD)` added
to the bodyless methods so correctness no longer depends on which method
the annotation isn't attached to. Two rounds of re-verification were needed
to get from "a fix that builds" to "a test that actually proves it."

**A doc claiming absence that the diff disproved.** A chapter asserted that
`examples/domain-model` was an intentionally *empty* module — a
placeholder for "a populated shared-entity module would recreate the
coupling domain ownership prevents." Plausible, and false: the module
holds seven real shared DTOs every service depends on
(`OrderDto`/`OrderCreate`/`OrderStatus`/`StockDto`/`ReviewDto`/`NotificationDto`,
plus `Topics`). A validation pass reading the module's real contents caught
the mismatch and rewrote the passage around the sharper real point: what
crosses a domain boundary is a narrow *contract*, never another domain's
internal entity.

**A field name only a live query would catch.** The Newman collection's
GraphQL request selected `orderId` on the `order` query's result type. The
real type, `OrderView`, exposes that value as `id`. A query selecting a
nonexistent field doesn't fail to compile — it fails at request time,
visible only by running it against a live gateway. Validation caught it
and corrected both the query and the downstream assertion against the
REST-side `{{orderId}}` variable.

**A category, generically.** Beyond those three pinned-down cases, this
build's validation surfaced a broader pattern worth naming even where no
single commit nails it precisely: documentation occasionally describes an
end state — something published, merged, flipped — a beat before the
change that would make it true has landed. A natural drift for anyone
narrating work in progress, human or agent, and exactly the kind of
claim-versus-artifact gap reading real state catches and a summary of
intent does not.

### The conventional net underneath the agentic one

None of this replaces ordinary tests — it finds what ordinary tests
structurally can't, then hands off to the conventional suite for
everything else. The 415 case is the clean illustration: agentic
validation noticed both the wiring problem and the test-validity problem —
neither is unit-test shaped, because a unit test only tells you what you
remembered to assert. Once fixed, the corrected test joins the permanent
net that runs in every future `mvn verify`, agentic or not.

That net has real depth here. Below the service layer,
`OrderPlacedAvroWireIT` is a Testcontainers integration test that produces
a real `OrderPlaced` record through the actual Avro/Apicurio serializer,
reads it back with a plain `KafkaConsumer<byte[],byte[]>`, and
byte-asserts the first byte is the Avro magic byte `0x0` rather than `0x7B`
(the JSON `{` a silent serde fallback would produce) — because an earlier
phase proved config-level serialization claims can be true and still wrong
on the wire, so this test reads the wire instead. Above the service layer,
`tooling/newman/` runs a 49-assertion Postman collection against the
running stack, covering REST, gRPC-fronted GraphQL federation, and the
event path together; the pre-publish sweep got 37 of 37 applicable
assertions green live. Alongside it, `tooling/load/` drives `hey` against
REST and `ghz` against gRPC for throughput and latency rather than
correctness. All of it is reachable through one consolidated entry point,
`scripts/run-all-tests.sh` — this build's answer to not making a reader
hunt across `mvn verify`, `demos/`, and `tooling/` separately to know
whether the whole thing works.

The honest relationship is complementary, not hierarchical. Agentic
validation is good at exactly what a fixed suite is bad at by
construction: noticing a chapter's prose doesn't match its code, that a
passing test isn't exercising what it claims to. A fixed suite is good at
exactly what agentic validation is expensive and non-deterministic at:
running the same check, cheaply, every time, forever, without an LLM call.
The agentic pass's job is to keep finding new net to add to the cheap
suite — not to stand in for it indefinitely.

## Where it needs a human

This isn't an argument for removing humans from the loop — the defect
catalog above is the argument for why they stay in it. Two points remain
load-bearing by design: plan approval before execution, and
publish-after-approval before anything agent-built reaches a public
audience. Neither is automatable without giving up what makes it
valuable — a plan gate nobody reads isn't a gate, and a publish decision an
agent can make unilaterally isn't a human decision.

The defect catalog is the plainest evidence for why the method exists: a
stale build artifact masked the GET-415 defect until validation insisted on
a clean rebuild, and a chapter's own prose asserted a false fact nobody had
checked against the directory. Both are real false passes and false
claims, not hypothetical risk — they're why an independent read of the diff
and the build, rather than a report about them, is non-optional.

Costs are worth naming plainly. Opus at both ends of every non-trivial step
is slower and pricier than one model straight through, and the
two-repair-round cap exists because that cost compounds badly if a stuck
plan gets patched indefinitely instead of rethought. Reproducibility has
real limits too: LLM behavior drifts across model versions and runs, so a
pre-validated classifier input that produces an exact decision today isn't
guaranteed to after an upstream model update — the caveat the
`ai-rules-triage` chapter's own footer already carries. And at least one
defect in this build's log, `DEF-001`, stays an open upstream deferral
rather than a closed finding because its root cause sits in a dependency
this project doesn't control — not every defect a validator finds is this
repo's to fix.

## What you learned

- The lgtm-relay routes each phase to the model tier suited to its failure
  mode — Opus for planning and validation, Sonnet for execution — with an
  explicit model override per phase so the tier is guaranteed, not
  incidental.
- Fan-out parallelism is safe exactly where work is file-disjoint — the
  eight reactor modules built this way — and unsafe where it isn't; shared
  files get sequenced or isolated, not raced.
- Checkpoint commits at every phase boundary, riding a branch → PR →
  squash-merge rail, make a multi-hour relay survivable; this build's 14
  PRs are that discipline's own evidence.
- A subagent doesn't inherit the orchestrating session's loaded skills or
  conventions — every executor prompt restates them, and every nested
  `Agent` call states its model tier explicitly rather than inheriting one.
- **A subagent's report is a claim, not evidence.** Validation reads the
  real diff and runs the real build without the executor's
  self-assessment, reporting met/not-met/not-checkable per criterion —
  never "looks right."
- Independent re-verification caught real defects a self-report would have
  missed: a 415 masked by a stale rebuild and then a test framework
  silently dropping the header it claimed to exercise, a chapter asserting
  a module was empty when a diff showed otherwise, and a GraphQL field
  selection only a live query could disprove.
- Agentic testing complements conventional tests, not replaces them: it
  finds defects a fixed suite can't see by construction, then hands the
  fix to that suite to run cheaply and deterministically forever after.
- Two gates stay human by design: plan approval before execution, and
  publish approval before anything reaches a public audience.

This closes the tutorial. The system the earlier chapters describe and the
method this chapter describes are the same project, seen from two angles:
what was built, and how what was built earned the right to be trusted.

---

*Verification status: unverified.
The highest-risk things to confirm on a real run: that `scripts/run-all-tests.sh`
still runs to a clean pass as the single consolidated entry point described
here, rather than only in the per-tool form (`mvn verify`,
`tooling/newman/run-newman.sh`, `tooling/load/*`) that was independently
verified; that the cited counts (49 Newman assertions, 37/37 live in the
pre-publish sweep, the reactor's green `mvn verify`) still hold against the
current `main`; and that the port-collision and false-pass examples cited
from PRs #12/#13 still match the code as merged, since this chapter was
written by reading that history rather than re-running it.*
