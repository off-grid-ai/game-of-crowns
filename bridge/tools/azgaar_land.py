"""Turns Azgaar's eroded height field into the land the game draws: a raw
float32 heightmap in game units (row 0 = north), 4 samples per game unit, the
same size as the Freeciv map (TILE units per tile). Land heights come from the
eroded bake (ridges, gullies, carved river valleys); the bake flattens all water
to the surface, so the sea shelves down with distance from the shore.

  python3 tools/azgaar_land.py data/belia-eroded-1297x2048.u16 1297 2048 data/belia-land-raw.f32
"""

import array
import sys

TILES_X, TILES_Y, TILE = 56, 88, 4  # must match azgaar_world.py and terrain.gd
PER_UNIT = 4  # samples per game unit (Terrain3D vertex spacing 0.25)
PEAK = 11.0  # game units at Azgaar height 100
SEA = 20.0


def bilinear(data, cols, rows, u, v):
    x = min(max(u * cols - 0.5, 0.0), cols - 1.001)
    y = min(max(v * rows - 0.5, 0.0), rows - 1.001)
    x0, y0 = int(x), int(y)
    fx, fy = x - x0, y - y0
    i = y0 * cols + x0
    top = data[i] * (1 - fx) + data[i + 1] * fx
    bottom = data[i + cols] * (1 - fx) + data[i + cols + 1] * fx
    return top * (1 - fy) + bottom * fy


SHELF = 14.0  # game units from the shore to the deep sea


def shore_distance(land, wet, w, h):
    """Approximate distance (in samples) from each water sample to the nearest land: two-pass chamfer."""
    far = 1e9
    is_wet = bytearray(w * h)
    for i in wet:
        is_wet[i] = 1
    d = array.array("f", [0.0]) * (w * h)
    for i in wet:
        d[i] = far
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if not is_wet[i]:
                continue
            best = d[i]
            if x > 0 and d[i - 1] + 1 < best: best = d[i - 1] + 1
            if y > 0:
                if d[i - w] + 1 < best: best = d[i - w] + 1
                if x > 0 and d[i - w - 1] + 1.41 < best: best = d[i - w - 1] + 1.41
                if x < w - 1 and d[i - w + 1] + 1.41 < best: best = d[i - w + 1] + 1.41
            d[i] = best
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            i = y * w + x
            if not is_wet[i]:
                continue
            best = d[i]
            if x < w - 1 and d[i + 1] + 1 < best: best = d[i + 1] + 1
            if y < h - 1:
                if d[i + w] + 1 < best: best = d[i + w] + 1
                if x < w - 1 and d[i + w + 1] + 1.41 < best: best = d[i + w + 1] + 1.41
                if x > 0 and d[i + w - 1] + 1.41 < best: best = d[i + w - 1] + 1.41
            d[i] = best
    return d


COAST_BLUR = 6  # samples
COAST_BAND = 3.0  # game units either side of the shore
PEAK_BLUR = 5  # samples
PEAK_FROM = 1.0  # game units: above this the high ground is softened, fully by 2 units higher


def box_blur(src, w, h, r):
    """Separable box blur with running sums."""
    tmp = array.array("f", [0.0]) * (w * h)
    out = array.array("f", [0.0]) * (w * h)
    n = 2 * r + 1
    for y in range(h):
        row = y * w
        acc = sum(src[row + min(max(x, 0), w - 1)] for x in range(-r, r + 1))
        for x in range(w):
            tmp[row + x] = acc / n
            acc += src[row + min(x + r + 1, w - 1)] - src[row + max(x - r, 0)]
    for x in range(w):
        acc = sum(tmp[min(max(y, 0), h - 1) * w + x] for y in range(-r, r + 1))
        for y in range(h):
            out[y * w + x] = acc / n
            acc += tmp[min(y + r + 1, h - 1) * w + x] - tmp[max(y - r, 0) * w + x]
    return out


def main():
    src, cols, rows, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    eroded = array.array("H")
    eroded.frombytes(open(src, "rb").read())
    eroded = [v / 655.35 for v in eroded]
    w, h = TILES_X * TILE * PER_UNIT, TILES_Y * TILE * PER_UNIT
    land = array.array("f", [0.0]) * (w * h)
    wet = []
    for y in range(h):
        v = (y + 0.5) / h
        for x in range(w):
            e = bilinear(eroded, cols, rows, (x + 0.5) / w, v)
            if e > SEA + 0.05:  # the bake lays every water surface at exactly SEA
                land[y * w + x] = (e - SEA) / (100.0 - SEA) * PEAK
            else:
                wet.append(y * w + x)
    # Azgaar barely records sea depth (nearly all water is 18 or 19), so the
    # sea shelves down with distance from the shore instead.
    dist = shore_distance(land, wet, w, h)
    for i in wet:
        reach = min(1.0, dist[i] / (SHELF * PER_UNIT))
        land[i] = -0.05 - reach ** 0.7 * 5.5
    # The bake marks water in blocky cells, so the raw coast is a stepped wall.
    # Blur a band either side of the shore until beaches slope into the sea.
    dry = [i for i in range(w * h) if land[i] > 0.0]
    inland = shore_distance(land, dry, w, h)  # for land: distance to the nearest water
    soft = box_blur(box_blur(land, w, h, COAST_BLUR), w, h, COAST_BLUR)
    band = COAST_BAND * PER_UNIT
    for i in range(w * h):
        d = dist[i] if land[i] <= 0.0 else inland[i]
        if d < band:
            k = 1.0 - d / band
            land[i] = land[i] * (1.0 - k) + soft[i] * k
    # The bake's mountains are needles a sample or two wide (0.6 to 9.6 units
    # within 2 units), which draw as rock pillars. Soften the high ground into
    # ridges and peaks; the lowland, its towns and coasts keep their detail.
    ridge = box_blur(box_blur(land, w, h, PEAK_BLUR), w, h, PEAK_BLUR)
    for i in range(w * h):
        k = min(1.0, max(0.0, (ridge[i] - PEAK_FROM) / 2.0))
        if k > 0.0:
            land[i] = land[i] * (1.0 - k) + ridge[i] * k
    open(out, "wb").write(land.tobytes())
    print(f"wrote {out}: {w}x{h} float32, {min(land):.2f}..{max(land):.2f} units")


if __name__ == "__main__":
    main()
