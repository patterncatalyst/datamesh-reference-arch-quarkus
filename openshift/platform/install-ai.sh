#!/usr/bin/env bash
#
# install-ai.sh — the AI tier on OpenShift Local: builds ai-mcp-service and
# ai-rules-service in the cluster, then the chart's ai flag deploys Ollama
# (the compose profile's version), pulls the model and starts both services.
#
#   ./openshift/platform/install-ai.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

require_crc
oc get deployment order-service -n "$NS" >/dev/null 2>&1 || fail "core not deployed: run deploy.sh first"

step "1/3 Build ai-mcp-service and ai-rules-service in the cluster"
"$OPENSHIFT_DIR/build-images.sh" ai-mcp-service ai-rules-service >/dev/null || fail "build-images.sh failed for the AI services"
ok "ai-mcp-service:v1 and ai-rules-service:v1"

step "2/3 Ollama and the model"
"$OPENSHIFT_DIR/deploy.sh" --set ai.enabled=true >/dev/null || fail "deploy.sh with ai.enabled failed"
oc wait job/ollama-pull-model -n "$NS" --for=condition=Complete --timeout=1200s >/dev/null \
    || fail "model pull did not complete (oc logs job/ollama-pull-model -n $NS)"
model="$(helm get values datamesh -n "$NS" --kube-context "$OCP_CONTEXT" -a -o json | jq -r .ai.model)"
oc exec -n "$NS" deploy/ollama -c ollama -- ollama list | grep -q "^${model}" || fail "model $model not listed by ollama"
ok "ollama serves $model"

step "3/3 AI services"
for d in ai-mcp-service ai-rules-service; do
    oc rollout status "deployment/$d" -n "$NS" --timeout=600s >/dev/null || fail "$d not Ready"
done
ok "ai-mcp-service and ai-rules-service Ready"
