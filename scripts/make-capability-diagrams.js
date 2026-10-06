// make-capability-diagrams.js — seven capability figures for chapter 11
// (Panache patterns, Uni vs imperative, WebSockets.Next, JBang, startup paths,
// Panama FFM, OIDC token flow). Same visual grammar as svglib.js /
// make-quarkus-diagrams.js; emits paired .svg + .excalidraw into
// assets/diagrams/.
const { SVG, FAM, INK, MUT } = require("./svglib.js");
const fs = require("fs");
const path = require("path");

const OUT = path.join(__dirname, "..", "assets", "diagrams");
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

const MONO = "'Red Hat Mono', ui-monospace, Menlo, Consolas, monospace";
const save = (name, svg) => {
  fs.writeFileSync(path.join(OUT, `${name}.svg`), svg.render());
  fs.writeFileSync(path.join(OUT, `${name}.excalidraw`), svg.excalidraw());
  console.log("wrote", name, `${svg.w}x${svg.h}`);
};

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const estW = (t, size, mono) => Math.round(String(t).length * size * (mono ? 0.6 : 0.54));

// text with optional monospace; (x,y) is the baseline, like svglib.text
function T(s, x, y, t, { size = 14, fill = INK, anchor = "middle", weight = null, mono = false, italic = false } = {}) {
  s.parts.push(`<text x="${x}" y="${y}" font-size="${size}" fill="${fill}" text-anchor="${anchor}"${mono ? ` font-family="${esc(MONO)}"` : ""}${weight ? ` font-weight="${weight}"` : ""}${italic ? ` font-style="italic"` : ""}>${esc(t)}</text>`);
  const w = estW(t, size, mono);
  const ex = anchor === "middle" ? x - w / 2 : anchor === "end" ? x - w : x;
  s.els.push(s._base({
    type: "text", x: ex, y: y - size * 0.8, width: w, height: Math.round(size * 1.25),
    strokeColor: fill, backgroundColor: "transparent", text: String(t), originalText: String(t),
    fontSize: size, fontFamily: mono ? 3 : 2,
    textAlign: anchor === "middle" ? "center" : anchor === "end" ? "right" : "left",
    verticalAlign: "top", lineHeight: 1.25, containerId: null, roundness: null,
  }));
  return w;
}

// box with centered heading + lines. lines: string | {t, mono}. head: string | {t, mono}
function box(s, x, y, w, h, fam, head, lines = [], { lh = 21, hsize = 15 } = {}) {
  const f = FAM[fam];
  s.rect(x, y, w, h, fam);
  const items = [];
  if (head) items.push({ ...(typeof head === "string" ? { t: head } : head), head: true });
  lines.forEach((l) => items.push(typeof l === "string" ? { t: l } : l));
  const block = items.length * lh;
  let by = y + (h - block) / 2 + lh * 0.72;
  items.forEach((it) => {
    const size = it.head ? (it.mono ? 14 : hsize) : 14;
    const tw = estW(it.t, size, it.mono);
    if (tw > w - 12) console.warn(`  WARN overflow: "${it.t}" ~${tw}px in box w=${w}`);
    T(s, x + w / 2, Math.round(by), it.t, { size, fill: it.head ? f.head : INK, weight: it.head ? 700 : null, mono: !!it.mono });
    by += lh;
  });
}

// container frame with top-left label
function frame(s, x, y, w, h, label, fam = "gray") {
  const f = FAM[fam];
  s._rect(x, y, w, h, "#fdfcfa", f.stroke, { rx: 10, sw: 1.5, dash: "6 4" });
  T(s, x + 16, y + 26, label, { size: 16, fill: f.head, weight: 700, anchor: "start" });
}

const arrow = (s, x1, y1, x2, y2, opt) => s.arrow(x1, y1, x2, y2, opt);
const lbl = (s, x, y, t, o = {}) => T(s, x, y, t, { size: 14, fill: MUT, italic: !o.mono, ...o });

/* ========== 11-panache-patterns ========== */
(() => {
  const s = new SVG(1180, 440);
  s.title("Panache: active record vs. repository");

  // left: active record
  frame(s, 30, 64, 440, 262, "Active record (this project)", "blue");
  const lw = 126, ly = 108, lh = 66;
  [[43, "OrderResource", "JAX-RS"], [187, "Order", "entity"], [331, "Database", "PostgreSQL"]].forEach(([x, h, sub], i) => {
    box(s, x, ly, lw, lh, i === 2 ? "gray" : i === 1 ? "blue" : "tan", { t: h, mono: i < 2 }, [sub]);
  });
  arrow(s, 43 + lw, ly + lh / 2, 187, ly + lh / 2);
  arrow(s, 187 + lw, ly + lh / 2, 331, ly + lh / 2);
  box(s, 50, 200, 406, 106, "white", null, [
    { t: "Order extends PanacheEntityBase", mono: true },
    { t: "Order.findById(id)", mono: true },
    { t: "order.persist()", mono: true },
  ]);

  // right: repository
  frame(s, 490, 64, 660, 262, "Repository", "orange");
  const rw = 140, rg = 20, rx0 = 510;
  const rn = [["OrderResource", "JAX-RS", "tan", true], ["OrderRepository", "injected bean", "orange", true], ["Order", "entity", "blue", true], ["Database", "PostgreSQL", "gray", false]];
  rn.forEach(([h, sub, fam, m], i) => {
    const x = rx0 + i * (rw + rg);
    box(s, x, ly, rw, lh, fam, { t: h, mono: m }, [sub]);
    if (i) arrow(s, x - rg, ly + lh / 2, x, ly + lh / 2);
  });
  box(s, 510, 200, 620, 106, "white", null, [
    { t: "OrderRepository implements PanacheRepository<Order>", mono: true },
    { t: "@Inject OrderRepository orders;", mono: true },
    { t: "orders.findById(id)  /  orders.persist(order)", mono: true },
  ]);

  // band
  s.rect(30, 346, 1120, 74, "tan");
  T(s, 590, 376, "Same Hibernate ORM and SQL underneath.", { size: 15, weight: 700, fill: FAM.tan.head });
  T(s, 590, 402, "Repository: easier to mock and layer. Active record: less code. Spring Data JPA is the twin's repository equivalent.", { size: 14 });
  save("11-panache-patterns", s);
})();

/* ========== 11-uni-vs-imperative ========== */
(() => {
  const s = new SVG(1180, 470);
  s.title("Imperative and reactive signatures in one Quarkus service");

  frame(s, 30, 64, 540, 340, "Imperative: StockResource", "blue");
  box(s, 50, 110, 500, 56, "white", null, [{ t: "StockDto get(String sku)", mono: true }]);
  arrow(s, 300, 166, 300, 206);
  box(s, 150, 206, 300, 80, "blue", "Worker thread", ["Blocking calls are fine"]);
  box(s, 50, 316, 500, 72, "gray", null, ["A plain return type runs on a worker thread", "by default in Quarkus REST"]);

  frame(s, 590, 64, 560, 340, "Reactive: InventoryGrpcService", "orange");
  box(s, 610, 110, 520, 56, "white", null, [{ t: "Uni<CheckStockResponse> checkStock(req)", mono: true }]);
  arrow(s, 760, 166, 760, 206);
  box(s, 610, 206, 300, 80, "orange", "Event loop (Vert.x)", ["Must never block"]);
  arrow(s, 910, 246, 1000, 246, { marker: "arrR", color: "#c14a3a" });
  lbl(s, 955, 232, "@Blocking", { mono: true });
  box(s, 1000, 206, 130, 80, "blue", "Worker", ["thread"]);
  box(s, 610, 316, 520, 72, "tan", "Uni<T>: lazy, one async result, runs when subscribed", [
    { t: "onItem().transform()   onFailure().retry()", mono: true },
  ]);

  T(s, 590, 442, "The signature and @Blocking / @NonBlocking (or @RunOnVirtualThread) choose the thread.", { size: 14, fill: "#6a5a3a", italic: true });
  save("11-uni-vs-imperative", s);
})();

/* ========== 11-websockets-next ========== */
(() => {
  const s = new SVG(1180, 500);
  s.title("WebSockets.Next vs. the legacy WebSocket extension");

  frame(s, 30, 64, 540, 262, "quarkus-websockets (legacy)", "gray");
  const rows = (x, w, fam, items) => items.forEach((it, i) => box(s, x, 100 + i * 54, w, 44, fam, null, [it], { lh: 21 }));
  rows(50, 500, "gray", [
    { t: '@ServerEndpoint("/chat")', mono: true },
    "Jakarta WebSocket API on Undertow",
    "Callback methods take a Session parameter",
    "Callback style: @OnOpen, @OnMessage, @OnClose",
  ]);

  frame(s, 590, 64, 560, 262, "quarkus-websockets-next (Vert.x)", "blue");
  rows(610, 520, "blue", [
    { t: '@WebSocket(path = "/ws/notifications")', mono: true },
    "@OnOpen / @OnTextMessage return a value, Uni or Multi",
    "Execution model follows the signature",
    "Injectable OpenConnections; @WebSocketClient for clients",
  ]);

  frame(s, 30, 346, 1120, 130, "notification-service push path", "green");
  const by = 384, bh = 52;
  box(s, 50, by, 290, bh, "red", null, [{ t: '@Incoming("order-placed-push")', mono: true }]);
  box(s, 380, by, 270, bh, "tan", null, [{ t: "OpenConnections.listAll()", mono: true }]);
  box(s, 690, by, 260, bh, "tan", null, [{ t: "connection.sendText(...)", mono: true }]);
  box(s, 990, by, 140, bh, "gray", "Clients", []);
  arrow(s, 340, by + bh / 2, 380, by + bh / 2);
  arrow(s, 650, by + bh / 2, 690, by + bh / 2);
  arrow(s, 950, by + bh / 2, 990, by + bh / 2);
  T(s, 590, 460, "Per-replica consumer group: every replica receives every event and pushes to its own sockets.", { size: 14, fill: MUT, italic: true });
  save("11-websockets-next", s);
})();

/* ========== 11-jbang-tooling ========== */
(() => {
  const s = new SVG(1180, 400);
  s.title("JBang: run a single .java file, no project");

  const y = 70, h = 124;
  box(s, 40, y, 300, h, "tan", "Single .java file", [
    { t: "//JAVA 25+", mono: true },
    { t: "//DEPS group:artifact:version", mono: true },
  ]);
  box(s, 390, y, 170, h, "orange", { t: "jbang", mono: true }, ["compile and run"]);
  box(s, 610, y, 280, h, "blue", "Resolve", ["Dependencies from Maven Central", "Downloads a JDK if missing"]);
  box(s, 940, y, 200, h, "green", "Cache", ["Build is cached;", "later runs start fast"]);
  arrow(s, 340, y + h / 2, 390, y + h / 2);
  arrow(s, 560, y + h / 2, 610, y + h / 2);
  arrow(s, 890, y + h / 2, 940, y + h / 2);

  frame(s, 40, 226, 1100, 150, "Used in this project", "gray");
  const bw = 252, bg = 14, bx = 60, byy = 270, bh = 84;
  [
    [{ t: "HelloRoute.java", mono: true }, ["Camel route prototype with", "pinned //DEPS (Camel 4.22.1)"]],
    [{ t: "WsNotificationClient.java", mono: true }, ["WebSocket client for", "the push demo"]],
    [{ t: "PanamaFfm.java", mono: true }, ["Foreign Function & Memory", "calls into libc"]],
    ["Pinned tools", [{ t: "camel-launcher:4.22.1", mono: true }, { t: "quarkus-agent-mcp:1.2.11", mono: true }]],
  ].forEach(([hd, ln], i) => box(s, bx + i * (bw + bg), byy, bw, bh, i === 3 ? "tan" : "white", hd, ln, { lh: 20, hsize: 14 }));
  save("11-jbang-tooling", s);
})();

/* ========== 11-startup-paths ========== */
(() => {
  const s = new SVG(1180, 540);
  s.title("Three startup paths for the same service");

  const lanes = [
    { fam: "blue", name: "JVM", sub: "", steps: [["Load classes"], ["Link and verify"], ["Interpret bytecode"], ["JIT warm-up"]] },
    { fam: "orange", name: "JVM + AOT cache", sub: "JDK 25, JEPs 483/514/515", steps: [
      ["Training run", { t: "-XX:AOTCacheOutput", mono: true }],
      ["app.aot", "loaded, linked, profiled"],
      ["Production run", { t: "-XX:AOTCache", mono: true }],
      ["Same jar, full JVM", "JIT still active"]] },
    { fam: "green", name: "Native image", sub: "GraalVM / Mandrel", steps: [
      ["Closed-world build", "static analysis"],
      ["Reflection config", "declared at build"],
      ["Native executable", "no JVM, no JIT"],
      ["Runs immediately", "nothing to load or link"]] },
  ];
  const lh = 72, gap = 12, y0 = 64;
  lanes.forEach((ln, i) => {
    const y = y0 + i * (lh + gap);
    box(s, 30, y, 210, lh, ln.fam, ln.name, ln.sub ? [ln.sub] : [], { lh: 20 });
    ln.steps.forEach((st, j) => {
      const x = 270 + j * 231;
      box(s, x, y, 195, lh, "white", st[0], st.slice(1), { lh: 20, hsize: 14.5 });
      if (j) arrow(s, x - 36, y + lh / 2, x, y + lh / 2);
    });
    arrow(s, 240, y + lh / 2, 270, y + lh / 2);
  });

  // qualitative matrix
  const ty = 330, cols = [30, 240, 540, 840], cw = [210, 300, 300, 310], rh = 31;
  const head = ["", "JVM", "JVM + AOT cache", "Native image"];
  const rows = [
    ["Build cost", "Compile only", "Compile + training run", "Closed-world build, minutes"],
    ["Startup", "Slowest: load, link, warm up", "Faster: classes pre-linked", "Fastest: no JVM start"],
    ["Memory", "Highest", "Close to JVM", "Lowest"],
    ["Compatibility", "Full", "Full; cache tied to jar and JDK", "Reflection config required"],
    ["Peak throughput", "JIT at full speed", "JIT at full speed", "No JIT: often lower peak"],
  ];
  s._rect(30, ty, 1120, rh, FAM.tan.fill, FAM.tan.stroke, { rx: 4 });
  head.forEach((t, c) => t && T(s, cols[c] + cw[c] / 2, ty + 21, t, { size: 15, weight: 700, fill: FAM.tan.head }));
  rows.forEach((r, i) => {
    const y = ty + rh + i * rh;
    s._rect(30, y, 1120, rh, i % 2 ? "#faf8f3" : "#ffffff", "#e0ddd4", { rx: 0, sw: 1 });
    r.forEach((t, c) => {
      if (estW(t, 14) > cw[c] - 10) console.warn(`  WARN overflow cell "${t}"`);
      T(s, cols[c] + (c ? cw[c] / 2 : 12), y + 21, t, { size: 14, weight: c ? null : 700, fill: c ? INK : FAM.tan.head, anchor: c ? "middle" : "start" });
    });
  });
  save("11-startup-paths", s);
})();

/* ========== 11-panama-ffm ========== */
(() => {
  const s = new SVG(1180, 400);
  s.title("Panama FFM: calling libc from Java without JNI");

  frame(s, 30, 64, 860, 150, "Java (JDK 25)", "blue");
  const y = 108, h = 76;
  box(s, 50, y, 220, h, "blue", null, [{ t: "Linker.nativeLinker()", mono: true }]);
  box(s, 300, y, 190, h, "blue", null, [{ t: "defaultLookup()", mono: true }]);
  box(s, 520, y, 260, h, "orange", { t: "downcallHandle", mono: true }, ["FunctionDescriptor: C signature"]);
  arrow(s, 270, y + h / 2, 300, y + h / 2);
  arrow(s, 490, y + h / 2, 520, y + h / 2);
  box(s, 940, y, 210, h, "green", "libc", [{ t: "getpid, strlen", mono: true }]);
  arrow(s, 780, y + h / 2, 940, y + h / 2, { marker: "arrG", color: "#5a8a3a" });
  lbl(s, 835, y + h / 2 - 12, "native call");

  box(s, 480, 258, 320, 100, "green", { t: "Arena", mono: true }, ["allocates an off-heap MemorySegment", "holds the C string for strlen", "freed when the arena closes"], { lh: 20 });
  arrow(s, 650, 258, 650, y + h, { marker: "arrG", color: "#5a8a3a" });
  T(s, 662, 232, "segment as argument", { size: 14, fill: MUT, italic: true, anchor: "start" });

  box(s, 30, 258, 430, 100, "gray", "JNI, for contrast", ["C glue code, generated headers,", "and a separate native build"], { lh: 20 });
  box(s, 820, 258, 330, 100, "tan", "Native access is restricted", [{ t: "--enable-native-access=ALL-UNNAMED", mono: true }, "JDK 25 warns without it"], { lh: 20 });
  save("11-panama-ffm", s);
})();

/* ========== 11-oidc-token-flow ========== */
(() => {
  const s = new SVG(1180, 520);
  s.title("OIDC bearer-token flow: Dev Services Keycloak and review-service");

  box(s, 40, 150, 220, 180, "blue", "Client", ["demo-oidc.sh (curl)", "acts as alice or bob"]);
  box(s, 470, 80, 280, 150, "orange", "Keycloak (Dev Services)", ["realm quarkus, client quarkus-app", "alice: admin + user", "bob: user", { t: "sets auth-server-url", mono: false }], { lh: 21 });
  box(s, 920, 150, 230, 180, "red", "review-service", ["quarkus-oidc verifies", "signature, issuer, expiry", { t: '@RolesAllowed("admin")', mono: true }]);

  arrow(s, 260, 190, 470, 190);
  lbl(s, 365, 180, "1  POST token endpoint");
  arrow(s, 470, 215, 260, 215);
  lbl(s, 365, 238, "2  JWT access token");
  arrow(s, 260, 300, 920, 300);
  lbl(s, 590, 290, "3  DELETE /reviews/{id} with Authorization: Bearer <jwt>");
  arrow(s, 920, 190, 750, 190);
  lbl(s, 835, 180, "4  fetch JWKS");

  frame(s, 40, 360, 1110, 110, "Outcomes of DELETE /reviews/{id}", "tan");
  box(s, 60, 394, 340, 56, "red", "No token", [{ t: "401", mono: true }], { lh: 20 });
  box(s, 420, 394, 340, 56, "red", "bob (user)", [{ t: "403", mono: true }], { lh: 20 });
  box(s, 780, 394, 350, 56, "green", "alice (admin)", ["204, then GET returns 404"], { lh: 20 });
  arrow(s, 1035, 330, 1035, 360);

  T(s, 590, 500, "Password grant for the demo only; browser apps use the authorization code flow.", { size: 14, fill: "#6a5a3a", italic: true });
  save("11-oidc-token-flow", s);
})();
