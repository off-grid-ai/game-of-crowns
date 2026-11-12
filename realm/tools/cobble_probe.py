"""The square's setts against 01-town's (supervisor, 2026-11-12: "match 01-town, warmer and rounder setts").

Reads bare-cobble patches of docs/art/target/01-town.jpg and the paving texture the game lays (realm/data/towns.json
paving.texture, at paving.tile game units a sheet), and prints, for each, the numbers a square round is judged by:

  hue    mean hue of the stones, degrees (HSV; 01-town's warm grey-beige sits near 30)
  sat    mean saturation (0-1)
  val    mean value (0-1)
  joint  how much darker the joints are than the stones (value p85 - p15)
  stone  one stone's size on the ground, metres (the texture's dominant repeat by autocorrelation, along both axes,
         averaged; 01-town's measured against a person there: TARGET_PX_PER_M)

and PASS or FAIL against 01-town: the hue within TOL (warm, not pink or grey), the joints at least as dark as
01-town's (JOINT_FLOOR). Saturation, value and stone size are printed, not judged: 01-town is a lit painting seen
from a few metres, our c01 camera sits about five times further out, so its real-size pebbles (0.19 m, 6a7746cf)
landed at 2-3 px a stone and the square read as sand (round 15). Whether the setts read as stones is judged on the
rendered frame: realm/tools/still_probe.py's setts line. Exit 1 on a fail.

  python3 realm/tools/cobble_probe.py [texture.jpg ...]   # default: the game's paving.texture; more to compare
"""
import json
import os
import sys

import numpy as np
from PIL import Image  # noqa: F401  (pillow is in the system python numpy came with)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "..", "docs", "art", "target", "01-town.jpg")
# Bare cobbles in 01-town (x, y, w, h): the square round the well and the street to its right, clear of people,
# carts, stalls and shadows (checked by eye on a contact sheet).
PATCHES = [(880, 750, 60, 45), (920, 625, 50, 40)]
TARGET_PX_PER_M = 89.0  # 01-town's guard by the smithy: about 160 px from helmet to feet for about 1.8 m
S = 0.12  # game units a metre (towns.gd S)
TOL = {"hue": 12.0}
JOINT_FLOOR = 1.0  # the joints' depth (joint) at least this share of 01-town's


def hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rr = m & (mx == r)
    gg = m & (mx == g) & ~rr
    bb = m & ~rr & ~gg
    h[rr] = ((g - b)[rr] / d[rr]) % 6
    h[gg] = (b - r)[gg] / d[gg] + 2
    h[bb] = (r - g)[bb] / d[bb] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h * 60.0, s, mx


def period(gray):
    """The dominant repeat (pixels) of a grey image: the first autocorrelation peak past zero, along x and y."""
    g = gray - gray.mean()
    f = np.fft.rfft2(g)
    ac = np.fft.irfft2(f * np.conj(f), s=g.shape)
    out = []
    for prof in (ac[0, : g.shape[1] // 2], ac[: g.shape[0] // 2, 0]):
        prof = prof / prof[0]
        # past the first dip below zero, the highest peak
        k = np.argmax(prof < 0) if np.any(prof < 0) else 1
        k = max(int(k), 2)
        out.append(k + int(np.argmax(prof[k:])))
    return float(np.mean(out))


def numbers(rgb, px_per_m):
    h, s, v = hsv(rgb)
    hue = float(np.degrees(np.arctan2(np.sin(np.radians(h)).mean(), np.cos(np.radians(h)).mean())) % 360)
    return {
        "hue": hue,
        "sat": float(s.mean()),
        "val": float(v.mean()),
        "joint": float(np.percentile(v, 85) - np.percentile(v, 15)),
        "stone": period(v) / px_per_m,
    }


def target():
    img = np.asarray(Image.open(TARGET).convert("RGB"), dtype=np.float64) / 255.0
    rows = [numbers(img[y : y + h, x : x + w], TARGET_PX_PER_M) for x, y, w, h in PATCHES]
    out = {k: float(np.mean([r[k] for r in rows])) for k in rows[0] if k != "stone"}
    out["stone"] = float(np.median([r["stone"] for r in rows]))
    return out


def ours(path, tile, tint):
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0
    img = np.clip(img * np.array(tint[:3]), 0, 1)
    sheet_m = tile / S  # metres one sheet covers on the ground
    return numbers(img, img.shape[1] / sheet_m)


def main():
    pave = json.load(open(os.path.join(ROOT, "data", "towns.json")))["paving"]
    tile = float(pave.get("tile", 0.3))
    tint = pave.get("tint", [1, 1, 1])
    paths = sys.argv[1:] or [os.path.join(ROOT, pave["texture"].replace("res://", ""))]
    t = target()
    print("01-town  hue %5.1f  sat %.3f  val %.3f  joint %.3f  stone %.2f m" % (t["hue"], t["sat"], t["val"], t["joint"], t["stone"]))
    bad = 0
    for p in paths:
        n = ours(p, tile, tint)
        fails = []
        if abs((n["hue"] - t["hue"] + 180) % 360 - 180) > TOL["hue"]:
            fails.append("hue")
        if n["joint"] < t["joint"] * JOINT_FLOOR:
            fails.append("joint")
        print("%-8s hue %5.1f  sat %.3f  val %.3f  joint %.3f  stone %.2f m  %s  (%s)" % (
            "ours", n["hue"], n["sat"], n["val"], n["joint"], n["stone"], "PASS" if not fails else "FAIL " + ",".join(fails), os.path.basename(p)))
        bad += 1 if fails else 0
    print("COBBLES %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
