# The painted-face style (generated faces)

One fixed prompt for every generated face, so generated and museum faces read as one painter's
(references: CK2's and King of Dragon Pass's painted courts; the museum set is Renaissance and
Dutch Golden Age oil). `gen.py` reads the block below as is and fills in `{subject}`. Change it
only with a judged before/after: every generated face must be made again when it changes.
After generation, each face goes through build.py's crop (YuNet, eyes on one line) and grade
(warm varnish, vignette), the same as the museum faces.

```
An oil portrait painting in the manner of a 16th–17th century Northern European master
(Holbein, Rembrandt, Frans Hals): {subject}. Half-length, three-quarter view, the head small in the picture with a
wide band of plain background above it (a quarter of the height), one sitter only, looking near
the viewer. Plain dark brown-green background. Soft warm window light from the upper left,
deep shadows, visible brushwork, a matte worn paint surface, aged yellowed varnish and fine craquelure, not
glossy or airbrushed. Period clothing of a
minor lord's household, no crown, no jewels of state, no religious symbols, no text, no
signature, no frame. Portrait orientation, 3:4.
```

Subjects are plain and specific: age, sex, one or two features of face and dress
("an old woman of about seventy, deep lines around the eyes, white linen cap, dark wool gown").
