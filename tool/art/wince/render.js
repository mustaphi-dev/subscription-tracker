// Renders SVGs to PNGs with the preinstalled Chromium (require('playwright')).
// usage: node render.js '[["in.svg","out.png",widthPx], ...]'
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const b = await chromium.launch();
  for (const [f, out, px] of JSON.parse(process.argv[2])) {
    let svg = fs.readFileSync(f, 'utf8');
    const vb = svg.match(/viewBox="([^"]+)"/)[1].split(/\s+/).map(Number);
    const w = px, h = Math.round(px * vb[3] / vb[2]);
    svg = svg.replace(/ width="\d+" height="\d+"/, '').replace('<svg ', `<svg width="${w}" height="${h}" `);
    const p = await b.newPage({ viewport: { width: w, height: h } });
    await p.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await p.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
    await p.close();
  }
  await b.close();
})();
