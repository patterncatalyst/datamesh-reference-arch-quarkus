package com.patterncatalyst.datamesh.inventory;

import capstone.inventory.v1.CheckStockRequest;
import capstone.inventory.v1.CheckStockResponse;
import capstone.inventory.v1.InventoryService;

import io.quarkus.grpc.GrpcService;
import io.smallrye.mutiny.Uni;

/**
 * gRPC server implementation of {@code capstone.inventory.v1.InventoryService}
 * (contracts jar, {@code capstone/inventory/v1/inventory.proto}). Mirrors the
 * Python reference's {@code InventoryServicer.CheckStock}: look up the SKU's
 * stock row and report whether the requested quantity is available.
 *
 * <p>{@code InventoryService} is the Mutiny service interface generated at
 * build time from the proto packaged in the {@code contracts} dependency jar
 * (see {@code quarkus.generate-code.grpc.scan-for-proto} in
 * application.properties); the generated sources land under
 * {@code target/generated-sources/grpc}.
 */
@GrpcService
public class InventoryGrpcService implements InventoryService {

    @Override
    public Uni<CheckStockResponse> checkStock(CheckStockRequest request) {
        return Uni.createFrom().item(() -> {
            Stock stock = Stock.findBySku(request.getSku());
            int onHand = stock != null ? stock.quantityOnHand : 0;
            boolean available = request.getQuantity() > 0 && onHand >= request.getQuantity();
            return CheckStockResponse.newBuilder()
                    .setAvailable(available)
                    .setQuantityOnHand(onHand)
                    .build();
        });
    }
}
