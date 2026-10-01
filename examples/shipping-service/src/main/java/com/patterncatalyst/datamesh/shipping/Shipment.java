package com.patterncatalyst.datamesh.shipping;

import java.time.Instant;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;

/**
 * Minimal, framework-owned (not shared) local record of a shipment dispatched
 * by {@link ShipmentProcessor}. This is intentionally lightweight -- a real
 * shipping service would own a richer aggregate -- but it demonstrates that
 * the choreography step also updates the service's own data product, not
 * just the outbound event.
 */
@Entity
public class Shipment extends PanacheEntity {

    @Column(name = "order_id")
    public String orderId;

    @Column(name = "customer_id")
    public String customerId;

    @Column(name = "item_sku")
    public String itemSku;

    public int quantity;
    public String carrier;

    @Column(name = "tracking_number")
    public String trackingNumber;

    public String status;

    @Column(name = "dispatched_at")
    public Instant dispatchedAt;
}
