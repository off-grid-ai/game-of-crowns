# Review: draft 1 of both cuts (2026-11-05)

## Checked
- `hyperframes check` passes on both (info notes only: the camera frames sit far outside their parents by design).
- Looked at: snapshots at every shot change and at 1 fps over both renders; frame 0 of each (the thumbnail) carries
  the first line; every crop was read at full size for clipped text, removed v1 features and edge slivers.
- Measured: share copies loudness-matched with a limiter (post-one −15.2 LUFS / −1.7 dBFS; 9:16 −16.1 / −2.4;
  one-call −13.9 / −2.5).
- Not checked: the sound was measured, never heard.

## Truth calls
- Every panel is a real frame from one run per cut; no UI is drawn except a pointer in one shot of one-call.
- one-call never says the temple caused the pikemen; post-one never says why Ysolde went unheard (the ledger
  notes a since-fixed patience bug behind that empty court).

## Weakest / next
- The world shots are stills with a slow push; clean moving takes (`tools/takes.sh`) replace them once rendered.
- one-call is a stand-in until a lord can be filmed bringing up the King's deed in his own words.
- 9:16 (`post-one-916/`, 27 s) drops the snow, odds and Riverhall shots: the Hand's odds sit at the bottom of their
  frame under a removed feature, so they can't fill a tall window honestly. A veil covers the houses table above the
  Hand's card in two shots for the same reason.

## Hold: no delivery render until the first-impression fixes land (docs/buzz/first-impression.md, 2026-11-05)
World shots that show those bugs today, each to be recaptured as a clean low-angle take (`tools/takes.sh`, once the
main session's fixes are pushed and it isn't relaunching):

| Shot | Source | Bugs seen | Recapture as |
|---|---|---|---|
| post-one b1, 9:16 v1, one-call s1 and s9 (hook, question) | intro still seat_Lionmoor | #7 cream boxes, #8 smoke disc, #9 castle slab, #1 per the list | `--clip=seat --city=<a seat>` or `--clip=realm` |
| post-one b9, one-call s3 | intro still seat_Riverhall | #8 white disc over the water, #10 flat light | `--clip=seat --city=Riverhall` |
| post-one b6 (Kingsmere in snow) | r14-siege/03 | #6 square stain, #4 smeared ground | `--clip=seat --city=Kingsmere` in winter, or cut |
| one-call s5 (the ride) | r31-ride/03–07 | #2 label sliced by a roof, #8 fog, #6 square | a Watch take of the King's rider (main session) |
| one-call s6 (a season later) | r31-ride/09 | #6 square stain, #4 ground, #8 fog | `--clip=seat --city=Goldrock` |

The panel crops (chronicle, Hand, court, town card, table) stay: they are the record of the real runs, can't be
replayed, and their backgrounds are mostly covered. "Choosing envoys" (#3) sits under Kingsmere in the r13 frames,
outside every crop used.
