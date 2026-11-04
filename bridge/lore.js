// The lore of Aldmere, for the game's Lore pages: the realm's story and each
// great house's, read from the world bible (WORLD.md), so the book and the
// bible never disagree.

import fs from "node:fs";

let cached = null;

const plain = (s) => String(s ?? "").replace(/\*\*|\*/g, "").trim();

export function bible(file) {
  if (cached) return cached;
  const text = fs.readFileSync(file, "utf8");
  const sections = {};
  let name = "intro";
  for (const line of text.split("\n")) {
    const head = line.match(/^##\s+(.*)/);
    if (head) {
      name = head[1].toLowerCase();
      continue;
    }
    if (line.startsWith("# ")) continue;
    (sections[name] ??= []).push(line);
  }
  const paras = (lines = []) => lines.join("\n").split(/\n\s*\n/).map((p) => plain(p.replace(/\n/g, " "))).filter(Boolean);
  const bullets = (lines = []) => lines.filter((l) => l.startsWith("- ")).map((l) => {
    const m = l.slice(2).match(/^\*\*(.+?):?\*\*:?\s*(.*)$/);
    return m ? { title: plain(m[1]).replace(/:$/, ""), text: plain(m[2]) } : { title: "", text: plain(l.slice(2)) };
  });
  const houses = {};
  for (const l of sections["the seven great houses"] ?? []) {
    const cols = l.split("|").map((c) => c.trim());
    if (cols.length < 8 || !cols[1].startsWith("**")) continue;
    const [, house, region, seat, words, character, wants, grudge] = cols;
    houses["House " + plain(house)] = { region, seat: plain(seat), words: plain(words).replace(/"/g, ""), character, wants, grudge: plain(grudge) };
  }
  cached = {
    intro: paras(sections.intro),
    crown: bullets(sections["the crown: you"]),
    faults: bullets(sections["fault lines at the start of your reign"]),
    fate: bullets(sections["fate: what tests a reign"]),
    tone: paras(sections.tone).join(" "),
    houses,
  };
  return cached;
}
