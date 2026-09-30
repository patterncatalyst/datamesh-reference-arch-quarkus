package com.patterncatalyst.datamesh.inventory;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import capstone.inventory.v1.Inventory.CheckStockRequest;
import capstone.inventory.v1.Inventory.CheckStockResponse;
import capstone.inventory.v1.InventoryService;

import io.quarkus.grpc.GrpcClient;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;

/**
 * Exercises InventoryService/CheckStock end-to-end over a real gRPC client
 * (see the "Testing your services" section of the Quarkus gRPC service
 * implementation guide) against the seeded import.sql rows and a row seeded
 * per-test.
 *
 * NOTE: written per the EXECUTE task spec but intentionally not run here.
 */
@QuarkusTest
class InventoryGrpcServiceTest {

    @GrpcClient
    InventoryService inventoryService;

    @BeforeEach
    void resetKnownSku() {
        QuarkusTransaction.requiringNew().run(() -> {
            Stock stock = Stock.findBySku("WIDGET-1");
            if (stock == null) {
                new Stock("WIDGET-1", 50).persist();
            } else {
                stock.quantityOnHand = 50;
            }
        });
    }

    @Test
    void reportsAvailableWhenEnoughStock() throws Exception {
        CompletableFuture<CheckStockResponse> future = new CompletableFuture<>();
        inventoryService.checkStock(CheckStockRequest.newBuilder()
                .setSku("WIDGET-1")
                .setQuantity(10)
                .build())
                .subscribe().with(future::complete, future::completeExceptionally);

        CheckStockResponse response = future.get(5, TimeUnit.SECONDS);
        assertTrue(response.getAvailable());
        assertEquals(50, response.getQuantityOnHand());
    }

    @Test
    void reportsUnavailableWhenRequestExceedsStock() throws Exception {
        CompletableFuture<CheckStockResponse> future = new CompletableFuture<>();
        inventoryService.checkStock(CheckStockRequest.newBuilder()
                .setSku("WIDGET-1")
                .setQuantity(999)
                .build())
                .subscribe().with(future::complete, future::completeExceptionally);

        CheckStockResponse response = future.get(5, TimeUnit.SECONDS);
        assertFalse(response.getAvailable());
        assertEquals(50, response.getQuantityOnHand());
    }

    @Test
    void reportsZeroOnHandForUnknownSku() throws Exception {
        CompletableFuture<CheckStockResponse> future = new CompletableFuture<>();
        inventoryService.checkStock(CheckStockRequest.newBuilder()
                .setSku("DOES-NOT-EXIST")
                .setQuantity(1)
                .build())
                .subscribe().with(future::complete, future::completeExceptionally);

        CheckStockResponse response = future.get(5, TimeUnit.SECONDS);
        assertFalse(response.getAvailable());
        assertEquals(0, response.getQuantityOnHand());
    }
}
