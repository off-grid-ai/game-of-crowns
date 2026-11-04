"""Paints the realm's map from its eroded land, at full detail, in the manner
of Azgaar's maps: graded sea, pale shallows, shaded relief, forests, snow on the
high peaks. Written once per land; the game's minimap draws territory over it.

  python3 tools/azgaar_mapimage.py data/belia-land.f32 896 1408 lua/world_setup_azgaar.lua data/belia-map.ppm
"""

import array
import math
import re
import sys

SEA = (38, 66, 94)
DEEP = (22, 40, 62)
SHALLOW = (92, 128, 150)
SAND = (196, 184, 146)
GRASS = (110, 132, 74)
FOREST = (62, 92, 52)
HILL = (132, 124, 94)
ROCK = (150, 144, 134)
SNOW = (236, 238, 242)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def main():
    src, w, h, setup, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
    land = array.array("f")
    land.frombytes(open(src, "rb").read())
    rows = re.findall(r'^\s+"([A-Za-z]+)"', open(setup).read(), re.M)
    tw, th = len(rows[0]), len(rows)

    def at(x, y):
        return land[min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))]

    def is_wood(tx, ty):
        return 1.0 if rows[min(th - 1, max(0, ty))][min(tw - 1, max(0, tx))] == "f" else 0.0

    def woods(x, y):
        # The forest tiles blended smoothly, edges broken up a little, so woods
        # read as woods and not as squares.
        fx = (x + 0.5) * tw / w - 0.5 + math.sin(y * 0.11) * 0.35
        fy = (y + 0.5) * th / h - 0.5 + math.cos(x * 0.13) * 0.35
        x0, y0 = int(math.floor(fx)), int(math.floor(fy))
        u, v = fx - x0, fy - y0
        a = is_wood(x0, y0) * (1 - u) + is_wood(x0 + 1, y0) * u
        b = is_wood(x0, y0 + 1) * (1 - u) + is_wood(x0 + 1, y0 + 1) * u
        t = a * (1 - v) + b * v
        return t * t * (3 - 2 * t)

    px = bytearray()
    lx, ly, lz = -0.6, -0.6, 0.53  # light from the north-west, above
    for y in range(h):
        for x in range(w):
            e = at(x, y)
            if e <= 0.0:
                c = mix(SHALLOW, SEA, -e / 1.2) if e > -1.2 else mix(SEA, DEEP, (-e - 1.2) / 4.0)
            else:
                c = mix(GRASS, FOREST, woods(x, y))
                c = mix(c, HILL, (e - 1.5) / 3.0)
                c = mix(c, ROCK, (e - 4.5) / 3.0)
                c = mix(c, SNOW, (e - 8.0) / 2.0)
                if e < 0.12:
                    c = mix(c, SAND, 1.0 - e / 0.12)
                # Relief shading: the surface normal against the light.
                dx = (at(x + 1, y) - at(x - 1, y)) * 2.0
                dy = (at(x, y + 1) - at(x, y - 1)) * 2.0
                n = math.sqrt(dx * dx + dy * dy + 1.0)
                shade = (-dx * lx - dy * ly + lz) / n / lz
                c = tuple(v * max(0.55, min(1.35, 0.35 + 0.65 * shade)) for v in c)
            px += bytes(int(max(0, min(255, v))) for v in c)
    with open(out, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (w, h))
        f.write(px)
    print("wrote", out)


if __name__ == "__main__":
    main()
