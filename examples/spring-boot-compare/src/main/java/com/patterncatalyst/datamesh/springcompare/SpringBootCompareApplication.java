package com.patterncatalyst.datamesh.springcompare;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point for the Spring Boot twin of the Quarkus order-service
 * (DRQ-006). See the module README for the build prerequisite
 * (domain-model/contracts must be `mvn install`ed first), run instructions,
 * and the chapter-12 comparison framing.
 */
@SpringBootApplication
public class SpringBootCompareApplication {

    public static void main(String[] args) {
        SpringApplication.run(SpringBootCompareApplication.class, args);
    }
}
