---
part_name: The Quarkus deep-dive
order: 4
title: The Quarkus deep-dive
blurb: A tour of what Quarkus itself brings to the table — the extensions, the dev loop, and the two orchestration engines this project runs side by side with Kafka choreography.
---

This part turns from the data-mesh patterns to the runtime underneath them.
Four chapters:

1. **A Quarkus capability tour** — Panache, gRPC, GraphQL, Reactive Messaging,
   WebSockets.Next, unified Vert.x reactive/imperative execution, continuous
   testing with Dev Services, native compilation, OIDC, and JBang prototyping,
   each grounded in a real endpoint or demo from this repo.
2. **Quarkus vs. Spring Boot** — a runnable side-by-side comparison on startup
   time, memory, and native build behavior.
3. **Orchestration styles** — Kafka choreography versus two different
   orchestration engines (a Camel route and a Quarkus Flow workflow)
   coordinating the same kind of decision.
4. **AI-assisted rules triage** — an Ollama-classified order handed to an
   embedded Drools rule set, orchestrated two ways, with a clear account
   of where in-process LLM tool-calling does and doesn't work on this stack.
