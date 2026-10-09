# Plan: Appendix "Running on OpenShift Local (CRC)" for the Quarkus repo

## Corrections applied to the original plan
- **No port-forward in verification.** Use `oc exec` or a Route. <!-- forbidden-ok -->
- **Don't stop Docker Desktop in the procedure.** Leave it to the user.
- **Assign DRQ numbers after plan A.** DRQ-016 and DRQ-017 are taken (merged in #52), so this plan starts at DRQ-018.
- **Scan 5 allowlist.** Add the appendix paths. Scan 6 still applies here, so the appendix must be Fedora/RHEL only.

## Design
- **Tree.** New `openshift/` at the repo root:
  - a data-driven Helm chart `openshift/helm/datamesh/`: one Deployment template over a `services:` map of 7 services, ConfigMap matching the minikube env contract, Secret, two Routes (gateway, apicurio) edge/Redirect, postgres StatefulSet, apicurio Deployment, NOTES; `mesh.enabled` and `keda.enabled` default to false;
  - `infra/amq-streams-subscription.yaml` and `infra/kafka.yaml` (Kafka CR named `datamesh`, KRaft dual-role, no entityOperator);
  - `install-infra.sh`, `build-images.sh`, `capture-evidence.sh` (with a secret-scrub gate), `README.md`, `gitops/application.yaml`, `evidence/`;
  - Phase 2 only: `platform/` (OSSM3 Sail with label `istio.io/rev`, and CMA Kafka-lag).
- **Image builds.** Use **`quarkus-container-image-openshift`**, a binary S2I build onto `registry.access.redhat.com/ubi10/openjdk-25`.
  - Maven builds on the host: `mvn -f examples/pom.xml -pl <svc> -am package -DskipTests -Popenshift -Dquarkus.container-image.build=true -Dquarkus.container-image.name=<svc> -Dquarkus.container-image.tag=v1 -Dquarkus.kubernetes-client.namespace=datamesh -Dquarkus.openshift.base-jvm-image=... -Dquarkus.kubernetes-client.trust-certs=true -Dquarkus.kubernetes.deploy=false`.
  - Each of the 7 service poms gets an `openshift` Maven profile; nothing goes in the parent pom.
  - Needs no Docker and no podman, and the CRC VM never pulls from Maven Central. <!-- forbidden-ok -->
  - Rejected: (b) a Docker-strategy BuildConfig running mvn in the VM, (c) docker plus insecure-registries, (d) podman, which CLAUDE.md forbids. <!-- forbidden-ok -->
  - The chart sets `JAVA_MAX_MEM_RATIO`, `JAVA_TOOL_OPTIONS` (the Avro packages per service), because the image runs `run-java.sh`, not the Containerfile entrypoint.
- **Infra on 20 GB / 6 vCPU.**
  - Kafka: the AMQ Streams operator via OLM (fallback community Strimzi).
  - Postgres: StatefulSet on `registry.redhat.io/rhel10/postgresql-16` (fallback rhel9) under restricted-v2. Document the drift from 16 to 18.6.
  - Apicurio: `quay.io/apicurio/apicurio-registry:3.2.4`, in memory.
  - Routes instead of NodePorts.
  - Observability and the AI services are document-only.
  - Native: one service (order-service), compiled on the host and binary-uploaded.
- **SCC.** All pods run under restricted-v2 with arbitrary UIDs and no exception; `runAsUser` is never set.
- **Chapter.** `_docs/22-running-on-openshift-crc.md` (order 22, part Appendices). Sections: intro, prereqs, what changes (SCC / Routes / registry built in-cluster), chart, building with the extension, infra via OperatorHub, deploy, verify (health through the Route, GraphQL order+stock, the Kafka choreography order→payment→shipping→notification, Apicurio artifacts), optional native, what broke, platform tier, GitOps, teardown, footer.
- **Diagrams.** `scripts/make-openshift-diagrams.js` generates `22-crc-openshift-topology` and `22-crc-image-build`, each as svg + excalidraw.
- **Deck.** Add an "Appendix A7: OpenShift Local" group (4-5 slides) to `presentation/datamesh-201/build-deck.js`, rebuild as r1.2, and update the README.
- **Decision records.** Scope and tiering; build path; infra; Routes and registry; native.
- **Repo facts.**
  - review-service has no Containerfile and has quarkus-oidc with no %prod config. Probe it in wave 0.
  - payment and shipping have never run on k8s.
  - inventory gRPC is on :9000.
  - SmallRye Health is at /q/health/*.
  - The minikube overlay deploys 4 services.

## Waves
0. **Probes on CRC.**
   - Confirm the config keys via quarkus_searchDocs.
   - Check the packagemanifests for amq-streams, servicemeshoperator3 and the CMA operator.
   - `oc import-image` probes for the postgres, openjdk and apicurio images.
   - Confirm the S2I label is on ubi10/openjdk-25.
   - Check whether review-service starts with OIDC under the prod profile.
1. **Author.** Chart, infra and scripts, the poms, diagrams, the chapter draft (and platform/ for phase 2).
2. **Live bring-up on CRC.** Evidence, then optional native, then teardown.
3. **Fold-in.** Chapter final, deck, shared navigation files (`00-index`, `_parts/appendices` Six→Seven, `_config.yml` exclude `openshift/`, setup.html, README), plans.
4. **Validate.** jekyll build, cross-references, voice, the secret grep, then commit and PR.

## Live
1. `minikube stop -p datamesh`.
2. `crc start`, then `eval $(crc oc-env)`.
3. `crc console --credentials`. Never record its output.
4. `oc login -u kubeadmin`, entering the password interactively.
5. `oc new-project datamesh`.
6. `install-infra`, `build-images`, `helm upgrade --install`, then `capture-evidence`.
7. `openshift/teardown.sh`: helm uninstall, delete KafkaTopics and the Kafka CR, delete the project, remove the AMQ Streams Subscription, CSV and CRDs, then `crc stop`.

## Acceptance (key)
- **Build.** 7 builds complete and 7 ImageStreams tagged v1, with no host push.
- **Pods.** All Ready under restricted-v2, with UIDs in the namespace range.
- **Gateway.** The gateway Route returns 200 on `/q/health/ready`, and GraphQL returns order+stock.
- **Kafka chain.** Choreography is observed for one order ID.
- **Apicurio.** Lists its artifacts.
- **Evidence.** Contains no tokens or passwords.
- **Maven.** The default `mvn verify` still passes, and application.properties is unchanged.

## Wave 0 results (2026-10-09, CRC 4.22.14, 6 vCPU / 20 GiB)
- **Config keys** (quarkus.io container-image guide; the local doc search needs a container engine and Docker was stopped): `quarkus.openshift.base-jvm-image` (default `ubi9/openjdk-25:1.24`, so override it), `quarkus.openshift.build-strategy` (default `binary`), `quarkus.openshift.jvm-arguments`, `quarkus.openshift.jar-file-name`, `quarkus.openshift.build-timeout` (default 5M).
- **Base image**: pin `registry.access.redhat.com/ubi10/openjdk-25:1.24-15`. It has the S2I labels `io.openshift.s2i.scripts-url=image:///usr/libexec/s2i` and `io.openshift.tags=builder,java`.
- **Operators already installed cluster-wide** in `openshift-operators` (from earlier CRC work): AMQ Streams `amqstreams.v3.2.1-14` (Subscription `amq-streams`, channel stable) and CNPG `cloudnative-pg.v1.30.1`. `install-infra.sh` must detect and reuse an existing Subscription rather than create a second one, and teardown must leave both operators in place. AMQ Streams 3.2 ships Kafka 4.1 and 4.2, so pin Kafka 4.2.0.
- **OperatorHub**: `redhat-operators` reports READY but lists 0 packages for about a minute after `crc start`, so the script must wait until the packagemanifest exists. Available: `servicemeshoperator3` (stable, v3.4.3), `openshift-custom-metrics-autoscaler-operator` (stable, v2.19.0-4) and `kiali-ossm` (stable, v2.27.5) for phase 2.
- **Images via `oc import-image`** (the CRC pull secret covers registry.redhat.io): `rhel10/postgresql-16:10.2-1791491499` (runs as user 26; the sclorg image supports arbitrary UIDs), `rhel9/postgresql-16`, `ubi10/openjdk-25:1.24-15` and `quay.io/apicurio/apicurio-registry:3.2.4` (matches minikube) all import. Use rhel10, no fallback needed.
- **review-service under prod** fails at boot with `'quarkus.oidc.auth-server-url' property must be configured`. With env `QUARKUS_OIDC_TENANT_ENABLED=false` it gets past OIDC (it then fails only on the DB we deliberately left unreachable). Decision: the chart sets that env var; `DELETE /reviews/{id}` returns 401 on CRC; application.properties stays unchanged. Record as a DRQ.
- **Shared-cluster finding, resolved**: namespace `hfd-ocp` (helm-for-developers) was still running. On the user's instruction, the namespace, the AMQ Streams and CNPG operators and their 21 CRDs were removed. A KafkaTopic finalizer (`strimzi.io/topic-operator`) blocked the namespace deletion and had to be cleared. CRC is now clean: no Subscriptions, CSVs, Strimzi/CNPG CRDs or non-system namespaces.
- **Rule (user, 2026-10-09)**: this CRC is dedicated to datamesh. Cleanup after each use is mandatory. `teardown.sh` removes the Helm release, the project, the AMQ Streams Subscription and CSV, and the Strimzi CRDs (KafkaTopics and the Kafka CR go before the namespace), then runs `crc stop`. `install-infra.sh` installs AMQ Streams from scratch.
- **Kubeconfig**: `crc start` writes the `crc-admin` context, so `oc config use-context crc-admin` replaces the interactive kubeadmin login. No password handling needed.

## Status (resume here)
- 2026-10-09: Wave 0 done. Wave 1 scripts/chart/poms done and Wave 2 live run done:
  - `openshift/` has lib.sh, install-infra.sh, build-images.sh, deploy.sh, capture-evidence.sh, teardown.sh, infra/, helm/datamesh/, README.md, evidence/2026-10-09/.
  - Full clean cycle from an empty CRC: teardown 46s, install-infra 50s, build-images 182s, deploy 33s, capture-evidence 13s; all 7 checks green, zero restarts, UIDs from the namespace range.
  - Live fixes folded in: quarkus-openshift (not container-image-openshift alone), quarkus.openshift.version for the tag, JAVA_MAX_MEM_RATIO, wait-for-postgres init container, config checksum, rollout-status wait, kafka.strimzi.io/v1.
  - DRQ-018..022 written; `_config.yml` excludes openshift/.
- Next step: Wave 3 fold-in (chapter 22, diagrams, deck A7 group, nav files, README), then Wave 4 validation and the PR. Phase 2 platform tier (OSSM3, CMA) and native are not started.
- When finished with CRC: `./openshift/teardown.sh` (removes everything, then crc stop).
- Rules:
  - One cluster at a time.
  - Secrets are never written to files or evidence.
  - Fedora/RHEL only; no other OS mentioned.
  - No port-forward or tunnels; use Routes or `oc exec`. <!-- forbidden-ok -->
  - Docker, not podman. <!-- forbidden-ok -->
  - Load the lgtm-quarkus and lgtm-camel skills before code. Pinned versions only.
  - Run `bash scripts/forbidden-syntax.sh` before commits.
  - Add the appendix paths to the scan-5 allowlist only if needed. Scan 6 still applies.
