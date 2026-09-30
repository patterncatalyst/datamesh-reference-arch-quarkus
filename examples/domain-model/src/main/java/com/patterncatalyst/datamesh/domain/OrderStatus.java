package com.patterncatalyst.datamesh.domain;

/**
 * Lifecycle states of an order aggregate, shared by every service that reads
 * or writes order state (order-service is the owner of record; other
 * services observe it via the {@code order.placed} / {@code payment.captured}
 * / {@code shipment.dispatched} events -- see {@link Topics}).
 */
public enum OrderStatus {
    PLACED,
    PAID,
    SHIPPED,
    CANCELLED
}
