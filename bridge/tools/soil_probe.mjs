// Guards The land remembers (soil.js): harvests wear a town's fields, a tired town's lord asks the King at court, fallow
// rests the fields with one lean season, and fields pressed past failing give out by themselves (Blight). No Freeciv.
//   node tools/soil_probe.mjs        (from bridge/)
import * as Soil from "../soil.js";
import { checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("SOIL");
const sent = [], said = [], asked = [];
const lord = { id: "c1", name: "Ser Odo", house: "House Thornvale", alive: true };
const world = { turn: 0, players: [{ id: 3, nation: "French" }], cities: [{ id: 10, owner: 3, size: 8 }, { id: 11, owner: 3, size: 2 }] };
const meta = {};
const ctx = { meta, world, send: (l) => sent.push(l), record: (e) => said.push(e.text), court: { lordOfTown: () => lord, arcPetition: (p) => asked.push(p) } };
let turn = 0;
const harvest = () => { turn += 4; world.turn = turn; meta.weather = { season: "autumn", turn }; Soil.season(ctx, turn); };
harvest();
check(meta.soil[10] > meta.soil[11], "a big town's fields don't wear faster");
check(!asked.length, "a lord asked after one harvest");
harvest(); harvest();
check(asked.length === 1 && asked[0].beat.startsWith("soil-10-"), `the big town's lord didn't come to court when its fields tired (${asked.map((p) => p.beat)})`);
check(asked[0].options.map((o) => o.id).join() === "fallow,press", "the plea isn't fallow or press on");
Soil.ruled(ctx, asked[0].beat, "fallow");
check(meta.soil[10] === 0 && sent.some((l) => l.includes("realm_decree(10, \"blight\", 1)")), "fallow didn't rest the fields with one lean season");
for (let i = 0; i < 6; i++) harvest();
check(said.some((t) => /give out/.test(t)) && sent.some((l) => l.includes("\"blight\", 3")), "fields pressed past failing didn't give out");
check(Soil.view(meta).towns[11] != null, "/world soil has no wear for the town");
done();
