"""Measure the look gap between our frames and the art target (docs/review/look-gap.md).
Run: arch -arm64 /usr/bin/python3 realm/tools/look_gap.py TARGET FRAME... (prints a markdown table).
The HUD (top band, minimap corner) is masked out of our frames; every image is resized to 960 wide first."""
import sys
import numpy as np
import cv2

W = 960


def load(path, hud):
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    h, w = img.shape[:2]
    img = cv2.resize(img, (W, int(h * W / w)), interpolation=cv2.INTER_AREA)
    mask = np.ones(img.shape[:2], bool)
    if hud:
        H = img.shape[0]
        mask[: int(H * 0.075), :] = False                      # the top bar
        mask[int(H * 0.67):, int(W * 0.87):] = False             # the minimap
    return img, mask


def stats(path, hud):
    img, m = load(path, hud)
    f = img.astype(np.float32) / 255.0
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV_FULL).astype(np.float32)
    lab = cv2.cvtColor(f, cv2.COLOR_BGR2LAB)
    L = lab[..., 0][m]
    sat = hsv[..., 1][m] / 255.0
    hue = hsv[..., 0][m] / 255.0 * 360.0
    b, g, r = f[..., 0][m], f[..., 1][m], f[..., 2][m]
    rg, yb = r - g, 0.5 * (r + g) - b
    colourful = np.sqrt(rg.std() ** 2 + yb.std() ** 2) + 0.3 * np.sqrt(rg.mean() ** 2 + yb.mean() ** 2)
    dark = np.min(f, axis=2)
    dark = cv2.erode(dark, np.ones((9, 9), np.uint8))[m]      # dark channel prior: haze lifts it
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    lap = cv2.Laplacian(gray, cv2.CV_32F)[m]
    p = np.percentile(L, [5, 25, 50, 75, 95])
    chroma = np.sqrt(lab[..., 1] ** 2 + lab[..., 2] ** 2)[m]
    sel = sat > 0.25
    hb = np.histogram(hue[sel], bins=[0, 20, 45, 70, 160, 200, 260, 330, 360])[0].astype(float)
    hb[0] += hb[-1]
    hb = hb[:-1] / max(1, sel.sum())
    return {
        "L mean": L.mean(), "L std (contrast)": L.std(), "L p5": p[0], "L p50": p[2], "L p95": p[4],
        "p95-p5 range": p[4] - p[0], "shadow L (darkest 10%)": L[L <= np.percentile(L, 10)].mean(),
        "sat mean (HSV)": sat.mean(), "share sat>0.5": (sat > 0.5).mean(), "chroma mean (Lab)": chroma.mean(),
        "colourfulness (H-S)": colourful * 100, "haze (dark channel)": dark.mean(), "sharpness (lap std)": lap.std(),
        "hue red 0-20": hb[0], "orange 20-45": hb[1], "yellow 45-70": hb[2], "green 70-160": hb[3],
        "cyan 160-200": hb[4], "blue 200-260": hb[5], "magenta 260-330": hb[6],
    }


if __name__ == "__main__":
    target, frames = sys.argv[1], sys.argv[2:]
    cols = [("01-town", stats(target, False))] + [(p.split("/")[-2] + "/" + p.split("/")[-1].rsplit(".", 1)[0], stats(p, True)) for p in frames]
    keys = list(cols[0][1].keys())
    print("| metric | " + " | ".join(c[0] for c in cols) + " |")
    print("|---|" + "---|" * len(cols))
    for k in keys:
        print("| " + k + " | " + " | ".join(f"{c[1][k]:.3f}" if c[1][k] < 2 else f"{c[1][k]:.1f}" for c in cols) + " |")
