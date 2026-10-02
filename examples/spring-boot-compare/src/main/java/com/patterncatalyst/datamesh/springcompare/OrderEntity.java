package com.patterncatalyst.datamesh.springcompare;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import com.patterncatalyst.datamesh.domain.OrderStatus;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * JPA twin of the Quarkus order-service's Panache {@code Order} entity
 * -- same table name, same columns/types/constraints, so the
 * two services are a fair side-by-side comparison. Spring Data JPA has no
 * active-record equivalent to Panache, so persistence operations go
 * through {@link OrderRepository} instead of instance methods here.
 */
@Entity
@Table(name = "orders")
public class OrderEntity {

    @Id
    @Column(length = 36, nullable = false, updatable = false)
    private String id;

    @Column(name = "customer_id", nullable = false)
    private String customerId;

    @Column(name = "item_sku", nullable = false)
    private String itemSku;

    @Column(nullable = false)
    private int quantity;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private OrderStatus status;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    /**
     * No-arg constructor required by JPA.
     */
    protected OrderEntity() {
    }

    /**
     * Factory for a newly placed order: assigns a fresh id, defaults status
     * to {@link OrderStatus#PLACED}, and stamps the creation time -- mirrors
     * {@code Order.create(...)} in the Quarkus twin exactly.
     */
    public static OrderEntity create(String customerId, String itemSku, int quantity, BigDecimal amount) {
        OrderEntity order = new OrderEntity();
        order.id = UUID.randomUUID().toString();
        order.customerId = customerId;
        order.itemSku = itemSku;
        order.quantity = quantity;
        order.amount = amount;
        order.status = OrderStatus.PLACED;
        order.createdAt = Instant.now();
        return order;
    }

    public String getId() {
        return id;
    }

    public String getCustomerId() {
        return customerId;
    }

    public String getItemSku() {
        return itemSku;
    }

    public int getQuantity() {
        return quantity;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public OrderStatus getStatus() {
        return status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
