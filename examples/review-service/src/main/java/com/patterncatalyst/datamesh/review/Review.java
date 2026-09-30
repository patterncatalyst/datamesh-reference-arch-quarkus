package com.patterncatalyst.datamesh.review;

import java.time.Instant;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;

/**
 * Panache active-record entity backing the review-service data product.
 *
 * Mirrors the Python capstone's {@code Review} SQLAlchemy model: a customer
 * review/rating of a product identified by {@code sku}. review-service owns
 * this table exclusively (per-service data ownership) -- no other module in
 * the reactor writes to it.
 */
@Entity
public class Review extends PanacheEntity {

    @Column(nullable = false)
    public String sku;

    /** 1..5, enforced at the REST boundary via Bean Validation on the request DTO. */
    @Column(nullable = false)
    public int rating;

    @Column(nullable = false)
    public String reviewer;

    @Column(length = 2000)
    public String comment;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;
}
