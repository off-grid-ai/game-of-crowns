// Pure geometry of the valley: terrain height, river, buildable land.
// No three.js here so the simulation can run headless in node.

const SEED = 1337;

export function smooth(a, b, x) {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

export function lerp(a, b, t) {
  return a + (b - a) * t;
}

function hash(i, j) {
  let h = (Math.imul(i, 374761393) + Math.imul(j, 668265263) + Math.imul(SEED, 982451653)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

function vnoise(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

export function fbm(x, y, octaves = 5) {
  let sum = 0, amp = 0.5, freq = 1, norm = 0;
  for (let i = 0; i < octaves; i++) {
    sum += amp * vnoise(x * freq, y * freq);
    norm += amp;
    amp *= 0.5;
    freq *= 2.03;
  }
  return sum / norm;
}

export const WORLD_SIZE = 260;
export const WATER_LEVEL = 0;
export const KEEP_POS = { x: 0, z: -24 };
export const SQUARE_POS = { x: 0, z: 2 };
export const QUARRY_POS = { x: -34, z: -62 };
export const PASTURE = { x: 44, z: -6, r: 13 };

export function riverZ(x) {
  return 42 + 9 * Math.sin(x * 0.028) + 4 * Math.sin(x * 0.07 + 1.3);
}

export function height(x, z) {
  const r = Math.hypot(x, z + 5);
  let h = 1.2 + (fbm(x * 0.015 + 10, z * 0.015 + 10) - 0.5) * 7 * smooth(22, 70, r);
  h += (fbm(x * 0.05, z * 0.05, 3) - 0.5) * 0.6;
  const m = fbm(x * 0.02 + 50, z * 0.02 + 50);
  h += smooth(85, 128, r) * (8 + m * 40);
  h += smooth(-42, -115, z) * (6 + m * 38);
  // Small rise for the keep to sit on.
  h += 2.2 * (1 - smooth(6, 16, Math.hypot(x - KEEP_POS.x, z - KEEP_POS.z)));
  const bank = smooth(3.5, 11, Math.abs(z - riverZ(x)));
  return lerp(-1.8, h, bank);
}

export function riverDistance(x, z) {
  return Math.abs(z - riverZ(x));
}

export function isBuildable(x, z, half = 2) {
  if (riverDistance(x, z) < 10 + half) return false;
  if (Math.hypot(x, z) > 72) return false;
  const h = height(x, z);
  if (h < 0.6 || h > 7) return false;
  for (const [dx, dz] of [[half, half], [-half, half], [half, -half], [-half, -half]]) {
    if (Math.abs(height(x + dx, z + dz) - h) > 1.6) return false;
  }
  return true;
}
