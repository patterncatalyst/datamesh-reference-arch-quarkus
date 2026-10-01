package com.patterncatalyst.datamesh.springcompare;

/**
 * The order flow's one synchronous cross-service dependency: before
 * persisting an order, ask inventory-service whether the requested
 * SKU/quantity is available. Mirrors the role of {@code InventoryClient} in
 * the Quarkus order-service (a gRPC {@code CheckStock} call) -- kept behind
 * this seam so {@link OrderController} can be tested without a live gRPC
 * server (see {@link AlwaysAvailableStockChecker}, wired only for the
 * {@code test}/{@code dev-no-inventory} profiles) while the real wiring
 * ({@link GrpcStockChecker}) is the default, production-equivalent
 * implementation.
 */
public interface StockChecker {

    /**
     * @throws StockCheckUnavailableException if inventory-service could not
     *         be reached -- the caller fails closed (503), exactly like the
     *         Quarkus side's {@code StatusRuntimeException} handling.
     */
    StockResult check(String sku, int quantity);

    record StockResult(boolean available, int quantityOnHand) {
    }

    /**
     * Thrown when the upstream inventory check could not be completed (e.g.
     * the gRPC call failed or timed out). Mirrors the Quarkus side's
     * {@code io.grpc.StatusRuntimeException} case, which {@code OrderResource}
     * maps to a 503.
     */
    class StockCheckUnavailableException extends RuntimeException {
        public StockCheckUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
