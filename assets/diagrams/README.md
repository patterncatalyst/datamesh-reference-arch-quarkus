# assets/diagrams/

Each diagram lives as a **pair** of files with the same base name:

- `<name>.svg` — the rendered diagram, what appears on the site
- `<name>.excalidraw` — the editable JSON source

Some diagrams are hand-coded SVGs with no editable source — see
[Hand-coded SVGs](#hand-coded-svgs) below for the list in this repo.

## Naming convention

`<section-number>-<topic>-<thing>.svg` for tutorial diagrams.

Examples:

- `01-data-mesh-decentralized.svg`
- `04-capstone-contracts.svg`
- `07-hpa-vs-keda.svg`

This makes diagrams findable by section number and keeps related
diagrams sorted next to each other in the directory listing.

## Including a diagram in tutorial prose

Use the include:

```liquid
{% raw %}{% include excalidraw.html
   file="04-capstone-contracts"
   alt="Diagram showing data contracts flowing from producers through the registry to consumers"
   caption="Figure 4.1 — Data contracts and the registry" %}{% endraw %}
```

The include automatically:

- Renders the SVG inline (fast, accessible, scales with CSS)
- Adds an `alt` attribute for screen readers
- Adds the caption below the figure
- Includes a "Download Excalidraw source" link pointing at the
  matching `.excalidraw` file

## Generator scripts

Most figures are generated from JavaScript specs in `scripts/`. Edit the
spec and re-run the script; each run rewrites the `.svg` and
`.excalidraw` pair together. Run from the repository root:

```bash
node scripts/make-quarkus-diagrams.js      # 11-capability-tour, 12 through 21
node scripts/make-capability-diagrams.js   # 11-panache-patterns, 11-uni-vs-imperative,
                                           # 11-websockets-next, 11-jbang-tooling,
                                           # 11-startup-paths, 11-panama-ffm,
                                           # 11-oidc-token-flow
node scripts/make-appendix-diagrams.js     # 16-websocket-failover, 20-vertx-in-memory,
                                           # 20-kafka-messaging
```

The scripts share the palette and helpers in `scripts/svglib.js`. Do not
hand-edit a generated `.svg` or `.excalidraw`; the next run overwrites it.
Figures that are not listed here come from the earlier Python generator or
are hand-coded (see below).

## Editing a diagram

1. Open https://excalidraw.com
2. Drag the `<name>.excalidraw` file in
3. Edit
4. **Export → SVG** (NOT PNG) — overwrites `<name>.svg`
5. **File → Save to file** — overwrites `<name>.excalidraw`

Always update both files; they should stay in sync.

## Hand-coded SVGs

Sometimes a hand-coded SVG is faster than Excalidraw — especially
for grids, sequence diagrams, and anything heavy on math. You can
hand-code an SVG and ship a minimal `.excalidraw` source as
documentation, or omit the `.excalidraw` entirely and adjust the
`excalidraw.html` include to handle missing sources.

The following figures in this repo are hand-coded SVGs with no
`.excalidraw` source (edit the SVG directly):

- `02-principles-to-pieces.svg`
- `05-api-implementations.svg`
- `06-service-mesh.svg`
- `07-keda-lag.svg`
- `07-keda-http.svg`
- `08-three-signals.svg`
- `08-observability-stack.svg`
- `10-value-domain-ownership.svg`
- `10-value-data-product.svg`
- `10-value-self-serve.svg`
- `10-value-governance.svg`

## SVG sizing

Use `viewBox="0 0 W H"` without explicit `width` or `height`
attributes. The site CSS will scale the SVG responsively to fit
its container. Hard-coded pixel dimensions break responsive
rendering.
