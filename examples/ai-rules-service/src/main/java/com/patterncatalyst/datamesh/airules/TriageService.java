package com.patterncatalyst.datamesh.airules;

import java.io.UncheckedIOException;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.patterncatalyst.datamesh.domain.OrderCreate;
import dev.langchain4j.model.chat.ChatModel;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.kie.api.KieBase;
import org.kie.api.runtime.KieSession;

/**
 * The single source of truth for "classify, then decide" --
 * extracted so both {@link OrderTriageRoute} (Camel orchestration,
 * {@code /triage}) and {@code OrderTriageWorkflow} (Quarkus Flow
 * orchestration, {@code /triage-flow}) run the exact same classify + Drools
 * decide logic. The two routes differ only in HOW the two steps are
 * sequenced (a Camel route vs. a Flow workflow); neither reimplements any
 * part of this logic itself.
 *
 * <p>{@code @ApplicationScoped} (not {@code @Singleton}) is load-bearing:
 * both the Camel route and the Flow workflow hold a normal-scope CDI client
 * proxy to this bean, not a direct reference, which is what lets
 * {@code @InjectMock TriageService} in tests swap in a mock without either
 * caller needing to re-resolve the bean.
 */
@ApplicationScoped
public class TriageService {

    @Inject
    ChatModel chatModel;

    @Inject
    KieBase orderTriageKieBase;

    @Inject
    ObjectMapper objectMapper;

    /**
     * Classifies the order with a single-shot {@code langchain4j}-style chat
     * call direct to the injected {@link ChatModel} (same proven,
     * tool-calling-free pattern as the former {@code OrderTriageRoute} -- no
     * agent, no tool calling), then merges the result with the order's own
     * fields into a single {@link ClassificationResult} that {@link #decide}
     * can act on without needing the original order again.
     */
    public ClassificationResult classify(OrderCreate order) {
        String prompt = buildClassifyPrompt(order);
        String response = chatModel.chat(prompt);
        String json = extractJsonObject(response);

        RawClassification raw;
        try {
            raw = objectMapper.readValue(json, RawClassification.class);
        } catch (JsonProcessingException e) {
            throw new UncheckedIOException("Failed to parse classification JSON: " + json, e);
        }

        return new ClassificationResult(
            raw.category(),
            raw.priority(),
            raw.riskSignal(),
            order.customerId(),
            order.itemSku(),
            order.quantity(),
            order.amount());
    }

    /**
     * Builds the chat prompt from the incoming {@link OrderCreate}'s fields.
     * A concrete example response is embedded in the prompt alongside the
     * schema description -- qwen2.5:3b (observed) reliably classifies
     * against a worked example, but drifts into echoing the order back
     * verbatim, or free-text prose, without one.
     */
    private String buildClassifyPrompt(OrderCreate order) {
        return "Classify this shipping order. Respond with a JSON object having "
            + "exactly these three keys and nothing else: category, priority, riskSignal. "
            + "category must be one of ELECTRONICS, PERISHABLE, HAZARDOUS, FRAGILE, STANDARD. "
            + "priority must be one of CRITICAL, HIGH, MEDIUM, LOW. "
            + "riskSignal must be one of HIGH, MEDIUM, LOW and represents how likely this "
            + "order is to be fraudulent. "
            + "Example response: {\"category\":\"STANDARD\",\"priority\":\"LOW\",\"riskSignal\":\"LOW\"}. "
            + "Order details: item=" + order.itemSku()
            + ", quantity=" + order.quantity()
            + ", amount=" + order.amount()
            + ", customer=" + order.customerId() + ".";
    }

    /**
     * Defensively narrows the chat response down to its JSON object before
     * unmarshalling. The prompt explicitly asks for "ONLY a JSON object ...
     * no markdown fences", but small local models (qwen2.5:3b observed)
     * sometimes wrap the answer in a {@code ```json ... ```} fence anyway;
     * taking the substring between the first {@code {} and the last
     * {@code }} tolerates that (and any other stray leading/trailing prose)
     * without having to trust the model's formatting discipline.
     */
    private String extractJsonObject(String body) {
        int start = body.indexOf('{');
        int end = body.lastIndexOf('}');
        if (start >= 0 && end > start) {
            return body.substring(start, end + 1);
        }
        return body;
    }

    /**
     * Fires a merged classification through a short-lived {@link KieSession}
     * minted from the shared {@link #orderTriageKieBase} and returns the
     * resulting {@link TriageDecision}. Drools -- not the LLM -- makes the
     * business decision; see {@code rules/order-triage.drl}.
     */
    public TriageDecision decide(ClassificationResult classification) {
        OrderTriageFact fact = new OrderTriageFact();
        fact.setCustomerId(classification.customerId());
        fact.setItemSku(classification.itemSku());
        fact.setQuantity(classification.quantity());
        fact.setAmount(classification.amount());
        fact.setCategory(classification.category());
        fact.setPriority(classification.priority());
        fact.setRiskSignal(classification.riskSignal());

        // KieBase is built once at startup and reused; mint a fresh,
        // short-lived KieSession per request and dispose it immediately
        // after firing -- KieSession is NOT thread-safe / reusable like
        // KieBase is.
        KieSession kieSession = orderTriageKieBase.newKieSession();
        try {
            kieSession.insert(fact);
            kieSession.fireAllRules();
        } finally {
            kieSession.dispose();
        }

        // Defensive fallback: every rule in order-triage.drl guards on
        // `decision == null` and the default rule (salience 10) always
        // fires if none of the others do, so fact.getDecision() is never
        // actually null today. But an edited DRL that drops or
        // mis-guards the default rule must not NPE here -- fail safe by
        // treating an unset decision as FRAUD_HOLD (hold for manual
        // review) rather than silently routing an unreviewed order to
        // fulfillment.
        TriageDecision.Decision decision = fact.getDecision() != null
            ? TriageDecision.Decision.valueOf(fact.getDecision())
            : TriageDecision.Decision.FRAUD_HOLD;

        return new TriageDecision(
            decision,
            fact.getReason(),
            fact.getCategory(),
            fact.getPriority(),
            fact.getRiskSignal(),
            fact.getCustomerId(),
            fact.getItemSku(),
            fact.getQuantity(),
            fact.getAmount());
    }

    /**
     * The raw, three-field shape Ollama's JSON response actually deserializes
     * to, before it is merged with the order's own fields into the public
     * {@link ClassificationResult}. Kept private/internal to this class --
     * callers never see this shape.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawClassification(String category, String priority, String riskSignal) {
    }
}
