package com.patterncatalyst.datamesh.inventory;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import capstone.inventory.v1.Inventory.CheckStockRequest;
import capstone.inventory.v1.Inventory.CheckStockResponse;
import capstone.inventory.v1.InventoryServiceGrpc;
import capstone.inventory.v1.InventoryServiceGrpc.InventoryServiceBlockingStub;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.quarkus.test.junit.QuarkusIntegrationTest;

/**
 * Exercises the PACKAGED inventory-service's real InventoryService/CheckStock
 * gRPC call on the wire (port 9000, see application.properties).
 *
 * <p>Unlike {@link InventoryGrpcServiceTest} (a {@code @QuarkusTest} using an
 * in-JVM, CDI-injected {@code @GrpcClient}), this is a
 * {@code @QuarkusIntegrationTest}: the application under test runs as a
 * separate packaged process (no CDI container in this test's own JVM), so the
 * client here is a plain {@code io.grpc} {@link ManagedChannel} + the generated
 * {@link InventoryServiceGrpc} blocking stub rather than a CDI-injected one.
 *
 * <p>IMPORTANT: this IT boots the packaged app under the {@code prod} profile,
 * where {@code import.sql} is NOT loaded (seed scripts
 * run only in dev/test schema generation). So this test SEEDS its own stock
 * over the REST surface ({@code POST /stock}) in {@code @BeforeAll} rather than
 * relying on the demo SKUs — a self-provisioning IT, consistent with how the
 * other wire-level ITs set up their own fixtures. The app's HTTP base URL is
 * taken from the {@code test.url} system property Quarkus sets for the launched
 * integration-test process.
 *
 * <p>Run by {@code maven-failsafe-plugin} under {@code mvn verify} (see the
 * execution bound in this module's {@code pom.xml}); {@code mvn test} only
 * compiles this class.
 */
@QuarkusIntegrationTest
class InventoryCheckStockWireIT {

    private static ManagedChannel channel;
    private static InventoryServiceBlockingStub stub;

    @BeforeAll
    static void setUp() throws Exception {
        // Seed stock over REST (import.sql does not run under the packaged
        // prod profile). The server derives available = quantityOnHand > 0.
        seedStock("WIDGET-1", 50);
        seedStock("WIDGET-2", 12);

        channel = ManagedChannelBuilder.forAddress("localhost", 9000)
                .usePlaintext()
                .build();
        stub = InventoryServiceGrpc.newBlockingStub(channel);
    }

    private static void seedStock(String sku, int quantityOnHand) throws Exception {
        String base = System.getProperty("test.url", "http://localhost:8081");
        String body = "{\"sku\":\"" + sku + "\",\"quantityOnHand\":" + quantityOnHand
                + ",\"available\":" + (quantityOnHand > 0) + "}";
        HttpResponse<String> response = HttpClient.newHttpClient().send(
                HttpRequest.newBuilder(URI.create(base + "/stock"))
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(body))
                        .build(),
                HttpResponse.BodyHandlers.ofString());
        assertEquals(200, response.statusCode(),
                "seeding " + sku + " via POST /stock should return 200, body=" + response.body());
    }

    @AfterAll
    static void stopChannel() throws InterruptedException {
        if (channel != null) {
            channel.shutdownNow().awaitTermination(5, TimeUnit.SECONDS);
        }
    }

    @Test
    void reportsAvailable_forSeededSkuWithEnoughStock() {
        CheckStockResponse response = stub.checkStock(CheckStockRequest.newBuilder()
                .setSku("WIDGET-1")
                .setQuantity(10)
                .build());

        assertTrue(response.getAvailable());
        assertEquals(50, response.getQuantityOnHand());
    }

    @Test
    void reportsInsufficient_forSeededSkuBelowRequestedQuantity() {
        CheckStockResponse response = stub.checkStock(CheckStockRequest.newBuilder()
                .setSku("WIDGET-2")
                .setQuantity(100)
                .build());

        assertFalse(response.getAvailable());
        assertEquals(12, response.getQuantityOnHand());
    }

    @Test
    void reportsUnavailable_forUnknownSku() {
        CheckStockResponse response = stub.checkStock(CheckStockRequest.newBuilder()
                .setSku("DOES-NOT-EXIST")
                .setQuantity(1)
                .build());

        assertFalse(response.getAvailable());
        assertEquals(0, response.getQuantityOnHand());
    }
}
