package com.patterncatalyst.datamesh.review;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Request body for {@code POST /reviews}. Kept separate from the {@link Review}
 * Panache entity (storage model) so the wire contract is decoupled from
 * persistence, mirroring the Python capstone's {@code ReviewCreate} Pydantic
 * schema.
 */
public record ReviewCreate(
        @NotBlank @Size(max = 64) String sku,
        @Min(1) @Max(5) int rating,
        @NotBlank @Size(max = 64) String reviewer,
        @Size(max = 2000) String comment) {
}
