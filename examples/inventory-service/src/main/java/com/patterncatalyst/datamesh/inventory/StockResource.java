package com.patterncatalyst.datamesh.inventory;

import java.util.List;

import com.patterncatalyst.datamesh.domain.StockDto;

import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/**
 * REST demo surface for inventory-service: seed and inspect the {@code stock}
 * table backing the InventoryService/CheckStock gRPC call. Not part of the
 * cross-service contract (see {@code InventoryGrpcService} for that);
 * this is a convenience for demos/tests, mirroring the Python reference's
 * {@code GET /stock}.
 */
@Path("/stock")
@Produces(MediaType.APPLICATION_JSON)
public class StockResource {

    /** Seed (create or update) the quantity on hand for a SKU. */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Transactional
    public StockDto seed(StockDto request) {
        Stock stock = Stock.findBySku(request.sku());
        if (stock == null) {
            stock = new Stock(request.sku(), request.quantityOnHand());
            stock.persist();
        } else {
            stock.quantityOnHand = request.quantityOnHand();
        }
        return toDto(stock);
    }

    /**
     * List current stock levels for every known SKU.
     *
     * <p>Explicit WILDCARD so this bodyless GET isn't matched against the
     * sibling POST method's @Consumes(APPLICATION_JSON) -- without it,
     * RESTEasy Reactive 415s any request whose Content-Type isn't JSON
     * (e.g. hey's default text/html) even though GET has no body to parse.
     */
    @GET
    @Consumes(MediaType.WILDCARD)
    public List<StockDto> list() {
        return Stock.<Stock>listAll().stream().map(StockResource::toDto).toList();
    }

    /** Look up current stock for a single SKU. */
    @GET
    @Path("/{sku}")
    @Consumes(MediaType.WILDCARD)
    public StockDto get(@PathParam("sku") String sku) {
        Stock stock = Stock.findBySku(sku);
        if (stock == null) {
            throw new NotFoundException("No stock recorded for sku=" + sku);
        }
        return toDto(stock);
    }

    private static StockDto toDto(Stock stock) {
        return new StockDto(stock.sku, stock.quantityOnHand > 0, stock.quantityOnHand);
    }
}
