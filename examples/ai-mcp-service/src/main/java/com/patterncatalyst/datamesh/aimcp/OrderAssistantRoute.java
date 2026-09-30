package com.patterncatalyst.datamesh.aimcp;

import jakarta.enterprise.context.ApplicationScoped;
import org.apache.camel.builder.RouteBuilder;

@ApplicationScoped
public class OrderAssistantRoute extends RouteBuilder {

    @Override
    public void configure() throws Exception {
        // The question is plain text, not a JSON document. Declaring it as
        // application/json makes langchain4j-agent reject the body: its
        // converter only accepts text/*, image/*, audio/*, video/* and
        // application/pdf, so a JSON content type fails before the agent runs.
        rest("/api/assistant")
            .post("/chat")
            .consumes("text/plain")
            .produces("text/plain")
            .to("direct:assistant-chat");

        from("direct:assistant-chat")
            .routeId("assistant-chat")
            // The agent needs the question as a String; the HTTP layer hands
            // over a stream.
            .convertBodyTo(String.class)
            .log("Assistant query: ${body}")
            // The agent takes the system prompt as its own header and the user
            // query as the body, rather than the two being concatenated into a
            // single chat prompt.
            .setHeader("CamelLangChain4jAgentSystemMessage", constant(
                "You are a helpful shipping order assistant. You can look up order statuses "
                + "using the available tools. Be concise and helpful."))
            // tags=shipping selects the ai-tool routes this agent may call.
            .to("langchain4j-agent:assistant?agent=#assistantAgent&tags=shipping")
            .log("Assistant response: ${body}");
    }
}
