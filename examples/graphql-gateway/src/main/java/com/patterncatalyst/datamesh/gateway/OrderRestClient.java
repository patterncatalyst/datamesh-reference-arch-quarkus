package com.patterncatalyst.datamesh.gateway;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * REST client to order-service. Returns a raw {@link Response} rather than
 * an {@code OrderDto} directly so {@link GatewayApi} can distinguish a 404
 * (unknown order id, mapped to a {@code null} GraphQL result) from a
 * successful lookup without needing a {@code ResponseExceptionMapper}.
 *
 * <p>The base URL is supplied via the {@code order-service} config key (see
 * {@code quarkus.rest-client.order-service.url} in application.properties);
 * this interface is never re-pinned to a hard-coded host.
 */
@RegisterRestClient(configKey = "order-service")
@Path("/orders")
@Produces(MediaType.APPLICATION_JSON)
public interface OrderRestClient {

    @GET
    @Path("/{id}")
    Response getOrder(@PathParam("id") String id);
}
