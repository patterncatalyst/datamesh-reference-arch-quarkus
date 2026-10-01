package com.patterncatalyst.datamesh.notification;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;

import org.junit.jupiter.api.Test;

import capstone.order.v1.OrderPlaced;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;

/**
 * REST-level tests for {@link NotificationResource}. Dev Services provisions
 * the Postgres container automatically for @QuarkusTest.
 */
@QuarkusTest
class NotificationResourceTest {

    @Inject
    OrderPlacedConsumer consumer;

    @Test
    void list_returnsOk() {
        given()
                .when().get("/notifications")
                .then()
                .statusCode(200);
    }

    @Test
    void list_returnsPersistedNotification_afterConsume() {
        OrderPlaced event = OrderPlaced.newBuilder()
                .setEventType("order.placed")
                .setOrderId("order-notif-rest-1")
                .setCustomerId("customer-rest-1")
                .setItemSku("sku-rest-1")
                .setQuantity(2)
                .setAmount("9.99")
                .setStatus("PLACED")
                .setCreatedAt("2026-01-01T00:00:00Z")
                .build();

        // consumer.consume(...) is @Transactional on its own (see
        // OrderPlacedConsumer) and commits when it returns -- unlike
        // OrderPlacedConsumerTest's @TestTransaction-wrapped tests, this
        // write must actually be durable so the separate HTTP request below
        // (its own connection) can see it.
        consumer.consume(event);

        given()
                .when().get("/notifications")
                .then()
                .statusCode(200)
                .body("find { it.orderId == 'order-notif-rest-1' }.customerId", equalTo("customer-rest-1"))
                .body("find { it.orderId == 'order-notif-rest-1' }.itemSku", equalTo("sku-rest-1"));
    }
}
