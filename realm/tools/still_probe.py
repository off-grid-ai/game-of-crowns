"""A still's light against the art target (docs/art/target/01-town.jpg): is the frame washed out?

Mac (2026-11-12): Kingsmere's square looks washed out, too bright and pale. This reads a rendered PNG and prints
the numbers each square round is judged by, beside 01-town's, with PASS or FAIL per line:

  mean   grey mean (Rec. 709 luma of the sRGB values, 0-1; ImageMagick's grayscale mean)  target ~0.42-0.45
  clip   share of pixels brighter than 0.92 (blown highlights, snow and pale stone gone white)  under 1%
  sat    HSL saturation mean (ImageMagick's)                                                  0.45 or more
  p5     the darkest twentieth's luma (shadows not crushed)                                   0.06 or more
  p95    the brightest twentieth's luma
  white  share of pale, colourless pixels (luma over 0.75, chroma under 0.12: snow, bleached paving)

The HUD's corners are masked (--hud, on by default: top bar 6% and the minimap's corner) so the panels don't count.

  python3 realm/tools/still_probe.py <still.png> [<more.png> ...]   # each beside 01-town
  python3 realm/tools/still_probe.py --no-hud <still.png>           # whole frame
"""
import os
import sys

import numpy as np
from PIL import Image

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
TARGET = os.path.join(R, "docs", "art", "target", "01-town.jpg")
GOAL = {"mean": (0.42, 0.45), "clip": (0.0, 0.01), "sat": (0.45, 1.0), "p5": (0.06, 1.0)}


def measure(path, hud=True):
    a = np.asarray(Image.open(path).convert("RGB"), float) / 255.0
    h, w, _ = a.shape
    keep = np.ones((h, w), bool)
    if hud:
        keep[: int(h * 0.06), :] = False  # the top bar
        keep[int(h * 0.66):, int(w * 0.87):] = False  # the minimap
    p = a[keep]
    luma = p[:, 0] * 0.2126 + p[:, 1] * 0.7152 + p[:, 2] * 0.0722
    mx, mn = p.max(1), p.min(1)
    l = (mx + mn) / 2
    d = mx - mn
    den = np.where(l <= 0.5, mx + mn, 2 - mx - mn)
    sat = np.where(d > 1e-6, d / np.maximum(den, 1e-6), 0.0)
    return {"mean": luma.mean(), "clip": (luma > 0.92).mean(), "sat": sat.mean(),
            "p5": np.percentile(luma, 5), "p95": np.percentile(luma, 95),
            "white": ((luma > 0.75) & (d < 0.12)).mean()}


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
        print(f"STILL {path}")
        for k in ("mean", "clip", "sat", "p5", "p95", "white"):
            v = verdict(k, m[k])
            bad += v == "FAIL"
            pct = k in ("clip", "white")
            f = (lambda x: f"{x * 100:5.1f}%") if pct else (lambda x: f"{x:6.3f}")
            print(f"  {k:5s} {f(m[k])}   01-town {f(t[k])}   {v}")
    print("LIGHT", "PASS" if bad == 0 else f"FAIL ({bad})")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
