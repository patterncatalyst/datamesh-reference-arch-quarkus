#!/usr/bin/env bash
#
# build-images.sh — build the 7 service images inside OpenShift Local.
#
# Maven packages each service on the host (the fast-jar in target/quarkus-app),
# then the quarkus-openshift extension (the `openshift` profile in each service
# pom) uploads it to a binary S2I build on the cluster. The build runs on
# ubi10/openjdk-25 and pushes to the internal registry as ImageStream tag
# <service>:v1 in the datamesh project. No docker, no local registry, and the
# cluster never pulls from Maven Central.
#
#   ./openshift/build-images.sh                    # all 7
#   ./openshift/build-images.sh order-service      # just one
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_JVM_IMAGE="registry.access.redhat.com/ubi10/openjdk-25:1.24-15"
TAG="v1"

require_crc
oc get project "$NS" >/dev/null 2>&1 || fail "project $NS missing: run ./openshift/install-infra.sh first"
command -v mvn >/dev/null 2>&1 || fail "mvn not on PATH"

targets=("$@")
(( ${#targets[@]} )) || targets=("${SERVICES[@]}")
modules="$(IFS=,; echo "${targets[*]}")"

step "Building ${#targets[@]} image(s) in-cluster: $modules"
# quarkus.openshift.version sets the BuildConfig's output tag; in 3.39.5
# quarkus.container-image.tag alone leaves it at the project version.
( cd "$REPO_ROOT/examples" && mvn -B -q -pl "$modules" -am package -DskipTests -Popenshift \
    -Dquarkus.container-image.build=true \
    -Dquarkus.container-image.tag="$TAG" \
    -Dquarkus.openshift.version="$TAG" \
    -Dquarkus.openshift.base-jvm-image="$BASE_JVM_IMAGE" \
    -Dquarkus.kubernetes-client.namespace="$NS" \
    -Dquarkus.kubernetes.deploy=false ) || fail "Maven/S2I build failed (oc get builds -n $NS; oc logs build/<name> -n $NS)"

step "Verifying ImageStream tags"
for svc in "${targets[@]}"; do
    ref="$(oc get istag "$svc:$TAG" -n "$NS" -o jsonpath='{.image.dockerImageReference}' 2>/dev/null)" \
        || fail "no ImageStream tag $svc:$TAG"
    ok "$svc:$TAG ${ref##*@}"
done
