"""A still's light against the art target (docs/art/target/01-town.jpg): is the frame washed out?

Mac (2026-11-12): Kingsmere's square looks washed out, too bright and pale. This reads a rendered PNG and prints
the numbers each square round is judged by, beside 01-town's, with PASS or FAIL per line:

  mean   grey mean (Rec. 709 luma of the sRGB values, 0-1; ImageMagick's grayscale mean)  target ~0.42-0.45
  clip   share of pixels brighter than 0.92 (blown highlights, snow and pale stone gone white)  under 1%
  sat    HSL saturation mean (ImageMagick's)                                                  0.45 or more
  p5     the darkest twentieth's luma (shadows not crushed)                                   0.06 or more
  p95    the brightest twentieth's luma
  white  share of pale, colourless pixels (luma over 0.75, chroma under 0.12: snow, bleached paving)

Needs only ImageMagick (`magick`) and Python's standard library. The HUD's corners are masked (--hud, on by default: top bar 6% and the minimap's corner) so the panels don't count.

  python3 realm/tools/still_probe.py <still.png> [<more.png> ...]   # each beside 01-town
  python3 realm/tools/still_probe.py --no-hud <still.png>           # whole frame
"""
import os
import re
import subprocess
import sys

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
TARGET = os.path.join(R, "docs", "art", "target", "01-town.jpg")
GOAL = {"mean": (0.42, 0.45), "clip": (0.0, 0.01), "sat": (0.45, 1.0), "p5": (0.06, 1.0)}
ROW = re.compile(r"^\s*(\d+):\s*\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)")


def histogram(path, crop=None):
    """The image's colours and their counts (ImageMagick's histogram, 8-bit), of the crop (w, h, x, y) if given."""
    cmd = ["magick", path, "-alpha", "off", "-colorspace", "sRGB"]
    if crop:
        cmd += ["-crop", "%dx%d+%d+%d" % crop, "+repage"]
    cmd += ["-depth", "8", "-format", "%c", "histogram:info:-"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        m = ROW.match(line)
        if m:
            yield int(m.group(1)), float(m.group(2)) / 255.0, float(m.group(3)) / 255.0, float(m.group(4)) / 255.0


def size(path):
    w, h = subprocess.run(["magick", "identify", "-format", "%w %h", path + "[0]"], capture_output=True, text=True, check=True).stdout.split()
    return int(w), int(h)


def percentile(pairs, total, q):
    """numpy's linear percentile over (value, count) pairs sorted by value."""
    k = (total - 1) * q / 100.0
    lo, f = int(k), k - int(k)
    seen, a, b = 0, None, None
    for v, n in pairs:
        if a is None and seen + n > lo:
            a = v
        if seen + n > lo + 1:
            b = v
            break
        seen += n
    b = a if b is None else b
    return a + (b - a) * f


def measure(path, hud=True):
    w, h = size(path)
    if hud:  # the top bar (6%) and the minimap's corner left out
        top, mm_y, mm_x = int(h * 0.06), int(h * 0.66), int(w * 0.87)
        parts = [(w, mm_y - top, 0, top), (mm_x, h - mm_y, 0, mm_y)]
    else:
        parts = [None]
    total = 0
    s_luma = s_sat = clip = white = 0.0
    lumas = {}
    for crop in parts:
        for n, r, g, b in histogram(path, crop):
            luma = r * 0.2126 + g * 0.7152 + b * 0.0722
            mx, mn = max(r, g, b), min(r, g, b)
            l, d = (mx + mn) / 2, mx - mn
            den = (mx + mn) if l <= 0.5 else (2 - mx - mn)
            sat = d / max(den, 1e-6) if d > 1e-6 else 0.0
            total += n
            s_luma += luma * n
            s_sat += sat * n
            clip += n if luma > 0.92 else 0
            white += n if (luma > 0.75 and d < 0.12) else 0
            lumas[luma] = lumas.get(luma, 0) + n
    pairs = sorted(lumas.items())
    return {"mean": s_luma / total, "clip": clip / total, "sat": s_sat / total,
            "p5": percentile(pairs, total, 5), "p95": percentile(pairs, total, 95), "white": white / total}


def verdict(k, v):
    if k not in GOAL:
        return ""
    lo, hi = GOAL[k]
    return "PASS" if lo <= v <= hi else "FAIL"


def main(args):
    hud = "--no-hud" not in args
    paths = [x for x in args if not x.startswith("--")]
    if not paths:
        print(__doc__)
        return 2
    t = measure(TARGET, hud=False)
    bad = 0
    for path in paths:
        m = measure(path, hud)
        was = bad
        print(f"STILL {path}")
        for k in ("mean", "clip", "sat", "p5", "p95", "white"):
            v = verdict(k, m[k])
            bad += v == "FAIL"
            pct = k in ("clip", "white")
            f = (lambda x: f"{x * 100:5.1f}%") if pct else (lambda x: f"{x:6.3f}")
            print(f"  {k:5s} {f(m[k])}   01-town {f(t[k])}   {v}")
        print("  LIGHT", "PASS" if bad == was else f"FAIL ({bad - was})")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
