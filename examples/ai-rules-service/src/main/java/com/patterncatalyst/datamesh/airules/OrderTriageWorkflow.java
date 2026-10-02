package com.patterncatalyst.datamesh.airules;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import io.quarkiverse.flow.Flow;
import io.quarkiverse.flow.dsl.FlowDSL;
import io.quarkiverse.flow.dsl.FlowWorkflowBuilder;
import io.serverlessworkflow.api.types.Workflow;

/**
 * Showcase: the Quarkus Flow A/B contrast to {@link OrderTriageRoute}'s
 * Camel orchestration of the same {@link TriageService} logic.
 *
 * <p>This workflow orchestrates exactly two tasks -- {@code classify} then
 * {@code decide} -- both of which are plain {@link TriageService} CDI-bean
 * method calls, chained via {@code quarkus-flow}'s default behavior where
 * each task's input is the prior task's output. Flow does the
 * orchestration; Drools (inside {@link TriageService#decide}) still makes
 * the business decision -- this workflow does not reimplement any part of
 * that decision as a Flow {@code switchCase}.
 *
 * <p>{@code quarkus-flow-bom:1.1.3} pulls in {@code serverlessworkflow-api}
 * et al., but zero Kogito/KIE/Drools artifacts -- this module's own Drools
 * 10.2.0 (managed via {@code drools-bom} in the pom) remains the only rules
 * engine on the classpath, used identically by both orchestration paths.
 */
@ApplicationScoped
public class OrderTriageWorkflow extends Flow {

    @Inject
    TriageService triageService;

    @Override
    public Workflow descriptor() {
        return FlowWorkflowBuilder.workflow("order-triage")
            .tasks(
                FlowDSL.function("classify", triageService::classify),
                FlowDSL.function("decide", triageService::decide))
            .build();
    }
}
