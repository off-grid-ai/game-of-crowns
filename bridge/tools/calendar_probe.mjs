// Guards "a year is four seasons" having one owner (integration audit #3, READY.md line 15: DRY): calendar.js. No
// other bridge file defines the seasons or the year's length, or counts a turn modulo 4. Exits 1 on a breach.
//   node tools/calendar_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checker } from "./fc_probe_lib.mjs";
import { calendar, isYearEnd, isYearStart, seasonsIn, yearsIn, SEASONS_PER_YEAR } from "../calendar.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("CALENDAR");
for (const f of fs.readdirSync(BRIDGE).filter((x) => x.endsWith(".js") && x !== "calendar.js")) {
  fs.readFileSync(path.join(BRIDGE, f), "utf8").split("\n").forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "");
    if (/%\s*4\b/.test(code)) check(false, `${f}:${i + 1} counts seasons by a bare 4: ${line.trim().slice(0, 100)}`);
    if (/SEASONS_PER_YEAR\s*=(?!=)|YEARLY\s*=(?!=)|CONQUEST_YEAR\s*=(?!=)|\["spring",\s*"summer"/.test(code)) check(false, `${f}:${i + 1} defines the year again: ${line.trim().slice(0, 100)}`);
  });
}
check(SEASONS_PER_YEAR === 4 && calendar(1).text === "Spring of 300 AC" && calendar(8).text === "Winter of 301 AC", `calendar.js miscounts (${calendar(1).text}, ${calendar(8).text})`);
check(isYearEnd(4) && !isYearEnd(5) && isYearStart(5) && seasonsIn(3) === 12 && yearsIn(8) === 2, "calendar.js's year tests are wrong");
done();
