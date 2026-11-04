# Image assets to generate

Drop the finished files into `realm/assets/heraldry/` and `realm/assets/ground/` using the file names below; the game picks them up by name.

**Shared style line.** Append it to every heraldry prompt so the set matches:

> Medieval heraldry in the grounded style of Game of Thrones house sigils: bold flat shapes, strong silhouette readable at tiny sizes, no gradients, no text, no border frame, painted-cloth look, muted natural dyes.

---

## 1. House banners (the cloth on every standard, in battle and over towns)

Each one is a **tall banner cloth, 512 × 1024 PNG, portrait**. The sigil sits in the upper middle, the field fills the whole image edge to edge, and the bottom edge is swallow-tailed (a V notch). Use a subtle woven linen texture, slightly worn, with no pole and no background.

| File | Prompt |
|---|---|
| `banner-wolfholt.png` | A grey direwolf head, snarling, in pale ash-white on a field of cold slate grey (#9aa6b2 darkened). House of the frozen North. |
| `banner-goldcrest.png` | A rampant lion in deep crimson on a field of rich gold (#d4a62a). A wealthy western house. |
| `banner-ironreach.png` | A golden kraken, tentacles spread, on a field of iron black-blue (#3d4a52). Island reavers. |
| `banner-thornvale.png` | A single white rose with thorned stem on a field of deep green (#4f8a3c). A fertile southern-reach house. |
| `banner-stormhold.png` | A black crowned stag, leaping, on a field of storm amber (#b8862b). Stormlands lords. |
| `banner-sunspire.png` | A red sun pierced by a golden spear on a field of burnt orange (#c2562a). Desert south. |
| `banner-highfell.png` | A white falcon rising before a crescent moon on a field of sky blue (#4a7bb7). Mountain vale house. |
| `banner-crown.png` | A golden crown above a black raven, wings spread, on a field of royal blood red (#b8202a). The King's own banner. |
| `banner-dead.png` | No sigil. A tattered, frost-rimed pale blue-white cloth (#9fb4c8), torn and rotted, with faint hand-prints in ice. The banner of the dead. |
| `banner-rebel.png` | A broken crown in black on a field of ash grey. Carried by a usurper's host. |

## 2. Sigils alone (for the UI: house list, court, chronicle)

Each one is a **512 × 512 PNG with a transparent background**: the sigil only, single colour off-white (#ece6da), centred, filling about 80% of the frame. Same subjects as above: `sigil-wolfholt.png`, `sigil-goldcrest.png`, `sigil-ironreach.png`, `sigil-thornvale.png`, `sigil-stormhold.png`, `sigil-sunspire.png`, `sigil-highfell.png`, `sigil-crown.png`, `sigil-dead.png` (a skeletal hand), `sigil-rebel.png`.

Prompt form: *"[subject], heraldic sigil, single flat off-white silhouette on a transparent background, no text, no frame, bold readable shape"* + the shared style line.

## 3. Ground textures (painted onto the land: town squares, roads, fields)

Each one is **1024 × 1024, seamless and tileable, straight top-down, evenly lit, with no shadows or perspective**. They tile many times, so avoid any feature that would show as an obvious repeat.

| File | Prompt |
|---|---|
| `ground/square-cobbles.jpg` | Medieval town-square cobblestones, rounded grey-brown setts of uneven size, dirt and moss in the joints, worn smooth. Seamless tileable top-down texture. |
| `ground/road-dirt.jpg` | A packed dirt cart track, two faint wheel ruts, hoof prints, scattered pebbles and dry straw, light brown earth. Seamless tileable top-down texture. |
| `ground/field-wheat.jpg` | Ripe golden wheat field seen from directly above, dense stalks in faint parallel rows. Seamless tileable top-down texture. |
| `ground/field-green.jpg` | A young green barley field seen from directly above, neat furrow rows, dark soil between. Seamless tileable top-down texture. |
| `ground/field-fallow.jpg` | A freshly ploughed fallow field from above, dark brown furrows in parallel ridges, clods of earth. Seamless tileable top-down texture. |
| `ground/field-dead.jpg` | A failed, blighted crop field from above: grey-brown dead stalks, cracked dry soil. Seamless tileable top-down texture. Shown when a town starves. |

---

When they arrive, I'll wire them in: banners onto every standard and town flag, sigils into the UI, and the ground textures in place of the current placeholders. Fields will switch between wheat, green, fallow and dead with the town's food.
