package com.patterncatalyst.datamesh.domain;

/**
 * Framework-agnostic view of a customer review of a fulfilled order,
 * owned by review-service.
 */
public record ReviewDto(
        String reviewId,
        String orderId,
        String customerId,
        int rating,
        String comment,
        String createdAt) {
}
