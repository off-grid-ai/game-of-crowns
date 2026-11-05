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
