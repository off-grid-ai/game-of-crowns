# Trades set: concept art for Meshy image-to-3D

The town's remaining kit trades in the square set's look: an alehouse, a stable with its paddock, a tower windmill
(drawn without sails: the game turns its own on the hub), a tannery and a dyer. Made with the Codex CLI (headless
`codex exec`), each with a crop of [`docs/art/target/01-town.jpg`](../target/01-town.jpg) or a reference attached,
then made through the Meshy API. Results and judging: [docs/research/meshy-trades-set.md](../../research/meshy-trades-set.md).

Files: `<name>_front.png` (the concept), `ref/<name>_ref.jpg` (the crop attached), `pieces.tsv` (each piece's line),
`style.txt` (the square set's fixed style prompt, word for word), `sheet.jpg` (our models in a Blender turntable,
front 3/4 and back 3/4: alehouse, windmill, tannery, dyer, then the stables).

```
codex exec --skip-git-repo-check -i ref/<name>_ref.jpg -- "<style.txt>

The asset: <line from pieces.tsv>" < /dev/null
```

Close stdin (`< /dev/null`): a run left on an open stdin waits on it and never finishes. The stables were drawn
twice: the first had no paddock; the second puts the fenced paddock, trough and hay in front of the stalls (2026-11-12).
