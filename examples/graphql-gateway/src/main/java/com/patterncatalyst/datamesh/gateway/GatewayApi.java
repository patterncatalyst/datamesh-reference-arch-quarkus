package com.patterncatalyst.datamesh.gateway;

import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.Query;
import org.eclipse.microprofile.graphql.Source;
import org.eclipse.microprofile.rest.client.inject.RestClient;

import capstone.inventory.v1.Inventory.CheckStockRequest;
import capstone.inventory.v1.Inventory.CheckStockResponse;
import capstone.inventory.v1.InventoryServiceGrpc;

import com.patterncatalyst.datamesh.domain.OrderDto;

import io.quarkus.grpc.GrpcClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.core.Response;

/**
 * The federating GraphQL API: {@code order(id)} resolves an order over REST
 * from order-service, and the nested {@code stock} field on that order
 * resolves over gRPC from inventory-service -- one client query, two
 * downstream protocols. Mirrors the Strawberry gateway in
 * datamesh-reference-arch-python's app/schema.py + app/clients.py.
 */
@GraphQLApi
@ApplicationScoped
public class GatewayApi {

    @RestClient
    OrderRestClient orderRestClient;

    @GrpcClient("inventory")
    InventoryServiceGrpc.InventoryServiceBlockingStub inventoryClient;

    @Query("order")
    public OrderView order(@Name("id") String id) {
        try (Response response = orderRestClient.getOrder(id)) {
            if (response.getStatus() == Response.Status.NOT_FOUND.getStatusCode()) {
                return null;
            }
            OrderDto dto = response.readEntity(OrderDto.class);
            return OrderView.from(dto);
        }
    }

    /**
     * Resolves the nested {@code stock} field on {@link OrderView} only when
     * a client actually asks for it (standard MicroProfile GraphQL
     * {@code @Source} behavior) -- the gRPC call is never made for queries
     * that don't select {@code stock}.
     */
    public StockView stock(@Source OrderView order) {
        CheckStockResponse response = inventoryClient.checkStock(CheckStockRequest.newBuilder()
                .setSku(order.itemSku())
                .setQuantity(order.quantity())
                .build());
        return new StockView(order.itemSku(), response.getQuantityOnHand(), response.getAvailable());
    }
}
