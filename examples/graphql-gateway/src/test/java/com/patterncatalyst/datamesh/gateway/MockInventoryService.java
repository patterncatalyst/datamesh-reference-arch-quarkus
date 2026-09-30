package com.patterncatalyst.datamesh.gateway;

import capstone.inventory.v1.Inventory.CheckStockRequest;
import capstone.inventory.v1.Inventory.CheckStockResponse;
import capstone.inventory.v1.InventoryService;

import io.quarkus.grpc.GrpcService;
import io.smallrye.mutiny.Uni;

/**
 * In-process gRPC stand-in for inventory-service, used by {@link GatewayApiTest}.
 *
 * <p>The gateway's {@code @GrpcClient("inventory")} blocking stub is a
 * {@code @Singleton} bean, which cannot be replaced by {@code @InjectMock} or
 * {@code QuarkusMock} (only normal-scoped beans are mockable). Registering this
 * {@code @GrpcService} in test scope starts an in-process gRPC server that the
 * gateway's real client dials, so the federation path is exercised over the
 * wire. Responses are fixed and independent of the request, which is enough to
 * assert the gateway stitches the nested {@code stock} field.
 */
@GrpcService
public class MockInventoryService implements InventoryService {

    public static final int QUANTITY_ON_HAND = 42;

    @Override
    public Uni<CheckStockResponse> checkStock(CheckStockRequest request) {
        return Uni.createFrom().item(CheckStockResponse.newBuilder()
                .setAvailable(true)
                .setQuantityOnHand(QUANTITY_ON_HAND)
                .build());
    }
}
