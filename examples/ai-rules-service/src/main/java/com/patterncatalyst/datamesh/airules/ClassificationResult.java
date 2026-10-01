package com.patterncatalyst.datamesh.airules;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * The structured output the classify prompt asks Ollama for, unmarshalled
 * straight from the {@code langchain4j-chat} response JSON. Deliberately a
 * narrow, closed shape (three string enums) -- the tighter the requested
 * JSON, the more reliably a small local model (qwen2.5:3b) returns something
 * Jackson can parse without extra text or markdown fences.
 *
 * <p>{@code @JsonIgnoreProperties(ignoreUnknown = true)} is a defensive net,
 * not the primary defense: a small local model occasionally pads its answer
 * with extra fields (e.g. echoing the order's {@code status} back) despite
 * being told to return exactly these three keys. Any of these three fields
 * missing entirely still lands as {@code null} here and simply fails to
 * match any Drools condition that tests it, falling through to the
 * {@code ROUTE_TO_WAREHOUSE} default rule rather than throwing.
 *
 * @param category one of ELECTRONICS, PERISHABLE, HAZARDOUS, FRAGILE, STANDARD
 * @param priority one of CRITICAL, HIGH, MEDIUM, LOW
 * @param riskSignal fraud/risk likelihood: one of HIGH, MEDIUM, LOW
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record ClassificationResult(String category, String priority, String riskSignal) {
}
