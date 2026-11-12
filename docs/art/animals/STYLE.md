# Farm beasts: concept art for Meshy image-to-3D

The realm's beasts (cow, sheep, pig, goat, hen, dog) in the cast's painted look, so people, animals and props read
as one set. Made with the Codex CLI (headless `codex exec`), fed to Meshy image-to-3D, then skinned onto the rigged
CC0 Quaternius base whose render is attached (`ref/<kind>_base.png`), so the model's shape fits that rig and every
clip the game plays keeps working (realm/tools/beast_rig.py). Each beast: `<kind>_front.png` (three-quarter front,
drawn over its base's pose, `ref/<kind>_base.png` attached). No views sheet: Meshy's own multi-view generator draws
the other sides, as for the square set. `sheet.jpg`: each base beside its concept.

## The style prompt (fixed; reused word for word, the cast's own adapted to beasts)

```
Style: a single original farm animal concept for a stylised fantasy real-time strategy game, rendered like a polished stylised 3D game model with hand-painted textures, in the spirit of Warcraft III Reforged: chunky readable shapes, slightly exaggerated proportions (sturdy legs, head a little large), soft painted textures with visible brush strokes on hair, wool and feathers, warm even studio light, clean bold silhouette, eyes and face readable at a distance. A medieval European farm beast of a hardy old breed, in natural earthy colours. Plain flat medium grey background, no ground, no shadow, no props, no harness, no text, no logos, no frame. Original design, not any existing franchise character.
```

## The framing (also fixed)

Front (base render attached: `codex exec --skip-git-repo-check -i ref/<kind>_base.png -- "<style>\n\n<front>\n\nThe animal: <line>"`):

```
The attached grey render is the body this animal will be fitted to: draw the animal in EXACTLY that pose, stance, camera angle and proportions (same head height, neck angle, leg positions and body length to height), standing naturally on all its feet, head level, mouth closed. Show ONE animal only, the whole body, centred, filling about 80% of the image width with clear grey space all round. Square image.
```

All six came out of one parallel batch, first try (2026-11-12); none redone.

## The beasts

| Kind | Base (rig and clips) | The animal |
|---|---|---|
| cow | Quaternius cow (Idle, Walk, WalkSlow, Run) | a small hardy red-brown medieval cow with short curved horns, a lighter muzzle and a pale belly |
| sheep | Quaternius sheep | a sturdy sheep with a thick cream fleece, dark brown face and legs, small curled horns |
| pig | Quaternius pig | a hairy medieval pig, bristly coat in rusty brown with darker patches, long snout, small ears forward |
| goat | Quaternius sheep's rig | a nanny goat, brown and white patched coat, short beard, swept-back horns, alert ears |
| hen | Quaternius chicken (Idle, Idle_Peck, Run) | a plump farmyard hen, warm brown speckled feathers, red comb and wattles, yellow legs |
| dog | Quaternius wolf (Idle, Walk, Eating, Gallop) | a medieval farm dog, a shaggy tan and brown herding dog with a darker back, floppy ears |
