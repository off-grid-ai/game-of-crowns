# The painted-face style (generated faces)

One fixed prompt for every generated face, so generated and museum faces read as one painter's
(references: Game of Thrones key art's gritty painted look, set around 900 AD: Mac 2026-11-14, 'game of thrones is swords, shields, and arrows ... we're looking at more 900AD'; the museum faces are gone, every face is generated). `gen.py` reads the block below as is and fills in `{subject}`. Change it
only with a judged before/after: every generated face must be made again when it changes.
After generation, each face goes through build.py's crop (YuNet, eyes on one line) and grade
(warm varnish, vignette), the same as the museum faces.

```
A painted character portrait in the gritty cinematic look of Game of Thrones key art (an original character, not any
actor), set around 900 AD in the Viking and Anglo-Saxon age: {subject}. Realistic digital oil painting, dramatic
low-key side light, a muted palette of greys, browns, dark reds and ochre, weathered, unwashed and grimy
skin, scars, beards and braids where they fit: someone who has lived through a war, not a posed portrait. Hard
light out of darkness, desaturated. Furs, leather and rough wool for most; rich dyed wool and silk only for the
highest lords and ladies. Dress and gear of 900 AD only: wool tunics, cloaks pinned with bronze brooches, furs, leather, linen
headrails and apron dresses with oval brooches for women, mail shirts, padded tunics, conical nasal helms, round
painted wooden shields with iron bosses, spears, Dane axes, seaxes, short bows and arrows. Nothing later: no plate
armour, no surcoats, no hoods with tails, no tall headdresses, no lace, no ruffs, no brimmed hats. Chest-up,
three-quarter view, the head in the upper middle of the picture with a little dark space above it, one person only,
a dark smoky haze behind. Natural hands, five fingers. No text, no frame, no crown. Portrait orientation, 3:4.
```

Subjects are plain and specific: age, sex, one or two features of face and dress
("an old woman of about seventy, deep lines around the eyes, white linen cap, dark wool gown").
