// The Lua the bridge sends Freeciv, written once (consolidation-plan B2).
const n = (v) => Number(v);

// Give (or take, with a negative amount) gold to a player.
export const gold = (pid, amount) => `for p in players_iterate() do if p.id == ${n(pid)} then edit.change_gold(p, ${n(amount)}) end end`;

// Run a Lua body with c bound to the town, if it still stands.
export const inCity = (cityId, body) => `local c = find.city(nil, ${n(cityId)}); if c then ${body} end`;

// Hand a town to a player.
export const transferCity = (cityId, pid) => `local c = find.city(nil, ${n(cityId)}); local to; for p in players_iterate() do if p.id == ${n(pid)} then to = p end end; if c and to then edit.transfer_city(c, to) end`;

// A decree building set down in a town for its seasons (realmrules/script.lua realm_decree): "feast", "relief",
// "blight" (fate's, not the King's: half the town's food); seasons, if given, instead of luadata.txt's.
export const decree = (cityId, kind, seasons) => `realm_decree(${n(cityId)}, "${["relief", "blight"].includes(kind) ? kind : "feast"}"${seasons ? `, ${n(seasons)}` : ""})`;

// The King's soldiers beside a town he besieges strike it once each, and take it if no one is left
// (realmrules/script.lua realm_assault; Freeciv fights every blow and reports "assault").
export const assault = (cityId, crownId) => `realm_assault(${n(cityId)}, ${n(crownId)})`;

// A mark the houses (player ids) bear in their seat, felt in all their towns, lifted everywhere else
// (realmrules/script.lua realm_bear).
const bear = (name, pids) => `realm_bear("${name}", "${pids.map(n).join(",")}")`;
export const heavyTithe = (pids) => bear("Heavy Tithe", pids);
export const grievance = (pids) => bear("Grievance", pids);

// Men a decree sends home (hosts.js homeward orders; realmrules/script.lua): held from their house's AI,
// walked along `way` ([[x, y], ...]) by Freeciv's own moves, and disbanded into their seat's work.
export const homewardHold = (ids) => `realm_hold("${ids.map(n).join(",")}")`;
export const homewardStep = (id, way) => `realm_walk_home(${n(id)}, "${way.map(([x, y]) => `${n(x)},${n(y)}`).join(";")}")`;
export const disbandHome = (id, cityId) => `realm_disband_home(${n(id)}, ${n(cityId)})`;
export const homewardRelease = (ids) => `realm_release("${ids.map(n).join(",")}")`;
