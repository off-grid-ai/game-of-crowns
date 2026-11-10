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
  remembers({ p, c, opt, option, out, gold, world }) {
    const deed = (this.deedsOf?.(c.playerId) ?? []).find((x) => x.what === p.deed);
    if (option === "amend") { out.favour[c.playerId] = 15; gold(c.playerId, 120); if (deed) { deed.d = Math.round(deed.d * 0.3); deed.mended = world.turn; } this.remember(c.id, "The King made amends for what was done to my house. It is settled, for now."); out.text = `The King makes amends to ${c.house}. ${c.name} takes the gold and, for now, lets the old wound close.`; }
    if (option === "hear") { out.favour[c.playerId] = 3; out.text = `The King hears ${c.name} out and promises nothing. ${c.house} goes home with its grudge.`; }
    if (option === "firm") { out.favour[c.playerId] = -8; this.remember(c.id, "I reminded the King what he did to my house. He said the crown did what it must."); if (this.warlike(c)) c.goals.unshift({ kind: "revenge", text: "make the crown answer for what it did to my house" }); out.text = `"The crown did what it must." ${c.name} bows, and adds it to the account.`; }
    if (option === "oath") { out.favour[c.playerId] = 6; c.loyalty = Math.min(100, c.loyalty + 10); out.text = `${c.name} kneels and swears ${c.house} to the crown before the whole court.`; }
    if (option === "purse") { out.favour[c.playerId] = -4; gold(c.playerId, -60); const crown = world.players.find((x) => houseFor(x).crown); if (crown) gold(crown.id, 60); out.text = `${c.house} sends 60 gold to Kingsmere. ${c.name} had hoped for thanks, not a bill.`; }
    this.save(c);
  },
  match({ p, c, opt, option, out, gold, world }) {
    const bride = this.people[p.bride];
    const groom = this.people[p.groom];
    const father = this.people[bride.parents[0]];
    const groomLord = this.lordOfHouse(this.people[groom.parents?.[0]]?.playerId ?? -1);
    if (option === "bless") {
      bride.spouse = groom.id; groom.spouse = bride.id; bride.house = groom.house;
      father.loyalty = Math.max(0, father.loyalty - 20);
      if (groomLord) { out.favour[groomLord.playerId] = 10; this.shift(father.id, groomLord.id, 30); }
      out.favour[c.playerId] = -10;
      out.text = `${bride.name} weds ${groom.name} with the King's blessing. ${c.name} smiles thinly.`;
    } else if (option === "forbid") {
      out.favour[c.playerId] = 10;
      if (groomLord) out.favour[groomLord.playerId] = -10;
      this.remember(father.id, "The King forbade my daughter's match.");
      out.text = `The King forbids the match. ${father.name} bows, and does not forget.`;
    } else {
      bride.rank = "ward";
      this.remember(father.id, "The King took my daughter as a royal ward. My house owes the crown.");
      father.loyalty = Math.min(100, father.loyalty + 10);
      out.text = `${bride.name} goes to Kingsmere as a royal ward.`;
    }
    this.save(bride); this.save(groom); this.save(father);
  },
  debt({ p, c, opt, option, out, gold, world }) {
    if (option === "forgive") { gold(c.playerId, 100); out.favour[c.playerId] = 15; for (const o of world.players) if (o.id !== c.playerId && !houseFor(o).crown && !houseFor(o).wild) out.favour[o.id] = -3; out.text = `The crown returns ${c.house}'s tithe. The other houses grumble that they were not asked.`; }
    if (option === "lend") { gold(c.playerId, 250); out.favour[c.playerId] = 5; (this.debts ??= []).push({ pid: c.playerId, amount: 325, due: (world.turn ?? 0) + 8 }); out.text = `The crown lends ${c.house} 250 gold. The debt is written in the King's ledger: 325, due in two years.`; }
    if (option === "refuse") { out.favour[c.playerId] = c.traits.includes("proud") ? -18 : -10; this.remember(c.id, "I begged the King for relief and was told to pay like everyone else."); out.text = `The King refuses. ${c.house} pays its share, and its lord counts every coin.`; }
  },
  outlaws({ p, c, opt, option, out, gold, world }) {
    const town = cityName(p.city);
    if (option === "hunt") { out.favour[c.playerId] = 15; out.lua.push(`local c = find.city(nil, ${p.city}); if c then local t = find.unit_type("Knights") or find.unit_type("Horsemen"); for i = 1, 3 do edit.create_unit(c.owner, c.tile, t, 1, c, -1) end end`); out.text = `The King's riders clear the forest road outside ${town}. The oaks bear different fruit now.`; }
    if (option === "pardon") { out.favour[c.playerId] = -15; const crown = world.players.find((x) => houseFor(x).crown); const seat = crown && world.cities.find((x) => x.owner === crown.id); if (seat) out.lua.push(`local c = find.city(nil, ${seat.id}); if c then for i = 1, 2 do edit.create_unit(c.owner, c.tile, find.unit_type("Archers") or find.unit_type("Warriors"), 0, c, -1) end end`); this.remember(c.id, `The King pardoned the outlaws who hanged my men outside ${town}, and put them in royal colours.`); out.text = `The outlaws of ${town} kneel and are pardoned. They march to Kingsmere in the King's colours. ${c.house} does not forgive it.`; }
    if (option === "theirs") { out.favour[c.playerId] = -5; gold(c.playerId, -60); out.text = `The King tells ${c.name} to keep his own roads. The outlaws keep the road, and the taxes of ${town} keep going into the forest.`; }
  },
  informer({ p, c, opt, option, out, gold, world }) {
    const informer = this.people[p.informer];
    const suspect = this.people[p.suspect];
    const heir = this.people[p.heir];
    if (option === "hostage") { out.favour[suspect.playerId] = -20; suspect.hostage = heir.id; heir.rank = heir.rank === "heir" ? "heir" : heir.rank; heir.ward = true; this.remember(suspect.id, `The King took my child ${heir.name} to Kingsmere on a bannerman's word.`); this.save(heir); out.text = `${heir.name} rides to Kingsmere as a royal ward. ${suspect.name} will not rise while the King holds his child, and will not forget.`; }
    if (option === "reward") { informer.loyalty = Math.min(100, informer.loyalty + 20); this.shift(suspect.id, informer.id, -40, `${informer.name} sold tales of me to the King.`); this.shift(informer.id, suspect.id, -10); out.text = `${informer.name} leaves court with a heavier purse. Within the month, ${suspect.name} knows who talked.`; }
    if (option === "dismiss") { out.favour[suspect.playerId] = 5; this.remember(informer.id, "The King called me a liar before the court."); informer.loyalty = Math.max(0, informer.loyalty - 10); out.text = `The King dismisses the accusation. ${informer.name} leaves court red-faced.`; }
    this.save(informer); this.save(suspect);
  },
  regency({ p, c, opt, option, out, gold, world }) {
    const regent = this.people[p.regent];
    if (option === "regent") { regent.loyalty = 100; regent.goals = [{ kind: "favour", text: "repay the King who raised me" }]; out.favour[c.playerId] = -10; this.remember(regent.id, "The King named me to govern my house. I owe him everything."); out.text = `${regent.name} is named to govern ${c.house} by the King's word. ${c.house}'s kin bow, and whisper.`; }
    if (option === "crown") { const me = world.players.find((x) => x.id === c.playerId); const take = Math.floor((me?.gold ?? 0) / 4); gold(c.playerId, -take); const crown = world.players.find((x) => houseFor(x).crown); if (crown) gold(crown.id, take); out.favour[c.playerId] = -15; out.text = `The crown governs ${c.house} until the matter is settled, and its stewards take ${take} gold for the trouble.`; }
    if (option === "leave") { regent.goals.unshift({ kind: "crown", text: `take ${c.house} for myself` }); regent.loyalty = Math.max(0, regent.loyalty - 25); out.text = `The King leaves ${c.house} to settle its own succession. ${regent.name} smiles.`; }
    this.save(regent);
  },
};
