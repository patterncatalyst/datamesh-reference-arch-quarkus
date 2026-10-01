package com.patterncatalyst.datamesh.airules;

import java.math.BigDecimal;

/**
 * The response body of {@code POST /api/orders/triage}: the deterministic
 * business decision Drools made, plus the classified fields and original
 * order fields it decided from, for traceability.
 *
 * @param decision the Drools-made business decision
 * @param reason a short human-readable explanation of which rule fired
 * @param category the LLM-classified order category
 * @param priority the LLM-classified order priority
 * @param riskSignal the LLM-classified fraud/risk likelihood
 * @param customerId the customer on the original order
 * @param itemSku the item SKU on the original order
 * @param quantity the quantity on the original order
 * @param amount the amount on the original order
 */
public record TriageDecision(
        Decision decision,
        String reason,
        String category,
        String priority,
        String riskSignal,
        String customerId,
        String itemSku,
        int quantity,
        BigDecimal amount) {

    /**
     * The only three outcomes the Drools rule set in
     * {@code rules/order-triage.drl} can produce. Exactly one is always set
     * per triage request -- see that file's rule ordering/guard.
     */
    public enum Decision {
        FRAUD_HOLD,
        EXPEDITE,
        ROUTE_TO_WAREHOUSE
    }
}
