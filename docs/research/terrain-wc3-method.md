# How Warcraft III-style RTS ground is made (and what we copy)

Mac, 2026-11-14, on the drawn-back Kingsmere view: "this terrain is unusable ... see how WC3 and others do it and just
replicate". We copy the method, never the art. From the World Editor and the shipped games:

1. **A small tileset, hand-painted.** WC3 maps use about 6-12 ground tiles (lush grass, dark grass, dirt, rough dirt, rock, sand, cobbles, leaves). Each tile is low-contrast: no high-frequency speckle, detail read at the RTS distance, never at the ground. AoE2 DE and Age of Mythology do the same with larger tiling paintings.
2. **Variation at a large scale.** Every tile has several hand-painted variants picked per cell (WC3), or a large soft colour wash over the tiling (AoE2 DE, Northgard), so a meadow is patches of lighter and darker green a few tiles across, never one flat colour or noise.
3. **Painted transitions, not lines.** Tiles meet through soft painted masks (WC3's blend masks, AoE2's blend modes): dirt runs ragged into grass, grass thins into sand at a shore. No outline, no stroke round a coast.
4. **Discrete relief.** WC3 has cliff levels with ramps; AoE2 and AoM have smooth hills shaded by the sun. Height is read from light and shadow, with a few strong steps, not from colour.
5. **Doodads over every tile.** Rocks, tufts, flowers, bushes and stumps are scattered densely and varied (size, turn, tint), so no patch of ground is bare paint.
6. **Trees as varied clusters.** Several models, each turned, sized and tinted a little differently, and grouped into woods with an edge of smaller trees and bushes (WC3's tree lines, Northgard's forests).
7. **Roads and paths are ground tiles.** Worn dirt painted into the ground, wide, with ragged grassy edges (WC3's dirt and rough dirt), not thin coloured lines on top.
8. **Fields are painted patches with hedged, soft edges** (AoE2 farms, Northgard's fields), set to the lie of the land, not sharp rectangles stamped at angles.
9. **Muted saturation.** The ground is the quietest thing on screen: units, banners and roofs carry the colour.
10. **Ours:** Terrain3D's ten painted layers are the tileset, ground.json macro is the large wash, the control map's overlay blends are the transitions, vegetation.gd and forest.gd scatter the doodads and trees, roads and fields are decals blended into the ground. This note's changes tune those; nothing is a second system.
