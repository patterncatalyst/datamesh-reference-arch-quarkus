// make-quarkus-diagrams.js — the 4 Quarkus-specific diagrams with no Python
// equivalent (11-14), authored in the same visual grammar as svglib.js /
// makediagrams.js from datamesh-reference-arch-python so the whole diagram
// set stays visually uniform. Emits paired .svg + .excalidraw straight into
// assets/diagrams/.
const { SVG, FAM } = require("./svglib.js");
const fs = require("fs");
const path = require("path");

const OUT = path.join(__dirname, "..", "assets", "diagrams");
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

const save = (name, svg) => {
  fs.writeFileSync(path.join(OUT, `${name}.svg`), svg.render());
  fs.writeFileSync(path.join(OUT, `${name}.excalidraw`), svg.excalidraw());
  console.log("wrote", name, "(svg + excalidraw)");
};

/* ========== 11. QUARKUS CAPABILITY TOUR ========== */
(() => {
  const s = new SVG(1180, 630);
  s.title(
    "A Quarkus capability tour — ten capabilities, one JVM",
    "Each one demonstrated by a real endpoint or demo already running in this reactor"
  );

  const cards = [
    { name: "Panache", fam: "blue", desc: ["entity IS the repository", "(active record)"], anchor: "order-service — Order" },
    { name: "quarkus-grpc", fam: "green", desc: ["typed contract, generated", "from .proto at build time"], anchor: "inventory-service — CheckStock" },
    { name: "SmallRye GraphQL", fam: "orange", desc: ["one query composes", "REST + gRPC downstream"], anchor: "graphql-gateway — /graphql" },
    { name: "Reactive Messaging", fam: "red", desc: ["Avro events via Apicurio,", "not raw JSON"], anchor: "order-service — OrderEventProducer" },
    { name: "WebSockets.Next", fam: "tan", desc: ["pushes an already-", "committed event, no polling"], anchor: "notification-service — /ws/notifications" },
    { name: "Vert.x: reactive + imperative", fam: "blue", desc: ["Uni<> and classic JAX-RS,", "one reactor, same JVM"], anchor: "inventory-service — gRPC + REST" },
    { name: "Continuous testing + Dev Services", fam: "green", desc: ["tests re-run on save;", "Testcontainers auto-provisioned"], anchor: "order-service — mvn quarkus:dev" },
    { name: "Native compilation", fam: "orange", desc: ["ahead-of-time to a", "JVM-free binary"], anchor: "order-service — demo-native.sh" },
    { name: "OIDC", fam: "red", desc: ["Dev Services Keycloak,", "zero quarkus.oidc.* config"], anchor: "review-service — DELETE /reviews/{id}" },
    { name: "JBang", fam: "tan", desc: ["prototype a route with", "no pom.xml, no module"], anchor: "demos/jbang/HelloRoute.java" },
  ];

  const cols = 5, gap = 16, marginX = 40;
  const cw = (1180 - 2 * marginX - (cols - 1) * gap) / cols;
  const rowY = [112, 112 + 190 + 20];
  const ch = 190;

  cards.forEach((c, i) => {
    const row = Math.floor(i / cols), col = i % cols;
    const x = marginX + col * (cw + gap);
    const y = rowY[row];
    const f = FAM[c.fam];
    s.rect(x, y, cw, ch, c.fam);
    s.lines(x + 14, y + 26, [c.name], { size: 12.5, fill: f.head, weight: 700, lh: 15 });
    s.lines(x + 14, y + 60, c.desc, { size: 10.5, fill: "#3a3a3a", lh: 15 });
    s.text(x + 14, y + ch - 34, "ANCHORED TO", { size: 8.5, weight: 600, fill: "#8a7a5a" });
    s.lines(x + 14, y + ch - 16, [c.anchor], { size: 9.5, fill: f.head, weight: 700, lh: 13 });
  });

  s.plainRect(marginX, rowY[1] + ch + 20, 1180 - 2 * marginX, 46, "#151515", "#151515", { rx: 8 });
  s.text(590, rowY[1] + ch + 48, "ONE JVM — the Quarkus / Vert.x reactor underneath every capability above", {
    size: 13, anchor: "middle", weight: 700, fill: "#ffffff",
  });

  s.footer("Breadth, not a toy snippet: every box above is a real endpoint or route already running somewhere in this reactor.");
  save("11-capability-tour", s);
})();

/* ========== 12. QUARKUS VS SPRING BOOT ========== */
(() => {
  const s = new SVG(1180, 620);
  s.title(
    "Quarkus vs. Spring Boot — same surface, measured on the JVM",
    "order-service (Quarkus) vs. its spring-boot-compare twin — REST + Panache/JPA + Kafka/Avro + gRPC, identical on both sides"
  );

  const baseline = 470;
  const chartTop = 160;
  const chartH = baseline - chartTop; // 310px of vertical scale

  const QUARKUS = { fill: "#e8eef7", stroke: "#2c5aa0", head: "#1a3a6a" };
  const SPRING = { fill: "#f4f3f0", stroke: "#9a9a9a", head: "#4a4a4a" };

  const bar = (x, w, value, max, label, valueLabel, palette) => {
    const h = Math.round((value / max) * chartH);
    const y = baseline - h;
    s._rect(x, y, w, h, palette.fill, palette.stroke, { rx: 4, sw: 2 });
    s.text(x + w / 2, y - 12, valueLabel, { size: 13, anchor: "middle", weight: 700, fill: palette.head });
    s.lines(x + w / 2, baseline + 24, label, { size: 11, anchor: "middle", fill: "#3a3a3a", lh: 15 });
  };

  // panel 1: startup time
  s.text(295, 128, "STARTUP TIME (self-reported, seconds)", { size: 11, anchor: "middle", weight: 600, fill: "#8a7a5a" });
  bar(150, 110, 1.54, 3.21, ["order-service", "(Quarkus)"], "1.54 s", QUARKUS);
  bar(360, 110, 3.21, 3.21, ["spring-boot-compare", "(Spring Boot)"], "3.21 s", SPRING);

  // panel 2: resident memory
  s.text(880, 128, "RESIDENT MEMORY (RSS, MB)", { size: 11, anchor: "middle", weight: 600, fill: "#8a7a5a" });
  bar(735, 110, 314, 494, ["order-service", "(Quarkus)"], "314 MB", QUARKUS);
  bar(945, 110, 494, 494, ["spring-boot-compare", "(Spring Boot)"], "494 MB", SPRING);

  // baseline axis lines
  s.parts.push(`<line x1="90" y1="${baseline}" x2="520" y2="${baseline}" stroke="#9a9a9a" stroke-width="1.5"/>`);
  s.parts.push(`<line x1="670" y1="${baseline}" x2="1100" y2="${baseline}" stroke="#9a9a9a" stroke-width="1.5"/>`);

  // divider
  s.parts.push(`<line x1="595" y1="${chartTop - 20}" x2="595" y2="${baseline + 40}" stroke="#e0ddd4" stroke-width="1.5" stroke-dasharray="4 3"/>`);

  // callout band
  s.rect(90, 535, 1000, 48, "tan");
  s.text(110, 557, "On this run: Quarkus starts in roughly half the time and boots into roughly two-thirds the resident memory —", {
    size: 11, fill: "#5a3a0a", weight: 700,
  });
  s.text(110, 575, "same REST + Panache/JPA + Kafka/Avro + gRPC surface on both sides. JVM only — no native image either side (see chapter 11).", {
    size: 10.5, fill: "#3a3a3a",
  });

  s.footer("JVM, single-run, indicative — captured by scripts/compare-quarkus-springboot.sh on one developer machine, not a rigorous benchmark.");
  save("12-quarkus-vs-spring-boot", s);
})();

/* ========== 13. ORCHESTRATION STYLES (DRQ-015 headline) ========== */
(() => {
  const s = new SVG(1180, 760);
  s.title(
    "Orchestration styles — three engines, the same order/triage domain",
    "Kafka choreography has no coordinator; Camel and Quarkus Flow are both “orchestration”, but imperative vs. declarative"
  );

  const marginX = 40, gap = 20, cols = 3;
  const cw = (1180 - 2 * marginX - (cols - 1) * gap) / cols;
  const colX = [marginX, marginX + cw + gap, marginX + 2 * (cw + gap)];

  // column headers
  const headers = [
    { title: "KAFKA — CHOREOGRAPHY", fam: "red" },
    { title: "CAMEL — ORCHESTRATION", fam: "blue" },
    { title: "QUARKUS FLOW — ORCHESTRATION", fam: "green" },
  ];
  headers.forEach((h, i) => {
    s.rect(colX[i], 75, cw, 40, h.fam);
    s.text(colX[i] + cw / 2, 100, h.title, { size: 12.5, anchor: "middle", weight: 700, fill: FAM[h.fam].head });
  });

  // the visual point: coordinator or none
  const coordLabel = [
    { t: "NO COORDINATOR", fill: "#a8331f" },
    { t: "ONE COORDINATOR — the route", fill: "#1a3a6a" },
    { t: "ONE COORDINATOR — the workflow", fill: "#2a5a1a" },
  ];
  coordLabel.forEach((c, i) => {
    s.text(colX[i] + cw / 2, 135, c.t, { size: 12, anchor: "middle", weight: 700, fill: c.fill });
  });

  /* ---- Column 1: Kafka choreography ---- */
  (() => {
    const x = colX[0];
    const boxW = cw - 20, bx = x + 10;
    s.rect(bx, 158, boxW, 42, "white");
    s.text(bx + boxW / 2, 184, "order-service", { size: 12, anchor: "middle", weight: 700, fill: "#5a3a0a" });

    s.arrow(bx + boxW * 0.3, 200, bx + boxW * 0.18, 238, { color: "#c14a3a", marker: "arrR", w: 1.6 });
    s.arrow(bx + boxW * 0.7, 200, bx + boxW * 0.82, 238, { color: "#c14a3a", marker: "arrR", w: 1.6 });
    s.text(bx + boxW / 2, 218, "order.placed (Kafka)", { size: 9, anchor: "middle", italic: true, fill: "#666666" });

    const halfW = boxW / 2 - 8;
    s.rect(bx, 242, halfW, 44, "white");
    s.text(bx + halfW / 2, 265, "payment-service", { size: 10.5, anchor: "middle", weight: 700, fill: "#5a3a0a" });
    s.text(bx + halfW / 2, 280, "captures payment", { size: 9, anchor: "middle", fill: "#666666" });

    s.rect(bx + halfW + 16, 242, halfW, 44, "white");
    s.text(bx + halfW + 16 + halfW / 2, 265, "notification-service", { size: 10, anchor: "middle", weight: 700, fill: "#5a3a0a" });
    s.text(bx + halfW + 16 + halfW / 2, 280, "a 4th, parallel reaction", { size: 8.5, anchor: "middle", fill: "#666666" });

    s.arrow(bx + halfW / 2, 286, bx + boxW * 0.32, 324, { color: "#c14a3a", marker: "arrR", w: 1.6 });
    s.text(bx + boxW / 2, 306, "payment.captured", { size: 9, anchor: "middle", italic: true, fill: "#666666" });

    s.rect(bx, 328, boxW, 42, "white");
    s.text(bx + boxW / 2, 354, "shipping-service", { size: 12, anchor: "middle", weight: 700, fill: "#5a3a0a" });

    s.arrow(bx + boxW / 2, 370, bx + boxW / 2, 400, { color: "#c14a3a", marker: "arrR", w: 1.6 });
    s.pill(bx + boxW / 2 - 90, 402, 180, "shipment.dispatched", "red");

    s.lines(bx, 460, [
      "No service holds a reference to",
      "“the whole sequence.” Each only knows:",
      "when I see event X, do Y, emit Z.",
    ], { size: 10.5, fill: "#3a3a3a", lh: 16 });

    s.lines(bx, 530, [
      "Adding a 5th reaction (say, analytics)",
      "costs zero changes to order-service,",
      "payment-service, or shipping-service.",
    ], { size: 10.5, italic: true, fill: "#666666", lh: 16 });
  })();

  /* ---- Column 2: Camel orchestration ---- */
  (() => {
    const x = colX[1];
    const boxW = cw - 20, bx = x + 10;
    s.pill(bx + boxW / 2 - 110, 158, 220, "POST /api/orders/triage", "blue");

    s.rect(bx, 198, boxW, 300, "blue");
    s.text(bx + 16, 222, "OrderTriageRoute", { size: 13, weight: 700, fill: "#1a3a6a" });
    s.text(bx + 16, 240, "imperative — one file, top to bottom", { size: 9.5, italic: true, fill: "#666666" });

    const steps = ["unmarshal JSON → OrderCreate", "classify (TriageService, Ollama)", "decide (TriageService, Drools)", "marshal JSON → TriageDecision"];
    steps.forEach((t, i) => {
      const y = 256 + i * 56;
      s.plainRect(bx + 16, y, boxW - 32, 40, "#ffffff", "#2c5aa0", { rx: 6 });
      s.text(bx + boxW / 2, y + 25, t, { size: 10.5, anchor: "middle", weight: 700, fill: "#1a3a6a" });
      if (i < steps.length - 1) {
        s.arrow(bx + boxW / 2, y + 40, bx + boxW / 2, y + 56, { color: "#2c5aa0", marker: "arrB", w: 1.5 });
      }
    });

    s.lines(bx, 522, [
      "Reading the route top to bottom IS",
      "reading the business process. The",
      "route coordinates; Drools decides.",
    ], { size: 10.5, fill: "#3a3a3a", lh: 16 });
  })();

  /* ---- Column 3: Quarkus Flow orchestration ---- */
  (() => {
    const x = colX[2];
    const boxW = cw - 20, bx = x + 10;
    s.pill(bx + boxW / 2 - 125, 158, 250, "POST /api/orders/triage-flow", "green");

    s.rect(bx, 198, boxW, 240, "green");
    s.text(bx + 16, 222, "OrderTriageWorkflow", { size: 13, weight: 700, fill: "#2a5a1a" });
    s.text(bx + 16, 240, "declarative — a workflow document, not code", { size: 9.5, italic: true, fill: "#666666" });

    const taskW = (boxW - 32 - 30) / 2;
    s.plainRect(bx + 16, 262, taskW, 50, "#ffffff", "#5a8a3a", { rx: 6 });
    s.text(bx + 16 + taskW / 2, 292, "FlowDSL.function(", { size: 10, anchor: "middle", weight: 700, fill: "#2a5a1a" });
    s.text(bx + 16 + taskW / 2, 306, "\"classify\")", { size: 10, anchor: "middle", weight: 700, fill: "#2a5a1a" });

    s.arrow(bx + 16 + taskW + 5, 287, bx + 16 + taskW + 25, 287, { color: "#5a8a3a", marker: "arrG", w: 1.6 });

    s.plainRect(bx + 16 + taskW + 30, 262, taskW, 50, "#ffffff", "#5a8a3a", { rx: 6 });
    s.text(bx + 16 + taskW + 30 + taskW / 2, 292, "FlowDSL.function(", { size: 10, anchor: "middle", weight: 700, fill: "#2a5a1a" });
    s.text(bx + 16 + taskW + 30 + taskW / 2, 306, "\"decide\")", { size: 10, anchor: "middle", weight: 700, fill: "#2a5a1a" });

    s.lines(bx + 16, 332, [
      "default wiring: each task's input is",
      "the prior task's output",
    ], { size: 9.5, italic: true, fill: "#666666", lh: 14 });

    s.lines(bx + 16, 376, [
      "OrderTriageFlowRunner bridges back",
      "to REST: startInstance(order)",
      ".await().indefinitely()",
    ], { size: 10, fill: "#3a3a3a", lh: 15 });

    s.lines(bx, 460, [
      "Same TriageService.classify/decide",
      "calls as the Camel route — expressed",
      "as a task graph, not imperative code.",
    ], { size: 10.5, fill: "#3a3a3a", lh: 16 });

    s.lines(bx, 530, [
      "Edit the workflow document to add a",
      "task; inspectable/versionable apart",
      "from a Java release.",
    ], { size: 10.5, italic: true, fill: "#666666", lh: 16 });
  })();

  // bottom contrast band — pulled straight from the chapter's own table
  s.rect(marginX, 600, 1180 - 2 * marginX, 90, "tan");
  s.text(marginX + 20, 624, "WHO KNOWS THE WHOLE SEQUENCE?", { size: 10, weight: 600, fill: "#8a7a5a" });
  const whoKnows = [
    "No one — each service knows only its own reaction",
    "The route — read top to bottom",
    "The workflow document — read declaratively",
  ];
  whoKnows.forEach((t, i) => {
    s.lines(colX[i] + 10, 650, [t], { size: 10.5, fill: "#3a3a3a", lh: 15, anchor: "start" });
  });

  s.footer("The three legs share a domain and a comparison, not one literal order flowing end to end through all three — see the chapter's honest-limits section.");
  save("13-orchestration-styles", s);
})();

/* ========== 14. AI RULES TRIAGE: OLLAMA CLASSIFIES, DROOLS DECIDES ========== */
(() => {
  const s = new SVG(1180, 560);
  s.title(
    "AI-assisted triage — Ollama classifies, Drools decides",
    "One classify → decide core, driven two ways: a Camel route and a Quarkus Flow workflow"
  );

  // top pipeline row
  const boxW = 230, pipeY = 90, pipeH = 80;
  const px = [40, 330, 620, 910];

  s.rect(px[0], pipeY, boxW, pipeH, "tan");
  s.text(px[0] + boxW / 2, pipeY + 24, "Order", { size: 13, anchor: "middle", weight: 700, fill: "#5a3a0a" });
  s.lines(px[0] + 16, pipeY + 44, ["OrderCreate: customerId,", "itemSku, quantity, amount"], { size: 9.5, fill: "#3a3a3a", lh: 13 });

  s.rect(px[1], pipeY, boxW, pipeH, "blue");
  s.text(px[1] + boxW / 2, pipeY + 24, "Classify (Ollama)", { size: 12.5, anchor: "middle", weight: 700, fill: "#1a3a6a" });
  s.lines(px[1] + 16, pipeY + 44, ["langchain4j ChatModel.chat()", "qwen2.5:3b, JSON response mode"], { size: 9.5, fill: "#3a3a3a", lh: 13 });

  s.rect(px[2], pipeY, boxW, pipeH, "green");
  s.text(px[2] + boxW / 2, pipeY + 24, "Decide (Drools)", { size: 12.5, anchor: "middle", weight: 700, fill: "#2a5a1a" });
  s.lines(px[2] + 16, pipeY + 44, ["KieSession fires order-triage.drl", "FRAUD_HOLD / EXPEDITE / ROUTE_TO_WAREHOUSE"], { size: 9, fill: "#3a3a3a", lh: 13 });

  s.rect(px[3], pipeY, boxW, pipeH, "red");
  s.text(px[3] + boxW / 2, pipeY + 24, "TriageDecision", { size: 12.5, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.lines(px[3] + 16, pipeY + 44, ["decision + reason +", "classified fields"], { size: 9.5, fill: "#3a3a3a", lh: 13 });

  for (let i = 0; i < 3; i++) {
    const x1 = px[i] + boxW, x2 = px[i + 1];
    s.arrow(x1, pipeY + pipeH / 2, x2, pipeY + pipeH / 2, { color: "#5a5a5a", w: 1.8 });
  }

  // convergence label: same core called by both engines
  const convX = (px[1] + boxW / 2 + px[2] + boxW / 2) / 2;
  const convY = 250;
  s.pill(convX - 170, convY - 14, 340, "SAME TriageService.classify / .decide", "tan");
  s.arrow(px[1] + boxW / 2, pipeY + pipeH, convX - 100, convY - 14, { color: "#c19a6b", w: 1.4, dash: "4 3" });
  s.arrow(px[2] + boxW / 2, pipeY + pipeH, convX + 100, convY - 14, { color: "#c19a6b", w: 1.4, dash: "4 3" });

  // driver row
  const driverY = 320, driverH = 110;
  const driverW = 480;
  const dax = 70, dbx = 630;

  s.arrow(dax + driverW / 2, driverY, convX - 90, convY + 14, { color: "#c19a6b", w: 1.4, dash: "4 3" });
  s.arrow(dbx + driverW / 2, driverY, convX + 90, convY + 14, { color: "#c19a6b", w: 1.4, dash: "4 3" });

  s.rect(dax, driverY, driverW, driverH, "blue");
  s.text(dax + 16, driverY + 26, "Camel orchestration — OrderTriageRoute", { size: 12, weight: 700, fill: "#1a3a6a" });
  s.lines(dax + 16, driverY + 48, ["POST /api/orders/triage", "unmarshal → classify → decide → marshal (imperative)"], { size: 10.5, fill: "#3a3a3a", lh: 17 });

  s.rect(dbx, driverY, driverW, driverH, "green");
  s.text(dbx + 16, driverY + 26, "Quarkus Flow orchestration — OrderTriageWorkflow", { size: 12, weight: 700, fill: "#2a5a1a" });
  s.lines(dbx + 16, driverY + 48, ["POST /api/orders/triage-flow", "FlowDSL.function(classify), function(decide) (declarative)"], { size: 10.5, fill: "#3a3a3a", lh: 17 });

  // rules band
  s.rect(70, 460, 1040, 60, "white");
  s.text(90, 486, "ORDER-TRIAGE.DRL — three mutually exclusive, salience-ordered rules:", { size: 10.5, weight: 700, fill: "#5a3a0a" });
  s.text(90, 506, "FRAUD_HOLD (riskSignal == HIGH) · EXPEDITE (amount ≥ 1000 and riskSignal == LOW) · ROUTE_TO_WAREHOUSE (default)", { size: 10, fill: "#3a3a3a" });

  s.footer("The LLM's job ends at classification; from there the decision is a deterministic, auditable function of those fields — the model never decides.");
  save("14-ai-rules-triage", s);
})();

console.log("DONE");
