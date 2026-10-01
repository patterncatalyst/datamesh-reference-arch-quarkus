package com.patterncatalyst.datamesh.airules;

import java.math.BigDecimal;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * The fully classified order, ready for the Drools decision step: the three
 * fields the classify prompt asks Ollama for (category/priority/riskSignal)
 * merged with the original order's identifying/amount fields.
 *
 * <p>This is the single-argument shape both {@link TriageService#classify}
 * returns and {@link TriageService#decide} consumes. Carrying the order
 * fields here (not just the LLM's three-field answer) is what lets
 * {@code decide} be a plain, self-sufficient one-argument function --
 * required for the Quarkus Flow path, where {@code OrderTriageWorkflow}
 * chains a step's output straight into the next step's input with no
 * second parameter available. The raw, three-field JSON Ollama actually
 * returns is parsed into a private intermediate shape inside
 * {@link TriageService} and merged with the order's fields to produce this
 * record; {@code category}/{@code priority}/{@code riskSignal} missing
 * entirely from that raw JSON still lands as {@code null} here and simply
 * fails to match any Drools condition that tests it, falling through to the
 * {@code ROUTE_TO_WAREHOUSE} default rule rather than throwing.
 *
 * @param category one of ELECTRONICS, PERISHABLE, HAZARDOUS, FRAGILE, STANDARD
 * @param priority one of CRITICAL, HIGH, MEDIUM, LOW
 * @param riskSignal fraud/risk likelihood: one of HIGH, MEDIUM, LOW
 * @param customerId the customer on the original order
 * @param itemSku the item SKU on the original order
 * @param quantity the quantity on the original order
 * @param amount the amount on the original order
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record ClassificationResult(
        String category,
        String priority,
        String riskSignal,
        String customerId,
        String itemSku,
        int quantity,
        BigDecimal amount) {
}
