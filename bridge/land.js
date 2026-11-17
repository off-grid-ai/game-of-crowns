// The land as a host walks it: one grid of the map (state/map.json), and how many steps over land each tile is from
// a goal. The one place this is worked out: hosts.js marches on it, fresh.js weighs the opening's foe by it.

// map: {width, height, tiles: [[x, y, terrain]]} -> {w, h, walk, sea}: walk 1 on land; sea 0 land, 1 coastal water
// (Ocean, Lake), 2 deep water.
export function grid(m) {
  if (!m?.tiles) return null;
  const walk = new Uint8Array(m.width * m.height);
  const sea = new Uint8Array(m.width * m.height);
  for (const [x, y, n] of m.tiles) {
    walk[y * m.width + x] = /Ocean|Lake/.test(String(n)) ? 0 : 1;
    sea[y * m.width + x] = /Deep Ocean/.test(String(n)) ? 2 : /Ocean|Lake/.test(String(n)) ? 1 : 0;
  }
  return { w: m.width, h: m.height, walk, sea };
}

// How many steps over land each tile is from a goal (breadth-first over the eight neighbours, as a unit moves in
// Freeciv), or null when the goal isn't on the land. shut: tiles ("x,y") no host can pass.
// {at: ({x, y}) -> steps, or -1 when the land doesn't reach, w, h}.
export function steps(L, goal, shut = null) {
  if (!L || goal.x < 0 || goal.y < 0 || goal.x >= L.w || goal.y >= L.h || !L.walk[goal.y * L.w + goal.x]) return null;
  const d = new Int32Array(L.w * L.h).fill(-1);
  const q = [goal.y * L.w + goal.x];
  d[q[0]] = 0;
  for (let i = 0; i < q.length; i++) {
    const x = q[i] % L.w, y = (q[i] / L.w) | 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= L.w || ny >= L.h) continue;
      const k = ny * L.w + nx;
      if (d[k] < 0 && L.walk[k] && !shut?.has(`${nx},${ny}`)) { d[k] = d[q[i]] + 1; q.push(k); }
    }
  }
  return { at: (p) => d[p.y * L.w + p.x], w: L.w, h: L.h };
}
