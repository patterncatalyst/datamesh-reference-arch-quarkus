package com.patterncatalyst.datamesh.review;

import java.time.Instant;
import java.util.List;

import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
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
 *   POST /reviews          -- create a review (400 on invalid rating)
 *   GET  /reviews           -- list reviews, optionally filtered by ?sku=
 *   GET  /reviews/{id}      -- fetch one review
 */
@Path("/reviews")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class ReviewResource {

    @POST
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

    @GET
    public List<ReviewResponse> list(@QueryParam("sku") String sku) {
        List<Review> reviews = (sku == null || sku.isBlank())
                ? Review.listAll()
                : Review.list("sku", sku);
        return reviews.stream().map(ReviewResponse::from).toList();
    }

    @GET
    @Path("/{id}")
    public Response getById(@PathParam("id") Long id) {
        Review review = Review.findById(id);
        if (review == null) {
            return Response.status(Status.NOT_FOUND).build();
        }
        return Response.ok(ReviewResponse.from(review)).build();
    }
}
