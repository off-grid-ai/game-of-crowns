# Artwork credits and source record

Date: 4 November 2026.

## Generation

Tool: **OpenAI `image_gen.imagegen`**, used in built-in imagegen mode. The tool did not report its model name or model ID.

Seven new masters were created for this kit:

- `masters/app-icon.png`
- `masters/goc-monogram.png`
- `masters/key-art-landscape.png`
- `masters/key-art-portrait.png`
- `masters/key-art-square.png`
- `masters/channel-banner.png`
- `masters/compact-title-card.png`

The complete final prompts for these masters are in `press/generation-records.json`.

## Existing approved artwork

- `masters/full-title-selected-c.png` copies the user's selected option C, from `realm/assets/ui/game-of-crowns-option-c-bronze.png`.
- `masters/landscape-original.png` copies the existing title background from `realm/assets/ui/title-background.png`.

Both existing images were also created with the built-in OpenAI imagegen tool in this chat on 4 November 2026. The model ID was not supplied.

The existing landscape is 3840 × 2160. It was previously resized from a generated 1672 × 941 image. It is not a native 4K render.

## Export tools

ImageMagick creates resized and cropped exports, encodes the ICO file, and builds review images. macOS `iconutil` creates the ICNS file. The export script is included.

The original generated images keep their native dimensions. The manifest records the source size for each export and flags enlarged exports.

All title lettering is raster artwork. No editable font, vector master, or layered PSD is claimed. Review-sheet labels use a system font; that font file is not included.

## Content

The castle images are promotional illustrations. They are not gameplay screenshots.

Draft game descriptions use the repository README and working vision. Platform sizing sources are linked in `press/platform-specs.md`.

