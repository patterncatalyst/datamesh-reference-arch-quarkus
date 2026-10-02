#!/usr/bin/env bash
#
# setup-profile.sh — create (or replace) the minikube profile sized for the
# datamesh-reference-arch-quarkus stack (Istio + Kiali + KEDA + LGTM + Strimzi
# + CloudNativePG + Apicurio all ON).
#
# Docker toolchain: uses --driver=docker and --container-runtime=containerd.
# No podman (repo-wide convention — see CLAUDE.md).
#
# Idempotent: safe to re-run. The profile is replaceable with --replace if you
# want to start fresh (deletes the existing profile first).
#
# Usage:
#   ./setup-profile.sh             # start (or do nothing if already running)
#   ./setup-profile.sh --replace   # delete first, then start fresh

set -euo pipefail

PROFILE_NAME="datamesh"
MEMORY="${MINIKUBE_MEMORY:-24g}"
CPUS="${MINIKUBE_CPUS:-16}"
DISK="${MINIKUBE_DISK:-80g}"
RUNTIME="${MINIKUBE_RUNTIME:-containerd}"
DRIVER="${MINIKUBE_DRIVER:-docker}"

REPLACE=0
if [[ "${1:-}" == "--replace" ]]; then
    REPLACE=1
fi

# ─── Pre-flight: required tools ─────────────────────────────────────────────
require_tool() {
    local tool="$1"
    local hint="$2"
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'ERROR: %s is not in PATH.\n' "$tool" >&2
        printf '  %s\n' "$hint" >&2
        exit 1
    fi
}

require_tool minikube 'Install minikube: https://minikube.sigs.k8s.io/docs/start/'
require_tool kubectl  'Install kubectl: https://kubernetes.io/docs/tasks/tools/'
require_tool helm     'Install helm: https://helm.sh/docs/intro/install/'
require_tool docker   'Install Docker Engine/Desktop: https://docs.docker.com/get-docker/'

# ─── Pre-flight: kernel limits ──────────────────────────────────────────────
# Many controllers + many pods = many inotify watches. Fedora's default
# fs.inotify.max_user_instances=128 is insufficient for this stack (see the
# lgtm-minikube-stack skill's references/preflight-and-prerequisites.md).
inotify_instances=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
if (( inotify_instances < 256 )); then
    printf 'ERROR: fs.inotify.max_user_instances is %d (need >= 256).\n' "$inotify_instances" >&2
    printf 'Apply this kernel-limits tweak before continuing:\n' >&2
    printf '  sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF\n' >&2
    printf '  fs.inotify.max_user_instances = 512\n' >&2
    printf '  fs.inotify.max_user_watches = 524288\n' >&2
    printf '  EOF\n' >&2
    printf '  sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf\n' >&2
    exit 1
fi

# ─── Pre-flight: other minikube profiles ───────────────────────────────────
running_profiles=$(minikube profile list -o json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for p in data.get("valid", []):
        if p["Name"] != "'"$PROFILE_NAME"'" and p.get("Status") == "Running":
            print(p["Name"])
except Exception:
    pass
' 2>/dev/null || true)

if [[ -n "$running_profiles" ]]; then
    printf 'WARNING: other minikube profiles are running and will compete for RAM:\n' >&2
    printf '%s\n' "$running_profiles" | sed 's/^/  - /' >&2
    printf 'Recommended: stop them with `minikube stop -p <name>` before continuing.\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── Profile setup ─────────────────────────────────────────────────────────
if minikube status -p "$PROFILE_NAME" >/dev/null 2>&1; then
    if (( REPLACE )); then
        printf '==> Deleting existing %s profile (--replace specified)\n' "$PROFILE_NAME"
        minikube delete -p "$PROFILE_NAME"
    else
        printf '==> Profile %s already exists and is running. Pass --replace to recreate.\n' "$PROFILE_NAME"
        printf '==> Switching kubectl context to %s\n' "$PROFILE_NAME"
        kubectl config use-context "$PROFILE_NAME"
        printf '==> Done. Current nodes:\n'
        kubectl get nodes
        exit 0
    fi
fi

printf '==> Starting %s profile (%s RAM, %s CPUs, %s disk, %s runtime, %s driver)\n' \
    "$PROFILE_NAME" "$MEMORY" "$CPUS" "$DISK" "$RUNTIME" "$DRIVER"

minikube start -p "$PROFILE_NAME" \
    --memory="$MEMORY" \
    --cpus="$CPUS" \
    --disk-size="$DISK" \
    --container-runtime="$RUNTIME" \
    --driver="$DRIVER" \
    --addons=metrics-server

printf '==> Switching kubectl context to %s\n' "$PROFILE_NAME"
kubectl config use-context "$PROFILE_NAME"

printf '==> Verifying cluster health\n'
kubectl get nodes
kubectl get pods -n kube-system

printf '\n'
printf '==> Profile is ready.\n'
printf '\n'
printf 'Application images are built directly into this profile'\''s docker daemon\n'
printf '(no in-cluster registry):\n'
printf '  eval $(minikube docker-env -p %s)\n' "$PROFILE_NAME"
printf '  docker build -t <service>:v1 examples/<service>\n'
printf '\n'
printf 'Next steps:\n'
printf '  ./scripts/bootstrap.sh             # bring up the full stack\n'
printf '  ./scripts/teardown.sh              # delete this profile\n'
