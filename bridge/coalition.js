// The brake on the blob (casebook, Where it goes wrong: the blob, a snowball with no brakes; EU4's coalitions,
// CK3's factions against a too-great vassal). One owner, meta.coalition {against, since, members}. Each season
// (season.js) a great house holding coalition.share of the realm's towns or more is a threat to every other: the
// houses that fear it most (data/coalition.json members, the nearest seats first) swear a pact against it (the
// intrigue, so they stand together, characters.js boundTo) and go to war on it (Freeciv's diplomacy through
// court.onWar). It holds until the house falls under coalition.release. A crown that grows as great is feared too:
// every great house cools toward it each season it stays so (coalition.crown), and the chronicle says why once.
// The crown is judged by its deeds too (alarm): every war it declares, town it marches on or takes, war it judges
// away, raises the realm's alarm (meta.alarm, 0-100), and quiet seasons ease it; at the line the great houses not
// sworn to the King swear a league and go to war on the crown (EU4's aggressive expansion). /world coalition, alarm.
import fs from "node:fs";
import { BANDS } from "./favour.js";
import { crownOf, greatHouses } from "./realm.js";
import { houseFor } from "./narrator.js";

const C = JSON.parse(fs.readFileSync(new URL("./data/coalition.json", import.meta.url), "utf8"));
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));

export function season(ctx, turn) {
  const { meta, world, court, record } = ctx;
  const towns = world?.cities ?? [];
  if (!towns.length || !court) return;
  const share = (pid) => towns.filter((c) => c.owner === pid).length / towns.length;
  const seat = (pid) => towns.find((c) => c.owner === pid && c.capital) ?? towns.find((c) => c.owner === pid);
  const great = greatHouses(world);
  // The coalition that stands: ended when its foe has fallen back, or is gone.
  const k = meta.coalition;
  const crown = crownOf(world);
  // The alarm eases each season (data/coalition.json alarm.ease); a league against the crown breaks up once it is low.
  meta.alarm = Math.max(0, (meta.alarm ?? 0) - C.alarm.ease);
  // Towns the crown took since last season, however (a siege, a war, a judgement's town counted once already).
  const held = crown ? towns.filter((c) => c.owner === crown.id).length : 0;
  if (meta.crownTowns != null && held > meta.crownTowns) for (let i = meta.crownTowns; i < held; i++) alarm(meta, "taken");
  meta.crownTowns = held;
  if (k?.crown && meta.alarm < C.alarm.release) {
    record({ turn, kind: "scheme", text: "The league against the crown breaks up: the King has kept the peace long enough that the great houses no longer fear him." });
    meta.coalition = null;
  } else if (k && !k.crown && (!great.some((p) => p.id === k.against) || share(k.against) < C.release)) {
    const foe = world.players.find((p) => p.id === k.against);
    record({ turn, kind: "scheme", text: `The league against ${foe ? houseFor(foe).name : "the fallen house"} breaks up: there is nothing left to fear.` });
    meta.coalition = null;
  }
  // The crown's deeds alarm the realm past bearing: the great houses not sworn to it swear a league and make war.
  if (!meta.coalition && crown && meta.alarm >= C.alarm.at) {
    const members = great.filter((p) => (ctx.favourOf?.(p.id) ?? 50) < BANDS.sworn && seat(p.id));
    if (members.length >= C.alarm.min) {
      for (let i = 0; i < members.length; i++) for (let j = i + 1; j < members.length; j++)
        court.scheme({ kind: "pact", from: members[i].id, to: members[j].id, line: "sworn together against the crown", turn });
      for (const m of members) court.onWar?.([m.id, crown.id]);
      meta.coalition = { against: crown.id, since: turn, members: members.map((m) => m.id), crown: true };
      meta.alarm = C.alarm.after;
      record({ turn, kind: "scheme", text: `The King's wars have frightened the realm past bearing. ${members.map((m) => houseFor(m).name).join(", ")} swear a league against the crown and call their banners. Only the houses sworn to him stand aside.` });
    }
  }
  if (!meta.coalition) {
    const blob = great.filter((p) => share(p.id) >= C.share).sort((a, b) => share(b.id) - share(a.id))[0];
    const at = blob && seat(blob.id);
    if (blob && at) {
      const members = great.filter((p) => p.id !== blob.id && seat(p.id)).sort((a, b) => cheb(seat(a.id), at) - cheb(seat(b.id), at)).slice(0, C.members);
      if (members.length >= 2) {
        const name = houseFor(blob).name;
        for (let i = 0; i < members.length; i++) for (let j = i + 1; j < members.length; j++)
          court.scheme({ kind: "pact", from: members[i].id, to: members[j].id, line: `sworn together against ${name}`, turn });
        for (const m of members) court.onWar?.([m.id, blob.id]);
        meta.coalition = { against: blob.id, since: turn, members: members.map((m) => m.id) };
        record({ turn, kind: "scheme", text: `${name} holds ${Math.round(share(blob.id) * 100)} towns in a hundred, and the realm is afraid. ${members.map((m) => houseFor(m).name).join(", ")} swear a league against it and call their banners.` });
      }
    }
  }
  // A crown grown as great: feared by every house, a little more each season.
  if (crown && share(crown.id) >= C.crown.share) {
    ctx.shiftFavour?.(Object.fromEntries(great.map((p) => [p.id, -C.crown.fear])), "a crown grown too great");
    if (!meta.crownFeared) record({ turn, kind: "scheme", text: `The crown holds ${Math.round(share(crown.id) * 100)} towns in a hundred. In the great halls the lords begin to ask who will be left to stand against it.` });
    meta.crownFeared = true;
  } else meta.crownFeared = false;
}

// A deed of the crown's that alarms the realm (routes_decree.js after war, march, back; war.js when a town falls to it).
export function alarm(meta, deed) {
  meta.alarm = Math.min(C.alarm.at, (meta.alarm ?? 0) + (C.alarm.raise[deed] ?? 0));
}

// What a deed adds to the alarm (the war council shows it before the King declares).
export const raiseOf = (deed) => C.alarm.raise[deed] ?? 0;

export function view(meta) {
  const k = meta?.coalition;
  return { alarm: Math.round(meta?.alarm ?? 0), at: C.alarm.at, league: k ? { against: k.against, since: k.since, members: k.members, crown: !!k.crown } : null };
}
