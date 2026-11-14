// Turns Freeciv's raw events into chronicle sentences and gives the realm
// its own names: great houses instead of nations, fantasy towns instead of
// real-world city names.
import { say } from "./say.js";  // several wordings per line (data/results.json event.*)

export const HOUSES = {
  scottish: { name: "House Wolfholt", seat: "the cold North", words: "Hold Fast", color: "#9aa6b2", sigil: "wolf" },
  english: { name: "House Goldcrest", seat: "the Western hills", words: "Wealth Is Strength", color: "#d4a62a", sigil: "lion" },
  norwegian: { name: "House Ironreach", seat: "the grey islands", words: "The Sea Provides", color: "#3d4a52", sigil: "kraken" },
  french: { name: "House Thornvale", seat: "the green valleys", words: "Root and Thorn", color: "#4f8a3c", sigil: "rose" },
  welsh: { name: "House Stormhold", seat: "the storm coast", words: "We Weather All", color: "#b8862b", sigil: "stag" },
  castilian: { name: "House Sunspire", seat: "the sands of the South", words: "The Sun Waits", color: "#c2562a", sigil: "sun" },
  irish: { name: "House Highfell", seat: "the high passes", words: "Sworn and Steadfast", color: "#4a7bb7", sigil: "falcon" },
  norman: { name: "The Crown", seat: "Kingsmere", words: "One Realm", color: "#b8202a", sigil: "crown", crown: true },
  animals: { name: "the wild beasts", color: "#6b5a44", sigil: "beast", wild: true },
  barbarian: { name: "barbarian raiders", color: "#7a2222", sigil: "skull", wild: true },
  pirate: { name: "sea raiders", color: "#2a2a3a", sigil: "skull", wild: true },
};

// Each house's own name is its key: what art and lore are found by, whatever
// the player calls it (names.js shows their name, never touching `key`).
for (const h of Object.values(HOUSES)) h.key = h.name;

export function houseFor(player) {
  const nation = String(player?.nation || "").toLowerCase();
  if (HOUSES[nation]) return HOUSES[nation];
  if (nation.includes("animal")) return HOUSES.animals;
  if (player?.name === "The Dead") return { name: "The Dead", color: "#9fb4c8", sigil: "skull", wild: true };
  if (nation.includes("pirate")) return HOUSES.pirate;
  if (nation.includes("barbarian")) return HOUSES.barbarian;
  // Houses born from civil war get a name and colour of their own.
  let h = 0;
  for (const ch of String(player?.name ?? "x")) h = (Math.imul(h, 31) + ch.charCodeAt(0)) >>> 0;
  const name = ["Blackbrook", "Ashcombe", "Redmane", "Greymantle", "Duskmoor", "Stonecrest", "Ravenmoor", "Brightwell", "Hollowmere", "Vyrwel"][h % 10];
  const color = ["#7d4e8f", "#8f3b3b", "#3b6f8f", "#6f8f3b", "#8f6f3b", "#3b8f7a", "#5b5b8f", "#8f3b6f", "#a0a03b", "#3b3b3b"][(h >>> 4) % 10];
  return { name: `House ${name}`, seat: "lands torn from an older house", words: "Our Own", color, sigil: "banner" };
}

const PREFIX = ["Winter", "Storm", "High", "Gold", "Iron", "Thorn", "Raven", "Eagle", "Red", "White", "Black", "Grey",
  "Sun", "Moon", "Raven", "Wolf", "Stag", "Lion", "Rose", "Salt", "Bitter", "Deep", "Old", "King's", "Maiden",
  "Ash", "Sea", "River", "Wind", "Frost", "Oak", "Bright", "Hollow", "Crow", "Stone", "Silver"];
const SUFFIX = ["fell", "hold", "watch", "ford", "haven", "gate", "keep", "mere", "spire", "wood", "march", "hall",
  "stone", "bridge", "crag", "vale", "rock", "reach", "cross", "moor", "burg", "port", "barrow", "field", "garden"];

// Towns named in the world bible keep their names; the rest get a fitting one.
const AUTHORED = new Set(["Kingsmere", "Stonefell", "Wintermoor", "Frostwatch", "Goldrock", "Gildport", "Silverhill",
  "Saltkeep", "Rook Hollow", "Rosehall", "Elder Reach", "Bitterford", "Stormwatch", "Rainhold", "Sunspire",
  "Redsands", "Saltmarsh", "Highfell", "Gullhaven"]);
let names = {};

export function rememberNames(world) {
  for (const c of world?.cities ?? []) names[c.id] = c.name;
}

// A town's name in a world that isn't the one being played (the baseline the
// Lore shows): its own authored name, else the name its id always gets.
export function nameIn(id, name) {
  return AUTHORED.has(name) ? name : generatedName(id);
}

export function cityName(id) {
  const given = names[Number(id)];
  if (given && AUTHORED.has(given)) return given;
  return generatedName(id);
}

function generatedName(id) {
  let h = (Number(id) * 2654435761) >>> 0;
  const p = PREFIX[h % PREFIX.length];
  h = Math.imul(h ^ (h >>> 15), 2246822507) >>> 0;
  const s = SUFFIX[h % SUFFIX.length];
  // "King's" + "spire" reads as two words: "King's Spire".
  return p.endsWith("'s") ? `${p} ${s[0].toUpperCase()}${s.slice(1)}` : p + s;
}

function owner(world, id) {
  const p = world?.players?.find((pl) => pl.id === Number(id));
  return houseFor(p).name;
}

function town(id) {
  return cityName(id);
}

const NOTABLE_BUILDINGS = {
  "City Walls": (c, h) => say("event.walls", { town: c, house: h }),
  Temple: (c, h) => say("event.sept", { town: c, house: h }),
  Granary: (c, h) => `${c} builds a great granary, remembering hungry winters.`,
  Barracks: (c, h, turn) => `Barracks rise in ${c}. ${say("event.barracks", { house: h }, null, turn)}`,
  Cathedral: (c, h) => `A great sept rises over ${c}, the pride of ${h}.`,
  Harbor: (c, h) => `${c} opens its harbour to the sea.`,
  Colosseum: (c, h) => say("event.arena", { town: c, house: h }),
  Amphitheater: (c, h) => say("event.arena", { town: c, house: h }),
  "Great Wall": (c, h) => `${h} completes the Great Wall. Their enemies despair.`,
  Pyramids: (c, h) => `${h} raises the Pyramids at ${c}, a wonder of the age.`,
  "Hanging Gardens": (c, h) => `The Hanging Gardens bloom in ${c}. ${h} rejoices.`,
  "Great Library": (c, h) => `The Great Library opens in ${c}. Scholars flock to ${h}.`,
  Colossus: (c, h) => `A bronze Colossus stands over ${c}'s harbour.`,
  Lighthouse: (c, h) => `A great lighthouse burns above ${c}.`,
  "Temple of Artemis": (c, h) => `A temple to the moon goddess rises in ${c}.`,
  "Statue of Zeus": (c, h) => `${h} raises a statue of the thunder god at ${c}.`,
};

// What a house learning a craft looks like in the realm; other advances aren't news.
const NOTABLE_TECH = {
  "Bronze Working": "smiths cast bronze", "Iron Working": "smiths forge iron blades",
  "Monarchy": "lord holds court like a king", "Feudalism": "lord binds knights by oath",
  "Chivalry": "knights swear the vows of chivalry", "Masonry": "masons raise stone walls",
  "Mathematics": "engineers reckon siege engines", "Astronomy": "maesters chart the stars",
  "Philosophy": "scholars hold learned debate", "Monotheism": "septons preach one faith",
  "Horseback Riding": "riders break horses for war", "Writing": "clerks keep written records",
  "Currency": "lord mints coin", "Construction": "builders raise great halls",
  "The Wheel": "wrights build war carts", "Seafaring": "shipwrights lay down sea-going hulls",
  "Map Making": "captains chart the coasts", "Code of Laws": "lord sets the law down in writing",
};

export function describe(ev, world) {
  const c = ev.city !== undefined ? town(ev.city) : "";
  switch (ev.kind) {
    case "city_built":
      return say("event.founded", { house: owner(world, ev.owner), town: c });
    case "city_shrank":
      if (ev.reason === "famine") {
        const who = owner(world, ev.owner);
        return `Famine in ${c}. ${say("event.famine", { people: who === "The Crown" ? "the King's own people" : `the people of ${who}` }, null, Number(ev.turn))}`;
      }
      if (ev.reason === "plague") return `Plague sweeps through ${c}. ${say("event.plague", {}, null, Number(ev.turn))}`;
      if (ev.reason === "disaster") return `Disaster strikes ${c}; many are lost.`;
      if (ev.reason === "migration") return `Families abandon ${c}, seeking better lands.`;
      return null;
    case "city_destroyed":
      return Number(ev.destroyer) >= 0
        ? say("event.razed", { town: c, house: owner(world, ev.destroyer) })
        : `${c} is abandoned and falls to ruin.`;
    case "city_transferred":
      if (ev.reason === "conquest") return say("event.conquest", { to: owner(world, ev.to), town: c, from: owner(world, ev.from) });
      if (ev.reason === "civil_war") return `Civil war! ${c} breaks from ${owner(world, ev.from)}.`;
      if (ev.reason === "incite") return `${c} is bribed into revolt and opens its gates to ${owner(world, ev.to)}.`;
      return `${c} passes from ${owner(world, ev.from)} to ${owner(world, ev.to)}.`;
    case "disaster":
      return `${ev.disaster} strikes ${c}.`;
    case "building_built": {
      const f = NOTABLE_BUILDINGS[ev.building];
      return f ? f(c, owner(world, ev.owner), Number(ev.turn)) : null;
    }
    case "building_lost":
      // Freeciv also "loses" buildings when they go obsolete or are sold; only violence is news.
      if (!["sabotaged", "razed", "disaster", "conquered", "attacked"].includes(ev.reason)) return null;
      return `The ${ev.building.toLowerCase()} of ${c} ${/s$/i.test(ev.building) ? "are" : "is"} destroyed.`;
    case "tech":
      // Techs the realm starts with are granted by script; they aren't news.
      if (ev.source === "script" || Number(ev.turn) <= 1) return null;
      return NOTABLE_TECH[ev.tech] ? `${owner(world, ev.owner)}'s ${NOTABLE_TECH[ev.tech]}.` : null;
    case "seam_spent":
      return `The gold seam in ${owner(world, ev.owner)}'s hills is worked out. The miners walk away.`;
    default:
      return null;
  }
}
