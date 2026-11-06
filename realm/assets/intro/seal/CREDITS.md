# Off Grid AI studio seal: revision 2

Date: 2026-11-06.

The revised pair uses warm painted bronze and a worn gold mark, following the desktop shield material reference and the later request to fit the game art. Both files are 2048 × 2048 RGBA PNGs. The wide name band is blank. The plain centre has texture only.

## Files

| File | Dimensions | File size |
| --- | --- | --- |
| [seal_plain.png](/Users/user/Downloads/Aldmere/intro/seal/seal_plain.png) | 2048 × 2048 | 4,619,531 bytes (4.41 MiB) |
| [seal_marked.png](/Users/user/Downloads/Aldmere/intro/seal/seal_marked.png) | 2048 × 2048 | 4,720,052 bytes (4.50 MiB) |

## Creation

Both new painted masters were created with OpenAI `image_gen.imagegen` (built-in tool), on 2026-11-06. The tool did not report its model name or ID. Native source size: 1254 × 1254. ImageMagick 7.1.2-27 made the final 2048 × 2048 exports and enforced the shared geometry.

The game style reference was `realm/assets/ui/title-background.png`. The material reference was a render of the existing Off Grid AI desktop Ares shield. The new seal uses a simple rim and a blank annular band. It has no shield, laurel, Greek border, crown, gems, letters or numbers.

The new plain master supplies the bronze in both files. The newly painted marked master supplies the worn gold finish. The original `realm/assets/ui/offgrid-mark.png` alpha outline supplies the final mark geometry, with three pins on each side, its original cut and inner opening. Its stencil is scaled to 750 × 547 pixels, about 55% of the centre field width. Fine edge highlights and a small contact shadow give shallow relief. Transparent openings reveal the plain master below. The generated mark contour was not used for the final outline.

The previous rejected pair is preserved under `source/rejected-v1/`. The source drawings and desktop models are unchanged. A separate 3D stamp study is also kept under `source/revision-v2/`; it is not the final painted inlay.

## Checks

Both files were opened together. The circular alpha is symmetric and identical in both files, with all pixels outside the circle fully transparent. All visible bronze pixels outside the inlay area are identical. The inlay alpha is pixel-identical to the source stencil. The left and right pin counts are both three. The seal diameter is 1884 pixels, about 92% of the canvas.

- [Plain master prompt](/Users/user/Downloads/Aldmere/intro/seal/source/revision-v2/PLAIN_PROMPT.txt).
- [Marked master prompt](/Users/user/Downloads/Aldmere/intro/seal/source/revision-v2/MARKED_PROMPT.txt).
- [Check data](/Users/user/Downloads/Aldmere/intro/seal/SEAL_CHECKS.json).
- [Pair preview](/Users/user/Downloads/Aldmere/intro/seal/SEAL_PREVIEW.png).
