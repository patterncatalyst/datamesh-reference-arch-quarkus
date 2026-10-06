#!/usr/bin/env bash
#
# demos/demo-jbang-prototype.sh — "bare" toolchain demo.
#
# Demonstrates JBang-based single-file prototyping: demos/jbang/HelloRoute.java
# is a complete Camel route with no pom.xml and no Maven module.
# `jbang camel@apache/camel run <file>.java` (Apache Camel's own JBang CLI —
# jbang transparently installs/trusts the `camel@apache/camel` app catalog
# entry the first time it's invoked) resolves Camel's runtime straight from
# Maven Central and runs the route directly. This is the "sketch an idea
# before committing to a Maven module" workflow this capability exists to
# showcase — no `mvn` anywhere in this script.
#
# The route runs to completion on its own (`--max-messages=1
# --max-seconds=<N>`) rather than being left running, so this demo is fully
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

# `camel@apache/camel run` drops a `.camel-jbang/` scratch directory
# (compiled classes, run state) into whatever the current directory happens
# to be when it's invoked — confirmed empirically (it landed in examples/ the
# first time this was run from there). Running from a throwaway tmpdir
# instead of the repo keeps that litter out of the working tree regardless
# of the caller's cwd.
RUN_DIR="$(mktemp -d -t demo-jbang-run-XXXXXX)"
_cleanup_rundir() {
    local rc=$?
    rm -rf "$RUN_DIR"
    return "$rc"
}
trap '_cleanup_rundir; _demo_exit_trap' EXIT

step "jbang-running a single-file Camel route (no pom.xml, no mvn build)"
narrate "jbang camel@apache/camel run ${ROUTE_FILE#"${REPO_ROOT}"/}"
info "log: $LOGFILE"
info "scratch dir (auto-cleaned): $RUN_DIR"

# --max-messages=1: shut down after the timer fires once.
# --max-seconds=90: hard ceiling in case dependency resolution is cold
# (jbang/camel-jbang cache a Maven-resolved runtime; a clean cache can take
# tens of seconds to download on first use — the route itself runs in ~1s
# once Camel is up).
if ! ( cd "$RUN_DIR" && jbang camel@apache/camel run "$ROUTE_FILE" --max-messages=1 --max-seconds=90 ) \
        >"$LOGFILE" 2>&1; then
    tail -n 40 "$LOGFILE" >&2
    fail "jbang camel run exited non-zero — see log above ($LOGFILE)"
fi

grep -qF "$MARKER" "$LOGFILE" \
    || { tail -n 40 "$LOGFILE" >&2; fail "expected marker '$MARKER' not found in jbang output ($LOGFILE)"; }

narrate "prototype produced the expected transformed output — a working Camel route, zero Maven project"
demo_ok
