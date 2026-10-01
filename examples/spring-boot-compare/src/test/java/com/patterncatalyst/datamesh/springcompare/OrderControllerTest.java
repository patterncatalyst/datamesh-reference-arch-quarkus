package com.patterncatalyst.datamesh.springcompare;

import static org.hamcrest.Matchers.equalTo;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.concurrent.CompletableFuture;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.kafka.support.SendResult;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * REST-level tests for {@link OrderController} -- the Spring Boot twin of
 * the Quarkus order-service's {@code OrderResourceTest}, asserting the
 * SAME JSON shape ({@code customerId}/{@code itemSku}/{@code status}) and
 * HTTP statuses (201/409/404/200) for parity.
 *
 * <p>{@link StockChecker} and {@link OrderEventProducer} are mocked so these
 * tests don't depend on a live inventory-service gRPC server or a live
 * Kafka/Apicurio broker; only Postgres is a real dependency, provided here
 * by Testcontainers via {@code @ServiceConnection} (postgres:18, matching
 * the Quarkus side's Dev Services image pin).
 *
 * <p>The real {@link GrpcStockChecker} path (a live gRPC round trip to
 * inventory-service) is intentionally NOT exercised here -- that would need
 * a running inventory-service or a stub gRPC server and is out of scope for
 * this module's own test suite. It would be covered by an integration test
 * standing up a plain grpc-java server implementing
 * {@code InventoryServiceGrpc.InventoryServiceImplBase}, the same way the
 * Quarkus side's {@code OrderPlacedAvroWireIT} self-provisions its own
 * Kafka/Apicurio pair rather than reusing application wiring.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
class OrderControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:18");

    @DynamicPropertySource
    static void overrideTimezone(DynamicPropertyRegistry registry) {
        // Same DRQ-011 crux as the Quarkus side: force UTC so the
        // Testcontainers Postgres instance doesn't reject the host's
        // default (possibly non-UTC) zone id.
        registry.add("spring.jpa.properties.hibernate.jdbc.time_zone", () -> "UTC");
    }

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private StockChecker stockChecker;

    @MockitoBean
    private OrderEventProducer eventProducer;

    @Test
    void placeOrder_persistsAndReturns201_whenStockAvailable() throws Exception {
        when(stockChecker.check("sku-1", 2)).thenReturn(new StockChecker.StockResult(true, 10));
        when(eventProducer.publish(org.mockito.ArgumentMatchers.any()))
                .thenReturn(CompletableFuture.completedFuture((SendResult<String, capstone.order.v1.OrderPlaced>) null));

        mockMvc.perform(post("/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customerId\":\"cust-1\",\"itemSku\":\"sku-1\",\"quantity\":2,\"amount\":19.99}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.customerId").value(equalTo("cust-1")))
                .andExpect(jsonPath("$.itemSku").value(equalTo("sku-1")))
                .andExpect(jsonPath("$.status").value(equalTo("PLACED")));
    }

    @Test
    void placeOrder_returns409_whenStockUnavailable() throws Exception {
        when(stockChecker.check("sku-2", 100)).thenReturn(new StockChecker.StockResult(false, 0));

        mockMvc.perform(post("/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customerId\":\"cust-2\",\"itemSku\":\"sku-2\",\"quantity\":100,\"amount\":5.00}"))
                .andExpect(status().isConflict());
    }

    @Test
    void getOrder_returns404_whenMissing() throws Exception {
        mockMvc.perform(get("/orders/does-not-exist"))
                .andExpect(status().isNotFound());
    }

    @Test
    void listOrders_returnsOk() throws Exception {
        mockMvc.perform(get("/orders"))
                .andExpect(status().isOk());
    }
}
