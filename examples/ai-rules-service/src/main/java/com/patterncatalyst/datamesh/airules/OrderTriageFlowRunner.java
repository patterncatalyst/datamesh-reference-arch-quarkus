package com.patterncatalyst.datamesh.airules;

import java.time.Duration;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import com.patterncatalyst.datamesh.domain.OrderCreate;

/**
 * Bridges {@link OrderTriageRoute}'s {@code direct:triage-flow} route to the
 * Quarkus Flow workflow: starts {@link OrderTriageWorkflow} with the
 * unmarshalled {@link OrderCreate} as its input, awaits the resulting
 * {@code Uni} (Flow instances run asynchronously), and unwraps the
 * workflow's final model back into a {@link TriageDecision} -- the exact
 * same response shape {@code /api/orders/triage} (the Camel path) returns.
 */
@ApplicationScoped
public class OrderTriageFlowRunner {

    @Inject
    OrderTriageWorkflow workflow;

    public TriageDecision run(OrderCreate order) {
        return workflow.startInstance(order)
            .onItem().transform(model -> model.as(TriageDecision.class).orElseThrow())
            .await().atMost(Duration.ofSeconds(120));
    }
}
