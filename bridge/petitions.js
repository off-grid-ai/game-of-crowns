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
  justice({ p, c, opt, option, out, gold, world }) {
    const enemy = this.people[p.enemy];
    if (option === "side" || option === "other") {
      const winner = option === "side" ? c : enemy;
      const loser = option === "side" ? enemy : c;
      out.favour[winner.playerId] = 15;
      out.favour[loser.playerId] = -25;
      this.remember(winner.id, `The King took my side against ${loser.name}.`);
      this.remember(loser.id, `The King humiliated me before ${winner.name}.`);
      this.shift(loser.id, winner.id, -20);
      if (this.warlike(loser)) loser.goals.unshift({ kind: "revenge", text: `make ${winner.house} pay for what the King allowed` });
      out.text = `The King rules for ${winner.house}. ${loser.name} leaves the hall white with fury.`;
    } else if (option === "peace") {
      this.makeTruce(c, enemy, 8, world);
      out.favour[c.playerId] = -5;
      out.favour[enemy.playerId] = -5;
      out.text = `The King's peace is proclaimed between ${c.house} and ${enemy.house}. The crown pays for the burned barns. Neither lord smiles.`;
    } else if (option === "combat") {
      const cWins = Math.random() < 0.5 + (this.warlike(c) ? 0.1 : 0) - (this.warlike(enemy) ? 0.1 : 0);
      const winner = cWins ? c : enemy;
      const loser = cWins ? enemy : c;
      const lp = world.players.find((x) => x.id === loser.playerId);
      gold(loser.playerId, -Math.floor((lp?.gold ?? 0) / 3));
      gold(winner.playerId, Math.floor((lp?.gold ?? 0) / 3));
      out.favour[winner.playerId] = 10;
      out.favour[loser.playerId] = -10;
      const son = loser.children.map((id) => this.people[id]).find((k) => k?.alive && k.gender === "male" && k.age >= 16);
      if (son && Math.random() < 0.5) {
        son.alive = false;
        this.remember(loser.id, `My son ${son.name} died in the trial by combat the King allowed.`);
        out.text = `Trial by combat at Kingsmere. ${winner.house}'s champion stands over ${son.name}, son of ${loser.name}. The gods have spoken.`;
      } else {
        out.text = `Trial by combat at Kingsmere. ${winner.house}'s champion wins; ${loser.house} pays a third of its treasury.`;
      }
    }
  },
};
