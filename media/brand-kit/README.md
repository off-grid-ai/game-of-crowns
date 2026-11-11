# Game of Crowns — media kit

Created: 4 November 2026.

Use this kit for the game **Game of Crowns**, with **GoC** as its short name. Say GoC as “gee-oh-see”. The design follows the selected option C: tall classical serif letters, pale aged bronze, a small crown, and fine horizontal rules.

## Start here

- [Main GoC app icon](icons/goc-1024.png).
- [macOS icon](icons/goc.icns) and [Windows icon](icons/goc.ico).
- [Selected full title logo](logos/full-title-original.png), with alpha transparency.
- [GoC mark](logos/goc-monogram-original.png), with alpha transparency.
- [Asset preview](previews/asset-overview.jpg).
- [CSV asset list](manifest.csv) and [JSON asset list](manifest.json): each export, its size, source, and use.
- [Brand guide](press/brand-guide.md), [game facts](press/factsheet.md), and [draft marketing copy](press/copy.md).
- [Artwork credits and prompt record](CREDITS.md).
- [Visual review](press/visual-review.md).

## Folders

| Folder | Contents |
|---|---|
| `masters/` | Original generated images, at the size returned by the tool. |
| `logos/` | Transparent full title and GoC marks. |
| `icons/` | PNG sizes, ICO, ICNS, and a macOS iconset. |
| `social/` | X header, YouTube banner, profile images, social posts, story image, link preview, thumbnail, and Discord banner. |
| `store/` | Steam capsule, library, and community artwork. |
| `backgrounds/` | Landscape artwork without a title. |
| `press/` | Game facts, draft copy, brand guide, and source links. |
| `tools/` | The script that creates the exports from the masters. |

## Use

Use the full title where a viewer first meets the game. Use GoC for icons, avatars, and short references.

The landscape and castle images are promotional illustrations. They are not gameplay screenshots. The kit keeps this distinction in its asset list.

Read `press/brand-guide.md` before you change a design. Read `press/factsheet.md` before you publish a game description. The release date, price, public store URL, press contact, and final platform list have not been supplied.

The Steam files are prepared artwork. Their presence does not state that the game is available on Steam. The repository currently identifies the project as a personal macOS project on Apple Silicon.

## Sizes and source quality

The exports have the dimensions in their file names. Some exports are larger than their generated masters. The asset list records the master size and whether an export was enlarged. Keep the original masters for future work.

Platform sizes were checked on 4 November 2026. Source links and placement notes are in `press/platform-specs.md`.

## Build the exports again

Run from the repository root:

```sh
python3 media/brand-kit/tools/build-kit.py
```

The script needs Python 3, ImageMagick (`magick`), and macOS `iconutil` for the ICNS file. It rebuilds exports inside this kit. It does not change the game's code or active icon setting.

The distribution ZIP is saved next to this folder as `media/game-of-crowns-media-kit.zip`.

