#!/usr/bin/env bash
#
# demos/lib/_demo.sh — shared helper library for datamesh-reference-arch-quarkus
# demo scripts. Not executable on its own — it is meant
# to be sourced from a demo-*.sh script, never run directly.
#
# Ported from the idiom in the Python sibling repo
# (datamesh-reference-arch-python/examples/lgtm-datamesh/demos/
# {walkthrough.sh,demo-order.sh,lib/endpoints.sh}):
#   - `set -uo pipefail` (not `-e`) so a demo manages failures explicitly —
#     via `fail` — and can dump diagnostics instead of aborting mid-assertion
#     on some unrelated command's non-zero exit.
#   - a success-flag + EXIT trap (`demo_begin`/`demo_ok`) so a script that
#     short-circuits (returns/exits 0 without ever reaching its last
#     assertion) can never be mistaken for a passing demo.
#   - every assertion checks positive content (a parsed field, an exact
#     status code, a specific byte) — never just "exit code was zero".
#
# Every demo-*.sh must start like this:
#
#   #!/usr/bin/env bash
#   set -uo pipefail
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib/_demo.sh"
#   demo_begin "demo-order"
#   ...
#   demo_ok
#
# `demo_begin` installs the EXIT trap; `demo_ok` raises the success flag. Any
# `fail` call, or any early `exit`/falling off the end without calling
# `demo_ok`, is caught by the trap and reported as a failure — even if the
# last command run happened to exit 0.

# Idempotent: sourcing this file twice (e.g. a demo that sources it and then
# shells out to a helper that also sources it) must not re-run setup twice.
if [[ -n "${_DEMO_LIB_SOURCED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_DEMO_LIB_SOURCED=1

# Defensive: enforce the required shell mode even if a demo forgets to set it
# itself. Safe to call again if the demo already did (no-op).
set -uo pipefail

# ─── Path resolution (works regardless of caller's CWD) ─────────────────────
# Resolved relative to this file's own location (demos/lib/_demo.sh), not the
# sourcing script's path or the shell's CWD.
_DEMO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_DEMO_LIB_DIR}/../.." && pwd)"
EXAMPLES_DIR="${REPO_ROOT}/examples"
DEMOS_DIR="${REPO_ROOT}/demos"
COMPOSE_FILE="${REPO_ROOT}/compose.yaml"

# ─── Colors (TTY-aware — no escape junk in logs/pipes/CI) ───────────────────
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
    YEL=$'\033[33m'; BLU=$'\033[34m'; RST=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; RST=""
fi

# ─── Core output helpers ─────────────────────────────────────────────────────

step()    { printf '\n%s%s==>%s %s\n' "$BOLD" "$BLU" "$RST" "$1"; }
narrate() { printf '%s  ▸ %s%s\n' "$YEL" "$1" "$RST"; }
info()    { printf '%s    %s%s\n' "$DIM" "$1" "$RST" >&2; }
warn()    { printf '%s⚠ %s%s\n' "$YEL" "$1" "$RST" >&2; }

# fail <message> — print in red to stderr and exit non-zero. If demo_begin
# has run, the EXIT trap below turns this into the standard FAILED banner;
# either way the process exits non-zero.
fail() {
    printf '\n%s✗ FAILED:%s %s\n' "$RED" "$RST" "$1" >&2
    exit 1
}

# check <label> <test-expression> <fix-hint> — one preflight-style assertion.
# <test-expression> is eval'd; a non-zero result prints the fix hint and
# increments the module-level $_DEMO_CHECK_FAILURES counter (read it yourself
# after a batch of checks — this function does not fail the script, so a
# caller can run a full preflight sweep and report every problem at once).
_DEMO_CHECK_FAILURES=0
check() {
    local label="$1" expr="$2" fix="$3"
    if eval "$expr"; then
        printf '  %s✓%s %s\n' "$GRN" "$RST" "$label"
    else
        printf '  %s✗%s %s\n      %sfix:%s %s\n' "$RED" "$RST" "$label" "$DIM" "$RST" "$fix"
        _DEMO_CHECK_FAILURES=$((_DEMO_CHECK_FAILURES + 1))
    fi
}

# ─── Presenter helpers (for walkthrough.sh-style orchestration) ─────────────

# act_header <short> <title> <lede> — section banner for a multi-act script.
_DEMO_ACT_NUM=0
act_header() {
    local title="$2" lede="$3"
    _DEMO_ACT_NUM=$((_DEMO_ACT_NUM + 1))
    printf '\n%s%s═══════════════════════════════════════════════════════════════%s\n' "$BOLD" "$BLU" "$RST"
    printf '%s%s  ACT %d  ·  %s%s\n' "$BOLD" "$BLU" "$_DEMO_ACT_NUM" "$title" "$RST"
    printf '%s%s═══════════════════════════════════════════════════════════════%s\n' "$BOLD" "$BLU" "$RST"
    printf '%s%s%s\n' "$DIM" "$lede" "$RST"
}

# prompt_enter [label] — Enter-to-advance, reading from /dev/tty so it still
# works when stdin is otherwise occupied (e.g. piped input to the script).
prompt_enter() {
    local label="${1:-press Enter to continue}"
    printf '\n%s[%s]%s ' "$BOLD" "$label" "$RST"
    read -r _ </dev/tty || true
}

# run_act <title> <cmd...> — announce, run, and report a sub-command's
# pass/fail without killing the parent script (the caller decides whether to
# `|| exit 1`).
run_act() {
    local title="$1"; shift
    printf '%s  ↻ running: %s%s\n' "$DIM" "$*" "$RST"
    if "$@"; then
        printf '%s  ✓ act passed: %s%s\n' "$GRN" "$title" "$RST"
        return 0
    else
        printf '%s  ✗ act FAILED: %s%s\n' "$RED" "$title" "$RST"
        return 1
    fi
}

# ─── Success-flag + trap pattern ─────────────────────────────────────────────

DEMO_NAME=""
DEMO_SUCCESS=0

_demo_exit_trap() {
    local rc=$?
    trap - EXIT   # don't let the following `exit` calls re-enter this trap
    if (( DEMO_SUCCESS == 1 )); then
        exit "$rc"
    fi
    if (( rc == 0 )); then
        # The script exited 0 without ever calling demo_ok — a short-circuit
        # (stray `return`, an `exit 0` down some branch, etc). Never let that
        # read as success.
        printf '\n%s✗ FAILED:%s %s exited 0 without calling demo_ok (short-circuited?)\n' \
            "$RED" "$RST" "${DEMO_NAME:-demo}" >&2
        exit 1
    fi
    # Already failing (fail() or an uncaught non-zero exit) — propagate as-is.
    exit "$rc"
}

# demo_begin <name> — call once, near the top, after `require`/arg parsing.
# Installs the EXIT trap that enforces "no success without demo_ok".
demo_begin() {
    DEMO_NAME="${1:-demo}"
    DEMO_SUCCESS=0
    trap '_demo_exit_trap' EXIT
    step "${DEMO_NAME}"
}

# demo_ok — call once, as the last thing a successful demo does.
demo_ok() {
    DEMO_SUCCESS=1
    printf '\n%s✓ SUCCESS%s — %s\n' "$GRN" "$RST" "${DEMO_NAME:-demo}"
}

# ─── Preconditions ───────────────────────────────────────────────────────────

# require <cmd> [cmd...] — assert every named binary is on PATH; fail with an
# install hint listing everything missing (not just the first).
require() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        fail "missing required command(s): ${missing[*]} — install them and retry (e.g. curl, jq, docker, mvn)"
    fi
}

# ─── HTTP waiters and assertions ─────────────────────────────────────────────

# wait_http <url> [timeout_s] — poll (1s interval) until the endpoint answers
# any HTTP response (connection + response, not a specific status). Returns
# non-zero on timeout; callers that need a specific status should follow up
# with assert_http_200 (or assert_json_field against the body).
wait_http() {
    local url="$1" budget="${2:-30}" i
    for (( i = 0; i < budget; i++ )); do
        curl -fsS -o /dev/null --max-time 3 "$url" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

# assert_http_200 <url> — positive-content assertion: the endpoint must
# answer exactly 200, not merely "connected".
assert_http_200() {
    local url="$1" code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo 000)"
    [[ "$code" == "200" ]] || fail "expected HTTP 200 from $url, got $code"
}

# assert_json_field <json> <jq-filter> <expected> — parse <json> with
# <jq-filter> (raw output) and assert it equals <expected> exactly.
assert_json_field() {
    local json="$1" filter="$2" expected="$3" actual
    actual="$(jq -r "$filter" <<<"$json" 2>/dev/null)" \
        || fail "jq filter '$filter' failed to parse JSON: $json"
    [[ "$actual" == "$expected" ]] \
        || fail "expected '$filter' == '$expected', got '$actual' (json: $json)"
}

# require_docker_engine — fail fast with the Fedora/RHEL start hint when the
# Docker Engine does not answer.
require_docker_engine() {
    docker info >/dev/null 2>&1 \
        || fail "Docker Engine is not reachable; start it: sudo systemctl start docker (and make sure your user is in the docker group)"
}

# ─── docker compose wrapper (repo-root compose.yaml) ────────────────────────

# compose_up [profile...] — `docker compose -f <repo-root>/compose.yaml
# [--profile p]... up -d`. No args = baseline only (postgres, kafka,
# apicurio, otel-lgtm). Pass e.g. `tools` or `ollama` to add a profile.
compose_up() {
    # The datamesh minikube profile publishes 3000/3100/3200/4317/4318 on the
    # host; compose binds the same ports, so both cannot run at once.
    if [[ "$(docker container inspect -f '{{.State.Running}}' "${MINIKUBE_PROFILE:-datamesh}" 2>/dev/null)" == "true" ]]; then
        fail "the datamesh minikube profile is running and holds host ports 3000/3100/3200/4317/4318 that compose needs; stop it first: minikube stop -p datamesh"
    fi
    local -a args=(-f "$COMPOSE_FILE")
    local p
    for p in "$@"; do
        args+=(--profile "$p")
    done
    args+=(up -d)
    info "docker compose ${args[*]}"
    docker compose "${args[@]}" || fail "docker compose up failed (profiles: ${*:-none})"
}

# compose_down [profile...] [-flag...] — mirror compose_up: pass the same
# profile names you passed to compose_up, or `docker compose down` silently
# leaves profile-gated services (e.g. `ollama`) running. Args starting with "-"
# are forwarded to `down` as flags (e.g. `-v` to also wipe named volumes).
compose_down() {
    local -a args=(-f "$COMPOSE_FILE")
    local -a flags=()
    local a
    for a in "$@"; do
        if [[ "$a" == -* ]]; then
            flags+=("$a")
        else
            args+=(--profile "$a")
        fi
    done
    args+=(down "${flags[@]}")
    info "docker compose ${args[*]}"
    docker compose "${args[@]}" || fail "docker compose down failed"
}

# ─── Local Quarkus dev-mode service lifecycle ───────────────────────────────

# svc_start_dev <module-dir> [port] — background `mvn quarkus:dev` for a
# reactor module (e.g. "$EXAMPLES_DIR/order-service"), binding HTTP to
# [port] (default 8080). Echoes the pidfile path on stdout — pass it to
# svc_stop for cleanup. Output is captured to a logfile (path printed via
# info) rather than interleaved with the demo's own output.
svc_start_dev() {
    local module_dir="$1" port="${2:-8080}" pidfile logfile pid
    [[ -d "$module_dir" ]] || fail "svc_start_dev: module dir not found: $module_dir"
    pidfile="$(mktemp -t demo-svc-pid-XXXXXX)"
    logfile="$(mktemp -t demo-svc-log-XXXXXX)"
    info "starting 'mvn quarkus:dev' in ${module_dir#"${REPO_ROOT}"/} (port $port)"
    info "log: $logfile"
    # `exec` inside the subshell replaces the subshell with the mvn process
    # itself, so $! (captured right after backgrounding) is mvn's real PID —
    # killing it doesn't leave an orphaned wrapper process behind.
    ( cd "$module_dir" && exec mvn -q -Dquarkus.http.port="$port" quarkus:dev >"$logfile" 2>&1 ) &
    pid=$!
    echo "$pid" > "$pidfile"
    echo "$pidfile"
}

# svc_stop <pidfile> — stop a service started with svc_start_dev: TERM, wait
# up to 5s, then KILL if it's still alive. Removes the pidfile. Safe to call
# on an already-stopped service or a missing pidfile (warns, does not fail).
svc_stop() {
    local pidfile="$1" pid i
    if [[ ! -f "$pidfile" ]]; then
        warn "svc_stop: no such pidfile: $pidfile"
        return 0
    fi
    pid="$(cat "$pidfile")"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        info "stopping service (pid $pid)"
        kill "$pid" 2>/dev/null || true
        for ((i = 0; i < 10; i++)); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$pidfile"
    return 0
}
