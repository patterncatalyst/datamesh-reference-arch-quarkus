#!/usr/bin/env bash
#
# endpoints.sh — the ONE source of truth for host access to the datamesh cluster.
#
# Every host-facing service is a fixed NodePort. The minikube profile publishes
# each NodePort to the host on loopback when the profile is created:
#   minikube start -p datamesh --ports=127.0.0.1:<hostPort>:<nodePort>,...
# so `http://127.0.0.1:<hostPort>` reaches the Service directly. No helper
# process runs and nothing needs to be brought up per demo.
#
# Source this from a demo or from a script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/endpoints.sh"   # from demos/
#   ensure_endpoint grafana                                     # verify one endpoint
#   curl "$(endpoint_url grafana)/api/health"                   # use the fixed host port
#
# The canonical host-port <-> nodePort map lives here and NOWHERE ELSE. If you
# add a service, add one row to _endpoint_row, its name to ENDPOINT_NAMES, and
# set its Service nodePort to the matching value in the setup script.
# Published ports are fixed at profile creation: changing the map requires
# recreating the profile (./scripts/setup-profile.sh --replace), which deletes
# and recreates the cluster, so run ./scripts/bootstrap.sh again.
#
# Does not define wait_http: demos/lib/_demo.sh has its own.
# Safe to `source` under `set -euo pipefail`: only definitions, no side effects.

# ─── Canonical port allocation (host → nodePort) ─────────────────────────────
# TP_* is the host port published on 127.0.0.1 (what YOU curl); NP_* is the
# nodePort the Service exposes.
TP_GRAFANA=3000;      NP_GRAFANA=30300
TP_OTLP_GRPC=4317;    NP_OTLP_GRPC=30417
TP_OTLP_HTTP=4318;    NP_OTLP_HTTP=30418
TP_MIMIR=9009;        NP_MIMIR=30009
TP_LOKI=3100;         NP_LOKI=30100
TP_TEMPO=3200;        NP_TEMPO=30320
TP_KIALI=20001;       NP_KIALI=30201
TP_APICURIO=8084;     NP_APICURIO=30084

EP_PROFILE="${MINIKUBE_PROFILE:-datamesh}"

# Namespaces, matching the setup scripts: setup-lgtm.sh honours OBS_NAMESPACE;
# the datamesh namespace (Strimzi, Apicurio, workloads) is APP_NAMESPACE, or
# DATAMESH_NS, default datamesh. Istio and Kiali stay in istio-system.
EP_OBS_NS="${OBS_NAMESPACE:-observability}"
EP_APP_NS="${APP_NAMESPACE:-${DATAMESH_NS:-datamesh}}"

ENDPOINT_NAMES=(grafana otlp-grpc otlp-http mimir loki tempo kiali apicurio)

# name → "host node namespace svc label [path]"  (svc/namespace used for Service
# checks; the optional path is shown after the URL for display only)
_endpoint_row() {
    case "$1" in
        grafana)   echo "$TP_GRAFANA $NP_GRAFANA $EP_OBS_NS grafana Grafana" ;;
        otlp-grpc) echo "$TP_OTLP_GRPC $NP_OTLP_GRPC $EP_OBS_NS otel-collector-opentelemetry-collector OTLP-gRPC" ;;
        otlp-http) echo "$TP_OTLP_HTTP $NP_OTLP_HTTP $EP_OBS_NS otel-collector-opentelemetry-collector OTLP-HTTP" ;;
        mimir)     echo "$TP_MIMIR $NP_MIMIR $EP_OBS_NS mimir-nginx Mimir" ;;
        loki)      echo "$TP_LOKI $NP_LOKI $EP_OBS_NS loki-gateway Loki" ;;
        tempo)     echo "$TP_TEMPO $NP_TEMPO $EP_OBS_NS tempo Tempo" ;;
        kiali)     echo "$TP_KIALI $NP_KIALI istio-system kiali Kiali /kiali" ;;
        apicurio)  echo "$TP_APICURIO $NP_APICURIO $EP_APP_NS apicurio Apicurio /apis/registry/v3" ;;
        *) return 1 ;;
    esac
}

# endpoint_port <name> → echoes the canonical host port
endpoint_port() {
    local row; row="$(_endpoint_row "$1")" || return 1
    echo "${row%% *}"   # first field is the host port
}

# endpoint_url <name> → http://127.0.0.1:<host>  (no display path)
endpoint_url() {
    local p; p="$(endpoint_port "$1")" || return 1
    echo "http://127.0.0.1:${p}"
}

# _extra_pairs → lines "<host> <node>" for EXTRA_NODE_PORTS. Items (comma
# separated, whitespace around items ignored) may be "p" (meaning p:p),
# "hp:np" or "127.0.0.1:hp:np". Each port must be numeric 1-65535. Anything
# else, including a 0.0.0.0: or other IP prefix, is an error: message on
# stderr, return 1, nothing printed. A host port or nodePort that duplicates
# the built-in map or another extra entry is also an error.
_extra_pairs() {
    local item hp np out="" IFS=',' name row mhp mnp
    local -a extra
    local seen_hp=" " seen_np=" "
    for name in "${ENDPOINT_NAMES[@]}"; do
        row="$(_endpoint_row "$name")"
        IFS=" " read -r mhp mnp _ <<<"$row"
        seen_hp+="${mhp} "; seen_np+="${mnp} "
    done
    read -ra extra <<<"${EXTRA_NODE_PORTS:-}"
    for item in "${extra[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"; item="${item%"${item##*[![:space:]]}"}"
        [[ -z "$item" ]] && continue
        if [[ "$item" =~ ^([0-9]+)$ ]]; then hp="${BASH_REMATCH[1]}"; np="$hp"
        elif [[ "$item" =~ ^([0-9]+):([0-9]+)$ ]]; then hp="${BASH_REMATCH[1]}"; np="${BASH_REMATCH[2]}"
        elif [[ "$item" =~ ^127\.0\.0\.1:([0-9]+):([0-9]+)$ ]]; then hp="${BASH_REMATCH[1]}"; np="${BASH_REMATCH[2]}"
        else
            printf 'endpoints: invalid EXTRA_NODE_PORTS item "%s": use p, hp:np or 127.0.0.1:hp:np (loopback only)\n' "$item" >&2
            return 1
        fi
        if (( 10#$hp < 1 || 10#$hp > 65535 || 10#$np < 1 || 10#$np > 65535 )); then
            printf 'endpoints: invalid EXTRA_NODE_PORTS item "%s": ports must be 1-65535\n' "$item" >&2
            return 1
        fi
        hp=$((10#$hp)); np=$((10#$np))
        if [[ "$seen_hp" == *" $hp "* ]]; then
            printf 'endpoints: invalid EXTRA_NODE_PORTS item "%s": host port %s is already published (built-in map or an earlier extra)\n' "$item" "$hp" >&2
            return 1
        fi
        if [[ "$seen_np" == *" $np "* ]]; then
            printf 'endpoints: invalid EXTRA_NODE_PORTS item "%s": nodePort %s is already published (built-in map or an earlier extra)\n' "$item" "$np" >&2
            return 1
        fi
        seen_hp+="${hp} "; seen_np+="${np} "
        out+="${hp} ${np}"$'\n'
    done
    printf '%s' "$out"
}

# node_ports_arg → "127.0.0.1:<host>:<node>,..." for `minikube start --ports=`.
# EXTRA_NODE_PORTS ("p", "hp:np" or "127.0.0.1:hp:np") is appended. Returns 1
# (nothing on stdout) if EXTRA_NODE_PORTS is invalid.
node_ports_arg() {
    local name row hp np out=() line extra
    for name in "${ENDPOINT_NAMES[@]}"; do
        row="$(_endpoint_row "$name")"
        read -r hp np _ <<<"$row"
        out+=("127.0.0.1:${hp}:${np}")
    done
    extra="$(_extra_pairs)" || return 1
    while IFS= read -r line; do
        [[ -n "$line" ]] && out+=("127.0.0.1:${line% *}:${line#* }")
    done <<<"$extra"
    local IFS=','
    echo "${out[*]}"
}

# assert_host_ports_free [<own-host-ports>] — every host port in the map (plus
# EXTRA_NODE_PORTS) must be free on the host. <own-host-ports> is a
# space-separated list of ports to skip (ports this same profile currently
# publishes while it is RUNNING). A stopped profile holds no listeners, so call
# it with no argument before `minikube start` of a stopped profile. Prints one
# error per busy port on stderr; returns 1 if any is busy or ss is missing.
assert_host_ports_free() {
    local own=" ${1:-} " pa spec hp busy=0
    local -a specs
    if ! command -v ss >/dev/null 2>&1; then
        printf 'ERROR: ss not in PATH (iproute2); needed to check host ports are free.\n' >&2
        return 1
    fi
    pa="$(node_ports_arg)" || return 1
    IFS=',' read -ra specs <<<"$pa"
    for spec in "${specs[@]}"; do
        hp="$(cut -d: -f2 <<<"$spec")"
        [[ "$own" == *" $hp "* ]] && continue
        if [[ -n "$(ss -Htln "sport = :$hp" 2>/dev/null)" ]]; then
            printf 'ERROR: host port %s is already in use: something else is listening; this workshop runs in isolation, so stop other clusters and compose stacks first.\n' "$hp" >&2
            busy=1
        fi
    done
    return "$busy"
}

# ─── Published-port inspection ───────────────────────────────────────────────

# _port_bindings_json → PortBindings JSON of the profile container (empty on error)
_port_bindings_json() {
    # The profile is a docker-driver container named after the profile
    # (setup-profile.sh); its published ports live in HostConfig.
    docker container inspect --format '{{json .HostConfig.PortBindings}}' "$EP_PROFILE" 2>/dev/null || true
}

# _parse_bindings <loopback|other> — reads PortBindings JSON on stdin.
#   loopback → "<containerPort> <hostPort>" for HostIp == 127.0.0.1, HostPort set
#   other    → "<containerPort> <HostIp>:<HostPort>" for any other HostIp
_parse_bindings() {
    python3 -c '
import json, sys
mode = sys.argv[1]
try:
    data = json.loads(sys.stdin.read() or "null") or {}
except Exception:
    sys.exit(0)
for key, binds in sorted(data.items()):
    port = key.split("/")[0]
    for b in binds or []:
        ip, hp = b.get("HostIp", ""), b.get("HostPort", "")
        if mode == "loopback" and ip == "127.0.0.1" and hp:
            print(port, hp)
        elif mode == "other" and ip != "127.0.0.1":
            print(port, "%s:%s" % (ip, hp))
' "$1" 2>/dev/null || true
}

# published_ports → lines "<nodePort> <hostPort>" bound on 127.0.0.1
published_ports() { _port_bindings_json | _parse_bindings loopback; return 0; }

# nonloopback_ports → lines "<containerPort> <HostIp>:<HostPort>" not on 127.0.0.1
nonloopback_ports() { _port_bindings_json | _parse_bindings other; return 0; }

# profile_container_exists → 0 if the profile's node container exists
profile_container_exists() { docker container inspect "$EP_PROFILE" >/dev/null 2>&1; }

# profile_container_running → 0 if the profile's node container is running
profile_container_running() {
    [[ "$(docker container inspect -f '{{.State.Running}}' "$EP_PROFILE" 2>/dev/null)" == "true" ]]
}

# _require_python → 0 if python3 exists, else prints why and returns 1
_require_python() {
    command -v python3 >/dev/null 2>&1 && return 0
    printf 'endpoints: python3 is required to read port bindings\n' >&2
    return 1
}

# docker_engine_ok → 0 if the Docker Engine answers; else a hint on stderr, 1
docker_engine_ok() {
    docker info >/dev/null 2>&1 && return 0
    local ctx
    ctx="$(docker context show 2>/dev/null || true)"
    printf 'Docker Engine is not reachable (context: %s). Run: sudo systemctl start docker; make sure your user is in the docker group (sudo usermod -aG docker $USER, then log in again); docker context use default.\n' "${ctx:-unknown}" >&2
    return 1
}

# check_published_ports — verify every required pair is published on loopback
# and nothing is bound off-loopback. Returns 1 with a hint on any problem.
check_published_ports() {
    local pub bad name row hp np msg="" line
    _require_python || return 1
    pub="$(published_ports)"
    bad="$(nonloopback_ports)"
    local pairs=()
    for name in "${ENDPOINT_NAMES[@]}"; do
        row="$(_endpoint_row "$name")"; read -r hp np _ <<<"$row"
        pairs+=("$hp $np")
    done
    local extra
    extra="$(_extra_pairs)" || return 1
    while IFS= read -r line; do [[ -n "$line" ]] && pairs+=("$line"); done <<<"$extra"
    local p
    for p in "${pairs[@]}"; do
        hp="${p%% *}"; np="${p##* }"
        grep -qx "${np} ${hp}" <<<"$pub" || msg+="  missing: 127.0.0.1:${hp} -> nodePort ${np}"$'\n'
    done
    [[ -n "$bad" ]] && while IFS= read -r line; do msg+="  not loopback-only: container port ${line}"$'\n'; done <<<"$bad"
    [[ -z "$msg" ]] && return 0
    {
        printf 'endpoints: profile "%s" does not publish the required ports:\n' "$EP_PROFILE"
        printf '%s' "$msg"
        printf 'Ports are fixed when the profile is created and cannot be added to a running one.\n'
        printf 'Recreate it with: ./scripts/setup-profile.sh --replace\n'
        printf '(--replace deletes and recreates the cluster; run ./scripts/bootstrap.sh again afterwards.)\n'
    } >&2
    return 1
}

# ensure_endpoint <name>[ <name> ...] — verify named endpoints are usable.
# Checks every name (does not stop at the first failure). Returns 0 ok, 1 if any
# port is unpublished or a Service does not match, 2 if a name is unknown (and
# no earlier check failed otherwise). A published port whose Service matches but
# does not answer yet is only a warning (stderr, rc 0): the pod may still be
# rolling out and callers do their own wait_http.
# Reach retries: EP_REACH_TRIES (default 3) attempts, EP_REACH_DELAY (default 2)
# s apart; non-positive-integer values fall back to the defaults.
ensure_endpoint() {
    local name row hp np ns svc label out rc stype nports try overall=0
    local tries="${EP_REACH_TRIES:-3}" delay="${EP_REACH_DELAY:-2}"
    [[ "$tries" =~ ^[0-9]+$ ]] && (( 10#$tries > 0 )) && tries=$((10#$tries)) || tries=3
    [[ "$delay" =~ ^[0-9]+$ ]] && (( 10#$delay > 0 )) && delay=$((10#$delay)) || delay=2
    _require_python || return 1
    for name in "$@"; do
        row="$(_endpoint_row "$name")" || { printf 'endpoints: unknown service "%s"\n' "$name" >&2; (( overall == 0 )) && overall=2; continue; }
        read -r hp np ns svc label _ <<<"$row"
        if ! published_ports | grep -qx "${np} ${hp}"; then
            printf 'endpoints: %s: 127.0.0.1:%s -> nodePort %s is not published by profile "%s"\n' \
                "$name" "$hp" "$np" "$EP_PROFILE" >&2
            printf 'Recreate it with: ./scripts/setup-profile.sh --replace\n' >&2
            printf '(--replace deletes and recreates the cluster; run ./scripts/bootstrap.sh again afterwards.)\n' >&2
            overall=1; continue
        fi
        out="$(kubectl --context "$EP_PROFILE" get svc -n "$ns" "$svc" \
                -o jsonpath='{.spec.type} {.spec.ports[*].nodePort}' 2>/dev/null)" || out=""
        stype="${out%% *}"; nports="${out#* }"
        if [[ "$stype" != "NodePort" && "$stype" != "LoadBalancer" ]] || ! grep -qw -- "$np" <<<"$nports"; then
            printf 'endpoints: %s: svc/%s in %s: expected NodePort %s, got "%s"\n' \
                "$name" "$svc" "$ns" "$np" "${out:-<not found>}" >&2
            overall=1; continue
        fi
        rc=0
        for (( try=1; try<=tries; try++ )); do
            rc=0
            curl -s -o /dev/null --max-time 3 "http://127.0.0.1:${hp}/" >/dev/null 2>&1 || rc=$?
            [[ "$rc" != 7 && "$rc" != 28 ]] && break
            (( try < tries )) && sleep "$delay"
        done
        if [[ "$rc" == 7 || "$rc" == 28 ]]; then
            printf 'endpoints: warning: %s: http://127.0.0.1:%s not answering after %s tries (curl exit %s); continuing\n' \
                "$name" "$hp" "$tries" "$rc" >&2
        fi
    done
    return "$overall"
}

# ensure_node_forwarding — the node image starts Docker once at first boot,
# before minikube masks it. That Docker can leave the node's iptables FORWARD
# policy at DROP, which kindnet does not expect: pod-to-pod and pod-to-Service
# traffic is silently dropped, CoreDNS times out and nothing becomes Ready.
# This guard resets the policy to ACCEPT when it is DROP and is a no-op
# otherwise. The rule lives in the node container's network namespace, not on
# the host.
ensure_node_forwarding() {
    local rules policy
    rules="$(docker exec "$EP_PROFILE" iptables -S FORWARD 2>/dev/null)" || true
    if [[ -z "$rules" ]]; then
        printf 'WARNING: could not read the FORWARD policy inside node %s (docker exec failed); skipping the guard.\n' "$EP_PROFILE" >&2
        return 0
    fi
    policy="$(awk '$1 == "-P" { print $3 }' <<<"$rules")"
    [[ "$policy" == "DROP" ]] || return 0
    printf '    node FORWARD policy is DROP (left by the node image'"'"'s Docker); setting ACCEPT for pod traffic\n'
    docker exec "$EP_PROFILE" iptables -P FORWARD ACCEPT \
        || printf 'WARNING: could not set the FORWARD policy to ACCEPT in node %s.\n' "$EP_PROFILE" >&2
    return 0
}
