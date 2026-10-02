package com.patterncatalyst.datamesh.airules;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import com.patterncatalyst.datamesh.domain.OrderCreate;
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.model.dataformat.JsonLibrary;

/**
 * Showcase: two REST endpoints orchestrate the exact same
 * classify-then-decide logic ({@link TriageService}) two different ways, as
 * an A/B contrast:
 *
 * <ul>
 *   <li>{@code POST /api/orders/triage} -- orchestrated by this Camel route
 *       (the {@code triage-order} route below), chaining
 *       {@code .bean(triageService, "classify")} into
 *       {@code .bean(triageService, "decide")}.</li>
 *   <li>{@code POST /api/orders/triage-flow} -- orchestrated by a Quarkus
 *       Flow workflow ({@code OrderTriageWorkflow}), which chains the same
 *       two {@link TriageService} methods as workflow tasks. This route
 *       (the {@code triage-flow-order} route below) just unmarshals the
 *       request and hands it to {@link OrderTriageFlowRunner}, which starts
 *       that workflow and awaits its result.</li>
 * </ul>
 *
 * <p>Because both paths delegate to the same {@link TriageService} bean --
 * and Drools (not the LLM, and not a langchain4j tool-calling round trip)
 * makes the decision in both -- neither path can regress into the tool-calling
 * limitation; see this module's README.
 */
@ApplicationScoped
public class OrderTriageRoute extends RouteBuilder {

    @Inject
    TriageService triageService;

    @Inject
    OrderTriageFlowRunner triageFlowRunner;

    @Override
    public void configure() throws Exception {
        rest("/api/orders")
            .post("/triage")
            .consumes("application/json")
            .produces("application/json")
            .to("direct:triage")
            .post("/triage-flow")
            .consumes("application/json")
            .produces("application/json")
            .to("direct:triage-flow");

        from("direct:triage")
            .routeId("triage-order")
            .log("Triaging order (Camel): ${body}")
            // Explicit, verified unmarshal -- the rest-dsl's own .type(...)
            // input-binding option does NOT perform this conversion on this
            // stack (no RestBindingMode is configured), so the body stays a
            // raw JSON string past it.
            .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
            .bean(triageService, "classify")
            .log("Classification result: ${body}")
            .bean(triageService, "decide")
            .marshal().json(JsonLibrary.Jackson);

        from("direct:triage-flow")
            .routeId("triage-flow-order")
            .log("Triaging order (Flow): ${body}")
            .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
            // platform-http (camel-quarkus-platform-http/Vert.x) dispatches this
            // route on the Vert.x event loop. triageFlowRunner.run() does a
            // blocking LLM call plus a Drools fire and then
            // .await().atMost(Duration.ofSeconds(120)) -- up to two minutes of
            // blocking -- which would starve the event loop if left on it. The
            // threads() EIP hands the exchange off to Camel's own worker thread
            // pool before that call, so the blocking work (and the .await())
            // runs off the event loop; platform-http's async consumer resumes
            // the HTTP response when that worker thread completes, so the
            // external response contract (status/body) is unchanged.
            .threads()
            .bean(triageFlowRunner, "run")
            .marshal().json(JsonLibrary.Jackson);
    }
}
