# Heraldry asset credits

## Aldmere lesser houses

- Date: 2026-11-05.
- The 26 emblem masters were created with OpenAI `image_gen.imagegen` (built-in tool). The tool did not report its model name or ID.
- Final export tool: ImageMagick 7.1.2-27. Each house has a 512 × 512 RGBA sigil and a 512 × 1024 RGBA banner.
- Style references: `banner-wolfholt.png`, `banner-thornvale.png`, `banner-highfell.png`, `sigil-wolfholt.png`, and `sigil-goldcrest.png`. No reference file was changed.
- The prompts below are the exact prompts sent to the image tool. No motto was added.

### Export method

Each pair uses one shared emblem mask. A 60% alpha threshold removes faint edge marks. Connected areas smaller than 64 source pixels are removed. The mask is trimmed, scaled to fit 448 × 448, and centred on a 512 × 512 canvas. All sigil RGB pixels are set to `#EDE6D6`; the mask supplies alpha. This gives one flat cream colour with clear open cuts and a transparent background.

The banner uses that same mask at offset `(0, 96)`. Its field and emblem use the colours in the table below. Ravenmoor has a black raven on a cream disc on its heather field; its sigil is only the same raven and branch in cream, with no disc. A clean field strip from `banner-wolfholt.png`, at `(0, 610, 512, 240)`, supplies the fine woven texture. The strip is mirrored and tiled, then limited to 12% tonal variation. The texture applies to the field and emblem. A separate alpha mask gives the swallowtail notch, with its apex at `(256, 852)` and the two tips at the bottom corners. No border, text, pole, or lighting was added.

All final pairs were opened together on dark backgrounds and checked at 32 px. File checks confirm size, one cream RGB colour for sigils, shared emblem masks, and transparent notches. SHA-256 checks confirm that all 40 files present in the heraldry folder before this task are unchanged.

### Banner colours

| House | Field | Emblem |
| --- | --- | --- |
| ashby | `#77776F` | `#EDE6D6` |
| greyford | `#4F6474` | `#D9DEDE` |
| hollin | `#244C36` | `#EDE6D6` |
| marsh | `#666B3D` | `#D9C990` |
| thorne | `#49372D` | `#E4D7BD` |
| varn | `#31353A` | `#C59B50` |
| crane | `#86ACBC` | `#FAF9F2` |
| dale | `#60734B` | `#EDE6D6` |
| brook | `#28686C` | `#E2E8E5` |
| fenwick | `#534336` | `#EDE6D6` |
| holt | `#274A3A` | `#D4B96A` |
| roswell | `#58646B` | `#EDE6D6` |
| kettle | `#4B5053` | `#CB956F` |
| morrow | `#A36F76` | `#EDE6D6` |
| pell | `#72563D` | `#DDCD93` |
| strand | `#497D73` | `#E2D0A6` |
| blackbrook | `#171B20` | `#D5DADD` |
| ashcombe | `#973F32` | `#D9B563` |
| redmane | `#6F2831` | `#EDE6D6` |
| greymantle | `#626B76` | `#F8F8F1` |
| duskmoor | `#51435E` | `#DECCA0` |
| stonecrest | `#787A76` | `#F7F7F0` |
| ravenmoor | `#766279` | `#17191B` on `#EDE6D6` disc |
| brightwell | `#26364F` | `#D7B85F` |
| hollowmere | `#254A69` | `#DCE3E7` |
| vyrwel | `#23483C` | `#E3D8BF` |

### Ashby

- Files: `banner-ashby.png`, `sigil-ashby.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original heraldic sigil master for House ashby in Aldmere.
Input image: the supplied banner-wolfholt.png is STYLE REFERENCE ONLY. Match its bold, austere, hand-cut woodcut shape language. Do not copy its wolf or cloth.
Primary request: an ash tree with a broad spreading crown, sturdy central trunk and three large roots; bold grouped foliage lobes, a few large negative-space cuts, no tiny leaves.
Create ONLY this single emblem, in one perfectly flat pale cream colour #EDE6D6, on a genuinely fully transparent PNG background. Square canvas. Centre the isolated emblem within the inner 84% of the square, with a small clear margin on all sides. Use broad simple solid shapes and a very few large transparent interior cuts; the subject must read clearly at 32 pixels. No texture or shading in the emblem. Original design, no franchise reference.
Avoid: text, letters, motto, outline, border, shield, disc, backdrop, checkerboard pixels, fabric, pole, gradients, shadows, bevel, realistic rendering, fine details, small linework, wolf, direwolf, stag, kraken, rose, lion, falcon, sun.
```

### Greyford

- Files: `banner-greyford.png`, `sigil-greyford.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original heraldic sigil master for House greyford in Aldmere.
Input image: the supplied banner-wolfholt.png is STYLE REFERENCE ONLY. Match its bold, austere, hand-cut woodcut shape language. Do not copy its wolf or cloth.
Primary request: one heron in side profile standing upright above exactly two broad wavy lines of water; long S-curved neck, long pointed beak, one visible bold standing leg, simple folded wing.
Create ONLY this single emblem, in one perfectly flat pale cream colour #EDE6D6, on a genuinely fully transparent PNG background. Square canvas. Centre the isolated emblem within the inner 84% of the square, with a small clear margin on all sides. Use broad simple solid shapes and a very few large transparent interior cuts; the subject must read clearly at 32 pixels. No texture or shading in the emblem. Original design, no franchise reference.
Avoid: text, letters, motto, outline, border, shield, disc, backdrop, checkerboard pixels, fabric, pole, gradients, shadows, bevel, realistic rendering, fine details, small linework, wolf, direwolf, stag, kraken, rose, lion, falcon, sun.
```

### Hollin

- Files: `banner-hollin.png`, `sigil-hollin.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original heraldic sigil master for House hollin in Aldmere.
Input image: the supplied banner-wolfholt.png is STYLE REFERENCE ONLY. Match its bold, austere, hand-cut woodcut shape language. Do not copy its wolf or cloth.
Primary request: one holly sprig with three large pointed holly leaves and exactly three round berries clustered at their junction; large bold serrations, no small veins.
Create ONLY this single emblem, in one perfectly flat pale cream colour #EDE6D6, on a genuinely fully transparent PNG background. Square canvas. Centre the isolated emblem within the inner 84% of the square, with a small clear margin on all sides. Use broad simple solid shapes and a very few large transparent interior cuts; the subject must read clearly at 32 pixels. No texture or shading in the emblem. Original design, no franchise reference.
Avoid: text, letters, motto, outline, border, shield, disc, backdrop, checkerboard pixels, fabric, pole, gradients, shadows, bevel, realistic rendering, fine details, small linework, wolf, direwolf, stag, kraken, rose, lion, falcon, sun.
```

### Marsh

- Files: `banner-marsh.png`, `sigil-marsh.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original heraldic sigil master for House marsh in Aldmere.
Input image: the supplied banner-wolfholt.png is STYLE REFERENCE ONLY. Match its bold, austere, hand-cut woodcut shape language. Do not copy its wolf or cloth.
Primary request: exactly three bulrushes with three thick oval seed heads on strong stems, and four broad pointed leaves; a compact unified upright composition.
Create ONLY this single emblem, in one perfectly flat pale cream colour #EDE6D6, on a genuinely fully transparent PNG background. Square canvas. Centre the isolated emblem within the inner 84% of the square, with a small clear margin on all sides. Use broad simple solid shapes and a very few large transparent interior cuts; the subject must read clearly at 32 pixels. No texture or shading in the emblem. Original design, no franchise reference.
Avoid: text, letters, motto, outline, border, shield, disc, backdrop, checkerboard pixels, fabric, pole, gradients, shadows, bevel, realistic rendering, fine details, small linework, wolf, direwolf, stag, kraken, rose, lion, falcon, sun.
```

### Thorne

- Files: `banner-thorne.png`, `sigil-thorne.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original heraldic sigil master for House thorne in Aldmere.
Input image: the supplied banner-wolfholt.png is STYLE REFERENCE ONLY. Match its bold, austere, hand-cut woodcut shape language. Do not copy its wolf or cloth.
Primary request: two stout thorn branches crossed in an X; broad triangular thorns spaced widely along the branches; no flowers, leaves or berries.
Create ONLY this single emblem, in one perfectly flat pale cream colour #EDE6D6, on a genuinely fully transparent PNG background. Square canvas. Centre the isolated emblem within the inner 84% of the square, with a small clear margin on all sides. Use broad simple solid shapes and a very few large transparent interior cuts; the subject must read clearly at 32 pixels. No texture or shading in the emblem. Original design, no franchise reference.
Avoid: text, letters, motto, outline, border, shield, disc, backdrop, checkerboard pixels, fabric, pole, gradients, shadows, bevel, realistic rendering, fine details, small linework, wolf, direwolf, stag, kraken, rose, lion, falcon, sun.
```

### Varn

- Files: `banner-varn.png`, `sigil-varn.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original heraldic sigil master for House varn in Aldmere.
Input image: the supplied banner-wolfholt.png is STYLE REFERENCE ONLY. Match its bold, austere, hand-cut woodcut shape language. Do not copy its wolf or cloth.
Primary request: a bear's paw print: one large broad lower pad and five bold separate toe pads in an arc, with short triangular claws; unmistakably bear paw, no other animal.
Create ONLY this single emblem, in one perfectly flat pale cream colour #EDE6D6, on a genuinely fully transparent PNG background. Square canvas. Centre the isolated emblem within the inner 84% of the square, with a small clear margin on all sides. Use broad simple solid shapes and a very few large transparent interior cuts; the subject must read clearly at 32 pixels. No texture or shading in the emblem. Original design, no franchise reference.
Avoid: text, letters, motto, outline, border, shield, disc, backdrop, checkerboard pixels, fabric, pole, gradients, shadows, bevel, realistic rendering, fine details, small linework, wolf, direwolf, stag, kraken, rose, lion, falcon, sun.
```

### Crane

- Files: `banner-crane.png`, `sigil-crane.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original heraldic sigil master for House crane in Aldmere.
Input image: the supplied banner-wolfholt.png is STYLE REFERENCE ONLY. Match its bold, austere, hand-cut woodcut shape language. Do not copy its wolf or cloth.
Primary request: one crane bird in flight in side view, long neck extended forward, long legs trailing backward, two powerful raised wings with just a few broad feather cuts; slender pointed beak; clearly a crane, never a falcon or other raptor.
Create ONLY this single emblem, in one perfectly flat pale cream colour #EDE6D6, on a genuinely fully transparent PNG background. Square canvas. Centre the isolated emblem within the inner 84% of the square, with a small clear margin on all sides. Use broad simple solid shapes and a very few large transparent interior cuts; the subject must read clearly at 32 pixels. No texture or shading in the emblem. Original design, no franchise reference.
Avoid: text, letters, motto, outline, border, shield, disc, backdrop, checkerboard pixels, fabric, pole, gradients, shadows, bevel, realistic rendering, fine details, small linework, wolf, direwolf, stag, kraken, rose, lion, falcon, sun.
```

### Dale

- Files: `banner-dale.png`, `sigil-dale.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

First prompt; rounded-hill correction follows:

```text
Use case: logo-brand. Asset type: original medieval house heraldry sigil master for Aldmere. Reference image is STYLE REFERENCE ONLY: match the bold angular woodcut silhouette language of the pale wolf emblem, do NOT depict or copy its subject. Subject: exactly three rounded hills, a central hill slightly taller and two lower flanking hills, a compact joined shape with two broad transparent valleys, no scenery or ground details. Make ONE isolated flat single-color pale cream #EDE6D6 silhouette on a genuinely fully transparent square canvas with alpha. Bold clean simplified hand-cut shapes, broad connected masses, only a few wide negative cuts, readable at 32px. Emblem occupies central 84% of the square, with at least 8% clear margin on every side. No texture, shading, gradients, outline, border, badge, shield, letters, text, shadow, grey/white backdrop, checkerboard, realism, tiny details or extra symbols. Original design; no existing franchise crest, direwolf, stag, kraken, rose, lion, falcon or sun. Generate only the transparent cream emblem.
```

Final master prompt:

```text
Use case: logo-brand.
Asset type: original Aldmere House Dale heraldic sigil master.
Primary request: EXACTLY THREE ROUNDED HILLS, smooth low domes of rolling countryside. The upper centre hill is slightly behind two lower foreground hills.
Shape requirement: each hill has a broad SMOOTH SEMICIRCULAR ROUND TOP, gently sloping soft curving sides. No angular points anywhere on the hilltops. Draw the contours as large continuous arcs. These must look like three rounded grassy mounds, never mountains, pyramids, triangles, pointed peaks, teeth or a crown. All three hilltops plainly visible. Broad joined base and two broad negative-space curving cuts separate the three domed masses.
Style: simple original medieval heraldic woodcut silhouette with bold substantial flat masses; readable at 32 pixels. Smooth round hill contours are mandatory even within the woodcut style.
Colour: one flat pale cream #EDE6D6 on fully transparent background with alpha; negative cuts transparent. No texture, shading, shadows, gradients, outline, backdrop, scenery, ground lines, grass, trees, snow, sun or other objects.
Composition: square canvas, emblem centred; three rounded hills occupy central 84% width and about 55% height, transparent margin all round.
No text, letters, border, shield, watermark or franchise imagery.
```

### Brook

- Files: `banner-brook.png`, `sigil-brook.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original medieval house heraldry sigil master for Aldmere. Reference image is STYLE REFERENCE ONLY: match the bold angular woodcut silhouette language of the pale wolf emblem, do NOT depict or copy its subject. Subject: one leaping salmon arched upward in side profile, muscular curved body, open tail and bold fins, one small clear eye knockout only, no water or other elements. Make ONE isolated flat single-color pale cream #EDE6D6 silhouette on a genuinely fully transparent square canvas with alpha. Bold clean simplified hand-cut shapes, broad connected masses, only a few wide negative cuts, readable at 32px. Emblem occupies central 84% of the square, with at least 8% clear margin on every side. No texture, shading, gradients, outline, border, badge, shield, letters, text, shadow, grey/white backdrop, checkerboard, realism, tiny details or extra symbols. Original design; no existing franchise crest, direwolf, stag, kraken, rose, lion, falcon or sun. Generate only the transparent cream emblem.
```

### Fenwick

- Files: `banner-fenwick.png`, `sigil-fenwick.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original medieval house heraldry sigil master for Aldmere. Reference image is STYLE REFERENCE ONLY: match the bold angular woodcut silhouette language of the pale wolf emblem, do NOT depict or copy its subject. Subject: one otter in a compact horizontal side profile with a round head, short legs and a thick tapering sweeping tail, a simple clear snout and one eye knockout, no water or props. Make ONE isolated flat single-color pale cream #EDE6D6 silhouette on a genuinely fully transparent square canvas with alpha. Bold clean simplified hand-cut shapes, broad connected masses, only a few wide negative cuts, readable at 32px. Emblem occupies central 84% of the square, with at least 8% clear margin on every side. No texture, shading, gradients, outline, border, badge, shield, letters, text, shadow, grey/white backdrop, checkerboard, realism, tiny details or extra symbols. Original design; no existing franchise crest, direwolf, stag, kraken, rose, lion, falcon or sun. Generate only the transparent cream emblem.
```

### Holt

- Files: `banner-holt.png`, `sigil-holt.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original medieval house heraldry sigil master for Aldmere. Reference image is STYLE REFERENCE ONLY: match the bold angular woodcut silhouette language of the pale wolf emblem, do NOT depict or copy its subject. Subject: one large upright acorn with a broad cup and exactly TWO simple lobed oak leaves flanking it, strong stem connects leaves and acorn into one compact emblem, no other acorns, no extra leaves. Make ONE isolated flat single-color pale cream #EDE6D6 silhouette on a genuinely fully transparent square canvas with alpha. Bold clean simplified hand-cut shapes, broad connected masses, only a few wide negative cuts, readable at 32px. Emblem occupies central 84% of the square, with at least 8% clear margin on every side. ALL INTERNAL CUTOUTS must be genuinely transparent, never gray. Sharp clean solid silhouette, no ragged speckles or haloes. No texture, shading, gradients, outline, border, badge, shield, letters, text, shadow, grey/white backdrop, checkerboard, realism, tiny details or extra symbols. Original design; no existing franchise crest, direwolf, stag, kraken, rose, lion, falcon or sun. Generate only the transparent cream emblem.
```

### Roswell

- Files: `banner-roswell.png`, `sigil-roswell.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original medieval house heraldry sigil master for Aldmere. Reference image is STYLE REFERENCE ONLY: match the bold angular woodcut silhouette language of the pale wolf emblem, do NOT depict or copy its subject. Subject: one stone well with one bucket, a stout round stone well shown in simple front elevation with a thick rim, only two broad masonry cuts, two uprights and a plain lintel holding the small bucket centrally above the well mouth, no roof, no fine rope or shading. Make ONE isolated flat single-color pale cream #EDE6D6 silhouette on a genuinely fully transparent square canvas with alpha. Bold clean simplified hand-cut shapes, broad connected masses, only a few wide negative cuts, readable at 32px. Emblem occupies central 84% of the square, with at least 8% clear margin on every side. ALL INTERNAL CUTOUTS must be genuinely transparent, never gray. Sharp clean solid silhouette, no ragged speckles or haloes. No texture, shading, gradients, outline, border, badge, shield, letters, text, shadow, grey/white backdrop, checkerboard, realism, tiny details or extra symbols. Original design; no existing franchise crest, direwolf, stag, kraken, rose, lion, falcon or sun. Generate only the transparent cream emblem.
```

### Kettle

- Files: `banner-kettle.png`, `sigil-kettle.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original medieval house heraldry sigil master for Aldmere. Reference image is STYLE REFERENCE ONLY: match the bold angular woodcut silhouette language of the pale wolf emblem, do NOT depict or copy its subject. Subject: one broad round cauldron with a thick rim and exactly THREE stout splayed legs clearly visible below it; a large clean bowl-like vessel, one small broad ear handle at each side, no fire, steam, utensils or contents. Make ONE isolated flat single-color pale cream #EDE6D6 silhouette on a genuinely fully transparent square canvas with alpha. Bold clean simplified hand-cut shapes, broad connected masses, only a few wide negative cuts, readable at 32px. Emblem occupies central 84% of the square, with at least 8% clear margin on every side. ALL INTERNAL CUTOUTS must be genuinely transparent, never gray. Sharp clean solid silhouette, no ragged speckles or haloes. No texture, shading, gradients, outline, border, badge, shield, letters, text, shadow, grey/white backdrop, checkerboard, realism, tiny details or extra symbols. Original design; no existing franchise crest, direwolf, stag, kraken, rose, lion, falcon or sun. Generate only the transparent cream emblem.
```

### Morrow

- Files: `banner-morrow.png`, `sigil-morrow.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset type: original medieval house heraldry sigil master for Aldmere. Reference image is STYLE REFERENCE ONLY: match the bold angular woodcut silhouette language of the pale wolf emblem, do NOT depict or copy its subject. Subject: one bold cockerel in side profile standing proudly, clear short beak and upright comb, rounded chest, two stout separated legs, sweeping three-lobed tail, a few broad wing and feather cutouts only, compact readable silhouette, no ground or props. Make ONE isolated flat single-color pale cream #EDE6D6 silhouette on a genuinely fully transparent square canvas with alpha. Bold clean simplified hand-cut shapes, broad connected masses, only a few wide negative cuts, readable at 32px. Emblem occupies central 84% of the square, with at least 8% clear margin on every side. ALL INTERNAL CUTOUTS must be genuinely transparent, never gray. Sharp clean solid silhouette, no ragged speckles or haloes. No texture, shading, gradients, outline, border, badge, shield, letters, text, shadow, grey/white backdrop, checkerboard, realism, tiny details or extra symbols. Original design; no existing franchise crest, direwolf, stag, kraken, rose, lion, falcon or sun. Generate only the transparent cream emblem.
```

### Pell

- Files: `banner-pell.png`, `sigil-pell.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand.
Asset type: original Aldmere heraldic sigil master.
Primary request: ONE original bold woodcut silhouette of a medieval hand plough, the emblem of House Pell.
Input image 1 is a style reference only: match the broad angular carved silhouette of the wolf emblem, but do not copy its animal.
Subject: a sturdy old plough in side profile, a broad hooked ploughshare at the ground, diagonal beam and two clearly separate hand grips. Use a strong simple recognisable silhouette and a few large transparent negative cuts. No wheel, ox, person, ground, badge, crest or other object.
Style: austere flat medieval heraldic woodcut, bold angular edges, readable at 32 pixels; avoid fine detail.
Colour: every solid pixel the same flat pale cream #EDE6D6. Transparent background and negative spaces. No texture, outline, shadow, gradient, lighting, realism or colour variation.
Composition: square transparent canvas, emblem centred, fills about 84% of width or height, at least 8% transparent margin on every side.
No text, letters, numbers, border, watermark, motto, shield or franchise imagery. Original design only.
```

### Strand

- Files: `banner-strand.png`, `sigil-strand.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand.
Asset type: original Aldmere heraldic sigil master for House strand.
Primary request: ONE original bold woodcut silhouette emblem of a single scallop shell, broad fan-shaped rounded upper rim, scalloped edge and narrow hinge below. Seven broad radial lobes with large open negative-space separations, no fine grooves; symmetrical, unmistakable shell silhouette.
Input image 1 is a style reference only: match the broad angular carved silhouette of the wolf emblem; do not copy its animal.
Style: austere flat medieval heraldic woodcut, bold simple shapes and broad negative cuts; readable at 32 pixels; avoid fine detail.
Colour: every solid pixel the same flat pale cream #EDE6D6. Fully transparent background and negative spaces. No texture, outline, shadow, gradient, lighting, realism or colour variation.
Composition: square transparent canvas, centred single emblem group, fills about 84% of width or height, at least 8% transparent margin on every side.
No text, letters, numbers, border, watermark, motto, shield, lion, direwolf, stag, kraken, rose, falcon, sun or franchise imagery. Original design only.
```

### Blackbrook

- Files: `banner-blackbrook.png`, `sigil-blackbrook.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand.
Asset type: original Aldmere heraldic sigil master for House blackbrook.
Primary request: ONE original bold woodcut silhouette emblem of a winding river bend between EXACTLY TWO large irregular stones. One thick S-shaped river band, one solid chunky stone on each opposite side of the bend. Clearly three dominant shapes. The river must read as a flowing bend, not a snake; no waves, scenery or extra rocks.
Input image 1 is a style reference only: match the broad angular carved silhouette of the wolf emblem; do not copy its animal.
Style: austere flat medieval heraldic woodcut, bold simple shapes and broad negative cuts; readable at 32 pixels; avoid fine detail.
Colour: every solid pixel the same flat pale cream #EDE6D6. Fully transparent background and negative spaces. No texture, outline, shadow, gradient, lighting, realism or colour variation.
Composition: square transparent canvas, centred single emblem group, fills about 84% of width or height, at least 8% transparent margin on every side.
No text, letters, numbers, border, watermark, motto, shield, lion, direwolf, stag, kraken, rose, falcon, sun or franchise imagery. Original design only.
```

### Ashcombe

- Files: `banner-ashcombe.png`, `sigil-ashcombe.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand.
Asset type: original Aldmere heraldic sigil master for House ashcombe.
Primary request: ONE original bold woodcut silhouette emblem of a single upright burning torch, thick tapered wooden handle and simple broad three-tongued flame above. One bold cut separates handle and flame, one large negative cut within the flame. No smoke, sparks, sun or ornamental wrapping.
Input image 1 is a style reference only: match the broad angular carved silhouette of the wolf emblem; do not copy its animal.
Style: austere flat medieval heraldic woodcut, bold simple shapes and broad negative cuts; readable at 32 pixels; avoid fine detail.
Colour: every solid pixel the same flat pale cream #EDE6D6. Fully transparent background and negative spaces. No texture, outline, shadow, gradient, lighting, realism or colour variation.
Composition: square transparent canvas, centred single emblem group, fills about 84% of width or height, at least 8% transparent margin on every side.
No text, letters, numbers, border, watermark, motto, shield, lion, direwolf, stag, kraken, rose, falcon, sun or franchise imagery. Original design only.
```

### Redmane

- Files: `banner-redmane.png`, `sigil-redmane.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand.
Asset type: original Aldmere heraldic sigil master for House redmane.
Primary request: ONE original bold woodcut silhouette emblem of a horse head in left-facing profile with a broad flowing mane sweeping back to the right. Long equine face, upright short ears and elegant thick arched neck, bold wind-shaped mane locks. No bridle, crown, chess base, shield or full body; a natural heraldic horse, never a chess knight.
Input image 1 is a style reference only: match the broad angular carved silhouette of the wolf emblem; do not copy its animal.
Style: austere flat medieval heraldic woodcut, bold simple shapes and broad negative cuts; readable at 32 pixels; avoid fine detail.
Colour: every solid pixel the same flat pale cream #EDE6D6. Fully transparent background and negative spaces. No texture, outline, shadow, gradient, lighting, realism or colour variation.
Composition: square transparent canvas, centred single emblem group, fills about 84% of width or height, at least 8% transparent margin on every side.
No text, letters, numbers, border, watermark, motto, shield, lion, direwolf, stag, kraken, rose, falcon, sun or franchise imagery. Original design only.
```

### Greymantle

- Files: `banner-greymantle.png`, `sigil-greymantle.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand.
Asset type: original Aldmere heraldic sigil master for House greymantle.
Primary request: ONE original bold woodcut silhouette emblem of one EMPTY hooded cloak, front view, a broad pointed hood with a large fully transparent empty face opening; two heavy cloak sides drape down and flare outward slightly, with a wide empty gap between them. No person, face, head, hands, body, skull, eyes, clasps or weapons. A clear empty garment silhouette.
Input image 1 is a style reference only: match the broad angular carved silhouette of the wolf emblem; do not copy its animal.
Style: austere flat medieval heraldic woodcut, bold simple shapes and broad negative cuts; readable at 32 pixels; avoid fine detail.
Colour: every solid pixel the same flat pale cream #EDE6D6. Fully transparent background and negative spaces. No texture, outline, shadow, gradient, lighting, realism or colour variation.
Composition: square transparent canvas, centred single emblem group, fills about 84% of width or height, at least 8% transparent margin on every side.
No text, letters, numbers, border, watermark, motto, shield, lion, direwolf, stag, kraken, rose, falcon, sun or franchise imagery. Original design only.
```

### Duskmoor

- Files: `banner-duskmoor.png`, `sigil-duskmoor.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset: original Aldmere medieval house sigil, one isolated single-colour cream (#EDE6D6) silhouette on genuinely fully transparent alpha background. Match the attached existing wolf BANNER's bold spare hand-cut woodcut shape language, but make an original new emblem. No wolf or other existing franchise motif. Broad solid shapes, a few large negative-space cuts only, distinct and legible downsampled to 32 pixels. Square image, whole emblem inside central 84%, centred, modest transparent margin. No colour variations, no texture, no shading, no outline, no shadow, no text, no letters, no border, no shield, no background plane. Subject: one solemn front-facing owl with wings FOLDED along its body; compact earless rounded head, two bold eye cutouts and a small beak cut, wide stocky body, two clear folded-wing cuts and small feet. No spread wings. Avoid intricate feather patterns.
```

### Stonecrest

- Files: `banner-stonecrest.png`, `sigil-stonecrest.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset: original Aldmere medieval house sigil, one isolated single-colour cream (#EDE6D6) silhouette on genuinely fully transparent alpha background. Match the attached existing wolf BANNER's bold spare hand-cut woodcut shape language, but make an original new emblem. No wolf or other existing franchise motif. Broad solid shapes, a few large negative-space cuts only, distinct and legible downsampled to 32 pixels. Square image, whole emblem inside central 84%, centred, modest transparent margin. No colour variations, no texture, no shading, no outline, no shadow, no text, no letters, no border, no shield, no background plane. Subject: ONE single angular mountain peak, bold triangular silhouette with irregular rock shoulder and one broad diagonal snow-cleft negative space. One mountain only, broad solid base. No range, no scene, no sun, no moon.
```

### Ravenmoor

- Files: `banner-ravenmoor.png`, `sigil-ravenmoor.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
Use case: logo-brand. Asset: original Aldmere medieval house sigil, one isolated single-colour cream (#EDE6D6) silhouette on genuinely fully transparent alpha background. Match the attached existing wolf BANNER's bold spare hand-cut woodcut shape language, but make an original new emblem. No wolf or other existing franchise motif. Broad solid shapes, a few large negative-space cuts only, distinct and legible downsampled to 32 pixels. Square image, whole emblem inside central 84%, centred, modest transparent margin. No colour variations, no texture, no shading, no outline, no shadow, no text, no letters, no border, no shield, no background plane. Subject: ONE raven in side profile perched on one short angular branch. Heavy straight raven beak, folded wing as a single broad cut, angular tail and sturdy feet, one short branch below. The isolated raven and branch must be pale cream; DO NOT include a disc or any background (disc will be added only on the banner at export). Not an eagle or falcon.
```

### Brightwell

- Files: `banner-brightwell.png`, `sigil-brightwell.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
undefinedSubject: ONE eight-pointed star with exactly EIGHT sharp rays, alternating four long cardinal points and four slightly shorter diagonal points. Solid centre, straight broad tapering points, simple bold heraldic star. No enclosing circle, no sun face, no rays beyond the eight points, no ornament.
```

Transparent emblem extraction prompt:

```text
Use case: background-extraction. Edit target: supplied image of the brightwell emblem on a gray cloth banner. Extract ONLY the pale emblem in the upper half. REMOVE ALL gray cloth, the entire banner rectangle and its swallowtail notch; none of the banner may remain. Keep the emblem silhouette exactly, including all internal open cutouts. Export it as one flat pale cream #EDE6D6 shape on GENUINELY TRANSPARENT alpha background, square canvas, with small equal margins, no fabric, no texture, no shading, no colors, no outline, no shadow, no box. This is a standalone sigil cutout, not a banner.  ONE eight-pointed star with exactly EIGHT sharp rays, alternating four long cardinal points and four slightly shorter diagonal points. Solid centre, straight broad tapering points, simple bold heraldic star. No enclosing circle, no sun face, no rays beyond the eight points, no ornament.
```

### Hollowmere

- Files: `banner-hollowmere.png`, `sigil-hollowmere.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
undefinedSubject: ONE upright crescent moon above ONE thick gently wavy horizontal water line. Bold smooth crescent with open side to the right; water line separated below it. Compact balanced emblem. No star, no sun, no scene, no extra wave lines.
```

Transparent emblem extraction prompt:

```text
Use case: background-extraction. Edit target: supplied image of the hollowmere emblem on a gray cloth banner. Extract ONLY the pale emblem in the upper half. REMOVE ALL gray cloth, the entire banner rectangle and its swallowtail notch; none of the banner may remain. Keep the emblem silhouette exactly, including all internal open cutouts. Export it as one flat pale cream #EDE6D6 shape on GENUINELY TRANSPARENT alpha background, square canvas, with small equal margins, no fabric, no texture, no shading, no colors, no outline, no shadow, no box. This is a standalone sigil cutout, not a banner.  ONE upright crescent moon above ONE thick gently wavy horizontal water line. Bold smooth crescent with open side to the right; water line separated below it. Compact balanced emblem. No star, no sun, no scene, no extra wave lines.
```

### Vyrwel

- Files: `banner-vyrwel.png`, `sigil-vyrwel.png`.
- Tool: OpenAI `image_gen.imagegen` (built-in tool); export: ImageMagick 7.1.2-27; date: 2026-11-05.

Master prompt:

```text
undefinedSubject: ONE coiled serpent forming a compact two-loop upright S-shaped coil, a single snake head raised above the coil, large wedge head and closed mouth, one tapering tail clearly distinct from head. Bold smooth body with one or two broad open negative-space gaps. No scales, no tiny tongue, no wings, no limbs, no ouroboros, no knot. An original simple coiled snake.
```

Transparent emblem extraction prompt:

```text
Use case: background-extraction. Edit target: supplied image of the vyrwel emblem on a gray cloth banner. Extract ONLY the pale emblem in the upper half. REMOVE ALL gray cloth, the entire banner rectangle and its swallowtail notch; none of the banner may remain. Keep the emblem silhouette exactly, including all internal open cutouts. Export it as one flat pale cream #EDE6D6 shape on GENUINELY TRANSPARENT alpha background, square canvas, with small equal margins, no fabric, no texture, no shading, no colors, no outline, no shadow, no box. This is a standalone sigil cutout, not a banner.  ONE coiled serpent forming a compact two-loop upright S-shaped coil, a single snake head raised above the coil, large wedge head and closed mouth, one tapering tail clearly distinct from head. Bold smooth body with one or two broad open negative-space gaps. No scales, no tiny tongue, no wings, no limbs, no ouroboros, no knot. An original simple coiled snake.
```
