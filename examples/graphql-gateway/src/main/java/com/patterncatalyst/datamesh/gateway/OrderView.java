package com.patterncatalyst.datamesh.gateway;

import java.math.BigDecimal;

import org.eclipse.microprofile.graphql.Description;

import com.patterncatalyst.datamesh.domain.OrderDto;
import com.patterncatalyst.datamesh.domain.OrderStatus;

/**
 * GraphQL view of an order, resolved over REST from order-service. The
 * nested {@code stock} field (see {@link GatewayApi#stock(OrderView)}) is
 * federated separately over gRPC from inventory-service -- this record only
 * carries what order-service itself returns.
 */
@Description("An order, federated from order-service (REST) with a nested live stock lookup from inventory-service (gRPC).")
public record OrderView(
        String id,
        String customerId,
        String itemSku,
        int quantity,
        BigDecimal amount,
        OrderStatus status,
        String createdAt) {

    /**
     * Maps the shared {@link OrderDto} (order-service's REST response shape)
     * onto the gateway's GraphQL type. Kept as a narrow adapter so the
     * GraphQL schema's field set can evolve independently of the wire DTO.
     */
    static OrderView from(OrderDto dto) {
        return new OrderView(
                dto.orderId(),
                dto.customerId(),
                dto.itemSku(),
                dto.quantity(),
                dto.amount(),
                dto.status(),
                dto.createdAt());
    }
}
