// What's at stake in a reign: the calendar, the usurper who rises when the
// houses lose faith in the crown, the dead who come from beyond the northern
// wall, and how a reign ends and is remembered.
//
// Hostile hosts are raised as units of Freeciv's barbarian player, which is
// at war with everyone, so Freeciv itself fights the battles.

import fs from "node:fs";
import path from "node:path";
import { houseFor, cityName } from "./narrator.js";
import { greatHouses } from "./realm.js";
import { BANDS } from "./favour.js";

const SEASONS = ["spring", "summer", "autumn", "winter"];
const CONQUEST_YEAR = 300; // the realm's calendar starts 300 years after the Conquest

export function calendar(turn) {
  const t = Math.max(1, Number(turn) || 1) - 1;
  return { season: SEASONS[t % 4], year: CONQUEST_YEAR + Math.floor(t / 4), text: `${SEASONS[t % 4][0].toUpperCase()}${SEASONS[t % 4].slice(1)} of ${CONQUEST_YEAR + Math.floor(t / 4)} AC` };
}

// The reign's stakes now being kept (one reign at a time), for raisePretender.
let current = null;

// A pretender proclaimed elsewhere (the director's ignored claim, director.js):
// the usurper's path starts at its rumour, so the claim still goes through the
// ultimatum at court before any host marches. One writer: stakes.js.
export function raisePretender(houseId) {
  current?.raise(houseId);
}

export class Stakes {
  constructor(stateDir, record, endReign) {
    current = this;
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

  // The usurper's rumour, started by a house's proclaimed claim (raisePretender).
  // A path already under way is left as it is.
  raise(houseId) {
    const u = this.s.usurper;
    if (houseId == null || u.stage !== "none") return;
    Object.assign(u, { stage: "rumour", house: Number(houseId), since: this.turnNow ?? 0 });
    this.save();
  }

  // Raises a host through realm_host() in realmrules/script.lua; Freeciv's AI then
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

  // A story declares for the throne: the house marches on Kingsmere now, and
  // the march ends as any usurper's does (broken, worn out, or the crown lost).
  declare(pid, world, ctx, size = 10) {
    const u = this.s.usurper;
    if (!this.s.seat || u.stage === "march") return false;
    u.stage = "march";
    u.house = pid;
    u.since = world.turn ?? 0;
    u.peak = 0;
    this.host(ctx, this.playerById(pid), this.s.seat.x, this.s.seat.y, ["Knights", "Pikemen", "Catapult", "Knights"], size);
    this.save();
    return true;
  }

  tick(turn, world, ctx) {
    this.turnNow = turn;
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
    const houses = greatHouses(world);
    // A house whose heir is the King's ward does not rise while the ward lives at court.
    const held = (this.s.wards ?? {});
    // Nor does a house sworn to the crown while its oath holds.
    const angry = houses.filter((p) => ctx.favour(p.id) < BANDS.cooling && !((held[p.id] ?? -1) > turn) && !ctx.sworn?.(p.id));
    const u = this.s.usurper;
    if (u.stage === "none" && ctx.options?.usurper !== false && ctx.usurperMay !== false && houses.length && angry.length >= Math.max(2, Math.ceil(houses.length / 3))) {
      const pretender = angry.sort((a, b) => b.cities - a.cities)[0];
      u.stage = "rumour";
      u.house = pretender.id;
      u.since = turn;
      this.record({ turn, kind: "unrest", text: `Whispers in Kingsmere: ${houseFor(pretender).name} speaks of a better claim to the throne. ${angry.length} great houses have lost faith in the crown.` });
    } else if (u.stage === "rumour") {
      if (angry.length < Math.max(2, Math.ceil(houses.length / 3)) - 1) {
        u.stage = "none";
        this.record({ turn, kind: "decree", text: "The whispers fade. The great houses have been won back, for now." });
      } else if (turn - u.since >= 8 && this.s.seat && ctx.mayRise && !ctx.mayRise(u.house)) {
        // Every rising passes the ultimatum: the pretender's claim goes to court first,
        // and the host marches only once it is refused or left unanswered.
        ctx.ultimatum?.(u.house);
      } else if (turn - u.since >= 8 && this.s.seat) {
        ctx.rose?.(u.house);
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
        const loyal = houses.filter((p) => p.id !== u.house && ctx.favour(p.id) >= BANDS.steady);
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
    }
    // How the last wave ended, three seasons on: the town held, or fell.
    if (n.struck && turn - n.struck.turn >= 3) {
      const town = world.cities.find((c) => c.id === n.struck.id);
      const name = cityName(n.struck.id);
      const lord = houseFor(world.players.find((p) => p.id === n.struck.owner) ?? {}).name ?? "its lord";
      if (town && town.owner === n.struck.owner) this.record({ turn, kind: "decree", text: `The dead broke against the walls of ${name}. ${lord} held, and ${n.struck.men.toLocaleString("en-US")} of them lie in the snow.` });
      else this.record({ turn, kind: "rebellion", text: `${name} has fallen to the dead. ${lord} could not hold it, and the North is smaller for it.` });
      n.struck = null;
    }
    if (n.nextAt && turn >= n.nextAt && !(turn >= n.awakeAt && !n.nextAt)) {
      n.waves++;
      n.nextAt = turn + Math.max(6, 16 - n.waves);
      const north = world.cities.filter((c) => c.y < 30).sort((a, b) => a.y - b.y)[0];
      const x = north ? north.x : 28;
      const y = north ? Math.max(2, north.y - 4) : 6;
      this.host(ctx, this.theDead(), x, y, ["Warriors", "Archers", "Pikemen"], 3 + n.waves * 2);
      // Remember where they struck, to tell how it ended.
      if (north) n.struck = { id: north.id, owner: north.owner, turn, men: (3 + n.waves * 2) * 200 };
      this.record({ turn, kind: "rebellion", text: n.waves === 1 ? "The dead come over the wall. The North bleeds first." : `The dead come again, more than before${n.waves > 4 ? ", as they have for years now" : ""}. The northern houses beg the King for aid.` });
      const northernSeats = world.cities.filter((c) => c.y < 22);
      if (n.waves >= 4 && northernSeats.length === 0) this.endReign("The North is lost to the dead, and the realm with it.", "fallen");
    }
    this.save();
  }
}

// How a reign is remembered: an epithet earned from how the King ruled.
// The names history gives a reign, in the order they are tested: each with how
// near its test is to met (0 or more: met). epithet() takes the first met; the
// running reading shows it and the nearest other, from the same thresholds.
const NAMES = [
  ["the Golden", (m) => Math.min((m.peace - 0.8) / 0.2, (m.grew - 1.3) / 0.3)],
  ["the Peacemaker", (m) => (m.peace - 0.75) / 0.25],
  ["the Bloody", (m) => (0.3 - m.peace) / 0.3],
  ["the Builder", (m) => (m.grew - 1.5) / 0.5],
  ["the Hoarder", (m) => (m.purse - 3000) / 3000],
  ["the Meddler", (m) => (m.decrees - 40) / 40],
  ["the Idle", (m) => (3 - m.decrees) / 3],
];
function measures(history, decreesIssued) {
  const peace = history.reduce((s, r) => s + r.peace, 0) / history.length;
  const grew = history[history.length - 1].pop / Math.max(1, history[0].pop);
  return { peace, grew, purse: history[history.length - 1].treasury, decrees: decreesIssued };
}

export function epithet(history, outcome, decreesIssued) {
  if (outcome === "deposed") return "the Deposed";
  if (outcome === "fallen") return "the Last";
  if (!history.length) return "the Brief";
  const m = measures(history, decreesIssued);
  // Strictly past each line, as the old tests were (peace > 0.8, not >=).
  return NAMES.find(([, near]) => near(m) > 0)?.[0] ?? "the Steadfast";
}

// The name the reign is earning and the one nearest after it.
export function epithetNear(history, decreesIssued) {
  const name = epithet(history, null, decreesIssued);
  if (!history.length) return { name, next: null };
  const m = measures(history, decreesIssued);
  const near = NAMES.filter(([n]) => n !== name).map(([n, f]) => [n, f(m)]).sort((a, b) => b[1] - a[1]);
  const next = near[0] && near[0][1] > -0.6 ? near[0][0] : name !== "the Steadfast" ? "the Steadfast" : near[0]?.[0] ?? null;
  return { name, next };
}
