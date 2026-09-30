package com.patterncatalyst.datamesh.review;

import java.time.Instant;

/**
 * Wire-level response shape for the review-service REST data product,
 * decoupled from the {@link Review} Panache entity (storage model) -- the
 * same separation the Python capstone keeps between its SQLAlchemy
 * {@code Review} model and its {@code ReviewResponse} Pydantic schema.
 *
 * NOTE: not the {@code ReviewDto} in {@code domain-model} -- that shared
 * record models an order-fulfillment review (orderId/customerId) and does
 * not match this data product's sku/reviewer shape, which mirrors the
 * Python review-service one-for-one.
 */
public record ReviewResponse(
        Long id,
        String sku,
        int rating,
        String reviewer,
        String comment,
        Instant createdAt) {

    static ReviewResponse from(Review review) {
        return new ReviewResponse(
                review.id,
                review.sku,
                review.rating,
                review.reviewer,
                review.comment,
                review.createdAt);
    }
}
