// A town's situation in one line, in the realm's words: why it looks the way it
// does (besieged by whom and since when, sacked by whom, starving, sick, in
// riot; a low granary is the card's own line). The town card's first line and the scars' hover read it; it's worked
// out only here, from the one bridge state (townStates' fields, the scenes and
// the land's marks), so the player sees the cause beside the effect.
import { houseFor, cityName } from "./narrator.js";
import { calendar } from "./calendar.js";

const when = (turn) => { const d = calendar(turn); return `${d.season} ${d.year}`; };
const houseName = (world, id) => houseFor(world.players.find((p) => p.id === id) ?? {}).name ?? "raiders";

// ctx: { world, scenes, marks, besiegers(c) }; the town's own fields (besieged,
// famine, plague, disorder) are set by townStates first.
export function situation(ctx, c) {
  const { world, scenes = [], marks = [] } = ctx;
  const turn = world.turn ?? 0;
  const parts = [];
  if (c.besieged) {
    const near = ctx.besiegers(c);
    const counts = {};
    for (const u of near) counts[u.owner] = (counts[u.owner] ?? 0) + 1;
    const top = Object.entries(counts).sort((a, b) => b[1] - a[1])[0];
    // The siege began the first turn of the unbroken run of siege scenes up to now.
    let since = turn;
    while (scenes.some((s) => s.kind === "siege" && s.city === c.id && s.turn === since - 1)) since -= 1;
    parts.push(top ? `Besieged by ${houseName(world, Number(top[0]))} since ${when(since)} · ${near.length} companies at the walls` : `Besieged since ${when(since)}`);
  }
  // Taken by storm (the conquest's scene, else its scar on the land).
  const sack = scenes.filter((s) => s.kind === "sack" && s.city === c.id && s.to != null).sort((a, b) => b.turn - a.turn)[0];
  if (sack) {
    const from = sack.from != null ? ` from ${houseName(world, sack.from)}` : "";
    parts.push(`Stormed by ${houseName(world, sack.to)}${from} in ${when(sack.turn)}${turn - sack.turn <= 8 ? " · rebuilding" : ""}`);
  } else {
    const scar = marks.find((m) => (m.kind ?? m[0]) === "sack" && Number(m.x ?? m[1]) === c.x && Number(m.y ?? m[2]) === c.y);
    if (scar) parts.push(`Sacked${(scar.turn ?? scar[3]) != null ? ` in ${when(scar.turn ?? scar[3])}` : ""} · the burnt ground is still black`);
  }
  if (c.famine) parts.push("Starving: the granary is empty");
  if (c.plague) parts.push(`Sickness since ${when(c.plagueTurn)}`);
  if (c.disorder) parts.push("In riot against its lord");
  return parts.length ? parts.join(" · ") : null;
}

// For the scars' hover: what happened on this tile, in one line.
export function scarLine(ctx, mark) {
  const kind = mark.kind ?? mark[0];
  const t = mark.turn ?? mark[3];
  const at = (ctx.world.cities ?? []).find((c) => c.x === Number(mark.x ?? mark[1]) && c.y === Number(mark.y ?? mark[2]));
  const date = t != null ? ` in ${when(t)}` : "";
  if (kind === "sack") return `${at ? at.name ?? cityName(at.id) : "A town"} was stormed here${date}`;
  if (kind === "razed") return `A town was burnt to the ground here${date}`;
  return `Men died fighting here${date}`;
}
