// raster.js — rasterize this repo's architecture diagrams (assets/diagrams/*.svg)
// into this deck's local dpng/ as PNGs, and write dpng/dims.json for deck-lib.js.
// Uses sharp at 200 DPI, flattened onto white. Adapted from
// datamesh-reference-arch-python/presentation/data-mesh-openshift/raster.js,
// pointed at datamesh-reference-arch-quarkus's own diagrams instead of that
// repo's dimg/ export.
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');
const dir = '/home/rsedor/Dev/datamesh-reference-arch-quarkus/assets/diagrams';
const out = 'dpng';
if (!fs.existsSync(out)) fs.mkdirSync(out);
(async () => {
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.svg'));
  const dims = {};
  for (const f of files) {
    const base = f.replace('.svg', '');
    const svg = fs.readFileSync(path.join(dir, f));
    // render at ~2x for crispness; flatten onto white
    const img = sharp(svg, { density: 200 }).flatten({ background: '#ffffff' });
    const buf = await img.png().toBuffer();
    fs.writeFileSync(path.join(out, base + '.png'), buf);
    const m2 = await sharp(buf).metadata();
    dims[base] = { w: m2.width, h: m2.height };
    console.log(base, m2.width + 'x' + m2.height);
  }
  fs.writeFileSync(path.join(out, 'dims.json'), JSON.stringify(dims, null, 2));
  console.log(`wrote dpng/dims.json (${files.length} entries)`);
})();
