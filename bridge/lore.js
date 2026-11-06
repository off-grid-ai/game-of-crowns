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
    faith: bullets(sections["the faith"]),
    faults: bullets(sections["fault lines at the start of your reign"]),
    fate: bullets(sections["fate: what tests a reign"]),
    tone: paras(sections.tone).join(" "),
    houses,
  };
  return cached;
}

// The lesser families sworn to the great houses, and the houses born of
// civil war: their arms in words, and a line or two of who they are. Their
// banners are painted in realm/assets/heraldry, under the family's name.
export const LESSER = "Beneath every great house stand the families who hold its towns in its name: bannermen, sworn by oath and bound by marriage, who raise its levies, keep its roads and, now and then, turn their coats. Their banners fly over the towns they hold.";

export const FAMILIES = {
  Ashby: { arms: "An ash tree on grey", character: "Old blood and older timber. The Ashbys planted their tree before the first king was crowned, and say they will see the last one buried." },
  Greyford: { arms: "A heron over water, on slate", character: "Keepers of fords and ferries. They wait as a heron waits, and are never seen to strike until the fish is gone." },
  Hollin: { arms: "A sprig of holly, on green", character: "Prickly, stubborn and evergreen. A Hollin keeps faith through the hardest winter, and keeps a grudge through ten." },
  Marsh: { arms: "Three bulrushes, gold on olive", character: "Fen lords who know every hidden path through the reeds. No army has crossed their country without a Marsh to guide it, or to drown it." },
  Thorne: { arms: "Two thorn branches crossed, on brown", character: "Hard men from hard country. A Thorne's oath draws blood when it is given, and more when it is broken." },
  Varn: { arms: "A bear's paw, gold on black", character: "Hunters and huge eaters, slow to rouse and terrible once roused. The Varns hold the forest roads, and charge for them." },
  Crane: { arms: "A crane in flight, on pale blue", character: "Courtiers and messengers, graceful and well-informed. Every rumour in their liege's hall passes through a Crane before it reaches the lord." },
  Dale: { arms: "Three green hills", character: "Plain farming folk raised to the banner in some forgotten war. They want good harvests and quiet roads, and fight hardest for both." },
  Brook: { arms: "A leaping fish, on teal", character: "River people, at home on every water in the realm. Wherever a liege needs boats, there is a Brook to sell them." },
  Fenwick: { arms: "An otter, on brown", character: "Clever, playful and slippery. A Fenwick will charm you at supper and have your lands mortgaged by the morning." },
  Holt: { arms: "An acorn and oak leaves, gold on green", character: "Woodwardens of the old forests. The Holts measure their wealth in oaks, and their patience in centuries." },
  Roswell: { arms: "A well and its bucket, on grey", character: "They hold the wells of a dry country, and with them every village that drinks. Nobody quarrels with a Roswell in a hot summer." },
  Kettle: { arms: "A cauldron, copper on iron grey", character: "Smiths and brewers grown rich on the trade. They feed their liege's armies, and remember to the last penny what they are owed." },
  Morrow: { arms: "A cockerel, on rose", character: "First to the field and first to crow about it. The Morrows are loud, proud and brave, in about that order." },
  Pell: { arms: "A plough, gold on brown", character: "They still plough their own fields, lord and all. A Pell's word is as plain and as good as bread." },
  Strand: { arms: "A scallop shell, gold on sea green", character: "Shore lords, wreckers once, pilgrims' hosts now. They hold the beaches and everything the sea brings up on them." },
  // Houses born of civil war.
  Blackbrook: { arms: "A river between two stones, on black", character: "They broke from their liege at a river crossing and held it against him. Now they hold whatever runs between their stones, and give none of it back." },
  Ashcombe: { arms: "A burning torch, gold on red", character: "They set their old lord's granaries alight and called it justice. Ashcombe burns bright, and its neighbours watch the sparks." },
  Redmane: { arms: "A horse's head, on blood red", character: "Horse lords who rode out from under their liege in a single night. They raid fast, run faster, and bend the knee to no one twice." },
  Greymantle: { arms: "An empty hooded cloak, on grey", character: "No one knows whose face is under the hood. Greymantle speaks softly, pays its spies well, and was in the plot long before the plot began." },
  Duskmoor: { arms: "An owl, gold on dusk purple", character: "Watchers of the moors who saw their lord's weakness first and struck at night. Wise, they say. Others say patient, and cruel." },
  Stonecrest: { arms: "A mountain peak, on grey", character: "Highlanders who simply stopped coming down. They hold their crags against all comers, and are as easy to move as the mountain." },
  Ravenmoor: { arms: "A black raven on a pale moon", character: "Carrion birds who fed on a house in its dying. Ravenmoor arrives after every battle, and always seems to profit by it." },
  Brightwell: { arms: "An eight-pointed star, gold on night blue", character: "Zealots of a bright new order, sure the old house had lost the gods' favour. They promise a better realm, and burn those who doubt it." },
  Hollowmere: { arms: "A crescent moon over water", character: "Lake lords who hid behind their waters while their liege bled. Now they rule the shores, quiet, cold and hard to reach." },
  Vyrwel: { arms: "A coiled serpent, on green", character: "Poisoners, by every account but their own. Vyrwel rose by a cup of wine at the wrong feast, and has been toasting since." },
};
