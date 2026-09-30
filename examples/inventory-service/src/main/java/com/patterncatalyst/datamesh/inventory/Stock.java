package com.patterncatalyst.datamesh.inventory;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import io.quarkus.hibernate.orm.panache.PanacheEntity;

/**
 * Stock on hand for a single SKU. inventory-service is the sole owner and
 * writer of this table (CAP-003) -- it backs both the REST {@code /stock}
 * demo endpoints and the InventoryService/CheckStock gRPC call used by
 * order-service.
 */
@Entity
@Table(name = "stock", uniqueConstraints = @UniqueConstraint(columnNames = "sku"))
public class Stock extends PanacheEntity {

    @Column(name = "sku", nullable = false, unique = true, length = 64)
    public String sku;

    @Column(name = "quantity_on_hand", nullable = false)
    public int quantityOnHand;

    public Stock() {
    }

    public Stock(String sku, int quantityOnHand) {
        this.sku = sku;
        this.quantityOnHand = quantityOnHand;
    }

    /** Active Record finder: look up stock by its business key (sku). */
    public static Stock findBySku(String sku) {
        return find("sku", sku).firstResult();
    }
}
