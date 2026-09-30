package com.patterncatalyst.datamesh.notification;

import java.util.List;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/**
 * Read-only view of the notifications persisted by {@link OrderPlacedConsumer}.
 */
@Path("/notifications")
@Produces(MediaType.APPLICATION_JSON)
public class NotificationResource {

    @GET
    public List<Notification> list() {
        return Notification.listAll();
    }
}
