// Reads Freeciv's own save files, which hold far more than its scripting API
// exposes: food stores, construction progress, famines, unit activity and
// orders, and who is at war with whom.

import fs from "node:fs";
import zlib from "node:zlib";

// Freeciv's secfile format: [section] headers, key=value lines, and tables
// written as key={"col","col",...} followed by comma-separated rows and "}".
export function parseSecfile(text) {
  const sections = {};
  let cur = null;
  let table = null;
  for (const raw of text.split("\n")) {
    const line = raw.trimEnd();
    if (table) {
      if (line === "}") {
        cur[table.key] = table.rows;
        table = null;
      } else {
        const vals = splitRow(line);
        const row = {};
        table.cols.forEach((c, i) => (row[c] = value(vals[i])));
        table.rows.push(row);
      }
      continue;
    }
    const sec = line.match(/^\[([^\]]+)\]$/);
    if (sec) {
      cur = sections[sec[1]] = {};
      continue;
    }
    if (!cur) continue;
    const eq = line.indexOf("=");
    if (eq < 0) continue;
    const key = line.slice(0, eq);
    const rest = line.slice(eq + 1);
    if (rest.startsWith("{")) {
      table = { key, cols: splitRow(rest.slice(1)).map((c) => value(c)), rows: [] };
    } else {
      cur[key] = value(rest);
    }
  }
  return sections;
}

function splitRow(line) {
  const out = [];
  let buf = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' && line[i - 1] !== "\\") quoted = !quoted;
    if (ch === "," && !quoted) {
      out.push(buf);
      buf = "";
    } else {
      buf += ch;
    }
  }
  out.push(buf);
  return out;
}

function value(v) {
  if (v === undefined) return undefined;
  v = v.trim();
  if (v.startsWith('"') && v.endsWith('"')) return v.slice(1, -1).replace(/\\"/g, '"');
  if (v === "TRUE") return true;
  if (v === "FALSE") return false;
  if (/^-?\d+$/.test(v)) return Number(v);
  return v;
}

export function readSave(file) {
  const buf = fs.readFileSync(file);
  const text = file.endsWith(".zst") ? zlib.zstdDecompressSync(buf).toString() : buf.toString();
  return parseSecfile(text);
}

// The parts of a save the view and the ledger need, keyed by Freeciv ids.
export function extractDetail(save) {
  const players = [];
  const cities = {};
  const units = {};
  for (let i = 0; save[`player${i}`]; i++) {
    const p = save[`player${i}`];
    const relations = (p.diplstate || []).map((d, j) => ({ with: j, state: d.current }));
    players.push({
      slot: i, name: p.name, gold: p.gold, government: p.government_name, alive: p.is_alive,
      atWarWith: relations.filter((r) => r.state === "War" && r.with !== i).map((r) => r.with),
      allies: relations.filter((r) => r.state === "Alliance" || r.state === "Team").map((r) => r.with),
    });
    for (const c of p.c || []) {
      cities[c.id] = {
        foodStock: c.food_stock, shieldStock: c.shield_stock, hadFamine: c.had_famine,
        plagueTurn: c.turn_plague, building: c.currently_building_name, buildingKind: c.currently_building_kind,
        shieldSurplus: c.last_turns_shield_surplus, founded: c.turn_founded, celebrating: c.rapture > 0,
        disorder: c.anarchy > 0,
      };
    }
    for (const u of p.u || []) {
      units[u.id] = {
        hp: u.hp, veteran: u.veteran, activity: u.activity, home: u.homecity,
        goto: u.go ? { x: u.goto_x, y: u.goto_y } : null,
      };
    }
  }
  // Who holds each tile: one comma-separated row per map line, "-" for nobody.
  const owners = [];
  for (let y = 0; save.map?.[`owner${String(y).padStart(4, "0")}`] !== undefined; y++) owners.push(String(save.map[`owner${String(y).padStart(4, "0")}`]));
  return { players, cities, units, owners };
}
