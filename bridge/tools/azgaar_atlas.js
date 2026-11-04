// Draws the realm's atlas from Azgaar's own map data (the Full JSON export) as
// an SVG in Azgaar's map coordinates, so it lines up exactly with the land the
// game builds from the same map: biome colours cell by cell, the sea graded by
// depth, lakes, coastlines and rivers swelling with their discharge. The game
// drapes it over the land when the camera pulls back (terrain.gdshader).
//
//   node tools/azgaar_atlas.js "data/Belia Full ….json" out.svg
// then shade and rasterise: tools/make_atlas.sh

import fs from "fs";

const [src, out] = process.argv.slice(2);
const d = JSON.parse(fs.readFileSync(src, "utf8"));
const { cells, vertices, biomes, features, rivers } = d.pack;
const W = d.info.width;
const H = d.info.height;
const SEA = 20;

const hex = (c) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
const css = (rgb) => `rgb(${rgb.map((v) => Math.round(Math.max(0, Math.min(255, v)))).join(",")})`;
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * Math.max(0, Math.min(1, t)));

// Azgaar's palette, a touch deeper so it holds up under daylight in the game.
const OCEAN_SHALLOW = [150, 182, 205];
const OCEAN = [88, 128, 175];
const OCEAN_DEEP = [52, 86, 135];
const LAKE = [120, 160, 200];
const RIVER = [90, 130, 185];
const COAST = [52, 58, 62];

const poly = (c) => c.v.map((v) => vertices[v].p.map((n) => n.toFixed(2)).join(",")).join(" ");

const parts = [];
parts.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`);
parts.push(`<rect width="${W}" height="${H}" fill="${css(OCEAN_DEEP)}"/>`);

// Cells. A thin stroke in the fill's own colour closes the hairline gaps
// between neighbouring polygons.
const fills = new Map();
for (const c of cells) {
  let rgb;
  const f = features[c.f];
  if (c.h < SEA) {
    if (f && f.type === "lake") rgb = LAKE;
    else {
      // Shallows by the shore (t = -1, -2 …), deep water further out.
      const depth = Math.max(0, -c.t - 1);
      rgb = depth < 1 ? OCEAN_SHALLOW : mix(OCEAN, OCEAN_DEEP, (depth - 1) / 5);
    }
  } else {
    const b = biomes[c.biome] || biomes[4];
    // Higher ground pales toward stone, as Azgaar's relief tint does.
    // Azgaar's biome colours, muted toward parchment so the map reads as ink
    // on paper; higher ground pales toward stone, as Azgaar's relief tint does.
    rgb = mix(mix(hex(b.color), [206, 196, 164], 0.34), [196, 190, 176], (c.h - 55) / 40);
  }
  const key = css(rgb);
  if (!fills.has(key)) fills.set(key, []);
  fills.get(key).push({ pts: poly(c), wet: c.h < SEA && !(f && f.type === "lake") });
}
// The sea is drawn soft (Azgaar's depth bands are smooth curves, not cells),
// the land crisp on top of it.
parts.push(`<defs><filter id="soft" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="3"/></filter></defs>`);
for (const wet of [true, false]) {
  parts.push(wet ? `<g filter="url(#soft)">` : `<g>`);
  for (const [fill, ps] of fills) {
    const mine = ps.filter((p) => p.wet === wet);
    if (!mine.length) continue;
    parts.push(`<g fill="${fill}" stroke="${fill}" stroke-width="0.6" stroke-linejoin="round">`);
    for (const p of mine) parts.push(`<polygon points="${p.pts}"/>`);
    parts.push(`</g>`);
  }
  parts.push(`</g>`);
}

// Coastlines and lake shores: the edges between land and water cells.
const shore = [];
for (const c of cells) {
  if (c.h < SEA) continue;
  c.c.forEach((n) => {
    if (cells[n].h >= SEA) return;
    const shared = c.v.filter((v) => cells[n].v.includes(v));
    if (shared.length === 2) shore.push(`M${vertices[shared[0]].p.join(",")}L${vertices[shared[1]].p.join(",")}`);
  });
}
parts.push(`<path d="${shore.join("")}" stroke="${css(COAST)}" stroke-width="0.45" stroke-opacity="0.7" fill="none" stroke-linecap="round"/>`);

// Rivers: through their cells' centres, smoothed, widening downstream.
for (const r of rivers) {
  if (!r || !r.cells || r.cells.length < 3 || r.discharge < 40) continue;
  const pts = r.cells.filter((i) => i >= 0 && cells[i]).map((i) => cells[i].p);
  if (pts.length < 3) continue;
  let dpath = `M${pts[0].join(",")}`;
  for (let i = 1; i < pts.length - 1; i++) {
    const m = [(pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2];
    dpath += `Q${pts[i].join(",")} ${m.join(",")}`;
  }
  dpath += `L${pts[pts.length - 1].join(",")}`;
  const w = Math.min(2.2, 0.25 + Math.sqrt(r.discharge) / 90);
  parts.push(`<path d="${dpath}" stroke="${css(RIVER)}" stroke-width="${w.toFixed(2)}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`);
}

parts.push(`</svg>`);
fs.writeFileSync(out, parts.join("\n"));
console.log(`atlas: ${cells.length} cells, ${fills.size} colours, ${shore.length} shore edges -> ${out}`);
