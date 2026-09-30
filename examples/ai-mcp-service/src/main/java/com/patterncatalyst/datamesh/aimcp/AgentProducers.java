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
 * <p>The chat model is built here rather than injecting the {@code ChatModel}
 * that quarkus-langchain4j produces. That bean drives the
 * {@code langchain4j-chat} classifier fine, but the agent never offered the
 * registered {@code ai-tool} routes to the model through it — the model
 * answered in a single round trip and {@code toolExecutions} came back empty.
 * Building the model directly, exactly as the Spring Boot variant does, makes
 * tool calling work on both runtimes.
 *
 * <p>Ported from the enterprise-integration-patterns-with-camel "42-ai-mcp"
 * seed (quarkus-langchain4j-bom 1.7.4) onto this reactor's pinned
 * quarkus-langchain4j-bom 1.14.1. The {@code OllamaChatModel.builder()} /
 * {@code Agent} / {@code AgentConfiguration} / {@code AgentWithoutMemory}
 * signatures used below are unchanged across that bump — see this module's
 * README for the compile-time verification notes.
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
