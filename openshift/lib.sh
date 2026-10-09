# lib.sh — shared helpers for the openshift/ scripts (sourced, not run).
#
# Every script talks to OpenShift Local through the "crc-admin" kubeconfig
# context that `crc start` writes, so no password is ever typed, printed or
# stored. Run `eval "$(crc oc-env)"` first if `oc` is not on PATH.

NS="${DATAMESH_NAMESPACE:-datamesh}"
OCP_CONTEXT="${OCP_CONTEXT:-crc-admin}"
OPENSHIFT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$OPENSHIFT_DIR/.." && pwd)"

# The 7 services built and deployed on OpenShift Local.
SERVICES=(order-service inventory-service payment-service shipping-service
          notification-service review-service graphql-gateway)

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
fail() { printf '\n\xe2\x9c\x97 %s\n' "$1" >&2; exit 1; }

# require_crc: oc on PATH, the crc-admin context reachable, and the API
# server is OpenShift Local's. Fails fast instead of touching another cluster.
require_crc() {
    command -v oc >/dev/null 2>&1 || fail "oc not on PATH: run eval \"\$(crc oc-env)\""
    command -v crc >/dev/null 2>&1 || fail "crc not on PATH"
    crc status 2>/dev/null | grep -q 'OpenShift:.*Running' || fail "OpenShift Local is not running: crc start"
    oc config use-context "$OCP_CONTEXT" >/dev/null 2>&1 \
        || fail "kubeconfig context $OCP_CONTEXT not found (crc start writes it)"
    local api
    api="$(oc whoami --show-server 2>/dev/null)" || fail "cannot reach the OpenShift API"
    [[ "$api" == *api.crc.testing* ]] || fail "context $OCP_CONTEXT points at $api, not OpenShift Local"
}

# wait_for <seconds> <description> <command...>: poll every 5 s until the
# command succeeds.
wait_for() {
    local timeout="$1" what="$2"; shift 2
    local waited=0
    until "$@" >/dev/null 2>&1; do
        (( waited >= timeout )) && fail "timed out after ${timeout}s waiting for $what"
        sleep 5; waited=$(( waited + 5 ))
    done
    ok "$what"
}
