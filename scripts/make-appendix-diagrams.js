// make-appendix-diagrams.js — appendix figures for ch16 (WebSocket failover)
// and ch20 (Vert.x in-memory messaging, Kafka messaging). Same visual grammar
// as make-quarkus-diagrams.js; emits paired .svg + .excalidraw into assets/diagrams/.
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

// ---- local helpers (copied small; svglib.js is not edited) ----
const ARROW_HEX = { arr: "#5a5a5a", arrR: "#c14a3a", arrB: "#2c5aa0", arrG: "#5a8a3a" };
// cubic bezier arrow: SVG path + excalidraw arrow with 5 sampled points
const curveArrow = (s, [x1, y1], [c1x, c1y], [c2x, c2y], [x2, y2], { marker = "arrR", w = 1.6, dash = null } = {}) => {
  const c = ARROW_HEX[marker];
  s.parts.push(`<path d="M ${x1} ${y1} C ${c1x} ${c1y}, ${c2x} ${c2y}, ${x2} ${y2}" fill="none" stroke="${c}" stroke-width="${w}"${dash ? ` stroke-dasharray="${dash}"` : ""} marker-end="url(#${marker})"/>`);
  const bz = (t) => {
    const u = 1 - t;
    return [u*u*u*x1 + 3*u*u*t*c1x + 3*u*t*t*c2x + t*t*t*x2, u*u*u*y1 + 3*u*u*t*c1y + 3*u*t*t*c2y + t*t*t*y2];
  };
  const pts = [0, 0.25, 0.5, 0.75, 1].map(bz).map(([px, py]) => [Math.round((px - x1) * 10) / 10, Math.round((py - y1) * 10) / 10]);
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  s.els.push(s._base({
    type: "arrow", x: x1, y: y1, width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys),
    strokeColor: c, backgroundColor: "transparent", strokeWidth: w, strokeStyle: dash ? "dashed" : "solid",
    roundness: { type: 2 }, points: pts, lastCommittedPoint: null,
    startBinding: null, endBinding: null, startArrowhead: null, endArrowhead: "arrow",
  }));
};
// pill with a legible font size
const pillL = (s, x, y, w, t, fam, { h = 28, size = 14 } = {}) => {
  const f = FAM[fam] || fam;
  s._rect(x, y, w, h, f.fill, f.stroke, { rx: h / 2 });
  s.text(x + w / 2, y + h / 2 + size * 0.35, t, { size, fill: f.head, anchor: "middle", weight: 700 });
};
// titled box: bold heading + body lines, all >= 14px
const boxL = (s, x, y, w, h, fam, head, lines = [], { hs = 15, ls = 14, lh = 19 } = {}) => {
  const f = FAM[fam];
  s.rect(x, y, w, h, fam);
  s.text(x + 14, y + 25, head, { size: hs, fill: f.head, weight: 700 });
  if (lines.length) s.lines(x + 14, y + 25 + 22, lines, { size: ls, fill: "#3a3a3a", lh });
};
// dark call-out band
const band = (s, x, y, w, h, t, size = 14) => {
  s.plainRect(x, y, w, h, "#151515", "#151515", { rx: 8 });
  s.text(x + w / 2, y + h / 2 + size * 0.35, t, { size, anchor: "middle", weight: 700, fill: "#ffffff" });
};

/* ========== 16b. WEBSOCKET FAILOVER ========== */
(() => {
  const s = new SVG(1180, 400);
  s.title("Replica failure and client reconnect");
  const pw = 350, pg = 25, py = 52, ph = 290;
  const px = [40, 40 + pw + pg, 40 + 2 * (pw + pg)];
  const heads = [["1  Normal", "blue"], ["2  Replica 2 fails", "red"], ["3  Recover", "green"]];
  heads.forEach(([h, fam], i) => {
    s.rect(px[i], py, pw, ph, fam);
    s.text(px[i] + 16, py + 28, h, { size: 16, weight: 700, fill: FAM[fam].head });
  });
  // arrows between panels (frame edge -> frame edge)
  s.arrow(px[0] + pw, py + ph / 2, px[1], py + ph / 2, { marker: "arr", w: 1.8 });
  s.arrow(px[1] + pw, py + ph / 2, px[2], py + ph / 2, { marker: "arr", w: 1.8 });

  const nodeY = py + 60;
  // panel 1
  let x = px[0];
  pillL(s, x + 20, nodeY, 110, "client", "white", { h: 40 });
  pillL(s, x + 220, nodeY, 110, "replica 2", "white", { h: 40 });
  s.arrow(x + 130, nodeY + 12, x + 220, nodeY + 12, { marker: "arrB", w: 1.6 });
  s.arrow(x + 220, nodeY + 28, x + 130, nodeY + 28, { marker: "arrG", w: 1.6 });
  s.lines(x + 16, py + 148, ["Socket open through the Service.", "Replica 2 pushes every event", "from its own consumer group."], { size: 14, fill: "#3a3a3a", lh: 20 });
  // panel 2
  x = px[1];
  pillL(s, x + 20, nodeY, 110, "client", "white", { h: 40 });
  s.plainRect(x + 220, nodeY, 110, 40, "#fdf0ec", "#c14a3a", { rx: 20, dash: "5 3" });
  s.text(x + 275, nodeY + 25, "replica 2", { size: 14, anchor: "middle", weight: 700, fill: "#a8331f" });
  s.arrow(x + 220, nodeY + 20, x + 130, nodeY + 20, { marker: "arrR", w: 1.6, dash: "5 3" });
  s.label(x + 175, nodeY + 8, "socket closes", { size: 13 });
  s.text(x + 16, py + 148, "Client backs off with jitter:", { size: 14, fill: "#3a3a3a" });
  ["1s", "2s", "4s", "..."].forEach((t, i) => pillL(s, x + 16 + i * 80, py + 166, 66, t, "white"));
  s.text(x + 16, py + 230, "Delay doubles up to a cap.", { size: 14, fill: "#3a3a3a" });
  // panel 3
  x = px[2];
  pillL(s, x + 20, nodeY + 14, 110, "client", "white", { h: 40 });
  pillL(s, x + 220, nodeY - 16, 110, "replica 1", "white", { h: 36 });
  pillL(s, x + 220, nodeY + 46, 110, "replica 3", "white", { h: 36 });
  s.arrow(x + 130, nodeY + 26, x + 220, nodeY + 2, { marker: "arrB", w: 1.6 });
  s.arrow(x + 130, nodeY + 42, x + 220, nodeY + 64, { marker: "arrB", w: 1.6 });
  s.lines(x + 16, py + 164, ["Service routes the reconnect to", "replica 1 or 3, already receiving", "every event via its own push group.", "Client re-fetches missed events:", "GET /notifications"], { size: 14, fill: "#3a3a3a", lh: 20 });

  s.footer("Client reconnect/backoff is a recommended pattern; WsNotificationClient does not implement it (unverified).");
  save("16-websocket-failover", s);
})();

/* ========== 20b. VERT.X IN-MEMORY ========== */
(() => {
  const s = new SVG(1180, 492);
  s.title("Vert.x in-memory messaging inside one JVM");
  s.rect(40, 50, 1100, 296, "white");
  s.text(56, 76, "One JVM", { size: 16, weight: 700, fill: "#5a3a0a" });

  boxL(s, 70, 96, 250, 140, "tan", "Producers", ["Emitter", "@Outgoing methods"]);
  s.rect(420, 96, 340, 140, "blue");
  s.text(436, 121, "Vert.x event bus", { size: 15, weight: 700, fill: "#1a3a6a" });
  [["send: one consumer", 0], ["publish: all consumers", 1], ["request-reply", 2]].forEach(([t, i]) => pillL(s, 436, 134 + i * 32, 308, t, "white"));
  boxL(s, 860, 96, 250, 140, "green", "Consumers", ["@Incoming methods", "@ConsumeEvent"]);
  s.arrow(320, 166, 420, 166, { marker: "arr", w: 1.8 });
  s.arrow(760, 166, 860, 166, { marker: "arr", w: 1.8 });

  boxL(s, 70, 262, 500, 68, "gray", "Event-loop threads (about 2 x cores)", ["Non-blocking handlers"]);
  boxL(s, 590, 262, 520, 68, "gray", "Worker pool", ["Blocking handlers"]);

  boxL(s, 40, 366, 540, 76, "green", "Scales up with cores", ["No network hop or wire serialization;", "back-pressure via Mutiny."]);
  boxL(s, 600, 366, 540, 76, "red", "Limits", ["One JVM, not durable, no replay."]);

  s.footer("This project uses the in-memory connector in shipping-service tests; event-bus usage shown is illustrative.");
  save("20-vertx-in-memory", s);
})();

/* ========== 20c. KAFKA MESSAGING ========== */
(() => {
  const s = new SVG(1180, 512);
  s.title("Kafka messaging: partitions, consumer groups, replay");

  boxL(s, 40, 150, 160, 76, "tan", "Producers", ["order-service"]);
  s.arrow(200, 188, 260, 188, { marker: "arr", w: 1.8 });
  s.label(230, 176, "publish", { size: 13 });

  // topic frame with partitions
  s.rect(260, 56, 360, 272, "red");
  s.text(276, 82, "Topic order.placed", { size: 15, weight: 700, fill: "#a8331f" });
  const py = [96, 154, 212, 270];
  py.forEach((y, i) => {
    s.plainRect(280, y, 320, 44, "#ffffff", "#c14a3a", { rx: 6 });
    s.text(440, y + 28, `P${i}`, { size: 14, anchor: "middle", weight: 700, fill: "#a8331f" });
  });

  // apicurio
  boxL(s, 40, 276, 160, 62, "orange", "Apicurio", ["Avro schemas"]);
  s.arrow(200, 307, 260, 307, { marker: "arr", w: 1.4, dash: "5 3" });

  // group A
  s.rect(760, 56, 380, 190, "green");
  s.text(776, 82, "Consumer group A", { size: 15, weight: 700, fill: "#2a5a1a" });
  s.plainRect(790, 100, 320, 50, "#ffffff", "#5a8a3a", { rx: 6 });
  s.text(950, 131, "replica A1 owns P0, P1", { size: 14, anchor: "middle", weight: 700, fill: "#2a5a1a" });
  s.plainRect(790, 172, 320, 50, "#ffffff", "#5a8a3a", { rx: 6 });
  s.text(950, 203, "replica A2 owns P2, P3", { size: 14, anchor: "middle", weight: 700, fill: "#2a5a1a" });
  s.arrow(600, 118, 790, 118, { marker: "arrG", w: 1.4 });
  s.arrow(600, 176, 790, 140, { marker: "arrG", w: 1.4 });
  s.arrow(600, 234, 790, 190, { marker: "arrG", w: 1.4 });
  s.arrow(600, 292, 790, 208, { marker: "arrG", w: 1.4 });

  // group B
  s.rect(760, 266, 380, 100, "blue");
  s.text(776, 292, "Consumer group B", { size: 15, weight: 700, fill: "#1a3a6a" });
  s.plainRect(790, 304, 320, 50, "#ffffff", "#2c5aa0", { rx: 6 });
  s.text(950, 335, "reads all partitions independently", { size: 14, anchor: "middle", weight: 700, fill: "#1a3a6a" });
  s.arrow(620, 320, 790, 330, { marker: "arrB", w: 1.4 });
  s.label(690, 354, "fan-out", { size: 13 });

  boxL(s, 40, 392, 560, 76, "tan", "Retention and offsets", ["Events stay after consumption; a consumer", "replays from any retained offset."]);
  boxL(s, 620, 392, 520, 76, "green", "Scale out", ["Consumers up to the partition count;", "KEDA scales replicas on lag."]);

  s.footer("Partition and replica counts are illustrative.");
  save("20-kafka-messaging", s);
})();

console.log("DONE");
