# Nature set: concept art for Meshy image-to-3D

Trees, bushes and grass in the target's painted look (STANDARDS.md replace list #3; Mac 11-12: "major issues with the
trees, the grass"), replacing Quaternius Stylized Nature trees and tufts. Route: docs/art/STANDARDS.md §6.

- `ref/<x>_ref.jpg`: crops from docs/art/target/01-town.jpg and 03-army.jpg (the piece's design, finish and colour).
- `style.txt`: the square set's prompt adapted to plants (fixed, word for word for every piece).
- `pieces.tsv`: name, reference crop, the asset line.
- `<name>_front.png`: the concept (`codex exec --skip-git-repo-check -i ref/<crop> -- "<style.txt>\n\n<line>\n\nSave the image as a PNG file named <name>_front.png in the current directory."`).
- Models: `~/code/goc-kits/meshy/nature/<name>/` (shape preview, judged in a turntable, then painted from the concept).
- `sheet.jpg`: crop | concept | painted model at 3/4.

Sizes (STANDARDS.md §2): grown trees 8-14 m, bush about 1.2 m, grass clump about 0.5 m; trees placed in clumps.
