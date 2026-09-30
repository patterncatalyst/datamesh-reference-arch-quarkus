package com.patterncatalyst.datamesh.domain;

import java.math.BigDecimal;

/**
 * Framework-agnostic view of an order, used across REST/GraphQL responses
 * and internal service-to-service calls. Not a Panache entity -- the JPA
 * entity lives in order-service and is mapped to/from this DTO at the
 * boundary.
 */
public record OrderDto(
        String orderId,
        String customerId,
        String itemSku,
        int quantity,
        BigDecimal amount,
        OrderStatus status,
        String createdAt) {
}
