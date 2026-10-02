package com.patterncatalyst.datamesh.airules;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import jakarta.inject.Inject;

import io.quarkus.test.junit.QuarkusTest;
import org.apache.camel.CamelContext;
import org.apache.camel.Route;
import org.apache.camel.ServiceStatus;
import org.junit.jupiter.api.Test;
import org.kie.api.KieBase;
import org.kie.api.runtime.KieSession;

/**
 * Wiring test: verifies the Camel route and the Drools {@link KieBase} CDI
 * producer both boot, WITHOUT calling Ollama. The behavioral,
 * classify-then-decide assertion lives in {@link OrderTriageRouteIT}, which
 * is opt-in and requires a live Ollama server; the per-branch Drools
 * decision assertions live in {@link OrderTriageDrlTest}, which needs
 * neither Quarkus nor Ollama.
 */
@QuarkusTest
class OrderTriageRouteTest {

    @Inject
    CamelContext camelContext;

    @Inject
    KieBase orderTriageKieBase;

    @Test
    void contextStartsWithTriageRouteRegistered() {
        assertNotNull(camelContext);
        assertEquals(ServiceStatus.Started, camelContext.getStatus());

        Route route = camelContext.getRoute("triage-order");
        assertNotNull(route, "Expected route 'triage-order' to be registered");

        ServiceStatus status = camelContext.getRouteController().getRouteStatus("triage-order");
        assertTrue(status.isStarted(), () -> "Expected route 'triage-order' to be started, was " + status);
    }

    /**
     * The Quarkus Flow A/B contrast route also boots and registers,
     * without calling Ollama. The behavioral assertion that it produces a
     * correct Drools decision lives in {@link OrderTriageFlowTest} (mocked
     * classify) and {@link OrderTriageFlowRouteIT} (opt-in, live Ollama).
     */
    @Test
    void contextStartsWithTriageFlowRouteRegistered() {
        Route route = camelContext.getRoute("triage-flow-order");
        assertNotNull(route, "Expected route 'triage-flow-order' to be registered");

        ServiceStatus status = camelContext.getRouteController().getRouteStatus("triage-flow-order");
        assertTrue(status.isStarted(), () -> "Expected route 'triage-flow-order' to be started, was " + status);
    }

    @Test
    void kieBaseIsProducedAndUsable() {
        assertNotNull(orderTriageKieBase);

        KieSession kieSession = orderTriageKieBase.newKieSession();
        assertNotNull(kieSession);
        kieSession.dispose();
    }
}
