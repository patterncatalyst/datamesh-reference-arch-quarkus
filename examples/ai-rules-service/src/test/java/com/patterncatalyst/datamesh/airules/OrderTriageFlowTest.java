package com.patterncatalyst.datamesh.airules;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doReturn;

import java.math.BigDecimal;

import jakarta.inject.Inject;

import com.patterncatalyst.datamesh.domain.OrderCreate;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.mockito.InjectSpy;
import org.junit.jupiter.api.Test;

/**
 * Proves the DRQ-014 Quarkus Flow orchestration ({@code OrderTriageWorkflow},
 * driven through {@link OrderTriageFlowRunner}) wires correctly to the
 * <em>real</em> Drools {@code decide} step, WITHOUT calling Ollama.
 *
 * <p>{@link TriageService} is {@code @InjectSpy}'d -- not {@code @InjectMock}'d
 * -- specifically so only {@code classify} is stubbed with a canned
 * {@link ClassificationResult} per test, while {@code decide} keeps running
 * for real against the real, CDI-injected {@code KieBase}: a plain mock
 * would also null out {@code decide}'s own injected dependencies, which
 * would defeat the point of this test (proving Flow orchestration + real
 * Drools wiring together).
 *
 * <p>Runs under the default {@code mvn verify} (no live Ollama server
 * required). The opt-in, Ollama-backed end-to-end test lives in
 * {@link OrderTriageFlowRouteIT}.
 */
@QuarkusTest
class OrderTriageFlowTest {

    @Inject
    OrderTriageFlowRunner triageFlowRunner;

    @InjectSpy
    TriageService triageService;

    @Test
    void highRiskClassificationFlowsToFraudHold() {
        OrderCreate order = new OrderCreate("CUST-1", "SKU-1", 1, new BigDecimal("50.00"));
        ClassificationResult highRisk = new ClassificationResult(
            "ELECTRONICS", "HIGH", "HIGH",
            order.customerId(), order.itemSku(), order.quantity(), order.amount());
        doReturn(highRisk).when(triageService).classify(any());

        TriageDecision decision = triageFlowRunner.run(order);

        assertEquals(TriageDecision.Decision.FRAUD_HOLD, decision.decision());
    }

    @Test
    void benignClassificationFlowsToWarehouse() {
        OrderCreate order = new OrderCreate("CUST-3", "SKU-3", 1, new BigDecimal("42.00"));
        ClassificationResult benign = new ClassificationResult(
            "STANDARD", "LOW", "MEDIUM",
            order.customerId(), order.itemSku(), order.quantity(), order.amount());
        doReturn(benign).when(triageService).classify(any());

        TriageDecision decision = triageFlowRunner.run(order);

        assertEquals(TriageDecision.Decision.ROUTE_TO_WAREHOUSE, decision.decision());
    }
}
