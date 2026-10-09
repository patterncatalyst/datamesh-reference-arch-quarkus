#!/usr/bin/env bash
#
# setup-istio.sh — install the Istio control plane into the datamesh cluster
# with Helm (base + istiod charts), consistent with how every other operator
# in this stack is installed (Strimzi, CNPG, KEDA all use
# `helm upgrade --install`). No istioctl dependency.
#
# Chart source: the pinned Istio release tarball. Istio 1.31 is not published
# to the istio-release Helm repository (its index stops at 1.30.5 and
# 1.31.0-rc.0; the 1.31.1 chart archives answer 404), so the charts come from
# the release's own manifests/charts/ directory. The tarball is downloaded from
# the GitHub release once, checked against its published .sha256, and kept at
# ~/.local/share/istio-<version> (the same place minikube-on-fedora's
# setup-istio.sh extracts it, so either repo reuses the other's download).
# Nothing is written to ~/.local/bin.
#
# istioctl is optional here. If one is on PATH, its client version is checked
# against ISTIO_VERSION, because a different istioctl misreports this control
# plane; the matching binary is $ISTIO_HOME/bin/istioctl.
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
ISTIO_VERSION="${ISTIO_VERSION:-1.31.1}"
ISTIO_ARCH="${ISTIO_ARCH:-amd64}"
ISTIO_HOME="${ISTIO_HOME:-${HOME}/.local/share/istio-${ISTIO_VERSION}}"
BASE_CHART="${ISTIO_HOME}/manifests/charts/base"
ISTIOD_CHART="${ISTIO_HOME}/manifests/charts/istio-control/istio-discovery"

step() { printf '\n==> %s\n' "$1"; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH.\n' >&2; exit 1; }
command -v curl    >/dev/null 2>&1 || { printf 'ERROR: curl not in PATH.\n' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { printf 'ERROR: sha256sum not in PATH.\n' >&2; exit 1; }

current_context="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$current_context" != "$PROFILE_NAME" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "%s".\n' "$current_context" "$PROFILE_NAME" >&2
    printf 'Switch with: kubectl config use-context %s\n' "$PROFILE_NAME" >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── 1. Istio release (charts + istioctl), pinned and checksum-verified ──────

step "Ensuring Istio ${ISTIO_VERSION} is unpacked at ${ISTIO_HOME}"
if [[ -f "${BASE_CHART}/Chart.yaml" && -f "${ISTIOD_CHART}/Chart.yaml" ]]; then
    printf 'Already present.\n'
else
    tarball="istio-${ISTIO_VERSION}-linux-${ISTIO_ARCH}.tar.gz"
    url="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/${tarball}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "${tmp}/${tarball}" "$url"
    curl -fsSL -o "${tmp}/${tarball}.sha256" "${url}.sha256"
    (cd "$tmp" && sha256sum -c "${tarball}.sha256") \
        || { printf 'ERROR: checksum mismatch for %s\n' "$tarball" >&2; exit 1; }
    mkdir -p "$(dirname "$ISTIO_HOME")"
    tar -xzf "${tmp}/${tarball}" -C "$tmp"
    rm -rf "$ISTIO_HOME"
    mv "${tmp}/istio-${ISTIO_VERSION}" "$ISTIO_HOME"
fi
for chart in "$BASE_CHART" "$ISTIOD_CHART"; do
    chart_version="$(sed -n 's/^version: *//p' "${chart}/Chart.yaml")"
    [[ "$chart_version" == "$ISTIO_VERSION" ]] \
        || { printf 'ERROR: %s is chart version %s, expected %s.\n' "$chart" "$chart_version" "$ISTIO_VERSION" >&2; exit 1; }
done

# istioctl is optional; a mismatched client misreports this control plane.
if command -v istioctl >/dev/null 2>&1; then
    istioctl_version="$(istioctl version --remote=false 2>/dev/null | head -1 \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
    if [[ "$istioctl_version" == "$ISTIO_VERSION" ]]; then
        printf 'istioctl on PATH is %s, matching the pinned version.\n' "$istioctl_version"
    else
        printf 'WARNING: istioctl on PATH is %s, not the pinned %s.\n' "${istioctl_version:-unknown}" "$ISTIO_VERSION" >&2
        printf '         Use %s/bin/istioctl for this mesh.\n' "$ISTIO_HOME" >&2
    fi
fi

# ─── 2. Minor-version skip guard ─────────────────────────────────────────────
# Istio upgrades in place one minor version at a time. A control plane two or
# more minors behind (for example 1.29 -> 1.31) must be removed first.

running_tag="$(kubectl get deployment istiod -n "$ISTIO_SYSTEM" \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://' || true)"
if [[ "$running_tag" =~ ^1\.([0-9]+)\. ]]; then
    running_minor="${BASH_REMATCH[1]}"
    pinned_minor="$(cut -d. -f2 <<<"$ISTIO_VERSION")"
    if (( pinned_minor - running_minor > 1 )); then
        printf 'ERROR: istiod %s is running; Istio cannot upgrade in place to %s (more than one minor version).\n' "$running_tag" "$ISTIO_VERSION" >&2
        printf 'Remove it first: helm uninstall istiod istio-base -n %s, then re-run this script\n' "$ISTIO_SYSTEM" >&2
        printf '(or recreate the cluster: ./scripts/setup-profile.sh --replace, then ./scripts/bootstrap.sh).\n' >&2
        exit 1
    fi
fi

# ─── 3. base CRDs, then istiod ───────────────────────────────────────────────

step "Installing istio-base (CRDs) ${ISTIO_VERSION} into ${ISTIO_SYSTEM}"
helm upgrade --install istio-base "$BASE_CHART" \
    --namespace "$ISTIO_SYSTEM" --create-namespace \
    --set defaultRevision=default

step "Installing istiod ${ISTIO_VERSION}"
helm upgrade --install istiod "$ISTIOD_CHART" \
    --namespace "$ISTIO_SYSTEM" \
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
