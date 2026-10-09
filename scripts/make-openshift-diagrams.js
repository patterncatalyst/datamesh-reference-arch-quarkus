// make-openshift-diagrams.js — figures for ch22 (running on OpenShift Local).
// Same visual grammar as make-appendix-diagrams.js; emits paired .svg + .excalidraw into assets/diagrams/.
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

/* ========== 22a. TOPOLOGY ========== */
(() => {
  const s = new SVG(1180, 566);
  s.title("Deployed topology on OpenShift Local");

  // outside the cluster
  s.plainRect(8, 112, 112, 70, "#ffffff", "#c19a6b", { rx: 8 });
  s.text(64, 143, "host browser", { size: 14, anchor: "middle", weight: 700, fill: "#5a3a0a" });
  s.text(64, 163, "/ curl", { size: 14, anchor: "middle", weight: 700, fill: "#5a3a0a" });
  s.arrow(120, 147, 210, 147, { marker: "arrB", w: 1.8 });
  s.label(155, 135, "HTTPS", { size: 13 });

  // cluster frame
  s.rect(190, 50, 960, 490, "white");
  s.text(206, 76, "OpenShift Local (CRC 4.22) · project datamesh · restricted-v2", { size: 16, weight: 700, fill: "#5a3a0a" });

  // lane 1: request path
  boxL(s, 210, 96, 320, 124, "orange", "Router: two edge-TLS Routes", ["graphql-gateway-datamesh.apps-crc.testing", "apicurio-datamesh.apps-crc.testing"]);
  s.arrow(530, 136, 580, 136, { marker: "arrB", w: 1.8 });
  const svcBox = (x, y, w, h, fam, name, sub) => {
    const f = FAM[fam];
    s.rect(x, y, w, h, fam);
    s.text(x + w / 2, y + 22, name, { size: 15, anchor: "middle", weight: 700, fill: f.head });
    if (sub) s.text(x + w / 2, y + 41, sub, { size: 14, anchor: "middle", fill: "#3a3a3a" });
  };
  svcBox(580, 108, 170, 56, "blue", "graphql-gateway", "");
  svcBox(800, 92, 170, 52, "green", "order-service", "REST :8080");
  svcBox(800, 168, 170, 52, "green", "inventory-service", "gRPC :9000");
  s.arrow(750, 128, 800, 118, { marker: "arrB", w: 1.6 });
  s.arrow(750, 146, 800, 194, { marker: "arrB", w: 1.6 });
  s.arrow(885, 144, 885, 168, { marker: "arrG", w: 1.6 });
  s.label(910, 161, "gRPC", { size: 13, anchor: "start" });
  svcBox(1000, 108, 130, 70, "gray", "review-service", "OIDC tenant off");

  // lane 2: Kafka
  s.rect(210, 244, 920, 176, "red");
  s.text(226, 270, "Kafka cluster datamesh", { size: 15, weight: 700, fill: "#a8331f" });
  s.text(226, 290, "AMQ Streams 3.2.1 · Kafka 4.2.0 · 1 KRaft node", { size: 14, fill: "#3a3a3a" });
  pillL(s, 580, 254, 540, "AMQ Streams operator in openshift-operators (OLM, pinned CSV)", "tan", { h: 28, size: 13 });
  const ry = 308, rh = 34;
  pillL(s, 226, ry, 130, "order-service", "green", { h: rh });
  pillL(s, 384, ry, 130, "order.placed", "white", { h: rh });
  pillL(s, 542, ry, 140, "payment-service", "green", { h: rh });
  pillL(s, 710, ry, 150, "payment.captured", "white", { h: rh });
  pillL(s, 888, ry, 140, "shipping-service", "green", { h: rh });
  [[356, 384], [514, 542], [682, 710], [860, 888]].forEach(([a, b]) => s.arrow(a, ry + 17, b, ry + 17, { marker: "arr", w: 1.6 }));
  // second row
  const r2 = 362;
  pillL(s, 358, r2, 182, "notification-service", "green", { h: rh });
  s.arrow(449, ry + rh, 449, r2, { marker: "arr", w: 1.6, dash: "5 3" });
  pillL(s, 954, r2, 160, "shipment.dispatched", "white", { h: rh });
  s.arrow(958, ry + rh, 1034, r2, { marker: "arr", w: 1.6 });

  // lane 3: data
  boxL(s, 210, 440, 480, 84, "blue", "Postgres StatefulSet datamesh-postgres-rw", ["rhel10/postgresql-16", "used by order, inventory, shipping, notification, review"]);
  boxL(s, 710, 440, 420, 84, "orange", "Apicurio 3.2.4", ["Avro schemas for the Kafka producers and", "consumers (in-cluster Service); Route for the host"]);

  save("22-crc-openshift-topology", s);
})();

/* ========== 22b. IMAGE BUILD ========== */
(() => {
  const s = new SVG(1180, 392);
  s.title("Image build path: binary S2I inside the cluster");

  boxL(s, 30, 100, 170, 130, "tan", "Host", ["mvn package", "-Popenshift", "fast-jar:", "target/quarkus-app"]);
  s.arrow(200, 165, 300, 165, { marker: "arrB", w: 1.8 });
  s.label(250, 153, "binary upload", { size: 12 });

  s.rect(300, 62, 850, 232, "white");
  s.text(316, 88, "OpenShift Local · project datamesh", { size: 16, weight: 700, fill: "#5a3a0a" });
  boxL(s, 320, 104, 240, 126, "orange", "BuildConfig", ["Source strategy, binary", "S2I on", "ubi10/openjdk-25:1.24-15"]);
  boxL(s, 596, 104, 170, 126, "blue", "Internal registry", ["image-registry", "service, port 5000"]);
  boxL(s, 802, 104, 170, 126, "green", "ImageStream", ["tag", "<service>:v1"]);
  boxL(s, 1004, 104, 130, 126, "red", "Deployment", ["pulls the", "image tag"]);
  s.arrow(560, 167, 596, 167, { marker: "arr", w: 1.8 });
  s.arrow(766, 167, 802, 167, { marker: "arr", w: 1.8 });
  s.arrow(972, 167, 1004, 167, { marker: "arr", w: 1.8 });
  s.text(725, 268, "image-registry.openshift-image-registry.svc:5000/datamesh/<service>:v1", { size: 14, anchor: "middle", fill: "#3a3a3a", weight: 700 });

  band(s, 30, 318, 640, 40, "No local container engine; the cluster never pulls from Maven Central");
  pillL(s, 700, 324, 450, "x7 services, one Maven reactor run (~3 min)", "tan", { h: 28 });

  save("22-crc-image-build", s);
})();

/* ========== 22c. PLATFORM TIER ========== */
(() => {
  const s = new SVG(1180, 612);
  s.title("Platform tier on OpenShift Local");
  const W = 360, xs = [30, 410, 790];
  const top = 54, bh = 124, bot = 386;
  const feat = (x, y, fam, head, lines, result) => {
    boxL(s, x, y, W, bh, fam, head, lines);
    s.text(x + 14, y + bh - 14, result, { size: 14, fill: FAM[fam].head, weight: 700 });
  };
  feat(xs[0], top, "blue", "Service Mesh 3 (Sail) + Kiali", ["Istio v1.30.5 · STRICT mTLS · canary 90/10"], "measured v1=94, v2=6 of 100");
  feat(xs[1], top, "green", "Custom Metrics Autoscaler (KEDA)", ["notification-service scales on Kafka lag"], "0 to 1 in 15 s, back to 0 in ~3 min");
  feat(xs[2], top, "orange", "OpenTelemetry + otel-lgtm", ["agent injected by annotation, no image change"], "one trace: gateway, REST, gRPC");
  feat(xs[0], bot, "red", "Ollama + AI services", ["qwen2.5:3b · ai-mcp-service · ai-rules-service"], "classify, triage, MCP checks pass");
  feat(xs[1], bot, "tan", "Native build in the cluster", ["order-service · Mandrel 25.0 BuildConfig"], "0.075 s and 31 MiB vs 12.7 s, 325 MiB");
  feat(xs[2], bot, "gray", "OpenShift GitOps (Argo CD)", ["Application adopts the Helm release"], "self-heal restores deletes in 2-3 s");

  // core
  s.rect(30, 202, 1120, 160, "white");
  s.text(46, 228, "Core · project datamesh · restricted-v2", { size: 16, weight: 700, fill: "#5a3a0a" });
  const names = ["graphql-gateway", "order-service", "inventory-service", "payment-service", "shipping-service", "notification-service", "review-service"];
  const pw = 144, gap = 12, x0 = 46;
  names.forEach((n, i) => pillL(s, x0 + i * (pw + gap), 244, pw, n, i === 0 ? "blue" : "green", { h: 28, size: 12 }));
  pillL(s, 46, 292, 300, "AMQ Streams Kafka 4.2.0 (KRaft)", "red", { h: 30, size: 13 });
  pillL(s, 366, 292, 300, "Postgres 16 StatefulSet", "blue", { h: 30, size: 13 });
  pillL(s, 686, 292, 300, "Apicurio 3.2.4", "orange", { h: 30, size: 13 });
  s.text(1004, 313, "7 services", { size: 13, fill: "#666666", weight: 700 });

  // arrows from core to boxes
  xs.forEach((x) => {
    const cx = x + W / 2;
    s.arrow(cx, top + bh, cx, 202, { marker: "arrB", w: 1.6 });
    s.arrow(cx, 362, cx, bot, { marker: "arrB", w: 1.6 });
  });

  band(s, 30, 536, 1120, 44, "every operator pinned: Manual approval + startingCSV; teardown returns CRC to clean");
  s.text(590, 600, "OpenShift Local (CRC 4.22) · 12 vCPU / 32 GiB", { size: 13, anchor: "middle", fill: "#666666", italic: true });

  save("22-crc-platform-tier", s);
})();

console.log("DONE");
