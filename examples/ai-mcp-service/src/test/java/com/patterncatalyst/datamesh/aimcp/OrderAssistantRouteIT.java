package com.patterncatalyst.datamesh.aimcp;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.util.List;

import jakarta.inject.Inject;

import dev.langchain4j.service.tool.ToolExecution;
import io.quarkus.test.junit.QuarkusTest;
import org.apache.camel.Exchange;
import org.apache.camel.ProducerTemplate;
import org.apache.camel.component.langchain4j.agent.api.Headers;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

/**
 * Behavioral test for the tool-calling assistant agent ({@link OrderAssistantRoute}
 * + {@link AgentProducers} + {@link OrderLookupToolRoute}). Requires a real Ollama
 * server serving {@code qwen2.5:3b} at the configured base URL (default
 * {@code http://localhost:11434}) -- see this module's README for setup.
 *
 * <p>Deliberately deferred / opt-in:
 * <ul>
 *   <li>Named {@code *IT}, not {@code *Test} -- Surefire's default include
 *       patterns ({@code **}/{@code *Test.java} etc.) skip it, so a plain
 *       {@code mvn test} / {@code mvn package} never runs it and never needs
 *       Ollama.</li>
 *   <li>Additionally gated behind the {@code ollama.tests.enabled} system
 *       property, so even running it through Failsafe or an IDE by class name
 *       requires an explicit opt-in flag.</li>
 * </ul>
 *
 * <p>Per the task's instructions, a 200 response is NOT sufficient proof that
 * tool calling worked -- the LLM can answer from its own knowledge without
 * invoking any tool. This test asserts on the
 * {@code CamelLangChain4jAgentToolExecutions} exchange header
 * ({@link Headers#TOOL_EXECUTIONS}), which Camel populates with the list of
 * tools the agent actually invoked.
 *
 * <p>Run with:
 * <pre>
 * ollama pull qwen2.5:3b
 * ollama serve
 * mvn test -Dollama.tests.enabled=true -Dtest=OrderAssistantRouteIT -f examples/pom.xml -pl ai-mcp-service
 * </pre>
 */
@QuarkusTest
@EnabledIfSystemProperty(named = "ollama.tests.enabled", matches = "true")
class OrderAssistantRouteIT {

    @Inject
    ProducerTemplate producerTemplate;

    @Test
    void assistantCallsOrderLookupToolForAKnownOrder() {
        Exchange result = producerTemplate.request("direct:assistant-chat", exchange ->
                exchange.getMessage().setBody("What is the status of order ORD-001?"));

        assertNotNull(result.getMessage().getBody(String.class));

        @SuppressWarnings("unchecked")
        List<ToolExecution> toolExecutions =
                result.getMessage().getHeader(Headers.TOOL_EXECUTIONS, List.class);

        assertNotNull(toolExecutions, "Expected the " + Headers.TOOL_EXECUTIONS + " header to be present");
        assertFalse(toolExecutions.isEmpty(),
                "Expected the agent to call the order-status tool at least once "
                        + "(toolExecutions was empty -- the open upstream deferral DEF-001, "
                        + "see _plans/decisions.md)");
    }
}
