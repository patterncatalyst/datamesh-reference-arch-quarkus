package com.patterncatalyst.datamesh.review;

import java.time.Instant;
import java.util.List;

import jakarta.annotation.security.RolesAllowed;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.Response.Status;

/**
 * review-service's REST data product: product reviews/ratings.
 *
 * Mirrors the Python capstone's {@code review-service} FastAPI routes:
 *   POST   /reviews          -- create a review (400 on invalid rating)
 *   GET    /reviews           -- list reviews, optionally filtered by ?sku=
 *   GET    /reviews/{id}      -- fetch one review
 *   DELETE /reviews/{id}      -- admin-only moderation (OIDC demo):
 *                                 requires a bearer token with the "admin"
 *                                 role, so this one endpoint doubles as this
 *                                 reactor's live Quarkus OIDC + Keycloak Dev
 *                                 Service capability demo (see
 *                                 demos/demo-oidc.sh).
 */
@Path("/reviews")
@Produces(MediaType.APPLICATION_JSON)
public class ReviewResource {

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Transactional
    public Response create(@Valid ReviewCreate payload) {
        Review review = new Review();
        review.sku = payload.sku();
        review.rating = payload.rating();
        review.reviewer = payload.reviewer();
        review.comment = payload.comment();
        review.createdAt = Instant.now();
        review.persist();
        return Response.status(Status.CREATED).entity(ReviewResponse.from(review)).build();
    }

    // Explicit WILDCARD on this and the other bodyless methods below so
    // they aren't matched against the sibling POST method's
    // @Consumes(APPLICATION_JSON) -- without it, RESTEasy Reactive 415s any
    // request whose Content-Type isn't JSON (e.g. hey's default text/html)
    // even though these methods have no body to parse.
    @GET
    @Consumes(MediaType.WILDCARD)
    public List<ReviewResponse> list(@QueryParam("sku") String sku) {
        List<Review> reviews = (sku == null || sku.isBlank())
                ? Review.listAll()
                : Review.list("sku", sku);
        return reviews.stream().map(ReviewResponse::from).toList();
    }

    @GET
    @Path("/{id}")
    @Consumes(MediaType.WILDCARD)
    public Response getById(@PathParam("id") Long id) {
        Review review = Review.findById(id);
        if (review == null) {
            return Response.status(Status.NOT_FOUND).build();
        }
        return Response.ok(ReviewResponse.from(review)).build();
    }

    /**
     * Admin-only moderation: remove a review. Protected by OIDC bearer-token
     * RBAC -- requires a valid access token carrying the "admin" role (no
     * token -> 401; a token without "admin" -> 403). See the class Javadoc
     * and demos/demo-oidc.sh.
     */
    @DELETE
    @Path("/{id}")
    @Consumes(MediaType.WILDCARD)
    @Transactional
    @RolesAllowed("admin")
    public Response delete(@PathParam("id") Long id) {
        Review review = Review.findById(id);
        if (review == null) {
            return Response.status(Status.NOT_FOUND).build();
        }
        review.delete();
        return Response.noContent().build();
    }
}
