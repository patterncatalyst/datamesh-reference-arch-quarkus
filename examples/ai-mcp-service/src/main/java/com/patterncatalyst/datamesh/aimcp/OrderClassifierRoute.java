package com.patterncatalyst.datamesh.aimcp;

import jakarta.enterprise.context.ApplicationScoped;
import org.apache.camel.builder.RouteBuilder;

/**
 * REST entry point that classifies an order via a single-shot langchain4j
 * chat call (no tool calling here -- see {@link OrderAssistantRoute} for the
 * tool-calling agent).
 */
@ApplicationScoped
public class OrderClassifierRoute extends RouteBuilder {

    @Override
    public void configure() throws Exception {
        rest("/api/orders")
            .post("/classify")
            .consumes("application/json")
            .produces("application/json")
            .to("direct:classify-order");

        from("direct:classify-order")
            .routeId("classify-order")
            .log("Classifying order: ${body}")
            // NOTE (demo step 10.4, uncommitted fix -- see demos/demo-ai-classify.sh):
            // this route previously set a header named "CamelLangChain4jChatPrompt"
            // (missing the "Template" suffix) and never switched the endpoint off
            // its default CHAT_SINGLE_MESSAGE operation. Neither
            // LangChain4jChatHeaders.PROMPT_TEMPLATE
            // ("CamelLangChain4jChatPromptTemplate", confirmed via the camel-mcp
            // catalog + LangChain4jChatProducer bytecode) nor the
            // CHAT_SINGLE_MESSAGE_WITH_PROMPT operation were ever engaged, so the
            // component silently fell back to sending the raw order JSON body as a
            // plain chat message -- the model just chatted about the order
            // ("You have requested one laptop...") instead of classifying it
            // (confirmed empirically, deterministically, across repeated calls).
            // Fixed here: correct header name + chatOperation=CHAT_SINGLE_MESSAGE_WITH_PROMPT.
            .setHeader("CamelLangChain4jChatPromptTemplate", simple(
                "You are an order classification assistant for a shipping company. "
                + "Classify the following order and return a JSON object with these fields: "
                + "category (one of: ELECTRONICS, PERISHABLE, HAZARDOUS, FRAGILE, STANDARD), "
                + "priority (one of: CRITICAL, HIGH, MEDIUM, LOW), "
                + "fulfillmentType (one of: SAME_DAY, NEXT_DAY, STANDARD, ECONOMY). "
                + "Only return the JSON, no other text. Order: ${body}"))
            // CHAT_SINGLE_MESSAGE_WITH_PROMPT requires the body to be a
            // Map<String,Object> of PromptTemplate variables (langchain4j's
            // PromptTemplate.apply(Map)); the prompt text above is already fully
            // resolved by `simple()` (no {{placeholders}} left for langchain4j to
            // substitute), so an empty map satisfies the mandatory-body check.
            .process(exchange -> exchange.getIn().setBody(java.util.Collections.emptyMap()))
            .to("langchain4j-chat:classifier?chatOperation=CHAT_SINGLE_MESSAGE_WITH_PROMPT")
            .log("Classification result: ${body}");
    }
}
