package com.patterncatalyst.datamesh.springcompare;

import java.time.format.DateTimeFormatter;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.patterncatalyst.datamesh.domain.OrderCreate;
import com.patterncatalyst.datamesh.domain.OrderDto;

import jakarta.validation.Valid;

/**
 * Order data product REST endpoints -- the Spring Boot twin of the Quarkus
 * order-service's {@code OrderResource} (DRQ-006). Same shapes/statuses:
 *
 * <ul>
 *   <li>{@code POST /orders} -- check inventory over gRPC ({@link StockChecker}),
 *       persist with status {@code PLACED} if available (409 otherwise, 503
 *       if inventory-service is unreachable), then publish
 *       {@code order.placed}.</li>
 *   <li>{@code GET /orders} -- list orders, most recent first.</li>
 *   <li>{@code GET /orders/{id}} -- fetch a single order (404 if absent).</li>
 * </ul>
 */
@RestController
@RequestMapping("/orders")
public class OrderController {

    private static final Logger LOG = LoggerFactory.getLogger(OrderController.class);

    private final OrderRepository orderRepository;
    private final StockChecker stockChecker;
    private final ApplicationEventPublisher eventPublisher;

    public OrderController(OrderRepository orderRepository, StockChecker stockChecker,
            ApplicationEventPublisher eventPublisher) {
        this.orderRepository = orderRepository;
        this.stockChecker = stockChecker;
        this.eventPublisher = eventPublisher;
    }

    @PostMapping
    @Transactional
    public ResponseEntity<?> placeOrder(@Valid @RequestBody OrderCreate payload) {
        StockChecker.StockResult stock;
        try {
            stock = stockChecker.check(payload.itemSku(), payload.quantity());
        } catch (StockChecker.StockCheckUnavailableException e) {
            // Fail closed: never place an order we couldn't validate against
            // inventory (mirrors the Quarkus side's StatusRuntimeException case).
            LOG.warn("inventory-service unreachable: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(e.getMessage());
        }

        if (!stock.available()) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body("insufficient stock for %s (%d on hand)"
                            .formatted(payload.itemSku(), stock.quantityOnHand()));
        }

        OrderEntity order = OrderEntity.create(payload.customerId(), payload.itemSku(), payload.quantity(),
                payload.amount());
        orderRepository.save(order);

        // Publish an application event rather than calling OrderEventProducer
        // directly here. OrderEventProducer listens with
        // @TransactionalEventListener(phase = AFTER_COMMIT), so the actual
        // Kafka publish only runs once this method's transaction has
        // committed -- the order is genuinely durable by the time anyone
        // downstream sees order.placed. A publish failure must not fail
        // this (already-committed) order; see OrderEventProducer. The
        // dual-write gap this leaves (commit succeeds, process crashes
        // before the listener runs) is the transactional outbox pattern's
        // job in production, not this example.
        eventPublisher.publishEvent(order);

        return ResponseEntity.status(HttpStatus.CREATED).body(toDto(order));
    }

    @GetMapping
    public List<OrderDto> listOrders() {
        return orderRepository.findAllByOrderByCreatedAtDesc()
                .stream()
                .map(OrderController::toDto)
                .toList();
    }

    @GetMapping("/{id}")
    public ResponseEntity<OrderDto> getOrder(@PathVariable String id) {
        return orderRepository.findById(id)
                .map(order -> ResponseEntity.ok(toDto(order)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    private static OrderDto toDto(OrderEntity order) {
        return new OrderDto(
                order.getId(),
                order.getCustomerId(),
                order.getItemSku(),
                order.getQuantity(),
                order.getAmount(),
                order.getStatus(),
                DateTimeFormatter.ISO_INSTANT.format(order.getCreatedAt()));
    }
}
