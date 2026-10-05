---
part_name: Building data products
order: 1
title: Building data products
blurb: How a Quarkus service becomes a self-describing data product — its REST/gRPC surface, its versioned contract, and the planes it moves data across.
---

With the landscape and the substrate in place, this part builds the data product itself:
order-service as the template for what a data product looks like end to end, inventory
and review as further products that show the pattern varying by role, the versioned
Avro and Protobuf contracts that make a product's interface explicit, and the
synchronous and asynchronous planes — REST, gRPC, GraphQL, and Kafka — the services
move data across. By the end of this part there's a working mesh of services
that own their data as products; Part 2 picks up from there to operate it.
