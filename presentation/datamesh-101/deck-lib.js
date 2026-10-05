// deck-lib.js — design-system helpers matched to the reference deck
// "Designing Cloud-Native APIs" (Red Hat brand). Reuses the extracted brand
// assets (illustration + logo) so branding is pixel-identical.
const pptxgen = require("pptxgenjs");
const fs = require("fs");

const DIMS = JSON.parse(fs.readFileSync("dpng/dims.json", "utf8"));
const IMG = (name) => `dpng/${name}.png`;

// brand assets extracted from the reference deck
const ILLUS = "brand-illustration.png"; // 2500x1407: left ~37% icon collage, right solid dark-red
const LOGO_DARK = "brand-logo-dark.png";   // black wordmark — for WHITE slides
const LOGO_LIGHT = "brand-logo-light.png";  // white wordmark — for DARK slides
const LOGO_AR = 496 / 117;

// ---- palette (from the reference deck) ----
const C = {
  red:    "EE0000",  // Red Hat Red — eyebrows, title-slide accents
  dkred:  "8A0000",  // (illustration's right side reads ~8A0000)
  ink:    "151515",  // near-black titles/body
  body:   "242424",  // body text
  gray:   "5A5A5A",  // muted
  gray2:  "8A8A8A",  // lighter muted (captions, lang labels)
  white:  "FFFFFF",
  paleR:  "FFD9D9",  // pale red (divider subtitle)
  paleR2: "F9E3E3",
  // code panel
  codeplate: "151515", // outer
  codebg:    "1A1A1A", // panel
  codefg:    "E6E6E6", // code text
  codecmt:   "8FB98F", // comments (sage green)
  codemut:   "8A8A8A", // lang label
};
const F = {
  head: "Overpass SemiBold",  // headers/eyebrows/titles
  body: "Red Hat Text",       // body
  mono: "Red Hat Mono",       // code + section numbers
};

const pres = new pptxgen();
pres.defineLayout({ name: "W", width: 13.333, height: 7.5 });
pres.layout = "W";
pres.author = "Robert Sedor";
pres.title = "Data Mesh on OpenShift";
const PW = 13.333, PH = 7.5;

const shadow = () => ({ type: "outer", color: "000000", blur: 8, offset: 3, angle: 90, opacity: 0.16 });

// ---- footer: page number (left) + Red Hat logo (right) ----
let PAGENO = 0;
function footer(slide, { dark = false } = {}) {
  PAGENO += 1;
  slide.addText(String(PAGENO), { x: 0.5, y: PH - 0.5, w: 1, h: 0.3, fontSize: 10, color: dark ? "FFFFFF" : C.gray2, fontFace: F.body, align: "left", margin: 0, transparency: dark ? 20 : 0 });
  const lw = 1.15, lh = lw / LOGO_AR;
  slide.addImage({ path: dark ? LOGO_LIGHT : LOGO_DARK, x: PW - 0.6 - lw, y: PH - 0.28 - lh, w: lw, h: lh });
}
function pageNumOnly(slide, { dark = false } = {}) {
  PAGENO += 1;
  slide.addText(String(PAGENO), { x: 0.5, y: PH - 0.5, w: 1, h: 0.3, fontSize: 10, color: dark ? "FFFFFF" : C.gray2, fontFace: F.body, align: "left", margin: 0, transparency: dark ? 20 : 0 });
}

// ---- TITLE slide: left illustration panel, right title block + logo ----
function titleSlide({ eyebrow, title, subtitle, tagline, breadcrumb, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  // left ~37% of the illustration holds the icon collage; crop the image so that
  // collage fills a left panel. Image is 2500x1407; left 37% = ~925px.
  const panelW = PW * 0.37;
  // sizingType crop: show only the left portion
  s.addImage({ path: ILLUS, x: 0, y: 0, w: panelW, h: PH, sizing: { type: "crop", w: panelW, h: PH, x: 0, y: 0 } });
  const rx = panelW + 0.7;
  const rw = PW - rx - 0.7;
  s.addText((eyebrow || "THE DATA MESH").toUpperCase(), { x: rx, y: 1.7, w: rw, h: 0.4, fontSize: 14, color: C.red, fontFace: F.head, bold: true, charSpacing: 3, margin: 0 });
  s.addText(title, { x: rx, y: 2.1, w: rw, h: 1.9, fontSize: 38, color: C.ink, fontFace: F.head, bold: true, valign: "top", margin: 0, lineSpacingMultiple: 1.0 });
  if (subtitle) s.addText(subtitle, { x: rx, y: 4.3, w: rw, h: 1.0, fontSize: 17, color: C.gray, fontFace: F.body, italic: true, valign: "top", margin: 0 });
  if (tagline) s.addText(tagline, { x: rx, y: 5.45, w: rw, h: 0.4, fontSize: 15, color: C.ink, fontFace: F.body, bold: true, valign: "top", margin: 0 });
  if (breadcrumb) s.addText(breadcrumb, { x: rx, y: 5.85, w: rw, h: 0.4, fontSize: 13, color: C.gray2, fontFace: F.body, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / LOGO_AR;
  s.addImage({ path: LOGO_DARK, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  if (notes) s.addNotes(notes);
  return s;
}

// ---- AGENDA slide: eyebrow + title + two columns of numbered items ----
function agendaSlide({ left, right, appendix, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  s.addText("AGENDA", { x: 0.7, y: 0.45, w: PW - 1.4, h: 0.32, fontSize: 12, color: C.red, fontFace: F.head, bold: true, charSpacing: 2, margin: 0 });
  s.addText("Agenda", { x: 0.7, y: 0.78, w: PW - 1.4, h: 0.9, fontSize: 34, color: C.ink, fontFace: F.head, bold: true, valign: "top", margin: 0 });
  const mkRuns = (items) => items.map((it) => ({
    text: it.text,
    options: { bullet: { indent: 16 }, color: C.ink, fontFace: F.body, fontSize: 17, paraSpaceAfter: 12, breakLine: true, italic: !!it.italic, ...(it.italic ? { color: C.gray } : {}) },
  }));
  s.addText(mkRuns(left), { x: 0.7, y: 1.95, w: 5.6, h: 4.6, valign: "top", margin: 0 });
  s.addText(mkRuns(right), { x: 6.7, y: 1.95, w: 6.0, h: 4.6, valign: "top", margin: 0 });
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// ---- SECTION DIVIDER: full illustration bg (dark-red right), mono number, white title ----
function divider({ num, title, sub }) {
  const s = pres.addSlide();
  // full-bleed illustration: left collage + right solid dark-red carries the text
  s.addImage({ path: ILLUS, x: 0, y: 0, w: PW, h: PH, sizing: { type: "cover", w: PW, h: PH } });
  const rx = PW * 0.42;
  const rw = PW - rx - 0.7;
  s.addText(num, { x: rx, y: 2.7, w: rw, h: 0.5, fontSize: 22, color: C.white, fontFace: F.mono, bold: true, margin: 0 });
  s.addText(title, { x: rx, y: 3.2, w: rw, h: 1.7, fontSize: 40, color: C.white, fontFace: F.head, bold: true, valign: "top", margin: 0, lineSpacingMultiple: 1.0 });
  if (sub) s.addText(sub, { x: rx, y: 4.95, w: rw, h: 0.8, fontSize: 16, color: C.paleR, fontFace: F.body, italic: true, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / LOGO_AR;
  s.addImage({ path: LOGO_LIGHT, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  PAGENO += 1; // dividers count but show no number
  return s;
}

// ---- eyebrow + title block for a content slide ----
// With a subtitle the title box shrinks to 0.6in and the subtitle sits at y 1.36.
function head(s, eyebrow, title, { titleH = 0.95, subtitle } = {}) {
  s.addText(eyebrow.toUpperCase(), { x: 0.7, y: 0.45, w: PW - 1.4, h: 0.32, fontSize: 12, color: C.red, fontFace: F.head, bold: true, charSpacing: 2, margin: 0 });
  s.addText(title, { x: 0.7, y: 0.78, w: PW - 1.4, h: subtitle ? 0.6 : titleH, fontSize: 30, color: C.ink, fontFace: F.head, bold: true, valign: "top", margin: 0 });
  if (subtitle) s.addText(subtitle, { x: 0.7, y: 1.36, w: PW - 1.4, h: 0.4, fontSize: 17, color: C.gray, fontFace: F.body, valign: "top", margin: 0 });
}

// ---- 8pt reference to the demo script, bottom of the slide ----
function addDemoRef(s, ref) {
  if (!ref) return;
  s.addText("Demo script: " + ref, { x: 1.6, y: PH - 0.47, w: 7.5, h: 0.25, fontSize: 8, color: C.gray2, fontFace: F.mono, align: "left", valign: "middle", margin: 0 });
}

// ---- CONTENT slide ----
function contentSlide({ eyebrow, title, subtitle, demoRef, bullets, bulletsX = 0.7, bulletsW = PW - 1.4, bulletsY, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title, { subtitle });
  const by = bulletsY !== undefined ? bulletsY : (subtitle ? 2.15 : 1.95);
  if (bullets) addBullets(s, bullets, { x: bulletsX, y: by, w: bulletsW, h: subtitle ? 4.5 : 4.6 });
  addDemoRef(s, demoRef);
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// Bullet items: { text, lvl, color, head, lead }. `lead` is a bold subject run
// (C.ink) at the start of the same paragraph, followed by `text`.
function addBullets(s, bullets, { x, y, w, h = 4.6, fontSize = 16 }) {
  const runs = [];
  bullets.forEach((b, i) => {
    const lvl = b.lvl || 0;
    if (b.head) {
      runs.push({ text: b.text, options: { bold: true, color: C.ink, fontFace: F.head, fontSize: fontSize + 1, bullet: false, breakLine: true, paraSpaceBefore: i ? 8 : 0, paraSpaceAfter: 4 } });
      return;
    }
    const para = {
      fontFace: F.body, fontSize: lvl ? fontSize - 1 : fontSize,
      bullet: { indent: 18 }, indentLevel: lvl,
      paraSpaceBefore: lvl ? 0 : 4, paraSpaceAfter: lvl ? 8 : 14,
    };
    const color = b.color || (lvl ? C.gray : C.body);
    if (b.lead) {
      runs.push({ text: b.lead, options: { ...para, bold: true, color: C.ink } });
      runs.push({ text: (b.sep === undefined ? " " : b.sep) + b.text, options: { fontFace: F.body, fontSize: para.fontSize, color, breakLine: true } });
    } else {
      runs.push({ text: b.text, options: { ...para, color, breakLine: true } });
    }
  });
  s.addText(runs, { x, y, w, h, valign: "top", margin: 0 });
}

// ---- DIAGRAM slide ----
function diagramSlide({ eyebrow, title, subtitle, demoRef, image, caption, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title, { subtitle });
  const d = DIMS[image];
  const maxH = subtitle ? 4.05 : 4.3, maxW = PW - 1.6;
  let w = maxW, h = w * (d.h / d.w);
  if (h > maxH) { h = maxH; w = h * (d.w / d.h); }
  const x = (PW - w) / 2, y = (subtitle ? 2.05 : 1.8) + (maxH - h) / 2;
  s.addImage({ path: IMG(image), x, y, w, h });
  if (caption) s.addText(caption, { x: 0.8, y: PH - 1.0, w: PW - 1.6, h: 0.5, fontSize: 12.5, color: C.gray, fontFace: F.body, italic: true, align: "center", valign: "top", margin: 0 });
  addDemoRef(s, demoRef);
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// ---- CODE slide: full-width rounded dark panel, explanation in caption below ----
function codeSlide({ eyebrow, title, subtitle, demoRef, lang, code, note, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title, { subtitle });
  const px = 0.7, py = subtitle ? 2.1 : 1.85, pw = PW - 1.4, ph = (note ? 4.1 : 4.55) - (subtitle ? 0.25 : 0);
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: px, y: py, w: pw, h: ph, rectRadius: 0.12, fill: { color: C.codebg }, line: { type: "none" }, shadow: shadow() });
  if (lang) s.addText(lang, { x: px + pw - 3.2, y: py + 0.14, w: 3.0, h: 0.28, fontSize: 11, color: C.codemut, fontFace: F.mono, align: "right", margin: 0 });
  // colorize and auto-size font to fit panel height
  const runs = buildCodeRuns(code);
  const lineCount = code.split("\n").length;
  const topPad = 0.42, botPad = 0.25;
  const avail = ph - topPad - botPad;
  let fs = 13;
  const lineIn = (f) => (f * 1.12 * 1.16) / 72; // fontSize * lineSpacing * em→in
  while (lineCount * lineIn(fs) > avail && fs > 7.5) fs -= 0.5;
  runs.forEach((r) => { r.options.fontSize = fs; });
  s.addText(runs, { x: px + 0.35, y: py + topPad, w: pw - 0.7, h: avail, valign: "top", margin: 0, lineSpacingMultiple: 1.12 });
  if (note) s.addText(note, { x: px, y: py + ph + 0.18, w: pw, h: 0.8, fontSize: 13, color: C.gray, fontFace: F.body, italic: true, valign: "top", margin: 0 });
  addDemoRef(s, demoRef);
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// ---- TABLE slide: titled slide with a pptxgenjs table in house style ----
function tableSlide({ eyebrow, title, subtitle, demoRef, headers, rows, note, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title, { subtitle });
  const tx = 0.7, ty = subtitle ? 2.15 : 1.95, tw = PW - 1.4;
  const colCount = (headers && headers.length) || (rows && rows[0] && rows[0].length) || 1;
  const colW = Array(colCount).fill(tw / colCount);
  const cellOpts = { fontFace: F.body, fontSize: 13, align: "left", valign: "middle" };
  const tableRows = [];
  if (headers) {
    tableRows.push(headers.map((h) => ({
      text: h,
      options: { ...cellOpts, bold: true, color: C.white, fill: { color: C.red }, fontSize: 14 },
    })));
  }
  (rows || []).forEach((r, i) => {
    const fill = i % 2 === 1 ? C.paleR2 : C.white;
    tableRows.push(r.map((cell) => ({
      text: String(cell),
      options: { ...cellOpts, color: C.body, fill: { color: fill } },
    })));
  });
  s.addTable(tableRows, {
    x: tx, y: ty, w: tw, colW,
    autoPage: false,
    rowH: 0.5,
    border: { type: "solid", color: "E6E6E6", pt: 0.75 },
    margin: [4, 8, 4, 8],
  });
  if (note) s.addText(note, { x: tx, y: PH - 1.05, w: tw, h: 0.45, fontSize: 13, color: C.gray, fontFace: F.body, italic: true, valign: "top", margin: 0 });
  addDemoRef(s, demoRef);
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// ---- GLOSSARY slide: two columns of bold term + short definition ----
function glossarySlide({ eyebrow, title, terms, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title);
  const nLeft = Math.ceil(terms.length / 2);
  const cols = [terms.slice(0, nLeft), terms.slice(nLeft)];
  const xs = [0.7, 6.85];
  cols.forEach((col, ci) => {
    const runs = [];
    col.forEach((t) => {
      runs.push({ text: t.term, options: { bold: true, color: C.ink, fontFace: F.head, fontSize: 15, breakLine: true, paraSpaceAfter: 2 } });
      runs.push({ text: t.def, options: { color: C.body, fontFace: F.body, fontSize: 13, breakLine: true, paraSpaceAfter: 14 } });
    });
    s.addText(runs, { x: xs[ci], y: 1.85, w: 5.8, h: 4.9, valign: "top", margin: 0 });
  });
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// split code into colored runs: full-line comments and inline (# ...) → green
function buildCodeRuns(code) {
  const runs = [];
  const lines = code.split("\n");
  lines.forEach((ln, i) => {
    const br = i < lines.length - 1;
    // find inline comment (# not inside quotes — simple heuristic)
    const hashIdx = findComment(ln);
    if (hashIdx === 0) {
      runs.push({ text: ln, options: { color: C.codecmt, fontFace: F.mono, breakLine: br } });
    } else if (hashIdx > 0) {
      runs.push({ text: ln.slice(0, hashIdx), options: { color: C.codefg, fontFace: F.mono, breakLine: false } });
      runs.push({ text: ln.slice(hashIdx), options: { color: C.codecmt, fontFace: F.mono, breakLine: br } });
    } else {
      runs.push({ text: ln || " ", options: { color: C.codefg, fontFace: F.mono, breakLine: br } });
    }
  });
  return runs;
}
function findComment(ln) {
  let inS = false, q = "";
  for (let i = 0; i < ln.length; i++) {
    const c = ln[i];
    if (inS) { if (c === q) inS = false; }
    else if (c === '"' || c === "'") { inS = true; q = c; }
    else if (c === "#") {
      // treat as comment only if preceded by whitespace or start (avoid '#' in URLs/strings)
      if (i === 0 || /\s/.test(ln[i - 1])) return i === 0 ? 0 : i;
    }
  }
  return -1;
}

// pptxgenjs emits a paragraph-properties block for every run; a second block in
// the same paragraph (the text run after a bold lead) overrides the first and
// drops the bullet. Keep only the first <a:pPr> in each paragraph, then write.
async function writeDeck(fileName) {
  const JSZip = require("jszip");
  const buf = await pres.write({ outputType: "nodebuffer" });
  const zip = await JSZip.loadAsync(buf);
  const re = /<a:pPr\b[^>]*>[\s\S]*?<\/a:pPr>/g;
  for (const name of Object.keys(zip.files)) {
    if (!/^ppt\/slides\/slide\d+\.xml$/.test(name)) continue;
    const xml = await zip.file(name).async("string");
    const out = xml.split("<a:p>").map((chunk, i) => {
      if (i === 0) return chunk;
      let n = 0;
      return chunk.replace(re, (m) => (n++ === 0 ? m : ""));
    }).join("<a:p>");
    zip.file(name, out);
  }
  fs.writeFileSync(fileName, await zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" }));
  return fileName;
}

module.exports = { writeDeck, pres, C, F, PW, PH, titleSlide, agendaSlide, divider, contentSlide, diagramSlide, codeSlide, tableSlide, glossarySlide, addDemoRef, head, addBullets, footer, pageNumOnly, DIMS, IMG, LOGO_DARK, LOGO_LIGHT, LOGO_AR, ILLUS };
