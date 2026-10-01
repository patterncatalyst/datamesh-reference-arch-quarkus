package com.patterncatalyst.datamesh.springcompare;

import java.util.concurrent.TimeUnit;

import io.grpc.StatusRuntimeException;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import capstone.inventory.v1.Inventory.CheckStockRequest;
import capstone.inventory.v1.Inventory.CheckStockResponse;
import capstone.inventory.v1.InventoryServiceGrpc;

/**
 * Default, production-equivalent {@link StockChecker}: a synchronous gRPC
 * {@code CheckStock} call to inventory-service, mirroring
 * {@code InventoryClient} in the Quarkus order-service exactly (same 3s
 * call timeout, same fail-closed semantics -- an unreachable/erroring
 * inventory-service surfaces as {@link StockCheckUnavailableException},
 * which {@link OrderController} maps to a 503 instead of placing an order
 * it couldn't validate).
 *
 * <p>Active unless the {@code dev-no-inventory} or {@code test} profile is
 * selected (see {@link AlwaysAvailableStockChecker}) -- i.e. this is the
 * bean wired in {@code default} and {@code prod}.
 */
@Component
@Profile("!dev-no-inventory & !test")
public class GrpcStockChecker implements StockChecker {

    private static final long CALL_TIMEOUT_SECONDS = 3;

    private final InventoryServiceGrpc.InventoryServiceBlockingStub inventoryServiceStub;

    public GrpcStockChecker(InventoryServiceGrpc.InventoryServiceBlockingStub inventoryServiceStub) {
        this.inventoryServiceStub = inventoryServiceStub;
    }

    @Override
    public StockResult check(String sku, int quantity) {
        CheckStockRequest request = CheckStockRequest.newBuilder()
                .setSku(sku)
                .setQuantity(quantity)
                .build();
        try {
            CheckStockResponse response = inventoryServiceStub
                    .withDeadlineAfter(CALL_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                    .checkStock(request);
            return new StockResult(response.getAvailable(), response.getQuantityOnHand());
        } catch (StatusRuntimeException e) {
            // Fail closed: never place an order we couldn't validate against
            // inventory -- mirrors the Quarkus order-service's handling of
            // the same exception type (it's the same gRPC client library).
            throw new StockCheckUnavailableException("inventory-service unreachable: " + e.getMessage(), e);
        }
    }
}
