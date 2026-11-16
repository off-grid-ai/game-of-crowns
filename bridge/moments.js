// The King's swings told as moments (data/moments.json): a chronicle line's `moment` field, which the view shows as
// its word across the screen (realm/scripts/moment_banner.gd). The one place the words are chosen.
import fs from "node:fs";

const M = JSON.parse(fs.readFileSync(new URL("./data/moments.json", import.meta.url), "utf8"));

export function moment(key, line = "") {
  const m = M[key];
  return m ? { word: m.word, loss: !!m.loss, line } : undefined;
}
