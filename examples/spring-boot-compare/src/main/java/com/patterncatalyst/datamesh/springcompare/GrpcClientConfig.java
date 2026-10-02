package com.patterncatalyst.datamesh.springcompare;

import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import jakarta.annotation.PreDestroy;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import capstone.inventory.v1.InventoryServiceGrpc;

/**
 * Wires the plain grpc-java channel/stub to inventory-service, mirroring the
 * Quarkus order-service's {@code @GrpcClient("inventory")} config
 * ({@code quarkus.grpc.clients.inventory.host}/{@code .port} in
 * {@code application.properties}). Host/port are env-overridable with the
 * SAME names and defaults (canonical inventory gRPC port is 9000) so
 * compose/K8s manifests can point both twins at the same target without a
 * code change.
 */
@Configuration
public class GrpcClientConfig {

    private ManagedChannel channel;

    @Bean
    public ManagedChannel inventoryChannel(
            @Value("${INVENTORY_GRPC_HOST:localhost}") String host,
            @Value("${INVENTORY_GRPC_PORT:9000}") int port) {
        // Plaintext, matching the Quarkus client's default (no TLS configured
        // for either side of this internal, same-network call).
        this.channel = ManagedChannelBuilder.forAddress(host, port)
                .usePlaintext()
                .build();
        return channel;
    }

    @Bean
    public InventoryServiceGrpc.InventoryServiceBlockingStub inventoryServiceStub(ManagedChannel inventoryChannel) {
        return InventoryServiceGrpc.newBlockingStub(inventoryChannel);
    }

    @PreDestroy
    public void shutdownChannel() {
        if (channel != null) {
            channel.shutdown();
        }
    }
}
