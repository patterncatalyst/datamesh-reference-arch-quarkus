package com.patterncatalyst.datamesh.springcompare;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Dev/test-only {@link StockChecker} that always reports stock as available,
 * so {@code OrderControllerTest} and local runs without a live
 * inventory-service don't depend on a real gRPC server. NOT the default
 * wiring -- {@link GrpcStockChecker} (the real inventory-service call) is
 * the production-equivalent default, matching the Quarkus order-service's
 * {@code InventoryClient}. Activate this bean explicitly with the
 * {@code dev-no-inventory} or {@code test} profile; {@code @Primary} is
 * deliberately NOT used here so a missing profile fails loudly (no
 * inventory-service bean) rather than silently skipping the real check.
 */
@Component
@Profile({"dev-no-inventory", "test"})
public class AlwaysAvailableStockChecker implements StockChecker {

    @Override
    public StockResult check(String sku, int quantity) {
        return new StockResult(true, Math.max(quantity, 1));
    }
}
