"""Turns an Azgaar Fantasy Map Generator map (belia-world.json) into Freeciv terrain:
one letter per Freeciv tile (same legend as worldgen.py) plus river tiles: every tile a river the game
draws runs through (realm/assets/maps/rivers.json, from azgaar_rivers.py), so the rivers have one source.
Each tile takes the Azgaar cells whose centres fall inside it: water when most
of them are water, mountains and hills by height, otherwise Azgaar's biome.

  python3 tools/azgaar_world.py data/belia-world.json [--preview | --out lua/world_setup_azgaar.lua]
  python3 tools/azgaar_world.py data/belia-world.json --rivers lua/world_setup_azgaar.lua  (the river tiles alone)
"""

import collections
import json
import sys

W, H = 56, 88  # Belia is 760×1200, so tiles stay square

SEA = 20  # Azgaar's sea level on its 0–100 height scale
DRAWN_RIVERS = __file__.replace("tools/azgaar_world.py", "../realm/assets/maps/rivers.json")  # the rivers the game draws
TILE = 4.0  # game units per Freeciv tile (realm/scripts/terrain.gd)

# Azgaar biome -> terrain letter. The map is placed from 55°N to 15°N in Azgaar's
# world settings, so its own climate gives a cold north and a warm south.
BIOME = {1: "d", 2: "t", 3: "p", 4: "g", 5: "p", 6: "g", 7: "f", 8: "f", 9: "f", 10: "t", 11: "a", 12: "s"}  # deciduous woodland reads as open farmland


def load(path):
    """belia-world.json: cells as [x, y, height, biome, is_lake, grid_cell], rivers with discharge."""
    d = json.load(open(path))
    cells = [{"p": (c[0], c[1]), "h": c[2], "biome": c[3], "lake": c[4], "i": i} for i, c in enumerate(d["cells"])]
    return cells, d["rivers"], d["width"], d["height"]


LAND_FILE = "data/belia-land.f32"  # the eroded land the game draws (azgaar_land.py)
LAND_W, LAND_H = 896, 1408


def drawn_water(tx, ty):
    """The share of a tile that is water in the land the game actually draws,
    so Freeciv's coast is where the player sees it."""
    import array, os
    global _land
    if "_land" not in globals():
        _land = None
        if os.path.exists(LAND_FILE):
            _land = array.array("f")
            _land.frombytes(open(LAND_FILE, "rb").read())
    if _land is None:
        return None
    sx, sy = LAND_W / W, LAND_H / H
    wet = total = 0
    for y in range(int(ty * sy), int((ty + 1) * sy), 2):
        for x in range(int(tx * sx), int((tx + 1) * sx), 2):
            total += 1
            if _land[y * LAND_W + x] <= 0.0:
                wet += 1
    return wet / max(total, 1)


def tiles(cells, width, height):
    groups = collections.defaultdict(list)
    for c in cells:
        x, y = c["p"]
        groups[(min(W - 1, int(x / width * W)), min(H - 1, int(y / height * H)))].append(c)
    rows = []
    for ty in range(H):
        row = []
        for tx in range(W):
            group = groups.get((tx, ty), [])
            if not group:
                row.append("O")
                continue
            water = [c for c in group if c["h"] < SEA]
            share = drawn_water(tx, ty)
            if share is None:
                share = len(water) / len(group)
            if share > 0.5:
                if not water:
                    row.append("o")
                    continue
                if sum(c["lake"] for c in water) * 2 > len(water):
                    row.append("l")
                else:
                    row.append("O" if sum(c["h"] for c in water) / len(water) < 12 else "o")
                continue
            land = [c for c in group if c["h"] >= SEA] or [dict(c, h=SEA + 2) for c in group]  # drawn dry, Azgaar wet: low land
            peak = max(c["h"] for c in land)
            mean = sum(c["h"] for c in land) / len(land)
            if peak >= 68 or mean >= 58:
                row.append("m")
            elif mean >= 44:
                row.append("h")
            else:
                biome = collections.Counter(c["biome"] for c in land).most_common(1)[0][0]
                row.append(BIOME.get(biome, "g"))
        rows.append("".join(row))
    return rows


def rivers(rows):
    """Every land tile a drawn river's course runs through: the rivers the player sees are the ones the rules know."""
    out = []
    seen = set()
    for r in json.load(open(DRAWN_RIVERS))["rivers"]:
        for x, _level, z, _width in r["points"]:
            tx, ty = min(W - 1, int(x / TILE)), min(H - 1, int(z / TILE))
            if rows[ty][tx] not in "oOl" and (tx, ty) not in seen:
                seen.add((tx, ty))
                out.append((tx, ty))
    return out


TERRAIN = {"g": "Grassland", "p": "Plains", "d": "Desert", "t": "Tundra", "a": "Glacier", "f": "Forest",
           "s": "Swamp", "h": "Hills", "m": "Mountains", "o": "Ocean", "O": "Deep Ocean", "l": "Lake"}

# Seats by region on this continent, in map fractions (u east, v south).
SEATS = {
    "Scottish": ("Stonefell", 0.59, 0.21, ["Wintermoor", "Frostwatch"]),   # the northern forests
    "Norwegian": ("Saltkeep", 0.14, 0.24, ["Pyke Hollow"]),                # the western isles
    "English": ("Goldrock", 0.18, 0.45, ["Lannport", "Silverhill"]),       # the western hills
    "Irish": ("Highfell", 0.75, 0.45, ["Gulltown"]),                       # the east
    "French": ("Rosehall", 0.21, 0.66, ["Oldtown Reach", "Bitterbridge"]), # the green south-west
    "Welsh": ("Stormwatch", 0.84, 0.77, ["Rainhold"]),                     # the south-east coast
    "Castilian": ("Sunspire", 0.75, 0.97, ["Redsands", "Saltshore"]),      # beyond the southern mountains
}
KINGSMERE = (0.50, 0.53)


TAKEN = []  # seats already placed: no two great houses share an island corner


def tile_of(u, v, rows):
    x, y = int(u * W), int(v * H)
    best = None
    for r in range(0, 8):
        for yy in range(y - r, y + r + 1):
            for xx in range(x - r, x + r + 1):
                # A seat needs a town's worth of dry land around it, not a beach.
                if 0 <= xx < W and 0 <= yy < H and rows[yy][xx] in "gphfd" and not any(abs(xx - a) + abs(yy - b) < 7 for a, b in TAKEN) and all(
                        0 <= xx + dx < W and 0 <= yy + dy < H and rows[yy + dy][xx + dx] not in "oOl"
                        and (drawn_water(xx + dx, yy + dy) or 0.0) < 0.2
                        for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                    d = (xx - x) ** 2 + (yy - y) ** 2
                    if best is None or d < best[0]:
                        best = (d, xx, yy)
        if best:
            return best[1], best[2]
    # No town-sized dry ground near here (small islands): take the driest land tile around.
    best = None
    for yy in range(max(0, y - 10), min(H, y + 11)):
        for xx in range(max(0, x - 10), min(W, x + 11)):
            if rows[yy][xx] in "gphfd" and not any(abs(xx - a) + abs(yy - b) < 7 for a, b in TAKEN):
                wet = sum((drawn_water(xx + dx, yy + dy) or 0.0) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if 0 <= xx + dx < W and 0 <= yy + dy < H)
                score = wet * 4 + ((xx - x) ** 2 + (yy - y) ** 2) * 0.02
                if best is None or score < best[0]:
                    best = (score, xx, yy)
    return (best[1], best[2]) if best else (x, y)


def lua(rows, river):
    """The same world_setup.lua the hand-shaped Aldmere used, with this land."""
    grid = [list(r) for r in rows]
    houses = []
    for nation, (seat, u, v, towns) in SEATS.items():
        x, y = tile_of(u, v, grid)
        TAKEN.append((x, y))
        grid[y][x] = grid[y][x] if grid[y][x] in "gp" else "g"
        houses.append('  {nation = "%s", seat = "%s", x = %d, y = %d, towns = {%s}}' % (nation, seat, x, y, ", ".join('"%s"' % t for t in towns)))
    kx, ky = tile_of(*KINGSMERE, grid)
    body = open(__file__.replace("tools/azgaar_world.py", "lua/realm_setup_body.lua")).read()
    return f"""-- Generated by tools/azgaar_world.py from an Azgaar map. Do not edit by hand.
-- realm_setup() reshapes Freeciv's map into the realm and founds the great houses.

local W, H = {W}, {H}
local ROWS = {{
{",\n".join('  "%s"' % "".join(r) for r in grid)}
}}
local TERRAIN = {{{", ".join(f'{k} = "{v}"' for k, v in TERRAIN.items())}}}
local RIVERS = {{{", ".join("{%d,%d}" % t for t in river)}}}
local HOUSES = {{
{",\n".join(houses)}
}}
KINGSMERE = {{x = {kx}, y = {ky}}}
{body}"""


def main():
    cells, river_list, width, height = load(sys.argv[1])
    rows = tiles(cells, width, height)
    river = rivers(rows)
    if "--preview" in sys.argv:
        for y, row in enumerate(rows):
            print("%2d %s" % (y, row))
        print("rivers:", len(river), "tiles;", collections.Counter("".join(rows)).most_common())
        return
    if "--rivers" in sys.argv:
        # Only the river tiles, refreshed in the setup the realm runs (its towns and coast were tuned there by hand).
        path = sys.argv[sys.argv.index("--rivers") + 1]
        lines = open(path).read().split("\n")
        lines = [f"local RIVERS = {{{', '.join('{%d,%d}' % t for t in river)}}}" if l.startswith("local RIVERS") else l for l in lines]
        open(path, "w").write("\n".join(lines))
        return
    if "--out" in sys.argv:
        open(sys.argv[sys.argv.index("--out") + 1], "w").write(lua(rows, river))
        return
    json.dump({"w": W, "h": H, "rows": rows, "rivers": river}, sys.stdout)


if __name__ == "__main__":
    main()
