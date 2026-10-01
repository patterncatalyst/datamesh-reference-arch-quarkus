package com.patterncatalyst.datamesh.springcompare;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;

import capstone.order.v1.OrderPlaced;

/**
 * Supplies the strongly-typed {@code KafkaTemplate<String, OrderPlaced>} that
 * {@link OrderEventProducer} depends on. Spring Boot's Kafka auto-configuration
 * only exposes a raw {@code KafkaTemplate<Object, Object>}, whose generic type
 * does not satisfy the type-aware autowire for the Avro-typed producer bean, so
 * the application context would fail to start.
 *
 * <p>Rather than re-declare the whole producer configuration, this reuses the
 * auto-configured {@link ProducerFactory} bean (already built from the
 * {@code spring.kafka.*} properties -- bootstrap servers, key/value
 * serializers, and the {@code apicurio.registry.*} passthrough in
 * {@code application.properties}) and only re-types the template. Behaviour is
 * identical to the auto-configured template; it is merely correctly typed.
 */
@Configuration
public class KafkaConfig {

    @Bean
    @SuppressWarnings({"unchecked", "rawtypes"})
    public KafkaTemplate<String, OrderPlaced> orderPlacedKafkaTemplate(ProducerFactory producerFactory) {
        return new KafkaTemplate<>((ProducerFactory<String, OrderPlaced>) producerFactory);
    }
}
