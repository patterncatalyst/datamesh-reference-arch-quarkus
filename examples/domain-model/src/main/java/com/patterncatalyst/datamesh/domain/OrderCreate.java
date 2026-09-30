package com.patterncatalyst.datamesh.domain;

import java.math.BigDecimal;

/**
 * Inbound command payload for placing a new order (REST/GraphQL input type).
 */
public record OrderCreate(
        String customerId,
        String itemSku,
        int quantity,
        BigDecimal amount) {
}
