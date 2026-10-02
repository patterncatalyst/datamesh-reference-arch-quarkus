package com.patterncatalyst.datamesh.notification;

import java.math.BigDecimal;
import java.time.Instant;

import capstone.order.v1.OrderPlaced;
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
 *
 * <p>{@link #from(OrderPlaced)} is also used by {@link OrderPlacedPushConsumer}
 * to build a transient (never-persisted) view purely for the WebSocket push
 * -- see {@code _docs/16-websocket-scaling.md} for why persistence and push
 * are two independent Kafka consumers over the same {@code order.placed}
 * topic rather than one.
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

    /**
     * Maps an Avro {@code OrderPlaced} record onto a (not-yet-persisted)
     * {@link Notification}. Shared by {@link OrderPlacedConsumer} (which
     * persists the result) and {@link OrderPlacedPushConsumer} (which never
     * persists it -- it only exists long enough to push over a WebSocket),
     * so the field mapping lives in exactly one place.
     */
    public static Notification from(OrderPlaced event) {
        Notification notification = new Notification();
        notification.orderId = event.getOrderId();
        notification.eventType = event.getEventType();
        notification.customerId = event.getCustomerId();
        notification.itemSku = event.getItemSku();
        notification.quantity = event.getQuantity();
        notification.amount = parseAmount(event.getAmount());
        notification.status = event.getStatus();
        notification.createdAt = parseCreatedAt(event.getCreatedAt());
        return notification;
    }

    private static BigDecimal parseAmount(String amount) {
        return amount == null ? null : new BigDecimal(amount);
    }

    private static Instant parseCreatedAt(String createdAt) {
        return createdAt == null ? Instant.now() : Instant.parse(createdAt);
    }
}
