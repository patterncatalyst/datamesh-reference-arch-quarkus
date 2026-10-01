package com.patterncatalyst.datamesh.airules;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import com.patterncatalyst.datamesh.domain.OrderCreate;
import org.apache.camel.Exchange;
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.model.dataformat.JsonLibrary;
import org.kie.api.KieBase;
import org.kie.api.runtime.KieSession;

/**
 * DRQ-012 showcase: {@code POST /api/orders/triage} classifies an order with
 * a single-shot {@code langchain4j-chat} call (same proven, DEF-001-free
 * pattern as ai-mcp-service's {@code OrderClassifierRoute} -- no agent, no
 * tool calling), then hands the classified facts to an embedded Drools
 * {@link KieBase} which makes the actual business decision.
 *
 * <p>Because Drools (not the LLM, and not a langchain4j tool-calling round
 * trip) makes the decision, this route sidesteps DEF-001 entirely -- see
 * this module's README and {@code _plans/decisions.md}.
 */
@ApplicationScoped
public class OrderTriageRoute extends RouteBuilder {

    @Inject
    KieBase orderTriageKieBase;

    @Override
    public void configure() throws Exception {
        rest("/api/orders")
            .post("/triage")
            .consumes("application/json")
            .produces("application/json")
            .to("direct:triage");

        from("direct:triage")
            .routeId("triage-order")
            .log("Triaging order: ${body}")
            // Explicit, verified unmarshal -- the rest-dsl's own .type(...)
            // input-binding option does NOT perform this conversion on this
            // stack (no RestBindingMode is configured), so the body stays a
            // raw JSON string past it; the same JsonDataFormat used for
            // ClassificationResult below does the real binding.
            .unmarshal().json(JsonLibrary.Jackson, OrderCreate.class)
            .setProperty("orderRequest", body())
            .process(this::buildClassifyPrompt)
            .to("langchain4j-chat:triage-classifier")
            .log("Classification result: ${body}")
            .process(this::extractJsonObject)
            .unmarshal().json(JsonLibrary.Jackson, ClassificationResult.class)
            .process(this::decide)
            .marshal().json(JsonLibrary.Jackson);
    }

    /**
     * Builds the {@code CamelLangChain4jChatPrompt} header from the incoming
     * {@link OrderCreate}'s fields directly (a plain {@link Exchange}
     * processor, not a {@code simple()} OGNL property expression, since this
     * module does not depend on {@code camel-quarkus-bean}). A concrete
     * example response is embedded in the prompt alongside the schema
     * description -- qwen2.5:3b (observed) reliably classifies against a
     * worked example, but drifts into echoing the order back verbatim, or
     * free-text prose, without one.
     */
    private void buildClassifyPrompt(Exchange exchange) {
        OrderCreate order = exchange.getProperty("orderRequest", OrderCreate.class);
        String prompt = "Classify this shipping order. Respond with a JSON object having "
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
        exchange.getMessage().setHeader("CamelLangChain4jChatPrompt", prompt);
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
    private void extractJsonObject(Exchange exchange) {
        String body = exchange.getMessage().getBody(String.class);
        int start = body.indexOf('{');
        int end = body.lastIndexOf('}');
        if (start >= 0 && end > start) {
            exchange.getMessage().setBody(body.substring(start, end + 1));
        }
    }

    /**
     * Merges the original order fields with the LLM classification into an
     * {@link OrderTriageFact}, fires it through a short-lived
     * {@link KieSession} minted from the shared {@link #orderTriageKieBase},
     * and replaces the exchange body with the resulting {@link TriageDecision}.
     */
    private void decide(Exchange exchange) {
        OrderCreate order = exchange.getProperty("orderRequest", OrderCreate.class);
        ClassificationResult classification = exchange.getMessage().getBody(ClassificationResult.class);

        OrderTriageFact fact = new OrderTriageFact();
        fact.setCustomerId(order.customerId());
        fact.setItemSku(order.itemSku());
        fact.setQuantity(order.quantity());
        fact.setAmount(order.amount());
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

        TriageDecision decision = new TriageDecision(
            TriageDecision.Decision.valueOf(fact.getDecision()),
            fact.getReason(),
            fact.getCategory(),
            fact.getPriority(),
            fact.getRiskSignal(),
            fact.getCustomerId(),
            fact.getItemSku(),
            fact.getQuantity(),
            fact.getAmount());

        exchange.getMessage().setBody(decision);
    }
}
