#!/usr/bin/env bash
#
# tunnel-services.sh — stable host access to in-cluster services via SSH
# tunnels through the minikube node, instead of `kubectl port-forward`
# (which drops under load and on idle timeouts — see the lgtm-minikube-stack
# skill's references/known-issues.md, Issue 0).
#
# Requires the NodePort services installed by setup-lgtm.sh / setup-kiali.sh /
# setup-apicurio.sh at the fixed ports below (the allocation map in the
# skill's references/ports-and-endpoints.md).
#
# Docker driver: the minikube node is a `docker` container; SSH is proxied
# through the container's mapped port, user `docker` (same as the podman
# driver's convention — only the port-lookup command differs).
#
# Usage:
#   ./scripts/tunnel-services.sh
#   pkill -f 'ssh.*docker@127.0.0.1'   # tear the tunnels down

set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-datamesh}"
NS="${NAMESPACE:-datamesh}"

echo "Starting SSH tunnels to NodePort services (minikube profile: $PROFILE)"

# Kill previous tunnels
pkill -f "ssh.*docker@127.0.0.1" 2>/dev/null || true
sleep 1

# Resolve minikube SSH connection details
SSH_KEY="$(minikube ssh-key -p "$PROFILE")"
SSH_PORT="$(docker port "$PROFILE" 22/tcp 2>/dev/null | head -1 | cut -d: -f2)"

if [[ -z "$SSH_PORT" ]]; then
  echo "ERROR: Could not detect SSH port for profile '$PROFILE'"
  echo "Is minikube running? Try: minikube start -p $PROFILE"
  exit 1
fi

tunnel() {
  local local_port=$1 node_port=$2 label=$3
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
      -i "$SSH_KEY" -p "$SSH_PORT" \
      -L "${local_port}:localhost:${node_port}" \
      -N -f docker@127.0.0.1
  echo "  + $label"
}

# ── Observability (LGTM) ───────────────────────────────────────
tunnel 3000 30300 "Grafana:          http://localhost:3000 (admin/admin)"
tunnel 4317 30417 "OTLP gRPC:        localhost:4317"
tunnel 4318 30418 "OTLP HTTP:        http://localhost:4318"
tunnel 9009 30009 "Mimir:            http://localhost:9009"
tunnel 3100 30100 "Loki:             http://localhost:3100"
tunnel 3200 30320 "Tempo:            http://localhost:3200"

# ── Mesh UI (Istio + Kiali) ─────────────────────────────────────
if kubectl get svc kiali -n istio-system >/dev/null 2>&1 || kubectl get svc kiali-server -n istio-system >/dev/null 2>&1; then
  tunnel 20001 30201 "Kiali:            http://localhost:20001/kiali"
fi

# ── Schema registry (Apicurio) ──────────────────────────────────
if kubectl get svc apicurio -n "$NS" >/dev/null 2>&1; then
  tunnel 8084 30084 "Apicurio:         http://localhost:8084/apis/registry/v3"
fi

echo ""
echo "SSH tunnels are stable — no more port-forward drops."
echo "Kill with: pkill -f 'ssh.*docker@127.0.0.1'"
