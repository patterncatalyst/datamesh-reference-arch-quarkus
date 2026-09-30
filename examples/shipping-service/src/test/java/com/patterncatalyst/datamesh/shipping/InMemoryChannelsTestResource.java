package com.patterncatalyst.datamesh.shipping;

import java.util.HashMap;
import java.util.Map;

import com.patterncatalyst.datamesh.domain.Topics;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import io.smallrye.reactive.messaging.memory.InMemoryConnector;

/**
 * Switches the payment-captured / shipment-dispatched channels to the
 * in-memory connector for {@link ShipmentProcessorTest}, so the choreography
 * logic in {@link ShipmentProcessor} can be unit-tested without a running
 * Kafka broker or Apicurio Registry. Pattern from the Quarkus Kafka reference
 * guide, "Testing a Kafka application &gt; Testing without a broker" (verified
 * via quarkus_searchDocs).
 */
public class InMemoryChannelsTestResource implements QuarkusTestResourceLifecycleManager {

    @Override
    public Map<String, String> start() {
        Map<String, String> env = new HashMap<>();
        env.putAll(InMemoryConnector.switchIncomingChannelsToInMemory(Topics.PAYMENT_CAPTURED_CHANNEL));
        env.putAll(InMemoryConnector.switchOutgoingChannelsToInMemory(Topics.SHIPMENT_DISPATCHED_CHANNEL));
        return env;
    }

    @Override
    public void stop() {
        InMemoryConnector.clear();
    }
}
