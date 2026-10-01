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

// greedy word-wrap to <= n chars per line, for grid/table cells
const wrap = (t, n) => {
  const words = String(t).split(" ");
  const out = [];
  let line = "";
  for (const w of words) {
    if ((line + " " + w).trim().length > n) { if (line) out.push(line); line = w; }
    else line = line ? line + " " + w : w;
  }
  if (line) out.push(line);
  return out;
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

/* ========== 15. AGENTIC RELAY: PLAN (OPUS) -> EXECUTE (SONNET, FAN-OUT) -> VALIDATE (OPUS) ========== */
(() => {
  const s = new SVG(1180, 700);
  s.title(
    "The agentic relay — Plan (Opus) → Execute (Sonnet, fan-out) → Validate (Opus)",
    "A subagent's report is a claim, not evidence — validation reads the real diff and runs the real build, independent of the executor's own summary"
  );

  const marginX = 40;

  // PLAN
  const planW = 230, planX = marginX, planY = 90, planH = 90;
  s.rect(planX, planY, planW, planH, "blue");
  s.text(planX + planW / 2, planY + 26, "PLAN — Opus", { size: 13, anchor: "middle", weight: 700, fill: "#1a3a6a" });
  s.lines(planX + 16, planY + 48, ["approach + steps +", "checkable acceptance criteria"], { size: 10, fill: "#3a3a3a", lh: 15 });

  // human gate
  const gateX = planX + planW + 30, gateW = 150;
  s.arrow(planX + planW, planY + planH / 2, gateX, planY + planH / 2, { color: "#2c5aa0", marker: "arrB", w: 1.8 });
  s.plainRect(gateX, planY + 10, gateW, planH - 20, "#ffffff", "#5a3a0a", { rx: 6, dash: "5 3" });
  s.text(gateX + gateW / 2, planY + 34, "HUMAN GATE", { size: 10.5, anchor: "middle", weight: 700, fill: "#5a3a0a" });
  s.lines(gateX + 14, planY + 54, ["approve the plan", "before code is written"], { size: 9, fill: "#5a3a0a", lh: 13 });

  // EXECUTE fan-out — N file-disjoint executors
  const execLabelX = gateX + gateW + 30;
  s.arrow(gateX + gateW, planY + planH / 2, execLabelX, planY + planH / 2, { color: "#5a3a0a", marker: "arr", w: 1.8 });

  const execColX = execLabelX, execColW = 330;
  s.text(execColX + execColW / 2, 70, "EXECUTE — Sonnet, one agent per file-disjoint step", { size: 12, anchor: "middle", weight: 700, fill: "#2a5a1a" });

  const execRows = [
    "order-service",
    "inventory-service + review-service",
    "payment-service",
    "shipping-service",
    "notification-service",
    "graphql-gateway",
    "ai-mcp-service",
  ];
  const execTop = 92, execH = 36, execGap = 8;
  execRows.forEach((name, i) => {
    const y = execTop + i * (execH + execGap);
    s.plainRect(execColX, y, execColW, execH, "#ffffff", "#5a8a3a", { rx: 6 });
    s.text(execColX + 14, y + 23, name, { size: 10.5, fill: "#2a5a1a", weight: 700 });
    s.text(execColX + execColW - 14, y + 23, "checkpoint commit", { size: 8.5, anchor: "end", italic: true, fill: "#666666" });
  });

  // converge into validate
  const valX = execColX + execColW + 60, valW = 230, valY = 90, valH = 90;
  execRows.forEach((_, i) => {
    const y = execTop + i * (execH + execGap) + execH / 2;
    s.arrow(execColX + execColW, y, valX, valY + valH / 2, { color: "#5a8a3a", marker: "arrG", w: 1.3 });
  });

  s.rect(valX, valY, valW, valH, "red");
  s.text(valX + valW / 2, valY + 26, "VALIDATE — Opus", { size: 13, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.lines(valX + 16, valY + 48, ["reads the real diff, runs the", "real build — not the report"], { size: 10, fill: "#3a3a3a", lh: 15 });

  // repair loop feedback edge (capped at 2)
  const repairY = valY + valH + 40;
  s.parts.push(`<path d="M ${valX + valW / 2} ${valY + valH} C ${valX + valW / 2} ${repairY + 20}, ${execColX + execColW / 2} ${repairY + 20}, ${execColX + execColW / 2} ${execTop + execRows.length * (execH + execGap)}" fill="none" stroke="#c14a3a" stroke-width="1.6" stroke-dasharray="5 3" marker-end="url(#arrR)"/>`);
  s.text((valX + execColX + execColW) / 2, repairY + 36, "repair round (capped at 2) — a 3rd failure means the PLAN was wrong", {
    size: 10, anchor: "middle", italic: true, fill: "#a8331f", weight: 700,
  });

  // PR rail across the bottom
  const railY = 560, railH = 54;
  s.rect(marginX, railY, 1180 - 2 * marginX, railH, "tan");
  s.text(marginX + 20, railY + 23, "EVERY PHASE RIDES THE SAME RAIL:", { size: 9.5, weight: 700, fill: "#8a7a5a" });
  s.text(marginX + 20, railY + 41, "branch → checkpoint commits → PR → squash-merge to main  (this build: 14 PRs, #1–#14, Phases A–E)", {
    size: 11, fill: "#5a3a0a", weight: 700,
  });

  // caption row: the thesis
  s.plainRect(marginX, 632, 1180 - 2 * marginX, 46, "#151515", "#151515", { rx: 8 });
  s.text(590, 660, "A subagent's report is a claim, not evidence — the method's value is the independent verification, not the first draft", {
    size: 12.5, anchor: "middle", weight: 700, fill: "#ffffff",
  });

  s.footer("Subagents don't inherit skills or model tier — every executor prompt restates conventions; every nested Agent call states its model explicitly.");
  save("15-agentic-relay", s);
})();

/* ========== 16. SCALING WEBSOCKETS WITH KAFKA ========== */
(() => {
  const s = new SVG(1180, 660);
  s.title(
    "Scaling WebSocket push across replicas — Kafka as the fan-out bus",
    "A socket pins a client to one replica; every replica must still see every event"
  );

  const marginX = 40;
  const busX = 340, busW = 500, busY = 80, busH = 54;
  s.rect(busX, busY, busW, busH, "red");
  s.text(busX + busW / 2, busY + 24, "orders topic (Kafka)", { size: 13, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.text(busX + busW / 2, busY + 42, "unique group.id per replica = broadcast (NOT a shared load-balanced group)", { size: 10, anchor: "middle", italic: true, fill: "#7a3a2a" });

  const cols = 3, gap = 40, repW = (1180 - 2 * marginX - (cols - 1) * gap) / cols;
  const repY = 220, repH = 190;
  for (let i = 0; i < cols; i++) {
    const x = marginX + i * (repW + gap);
    s.rect(x, repY, repW, repH, "green");
    s.text(x + 16, repY + 26, `notification-service · replica ${i + 1}`, { size: 12, fill: "#2a5a1a", weight: 700 });
    s.lines(x + 16, repY + 50, ["local OpenConnections registry", "(this replica's sockets only)"], { size: 10.5, fill: "#3a3a3a", lh: 15 });
    const cy = repY + 96, pw = (repW - 48) / 2;
    s.pill(x + 16, cy, pw, "client", "white");
    s.pill(x + 16 + pw + 16, cy, pw, "client", "white");
    s.pill(x + 16, cy + 36, pw, "client", "white");
    s.arrow(busX + busW / 2, busY + busH, x + repW / 2, repY, { marker: "arrG", w: 1.4 });
    s.text(x + 16, repY + repH - 8, "push only to local sockets", { size: 9, italic: true, fill: "#5a8a3a" });
  }

  const kX = marginX, kY = 450, kW = 1180 - 2 * marginX;
  s.rect(kX, kY, kW, 56, "tan");
  s.text(kX + 16, kY + 23, "KEDA scales on consumer lag (minReplicaCount: 0)", { size: 11, weight: 700, fill: "#5a3a0a" });
  s.text(kX + 16, kY + 43, "a replica holding live sockets but zero lag can scale to zero and drop clients — use a connection-aware trigger, graceful drain, or minReplicaCount: 1 (not implemented here).", { size: 10, fill: "#5a3a0a" });

  s.plainRect(marginX, 530, 1180 - 2 * marginX, 46, "#151515", "#151515", { rx: 8 });
  s.text(590, 558, "Kafka is the fan-out bus — any instance can serve any client; no distributed connection registry needed", { size: 12.5, anchor: "middle", weight: 700, fill: "#ffffff" });

  s.footer("What the repo runs today is single-instance; the per-replica broadcast fan-out above is the recommended scaled pattern, not deployed.");
  save("16-websocket-scaling", s);
})();

/* ========== 17. GOTCHAS ========== */
(() => {
  const s = new SVG(1180, 700);
  s.title(
    "Gotchas — symptoms and the fixes that actually landed",
    "Each one cost real debugging time while building this reactor"
  );
  const items = [
    { fam: "red", h: "postgres:18 TimeZone", sym: "'invalid value for parameter TimeZone'", fix: "-Duser.timezone=UTC + TZ/PGTZ=UTC" },
    { fam: "orange", h: "Avro ClassSecurityValidator", sym: "deserialization blocked (Avro 1.12)", fix: "org.apache.avro.SERIALIZABLE_PACKAGES" },
    { fam: "blue", h: "gRPC port mismatch", sym: "order pinned 9001, inventory 9000", fix: "converge on INVENTORY_GRPC_PORT:9000" },
    { fam: "green", h: "@QuarkusIntegrationTest TZ", sym: "launched process ignores -Duser.timezone", fix: "quarkus.test.arg-line=-Duser.timezone=UTC" },
    { fam: "tan", h: "import.sql in %prod", sym: "seed data never loaded", fix: "self-seed via REST in @BeforeAll" },
    { fam: "red", h: "@Consumes on bodyless GET", sym: "415; RestAssured drops CT = false pass", fix: "@Consumes(WILDCARD) + java.net.http test" },
    { fam: "orange", h: "Avro serde autodetect", sym: "silent fallback to JSON on the wire", fix: "pin value.serializer explicitly" },
    { fam: "blue", h: "stale postgres volume", sym: "schema survives a Hibernate DDL change", fix: "docker compose down -v to reset" },
  ];
  const cols = 4, marginX = 40, gap = 16;
  const cw = (1180 - 2 * marginX - (cols - 1) * gap) / cols;
  const ch = 190, rowY = [92, 92 + ch + 24];
  items.forEach((it, i) => {
    const row = Math.floor(i / cols), col = i % cols;
    const x = marginX + col * (cw + gap), y = rowY[row];
    const f = FAM[it.fam];
    s.rect(x, y, cw, ch, it.fam);
    s.lines(x + 12, y + 24, [it.h], { size: 12, fill: f.head, weight: 700, lh: 14 });
    s.text(x + 12, y + 58, "SYMPTOM", { size: 8.5, weight: 600, fill: "#8a7a5a" });
    s.lines(x + 12, y + 74, wrap(it.sym, 32), { size: 9.5, fill: "#3a3a3a", lh: 13 });
    s.text(x + 12, y + 132, "FIX", { size: 8.5, weight: 600, fill: "#8a7a5a" });
    s.lines(x + 12, y + 148, wrap(it.fix, 32), { size: 9.5, fill: f.head, weight: 700, lh: 13 });
  });
  s.plainRect(marginX, rowY[1] + ch + 20, 1180 - 2 * marginX, 46, "#151515", "#151515", { rx: 8 });
  s.text(590, rowY[1] + ch + 48, "Documented here so you skip the debugging — each maps to a committed fix in this repo", { size: 12.5, anchor: "middle", weight: 700, fill: "#ffffff" });
  s.footer("Symptoms and fixes are grounded in the repo's commits and config; none were re-run live for this figure.");
  save("17-gotchas", s);
})();

/* ========== 18. AGENTIC RECOMMENDATIONS ========== */
(() => {
  const s = new SVG(1180, 620);
  s.title(
    "A plan / execute / validate relay, grounded in MCP tooling",
    "Route each phase to the model tier that fits it — and verify the result independently"
  );
  const marginX = 60, boxY = 100, boxW = 300, boxH = 130;
  const gap = (1180 - 2 * marginX - 3 * boxW) / 2;
  const xs = [marginX, marginX + boxW + gap, marginX + 2 * (boxW + gap)];
  s.card(xs[0], boxY, boxW, boxH, "red", "PLAN — Opus", ["decompose the work,", "pick the approach,", "define acceptance criteria"]);
  s.card(xs[1], boxY, boxW, boxH, "green", "EXECUTE — Sonnet", ["one agent per file-disjoint", "step, fanned out in parallel,", "checkpoint-commit each"]);
  s.card(xs[2], boxY, boxW, boxH, "red", "VALIDATE — Opus", ["reads the real diff, runs", "the real build — not the", "executor's self-report"]);
  s.arrow(xs[0] + boxW, boxY + boxH / 2, xs[1], boxY + boxH / 2, { marker: "arr", w: 1.8 });
  s.arrow(xs[1] + boxW, boxY + boxH / 2, xs[2], boxY + boxH / 2, { marker: "arr", w: 1.8 });
  const ry = boxY + boxH + 36;
  s.arrow(xs[2] + boxW / 2, boxY + boxH, xs[1] + boxW / 2, ry, { marker: "arrR", w: 1.5, dash: "5 3" });
  s.text(xs[2], ry + 16, "repair round (capped at 2)", { size: 10, anchor: "middle", italic: true, fill: "#a8331f", weight: 700 });
  const mY = 360, mW = 480, mH = 90;
  const mXs = [marginX, 1180 - marginX - mW];
  s.card(mXs[0], mY, mW, mH, "blue", "camel-mcp", ["catalog lookups, route validation, runtime introspection", "— don't guess Camel component/EIP syntax"]);
  s.card(mXs[1], mY, mW, mH, "orange", "quarkus-agent", ["quarkus_searchDocs / quarkus_skills / quarkus_logs", "— version-matched patterns, not recalled guesses"]);
  s.text(590, mY - 14, "GROUND EVERY EXECUTOR IN REAL TOOLING", { size: 10, anchor: "middle", weight: 700, fill: "#8a7a5a" });
  s.plainRect(marginX, 480, 1180 - 2 * marginX, 46, "#151515", "#151515", { rx: 8 });
  s.text(590, 508, "A subagent's report is a claim, not evidence — the value is the independent verification", { size: 12.5, anchor: "middle", weight: 700, fill: "#ffffff" });
  s.footer("Guardrails: Conventional Commits, no attribution trailers, scope discipline, explicit model tier on every nested agent call.");
  save("18-agentic-recommendations", s);
})();

/* ========== 19. TESTING PYRAMID ========== */
(() => {
  const s = new SVG(1180, 640);
  s.title(
    "The test pyramid, and the phases run-all-tests.sh walks",
    "Fast and many at the base; few, heavy, and end-to-end at the top"
  );
  const cx = 380;
  const tiers = [
    { fam: "orange", w: 240, label: ["functional (Newman) + load (hey, ghz)"] },
    { fam: "blue", w: 420, label: ["failsafe *IT — OrderPlacedAvroWireIT,", "InventoryCheckStockWireIT (Testcontainers)"] },
    { fam: "green", w: 600, label: ["unit @QuarkusTest — surefire, Dev Services auto-provision"] },
  ];
  let ty = 140, th = 92, tgap = 10;
  tiers.forEach((t) => {
    const x = cx - t.w / 2;
    s.rect(x, ty, t.w, th, t.fam);
    s.lines(x + 16, ty + (t.label.length === 1 ? 52 : 42), t.label, { size: 11, fill: FAM[t.fam].head, weight: 700, lh: 16 });
    ty += th + tgap;
  });
  const rX = 760, rY = 130, rW = 380;
  s.text(rX, rY - 8, "scripts/run-all-tests.sh — phases", { size: 12, weight: 700, fill: "#5a3a0a" });
  const phases = ["PREFLIGHT", "UNIT + IT (mvn verify)", "TWIN (Spring Boot build)", "STACK-UP (docker compose)", "FUNCTIONAL (Newman)", "LOAD (hey / ghz)", "TEARDOWN"];
  phases.forEach((p, i) => {
    const y = rY + 16 + i * 44;
    s.rect(rX, y, rW, 34, "tan");
    s.text(rX + 14, y + 22, `${i + 1}. ${p}`, { size: 11, fill: "#5a3a0a", weight: 700 });
  });
  s.plainRect(40, 560, 1180 - 80, 46, "#151515", "#151515", { rx: 8 });
  s.text(590, 588, "One command walks the whole pyramid — flags select tiers: --unit / --it / --load / --all", { size: 12.5, anchor: "middle", weight: 700, fill: "#ffffff" });
  s.footer("Phase names mirror scripts/run-all-tests.sh; no suite was executed to produce this figure.");
  save("19-testing-pyramid", s);
})();

/* ========== 20. IN-MEMORY VS KAFKA ========== */
(() => {
  const s = new SVG(1180, 600);
  s.title(
    "In-memory connector vs. Kafka — same code, different transport",
    "The @Incoming/@Outgoing methods never change; only the connector config does"
  );
  const lX = 60, lW = 460, topY = 100;
  s.rect(lX, topY, lW, 220, "green");
  s.text(lX + 16, topY + 26, "In-memory connector (tests)", { size: 13, weight: 700, fill: "#2a5a1a" });
  s.plainRect(lX + 30, topY + 50, lW - 60, 140, "#ffffff", "#5a8a3a", { rx: 6 });
  s.text(lX + lW / 2, topY + 74, "one JVM", { size: 11, anchor: "middle", italic: true, fill: "#5a8a3a" });
  s.pill(lX + 60, topY + 92, lW - 120, "@Outgoing producer", "white");
  s.pill(lX + 60, topY + 140, lW - 120, "@Incoming consumer", "white");
  s.arrow(lX + lW / 2, topY + 118, lX + lW / 2, topY + 140, { marker: "arrG", w: 1.4 });
  s.text(lX + lW / 2, topY + 212, "fast · deterministic · no broker · not durable", { size: 10, anchor: "middle", italic: true, fill: "#2a5a1a" });
  const rX = 660, rW = 460;
  s.rect(rX, topY, rW, 220, "red");
  s.text(rX + 16, topY + 26, "Kafka connector (%prod)", { size: 13, weight: 700, fill: "#a8331f" });
  s.pill(rX + 24, topY + 66, 150, "producer JVM", "white");
  s.pill(rX + rW - 174, topY + 66, 150, "consumer JVM", "white");
  s.plainRect(rX + rW / 2 - 70, topY + 120, 140, 48, "#fdf0ec", "#c14a3a", { rx: 6 });
  s.text(rX + rW / 2, topY + 149, "Kafka broker", { size: 11, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.arrow(rX + 99, topY + 92, rX + rW / 2 - 50, topY + 122, { marker: "arrR", w: 1.4 });
  s.arrow(rX + rW / 2 + 50, topY + 122, rX + rW - 99, topY + 92, { marker: "arrR", w: 1.4 });
  s.text(rX + rW / 2, topY + 212, "durable · partitioned · ordered per partition · back-pressure", { size: 10, anchor: "middle", italic: true, fill: "#a8331f" });
  s.text(590, topY + 258, "same @Incoming / @Outgoing code — only the connector config changes", { size: 12, anchor: "middle", weight: 700, fill: "#5a3a0a" });
  s.plainRect(60, 470, 1180 - 120, 46, "#151515", "#151515", { rx: 8 });
  s.text(590, 498, "In-memory proves the messaging logic in tests; Kafka is the real transport in %prod", { size: 12.5, anchor: "middle", weight: 700, fill: "#ffffff" });
  s.footer("Reflects how this reactor wires each connector; trade-off notes are qualitative, not benchmarked.");
  save("20-inmemory-vs-kafka", s);
})();

/* ========== 21. THREE ENGINES COMPARED ========== */
(() => {
  const s = new SVG(1180, 640);
  s.title(
    "Choreography is not orchestration — pick by who owns the sequence",
    "The same order-to-shipment domain, coordinated three ways"
  );
  const marginX = 40, labelW = 210;
  const engW = (1180 - 2 * marginX - labelW) / 3;
  const engines = [
    { fam: "red", name: "Kafka choreography", sub: "no central coordinator" },
    { fam: "blue", name: "Camel orchestration", sub: "OrderTriageRoute" },
    { fam: "green", name: "Quarkus Flow", sub: "OrderTriageWorkflow" },
  ];
  const headY = 90, headH = 56;
  engines.forEach((e, i) => {
    const x = marginX + labelW + i * engW;
    s.rect(x, headY, engW, headH, e.fam);
    s.text(x + engW / 2, headY + 24, e.name, { size: 12, anchor: "middle", weight: 700, fill: FAM[e.fam].head });
    s.text(x + engW / 2, headY + 42, e.sub, { size: 9.5, anchor: "middle", italic: true, fill: FAM[e.fam].head });
  });
  const rows = [
    { k: "who knows the sequence", v: ["no one — each reacts to events", "the route, start to finish", "the workflow document"] },
    { k: "coupling", v: ["loose (via topics)", "centralized in the route", "centralized in the doc"] },
    { k: "failure / compensation", v: ["idempotent redelivery", "exception propagation (no saga)", "task-level, declarative"] },
    { k: "debuggability", v: ["trace across services", "one route, one log", "inspect the task graph"] },
    { k: "where logic lives", v: ["spread over consumers", "in Java route code", "in the task declaration"] },
  ];
  let ry = headY + headH + 8;
  const rh = 70;
  rows.forEach((r) => {
    s.plainRect(marginX, ry, labelW, rh, "#f4f3f0", "#9a9a9a", { rx: 6 });
    s.lines(marginX + 12, ry + rh / 2 - 4, wrap(r.k, 22), { size: 10.5, weight: 700, fill: "#4a4a4a", lh: 14 });
    r.v.forEach((v, i) => {
      const x = marginX + labelW + i * engW;
      s.plainRect(x, ry, engW, rh, "#ffffff", "#c0c0c0", { rx: 6 });
      s.lines(x + 12, ry + rh / 2 - 4, wrap(v, 34), { size: 10, fill: "#3a3a3a", lh: 14 });
    });
    ry += rh + 6;
  });
  s.footer("Grounded in the three real implementations; terminology kept exact — Kafka is choreography, Camel and Flow are orchestration.");
  save("21-three-engines-compare", s);
})();

console.log("DONE");
