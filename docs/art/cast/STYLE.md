# Townsfolk cast: concept art for Meshy image-to-3D

Fourteen townsfolk for Aldmere's streets and fields, made with the Codex CLI (headless `codex exec`) and fed to
Meshy image-to-3D. Each character has two images: `<name>_front.png` (full body, A-pose, front) and
`<name>_views.png` (the same character from the side and back, made with the front image attached as reference).

Style anchor: the approved man-at-arms (Downloads/f292a9bc…png) and the art targets in `docs/art/target`
(01-town's people). Our own designs, never a Blizzard character.

## The style prompt (fixed; reused word for word for every image)

```
Style: a single original character concept for a stylised fantasy real-time strategy game, rendered like a polished stylised 3D game model with hand-painted textures, in the spirit of Warcraft III Reforged townsfolk: chunky readable shapes, slightly exaggerated proportions (large hands and feet, sturdy limbs, head a little large), soft painted textures with visible brush strokes on cloth, warm even studio light, clean bold silhouette, face readable at a distance with clear simple features. Medieval European peasant world, earthy wool, linen and leather in muted browns, greens, greys and ochres, with one clear accent colour. One or two cloth pieces are plain undyed cream off-white (kept for house colour). Hands open and empty, holding nothing. Plain flat medium grey background, no ground, no shadow, no props, no text, no logos, no frame. Original design, not any existing franchise character.
```

## The two framings (also fixed)

Front:

```
Show ONE character only: full body from head to feet, centred, standing in a relaxed A-pose (arms angled about 30 degrees down from the shoulders, away from the body, palms open, feet slightly apart), facing straight to the camera, orthographic front view, whole figure filling about 80% of the image height with clear grey space above the head and below the feet. Square image.
```

Views (front image attached with `-i`):

```
The attached image is the front view of this exact character. Make a character turnaround sheet of the SAME character with identical clothes, colours, proportions and face: two full-body figures side by side on one plain flat grey background, left a strict side profile view facing left, right a back view. Same relaxed A-pose, empty open hands, same scale, feet on the same line. Landscape image.
```

## Cast

See `cast.tsv` (name, description) for each character's line; the prompt is STYLE + description + framing.

## Notes from the first set (2026-11-12)

- All 14 fronts came out of one batch with this prompt; the set reads as one family beside the man-at-arms
  (`sheet.jpg`). Only the town crier was redone: the first try drifted to an 18th-century pirate coat (brass buttons,
  buckle shoes, plumed cap), so his line now asks for plain 14th-century dress.
- Views were made with the front attached (`codex exec -i <front> -- "<prompt>"`; the `--` matters, `-i` eats the
  prompt otherwise). Clothes, colours and proportions hold in every pair. The side views mostly face right instead of
  left, which doesn't matter for Meshy.
- The cream pieces for house colour: farmer_m sash, farmer_f headscarf and apron, blacksmith neckerchief, miller cap
  and apron, stallholder hooded capelet, townswoman shawl, merchant sash, old_man hood, old_woman head cloth and apron,
  boy sash, girl pinafore, priest scapular, noble_lady veil and front panel, town_crier tabard.
