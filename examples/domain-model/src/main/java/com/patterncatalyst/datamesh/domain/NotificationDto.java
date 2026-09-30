package com.patterncatalyst.datamesh.domain;

/**
 * Framework-agnostic view of a customer notification, owned by
 * notification-service and triggered by the order/payment/shipping event
 * flow (see {@link Topics}).
 */
public record NotificationDto(
        String notificationId,
        String customerId,
        String channel,
        String subject,
        String body,
        String createdAt) {
}
