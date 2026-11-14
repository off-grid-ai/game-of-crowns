// The Crown: royal treasury (the Crown player's gold in Freeciv), the tithe on
// the great houses, each house's favour toward the crown, and royal decrees
// that cost gold and move favour. Each decree becomes Freeciv Lua.

import { cityName, houseFor } from "./narrator.js";
import { greatHouses, crownOf } from "./realm.js";
import { BANDS } from "./favour.js";
import * as Lua from "./lua.js";
import fs from "node:fs";
// The crown's money in one place (the purse, the tithe's yield, wear, thin): data/economy.json.
export const ECONOMY = JSON.parse(fs.readFileSync(new URL("./data/economy.json", import.meta.url), "utf8"));

// The decrees, their prices and words: data/decrees.json (one place for both the
// bridge and the town card).
export const DECREES = Object.fromEntries(Object.entries(JSON.parse(fs.readFileSync(new URL("./data/decrees.json", import.meta.url), "utf8"))).filter(([k]) => k !== "_"));

// When the banners were last called: the houses won't answer twice in a year.
let bannersCalled = -99;
// Whether the houses would answer the banners now (once a year).
export const bannersReady = (turn) => turn - bannersCalled >= 4;

const BUILDABLE = { temple: "Temple", granary: "Granary", walls: "City Walls", market: "Marketplace", aqueduct: "Aqueduct", barracks: "Barracks" };
// The build decree's key for a building's own name ("Marketplace" -> "market"), or null.
export const buildKey = (name) => Object.keys(BUILDABLE).find((k) => BUILDABLE[k] === name) ?? null;


export function clampFavour(v) {
  return Math.max(0, Math.min(100, Math.round(v)));
}

// The tithe: each season the crown takes `rate` of what every great house
// EARNED since the last (its treasury's rise), not of its savings: a tithe on
// savings, taken every season, drained the houses to nothing and piled their
// whole wealth up at Kingsmere. Higher tithes still cost favour every season.
//
// And the crown pays its way: the court, the royal host's wages and its
// castles' keep, plus the cost of a great treasury itself (stewards, gifts,
// loans called in), so royal gold is a choice to spend, not a heap that grows.

// The court and the castles' keep, plus a little for a great treasury's
// stewards. Not the soldiers: the engine already charges a town for its units,
// and charging again left the crown at 0 crowns for good, unable to decree.
// A house's fighting men where `near` holds: the men a decree sends home. They take a homeward order
// (hosts.js): Freeciv's moves to their seat, disbanded there into its work. No unit vanishes.
function menNear(world, pid, near) {
  return (world.units ?? []).filter((u) => u.owner === pid && u.type !== "Workers" && u.type !== "Settlers" && near(u)).map((u) => u.id);
}
const within = (at, r) => (u) => Math.hypot(u.x - at.x, u.y - at.y) <= r;
// Beside another house's towns (three tiles), as the old kill path counted them.
const byTownsOf = (world, pid) => (u) => world.cities.some((c) => c.owner === pid && (u.x - c.x) ** 2 + (u.y - c.y) ** 2 <= 9);

// A tithe this heavy grasps: the ledger's tithe_high, and the towns mutter (view.js townStates).
export const TITHE_HIGH = ECONOMY.tithe.high;  // data/economy.json

// The decrees, one handler each. A new decree is a row in data/decrees.json plus
// a handler here; x is what decree() reckoned for it (the crown, the price, the
// town and its lord).
const HANDLERS = {
  banners(x) {
    const { cmd, world, crown, cost, pay } = x;
    // The King summons every great house to send men to Kingsmere. Each
    // answers by its favour: the loyal march at once, the wary send a few
    // with excuses, the cold refuse to his face. One decree, and the King
    // learns who he can count on; the men who come join the royal host.
    const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
    if (!seat) return { error: "the crown has no seat to muster at" };
    const since = (world.turn ?? 0) - bannersCalled;
    if (since < 4) return { error: `the banners were called ${since === 0 ? "this season" : since === 1 ? "last season" : `${since} seasons ago`}; the houses won't answer again before the year is out` };
    bannersCalled = world.turn ?? 0;
    const fav = cmd.favourOf ?? (() => 60);
    const came = [], few = [], refused = [];
    const lua = [pay];
    const favour = {};
    let men = 0;
    for (const p of world.players) {
      const h = houseFor(p);
      if (h.wild || h.crown || !world.cities.some((x) => x.owner === p.id)) continue;
      const f = fav(p.id);
      const name = h.name.replace("House ", "");
      // What a house sends scales with its strength: a quarter of a loyal
      // house's companies, an eighth of a willing one's, at least one.
      // A house sworn to the crown answers gladly, whatever its mood.
      const oath = (cmd.sworn ?? (() => false))(p.id);
      const share = f >= BANDS.loyal || oath ? 0.25 : f >= BANDS.steady ? 0.125 : 0;
      const n = share ? Math.max(1, Math.round((p.units ?? 0) * share)) : 0;
      const sent = `${name} ${(n * 200).toLocaleString("en-US")}`;
      if (f >= BANDS.loyal || oath) came.push(sent);
      else if (n) few.push(sent);
      else refused.push(name);
      // A house that answers is bound closer by fighting beside the crown; one
      // that refuses has defied the King to his face and cools further.
      favour[p.id] = f >= BANDS.loyal ? 3 : n ? 1 : -3;  // gladly, grudgingly, or not at all
      if (n) {
        men += n;
        // A transfer, not a loss: these men, the house's nearest Kingsmere, march there by the road and join the
        // royal host at its walls (realm_banners; hosts.js warpath, join), seen on the way.
        lua.push(Lua.banners(p.id, seat.id, n));
      }
    }
    const list = (xs) => xs.length > 1 ? `${xs.slice(0, -1).join(", ")} and ${xs.at(-1)}` : xs[0];
    const parts = [];
    const verb = (xs, one, many) => (xs.length > 1 ? many : one);
    // Each house by the men it sent: gladly (loyal) or grudgingly (willing).
    if (came.length) parts.push(`gladly: ${list(came)}`);
    if (few.length) parts.push(`grudgingly: ${list(few)}`);
    if (refused.length) parts.push(`${list(refused)} ${verb(refused, "refuses", "refuse")} the summons`);
    // The coldest refusal says why, from what that house has not forgotten.
    const firstNo = world.players.find((p) => houseFor(p).name.replace("House ", "") === refused[0]);
    const why = firstNo && cmd.causeOf ? cmd.causeOf(firstNo.id) : "";
    if (why) parts.push(`${refused[0]} has not forgotten ${why}`);
    return { cost, favour, text: `The King calls the banners. ${parts.join("; ").replace(/^./, (c) => c.toUpperCase())}.${men ? ` ${(men * 200).toLocaleString("en-US")} men march to Kingsmere.` : " No one marches."}`, lua, refused };
  },
  relief(x) {
    const { cost, pay, c, owner, lord, town } = x;
    if (!c) return { error: "choose a town" };
    return {
      cost, favour: { [owner.id]: 12 },
      text: `By royal decree, wagons of grain roll into ${town}. ${lord} remembers the King's mercy.`,
      // The grain is Freeciv's: the town's food half again as much while the wagons last (Royal Relief).
      lua: [pay, Lua.decree(c.id, "relief")], relieved: c.id,
    };
  },
  gift(x) {
    const { cost, pay, owner, lord } = x;
    if (!owner) return { error: "choose a town or house" };
    return {
      cost, favour: { [owner.id]: 10 },
      text: `The King sends a chest of gold to ${lord}.`,
      lua: [pay, Lua.gold(owner.id, cost)],
    };
  },
  sellswords(x) {
    const { world, crown, cost, pay } = x;
    // Free companies, paid in gold: a thousand men at Kingsmere, owing nothing to any house.
    const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
    if (!seat) return { error: "the crown has no seat" };
    return { cost, favour: {}, text: "The King hires sellswords: a thousand men of the free companies march into Kingsmere, loyal to his gold.",
      lua: [pay, Lua.levy(seat.id, ["Pikemen", "Knights", "Pikemen", "Knights", "Pikemen"])] };
  },
  levy(x) {
    const { world, crown, cost, pay } = x;
    const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
    if (!seat) return { error: "the crown has no seat" };
    return {
      cost, favour: {},
      text: "The King raises a levy: 600 men, pikemen and knights, muster at Kingsmere.",
      lua: [pay, Lua.levy(seat.id, ["Pikemen", "Pikemen", "Knights"])],
    };
  },
  build(x) {
    const { cmd, cost, pay, c, owner, lord, town, inCity } = x;
    if (!c) return { error: "choose a town" };
    const b = BUILDABLE[cmd.building];
    if (!b) return { error: "unknown building" };
    // "new city walls", "a granary", "an aqueduct": the building as it reads.
    const what = b.toLowerCase();
    const thing = what.endsWith("s") ? `new ${what}` : `${/^[aeiou]/.test(what) ? "an" : "a"} ${what}`;
    // In the King's own town the crown builds for itself: nobody to thank.
    const own = houseFor(owner).crown;
    // The King's own works rise over two seasons on the town's site (server.js royal works);
    // a house's town builds the gift at once, and so do the sept and aqueduct the Hand calls
    // for against plague and unrest (they were always at once, and a crisis can't wait).
    if (own && (cmd.works ?? {})[c.id]) return { error: `the King's masons are already at work in ${town}` };
    if (own && !["Temple", "Aqueduct"].includes(b)) return {
      cost, favour: {},
      text: `The King's masons break ground on ${thing} in ${town}. It will stand in two seasons.`,
      lua: [pay], work: { city: c.id, building: b },
    };
    return {
      cost, favour: own ? {} : { [owner.id]: 8 },
      text: own ? `The King raises ${thing} in ${town} at the crown's cost.` : `The crown pays for ${thing} in ${town}. ${lord} is grateful.`,
      lua: [pay, Lua.building(c.id, b)],
    };
  },
  feast(x) {
    const { world, cost, pay, owner, lord } = x;
    if (!owner) return { error: "choose a town or house" };
    // At the King's own court: every great house is his guest.
    if (houseFor(owner).crown) {
      const guests = Object.fromEntries(world.players.filter((p) => !houseFor(p).crown && !houseFor(p).wild && p.id !== owner.id).map((p) => [p.id, 5]));
      const seat = world.cities.find((c) => c.owner === owner.id && c.capital);
      return { cost, favour: guests, text: "The King holds a feast at court. Every great house sends someone; tempers cool, for now.", lua: [pay, ...(seat ? [Lua.decree(seat.id, "feast")] : [])] };
    }
    return {
      cost, favour: { [owner.id]: 15 },
      text: `A feast at Kingsmere in honour of ${lord}. Wine flows; old slights are forgotten, for now.`,
      // Its people feast too: a Royal Feast in the house's seat (Freeciv: content townsfolk while it lasts).
      lua: [pay, ...((seat) => (seat ? [Lua.decree(seat.id, "feast")] : []))(world.cities.find((c) => c.owner === owner.id && c.capital))],
    };
  },
  ward(x) {
    const { world, cost, pay, c, cmd } = x;
    // The heir lives at court: the house cannot rise while the King holds them.
    const owner = c ? world.players.find((p) => p.id === c.owner) : null;
    if (!owner || houseFor(owner).crown) return { error: "choose a great house's town" };
    if ((cmd.warded ?? (() => false))(owner.id)) return { error: `${houseFor(owner).name}'s heir is already at court` };
    return { cost, favour: { [owner.id]: DECREES.ward.favour ?? -15 }, lua: [pay], ward: owner.id,
      text: `${houseFor(owner).name}'s heir rides to Kingsmere as the King's ward. While the child lives at court, the house will not rise, and it will not forget who took them.` };
  },
  buyoff(x) {
    const { cmd, world, cost, pay } = x;
    // Gold for the pretender's claim: their host about Kingsmere goes home and
    // the whispers stop, at a price every other house will remember.
    const u = cmd.usurper;
    const who = world.players.find((p) => p.id === u?.house);
    if (!u || u.stage === "none" || !who) return { error: "no pretender threatens the throne" };
    const at = cmd.seat;
    const homeward = at ? [{ owner: who.id, units: menNear(world, who.id, within(at, 6)) }] : [];
    const lord = houseFor(who).name;
    const others = Object.fromEntries(world.players.filter((p) => p.id !== who.id && !houseFor(p).wild && !houseFor(p).crown).map((p) => [p.id, -2]));
    return { cost, favour: { [who.id]: 25, ...others }, lua: [pay], homeward, endUsurper: true,
      text: `The King buys off ${lord}: gold for their claim. Their host breaks camp and goes home, and the other houses mutter that treason pays.` };
  },
  back(x) {
    const { cmd, world, cost, pay, owner } = x;
    // The King takes a side: gold to the house he favours (the town chosen is
    // theirs). They love him for it; the other side will not forget.
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!owner || !to || houseFor(owner).crown || houseFor(to).crown) return { error: "choose two great houses" };
    return { cost, favour: { [owner.id]: 12, [to.id]: -12 }, lua: [pay, Lua.gold(owner.id, cost)],
      text: `The King backs ${houseFor(owner).name} against ${houseFor(to).name}: crowns for swords, and every lord at court knows whose side the crown is on.` };
  },
  settle(x) {
    const { cmd, world, cost, pay, owner } = x;
    // Another house keeps the King's peace with its own men: the warring hosts
    // are turned home whether or not they love the crown; the peacekeeper is
    // honoured, the two warring houses resent the meddling.
    const to = world.players.find((p) => p.id === Number(cmd.to));
    // The keeper: the most loyal great house not in this war.
    const fav = cmd.favourOf ?? (() => 50);
    const keeper = world.players.filter((p) => p.id !== owner?.id && p.id !== Number(cmd.to) && !houseFor(p).wild && !houseFor(p).crown && p.cities > 0)
      .sort((x, y) => fav(y.id) - fav(x.id))[0];
    if (!owner || !to || !keeper) return { error: "choose two warring houses and a house to settle it" };
    const home = (x, y) => ({ owner: x, units: menNear(world, x, byTownsOf(world, y)) });
    const k = houseFor(keeper).name;
    return { cost, favour: { [keeper.id]: 6, [owner.id]: -3, [to.id]: -3 }, lua: [pay], homeward: [home(owner.id, to.id), home(to.id, owner.id)], truce: [owner.id, to.id],
      text: `At the King's word, ${k} rides between ${houseFor(owner).name} and ${houseFor(to).name}. ${k}'s men turn back the hosts near their towns, and riders carry the King's word to both houses: a truce for sixteen seasons.` };
  },
  peace(x) {
    const { cmd, world, crown, c, owner } = x;
    // The King commands two warring houses to lay down arms. Each obeys by its
    // favour: if both are warm enough, the soldiers camped by the other's towns
    // go home and both lose their taste for war a while (the engine still
    // counts them at war; the fighting stops). A cold house refuses to his face.
    if (!c) return { error: "choose a town of one of the two houses" };
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!to || to.id === owner.id || houseFor(to).wild || houseFor(to).crown || houseFor(owner).crown) return { error: "choose two great houses" };
    const fav = cmd.favourOf ?? (() => 60);
    const a = houseFor(owner).name, b = houseFor(to).name;
    // One peace verb, "Make them stop" (the cut list: peace, settle and back were three): it always
    // holds, but the colder the two houses are, the dearer the blood-price the crown pays, and a cold
    // house resents being made to stop where a warm one is grateful.
    const cost = Math.round(x.cost * peaceScale(fav(owner.id), fav(to.id)));
    if (crown.gold < cost) return { error: `the treasury holds ${(crown.gold * 100).toLocaleString("en-GB")} crowns; this costs ${(cost * 100).toLocaleString("en-GB")}` };
    const pay = Lua.gold(crown.id, -cost);
    const cold = [owner, to].filter((p) => fav(p.id) < (DECREES.peace.coldBelow ?? 40));
    const home = (x, y) => ({ owner: x, units: menNear(world, x, byTownsOf(world, y)) });
    const favour = Object.fromEntries([owner, to].map((p) => [p.id, cold.includes(p) ? -3 : 2]));
    const grudging = cold.length ? ` ${cold.map((p) => houseFor(p).name).join(" and ")} ${cold.length > 1 ? "obey" : "obeys"} with bad grace, and the crown pays the blood-price.` : " Both bow to the crown.";
    return { cost, favour, lua: [pay], homeward: [home(owner.id, to.id), home(to.id, owner.id)], text: `The King tells ${a} and ${b} to stop.${grudging} They pull their hosts back from each other's towns, and riders carry the King's word to both houses: a truce for sixteen seasons.`, truce: [owner.id, to.id] };
  },
  marriage(x) {
    const { cmd, world, cost, pay, c, owner, lord } = x;
    // A royal match binds two great houses by blood: both thank the crown,
    // and the bond holds them from each other's throats (the court's truce;
    // the names and the vows come from the court, in server.js).
    if (!c) return { error: "choose a town of one of the two houses" };
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!to || to.id === owner.id || houseFor(to).wild || houseFor(to).crown || houseFor(owner).crown) return { error: "choose two great houses to wed" };
    return { cost, favour: { [owner.id]: 8, [to.id]: 8 }, text: `By the King's word, ${lord} and ${houseFor(to).name} are to be joined by marriage.`, lua: [pay], pact: [owner.id, to.id] };
  },
  grant(x) {
    const { cmd, world, c, owner, lord, town } = x;
    if (!c) return { error: "choose a town" };
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!to || to.id === owner.id || houseFor(to).wild) return { error: "choose a house to grant it to" };
    if (c.capital) return { error: "a house's seat cannot be granted away" };
    // One of the crown's own towns, given as a reward.
    if (houseFor(owner).crown) {
      return {
        cost: 0, favour: { [to.id]: 25 },
        text: `The King grants ${town} to ${houseFor(to).name}, a reward for loyal service.`,
        lua: [Lua.transferCity(c.id, to.id)],
      };
    }
    return {
      cost: 0, favour: { [owner.id]: -30, [to.id]: 20 },
      text: `By royal decree, ${town} is taken from ${lord} and granted to ${houseFor(to).name}. ${lord} will not forget.`,
      lua: [Lua.transferCity(c.id, to.id)],
    };
  },
  alliance(x) {
    const { cmd, cost, pay, owner, lord } = x;
    // An oath: the house fights the King's wars and won't rise against him
    // for four years. A house that doesn't trust the crown won't swear it.
    if (!owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town" };
    const f = (cmd.favourOf ?? (() => 60))(owner.id);
    if (f < BANDS.sworn) return { error: `${lord} will not swear an oath to a crown it does not trust (favour ${Math.round(f)}; it needs ${BANDS.sworn}). Win them first.` };
    if ((cmd.sworn ?? (() => false))(owner.id)) return { error: `${lord} is already sworn to the crown` };
    return { cost, lua: [pay], favour: { [owner.id]: 5 }, alliance: owner.id,
      text: `${lord} kneels and swears an oath to the crown: its swords are the King's for four years, and it will not rise against him while the oath holds.` };
  },
  promise(x) {
    const { cmd, world, owner, lord } = x;
    // The answer a broke crown can always give (gameplay review #1): a seat at the King's council,
    // paid for in the favour of the house he had favoured most (cmd.to), which thought it theirs.
    const d = DECREES.promise;
    const rival = world.players.find((p) => p.id === Number(cmd.to));
    if (!owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town" };
    const favour = { [owner.id]: d.favour ?? 10, ...(rival && rival.id !== owner.id ? { [rival.id]: d.rival ?? -8 } : {}) };
    return { cost: 0, favour, lua: [],
      text: `The King promises ${lord} a seat at his council.${rival && rival.id !== owner.id ? ` ${houseFor(rival).name} had thought that seat was theirs.` : ""}` };
  },
  cede(x) {
    const { cmd, world, crown, c, town } = x;
    // A royal town for the pretender's claim (gameplay review #1): their host goes home with
    // something to show for it, and every house marks what rising against the crown bought.
    const d = DECREES.cede;
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!c || c.owner !== crown.id) return { error: "choose a town of the crown's" };
    if (c.capital) return { error: "Kingsmere is the crown itself; it cannot be ceded" };
    if (!to || houseFor(to).crown || houseFor(to).wild) return { error: "choose a great house to cede it to" };
    const u = cmd.usurper;
    const at = cmd.seat;
    const home = u && u.stage !== "none" && u.house === to.id && at ? { owner: to.id, units: menNear(world, to.id, within(at, 6)) } : null;
    const others = Object.fromEntries(greatHouses(world).filter((p) => p.id !== to.id).map((p) => [p.id, d.others ?? -2]));
    return { cost: 0, favour: { [to.id]: d.favour ?? 25, ...others }, lua: [Lua.transferCity(c.id, to.id)], homeward: home ? [home] : [], endUsurper: !!home,
      text: `The King cedes ${town} to ${houseFor(to).name} for their claim. ${home ? "Their host goes home with a town to show for it, and" : "And"} every house marks what rising against the crown can buy.` };
  },
  reinforce(x) {
    const { cmd, world, cost, pay, owner, lord } = x;
    // The King stands by a house (READY line 9: supporting a house sends your army to reinforce it): the
    // royal host marches to its town under siege, else its seat, and garrisons it by the house's leave.
    // The same march as any other (hosts.js garrison), only to a friend's gates.
    if (!owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town to reinforce" };
    const theirs = world.cities.filter((t) => t.owner === owner.id);
    if (theirs.some((t) => (cmd.marching ?? (() => false))(t.id))) return { error: `the royal host is besieging ${lord}` };
    const to = theirs.find((t) => t.besieged) ?? theirs.find((t) => t.capital) ?? theirs[0];
    if (!to) return { error: `${lord} holds no town to reinforce` };
    const h = cmd.host;
    if (!h) return { error: "the crown has no host to send" };
    const d = DECREES.reinforce;
    const others = greatHouses(world).filter((p) => p.id !== owner.id);
    const why = to.besieged ? `to break the siege of ${cityName(to.id)}` : `to ${cityName(to.id)}, its seat`;
    return { cost, lua: [pay], favour: { [owner.id]: d.favour ?? 15, ...Object.fromEntries(others.map((p) => [p.id, d.others ?? 0])) },
      hostMarch: { host: h.id, city: to.id, house: owner.id, order: "garrison", opens: owner.id },
      text: `The King stands by ${lord}: the royal host, ${h.men.toLocaleString("en-US")} men, marches ${why}.` };
  },
  march(x) {
    const { cmd, world, crown, cost, pay, c, owner, lord, town } = x;
    // The royal host marches on a town, and lays siege when it reaches the walls (hosts.js, then
    // campaigns.js): one verb, one army (gameplay review #7). The King's sworn houses send men
    // with it; two seasons before the walls the town falls to the crown, or the host breaks.
    if (!c || !owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town to march on" };
    if ((cmd.marching ?? (() => false))(c.id)) return { error: `the royal host is already before ${town}` };
    const d = DECREES.march;
    const others = greatHouses(world).filter((p) => p.id !== owner.id);
    const favour = { [owner.id]: d.favour ?? -25, ...Object.fromEntries(others.map((p) => [p.id, d.others ?? -2])) };
    // A ruling that sends the host (a siege plea answered) raises one at the King's town nearest the walls, which
    // marches there and lays siege when it arrives (realm_war_host, hosts.js warpath; campaigns.js marchOn).
    if (cmd.spawn) return { cost, lua: [pay, Lua.warHost(crown.id, c.id, ["Pikemen", "Knights", "Archers", "Catapult"], 8)], favour, march: { city: c.id, house: owner.id },
      text: `The royal host marches on ${town}. ${lord} calls every man to its walls, and every house in the realm watches.` };
    const h = cmd.host;
    if (!h) return { error: "the crown has no host to march" };
    return { cost, lua: [pay], favour, hostMarch: { host: h.id, city: c.id, house: owner.id },
      text: `The royal host, ${h.men.toLocaleString("en-US")} men, marches on ${town}. ${lord} calls every man to its walls, and every house in the realm watches.` };
  },
};

// The price of making two warring houses stop, as a multiple of the base: each point under coldBelow
// adds 1/coldBelow, up to coldMost times (data/decrees.json peace).
export function peaceScale(fa, fb) {
  const p = DECREES.peace ?? {};
  const below = p.coldBelow ?? 40;
  const cold = Math.max(0, below - fa) + Math.max(0, below - fb);
  return Math.min(p.coldMost ?? 2, 1 + cold / below);
}

// Returns { error } or { text, lua, cost, favour: {playerId: delta} }.
export function decree(cmd, world) {
  const crown = crownOf(world);
  if (!crown) return { error: "the crown has no seat" };
  const d = DECREES[cmd.action];
  if (!d) return { error: "unknown decree" };
  // What the decree costs now: the server scales it with the treasury (cmd.price).
  const cost = Math.max(d.cost, Math.round(cmd.price ?? d.cost));
  if (crown.gold < cost) return { error: `the treasury holds ${(crown.gold * 100).toLocaleString("en-GB")} crowns; this costs ${(cost * 100).toLocaleString("en-GB")}` };
  const pay = Lua.gold(crown.id, -cost);
  const c = world.cities.find((x) => x.id === Number(cmd.city));
  const owner = c ? world.players.find((p) => p.id === c.owner) : world.players.find((p) => p.id === Number(cmd.house));
  const lord = owner ? houseFor(owner).name : "";
  const town = c ? cityName(c.id) : "";
  const inCity = (body) => Lua.inCity(c?.id, body);

  if (d.off) return { error: "the King no longer gives that order" };
  const h = Object.hasOwn(HANDLERS, cmd.action) ? HANDLERS[cmd.action] : null;
  if (!h) return { error: "unknown decree" };
  return h({ cmd, world, crown, cost, pay, c, owner, lord, town, inCity });
}
