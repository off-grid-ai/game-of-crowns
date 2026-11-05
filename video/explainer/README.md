# Explainer videos

Short films for Reddit, made with [HyperFrames](https://hyperframes.heygen.com) (HTML rendered to video), built the
way the Off Grid AI Product Hunt film was. Every panel is a real play frame from `docs/play/`, every world shot a
clean still or take from the game; no UI is drawn. Copy follows `docs/buzz/`.

| Cut | Folder | Length | Story |
|---|---|---|---|
| Every lord remembers | `post-one/` | 40 s | One lady left unheard; her house turns and marches on the throne (r13–r14) |
| Every lord remembers, 9:16 | `post-one-916/` | 27 s | The same chain, cut for Shorts and TikTok: picture on top, captions in a band below |
| One call | `one-call/` | 44 s | A temple paid for; a season later, pikemen and a war (r31) |

`STORYLINES.md` has the pitches; each cut's `SPEC.md` its shots by the second.

## Build

```bash
cd video/explainer/post-one        # or one-call
./scripts/assets.sh                # copies the media in from docs/play, realm/assets and media/brand-kit
python3 scripts/build.py           # writes index.html and compositions/ from the shot list
npx hyperframes@0.8.188 check
npx hyperframes@0.8.188 render -o renders/v1.mp4
ffmpeg -i renders/v1.mp4 -c:v libx264 -crf 21 -af "loudnorm=I=-15:TP=-2,alimiter=limit=0.7:level=false" -ar 48000 -c:a aac -b:a 192k -movflags +faststart renders/v1-share.mp4
```

Renders, takes and assets/ are gitignored; the share copies go to `docs/buzz/video/` (also gitignored). The world stills come from `realm/assets/intro/stills/` (made by
`realm/tools/media.sh intro`, also gitignored). Clean moving takes of the realm: `tools/takes.sh <out dir> [name ...]`
(cinematics.gd through `realm/tools/render.sh`, so they wait behind any open game).

## Sound and fonts
Music and effects are the game's own CC0 files (`realm/assets/audio/CREDITS.md`): "Viking March" (nightm4re) and
"Lament of the War" (Cethiel). Fonts are EB Garamond and Cinzel (OFL, beside them in `assets/fonts/`).
