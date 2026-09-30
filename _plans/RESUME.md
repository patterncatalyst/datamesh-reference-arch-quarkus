---
title: RESUME — session state
description: Read this FIRST after a context compaction or restart to resume the build
---

# RESUME — datamesh-reference-arch-quarkus build

**Read this first after any /compact or restart.** Then read
[build-plan.md](build-plan.md) (steps + status table) and
[decisions.md](decisions.md) (DRQ-001…008).

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
- Branch: `build/initial-scaffold` (NOT pushed — publish to
  github.com/patterncatalyst/datamesh-reference-arch-quarkus PUBLIC only after
  user approval, Step 17).
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
- **Phase B — build-verified DONE** (steps 5–7): reactor `examples/` + shared
  `domain-model`/`contracts` (Avro codegen 3 events + gRPC) + all 8 modules
  (order, inventory, payment, shipping, notification, review, graphql-gateway,
  ai-mcp-service). Full reactor `mvn -DskipTests package` = EXIT 0, 10 jars.
  Fixes landed: inventory nested gRPC message classes; shipping explicit Avro
  serde (autodetection proven to silent-fall-back to JSON — split-package).
  Opus runtime validation (mvn verify + Dev Services + DEF-001 pin) IN PROGRESS.
  New decisions since last checkpoint: DRQ-009 (Avro+Apicurio all events up
  front, no JSON), DRQ-010 (real payment/shipping choreography), DEF-001
  (langchain4j core/ollama version skew — pin in Batch C).
- **NEXT after validation** — Phase C infra (step 8 docker compose +
  Testcontainers + devcontainer via lgtm-docker-stack; step 9 minikube/KEDA),
  then Phase D content, Phase E finish. See build-plan.md status table.

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
