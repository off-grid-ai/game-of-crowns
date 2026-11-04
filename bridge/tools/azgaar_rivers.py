"""Rivers for the 3D realm, from an Azgaar Fantasy Map Generator map (belia-world.json):
each big river as a line of points in game units, source to mouth, with its width.
The game lays a Waterways river along each (realm/scripts/rivers.gd).

  python3 tools/azgaar_rivers.py data/belia-world.json ../realm/assets/maps/rivers.json
"""

import json
import math
import sys

W, H = 56, 88  # Freeciv tiles, as azgaar_world.py
RIVER_DISCHARGE = 900  # the same big rivers Freeciv gets (azgaar_world.py)
TILE = 4.0  # game units per Freeciv tile (realm/scripts/terrain.gd)


def load(path):
    d = json.load(open(path))
    return [{"p": (c[0], c[1])} for c in d["cells"]], d["rivers"], d["width"], d["height"]


def main(src, out):
    cells, rivers, width, height = load(src)
    sx, sz = W * TILE / width, H * TILE / height
    lines = []
    for r in rivers:
        if r.get("discharge", 0) < RIVER_DISCHARGE:
            continue
        pts = [cells[i]["p"] for i in r.get("cells", []) if 0 <= i < len(cells)]
        if len(pts) < 3:
            continue
        # Wide enough to read from the strategy camera: a big river is ~15 m
        # across at its mouth, the greatest ~28 m (a game unit is ~8 m).
        mouth = min(3.5, 0.4 + math.sqrt(r["discharge"]) / 45)
        lines.append({
            "width": round(mouth, 3),
            "points": [[round(x * sx, 3), round(y * sz, 3)] for x, y in pts],
        })
    json.dump({"rivers": lines}, open(out, "w"), separators=(",", ":"))
    print(f"{len(lines)} rivers -> {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
