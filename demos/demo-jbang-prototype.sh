#!/usr/bin/env bash
#
# demos/demo-jbang-prototype.sh — "bare" toolchain demo.
#
# Demonstrates JBang-based single-file prototyping: demos/jbang/HelloRoute.java
# is a complete Camel route with no pom.xml and no Maven module.
# `jbang demos/jbang/HelloRoute.java` resolves the script's pinned //DEPS
# (Camel 4.22.1, the latest stable patch on the 4.22 line the
# quarkus-camel-bom 3.39.5 platform pins)
# from Maven Central and runs it directly. This is the "sketch an idea
# before committing to a Maven module" workflow this capability exists to
# showcase — no `mvn` anywhere in this script.
#
# Supply chain: the script is a local file (jbang trusts file:// sources by
# default) and its dependencies are pinned Maven Central artifacts. No remote
# catalog alias or GitHub-hosted launcher is fetched, so jbang never asks the
# presenter to trust a source.
#
# The route stops itself after one message (Camel Main's
# durationMaxMessages=1, with a 90 s ceiling), so this demo is fully
# non-interactive and has nothing to tear down.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/_demo.sh"

demo_begin "demo-jbang-prototype"

# require() gives a generic "install curl/jq/docker/mvn"-style hint, which
# would be actively misleading for jbang (none of those are the fix) — so
# this preflight is a dedicated check with a jbang-specific install hint
# instead of `require jbang`, so a missing jbang fails with an install hint
# rather than silently passing.
if ! command -v jbang >/dev/null 2>&1; then
    fail "jbang is required for this demo but was not found on PATH. Install it with: curl -Ls https://sh.jbang.dev | bash (or: sdk install jbang, or: brew install jbangdev/tap/jbang) — then re-run this script. See https://www.jbang.dev/documentation/guide/latest/installation.html"
fi

ROUTE_FILE="${SCRIPT_DIR}/jbang/HelloRoute.java"
[[ -f "$ROUTE_FILE" ]] || fail "prototype source not found: $ROUTE_FILE"

MARKER="JBANG_PROTOTYPE_OK: HELLO FROM A JBANG PROTOTYPE"
LOGFILE="$(mktemp -t demo-jbang-log-XXXXXX)"

# Running from a throwaway tmpdir keeps any runtime scratch files out of the
# working tree regardless of the caller's cwd.
RUN_DIR="$(mktemp -d -t demo-jbang-run-XXXXXX)"
_cleanup_rundir() {
    local rc=$?
    rm -rf "$RUN_DIR"
    return "$rc"
}
trap '_cleanup_rundir; _demo_exit_trap' EXIT

step "jbang-running a single-file Camel route (no pom.xml, no mvn build)"
narrate "jbang ${ROUTE_FILE#"${REPO_ROOT}"/}"
info "log: $LOGFILE"
info "scratch dir (auto-cleaned): $RUN_DIR"

# HelloRoute.main() stops Camel after one message (90 s ceiling for a cold
# dependency cache; the route itself runs in about a second once Camel is up).
if ! ( cd "$RUN_DIR" && jbang "$ROUTE_FILE" ) \
        >"$LOGFILE" 2>&1; then
    tail -n 40 "$LOGFILE" >&2
    fail "jbang run exited non-zero — see log above ($LOGFILE)"
fi

grep -qF "$MARKER" "$LOGFILE" \
    || { tail -n 40 "$LOGFILE" >&2; fail "expected marker '$MARKER' not found in jbang output ($LOGFILE)"; }

narrate "prototype produced the expected transformed output — a working Camel route, zero Maven project"
demo_ok
