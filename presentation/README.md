# Presentation decks

Two decks for the "Building a Datamesh using Quarkus and Kubernetes" talk,
built with [pptxgenjs](https://gitbrent.github.io/PptxGenJS/) (same format as the
sibling `datamesh-reference-arch-python` decks):

| Deck | Dir | Audience / use |
|------|-----|----------------|
| **101** | `datamesh-101/` | Concept-forward overview for Quarkus developers — data-architecture landscape, the four principles, Quarkus/Kubernetes teaser. ~17 slides. |
| **201** | `datamesh-201/` | Deep-dive with **live demos** and a large **appendix** — capability tour, the three orchestration engines, AI+rules triage, Quarkus-vs-Spring-Boot (JVM), platform/observability. ~89 slides. |

## Build

Each deck dir is self-contained. From a deck dir:

```bash
npm install            # pptxgenjs + sharp
node raster.js         # SVG -> dpng/*.png (+ dims.json), reads ../../assets/diagrams/*.svg
node build-101.js      # (101)  -> Datamesh_101-r1.0.pptx
node build-deck.js     # (201)  -> Datamesh-201-Quarkus-r1.0.pptx
```

`raster.js` must run before the builder (the builder reads `dpng/dims.json`). The
`.pptx` files are committed as deliverables; `node_modules/` and `dpng/` are
generated (gitignored).

## Diagrams

Both decks reuse the paired SVG+Excalidraw diagrams in `../../assets/diagrams/`
(see that dir's README). Diagrams are referenced by basename in `diagramSlide({ image: "NN-name" })`.

## Branding

Red Hat house style, inherited from `deck-lib.js` (palette, Overpass / Red Hat
Text / Red Hat Mono fonts, logo + speaker notes on every slide). Fonts render
correctly on a machine with the Red Hat typefaces installed; LibreOffice
substitutes Calibri otherwise.
