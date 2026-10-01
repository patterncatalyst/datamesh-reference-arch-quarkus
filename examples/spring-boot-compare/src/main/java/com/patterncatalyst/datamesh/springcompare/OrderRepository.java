package com.patterncatalyst.datamesh.springcompare;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Spring Data JPA twin of {@code Order.listAll(Sort.by("createdAt").descending())}
 * / {@code Order.findById(id)} in the Quarkus order-service.
 */
public interface OrderRepository extends JpaRepository<OrderEntity, String> {

    List<OrderEntity> findAllByOrderByCreatedAtDesc();
}
