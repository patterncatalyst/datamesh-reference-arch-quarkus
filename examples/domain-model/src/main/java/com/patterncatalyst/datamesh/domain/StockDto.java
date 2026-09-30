package com.patterncatalyst.datamesh.domain;

/**
 * Framework-agnostic mirror of the {@code CheckStockResponse} gRPC message
 * (see {@code contracts/src/main/proto/capstone/inventory/v1/inventory.proto}),
 * for use by callers that want a plain domain type instead of the generated
 * gRPC stub.
 */
public record StockDto(
        String sku,
        boolean available,
        int quantityOnHand) {
}
