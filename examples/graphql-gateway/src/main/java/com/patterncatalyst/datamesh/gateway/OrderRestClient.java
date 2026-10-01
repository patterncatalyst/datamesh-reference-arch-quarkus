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
 * an {@code OrderDto} directly, but the modern reactive
 * {@code quarkus-rest-client} still applies its default exception handling
 * to any response with a status &gt;= 400, regardless of the declared return
 * type -- a 404 (or any other error status) throws
 * {@code jakarta.ws.rs.WebApplicationException} before {@link GatewayApi}
 * ever sees the {@link Response}. SmallRye GraphQL catches that exception
 * and surfaces it as a {@code null} {@code order} field plus a
 * {@code DataFetchingException} entry in the GraphQL response's
 * {@code errors} array.
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
