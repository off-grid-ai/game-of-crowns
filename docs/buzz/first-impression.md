# First-impression fixes (2026-11-05)

What a stranger sees in the first minute and in every post. Found in the 4K intro stills (docs/buzz/images/zoom/), the play frames and the explainer cut one-call-v1 (Mac's screenshots). Ordered by how loudly each one says "unfinished".

| # | Problem | Where seen | Done when |
|---|---|---|---|
| 1 | **People half sunk in the ground** | one-call-v1 (Kingsmere, the rider's road), Lionmoor stills | Every person and horse stands on the ground at any zoom, on slopes too. It's already on v1's bar ("no one sunk"). |
| 2 | **World labels cut by buildings**: "The crown's purse for a new building" sliced by a roof | one-call-v1 | Scene captions draw on top of the world, never behind geometry. |
| 3 | **Engine progress text on the map**: "Choosing envoys · 50%" under Kingsmere | one-call-v1 | No progress text on map labels (the ledger said this was fixed; it's back or never reached the build). |
| 4 | **The ground**: one blurry smeared texture; noisy orange crop patches; huge orange weed sprites | every shot, worst up close | Ground reads as grass, dirt and fields at the oblique camera's distance; crops read as rows. |
| 5 | **Stone patches under houses**: flat grey aprons pasted on grass | stills, one-call-v1 | Houses sit in the ground: no visible apron, or one that blends into dirt. |
| 6 | **The town square as a round brown stain** | one-call-v1, r34 | A square that reads as trodden earth or cobbles with an edge, not a decal. |
| 7 | **Untextured cream boxes** next to detailed houses | stills, one-call-v1 | Every building has its textures; none render as plain boxes. |
| 8 | **White fog blobs** floating over towns | one-call-v1, r34 | Smoke and haze read as chimney smoke or soft haze, not white discs. |
| 9 | **Castle on a raised dirt slab** with a hard cliff edge | Lionmoor still | Castles sit on the land. |
| 10 | **Flat noon light** | everything | The colour grade the release calls already chose: golden hour, haze, muted colour. |
| 11 | **Watched scenes miss their subject**: the King's gold hidden in a forest | r34/05 | The camera holds what the scene is about. |
| 12 | **Broken intro stills**: seat_Deepvale.png and seat_Eaglefell.png are fully black | realm/assets/intro/stills | Re-rendered or dropped from the intro. |

Posting waits on 1–3 at least (they read as bugs), and ideally on 4–8 (they read as unfinished).
