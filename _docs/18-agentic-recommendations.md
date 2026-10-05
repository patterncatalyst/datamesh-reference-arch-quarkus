---
title: "Agentic development recommendations"
order: 18
part: Appendices
description: "Guidance for AI-agent-assisted development on a Quarkus/Camel codebase: where it helps, where it does not, the plan/execute/validate relay, and the MCP tooling that grounds agents in the real catalog and docs."
duration: 25 minutes
marker: "18"
---

Most of this tutorial is about a running system. This chapter covers how it
was built: a large share of the code, chapters, and demos in this repo were
written with AI-agent assistance. It records what that process was reliable
for, where it needed a human or a second pass, and which tools kept it
grounded in this stack's APIs. Agentic assistance has one dominant failure
mode: it reports success with the same confidence whether or not the claim
is true. Most of what follows compensates for that.

{% include excalidraw.html file="18-agentic-recommendations" alt="A plan/execute/validate relay feeding a Quarkus/Camel development loop: a planning pass decomposes a task into bounded steps with checkable acceptance criteria; an execution pass writes code grounded in camel-mcp catalog and validation tools and quarkus-agent docs/dev-loop tools instead of guessing component URIs or extension APIs; a validation pass reads the diff and runs the build independently of the executor's own summary, looping failures back to execution up to a capped number of repair rounds, with a human gate before the plan is executed and before anything is published" caption="Figure A3.1 — A plan / execute / validate relay, grounded in MCP tooling" %}

A fuller build case study (the build history, the defect catalog from
independent re-verification, and the mechanics of fanning work out across
file-disjoint modules) informs this chapter. It stays an internal document
because it narrates this repo's history; this chapter is the part that
generalizes.

## Where it helps

Agentic assistance pays off on work that is **bounded and
well-specified**, even when it spans many files. Three shapes recur in this
repo:

- **Scaffolding a new module against an existing pattern.** Adding a new
  Quarkus service that mirrors `order-service`'s structure, or a new Camel
  route that mirrors an existing EIP shape, is where an agent reading three
  sibling examples and reproducing the pattern is faster and no less
  reliable than a human doing the same mechanical copy-adapt-rename work.
- **Cross-file refactors with a single, checkable rule.** Renaming a header
  key across a dozen routes, or propagating a schema change through every
  consumer, is bounded (the rule is simple) but tedious (the file count is
  large) — a profile where an agent beats a human typing the same edit a
  dozen times with a dozen chances to typo one.
- **Chapter and demo authoring against a working example.** Writing a
  tutorial chapter *about* code that already runs, or a demo script that
  exercises an endpoint that already exists, is bounded by the code itself
  — the agent is describing or driving something that exists.

All three share a property: there's a cheap, objective check for whether the
output is right — compiles, tests pass, the described behavior matches a
`curl` response — so a mistake surfaces quickly instead of persisting until a
reader hits it.

## Where it doesn't

The failure modes cluster just as predictably.

- **Architecture decisions.** Whether to use Camel orchestration or Quarkus
  Flow for a given workflow, whether a module should be a saga step or a
  synchronous call, which EIP fits a given fan-out — these are judgment
  calls with real trade-offs and no single checkable answer. An agent can
  lay out the trade-offs, which is useful, but the decision
  itself belongs to whoever owns the consequences, recorded in a decision
  log the way this repo does it, not inferred from an agent's
  confident-sounding recommendation.
- **Unverified claims presented as working.** This is the sharpest edge.
  Chapter 14's own `ai-rules-triage` example is the concrete case: the
  in-process `langchain4j-agent` tool-calling path in `ai-mcp-service` does
  not fire on this stack — a known upstream defect in
  `camel-quarkus-support-langchain4j`'s HTTP client wiring — and a less
  careful pass could easily have shipped a demo claiming it works, because a
  non-empty chat response looks like success without exercising the tool
  call. The correct chapter carries a banner saying the path is known broken and
  showing that the model is not the cause, rather than avoiding the broken
  endpoint and letting silence imply success.
- **Multi-turn, open-ended agentic loops on an unfamiliar stack.** The
  further an agent gets from a single, checkable action (write this method,
  validate this URI) and the closer it gets to a long chain of
  self-directed tool calls with no external check on each step, the more
  its own self-assessment becomes the only signal — the least trustworthy
  one, since the agent assessing its own work grades on its own intent, not
  the outcome.

## The plan / execute / validate relay

The discipline that makes the "where it helps" column reliable and catches
the "where it doesn't" column before it ships is a three-phase relay:

1. **Plan** — a strong model decomposes the task into steps with *checkable*
   acceptance criteria. "`mvn verify` green, N tests, 0 failures" is
   checkable against a build log; "the service works correctly" is not. The
   plan also states what was rejected and why, so a reviewer sees the
   trade-off, not just the chosen path.
2. **Execute** — a fast model turns one step's already-unambiguous plan into
   code. This is the cheap half of the relay: by the time a
   step reaches execution, the hard thinking is done, and turning a clear
   spec into code is not where the expensive model's marginal value is
   highest.
3. **Validate** — a strong model again, reading the diff and running
   the build, reporting **met / not-met / not-checkable** against each
   criterion from the plan — never "looks right." A failure goes back to
   execution for a capped number of repair rounds; a repeated failure on the
   same criterion means the plan was wrong, not the execution, and the
   right move is to stop and re-plan rather than patch indefinitely.

The asymmetry behind spending the stronger model at both ends and the
cheaper one in the middle is about how failure compounds, not about code
quality per line: a wrong plan wastes everything built on top of it, and an
unvalidated defect ships silently and gets paid for later by whoever hits
it. Skip the relay for one-line edits, lookups, and mechanical
find-and-replace — tiering every trivial change is its own waste.

**The one sentence worth remembering from all of this:** *a subagent's
report is a claim, not evidence.* An agent that just wrote the code under
test is structurally the worst-positioned party to find the bug in it — not
from carelessness, but because it's reporting on its own intent, and intent
and outcome drift apart in exactly the cases worth catching. This repo's own
defect catalog is the concrete argument for this: the RestAssured/415 gotcha
covered in Appendix 17 (a regression test that did not exercise the
bug it was named for); a chapter asserting a module was empty when the
directory held seven shared DTOs; a GraphQL field name that only
failed at request time against a live gateway. None of those were caught by
asking an agent if its own work was correct. All of them were caught by a
second pass that read the file and ran the query, independent of the first
pass's summary.

## Grounding agents in tooling

The single highest-leverage habit for working with Camel and Quarkus
specifically is not letting an agent guess at component URIs,
configuration option names, or extension APIs it hasn't looked up. General
LLM knowledge about Camel is stale the moment a version shifts, and small
syntax mistakes compile and run — they just fail quietly or wrong, worse
than failing loudly. This repo's
[CLAUDE.md]({{ site.repo_blob }}/CLAUDE.md) names two MCP servers for
exactly this reason:

- **`camel-mcp`** exposes the live Camel catalog, route validation, and
  runtime introspection — `camel_catalog_component_doc` for a component's
  URI syntax and option types, `camel_validate_route` to check a
  `.to()`/`.from()` URI before it's committed, `camel_catalog_eip_doc` for
  EIP option names, and runtime tools (`camel_runtime_routes`,
  `camel_runtime_errors`) for introspecting a route that is running
  rather than reasoning about what it probably does. It prevents a specific
  failure: an invalid option name or a type mismatch (a delay expressed as
  `5s` instead of milliseconds, say) that an LLM might produce from
  pattern-matching on older Camel syntax, but that the catalog — pulled
  from the version-matched schema — won't validate.
- **`quarkus-agent`** does the equivalent job for the Quarkus side:
  `quarkus_searchDocs` for version-matched extension documentation,
  `quarkus_skills` for extension-specific patterns before writing code
  against Panache, gRPC, or Reactive Messaging, and `quarkus_start`/
  `quarkus_logs` for driving the dev loop instead of narrating what
  `mvn quarkus:dev` would probably print.

The principle generalizes past these two servers: an agent that can query
ground truth (a catalog, a running process, the actual file on disk) and is
instructed to do so before committing syntax is more reliable
than one reasoning from training-data memory of what a similar-looking API
probably looks like. Wiring up that grounding is a small, one-time cost
(see `camel-mcp-setup` for the Camel side); not wiring it up costs a slow
trickle of configuration bugs that compile cleanly and fail at runtime —
exactly the kind of defect that's expensive to trace back to its source.

## Verification-status discipline

Every chapter in this tutorial ends with a verification-status footer —
unverified until someone has run it against a live environment,
with the highest-risk claims named instead of a blanket "this should
work." That convention exists for the same reason the relay's
Validate phase exists: a claim an agent makes about its own output is worth
exactly as much as the independent check behind it, no more. Applying the
same discipline to agent-written code in day-to-day work means treating
"the agent says the tests pass" and "I ran the tests and they passed" as
different facts, not the same fact stated twice. Where a tool-calling
result is at stake — a multi-turn agent loop, an MCP round trip — a
non-empty response is not evidence of anything; verify the specific side
effect the call was supposed to produce, not just that something came back.

## Low-cost guardrails

A short list of conventions this repo enforces that have nothing to do with
AI specifically, but matter more once an agent generates a meaningful
share of the commits: an agent follows a small, consistent rule if told
once, and drifts from it if nobody enforces it:

- **Conventional Commits**, scoped where useful (`feat(order):`,
  `fix(graphql):`), so the history stays legible regardless of who or what
  wrote a given commit.
- **No `Co-authored-by` or other attribution trailers** in commit messages
  — a house rule, not a technical requirement, so state it in every
  executor agent's prompt instead of assuming it is inherited.
- **Scope discipline** — an executor handed a bounded step's acceptance
  criteria and file paths, not the whole plan, so a side quest ("while I'm
  here, let me also refactor...") doesn't creep into a change whose blast
  radius was supposed to be one module.
- **Subagents don't inherit skills or conventions.** A freshly spawned
  agent knows nothing about this repo's rules unless its own prompt states
  them — codetab syntax, front-matter shape, the verification-footer
  wording, the no-attribution rule. Every executor prompt restated the
  relevant conventions rather than assuming an inherited understanding, and
  the same applies one level up: a nested `Agent` call that omits an
  explicit model override silently inherits the caller's model, so a
  validation pass can degrade from a strong model to a fast one unnoticed.
- **Two points stay human by design:** plan approval before execution
  starts, and publish approval before anything agent-built reaches a public
  remote or audience. Neither substitutes for the other, and neither is
  worth automating away — a plan gate nobody reads isn't a gate, and a
  publish decision an agent can make unilaterally isn't a human decision.

## A practical checklist

A version to pin somewhere visible:

1. Is this task bounded and checkable (compiles, tests pass, a `curl`
   response matches)? If not, it's a decision — make it yourself, let an
   agent lay out trade-offs if useful, but don't delegate the call.
2. Before an agent writes a Camel URI, Quarkus config key, or extension API
   call, has it looked the real syntax up via `camel-mcp` or
   `quarkus-agent`, or is it pattern-matching from memory?
3. Would a plan for this task survive being handed to someone else to
   execute, with acceptance criteria specific enough to check against a
   build log rather than a vibe?
4. Has anyone read the actual diff and run the actual build, independent of
   the agent's own summary of what it did?
5. Does any claim here — a tool call succeeded, a test proves the fix, a
   module is empty, a field exists on that type — rest on something a human
   or a second agent checked, or only on the first agent saying so?
6. Do commit messages, scope, and attribution follow this repo's
   conventions regardless of who (or what) is typing them?

This is the discipline that makes any unsupervised contributor's work
trustworthy (bounded tasks, independent review, an audit trail), applied to
a contributor whose false claims carry the same confidence as its true
ones.

## What you learned

- Agentic assistance is reliable on bounded, well-specified work —
  pattern-matched scaffolding, mechanical cross-file refactors, documenting
  or driving code that already runs — and unreliable on architecture
  judgment calls and unverified claims about what a system does.
- The plan/execute/validate relay assigns each phase to the model tier
  suited to its failure mode and treats a subagent's report as a claim,
  not evidence — validation reads the diff and runs the build.
- `camel-mcp` and `quarkus-agent` ground agent-written code in the
  version-matched catalog and docs instead of a plausible-looking guess,
  turning a class of silent runtime misconfiguration into a validation
  failure caught before commit.
- Verification-status discipline — treating "the agent says it passed" and
  "it was independently checked" as different facts — is the same
  principle behind this tutorial's own chapter footers, applied to
  day-to-day agentic work.
- Conventional commits, no attribution trailers, and strict scope
  discipline cost nothing and catch real drift once an agent is writing a
  meaningful share of a repo's commits.
- Plan approval and publish approval stay human by design; this repo's full
  build case study records the specific defects an independent validation
  pass caught that a self-report would have missed.

---

*Status: <span class="status status--conceptual">conceptual</span>.
This chapter is a distillation of recommendations rather than a runnable
example, so there is no build or demo to execute against it. The claims
to re-check independently: that the known upstream defect in
`camel-quarkus-support-langchain4j`'s HTTP client override (breaking
in-process agent tool-calling) still reproduces against this repo's pinned
langchain4j/Camel versions, since an upstream fix would make that example
stale; and that the cited defect catalog and pull request references still match
the repository history, since this chapter was written from that record
rather than by re-deriving its claims.*
