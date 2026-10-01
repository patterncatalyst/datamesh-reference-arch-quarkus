package com.patterncatalyst.datamesh.airules;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.math.BigDecimal;

import org.junit.jupiter.api.Test;
import org.kie.api.KieBase;
import org.kie.api.io.ResourceType;
import org.kie.api.runtime.KieSession;
import org.kie.internal.io.ResourceFactory;
import org.kie.internal.utils.KieHelper;

/**
 * Isolated Drools unit test for {@code rules/order-triage.drl} -- plain
 * JUnit, no Quarkus bootstrap and no Ollama. Builds the {@link KieBase}
 * directly (the same recipe {@link RuleBaseProducer} uses at runtime) and
 * fires each of the three possible {@link TriageDecision.Decision} outcomes
 * from hand-built {@link OrderTriageFact} instances, bypassing the LLM
 * classification step entirely.
 *
 * <p>Runs under the default {@code mvn verify} (it is a {@code *Test}, not
 * an {@code *IT}) -- see {@link OrderTriageRouteIT} for the opt-in,
 * Ollama-backed end-to-end test.
 */
class OrderTriageDrlTest {

    private static KieBase buildKieBase() {
        KieHelper kieHelper = new KieHelper();
        kieHelper.addResource(
            ResourceFactory.newClassPathResource("rules/order-triage.drl"),
            ResourceType.DRL);
        KieBase kieBase = kieHelper.build();
        assertNotNull(kieBase, "KieHelper.build() should produce a KieBase from order-triage.drl");
        return kieBase;
    }

    private static OrderTriageFact fire(OrderTriageFact fact) {
        KieBase kieBase = buildKieBase();
        KieSession kieSession = kieBase.newKieSession();
        try {
            kieSession.insert(fact);
            kieSession.fireAllRules();
        } finally {
            kieSession.dispose();
        }
        return fact;
    }

    @Test
    void highRiskSignalTriggersFraudHold() {
        OrderTriageFact fact = new OrderTriageFact();
        fact.setCustomerId("CUST-1");
        fact.setItemSku("SKU-1");
        fact.setQuantity(1);
        fact.setAmount(new BigDecimal("50.00"));
        fact.setCategory("ELECTRONICS");
        fact.setPriority("HIGH");
        fact.setRiskSignal("HIGH");

        fire(fact);

        assertEquals("FRAUD_HOLD", fact.getDecision());
        assertNotNull(fact.getReason());
    }

    @Test
    void largeLowRiskOrderTriggersExpedite() {
        OrderTriageFact fact = new OrderTriageFact();
        fact.setCustomerId("CUST-2");
        fact.setItemSku("SKU-2");
        fact.setQuantity(2);
        fact.setAmount(new BigDecimal("1500.00"));
        fact.setCategory("STANDARD");
        fact.setPriority("MEDIUM");
        fact.setRiskSignal("LOW");

        fire(fact);

        assertEquals("EXPEDITE", fact.getDecision());
        assertNotNull(fact.getReason());
    }

    @Test
    void ordinarySmallOrderRoutesToWarehouse() {
        OrderTriageFact fact = new OrderTriageFact();
        fact.setCustomerId("CUST-3");
        fact.setItemSku("SKU-3");
        fact.setQuantity(1);
        fact.setAmount(new BigDecimal("42.00"));
        fact.setCategory("STANDARD");
        fact.setPriority("LOW");
        fact.setRiskSignal("MEDIUM");

        fire(fact);

        assertEquals("ROUTE_TO_WAREHOUSE", fact.getDecision());
        assertNotNull(fact.getReason());
    }
}
