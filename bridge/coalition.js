// The brake on the blob (casebook, Where it goes wrong: the blob, a snowball with no brakes; EU4's coalitions,
// CK3's factions against a too-great vassal). One owner, meta.coalition {against, since, members}. Each season
// (season.js) a great house holding coalition.share of the realm's towns or more is a threat to every other: the
// houses that fear it most (data/coalition.json members, the nearest seats first) swear a pact against it (the
// intrigue, so they stand together, characters.js boundTo) and go to war on it (Freeciv's diplomacy through
// court.onWar). It holds until the house falls under coalition.release. A crown that grows as great is feared too:
// every great house cools toward it each season it stays so (coalition.crown), and the chronicle says why once.
// /world coalition.
import fs from "node:fs";
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
  if (k && (!great.some((p) => p.id === k.against) || share(k.against) < C.release)) {
    const foe = world.players.find((p) => p.id === k.against);
    record({ turn, kind: "scheme", text: `The league against ${foe ? houseFor(foe).name : "the fallen house"} breaks up: there is nothing left to fear.` });
    meta.coalition = null;
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
  const crown = crownOf(world);
  if (crown && share(crown.id) >= C.crown.share) {
    ctx.shiftFavour?.(Object.fromEntries(great.map((p) => [p.id, -C.crown.fear])), "a crown grown too great");
    if (!meta.crownFeared) record({ turn, kind: "scheme", text: `The crown holds ${Math.round(share(crown.id) * 100)} towns in a hundred. In the great halls the lords begin to ask who will be left to stand against it.` });
    meta.crownFeared = true;
  } else meta.crownFeared = false;
}

export function view(meta) {
  const k = meta?.coalition;
  return k ? { against: k.against, since: k.since, members: k.members } : null;
}
