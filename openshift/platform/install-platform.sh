#!/usr/bin/env bash
#
# install-platform.sh — the whole platform tier on top of the core, in order:
# mesh (with the order-service canary), autoscaling, tracing, the AI
# services, native order-service, then GitOps. Each step is its own script
# and can be run alone.
#
#   ./openshift/platform/install-platform.sh [gitops-revision]   # default: main
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
P="$OPENSHIFT_DIR/platform"

require_crc
run() { local start=$(date +%s); "$@" || fail "$(basename "$1") failed"; ok "$(basename "$1") done in $(( $(date +%s) - start ))s"; }
run "$P/install-mesh.sh" --canary
run "$P/install-keda.sh"
run "$P/install-observability.sh"
run "$P/install-ai.sh"
run "$P/build-native.sh"
run "$OPENSHIFT_DIR/deploy.sh" --set native.enabled=true
run "$P/install-gitops.sh" "${1:-main}"
