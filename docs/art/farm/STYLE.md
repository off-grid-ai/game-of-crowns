# Farm set: concept art for Meshy image-to-3D

The town's working buildings in the square set's look: an armoury, a farm barn, a granary and a yard's livestock pen.
Made with the Codex CLI (headless `codex exec`), each with a crop of [`docs/art/target/01-town.jpg`](../target/01-town.jpg)
attached, then made through the Meshy API. Results and judging: [docs/research/meshy-farm-set.md](../../research/meshy-farm-set.md).

Files: `<name>_front.png` (the concept), `ref/<name>_ref.jpg` (the 01-town crop: the smithy corner for the armoury,
the thatched houses for the barn and the granary, the pig pen for the pen), `pieces.tsv` (each piece's line),
`style.txt` (the square set's fixed style prompt, word for word), `sheet.jpg` (per row: crop, concept, model front,
model back).

```
codex exec --skip-git-repo-check -i ref/<name>_ref.jpg -- "<style.txt>

The asset: <line from pieces.tsv>"
```

All four came out of one parallel batch, first try (2026-11-12).
