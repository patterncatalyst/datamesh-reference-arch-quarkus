package com.patterncatalyst.datamesh.order;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import com.patterncatalyst.datamesh.domain.OrderStatus;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Order aggregate, owned exclusively by order-service (CAP-003 per-service
 * data ownership -- other services only observe order state via the
 * {@code order.placed} event, never this table). Persisted with Hibernate
 * ORM Panache (active record).
 *
 * <p>The {@code String} UUID primary key mirrors the Python reference
 * architecture's {@code Order.id} (see
 * {@code services/order-service/app/models.py}) and matches
 * {@code domain-model}'s {@code OrderDto#orderId}.
 */
@Entity
@Table(name = "orders")
public class Order extends PanacheEntityBase {

    @Id
    @Column(length = 36, nullable = false, updatable = false)
    public String id;

    @Column(name = "customer_id", nullable = false)
    public String customerId;

    @Column(name = "item_sku", nullable = false)
    public String itemSku;

    @Column(nullable = false)
    public int quantity;

    @Column(nullable = false, precision = 12, scale = 2)
    public BigDecimal amount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    public OrderStatus status;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    /**
     * No-arg constructor required by Hibernate/Panache.
     */
    public Order() {
    }

    /**
     * Factory for a newly placed order: assigns a fresh id, defaults status
     * to {@link OrderStatus#PLACED}, and stamps the creation time -- mirrors
     * the shape of {@code place_order} in the Python reference's
     * {@code app/main.py} before the row is persisted.
     */
    public static Order create(String customerId, String itemSku, int quantity, BigDecimal amount) {
        Order order = new Order();
        order.id = UUID.randomUUID().toString();
        order.customerId = customerId;
        order.itemSku = itemSku;
        order.quantity = quantity;
        order.amount = amount;
        order.status = OrderStatus.PLACED;
        order.createdAt = Instant.now();
        return order;
    }
}
