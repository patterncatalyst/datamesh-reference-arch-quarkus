# Plan: loopback-published NodePorts, Docker Engine on Fedora/RHEL, forbidden-syntax gate

Planned 2026-10-09 (Opus). Base `main` b4fb031. Reference: datamesh-reference-arch-python bdfcd32 (PR #10, DRA-017/019).
Move to `_plans/archive/` once executed (its own text trips the gate).

## Rules (user)
- **No SSH or kubectl forwarding.** Host access is NodePorts published at profile creation as
  `--ports=127.0.0.1:<host>:<node>`. The bare form, which binds 0.0.0.0, is forbidden. <!-- forbidden-ok -->
- **Host ports are unchanged.** Each workshop runs in isolation, with everything else shut down.
- **Engine.** Docker Engine is required. Docker Desktop is optional and appears only as an example of a VM-based engine.
- **Hosts.** Fedora or RHEL, bare metal or VM. No other OS is mentioned anywhere.
- **minikube.** `--driver=docker --container-runtime=containerd`.

## Approach
- **New `demos/lib/endpoints.sh`.** Ported from the Python repo:
  - the TP_*/NP_* map, `node_ports_arg`, published/nonloopback checks via `docker container inspect`;
  - `check_published_ports`, `ensure_endpoint` (accepts NodePort or LoadBalancer), `ensure_node_forwarding`, `docker_engine_ok`;
  - `EP_PROFILE=${MINIKUBE_PROFILE:-datamesh}`;
  - leaves out `wait_http` and `wake_gateway`, because `_demo.sh` has its own `wait_http`.
- **`scripts/setup-profile.sh` rewritten** to follow `setup-capstone-profile.sh`:
  - Fedora/RHEL check (warn only);
  - `PORTS_ARG` validation, tools, `docker_engine_ok`, rootless rejection, capacity check;
  - VM-engine detection by kernel comparison;
  - inotify check, on the host or inside the node;
  - minikube >= 1.36;
  - refuse a profile created with a different driver or runtime;
  - an existing profile must have its published ports (refuse otherwise, pointing to `--replace`);
  - free-port pre-flight before any delete;
  - `minikube start --ports=...`;
  - post-start checks.
- **New `scripts/show-endpoints.sh`.** Deletes `scripts/tunnel-services.sh`. <!-- forbidden-ok -->
- **CI gate.** New `scripts/forbidden-syntax.sh` with scans 1-5 from the Python repo plus **scan 6 for other-OS mentions**:
  - matches mac/osx/darwin/wsl/ubuntu/debian/alpine/centos/suse/colima/rancher desktop/homebrew/brew install/apt(-get) install, `.wslconfig`, `%APPDATA%`, and case-sensitive `\bWindows\b`;
  - excludes `runs-on:` lines, `-moz-osx-font-smoothing`, archive files and `forbidden-ok` lines;
  - pptx is checked against scans 1, 5 and 6;
  - new `.github/workflows/checks.yml` runs it.
- **Compose and the cluster are mutually exclusive**, because both use 3000, 3100, 3200, 4317 and 4318.
  - `_demo.sh compose_up` and `tooling/newman/run-newman.sh` fail fast while the `datamesh` profile is running.
  - Walkthrough ACT 5 (`--with-minikube`) starts the stopped profile.
- **`scripts/load-images.sh`.** Keeps `datamesh/<svc>:latest` + IfNotPresent + `minikube image load`. Now waits for rollouts and for terminating pods. Switching to `Never` is deferred.
- **gRPC resolver.** Not applicable: Quarkus clients use the JDK/Netty resolver, and `INVENTORY_GRPC_HOST` is already the FQDN.
- **Remove `.devcontainer/`.** It uses an ubuntu base, unpinned "latest" features, and forwardPorts; also remove its `.dockerignore` line.
- **Decisions.** DRQ-016 (host access) and DRQ-017 (engine and host scope, compose/cluster exclusivity, devcontainer removal, deferrals).

## Port map (host ports unchanged)
| Name | Host | NodePort | Service / ns | Set by |
|---|---|---|---|---|
| grafana | 3000 | 30300 | grafana / observability | setup-lgtm.sh |
| otlp-grpc | 4317 | 30417 | otel-collector-opentelemetry-collector / observability | setup-lgtm.sh |
| otlp-http | 4318 | 30418 | same | setup-lgtm.sh |
| mimir | 9009 | 30009 | mimir-nginx / observability | setup-lgtm.sh |
| loki | 3100 | 30100 | loki-gateway / observability | setup-lgtm.sh |
| tempo | 3200 | 30320 | tempo / observability (verify that 30320 lands on 3200 live) | setup-lgtm.sh |
| kiali | 20001 | 30201 | kiali / istio-system | setup-kiali.sh |
| apicurio | 8084 | 30084 | apicurio / datamesh | setup-apicurio.sh |

## Waves
1. **Wave 1.**
   - 1A: the gate and checks.yml.
   - 1B: endpoints.sh, show-endpoints.sh, setup-profile.sh.
2. **Wave 2.**
   - 2C, scripts: bootstrap, cluster-status, teardown, load-images, setup-lgtm/kiali/apicurio, run-all-tests, tooling/load; remove the old forwarding script.
   - 2D, demos: _demo.sh, walkthrough, the oidc/reactive-vertx/continuous-testing/native/panama/jbang-prototype demos, PanamaFfm.java, demos/README, run-newman guard.
   - 2E, docs: _docs/00/02/08/11, setup.html (drop the Docker Desktop resize Option B and all OS-specific text; add a Host access section), demos.html, index.html, README, k8s/README, the example READMEs, compose.yaml, infra/README, Gemfile; delete .devcontainer and its .dockerignore line.
   - 2F, plans and meta: CLAUDE.md (add the host-access, host-scope and gate convention), PRD, decisions DRQ-016/017, build-plan, reconciliation, professional-content-pass.
   - 2G, deck: the build-deck.js FFM note, then rebuild the 201 pptx.
3. **Wave 3.** Gate OK, negative tests, live run, footers and reconciliation, then archive this plan.

## Acceptance
- **Gate.** forbidden-syntax prints OK, with negative tests for each scan. CI checks and Pages pass.
- **Greps.** Forwarding and OS terms appear only on forbidden-ok or runs-on lines. The old forwarding script and `.devcontainer` are gone. <!-- forbidden-ok -->
- **Syntax.** `bash -n` passes.
- **Bindings.** `docker port datamesh` shows loopback only, all 8 pairs. A request from the LAN is refused.
- **Refusals.** setup-profile.sh refuses each of these: an old profile without ports, a busy port (compose lgtm up) before any delete, CPUs above engine capacity, and a non-loopback EXTRA port.
- **Bootstrap and endpoints.** bootstrap is green with `MINIKUBE_CPUS=8 MINIKUBE_MEMORY=24g`, and show-endpoints is green, including stop/start.
- **Images.** load-images waits for rollouts.
- **Demos.**
  - demo-keda-kafka, demo-keda-http and verify-ws-failover pass.
  - The compose guard fails fast while the cluster runs.
  - `walkthrough --auto --with-minikube` passes 15/15.
  - run-all-tests passes with the profile stopped.

## Risks
- **Compose/cluster port collision.** Covered by the guards.
- **Fixed vs. dynamic nodePorts.** A fixed nodePort could collide with a dynamically allocated one; the fallback is the static band 30000-30085.
- **Tempo and OTel Service names and ports.** Verify both live.
- **Docker Desktop's VM proxy.** Loopback publishing behaviour has only been checked on this host.
- **Recreating the profile.** It wipes the images.
- **The gate is red until wave 3.**
- **The 201 pptx rebuild.** The diff will be large; the slide count must stay at 102.
