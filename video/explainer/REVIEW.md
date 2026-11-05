# Review: draft 1 of both cuts (2026-11-05)

## Checked
- `hyperframes check` passes on both (info notes only: the camera frames sit far outside their parents by design).
- Looked at: snapshots at every shot change and at 1 fps over both renders; frame 0 of each (the thumbnail) carries
  the first line; every crop was read at full size for clipped text, removed v1 features and edge slivers.
- Measured: share copies loudness-matched (one-call −13.8 LUFS / −1.5 dBFS; post-one −14.7 LUFS / −0.7 dBFS peak).
- Not checked: the sound was measured, never heard.

## Truth calls
- Every panel is a real frame from one run per cut; no UI is drawn except a pointer in one shot of one-call.
- one-call never says the temple caused the pikemen; post-one never says why Ysolde went unheard (the ledger
  notes a since-fixed patience bug behind that empty court).

## Weakest / next
- The world shots are stills with a slow push; clean moving takes (`tools/takes.sh`) replace them once rendered.
- one-call is a stand-in until a lord can be filmed bringing up the King's deed in his own words.
- A 9:16 cut, asked for by the buzz session, isn't built yet.
