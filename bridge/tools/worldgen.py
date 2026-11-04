"""Generates lua/world_setup.lua: the hand-shaped continent of Aldmere (WORLD.md)
and the founding of each great house at its seat. Freeciv runs realm_setup()
on the first turn, so Freeciv's own simulation takes over from there.

    python3 tools/worldgen.py                          # Aldmere, writes lua/world_setup.lua
    python3 tools/worldgen.py --random --seed 7 --out X  # a random world in the same spirit
    python3 tools/worldgen.py --preview                # also prints an ASCII map
"""
import math
import random
import sys
from pathlib import Path

W, H = 56, 84


def _arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


RANDOM = "--random" in sys.argv
SEED = int(_arg("--seed", 1066))
random.seed(SEED)
# Shape of the world. Aldmere's values by default; random worlds perturb them.
SHAPE = {"noise": 3, "wiggle": 0.05, "phase": 0.0, "north": 0.17, "mid": 0.33, "bay": (0.83, 0.51), "gulf": (0.35, 0.77),
         "isles": [(0.17, 0.46, 0.045), (0.12, 0.51, 0.03), (0.22, 0.53, 0.028), (0.15, 0.40, 0.025)], "wall": 0.775}
if RANDOM:
    SHAPE = {
        "noise": SEED % 997, "wiggle": random.uniform(0.02, 0.09), "phase": random.uniform(0, 6.28),
        "north": random.uniform(0.12, 0.22), "mid": random.uniform(0.28, 0.36),
        "bay": (random.uniform(0.78, 0.86), random.uniform(0.4, 0.6)), "gulf": (random.uniform(0.28, 0.42), random.uniform(0.7, 0.8)),
        "isles": [(random.uniform(0.1, 0.24), random.uniform(0.3, 0.6), random.uniform(0.02, 0.05)) for _ in range(random.randint(2, 5))],
        "wall": random.uniform(0.74, 0.8),
    }

TERRAIN = {"g": "Grassland", "p": "Plains", "d": "Desert", "t": "Tundra", "a": "Glacier", "f": "Forest",
           "s": "Swamp", "h": "Hills", "m": "Mountains", "o": "Ocean", "O": "Deep Ocean", "l": "Lake"}

# Seats from the world bible, in map fractions (u east, v south).
SEATS = {
    "Scottish": ("Stonefell", 0.50, 0.22, ["Wintermoor", "Frostwatch"]),
    "English": ("Goldrock", 0.36, 0.44, ["Lannport", "Silverhill"]),
    "Norwegian": ("Saltkeep", 0.17, 0.47, ["Pyke Hollow"]),
    "French": ("Rosehall", 0.46, 0.63, ["Oldtown Reach", "Bitterbridge"]),
    "Welsh": ("Stormwatch", 0.80, 0.65, ["Rainhold"]),
    "Castilian": ("Sunspire", 0.60, 0.91, ["Redsands", "Saltshore"]),
    "Irish": ("Highfell", 0.72, 0.36, ["Gulltown"]),
}
KINGSMERE = (0.73, 0.52)


def _hash(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 982451653) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def noise(x, y, seed=0):
    xi, yi = math.floor(x), math.floor(y)
    xf, yf = x - xi, y - yi
    u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    a, b = _hash(xi, yi, seed), _hash(xi + 1, yi, seed)
    c, d = _hash(xi, yi + 1, seed), _hash(xi + 1, yi + 1, seed)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


def fbm(x, y, seed=0):
    return sum(noise(x * 2 ** i, y * 2 ** i, seed + i) / 2 ** i for i in range(4)) / 1.875


def is_land(u, v):
    n = (fbm(u * 9, v * 9, SHAPE["noise"]) - 0.5) * 0.09
    # Iron Isles off the western coast.
    for cx, cy, r in SHAPE["isles"]:
        if math.hypot(u - cx, (v - cy) * 0.66) < r + n * 0.4:
            return True
    if v < 0.03 or v > 0.97:
        return False
    # Kingsmere's bay and the gulf between the Reach and the south.
    if math.hypot(u - SHAPE["bay"][0], (v - SHAPE["bay"][1]) * 0.8) < 0.07 + n:
        return False
    if math.hypot(u - SHAPE["gulf"][0], (v - SHAPE["gulf"][1]) * 1.4) < 0.08 + n:
        return False
    centre = 0.55 + SHAPE["wiggle"] * math.sin(v * 7.0 + SHAPE["phase"])
    if v < 0.45:
        half = SHAPE["north"] + (SHAPE["mid"] - SHAPE["north"]) * (v / 0.45)
    elif v < 0.75:
        half = SHAPE["mid"] - 0.04 * math.sin((v - 0.45) * 10)
    else:
        half = 0.30 * (1 - ((v - 0.75) / 0.24) ** 2.2)
    return abs(u - centre) < half + n


def region_terrain(u, v, r):
    vale = math.hypot(u - 0.72, (v - 0.36) * 0.75)
    if vale < 0.075:
        if vale > 0.045:
            return "m" if r < 0.8 else "h"
        return "g" if r < 0.6 else ("p" if r < 0.85 else "l")
    if v < 0.09:
        return "a" if r < 0.55 else "t"
    if v < 0.105:
        return "h"  # the old wall
    if v < 0.33:
        return "f" if r < 0.42 else "t" if r < 0.62 else "h" if r < 0.78 else "g" if r < 0.95 else "m"
    if SHAPE["wall"] < v < SHAPE["wall"] + 0.035 and r < 0.85:
        return "m"  # the mountain wall before the south, with passes
    if v >= 0.81:
        return "d" if r < 0.55 else "p" if r < 0.8 else "h" if r < 0.92 else "g"
    if u < 0.45 and v < 0.53:
        return "h" if r < 0.42 else "m" if r < 0.55 else "g" if r < 0.8 else "f"
    if u > 0.62 and 0.57 < v < 0.73:
        return "f" if r < 0.38 else "h" if r < 0.65 else "g"
    if 0.72 < v <= 0.775:
        return "p" if r < 0.5 else "g" if r < 0.8 else "h"
    if v >= 0.52:
        return "g" if r < 0.5 else "p" if r < 0.8 else "f" if r < 0.95 else "s"
    return "g" if r < 0.45 else "p" if r < 0.75 else "f" if r < 0.9 else "s"


def build():
    grid = [["O"] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            u, v = (x + 0.5) / W, (y + 0.5) / H
            if is_land(u, v):
                grid[y][x] = region_terrain(u, v, fbm(u * 14, v * 14, 11) * 0.55 + random.random() * 0.45)
    for y in range(H):
        for x in range(W):
            if grid[y][x] == "O" and any(
                grid[yy][xx] not in "oO"
                for yy in range(max(0, y - 2), min(H, y + 3))
                for xx in range(max(0, x - 2), min(W, x + 3))
            ):
                grid[y][x] = "o"
    return grid


def river(grid, points):
    tiles = []
    for (u0, v0), (u1, v1) in zip(points, points[1:]):
        steps = int(max(abs(u1 - u0) * W, abs(v1 - v0) * H) * 2) + 1
        for i in range(steps + 1):
            u = u0 + (u1 - u0) * i / steps + (noise(i * 0.4, u0 * 9, 5) - 0.5) * 0.02
            v = v0 + (v1 - v0) * i / steps
            x, y = int(u * W), int(v * H)
            if 0 <= x < W and 0 <= y < H and grid[y][x] not in "oOml" and (x, y) not in tiles:
                tiles.append((x, y))
    return tiles


def tile_of(u, v, grid):
    x, y = int(u * W), int(v * H)
    if grid[y][x] in "oOml":
        # Nudge seats off water and peaks onto the nearest good land.
        best = None
        for r in range(1, 6):
            for yy in range(y - r, y + r + 1):
                for xx in range(x - r, x + r + 1):
                    if 0 <= xx < W and 0 <= yy < H and grid[yy][xx] in "gphfdt":
                        d = (xx - x) ** 2 + (yy - y) ** 2
                        if best is None or d < best[0]:
                            best = (d, xx, yy)
            if best:
                return best[1], best[2]
    return x, y


def main():
    grid = build()
    rivers = river(grid, [(0.72, 0.40), (0.70, 0.45), (0.73, 0.50)])
    rivers += river(grid, [(0.38, 0.50), (0.45, 0.58), (0.52, 0.66), (0.58, 0.74)])
    rivers += river(grid, [(0.50, 0.25), (0.55, 0.32), (0.60, 0.40), (0.66, 0.46)])
    houses = []
    for nation, (seat, u, v, towns) in SEATS.items():
        if RANDOM:
            u, v = u + random.uniform(-0.06, 0.06), v + random.uniform(-0.04, 0.04)
        sx, sy = tile_of(u, v, grid)
        grid[sy][sx] = "g" if grid[sy][sx] not in "gp" else grid[sy][sx]
        houses.append((nation, seat, sx, sy, towns))
    kx, ky = tile_of(KINGSMERE[0] + (random.uniform(-0.05, 0.03) if RANDOM else 0), KINGSMERE[1] + (random.uniform(-0.04, 0.04) if RANDOM else 0), grid)

    rows = ",\n".join('  "%s"' % "".join(r) for r in grid)
    lua_houses = ",\n".join(
        '  {nation = "%s", seat = "%s", x = %d, y = %d, towns = {%s}}'
        % (n, s, x, y, ", ".join('"%s"' % t for t in towns))
        for n, s, x, y, towns in houses
    )
    lua = f'''-- Generated by tools/worldgen.py from WORLD.md. Do not edit by hand.
-- realm_setup() reshapes Freeciv's map into Aldmere and founds the great houses.

local W, H = {W}, {H}
local ROWS = {{
{rows}
}}
local TERRAIN = {{{", ".join(f'{k} = "{v}"' for k, v in TERRAIN.items())}}}
local RIVERS = {{{", ".join("{%d,%d}" % t for t in rivers)}}}
local HOUSES = {{
{lua_houses}
}}
KINGSMERE = {{x = {kx}, y = {ky}}}

local function place_town(p, x, y, name)
  local t = find.tile(x, y)
  if t and not t:city() then edit.create_city(p, t, name) end
end

function realm_setup()
  for p in players_iterate() do
    for u in p:units_iterate() do edit.unit_kill(u, "killed", nil) end
    for c in p:cities_iterate() do edit.remove_city(c) end
  end
  for y = 0, H - 1 do
    local row = ROWS[y + 1]
    for x = 0, W - 1 do
      local t = find.tile(x, y)
      local want = TERRAIN[row:sub(x + 1, x + 1)]
      if t and want and t.terrain:rule_name() ~= want then edit.change_terrain(t, find.terrain(want)) end
    end
  end
  for _, r in ipairs(RIVERS) do
    local t = find.tile(r[1], r[2])
    if t then pcall(edit.create_owned_extra, t, "River", nil) end
  end
  for p in players_iterate() do
    for _, h in ipairs(HOUSES) do
      if p.nation:rule_name() == h.nation then
        place_town(p, h.x, h.y, h.seat)
        log.normal("REALM_SETUP %s seat %s at (%d,%d) terrain %s city %s", p.name, h.seat, h.x, h.y, find.tile(h.x, h.y).terrain:rule_name(), tostring(find.tile(h.x, h.y):city()))
        local seat = find.tile(h.x, h.y)
        -- Daughter towns a few days' ride from the seat, on good land.
        local placed = 0
        for t in seat:square_iterate(4) do
          if placed >= #h.towns then break end
          local n = t.terrain:rule_name()
          local dx, dy = math.abs(t.x - h.x), math.abs(t.y - h.y)
          if (dx >= 3 or dy >= 3) and (n == "Grassland" or n == "Plains" or n == "Hills") and not t:city() then
            placed = placed + 1
            place_town(p, t.x, t.y, h.towns[placed])
          end
        end
        local units = {{{{"Settlers", 2}}, {{"Workers", 2}}, {{"Warriors", 2}}, {{"Archers", 1}}, {{"Horsemen", 1}}}}
        for _, pair in ipairs(units) do
          local ut = find.unit_type(pair[1])
          for i = 1, pair[2] do
            local ok, err = pcall(edit.create_unit, p, seat, ut, 0, seat:city(), -1)
            if not ok then log.normal("REALM_SETUP unit %s failed at %s (%d,%d): %s", pair[1], h.seat, h.x, h.y, tostring(err)) end
          end
        end
      end
    end
  end
  -- The Crown: Kingsmere and the royal host.
  for p in players_iterate() do
    if p.nation:rule_name() == "Norman" then
      place_town(p, KINGSMERE.x, KINGSMERE.y, "Kingsmere")
      edit.change_gold(p, 500)  -- the royal treasury at the start of a reign
      local k = find.tile(KINGSMERE.x, KINGSMERE.y)
      for _, pair in ipairs({{{{"Knights", 4}}, {{"Pikemen", 4}}, {{"Archers", 2}}, {{"Workers", 2}}}}) do
        local ut = find.unit_type(pair[1])
        for i = 1, pair[2] do pcall(edit.create_unit, p, k, ut, 1, k:city(), -1) end
      end
      log.normal("REALM_SETUP crown at Kingsmere (%d,%d) city %s", KINGSMERE.x, KINGSMERE.y, tostring(k:city()))
    end
  end
  log.normal("REALM_SETUP done")
end
'''
    out = Path(_arg("--out")) if _arg("--out") else Path(__file__).resolve().parent.parent / "lua" / "world_setup.lua"
    out.write_text(lua)
    if "--preview" in sys.argv:
        marks = {(x, y): s[0] for _, s, x, y, _ in houses}
        marks[(kx, ky)] = "K"
        for (x, y) in rivers:
            marks.setdefault((x, y), "~")
        for y in range(H):
            print("".join(marks.get((x, y), {"O": " ", "o": "."}.get(grid[y][x], grid[y][x])) for x in range(W)))
    print(f"wrote {out}: {W}x{H}, {len(rivers)} river tiles")


main()
