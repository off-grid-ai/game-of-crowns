// Blight on the land: farmland round a town turned to desert or marsh (famine,
// plague), each tile's old ground written down, so the land grows back when its
// time comes (season.js healBlights). Freeciv has no "shrink this town" call: a
// blighted town really starves, and recovers when its fields return.

const FARMLAND = `n == "Grassland" or n == "Plains" or n == "Forest" or n == "Jungle" or n == "Swamp" or n == "Tundra"`;

// Turns farmland within the town's work radius into `into` (by `chance` a tile),
// logging the originals as a "blight" event (server.js keeps them) that grows back at turn + heal.
export function blightLua(id, into, chance, heal) {
  return `local c = find.city(nil, ${Number(id)}); if c then local s = {}; for t in c.tile:circle_iterate(5) do local n = t.terrain:rule_name(); if t ~= c.tile and (${FARMLAND}) and math.random() < ${Number(chance)} then s[#s + 1] = string.format("%d,%d,%s", t.x, t.y, n); edit.change_terrain(t, find.terrain("${String(into).replace(/[^A-Za-z ]/g, "")}")) end end; log.normal('EVENT {"turn":"%d","kind":"blight","city":"%d","tiles":"%s","heal":"%d"}', game.current_turn(), c.id, table.concat(s, ";"), game.current_turn() + ${Number(heal)}) end`;
}

// The ground as it was, tile by tile ("x,y,Terrain;…").
export function regrowLua(tiles) {
  return String(tiles ?? "").split(";").filter(Boolean).map((t) => {
    const [x, y, terrain] = t.split(",");
    return `local t = find.tile(${Number(x)}, ${Number(y)}); if t then edit.change_terrain(t, find.terrain("${terrain.replace(/[^A-Za-z ]/g, "")}")) end`;
  });
}
