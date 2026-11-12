# The royal army: concept art for Meshy image-to-3D

The army set by the route in [docs/art/STANDARDS.md](../STANDARDS.md) §6, replacing the KayKit chibi knight
(`armies/knight_v2`) and the KayKit-rider cavalry (`armies/cavalry`). Bar: [03-army](../target/03-army.jpg).
Crops from it in `ref/` (`knight_ref.jpg`, `cavalry_ref.jpg`). Our own designs, never a Blizzard unit.

- **knight**: one model serves as the foot knight (army.json `knights`) and, seated by `realm/tools/vat_bake.py`'s
  rider block, as the cavalry rider: one family, one spend. Made like the cast: `knight_front.png` (A-pose) and
  `knight_views.png` (side and back), the cast's framings.
- **horse**: a barded warhorse drawn over the CC0 horse's own render (`ref/horse_base.png`, the rig's five gaits), so
  `realm/tools/rig/rig_unit.py --kind horse` fits it to that rig, as the beasts were.

House colour: every part that wears the house's colour is drawn plain cream off-white (tabard, plume, cloak lining,
caparison), so the army shader's mask (`rig.json` mask: bright, unsaturated cloth) paints it per house.

## The style prompt (the cast's, for soldiers; fixed, word for word)

```
Style: a single original character concept for a stylised fantasy real-time strategy game, rendered like a polished stylised 3D game model with hand-painted textures, in the spirit of Warcraft III Reforged soldiers: chunky readable shapes, slightly exaggerated proportions (broad shoulders, large hands and feet, sturdy limbs, head a little large but adult proportions, never chibi), soft painted textures with visible brush strokes, painted steel with warm highlights, warm even studio light, clean bold silhouette, face readable at a distance. Medieval European heavy soldier of about 1300. Every cloth part that shows the army's colour is plain cream off-white (kept for house colour); no emblem, no heraldry, no pattern on it. Plain flat medium grey background, no ground, no shadow, no text, no logos, no frame. Original design, not any existing franchise character.
```

Framings: the cast's front and views prompts ([cast/STYLE.md](../cast/STYLE.md)), with the knight's sword in his
right hand pointing down and his shield on his left forearm (the man-at-arms' rigid-gear route).

The horse: the beasts' framing ([animals/STYLE.md](../animals/STYLE.md)) with the base render attached, and the line
in `pieces.tsv`.
