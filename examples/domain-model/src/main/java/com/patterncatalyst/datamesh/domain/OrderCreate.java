package com.patterncatalyst.datamesh.domain;

import java.math.BigDecimal;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * Inbound command payload for placing a new order (REST/GraphQL input type).
 *
 * <p>Carries Jakarta Bean Validation constraints so {@code order-service}'s
 * and {@code spring-boot-compare}'s {@code POST /orders} endpoints reject
 * malformed input with 400, mirroring {@code review-service}'s
 * {@code ReviewCreate} pattern. This module stays framework-agnostic: only
 * the {@code jakarta.validation} API is a compile dependency here (see
 * domain-model's pom.xml), not a validator implementation -- each consuming
 * service module brings its own (Hibernate Validator via
 * {@code quarkus-hibernate-validator} on the Quarkus side,
 * {@code spring-boot-starter-validation} on the Spring side) and wires it
 * in with {@code @Valid} on the REST input parameter.
 */
public record OrderCreate(
        @NotBlank String customerId,
        @NotBlank String itemSku,
        @Positive int quantity,
        @NotNull @DecimalMin("0.00") BigDecimal amount) {
}
