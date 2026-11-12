// Guards one owner for the day's parts (READY.md line 13 "People live by a plan" and 15, SSOT; casebook, Living
// towns): the bridge's minds plan by the same day the town lives by, realm/data/town_scenes.json `day`, read
// through the bridge's data reader (chronicles.js readJson), never a table of their own. For every quarter hour,
// minds.js block(h) gives the row's part and the hour it ends. Exits 1 on a failure.   node tools/day_probe.mjs
import fs from "node:fs";
import { checker } from "./fc_probe_lib.mjs";
import * as Minds from "../minds.js";

const { check, done } = checker("DAY");
const src = fs.readFileSync(new URL("../minds.js", import.meta.url), "utf8");
check(!/return \["(night|dawn|work|meal|work2|evening)"/.test(src), "minds.js keeps its own table of the day's parts");
const rows = JSON.parse(fs.readFileSync(new URL("../../realm/data/town_scenes.json", import.meta.url), "utf8")).day;
check(Array.isArray(rows) && rows.length > 0, "town_scenes.json has no day");
check(typeof Minds.block === "function", "minds.js has no block(h) to read the day by");
let n = 0;
if (typeof Minds.block === "function") for (let h = 0; h < 24; h += 0.25) {
  const row = rows.find((r) => (r.from < r.to ? h >= r.from && h < r.to : h >= r.from || h < r.to));
  const until = row.from > row.to && h >= row.from ? row.to + 24 : row.to;
  const [part, end] = Minds.block(h);
  n++;
  check(part === row.part && end === until, `hour ${h}: minds says ${part} until ${end}, the day says ${row.part} until ${until}`);
}
console.log(`  ${n} quarter hours against ${rows?.length} rows`);
done();
