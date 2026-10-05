---
title: "Data architectures — from pipelines to mesh"
order: 1
part: Foundations
description: "The landscape: data pipelines, data warehouses, data lakes, and data mesh — what each pattern is, the problem it solves, and why the mesh is a different kind of answer."
duration: "20 min"
marker: "01"
---

Data mesh responds to organizational scaling problems that earlier data architectures
left unsolved, so the landscape comes first. Each earlier pattern solved a real problem
and remains the right answer when that problem dominates. Knowing what each does well
makes the mesh's value proposition concrete. Figure 1.5, at the end of this chapter,
lays the progression out side by side.

## Data pipelines

The oldest problem in data architecture is movement: operational systems produce data,
analytical systems consume it, and something has to get it from one place to the other.
That something is a **data pipeline** — a sequence of steps that extracts data from a
source, transforms it into a shape the destination can use, and loads it into the target
store. Figure 1.1 shows the shape of this: a known source, a transformation step, and a
known destination, repeated once per source-destination pair.

{% include excalidraw.html file="01-data-pipeline-architecture" alt="A linear ETL/ELT data pipeline moving data from an operational source through a transformation step into an analytical destination" caption="Figure 1.1 — Data pipeline architecture" %}

The two canonical patterns are **ETL** (extract-transform-load), where
transformation happens in transit before the data lands, and **ELT**
(extract-load-transform), where raw data is landed first and transformed in place
afterward. The distinction matters for latency, cost, and where you locate your business
logic, but both are pipelines: linear flows from a known source to a known destination,
processing data in batches on a schedule or streaming it in near-real-time.

Pipelines are point-to-point by nature. Each one knows its source, its destination, and
its transformations. When you have a handful of operational databases feeding one
analytical warehouse, that directness is a virtue — the flow is legible, the ownership is
clear, and debugging means following a straight line. The trouble starts when the number
of sources and destinations grows. Each new source-destination pair typically requires
its own pipeline, and the total count grows as the product of sources and destinations,
not the sum. A company with fifteen operational systems feeding five analytical
consumers doesn't have twenty pipelines — it has something closer to seventy-five, each
with its own schedule, its own transformation logic, and its own failure modes.

This is **pipeline sprawl**, and it's the defining limitation of the pattern. Nobody
"owns" the data flowing through a pipeline — the pipeline is plumbing, not a product.
When a pipeline breaks, there is rarely a clear answer to whose problem it is: the data
team owns the pipeline, but the domain team owns the semantics, and neither has full
context. It was exactly this sprawl — and the
operational fragility that comes with it — that the data warehouse was designed to tame.

## Data warehouses

A **data warehouse** is a centralized analytical store, purpose-built for structured
queries across the entire business. Figure 1.2 shows the shape that replaces the
pipeline tangle: many sources converging on one governed, centrally-owned store.

{% include excalidraw.html file="01-data-warehouse-architecture" alt="Multiple operational sources feeding a centralized, schema-on-write data warehouse owned by a central team" caption="Figure 1.2 — Data warehouse architecture" %}

Where pipelines are plumbing, the warehouse is a
destination — a single place where data from every operational system arrives, gets
cleaned, modeled into a consistent schema, and becomes queryable by anyone with the right
access. The intellectual heritage runs through Kimball's dimensional modeling and Inmon's
enterprise data warehouse: **star schemas**, **fact tables** and **dimension tables**,
all optimized for the kind of aggregations and joins that business intelligence tools
need.

The warehouse's defining characteristic is **schema-on-write**. Data is modeled and
validated before it's stored. That rigidity is a feature: it forces consistency, makes
the warehouse a governed single source of truth, and ensures that when two teams query
"total revenue last quarter," they get the same number. The warehouse solved the truth
problem that pipeline sprawl created — instead of every consumer building its own
understanding of the data from raw pipeline output, everyone queries the same curated
model.

The limitation is organizational, not technical. The warehouse is owned by a central data
team — sometimes called the BI team, the analytics engineering team, or the data
platform team — and that team becomes a bottleneck in direct proportion to the
organization's growth. The central team owns all the data but understands none of the
domains that produced it. When the logistics domain needs a new dimension added to the
warehouse, the request goes to the central team, who must learn enough about logistics
to model it correctly, prioritize it against requests from every other domain, and
coordinate the schema change without breaking downstream consumers. The analytical view
is also typically hours or days behind the operational truth, since the ingestion
pipelines run on a schedule.

## Data lakes

The **data lake** emerged as a response to the warehouse's format rigidity. Figure 1.3
shows the zone structure a well-run lake organizes itself into — raw, curated, and
refined — still centralized, but no longer demanding a schema up front.

{% include excalidraw.html file="01-data-lake-architecture" alt="A data lake organized into raw, curated, and refined zones, accepting structured, semi-structured, and unstructured data" caption="Figure 1.3 — Data lake architecture" %}

Where a
warehouse demands that data conform to a schema before it can be stored, a data lake
accepts data in any format — structured tables, semi-structured JSON and XML,
unstructured logs and text, binary blobs like images and sensor readings — and defers
schema decisions to the point of consumption. This is **schema-on-read**: the data lands
as-is, and the consumer applies a schema when querying it.

A well-run lake is organized into zones that reflect the data's maturity. The **raw
zone** (sometimes called the landing zone) holds data exactly as it arrived from the
source systems — untouched, append-only, the system of record. The **curated zone**
holds data that has been cleaned, validated, deduplicated, and enriched — still in its
original grain, but trustworthy. The **refined zone** holds data that has been modeled
and aggregated for specific consumption patterns — analytics, dashboards, ML feature
stores. The progression from raw to curated to refined represents increasing levels of
transformation and decreasing levels of generality.

The lake solved the warehouse's most visible problem: format inflexibility. The
warehouse can't easily accommodate a Kafka topic full of JSON events, a directory of
Parquet files from a data science experiment, or a bucket of images for a computer
vision model. The lake can. At massive scale and with cheap object storage, the lake
makes it economically feasible to keep *everything* and decide later what's worth
querying. That flexibility unlocked workloads — machine learning, unstructured
analytics, exploratory data science — that warehouses were never built for.

The limitation is governance. Without active curation, the lake becomes the **data
swamp** — a term so common in the field that it's practically a synonym for a poorly-run
lake. Undocumented datasets accumulate. Nobody knows which version of the customer table
is authoritative, which datasets are stale, which ones duplicate each other under
different names. The curation effort needed to keep a lake useful re-creates much of the
warehouse's modeling and governance work, just without the warehouse's enforcement
mechanisms. The organizational problem is unchanged: a central team
still owns the lake, still cannot understand every domain's data, and still bottlenecks
on the same requests. The technology changed — from rigid schema to flexible storage —
but the shape of the organization did not.

## How data mesh differs

All three patterns — pipelines, warehouses, lakes — centralize data and hand ownership
to a single team. The technology improves with each generation: from bespoke
point-to-point plumbing, to a governed analytical store, to a flexible format-agnostic
lake. But the organizational shape stays the same in every case: one team at the center,
receiving requests from every domain, owning data it did not produce, modeling concepts
it does not deeply understand, and scaling its capacity linearly while the demands on it
grow combinatorially.

The **data mesh** proposes a different axis of change. Figure 1.4 shows that
decentralization directly against the three centralized shapes above: instead of one
box in the middle, each domain owns its own data product, connected by a shared
platform rather than funneled through a single team.

{% include excalidraw.html file="01-data-mesh-decentralized" alt="Multiple domain teams each owning a data product, connected by a shared self-serve platform instead of a central team" caption="Figure 1.4 — Data mesh: decentralized domain ownership" %}

Instead of building a better
center, it decentralizes ownership to the domain teams that produce the data. Each
domain owns its data as a product — discoverable, addressable, trustworthy,
self-describing — and publishes it for other domains to consume. A shared **self-serve
data platform** provides the infrastructure that every domain needs (streaming, storage,
observability, schema registries) so that domain teams don't each build their own. And
**federated computational governance** keeps the independently-owned products
interoperable — not through review boards and policy documents, but through standards
enforced automatically by the platform itself.

The mesh changes the organizational shape, not just the technology. A domain team that understands its own data curates it, models it,
documents it, and stands behind it the way a product team stands behind a product. The
central team's role shifts from owning every dataset to providing the platform and
enforcing the standards, a different scaling model.

The mesh does not replace warehouses or lakes. A
domain may still use a warehouse or a lake internally — the order-analytics domain
might store its refined data in a Parquet-based lakehouse. The reorganization is about *who owns the data*, not about which storage technology to use.
The mesh is an answer to the question "how does this organization scale its data
architecture?" — not "which database should this team pick?"

The mesh pays off in organizations with many domains, many data consumers,
and the operational maturity to sustain federated ownership. For smaller teams, simpler
data flows, or organizations where the central team is not yet the bottleneck, a
well-run warehouse or a governed lake may be exactly the right answer. The mesh is not
the next step in a linear progression; it addresses a different problem.

## The evolution — and when each pattern fits

Figure 1.5 lays the four patterns out in one sequence, from the earliest, most
point-to-point pattern to the most decentralized — the progression the rest of this
section walks through in terms of the problem each one solved.

{% include excalidraw.html file="01-architecture-evolution" alt="Timeline showing the progression from data pipelines to data warehouses to data lakes to data mesh, with the problem each pattern solved" caption="Figure 1.5 — The evolution from pipelines to mesh" %}

The progression from pipelines to warehouses to lakes to mesh is not a replacement chain
where each generation obsoletes the last. It's an expansion of the problem space.
Pipelines solved the **movement problem** — getting data from where it's produced to
where it's consumed. Warehouses solved the **truth problem** — creating a single
governed view of the business from the chaos of independent pipelines. Lakes solved the
**flexibility problem** — accommodating the formats and workloads that warehouses were
too rigid to handle. The mesh solves the **organizational scaling problem** —
restructuring ownership so that the central team is no longer the bottleneck on every
domain's data needs.

Each pattern is still valid when its problem is the dominant one. The choice depends on
the organization's scale, its data landscape, and where the bottleneck sits:

- **Pipelines** are the right answer when you have a small number of well-understood
  integrations, the data flows are stable, and there is no pressing need for
  centralized cross-domain analytics. The plumbing is simple enough that the sprawl
  hasn't started.

- **A data warehouse** fits when the organization needs a reliable, governed analytical
  view of the business — BI dashboards, executive reporting, structured
  decision-making — and a central team has the capacity to curate and model the data.
  The bottleneck is not yet the central team's bandwidth but the absence of a single
  source of truth.

- **A data lake** fits when the data is heterogeneous — logs, events, unstructured
  content, ML training sets — and the scale or the workload patterns (exploratory
  analysis, feature engineering, large-scale batch processing) exceed what a warehouse
  handles well. The bottleneck is format rigidity, not organizational ownership.

- **A data mesh** fits when the organization has many domains, many data consumers, and
  the central team has become the constraint. The bottleneck is organizational — who
  owns what, who can ship what, who understands what — not technical. The organization
  needs the maturity to operate federated ownership: domain teams that can treat data as
  a product, a platform team that can provide self-serve infrastructure, and a
  governance model that works through automation rather than approvals.

With this landscape in place, the next chapter defines data mesh precisely — what
Dehghani's four principles are, how they interlock, and why implementing one without the
others produces a distributed mess rather than a mesh.

[Concepts & principles]({{ '/docs/01-concepts/' | relative_url }}).

---

*Status: <span class="status status--conceptual">conceptual</span>. This
chapter is stack-agnostic conceptual framing with no code or commands to run; the
main item to confirm is that the terminology here (pipeline sprawl, schema-on-write
vs. schema-on-read, data swamp) stays consistent with how later, hands-on chapters use the
same terms once they're written.*
