#!/usr/bin/env bash
#
# setup-istio.sh — install the Istio control plane into the datamesh cluster
# via the upstream Helm charts (base + istiod), consistent with how every
# other operator in this stack is installed (Strimzi, CNPG, KEDA all use
# `helm upgrade --install`). No istioctl dependency.
#
# Scope: control plane only, no ingress gateway (not needed for the
# substrate; add `istio/gateway` later if an ingress path is needed).
#
# IMPORTANT — mesh selectively, not namespace-wide (lgtm-minikube-stack
# known-issues #1/#2): this script does NOT label the `datamesh` namespace
# for automatic sidecar injection. Namespace-wide injection breaks Job pods
# (hang at 1/2 forever — the sidecar never exits) and CloudNativePG's
# Postgres pods (mTLS collides with the operator's own TLS). Inject
# per-Deployment instead, when a given service actually joins the mesh —
# and it must be a pod-template LABEL, not an annotation: Istio's
# sidecar-injection webhook matches pods via an objectSelector
# (sidecar.istio.io/inject In ["true"]), and a webhook objectSelector is
# evaluated against the pod's labels, never its annotations, so the
# annotation form silently injects nothing in this unlabeled namespace
# (confirmed live on this cluster):
#
#   spec:
#     template:
#       metadata:
#         labels:
#           sidecar.istio.io/inject: "true"
#
# See k8s/istio/ for the overlay that applies this label to order-service,
# notification-service, and graphql-gateway (plus the namespace-wide
# PeerAuthentication and the order-service v1/v2 canary).
#
# Istio 1.29+ uses NATIVE sidecars: istio-proxy runs as an initContainer with
# restartPolicy: Always, not a regular container. A meshed pod still reports
# 2/2 Ready; membership checks must inspect `.spec.initContainers`, not just
# `.spec.containers`.
#
# Idempotent: helm upgrade --install.
#
# Usage (from the project root):
#   ./scripts/setup-istio.sh

set -euo pipefail

NS="datamesh"
PROFILE_NAME="datamesh"
ISTIO_SYSTEM="istio-system"
ISTIO_VERSION="${ISTIO_VERSION:-1.29.0}"

step() { printf '\n==> %s\n' "$1"; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH.\n' >&2; exit 1; }

current_context="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$current_context" != "$PROFILE_NAME" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "%s".\n' "$current_context" "$PROFILE_NAME" >&2
    printf 'Switch with: kubectl config use-context %s\n' "$PROFILE_NAME" >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── 1. istio helm repo ──────────────────────────────────────────────────────

step "Ensuring the istio helm repo is registered"
if helm repo list 2>/dev/null | grep -q '^istio[[:space:]]'; then
    helm repo update istio >/dev/null
else
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update istio >/dev/null
fi

# ─── 2. base CRDs, then istiod ───────────────────────────────────────────────

step "Installing istio-base (CRDs) ${ISTIO_VERSION} into ${ISTIO_SYSTEM}"
helm upgrade --install istio-base istio/base \
    --namespace "$ISTIO_SYSTEM" --create-namespace \
    --version "$ISTIO_VERSION" \
    --set defaultRevision=default

step "Installing istiod ${ISTIO_VERSION}"
helm upgrade --install istiod istio/istiod \
    --namespace "$ISTIO_SYSTEM" \
    --version "$ISTIO_VERSION" \
    --wait --timeout 5m

step "Waiting for istiod to be Available"
kubectl rollout status deployment/istiod -n "$ISTIO_SYSTEM" --timeout=5m

# ─── Done ────────────────────────────────────────────────────────────────────

step "Istio control plane is installed."
printf '\nNamespace %s is NOT labeled for auto-injection (by design — see header).\n' "$NS"
printf 'Opt a Deployment into the mesh with a pod-template LABEL (not an annotation):\n'
printf '  kubectl patch deployment <name> -n %s -p \x27{"spec":{"template":{"metadata":{"labels":{"sidecar.istio.io/inject":"true"}}}}}\x27\n' "$NS"
printf 'Or apply the k8s/istio/ overlay directly: kubectl apply -k k8s/istio\n'
printf '\nNext: ./scripts/setup-kiali.sh   (mesh-topology UI wired to the LGTM stack)\n'
