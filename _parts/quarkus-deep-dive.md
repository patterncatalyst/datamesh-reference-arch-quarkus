---
part_name: The Quarkus deep-dive
order: 4
title: The Quarkus deep-dive
blurb: "What Quarkus provides: the extensions, the dev loop, startup options, and the two orchestration engines this project runs alongside Kafka choreography."
---

This part covers the runtime underneath the data-mesh patterns. Four chapters:

1. **A Quarkus capability tour** — twelve capabilities, each backed by code or
   a demo script: Panache, gRPC, GraphQL, Reactive Messaging, WebSockets.Next,
   Vert.x reactive and imperative execution, continuous testing with Dev
   Services, native image and the JDK AOT cache, OIDC, JBang, and Panama FFM.
2. **Quarkus vs. Spring Boot** — a runnable side-by-side comparison of
   startup time and memory, including the JDK 25 AOT cache, and the native
   build.
3. **Orchestration styles** — Kafka choreography versus two different
   orchestration engines (a Camel route and a Quarkus Flow workflow)
   coordinating the same kind of decision.
4. **AI-assisted rules triage** — an Ollama-classified order handed to an
   embedded Drools rule set, orchestrated two ways, and where in-process LLM
   tool-calling works and where it does not on this stack.
