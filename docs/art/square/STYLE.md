# Kingsmere square set: concept art for Meshy image-to-3D

Eight pieces for Kingsmere's square, each drawn to match its counterpart in the art target
[`docs/art/target/01-town.jpg`](../target/01-town.jpg), made with the Codex CLI (headless `codex exec`) and fed to
Meshy image-to-3D (High Detail, Meshy 7.1, Multi-view, Meshy 7 texture 2K, Private). Results and judging:
[docs/research/meshy-square-set.md](../../research/meshy-square-set.md).

Files: `<name>_front.png` (the concept, one isolated 3/4 view on flat grey), `ref/<name>_ref.jpg` (the piece cropped
from 01-town.jpg, attached to Codex with `-i` as the design and finish reference), `pieces.tsv` (each piece's line),
`style.txt` (the fixed style prompt), `sheet.jpg` (crop above concept, all eight).

## How each image was made

```
codex exec --skip-git-repo-check -i ref/<name>_ref.jpg -- "<style.txt>

The asset: <line from pieces.tsv>"
```

The style prompt (fixed; reused word for word for every piece):

```
Style: a single original game asset concept for a stylised fantasy real-time strategy game, rendered like a polished stylised 3D game model with hand-painted textures, matching the attached reference crop (a storybook medieval market town in the spirit of Warcraft III Reforged): chunky readable shapes, slightly exaggerated proportions, thick timbers and chunky stones, soft painted textures with visible brush strokes, rich warm saturated colours (red clay tiles, golden thatch, cream plaster, dark oak timber, warm grey stone), warm even studio light, clean bold silhouette, every part solid and well defined, no loose cards or floating bits. The attached image is a crop from our town painting: copy its design, colours and finish, not its camera or surroundings. Show the WHOLE object alone, centred, in a three-quarter view from slightly above (about 25 degrees down), the front and one side both visible, the object filling about 80% of the image with clear space all around. Plain flat medium grey background, no ground, no ground plane, no shadow, no people, no animals, no smoke, no text, no logos, no frame. Square image. Original design, not any existing franchise asset.
```

## Notes (2026-11-12)

- All eight came out of one parallel batch, first try; none redone. The set reads as one family with 01-town:
  red clay tiles, golden thatch, cream plaster, dark oak, warm grey stone.
- No separate side/back views were drawn: Meshy's own multi-view generator (free) drew left, back and right from
  each concept, and its backs were checked before generating (the stall's back is a closed plank wall, as wanted).
- The statue is painted (steel, gilt crown, red cloak) rather than one-colour stone, as in 01-town.
