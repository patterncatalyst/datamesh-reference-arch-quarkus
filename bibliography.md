---
layout: default
title: "Bibliography"
permalink: /bibliography/
description: "The reference works this site's coverage and rigor draw on. Nothing here is reproduced from them."
---

# Bibliography

This reference's chapter arc and its level of rigor draw on a short list of books
and primary documentation covering data mesh and the Quarkus-on-Kubernetes platform
it runs on. They're reference works, not sources. No text or code from any of them
is reproduced in these chapters or the runnable examples. When a chapter is useful
to you, these are where to go deeper.

## Books

| Title | Author(s) | Publisher | Focus |
|---|---|---|---|
| [*Data Mesh*](https://www.oreilly.com/library/view/data-mesh/9781492092384/) | Zhamak Dehghani | O'Reilly | The four principles, the data product as architectural quantum, federated governance |
| [*Designing Data-Intensive Applications*, 2nd ed.](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781098119058/) | Martin Kleppmann & Chris Riccomini | O'Reilly | Reasoning about distributed systems built from independently-owned parts |
| [*Cloud Native Patterns*](https://www.manning.com/books/cloud-native-patterns) | Cornelia Davis | Manning | Packaging, runtime, and platform-provided concerns for services that double as data products |
| [*Cloud Native Anti-Patterns*](https://www.packtpub.com/en-us/product/cloud-native-anti-patterns-9781836200581) | Gerald Bachlmayr, Aiden Ziegelaar, Alan Blockley & Bojan Zivic | Packt | The failure modes the anti-patterns chapter maps |
| [*Kubernetes Patterns*](https://www.oreilly.com/library/view/-/9781098131678/) | Bilgin Ibryam & Roland Huß | O'Reilly | Container image and workload patterns behind the build, load, and deploy sequence |
| [*Platform Engineering on Kubernetes*](https://www.manning.com/books/platform-engineering-on-kubernetes) | Mauricio Salatino | Manning | The self-serve platform principle built out as an operating model |
| [*GitOps and Kubernetes*](https://www.manning.com/books/gitops-and-kubernetes) | Billy Yuen, Alexander Matyushentsev, Todd Ekenstam & Jesse Suen | Manning | Declarative delivery for the platform tier |
| [*Learning Domain-Driven Design*](https://www.oreilly.com/library/view/learning-domain-driven-design/9781098100124/) | Vlad Khononov | O'Reilly | Bounded contexts and domain ownership behind the service boundaries |
| [*Implementing Domain-Driven Design*](https://www.informit.com/store/implementing-domain-driven-design-9780133039894) | Vaughn Vernon | Addison-Wesley | Aggregates, events, and context mapping in code |

## Primary documentation

| Project | Link | Used for |
|---|---|---|
| Quarkus | [quarkus.io/guides](https://quarkus.io/guides/) | The core runtime: Panache, REST, config, native build |
| Quarkus gRPC | [quarkus.io/guides/grpc](https://quarkus.io/guides/grpc) | The inventory-service synchronous contract |
| SmallRye GraphQL | [quarkus.io/guides/smallrye-graphql](https://quarkus.io/guides/smallrye-graphql) | The GraphQL gateway |
| Reactive Messaging (Kafka) | [quarkus.io/guides/kafka](https://quarkus.io/guides/kafka) | The async event backbone |
| Camel on Quarkus | [camel.apache.org/camel-quarkus](https://camel.apache.org/camel-quarkus/) | Orchestration routes and EIPs |
| Quarkus LangChain4j | [docs.quarkiverse.io/quarkus-langchain4j](https://docs.quarkiverse.io/quarkus-langchain4j/dev/) | The AI triage service and MCP tooling |
| Drools | [drools.org](https://www.drools.org/) | The rules side of the classify-then-decide split |
| Apicurio Registry | [apicur.io/registry/docs](https://www.apicur.io/registry/docs/) | The schema registry for Avro contracts |
| OpenTelemetry | [opentelemetry.io/docs](https://opentelemetry.io/docs/) | The metrics, traces, and logs signal model |
| Grafana | [grafana.com/docs](https://grafana.com/docs/) | Tempo for traces, Mimir/Prometheus for metrics |
| Istio | [istio.io/latest/docs](https://istio.io/latest/docs/) | The service mesh, mTLS, and progressive delivery |
| KEDA | [keda.sh/docs](https://keda.sh/docs/) | Event-driven and lag-based autoscaling |
| Strimzi | [strimzi.io/docs](https://strimzi.io/docs/) | The Kafka operator for the async backbone |
| CloudNativePG | [cloudnative-pg.io/documentation](https://cloudnative-pg.io/documentation/) | The Postgres operator behind each product's store |
| Kubernetes | [kubernetes.io/docs](https://kubernetes.io/docs/) | Namespaces, RBAC, CRDs, admission control |
| minikube | [minikube.sigs.k8s.io/docs](https://minikube.sigs.k8s.io/docs/) | The local cluster, docker driver, containerd runtime |
| OpenShift Local (CRC) | [crc.dev](https://crc.dev/) | The OpenShift appendix |
| Spring Boot | [docs.spring.io/spring-boot](https://docs.spring.io/spring-boot/) | The runnable twin service used for the side-by-side comparison |

These titles inform this site's coverage and rigor only. Nothing in these chapters
or the runnable examples copies text or code from them.
