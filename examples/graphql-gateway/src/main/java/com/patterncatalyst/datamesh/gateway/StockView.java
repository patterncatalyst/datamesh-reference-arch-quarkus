package com.patterncatalyst.datamesh.gateway;

import org.eclipse.microprofile.graphql.Description;

/**
 * GraphQL view of stock for a single SKU, resolved over gRPC from
 * inventory-service's {@code CheckStock} RPC
 * (capstone.inventory.v1.InventoryService). Nested under {@link OrderView#stock}
 * (see {@link GatewayApi#stock(OrderView)}) rather than fetched top-level, so
 * the availability figure is always scoped to the order's own SKU and quantity.
 */
@Description("Point-in-time stock for a SKU, as reported by inventory-service over gRPC.")
public record StockView(String sku, int quantityOnHand, boolean available) {
}
