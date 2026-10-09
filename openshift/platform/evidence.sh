# evidence.sh — platform-tier checks for capture-evidence.sh (sourced, not
# run). Each section runs only when its feature is installed and writes
# $OUT/1N-*.txt; every check fails the capture on a miss. Expects lib.sh,
# $OUT, $GATEWAY, https() and in_pod() from capture-evidence.sh.

mesh_on()   { oc get istio default >/dev/null 2>&1; }
keda_on()   { oc get scaledobject notification-service -n "$NS" >/dev/null 2>&1; }
otel_on()   { oc get instrumentation datamesh-java -n "$NS" >/dev/null 2>&1; }
ai_on()     { oc get deployment ai-mcp-service -n "$NS" >/dev/null 2>&1; }
native_on() { oc get deployment order-service -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -q order-service-native; }
gitops_on() { oc get application datamesh -n openshift-gitops >/dev/null 2>&1; }

# istio_requests_total seen by one pod's sidecar from a given source workload.
inbound_from() {
    oc exec -n "$NS" "$1" -c istio-proxy -- pilot-agent request GET stats/prometheus 2>/dev/null \
        | grep '^istio_requests_total{' | grep 'reporter="destination"' | grep 'request_protocol="http"' \
        | grep "source_workload=\"$2\"" | awk '{s+=$NF} END {print s+0}'
}

evidence_mesh() {
    step "P1 Service mesh (OSSM 3)"
    local f="$OUT/11-mesh.txt" plain v1 v2 a1 a2
    {
        oc get istio default -o jsonpath='Istio {.spec.version}, revision {.status.activeRevisionName}, Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
        oc get csv -n openshift-operators -o custom-columns='CSV:.metadata.name,PHASE:.status.phase' | grep -E 'CSV|servicemesh|kiali'
        printf '\n-- pods: init containers (istio-proxy runs as a native sidecar)\n'
        oc get pods -n "$NS" -l app.kubernetes.io/part-of=datamesh --field-selector=status.phase=Running \
            -o custom-columns='POD:.metadata.name,REV:.metadata.labels.istio\.io/rev,VERSION:.metadata.labels.version,INIT:.spec.initContainers[*].name'
        printf '\n-- PeerAuthentication\n'
        oc get peerauthentication -n "$NS" -o custom-columns='NAME:.metadata.name,MODE:.spec.mtls.mode'
    } > "$f" 2>&1
    # STRICT: plaintext from a pod outside the mesh is reset.
    plain=$(oc exec -n "$NS" deploy/apicurio -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
        http://order-service:8080/q/health/ready 2>/dev/null; echo " exit=$?")
    printf '\n-- plaintext from unmeshed apicurio pod to order-service: %s\n' "$plain" >> "$f"
    [[ "$plain" == *"exit=0"* && "$plain" == 200* ]] && fail "STRICT mTLS not enforced: plaintext call succeeded"
    ok "STRICT mTLS rejects plaintext from outside the mesh"
    if oc get deployment order-service-v2 -n "$NS" >/dev/null 2>&1; then
        v1=$(oc get pod -n "$NS" -l app.kubernetes.io/name=order-service,version=v1 --field-selector=status.phase=Running -o name | head -1)
        v2=$(oc get pod -n "$NS" -l app.kubernetes.io/name=order-service,version=v2 --field-selector=status.phase=Running -o name | head -1)
        a1=$(inbound_from "$v1" graphql-gateway); a2=$(inbound_from "$v2" graphql-gateway)
        in_pod graphql-gateway bash -c 'for i in $(seq 100); do curl -s -o /dev/null http://order-service:8080/q/health/ready; done'
        a1=$(( $(inbound_from "$v1" graphql-gateway) - a1 )); a2=$(( $(inbound_from "$v2" graphql-gateway) - a2 ))
        printf '\n-- canary: 100 requests from graphql-gateway -> v1=%s v2=%s (VirtualService 90/10)\n' "$a1" "$a2" >> "$f"
        (( a1 + a2 == 100 && a2 > 0 && a2 < 30 )) || fail "canary split off: v1=$a1 v2=$a2"
        ok "canary split v1=$a1 v2=$a2 for 90/10"
    fi
    if oc get route kiali -n istio-system >/dev/null 2>&1; then
        local kiali="https://$(oc get route kiali -n istio-system -o jsonpath='{.spec.host}')" tls nodes
        tls=$(https "$kiali/api/namespaces/$NS/tls" | jq -r .status)
        nodes=$(https "$kiali/api/namespaces/graph?namespaces=$NS&graphType=workload&duration=600s" \
            | jq -r '[.elements.nodes[].data | .workload // empty] | unique | join(", ")')
        printf '\n-- Kiali: namespace TLS %s\n-- Kiali graph workloads: %s\n' "$tls" "$nodes" >> "$f"
        [[ "$tls" == MTLS_ENABLED ]] || fail "Kiali reports $tls for $NS"
        ok "Kiali: $NS MTLS_ENABLED, graph has $(tr ',' '\n' <<<"$nodes" | grep -c .) workloads"
    fi
}

evidence_keda() {
    step "P2 Autoscaling (Custom Metrics Autoscaler)"
    local f="$OUT/12-keda.txt" sku="KEDA-BURST-$$" start r a prev="" max=0 t
    in_pod inventory-service curl -fsS -X POST localhost:8080/stock -H 'Content-Type: application/json' \
        -d "{\"sku\":\"$sku\",\"quantityOnHand\":500,\"available\":true}" >/dev/null || fail "seed $sku"
    wait_for 600 "notification-service idle at 0 replicas" \
        bash -c "[[ \"\$(oc get deploy notification-service -n $NS -o jsonpath={.spec.replicas})\" == 0 ]]"
    in_pod graphql-gateway bash -c "for i in \$(seq 15); do curl -fsS -o /dev/null -X POST http://order-service:8080/orders \
        -H 'Content-Type: application/json' -d '{\"customerId\":\"keda-burst\",\"itemSku\":\"$sku\",\"quantity\":1,\"amount\":1.0}'; done" \
        || fail "order burst"
    {
        printf '15 orders on order.placed at %s; ScaledObject min 0, max 10, lagThreshold 5\n' "$(date -u +%T)"
        start=$(date +%s)
        while (( $(date +%s) - start < 420 )); do
            r=$(oc get deploy notification-service -n "$NS" -o jsonpath='{.spec.replicas}')
            a=$(oc get scaledobject notification-service -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Active")].status}')
            (( r > max )) && max=$r
            [[ "$r $a" != "$prev" ]] && { printf '+%ss replicas=%s active=%s\n' "$(( $(date +%s) - start ))" "$r" "$a"; prev="$r $a"; }
            [[ "$r" == 0 && $max -gt 0 ]] && break
            sleep 5
        done
    } > "$f"
    cat "$f" | sed 's/^/    /'
    grep -q 'replicas=0 active=False' <(tail -1 "$f") && grep -q 'replicas=[1-9]' "$f" \
        || fail "no 0 -> N -> 0 cycle observed"
    ok "notification-service scaled 0 -> N -> 0"
}

evidence_otel() {
    step "P3 Tracing (OpenTelemetry Java agent -> otel-lgtm)"
    local f="$OUT/13-tracing.txt" tid spans q
    q=$(jq -nc --arg id "$ORDER_ID" '{query: ("{ order(id: \"" + $id + "\") { id stock { sku } } }")}')
    https -X POST "$GATEWAY/graphql" -H 'Content-Type: application/json' -d "$q" >/dev/null || fail "GraphQL for the trace"
    sleep 15
    tid=$(in_pod lgtm curl -s "localhost:3200/api/search?tags=service.name%3Dgraphql-gateway&limit=500" \
        | jq -r '[.traces[] | select(.rootTraceName=="POST /graphql/graphql")] | sort_by(.startTimeUnixNano) | last | .traceID')
    [[ -n "$tid" && "$tid" != null ]] || fail "no POST /graphql trace in Tempo"
    spans=$(in_pod lgtm curl -s "localhost:3200/api/traces/$tid" | jq -r '[.batches[] |
        (.resource.attributes[] | select(.key=="service.name") | .value.stringValue) as $s |
        ((.scopeSpans // []) + (.instrumentationLibrarySpans // []))[] | .spans[] | "\($s): \(.name)"] | .[]' | sort | uniq -c)
    printf 'trace %s\n%s\n' "$tid" "$spans" > "$f"
    local need=(graphql-gateway order-service inventory-service)
    if native_on; then
        # A native binary carries no Java agent: order-service spans come only
        # from the JVM canary (v2), which the 90/10 split rarely picks.
        need=(graphql-gateway inventory-service)
        printf '\norder-service runs native (no Java agent); its span is not required\n' >> "$f"
    fi
    for svc in "${need[@]}"; do
        grep -q " $svc:" "$f" || fail "trace $tid has no $svc span"
    done
    ok "one trace spans ${need[*]} ($(grep -c . <<<"$spans") span names)"
    local code; code=$(https -o /dev/null -w '%{http_code}' "https://$(oc get route grafana -n "$NS" -o jsonpath='{.spec.host}')/api/health")
    printf '\nGrafana /api/health through its Route: %s\n' "$code" >> "$f"
    [[ "$code" == 200 ]] || fail "Grafana Route returned $code"
    ok "Grafana Route 200"
}

evidence_ai() {
    step "P4 AI services (Ollama)"
    local f="$OUT/14-ai.txt" out c e
    : > "$f"
    oc exec -n "$NS" deploy/ollama -c ollama -- ollama list >> "$f" 2>&1
    for c in 'fresh strawberries|50|PERISHABLE' 'industrial sulfuric acid, corrosive chemical|4|HAZARDOUS' 'antique crystal wine glasses|6|FRAGILE'; do
        IFS='|' read -r item qty want <<<"$c"
        out=$(in_pod ai-mcp-service curl -sS --max-time 120 -X POST localhost:8080/api/orders/classify \
            -H 'Content-Type: application/json' -d "{\"item\":\"$item\",\"quantity\":$qty}")
        printf 'classify %s -> %s\n' "$item" "$(jq -c . <<<"$out")" >> "$f"
        [[ "$(jq -r .category <<<"$out")" == "$want" ]] || fail "classify '$item': expected $want, got $out"
    done
    ok "classify: PERISHABLE, HAZARDOUS, FRAGILE"
    for e in /api/orders/triage /api/orders/triage-flow; do
        for c in '{"customerId":"CUST-1001","itemSku":"BOOK-NOVEL-001","quantity":1,"amount":19.99}|ROUTE_TO_WAREHOUSE' \
                 '{"customerId":"CUST-VERIFIED-LONGTIME","itemSku":"OFFICE-CHAIR-ERGO","quantity":2,"amount":1250.00}|EXPEDITE' \
                 '{"customerId":"CUST-ANON-9999","itemSku":"STOLEN-GIFTCARD-BULK-RESHIP-FRAUD","quantity":500,"amount":48999.99}|FRAUD_HOLD'; do
            out=$(in_pod ai-rules-service curl -sS --max-time 120 -X POST "localhost:8080$e" -H 'Content-Type: application/json' -d "${c%|*}")
            printf '%s -> %s\n' "$e" "$(jq -c '{decision, reason}' <<<"$out")" >> "$f"
            [[ "$(jq -r .decision <<<"$out")" == "${c##*|}" ]] || fail "$e: expected ${c##*|}, got $out"
        done
    done
    ok "triage (Camel) and triage-flow (Quarkus Flow): ROUTE_TO_WAREHOUSE, EXPEDITE, FRAUD_HOLD"
    out=$(in_pod ai-mcp-service bash -c '
        H=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
        curl -sS -D /tmp/mcp-h -o /dev/null "${H[@]}" -X POST localhost:8080/mcp -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"crc-evidence\",\"version\":\"1.0.0\"}}}"
        S=$(grep -i "^Mcp-Session-Id:" /tmp/mcp-h | tr -d "\r" | cut -d" " -f2)
        curl -sS -o /dev/null "${H[@]}" -H "Mcp-Session-Id: $S" -X POST localhost:8080/mcp -d "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
        curl -sS "${H[@]}" -H "Mcp-Session-Id: $S" -X POST localhost:8080/mcp -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"; echo
        curl -sS "${H[@]}" -H "Mcp-Session-Id: $S" -X POST localhost:8080/mcp -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"order-status\",\"arguments\":{\"orderId\":\"ORD-001\"}}}"')
    printf '\nMCP tools/list + tools/call order-status ORD-001:\n%s\n' "$out" >> "$f"
    grep -q '"name":"order-status"' <<<"$out" && grep -q 'SHIPPED' <<<"$out" || fail "MCP tools/list or tools/call failed: $out"
    ok "MCP: tools/list has order-status; ORD-001 SHIPPED"
}

evidence_native() {
    step "P5 Native order-service"
    local f="$OUT/15-native.txt" np node
    np=$(oc get pod -n "$NS" -l app.kubernetes.io/name=order-service,version=v1 --field-selector=status.phase=Running -o name | head -1)
    [[ -n "$np" ]] || np=$(oc get pod -n "$NS" -l app.kubernetes.io/name=order-service --field-selector=status.phase=Running -o name | grep -v v2 | head -1)
    node=$(oc get node -o jsonpath='{.items[0].metadata.name}')
    {
        oc get builds -n "$NS" -l buildconfig=order-service-native -o custom-columns='BUILD:.metadata.name,STATUS:.status.phase,DURATION:.status.duration' 2>/dev/null
        oc get istag order-service-native:v1 -n "$NS" -o jsonpath='image {.image.dockerImageReference}{"\n"}'
        printf '\n-- startup\n'
        oc logs -n "$NS" "$np" -c order-service | grep -m1 'started in'
        oc get deployment order-service-v2 -n "$NS" >/dev/null 2>&1 && oc logs -n "$NS" deploy/order-service-v2 -c order-service | grep -m1 'started in'
        printf '\n-- working set (kubelet stats)\n'
        oc get --raw "/api/v1/nodes/$node/proxy/stats/summary" | jq -r --arg ns "$NS" '.pods[] | select(.podRef.namespace==$ns)
            | select(.podRef.name|test("^order-service")) | .podRef.name as $p | .containers[] | select(.name=="order-service")
            | "\($p): \(.memory.workingSetBytes/1048576|floor) MiB"'
    } > "$f" 2>&1
    grep -q ' native (powered by Quarkus' "$f" || fail "order-service is not running the native binary"
    # The core choreography check above already sent its order through the
    # Service; confirm the native pod logged no producer error doing so.
    oc logs -n "$NS" "$np" -c order-service | grep -q 'SecurityException' && fail "native producer rejected the Avro classes"
    ok "native: $(grep -o 'started in [0-9.]*s' "$f" | head -1); $(grep -E '^order-service-[a-z0-9]+-[a-z0-9]+:' "$f" | grep -v v2 | cut -d: -f2)"
}

evidence_gitops() {
    step "P6 GitOps (Argo CD)"
    local f="$OUT/16-gitops.txt" start
    {
        oc get application datamesh -n openshift-gitops -o jsonpath='Application datamesh: {.spec.source.repoURL} @ {.spec.source.targetRevision} path {.spec.source.path}{"\n"}sync={.status.sync.status} health={.status.health.status} revision={.status.sync.revision}{"\n"}'
        oc delete configmap datamesh-app-config -n "$NS" >/dev/null
        start=$(date +%s)
        until oc get configmap datamesh-app-config -n "$NS" >/dev/null 2>&1; do sleep 2; (( $(date +%s) - start > 300 )) && break; done
        printf 'self-heal: deleted ConfigMap datamesh-app-config; restored after %ss\n' "$(( $(date +%s) - start ))"
    } > "$f" 2>&1
    grep -q 'sync=Synced' "$f" || fail "Application not Synced"
    grep -q 'restored after' "$f" && oc get configmap datamesh-app-config -n "$NS" >/dev/null 2>&1 || fail "Argo CD did not restore the ConfigMap"
    ok "Argo CD Synced; $(grep -o 'restored after [0-9]*s' "$f")"
}

platform_evidence() {
    mesh_on && evidence_mesh
    keda_on && evidence_keda
    otel_on && evidence_otel
    ai_on && evidence_ai
    native_on && evidence_native
    gitops_on && evidence_gitops
    return 0
}
