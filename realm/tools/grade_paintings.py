"""The title, intro and reign-end paintings graded toward the in-game palette (the professional audit:
they read photographic beside the painted realm; art-direction-report.md: lifted, warm mid-tones, quieter
greens, softer contrast). Each painting is read from git at --from (the ungraded original), so running
it again never grades twice: lifted shadows, a little less saturation, then the game's own storybook
LUT (assets/grade/storybook.png, tools/make_storybook_lut.py).

Run:  python3 grade_paintings.py --from <commit with the originals> [--dry <sheet.jpg>]"""
import argparse, glob, os, subprocess
import numpy as np
import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
REALM = os.path.normpath(os.path.join(HERE, ".."))
N = 33
LIFT, SAT = 0.045, 0.9


def lut():
    img = cv2.imread(os.path.join(REALM, "assets", "grade", "storybook.png"))[:, :, ::-1].astype(np.float32) / 255
    # tiles side by side: x = blue * 33 + red, y = green  ->  L[r, g, b]
    return img.reshape(N, N, N, 3).transpose(1, 0, 2, 3)  # rows g, columns b*33+r: (g, b, r) -> (b, g, r)


def apply_lut(f, L):
    # f in 0..1 RGB, trilinear over the 33-step grid. L indexed [b, g, r].
    x = f * (N - 1)
    i0 = np.floor(x).astype(int).clip(0, N - 2)
    t = x - i0
    out = np.zeros_like(f)
    for dr in (0, 1):
        for dg in (0, 1):
            for db in (0, 1):
                w = (t[..., 0] if dr else 1 - t[..., 0]) * (t[..., 1] if dg else 1 - t[..., 1]) * (t[..., 2] if db else 1 - t[..., 2])
                out += w[..., None] * L[i0[..., 2] + db, i0[..., 1] + dg, i0[..., 0] + dr]
    return out


def grade(bgr, L):
    f = bgr[:, :, ::-1].astype(np.float32) / 255
    f = LIFT + f * (1 - LIFT)                                  # lifted shadows: painted, not photographic
    lum = (f @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    f = lum + (f - lum) * SAT                                  # a little quieter
    f = apply_lut(np.clip(f, 0, 1), L)
    return (np.clip(f, 0, 1)[:, :, ::-1] * 255 + 0.5).astype(np.uint8)


def files():
    return sorted(glob.glob(os.path.join(REALM, "assets", "intro", "art", "*.jpg"))) + \
        sorted(glob.glob(os.path.join(REALM, "assets", "intro", "splash", "*.jpg"))) + [os.path.join(REALM, "assets", "ui", "title-background.png")]


def original(path, ref):
    rel = os.path.relpath(path, os.path.dirname(REALM))
    data = subprocess.run(["git", "-C", os.path.dirname(REALM), "show", f"{ref}:{rel}"], capture_output=True, check=True).stdout
    return cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="ref", required=True)
    ap.add_argument("--dry", help="write a before/after sheet here instead of grading the files")
    a = ap.parse_args()
    L = lut()
    if a.dry:
        rows = []
        for p in files()[:6]:
            o = original(p, a.ref)
            g = grade(o, L)
            rows.append(np.hstack([cv2.resize(o, (480, 270)), cv2.resize(g, (480, 270))]))
        cv2.imwrite(a.dry, np.vstack(rows))
        return
    for p in files():
        o = original(p, a.ref)
        g = grade(o, L)
        if p.endswith(".png"):
            cv2.imwrite(p, g, [cv2.IMWRITE_PNG_COMPRESSION, 6])
        else:
            cv2.imwrite(p, g, [cv2.IMWRITE_JPEG_QUALITY, 92])
        print(os.path.relpath(p, REALM))


if __name__ == "__main__":
    main()
