"""Rivers for the 3D realm, from an Azgaar Fantasy Map Generator map (belia-world.json),
laid into the land the game draws (belia-land.f32, from azgaar_land.py):

- each big river's course, smoothed and followed every STEP units, with the
  water's level at every point (running downhill all the way) and its width;
- the land with every river's valley shaped into it once: a channel under the
  water, banks just clear of it, and slopes that ease back into the land over a
  distance that grows with the cut, so steep stretches read as valleys, not shards,
  and the far, coarser terrain still shows them;
- a mask of where river water lies (255), so nothing is built or planted in
  it, fading out beside it so towns ease their grading off near a river.

The game lays a Waterways river along each course (realm/scripts/rivers.gd).

  python3 tools/azgaar_rivers.py data/belia-world.json data/belia-land-raw.f32 \
      ../realm/assets/maps/rivers.json data/belia-land.f32 ../realm/assets/maps/rivers-mask.png
"""

import array
import json
import math
import struct
import sys
import zlib

W, H = 56, 88  # Freeciv tiles, as azgaar_world.py
RIVER_DISCHARGE = 900  # the same big rivers Freeciv gets (azgaar_world.py)
TILE = 4.0  # game units per Freeciv tile (realm/scripts/terrain.gd)
PER_UNIT = 4  # land samples per game unit (azgaar_land.py)
SEA_LEVEL = -0.15  # the water's surface (terrain.gd)
WET = SEA_LEVEL + 0.04  # below this the land is sea or lake (terrain.gd is_land)
STEP = 0.5  # game units between course points
BANK = 0.03  # how far the bank stands clear of the water
CUT_SIDE = 1.2  # the steepest valley side a bank may rise into, rise over run
FILL_SIDE = 0.5  # how a bank built up over low ground slopes away
REACH = 5.0  # game units beyond the bank the valley side may reach
NEAR = 3.0  # game units over which the mask fades from the water's edge (towns grade less near a river)


def load(path):
    d = json.load(open(path))
    return [(c[0], c[1]) for c in d["cells"]], d["rivers"], d["width"], d["height"]


def smooth(pts, rounds=2):
    """Chaikin's corner cutting: Azgaar's cell-to-cell zigzag becomes a bend."""
    for _ in range(rounds):
        out = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        out.append(pts[-1])
        pts = out
    return pts


def resample(pts):
    out = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, math.ceil(math.dist(a, b) / STEP))
        for k in range(n):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    out.append(pts[-1])
    return out


class Land:
    def __init__(self, path):
        self.w, self.h = W * int(TILE) * PER_UNIT, H * int(TILE) * PER_UNIT
        self.v = array.array("f")
        self.v.frombytes(open(path, "rb").read())
        assert len(self.v) == self.w * self.h, "land file size"

    def at(self, x, z):
        """Bilinear height at a world position (terrain.gd _land_height)."""
        fx = min(max(x * PER_UNIT - 0.5, 0.0), self.w - 1.001)
        fz = min(max(z * PER_UNIT - 0.5, 0.0), self.h - 1.001)
        x0, z0 = int(fx), int(fz)
        u, t = fx - x0, fz - z0
        i = z0 * self.w + x0
        top = self.v[i] * (1 - u) + self.v[i + 1] * u
        bottom = self.v[i + self.w] * (1 - u) + self.v[i + self.w + 1] * u
        return top * (1 - t) + bottom * t


def downhill(levels):
    """The closest line to the land's that never climbs (pool adjacent violators)."""
    blocks = []
    for y in levels:
        blocks.append([y, 1])
        while len(blocks) > 1 and blocks[-1][0] > blocks[-2][0]:
            b, a = blocks.pop(), blocks.pop()
            n = a[1] + b[1]
            blocks.append([(a[0] * a[1] + b[0] * b[1]) / n, n])
    out = []
    for y, n in blocks:
        out += [y] * n
    return out


def runs(land, course, mouth):
    """A river's stretches of dry land, each ending in the water it feeds (a lake
    splits a river in two). Returns [[(x, z, level, width)]]."""
    out, cur = [], []
    n = len(course)
    for i, (x, z) in enumerate(course):
        h = land.at(x, z)
        if h > WET:
            cur.append([x, z, h, mouth * (0.4 + 0.6 * i / max(1, n - 1))])
            continue
        if cur:
            cur.append([x, z, max(SEA_LEVEL, h), cur[-1][3]])  # into the water
            out.append(cur)
        cur = []
        if h < SEA_LEVEL - 0.3:
            break  # the sea
    if cur:
        out.append(cur)
    out = [r for r in out if len(r) >= 6]
    for r in out:
        # Level the water a little over its neighbours first, so a single
        # gully in the bake doesn't drag a whole stretch down with it.
        raw = [p[2] for p in r]
        soft = [sum(raw[max(0, i - 2):i + 3]) / len(raw[max(0, i - 2):i + 3]) for i in range(len(raw))]
        for p, y in zip(r, downhill(soft)):
            p[2] = y
    return out


def carve(land, rivers):
    """Shapes every river's valley into the land in one pass: each sample takes the
    nearest river's profile, so overlapping stretches never fight."""
    near = {}  # sample index -> (distance, level, half width, depth, reach)
    per = PER_UNIT
    for r in rivers:
        for a, b in zip(r, r[1:]):
            ax, az, al, aw = a
            bx, bz, bl, bw = b
            hw = max(aw, bw) * 0.5
            reach = hw + REACH
            x0 = max(0, int((min(ax, bx) - reach) * per))
            x1 = min(land.w - 1, int((max(ax, bx) + reach) * per) + 1)
            z0 = max(0, int((min(az, bz) - reach) * per))
            z1 = min(land.h - 1, int((max(az, bz) + reach) * per) + 1)
            dx, dz = bx - ax, bz - az
            ll = dx * dx + dz * dz or 1e-9
            for sz in range(z0, z1 + 1):
                wz = (sz + 0.5) / per
                row = sz * land.w
                for sx in range(x0, x1 + 1):
                    wx = (sx + 0.5) / per
                    t = ((wx - ax) * dx + (wz - az) * dz) / ll
                    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
                    px, pz = ax + dx * t - wx, az + dz * t - wz
                    d = math.sqrt(px * px + pz * pz)
                    if d >= reach:
                        continue
                    i = row + sx
                    best = near.get(i)
                    if best is not None and best[0] <= d:
                        continue
                    whw = aw * 0.5 + (bw - aw) * 0.5 * t
                    near[i] = (d, al + (bl - al) * t, whw, 0.06 + whw * 0.16)
    mask = bytearray(land.w * land.h)
    for i, (d, level, hw, depth) in near.items():
        old = land.v[i]
        if old <= WET:
            continue  # the sea and lakes keep their own beds
        if d < hw:
            k = d / hw
            v = level + BANK - (depth + BANK) * (1.0 - k * k)
            if d < hw * 0.85:
                mask[i] = 255
        else:
            # The valley side: the land kept as it is, unless it rises sheerer
            # than a gorge wall right at the bank (cut back) or falls away below
            # the bank (built up, sloping off gently). A gorge stays a gorge.
            e = d - hw
            v = min(max(old, level + BANK - e * FILL_SIDE), level + BANK + e * CUT_SIDE)
        land.v[i] = v
        if mask[i] == 0:
            # Beside the water: 1..254 fading out over NEAR, so the game knows how close a river is.
            mask[i] = max(0, min(254, int(254 * (1.0 - max(0.0, d - hw * 0.85) / NEAR))))
    return mask


def png(path, w, h, gray):
    raw = b"".join(b"\0" + bytes(gray[y * w:(y + 1) * w]) for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main(world, land_in, out, land_out, mask_out):
    cells, rivers, width, height = load(world)
    sx, sz = W * TILE / width, H * TILE / height
    land = Land(land_in)
    laid = []
    for r in rivers:
        if r.get("discharge", 0) < RIVER_DISCHARGE:
            continue
        pts = [(cells[i][0] * sx, cells[i][1] * sz) for i in r.get("cells", []) if 0 <= i < len(cells)]
        if len(pts) < 3:
            continue
        # Wide enough to read from the strategy camera: a big river is ~15 m
        # across at its mouth, the greatest ~28 m (a game unit is ~8 m).
        mouth = min(3.5, 0.4 + math.sqrt(r["discharge"]) / 45)
        laid += runs(land, resample(smooth(pts)), mouth)
    mask = carve(land, laid)
    open(land_out, "wb").write(land.v.tobytes())
    png(mask_out, land.w, land.h, mask)
    json.dump({"rivers": [{"points": [[round(x, 3), round(y, 3), round(z, 3), round(w, 3)] for x, z, y, w in r]} for r in laid]},
              open(out, "w"), separators=(",", ":"))
    print(f"{len(laid)} river stretches -> {out}, {land_out}, {mask_out}")


if __name__ == "__main__":
    main(*sys.argv[1:6])
