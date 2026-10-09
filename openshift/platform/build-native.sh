#!/usr/bin/env bash
#
# build-native.sh — order-service as a native executable, compiled inside
# OpenShift Local. The host only runs Maven with -Dquarkus.native.sources-only
# (the jar, its libraries and native-image.args); a Docker-strategy binary
# build then runs native-image in the Mandrel builder image and pushes
# ImageStream tag order-service-native:v1. No container engine on the host.
#
#   ./openshift/platform/build-native.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
PLATFORM="$OPENSHIFT_DIR/platform"

require_crc
oc get project "$NS" >/dev/null 2>&1 || fail "project $NS missing: run install-infra.sh first"

step "1/3 native-image sources on the host"
# Avro's ClassSecurityValidator reads org.apache.avro.SERIALIZABLE_PACKAGES in
# a static initializer, and Quarkus initialises it while native-image runs.
# The allow-list therefore has to reach the image builder's JVM (-J-D); a -D
# on the running binary comes too late and every send fails with
# "SecurityException: Forbidden capstone...".
AVRO_PACKAGES="capstone.order.v1"
( cd "$REPO_ROOT/examples" && mvn -B -q -pl order-service -am package -DskipTests -Pnative \
    -Dquarkus.native.sources-only=true \
    -Dquarkus.native.additional-build-args="-J-Dorg.apache.avro.SERIALIZABLE_PACKAGES=$AVRO_PACKAGES" ) \
    || fail "mvn -Dquarkus.native.sources-only=true failed"
grep -q "SERIALIZABLE_PACKAGES=$AVRO_PACKAGES" "$REPO_ROOT/examples/order-service/target/native-sources/native-image.args" \
    || fail "the Avro allow-list did not reach native-image.args"
SRC="$REPO_ROOT/examples/order-service/target/native-sources"
[[ -f "$SRC/native-image.args" ]] || fail "no $SRC/native-image.args"
ok "$(du -sh "$SRC" | cut -f1) of native sources (GraalVM $(cat "$SRC/graalvm.version"))"

step "2/3 BuildConfig order-service-native"
if ! oc get bc order-service-native -n "$NS" >/dev/null 2>&1; then
    oc new-build --name=order-service-native --binary --strategy=docker \
        --to=order-service-native:v1 -n "$NS" >/dev/null || fail "oc new-build"
fi
# native-image needs memory: give the build pod room, and keep the
# Containerfile out of the sources directory.
oc patch bc order-service-native -n "$NS" --type merge -p \
    '{"spec":{"resources":{"requests":{"cpu":"2","memory":"4Gi"},"limits":{"memory":"8Gi"}},"strategy":{"dockerStrategy":{"dockerfilePath":"Containerfile"}}}}' >/dev/null
CTX="$(mktemp -d)"; trap 'rm -rf "$CTX"' EXIT
cp -r "$SRC/." "$CTX/" && cp "$PLATFORM/native/Containerfile" "$CTX/Containerfile"
ok "build context ready"

step "3/3 native-image in the cluster"
start=$(date +%s)
oc start-build order-service-native --from-dir="$CTX" --follow --wait -n "$NS" > "$CTX.log" 2>&1 \
    || { tail -30 "$CTX.log" >&2; fail "native build failed"; }
ok "order-service-native:v1 in $(( $(date +%s) - start ))s ($(grep -o -E 'Finished generating .* in [^.]*' "$CTX.log" | tail -1))"
rm -f "$CTX.log"
