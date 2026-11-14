// The land remembers (casebook, The land remembers: Farthest Frontier's soil that sinks under the same crop, Manor
// Lords' fallow fields). One owner: meta.soil {cityId: wear 0..1}, how worn a town's fields are. Each autumn harvest
// (the same turn harvest.js reads) wears every town's fields, the bigger the town the faster. A tired town's lord
// comes to court (court.arcPetition, arc "soil"; one a harvest, the most worn): let the fields lie fallow, a lean
// season now for land as good as new, or press on. Fields pressed past failing give out by themselves: Freeciv's
// Blight decree (script.lua realm_decree: the land gives half its food) for seasons, told in the chronicle. So
// farming is a plan the King keeps, not a click. Numbers: data/soil.json. /world soil.
import fs from "node:fs";
import * as Lua from "./lua.js";
import { cityName, houseFor } from "./narrator.js";

const S = JSON.parse(fs.readFileSync(new URL("./data/soil.json", import.meta.url), "utf8"));
const signed = (d) => `${d > 0 ? "+" : "−"}${Math.abs(d)}`;
const round = (x) => Math.round(x * 100) / 100;

export function season(ctx, turn) {
  const { meta, world, send, record, court } = ctx;
  const w = meta.weather;
  if (!world?.cities || w?.season !== "autumn" || w.turn !== turn || meta.soilTurn === turn) return;
  meta.soilTurn = turn;
  const soil = (meta.soil ??= {});
  for (const k of Object.keys(soil)) if (!world.cities.some((c) => c.id === Number(k))) delete soil[k];
  const failed = [];
  for (const c of world.cities) {
    const wear = (soil[c.id] ?? 0) + S.perHarvest + (c.size ?? 1) * S.perSize;
    if (wear >= S.failed.at) {
      send(`lua cmd ${Lua.decree(c.id, "blight", S.failed.seasons)}`);
      soil[c.id] = S.failed.after;
      failed.push(c);
    } else soil[c.id] = round(wear);
  }
  if (failed.length) {
    const names = failed.slice(0, 3).map((c) => cityName(c.id)).join(", ");
    record({ turn, kind: "famine", text: `The fields round ${names}${failed.length > 3 ? ` and ${failed.length - 3} more` : ""} give out: sown too many years running, they bear thin and weedy, and will for a while yet.`, city: failed[0].id });
  }
  // The most worn tired town whose lord can come: his plea, once a harvest.
  const tired = world.cities.filter((c) => soil[c.id] >= S.tired && !failed.includes(c)).sort((a, b) => soil[b.id] - soil[a.id]);
  for (const c of tired) {
    const lord = court?.lordOfTown?.(c.id);
    if (!lord?.alive) continue;
    const owner = world.players.find((p) => p.id === c.owner);
    const house = owner ? houseFor(owner).name : lord.house;
    const town = cityName(c.id);
    const fav = (d) => (owner && !houseFor(owner).crown ? { [owner.id]: d } : {});
    const by = (d) => (owner && !houseFor(owner).crown ? ` · ${house} ${signed(d)}` : "");
    court.arcPetition({ arc: "soil", beat: `soil-${c.id}-${turn}`, thread: `the worn fields of ${town}`, from: lord,
      text: `${lord.name} turns a clod of grey earth in his hands. "The fields of ${town} have borne wheat every year in memory, Your Grace, and every year less. Let them lie fallow a season, under clover and the town's dung, and they'll come back. Or we sow again, and pray."`,
      options: [
        { id: "fallow", label: "Let them lie fallow", favour: fav(S.favour.fallow), hint: `${town} eats lean for ${S.fallow.seasons === 1 ? "a season" : `${S.fallow.seasons} seasons`}, then its fields are as good as new${by(S.favour.fallow)}`, result: `The plough stays in the barn at ${town}. Clover comes up where the wheat was, and the town tightens its belt.` },
        { id: "press", label: "Sow again", favour: fav(S.favour.press), hint: `nothing now; the fields keep wearing, and give out for ${S.failed.seasons} seasons when they fail${by(S.favour.press)}`, result: `${town} sows its tired fields again. The stalks come up thinner, and the old men shake their heads.` },
      ] }, world);
    break;
  }
}

// The King's answer (server.js court.onArcRuling, arc "soil").
export function ruled(ctx, beat, option) {
  const { meta, send } = ctx;
  const id = Number(String(beat).split("-")[1]);
  if (option !== "fallow" || meta.soil?.[id] == null) return;
  send(`lua cmd ${Lua.decree(id, "blight", S.fallow.seasons)}`);
  meta.soil[id] = 0;
}

// For /world soil: each town's wear (0..1), and where it tires and fails.
export function view(meta) {
  return { towns: meta?.soil ?? {}, tired: S.tired, failed: S.failed.at };
}
