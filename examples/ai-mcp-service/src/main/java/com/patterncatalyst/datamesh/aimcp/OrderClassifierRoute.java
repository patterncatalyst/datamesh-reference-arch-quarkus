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
            .setHeader("CamelLangChain4jChatPrompt", simple(
                "You are an order classification assistant for a shipping company. "
                + "Classify the following order and return a JSON object with these fields: "
                + "category (one of: ELECTRONICS, PERISHABLE, HAZARDOUS, FRAGILE, STANDARD), "
                + "priority (one of: CRITICAL, HIGH, MEDIUM, LOW), "
                + "fulfillmentType (one of: SAME_DAY, NEXT_DAY, STANDARD, ECONOMY). "
                + "Only return the JSON, no other text. Order: ${body}"))
            .to("langchain4j-chat:classifier")
            .log("Classification result: ${body}");
    }
}
