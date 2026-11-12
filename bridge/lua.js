// The Lua the bridge sends Freeciv, written once (consolidation-plan B2).
const n = (v) => Number(v);

// Give (or take, with a negative amount) gold to a player: booked as the house's dealings this season
// (realmrules/script.lua realm_gold, the "income" report).
export const gold = (pid, amount) => `realm_gold(${n(pid)}, ${Math.round(n(amount))})`;

// Gold from one house to another (a debt paid, a tribute, a tithe returned): from's purse to to's.
export const pay = (from, to, amount) => `${gold(from, -n(amount))}; ${gold(to, n(amount))}`;

// Men raised in a town for its house, homed there (realmrules/script.lua realm_levy): kinds, one company each,
// "A|B" for the first of those the ruleset has; vet, their veteran level.
export const levy = (cityId, kinds, vet = 1) => `realm_levy(${n(cityId)}, "${kinds.join(",")}", ${n(vet)})`;

// A host raised beside a tile for a house (realm_host; who: a player id, or "dead" for the dead beyond the wall).
const whoLua = (who) => (who === "dead" ? "realm_the_dead()" : `realm_find_player(${n(who)})`);
export const host = (who, x, y, kinds, count) => `realm_host(${whoLua(who)}, ${n(x)}, ${n(y)}, {${kinds.map((k) => `"${k}"`).join(",")}}, ${n(count)})`;

// Men without banners raised beside a town (realm_raid: Freeciv's barbarians, a raid's season).
export const raid = (cityId) => `realm_raid(${n(cityId)})`;

// A building set down in a town, or taken up (realm_building).
export const building = (cityId, name, on = true) => `realm_building(${n(cityId)}, "${name}", ${on ? "true" : "false"})`;

// A house's fighting men taken off (realm_take_men): n of them, never its workers or scouts.
export const takeMen = (pid, count) => `realm_take_men(${n(pid)}, ${n(count)})`;

// A host company's season on the road, in Freeciv: tile by tile along the way the bridge found, stopping where the
// way is shut. A step is a real move (edit.unit_move: its own test of the tile, then its move handling, vision and
// huts), not a teleport, and costs no move points (the season's pace is the hosts' own). Arguments after the
// tile: move cost, embark_to, disembark, conquer_city, conquer_extra, enter_hut, frighten_hut.
const MOVE = "edit.unit_move, u, t, 0, nil, false, false, false, false, false";
export const walk = (id, tiles) => `local u = find.unit(nil, ${n(id)}); if u then for _, p in ipairs({${tiles.map(([x, y]) => `{${n(x)},${n(y)}}`).join(",")}}) do local t = find.tile(p[1], p[2]); if not t then break end; pcall(${MOVE}); if u.tile ~= t then break end end end`;

// With no way over land known: up to n steps, each to the neighbouring land tile nearest the goal, stopping `stop`
// tiles short of it (1 before another's walls).
export const step = (id, x, y, steps, stop = 0) => `local u = find.unit(nil, ${n(id)}); if u then for i = 1, ${n(steps)} do local c = u.tile; local t, bd = nil, math.max(math.abs(c.x - ${n(x)}), math.abs(c.y - ${n(y)})); if bd <= ${n(stop)} then break end; for a in c:square_iterate(1) do local nm = a.terrain:rule_name(); local d = math.max(math.abs(a.x - ${n(x)}), math.abs(a.y - ${n(y)})); if d < bd and not nm:find("Ocean") and nm ~= "Lake" then t, bd = a, d end end; if not t then break end; pcall(${MOVE}); if u.tile ~= t then break end end end`;

// The tithe's rate for the crown's purse each season (realmrules/script.lua realm_purse, which reports "purse").
export const titheRate = (rate) => `realm_tithe_rate(${n(rate)})`;

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

// The King's companies fall on the foe's men on a tile beside them (hosts.js attack): each strikes once by
// Freeciv's own Attack action (its enablers: war with the foe, moves left; its combat decides; a winner may march
// onto the tile, Freeciv's occupy chance), while any of the foe still stands there. Run on the season
// step, as the siege's assault is (at turn_begin Freeciv has not yet given the moves back).
export const strike = (ids, x, y) => `local t = find.tile(${n(x)}, ${n(y)}); local attack = find.action("Attack"); if t then for _, id in ipairs({${ids.map(n).join(",")}}) do local u = find.unit(nil, id); local foe = false; if u then for v in t:units_iterate() do if v.owner ~= u.owner then foe = true end end end; if foe and math.max(math.abs(u.tile.x - t.x), math.abs(u.tile.y - t.y)) == 1 then pcall(edit.perform_action, u, attack, t) end end end`;

// A great house split by Freeciv's civil war, its rebels raised and marching (realmrules/script.lua realm_rising):
// chance 0 lets Freeciv's own odds decide (its government, unhappy and celebrating towns). Reports "rising".
export const rising = (houseId, chance = 0) => `realm_rising(${n(houseId)}, ${n(chance)})`;
// Freeciv's own odds that the house splits if a rising is tried now (realm_rising_odds). Reports "rising_odds".
export const risingOdds = (houseId) => `realm_rising_odds(${n(houseId)})`;
// How a rising ends (id: the house it split, or its rebels): "return" (the towns go back to the lord), "keep" (the
// rebels a lesser house). Reports "rising_over".
export const risingEnd = (id, how) => `realm_rising_end(${n(id)}, "${how === "keep" ? "keep" : "return"}")`;

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
// The King's host takes ship and comes ashore (hosts.js crossing; realmrules/script.lua realm_ferry_raise, realm_ferry_land):
// the crown raises and pays for its Triremes on the water (x, y) and the host boards them by Freeciv's own Transport
// Board / Embark; ashore by Transport Disembark, the ships disbanded. Report "FERRY raise k of n", "FERRY board n of m",
// "FERRY land n of m".
export const ferryRaise = (pid, units, x, y, ships, cost) => `realm_ferry_raise(${n(pid)}, "${units.map(n).join(",")}", ${n(x)}, ${n(y)}, ${n(ships)}, ${n(cost)})`;
export const ferryLand = (units, x, y, hulls) => `realm_ferry_land("${units.map(n).join(",")}", ${n(x)}, ${n(y)}, "${hulls.map(n).join(",")}")`;
