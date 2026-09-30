package com.patterncatalyst.datamesh.notification;

import java.math.BigDecimal;
import java.time.Instant;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;

/**
 * Persisted view of a consumed {@code order.placed} event, owned by
 * notification-service. One row per order (mirrors the Python reference's
 * {@code notifications} table) -- populated by {@link OrderPlacedConsumer}.
 *
 * <p>{@code order_id}, {@code status}, and {@code type} are avoided as plain
 * field names because they collide with SQL reserved words on some
 * databases (notably H2, used in tests); each is mapped to a safe column
 * name via {@code @Column}.
 */
@Entity
public class Notification extends PanacheEntity {

    @Column(name = "order_id", nullable = false, unique = true)
    public String orderId;

    @Column(name = "event_type", nullable = false)
    public String eventType;

    @Column(name = "customer_id")
    public String customerId;

    @Column(name = "item_sku")
    public String itemSku;

    @Column(name = "quantity")
    public Integer quantity;

    @Column(name = "amount")
    public BigDecimal amount;

    @Column(name = "status")
    public String status;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    public static Notification findByOrderId(String orderId) {
        return find("orderId", orderId).firstResult();
    }
}
