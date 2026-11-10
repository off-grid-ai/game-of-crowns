// The Lua the bridge sends Freeciv, written once (consolidation-plan B2).
const n = (v) => Number(v);

// Give (or take, with a negative amount) gold to a player.
export const gold = (pid, amount) => `for p in players_iterate() do if p.id == ${n(pid)} then edit.change_gold(p, ${n(amount)}) end end`;

// Run a Lua body with c bound to the town, if it still stands.
export const inCity = (cityId, body) => `local c = find.city(nil, ${n(cityId)}); if c then ${body} end`;

// Hand a town to a player.
export const transferCity = (cityId, pid) => `local c = find.city(nil, ${n(cityId)}); local to; for p in players_iterate() do if p.id == ${n(pid)} then to = p end end; if c and to then edit.transfer_city(c, to) end`;
