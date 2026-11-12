"""Fit the v3 colour grade (look.json v3.lut) from our town frames to the art target 01-town, offline.
Run: arch -arm64 /usr/bin/python3 realm/tools/fit_look_lut.py OUT_PREVIEW_DIR FRAME...
Measured (docs/review/look-gap.md): our frames' brightness range is near the target's (goldrock-6 L p5-p95 62.9 vs
65.6), so a full lightness CDF match only brightened the already bright frames (tried first: goldrock-new blew out);
what differs is where the colour sits and how far it goes. So the fit is parametric, each knob from a measurement:
- L: a gentle S round the target's median (contrast), and the crushed shade's toe lifted (`toe`): tuned on Kingsmere's
  square (Mac, 2026-11-12: one view until it's right), whose darkest tenth sits near black (L 3 vs the target's 14).
- chroma: scaled to the target's mean chroma (fitted), easing off above C 70 so nothing neons.
- hue: our chroma piles up in Lab orange (60-75 deg: 0.36 vs 0.17); the target's sits in red (30-45: 0.23 vs 0.13)
  and green (110-140: 0.10 vs 0.02), so orange turns toward red by up to `turn` and the olive grass toward green
  by up to `green`.
- strength: the share of the change kept.
The fit becomes a 33^3 LUT composed after the current grade (assets/grade/bold.png): v3.png = fit(bold(x)),
in golden-hour.png's layout (red across, green down, blue by tile), and before/after previews of each frame."""
import os
import sys
import numpy as np
import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
TARGET = os.path.join(ROOT, "docs", "art", "target", "01-town.jpg")
BOLD = os.path.join(HERE, "..", "assets", "grade", "bold.png")
OUT = os.path.join(HERE, "..", "assets", "grade", "v3.png")
N = 33
STRENGTH = 1.0
TURN = 9.0     # degrees, orange (Lab hue 52-82) toward red
GREEN = 12.0   # degrees, olive (Lab hue 92-125) toward green
CONTRAST = 0.55  # the S: 0.55 is a slope of 1.10 at the pivot
TOE = 8.0      # L units the deepest shade comes up (fading out by L 25): Kingsmere's darkest tenth sits at L 3, the target's at 14
PIVOT = 46.0   # the target's median L


def lab_of(img_bgr_u8):
    return cv2.cvtColor(img_bgr_u8.astype(np.float32) / 255.0, cv2.COLOR_BGR2LAB)


def masked(img):
    h, w = img.shape[:2]
    m = np.ones((h, w), bool)
    m[: int(h * 0.075), :] = False
    m[int(h * 0.67):, int(w * 0.87):] = False
    return m


def small(path):
    img = cv2.imread(path)
    h, w = img.shape[:2]
    return cv2.resize(img, (960, int(h * 960 / w)), interpolation=cv2.INTER_AREA)


def cdf(vals, bins):
    hst, _ = np.histogram(vals, bins=bins)
    c = np.cumsum(hst).astype(np.float64)
    return c / c[-1]


def fit(frames):
    tl = lab_of(small(TARGET)).reshape(-1, 3)
    ours = []
    for p in frames:
        im = small(p)
        ours.append(lab_of(im)[masked(im)])
    ol = np.concatenate(ours)
    bins = np.linspace(0, 100, 257)
    mid = 0.5 * (bins[1:] + bins[:-1])
    co, ct = cdf(ol[:, 0], bins), cdf(tl[:, 0], bins)
    lmap = np.interp(co, ct, mid)  # our L at each bin -> the target's L at the same rank
    lmap = cv2.GaussianBlur(lmap.reshape(1, -1).astype(np.float32), (1, 0), 4).ravel()  # no banding steps
    chroma_t = np.hypot(tl[:, 1], tl[:, 2]).mean()
    chroma_o = np.hypot(ol[:, 1], ol[:, 2]).mean()
    return {"lmid": mid, "lmap": lmap, "chroma": chroma_t / chroma_o}


def apply_lab(lab, f, strength=STRENGTH, turn=TURN):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    x = (L - PIVOT) / 50.0
    L2 = PIVOT + 50.0 * np.tanh(x * CONTRAST) / np.tanh(CONTRAST)  # an S: slope CONTRAST/tanh(CONTRAST) at the pivot, flat at the ends
    L2 = np.clip(L2 + TOE * np.clip(1.0 - L / 25.0, 0.0, 1.0) ** 2, 0.0, 100.0)
    C = np.hypot(a, b)
    hdeg = np.degrees(np.arctan2(b, a))
    k = 1.0 + (f["chroma"] - 1.0) * np.clip(1.0 - (C - 70.0) / 30.0, 0.0, 1.0) * np.clip(C / 8.0, 0.0, 1.0)  # greys stay grey
    C2 = C * k
    sat = np.clip(C / 15.0, 0.0, 1.0)
    w_or = np.clip(1.0 - np.abs(hdeg - 67.0) / 15.0, 0.0, 1.0) * sat
    w_gr = np.clip(1.0 - np.abs(hdeg - 108.0) / 17.0, 0.0, 1.0) * sat
    h2 = np.radians(hdeg - turn * w_or + GREEN * w_gr)
    out = np.stack([L2, C2 * np.cos(h2), C2 * np.sin(h2)], axis=-1)
    return lab + (out - lab) * strength


def apply_bgr(img_u8, f):
    lab = lab_of(img_u8)
    out = cv2.cvtColor(apply_lab(lab, f).astype(np.float32), cv2.COLOR_LAB2BGR)
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


def write_lut(f):
    bold = cv2.imread(BOLD)[:, :, ::-1].astype(np.float32) / 255.0  # RGB, N tall, N*N wide
    grid = np.stack([bold[:, k * N:(k + 1) * N, :] for k in range(N)], axis=2)  # [g, r, b] -> rgb
    bgr = grid[..., ::-1].reshape(1, -1, 3).astype(np.float32)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    out = cv2.cvtColor(apply_lab(lab, f).astype(np.float32), cv2.COLOR_LAB2BGR)
    out = np.clip(out, 0, 1).reshape(grid.shape)[..., ::-1]
    img = np.concatenate([out[:, :, k, :] for k in range(N)], axis=1)
    cv2.imwrite(OUT, (img[:, :, ::-1] * 255 + 0.5).astype(np.uint8))
    return OUT


if __name__ == "__main__":
    outdir, frames = sys.argv[1], sys.argv[2:]
    os.makedirs(outdir, exist_ok=True)
    f = fit(frames)
    print("chroma x%.3f" % f["chroma"])
    print("L map (ours->target) at 10/25/50/75/90:", [round(float(np.interp(v, f["lmid"], f["lmap"])), 1) for v in (10, 25, 50, 75, 90)])
    for p in frames:
        img = cv2.imread(p)
        after = apply_bgr(img, f)
        name = p.split("/")[-2] + "-" + os.path.basename(p).rsplit(".", 1)[0]
        h, w = img.shape[:2]
        s = 1200 / w
        pair = np.hstack([cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_AREA), cv2.resize(after, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)])
        cv2.imwrite(os.path.join(outdir, name + "-before-after.jpg"), pair, [cv2.IMWRITE_JPEG_QUALITY, 88])
        cv2.imwrite(os.path.join(outdir, name + "-after.png"), after)
    print(write_lut(f))
