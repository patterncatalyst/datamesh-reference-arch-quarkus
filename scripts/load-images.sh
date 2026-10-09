#!/usr/bin/env bash
#
# scripts/load-images.sh — build the service images the k8s overlay deploys and
# load them into the minikube profile's container runtime.
#
# The stack has no image registry. k8s/overlays/minikube deploys
# datamesh/<service>:latest with imagePullPolicy: IfNotPresent, so each image
# has to exist inside the cluster before the Deployments can start; otherwise
# the pods sit in ImagePullBackOff (the kubelet tries Docker Hub, where these
# images do not exist).
#
# The profile runs the containerd runtime (MINIKUBE_RUNTIME in
# setup-profile.sh), so `eval $(minikube docker-env)` does not apply: it only
# works with the docker runtime. Instead, build with the host's docker and copy
# each image in with `minikube image load`.
#
# Build context is the repo root for every service: each Containerfile's
# builder stage copies the whole examples/ Maven reactor so domain-model and
# contracts resolve as reactor modules.
#
# Usage:
#   ./scripts/load-images.sh                  # build + load all four, restart running Deployments
#   ./scripts/load-images.sh order-service    # one or more named services
#   SKIP_BUILD=1 ./scripts/load-images.sh     # load images already built on the host
#
# Environment:
#   MINIKUBE_PROFILE   profile to load into (default: datamesh)
#   SKIP_BUILD         1 = skip docker build, load existing host images
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE="${MINIKUBE_PROFILE:-datamesh}"
NS="datamesh"
TAG="latest"
SKIP_BUILD="${SKIP_BUILD:-0}"

ALL_SERVICES=(order-service inventory-service notification-service graphql-gateway)
if (( $# > 0 )); then
    SERVICES=("$@")
else
    SERVICES=("${ALL_SERVICES[@]}")
fi

fail() { printf '\n\xe2\x9c\x97 %s\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

command -v docker   >/dev/null 2>&1 || fail "docker not in PATH"
command -v minikube >/dev/null 2>&1 || fail "minikube not in PATH"
minikube status -p "$PROFILE" >/dev/null 2>&1 \
    || fail "minikube profile '${PROFILE}' is not running; run ./scripts/bootstrap.sh first"

for svc in "${SERVICES[@]}"; do
    cf="${REPO_ROOT}/examples/${svc}/src/main/docker/Containerfile.multistage"
    [[ -f "$cf" ]] || fail "no Containerfile for '${svc}' at ${cf#"${REPO_ROOT}/"}"
done

for svc in "${SERVICES[@]}"; do
    image="datamesh/${svc}:${TAG}"
    if [[ "$SKIP_BUILD" != "1" ]]; then
        step "build ${image}"
        docker build \
            -f "${REPO_ROOT}/examples/${svc}/src/main/docker/Containerfile.multistage" \
            -t "$image" "$REPO_ROOT" \
            || fail "docker build failed for ${svc}"
    else
        docker image inspect "$image" >/dev/null 2>&1 \
            || fail "SKIP_BUILD=1 but ${image} is not on the host; build it first"
    fi
    step "load ${image} into profile ${PROFILE}"
    minikube image load "$image" -p "$PROFILE" || fail "minikube image load failed for ${svc}"
done

step "images in profile ${PROFILE}"
minikube image ls -p "$PROFILE" | grep -E 'datamesh/' || true

# Restart Deployments that already exist so they pick up the new image.
# Deployments scaled to zero by KEDA have no pods to restart; they use the new
# image the next time they scale up.
if command -v kubectl >/dev/null 2>&1; then
    restarted=()
    for svc in "${SERVICES[@]}"; do
        if kubectl --context "$PROFILE" get deployment "$svc" -n "$NS" >/dev/null 2>&1; then
            if kubectl --context "$PROFILE" rollout restart "deployment/${svc}" -n "$NS" >/dev/null; then
                printf '  restarted deployment/%s\n' "$svc"
                restarted+=("$svc")
            fi
        fi
    done
    # Wait for the restarted rollouts so callers never hit a pod that is still
    # being replaced (the mesh answers 503 until the new pod is in the
    # endpoints). A Deployment scaled to zero finishes immediately. Waiting is
    # best effort: a failed kubectl call here warns and never aborts the load.
    for dep in "${restarted[@]+"${restarted[@]}"}"; do
        kubectl --context "$PROFILE" rollout status "deploy/${dep}" -n "$NS" --timeout=180s >/dev/null \
            || printf '    WARN: deploy/%s did not finish rolling out within 180s\n' "$dep" >&2
        # Then wait up to 120s for the replaced pods to finish terminating:
        # while an old pod drains, a request on the NodePort can still land on
        # it and get a 503 from its sidecar.
        sel="$(kubectl --context "$PROFILE" get deploy "$dep" -n "$NS" \
            -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}' 2>/dev/null)" || true
        sel="${sel%,}"
        if [[ -n "$sel" ]]; then
            for _ in $(seq 1 60); do
                terminating="$(kubectl --context "$PROFILE" get pods -n "$NS" -l "$sel" \
                    -o go-template='{{range .items}}{{if .metadata.deletionTimestamp}}x{{end}}{{end}}' 2>/dev/null)" || true
                [[ -z "$terminating" ]] && break
                sleep 2
            done
        fi
    done
fi

printf '\n==> Done. Deploy or update the apps with: kubectl apply -k k8s/overlays/minikube\n'
