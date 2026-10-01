package com.patterncatalyst.datamesh.aimcp;

import java.time.Duration;

import dev.langchain4j.model.chat.ChatModel;
import dev.langchain4j.model.ollama.OllamaChatModel;
import io.smallrye.common.annotation.Identifier;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import org.apache.camel.component.langchain4j.agent.api.Agent;
import org.apache.camel.component.langchain4j.agent.api.AgentConfiguration;
import org.apache.camel.component.langchain4j.agent.api.AgentWithoutMemory;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Supplies the agent that {@code langchain4j-agent:} endpoints reference by name.
 *
 * <p>Built directly from an {@link OllamaChatModel}, mirroring the
 * enterprise-integration-patterns-with-camel "42-ai-mcp" seed and the Spring Boot
 * variant, rather than injecting the synthetic {@code ChatModel} that
 * quarkus-langchain4j produces. The two paths behave identically here (see the
 * DEF-001 note below); the explicit build is kept because it is the form the
 * tutorial explains and the one that is portable across runtimes.
 *
 * <p><strong>DEF-001 (open behavioral deferral) — tool calling does not fire on
 * this stack.</strong> The {@code OrderAssistantRouteIT} assertion that the agent
 * invokes the {@code order-status} ai-tool (a non-empty
 * {@code CamelLangChain4jAgentToolExecutions} header) currently fails: the model
 * answers in a single round trip and never calls the tool. Root cause, after
 * exhaustive diagnosis, is upstream integration — not this code, the model, the
 * tags, or the langchain4j version:
 * <ul>
 *   <li>{@code camel-quarkus-support-langchain4j} unconditionally sets the global
 *       {@code langchain4j.http.clientBuilderFactory} system property to the
 *       Quarkiverse JAX-RS factory ("enforcing JAX-RS HTTP client factory"), so
 *       the transport is Quarkus-controlled regardless of what this builder sets —
 *       the configured {@code base-url} on the hand-built model is not honoured
 *       (requests resolve to the dev-service-detected Ollama on 11434), and an
 *       explicit {@code httpClientBuilder(new JdkHttpClientBuilder())} does not
 *       change it.</li>
 *   <li>Ruled out: model capability (a direct {@code /api/chat} curl with a tools
 *       array elicits a {@code tool_calls} response from both {@code qwen2.5:3b}
 *       and {@code qwen2.5:7b-instruct}); tool registration and tag matching (the
 *       ai-tool route is tagged {@code shipping}, the agent filters on
 *       {@code shipping}); and langchain4j versions (classpath matches the seed
 *       exactly — Quarkiverse 1.7.4, dev.langchain4j 1.11.0, camel 4.22.0 /
 *       camel-quarkus 3.39.0; the seed itself ships no test asserting this).</li>
 * </ul>
 * The IT is opt-in ({@code -Dollama.tests.enabled=true}) and is not bound into the
 * default {@code mvn verify}, so the deferral does not break the reactor build.
 * See {@code _plans/decisions.md} (DEF-001) for the full write-up.
 *
 * <p>{@link AgentWithoutMemory} treats every exchange as an independent
 * conversation. For a multi-turn assistant, produce an {@code AgentWithMemory}
 * and set a {@code ChatMemoryProvider} on the {@link AgentConfiguration}.
 */
@ApplicationScoped
public class AgentProducers {

    @ConfigProperty(name = "quarkus.langchain4j.ollama.base-url", defaultValue = "http://localhost:11434")
    String baseUrl;

    @ConfigProperty(name = "quarkus.langchain4j.ollama.chat-model.model-id", defaultValue = "qwen2.5:3b")
    String modelName;

    @Produces
    @Identifier("assistantAgent")
    Agent assistantAgent() {
        ChatModel chatModel = OllamaChatModel.builder()
            .baseUrl(baseUrl)
            .modelName(modelName)
            .timeout(Duration.ofSeconds(120))
            .build();

        AgentConfiguration config = new AgentConfiguration()
            .withChatModel(chatModel);

        return new AgentWithoutMemory(config);
    }
}
