// What's at stake in a reign: the calendar, the usurper who rises when the
// houses lose faith in the crown, the dead who come from beyond the northern
// wall, and how a reign ends and is remembered.
//
// Hostile hosts are raised as units of Freeciv's barbarian player, which is
// at war with everyone, so Freeciv itself fights the battles.

import fs from "node:fs";
import path from "node:path";
import { houseFor } from "./narrator.js";

const SEASONS = ["spring", "summer", "autumn", "winter"];
const CONQUEST_YEAR = 300; // the realm's calendar starts 300 years after the Conquest

export function calendar(turn) {
  const t = Math.max(1, Number(turn) || 1) - 1;
  return { season: SEASONS[t % 4], year: CONQUEST_YEAR + Math.floor(t / 4), text: `${SEASONS[t % 4][0].toUpperCase()}${SEASONS[t % 4].slice(1)} of ${CONQUEST_YEAR + Math.floor(t / 4)} AC` };
}

export class Stakes {
  constructor(stateDir, record, endReign) {
    this.file = path.join(stateDir, "stakes.json");
    this.record = record;
    this.endReign = endReign;
    this.s = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, "utf8")) : {
      usurper: { stage: "none", house: null, since: 0 },
      north: { awakeAt: 0, waves: 0, nextAt: 0 },
      seat: null,
    };
  }

  save() {
    fs.writeFileSync(this.file, JSON.stringify(this.s, null, 1));
  }

  // Raises a host through realm_host() in lua/events.lua; Freeciv's AI then
  // fights with it. `who` is a Lua expression for the owning player.
  host(ctx, who, x, y, units, count) {
    ctx.send(`realm_host(${who}, ${x}, ${y}, {${units.map((u) => `"${u}"`).join(",")}}, ${count})`);
  }

  playerById(id) {
    return `realm_find_player(${Number(id)})`;
  }

  // The dead are a Freeciv player of their own: never met, so at war with all.
  theDead() {
    return "realm_the_dead()";
  }

  tick(turn, world, ctx) {
    if (!world) return;
    // The crown's fate only advances while the King is present; the realm lives on regardless.
    if (!ctx.watched) {
      this.save();
      return;
    }
    const crown = world.players.find((p) => houseFor(p).crown);
    const seat = world.cities.find((c) => c.owner === crown?.id && c.capital) ?? world.cities.find((c) => c.title === "Kingsmere");
    if (seat) this.s.seat = { id: seat.id, x: seat.x, y: seat.y };

    // --- Losing the crown ---------------------------------------------------
    // Deposed: Kingsmere is in other hands, or the crown no longer exists at all.
    if (this.s.seat && (!crown || !world.cities.some((c) => c.id === this.s.seat.id && c.owner === crown.id))) {
      const holder = world.cities.find((c) => c.id === this.s.seat.id);
      const taker = holder ? houseFor(world.players.find((p) => p.id === holder.owner)).name : "fire";
      this.endReign(`Kingsmere has fallen to ${taker}. The crown is lost.`, "deposed");
      return;
    }

    // --- The usurper -----------------------------------------------------------
    const houses = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && p.cities > 0);
    const angry = houses.filter((p) => ctx.favour(p.id) < 25);
    const u = this.s.usurper;
    if (u.stage === "none" && ctx.options?.usurper !== false && houses.length && angry.length >= Math.max(2, Math.ceil(houses.length / 3))) {
      const pretender = angry.sort((a, b) => b.cities - a.cities)[0];
      u.stage = "rumour";
      u.house = pretender.id;
      u.since = turn;
      this.record({ turn, kind: "unrest", text: `Whispers in Kingsmere: ${houseFor(pretender).name} speaks of a better claim to the throne. ${angry.length} great houses have lost faith in the crown.` });
    } else if (u.stage === "rumour") {
      if (angry.length < Math.max(2, Math.ceil(houses.length / 3)) - 1) {
        u.stage = "none";
        this.record({ turn, kind: "decree", text: "The whispers fade. The great houses have been won back, for now." });
      } else if (turn - u.since >= 8 && this.s.seat) {
        u.stage = "march";
        u.since = turn;
        const name = houseFor(world.players.find((p) => p.id === u.house) ?? {}).name ?? "A pretender";
        // The usurper marches under their own house's banner; Freeciv's AI wages the war.
        this.host(ctx, this.playerById(u.house), this.s.seat.x, this.s.seat.y, ["Knights", "Pikemen", "Catapult", "Knights"], 6 + angry.length * 2);
        this.record({ turn, kind: "rebellion", text: `${name} declares for the throne! A usurper's host marches on Kingsmere.` });
      }
    } else if (u.stage === "march" && this.s.seat) {
      // The march ends on the field, not on a timer: the pretender's soldiers
      // around Kingsmere are counted each season.
      const name = houseFor(world.players.find((p) => p.id === u.house) ?? {}).name ?? "The pretender";
      const CIVIL = new Set(["Settlers", "Workers", "Migrants", "Engineers", "Explorer", "Caravan", "Freight", "Diplomat", "Spy", "Leader"]);
      const near = (world.units ?? []).filter((x) => x.owner === u.house && !CIVIL.has(x.type) && Math.hypot(x.x - this.s.seat.x, x.y - this.s.seat.y) <= 6).length;
      u.peak = Math.max(u.peak ?? 0, near);
      if (turn - u.since >= 2 && near === 0) {
        u.stage = "none";
        this.record({ turn, kind: "decree", text: `${name}'s host is broken before the walls of Kingsmere. The crown endures, and the houses that stood by it take heart.` });
        u.ended = { house: u.house, turn };  // the King decides what becomes of them
        const loyal = houses.filter((p) => p.id !== u.house && ctx.favour(p.id) >= 35);
        if (loyal.length) ctx.shift?.(Object.fromEntries(loyal.map((p) => [p.id, 5])), "the crown stood firm against the pretender");
      } else if (turn - u.since >= 16) {
        u.stage = "none";
        this.record({ turn, kind: "unrest", text: `Four years before Kingsmere, and the walls still stand. ${name}'s host melts away home, humbled but unbroken.` });
        u.ended = { house: u.house, turn };  // the King decides what becomes of them
      }
    }

    // --- The dead beyond the wall ------------------------------------------------
    const n = this.s.north;
    // The King chose when, or whether, the dead stir.
    const dead = ctx.options?.dead ?? "normal";
    if (dead === "off") {
      this.save();
      return;
    }
    const wait = { soon: [15, 15], normal: [40, 40], late: [90, 60] }[dead] ?? [40, 40];
    if (!n.awakeAt || (n.awakeAt < turn && !n.nextAt)) n.awakeAt = turn + wait[0] + Math.floor(Math.random() * wait[1]);
    if (turn >= n.awakeAt && !n.nextAt) {
      this.record({ turn, kind: "unrest", text: "Beyond the old wall, the snow is moving. Rangers do not return. The dead are stirring." });
      n.nextAt = turn + 8;
    } else if (n.nextAt && turn >= n.nextAt) {
      n.waves++;
      n.nextAt = turn + Math.max(6, 16 - n.waves);
      const north = world.cities.filter((c) => c.y < 30).sort((a, b) => a.y - b.y)[0];
      const x = north ? north.x : 28;
      const y = north ? Math.max(2, north.y - 4) : 6;
      this.host(ctx, this.theDead(), x, y, ["Warriors", "Archers", "Pikemen"], 3 + n.waves * 2);
      this.record({ turn, kind: "rebellion", text: n.waves === 1 ? "The dead come over the wall. The North bleeds first." : `The dead come again, more than before${n.waves > 4 ? ", as they have for years now" : ""}. The northern houses beg the King for aid.` });
      const northernSeats = world.cities.filter((c) => c.y < 22);
      if (n.waves >= 4 && northernSeats.length === 0) this.endReign("The North is lost to the dead, and the realm with it.", "fallen");
    }
    this.save();
  }
}

// How a reign is remembered: an epithet earned from how the King ruled.
export function epithet(history, outcome, decreesIssued) {
  if (outcome === "deposed") return "the Deposed";
  if (outcome === "fallen") return "the Last";
  if (!history.length) return "the Brief";
  const peace = history.reduce((s, r) => s + r.peace, 0) / history.length;
  const first = history[0];
  const last = history[history.length - 1];
  const grew = last.pop / Math.max(1, first.pop);
  if (peace > 0.8 && grew > 1.3) return "the Golden";
  if (peace > 0.75) return "the Peacemaker";
  if (peace < 0.3) return "the Bloody";
  if (grew > 1.5) return "the Builder";
  if (last.treasury > 3000) return "the Hoarder";
  if (decreesIssued > 40) return "the Meddler";
  if (decreesIssued < 3) return "the Idle";
  return "the Steadfast";
}
