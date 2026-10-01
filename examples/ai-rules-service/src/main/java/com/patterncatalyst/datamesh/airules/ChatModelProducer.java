package com.patterncatalyst.datamesh.airules;

import java.time.Duration;

import dev.langchain4j.model.chat.ChatModel;
import dev.langchain4j.model.chat.request.ResponseFormat;
import dev.langchain4j.model.ollama.OllamaChatModel;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Supplies the {@link ChatModel} that {@code langchain4j-chat:} endpoints
 * autowire by type (see {@link OrderTriageRoute}).
 *
 * <p>Built directly from an {@link OllamaChatModel}, mirroring ai-mcp-
 * service's {@code AgentProducers}, rather than relying on
 * quarkus-langchain4j-ollama's own synthetic {@code ChatModel} CDI bean.
 * That synthetic bean is only synthesized by
 * {@code io.quarkiverse.langchain4j.deployment.BeansProcessor#handleProviders}
 * when something in the application has a <em>static</em>, Jandex-visible
 * injection point for {@code ChatModel} (an {@code @Inject ChatModel} field,
 * or a {@code @RegisterAiService} interface) -- a runtime-only CDI type
 * lookup, which is all Camel's {@code langchain4j-chat:} component does to
 * autowire its {@code chatModel} property, is invisible to that build step.
 * ai-mcp-service's classifier route is unaffected by this because that
 * module also pulls in {@code camel-quarkus-langchain4j-agent}, whose
 * {@code Agent} bean wiring happens to create such an injection point; this
 * module deliberately depends on neither (see the pom's DEF-001 note), so
 * without an explicit producer like this one the route fails to start with
 * {@code "chatModel must be specified"}.
 */
@ApplicationScoped
public class ChatModelProducer {

    @ConfigProperty(name = "quarkus.langchain4j.ollama.base-url", defaultValue = "http://localhost:11434")
    String baseUrl;

    @ConfigProperty(name = "quarkus.langchain4j.ollama.chat-model.model-id", defaultValue = "qwen2.5:3b")
    String modelName;

    @Produces
    @ApplicationScoped
    public ChatModel chatModel() {
        return OllamaChatModel.builder()
            .baseUrl(baseUrl)
            .modelName(modelName)
            .timeout(Duration.ofSeconds(120))
            // Forces Ollama's native JSON output mode. The classify prompt
            // in OrderTriageRoute already asks for "ONLY a JSON object ...
            // no markdown fences", but small local models (qwen2.5:3b
            // observed) don't reliably follow that instruction on their
            // own -- wrapping the answer in a ```json fence, or dropping
            // into free-text prose instead of JSON entirely. This makes
            // Ollama itself constrain decoding to valid JSON syntax
            // (it does not enforce the specific category/priority/
            // riskSignal schema -- OrderTriageRoute still defensively
            // extracts the {...} substring before unmarshalling).
            .responseFormat(ResponseFormat.JSON)
            .build();
    }
}
