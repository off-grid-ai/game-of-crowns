// The court's answers, one handler per kind of petition (consolidation B6):
// answer(kind) is looked up here first; kinds not yet moved fall through to
// characters.js's own chain. Each runs as the court (`this`), with the
// petition, the petitioner, the option chosen, the result being built, a
// gold() helper and the world.
import { cityName, houseFor } from "./narrator.js";

export const ANSWERS = {
  siege({ p, c, option, out, gold, world }) {
    const town = cityName(p.city);
    const them = houseFor(world.players.find((x) => x.id === p.besieger) ?? {}).name;
    if (option === "relieve") {
      out.favour[c.playerId] = 15; out.favour[p.besieger] = -20;
      out.march = p.city;  // the bridge sends the royal host (its own march decree)
      out.text = `The royal host marches to break the siege of ${town}.`;
    }
    if (option === "pay") {
      out.favour[c.playerId] = 5; out.favour[p.besieger] = 5; out.cost = 200;
      gold(p.besieger, 200);
      const foeLord = this.lordOfHouse(p.besieger);
      if (foeLord) this.makeTruce(c, foeLord, 8, world);  // Freeciv's ceasefire: their host goes home
      out.text = `The crown's gold buys ${them} off. Their host leaves ${town}'s walls.`;
    }
    if (option === "abandon") {
      out.favour[c.playerId] = -20;
      for (const b of this.alive().filter((x) => x.rank === "bannerman" && x.playerId === c.playerId)) b.loyalty = Math.max(0, b.loyalty - 10);
      out.text = `The King sends no one. ${town} is left to hold, or to fall.`;
    }
    this.remember(c.id, option === "abandon" ? `The King left ${town} to ${them}.` : `The King came to ${town}'s aid against ${them}.`);
  },
  grain({ p, c, option, out, gold, world }) {
    if (option === "grant") { out.favour[c.playerId] = 15; gold(c.playerId, 150); out.text = `The crown sends grain to ${c.house}.`; }
    if (option === "order") { out.favour[p.donor] = -20; out.favour[c.playerId] = 10; gold(p.donor, -150); gold(c.playerId, 150); out.text = `By royal command, ${houseFor(world.players.find((x) => x.id === p.donor)).name} feeds the starving of ${c.house}, and resents every sack.`; }
    if (option === "refuse") {
      out.favour[c.playerId] = -15;
      for (const b of this.alive().filter((x) => x.rank === "bannerman" && x.playerId === c.playerId)) b.loyalty = Math.max(0, b.loyalty - 15);
      out.text = `The King refuses grain. In ${c.house}'s lands, the bannermen begin to talk.`;
    }
    this.remember(c.id, option === "refuse" ? "The King let my people starve." : "The King fed my people when they starved.");
  },
  claim({ p, c, opt, option, out, gold, world }) {
    const k = p.claim;
    k.settled = true;
    const town = cityName(k.city);
    const move = (to) => out.lua.push(`local c = find.city(nil, ${k.city}); local to; for p in players_iterate() do if p.id == ${to} then to = p end end; if c and to then edit.transfer_city(c, to) end`);
    if (option === "return") { move(k.from); out.favour[k.from] = 20; out.favour[k.to] = -30; out.text = `By the King's judgment, ${town} is returned to ${c.house}.`; }
    if (option === "confirm") { out.favour[k.to] = 15; out.favour[k.from] = -30; for (const b of this.alive().filter((x) => x.rank === "bannerman")) b.loyalty = Math.max(0, b.loyalty - 5); out.text = `The King confirms ${town} to its new masters. Bannermen across the realm take note.`; }
    if (option === "seize") { const crown = world.players.find((x) => houseFor(x).crown); if (crown) move(crown.id); out.favour[k.from] = -20; out.favour[k.to] = -20; out.text = `The King takes ${town} for the crown. Neither house is pleased.`; }
  },
};
