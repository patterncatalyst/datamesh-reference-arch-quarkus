# openshift/ — datamesh on OpenShift Local (CRC)

The optional Red Hat path for this workshop. The main path is minikube on
Docker Engine (`scripts/bootstrap.sh`); this directory runs the same 7 Quarkus
services on OpenShift Local instead. The walkthrough is the appendix chapter
`_docs/22-running-on-openshift-crc.md`.

Supported hosts: Fedora or RHEL, bare metal or VM. Needs `crc` (with a pull
secret), `oc`, `helm`, `mvn` with JDK 25, and `jq`. No container engine is
used: images are built inside the cluster.

## Run it

Stop minikube first. Run one cluster at a time.

```bash
crc start                         # writes the crc-admin kubeconfig context
eval "$(crc oc-env)"

./openshift/install-infra.sh      # project, AMQ Streams operator, Kafka
./openshift/build-images.sh       # 7 binary S2I builds -> ImageStream tags v1
./openshift/deploy.sh             # Helm chart: services, Postgres, Apicurio, Routes
./openshift/capture-evidence.sh   # checks + evidence/<date>/, with a secret scrub
./openshift/teardown.sh           # remove everything above, then crc stop
```

## What is here

| Path | Purpose |
|---|---|
| `lib.sh` | Shared helpers; pins the `crc-admin` context and refuses any other cluster. |
| `infra/amq-streams-subscription.yaml` | AMQ Streams `amqstreams.v3.2.1-14`, Manual approval. |
| `infra/kafka.yaml` | Kafka CR `datamesh` (`kafka.strimzi.io/v1`), Kafka 4.2.0, one KRaft node. |
| `helm/datamesh/` | Chart: 7 Deployments from one `services:` map, Postgres 16, Apicurio 3.2.4, two Routes. |
| `evidence/` | Output of `capture-evidence.sh`. No passwords or tokens; the script checks. |

## Differences from minikube

| | minikube | OpenShift Local |
|---|---|---|
| Images | `docker build` + `minikube image load` | `quarkus-openshift` binary S2I on `ubi10/openjdk-25:1.24-15` |
| Host access | NodePorts published on 127.0.0.1 | Edge-TLS Routes on `*.apps-crc.testing` |
| Kafka | Strimzi 0.51.0 via Helm | AMQ Streams 3.2.1 via OperatorHub |
| Postgres | CloudNativePG, PostgreSQL 18.6 | StatefulSet, `rhel10/postgresql-16` |
| Pod security | `runAsUser: 185` | `restricted-v2`, UID from the namespace range |
| review-service | not deployed | OIDC tenant disabled; `DELETE /reviews/{id}` answers 401 |

The decisions are DRQ-018 to DRQ-022 in `_plans/decisions.md`.
