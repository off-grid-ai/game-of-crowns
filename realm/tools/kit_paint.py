"""The village kit's colour sheets repainted in the painted style (docs/research/quality-deep-dive.md #5; North Star
docs/art/target/01-town.jpg; the Warcraft III Reforged recipe): deeper value steps, dark grooves between tiles and
stones, painted highlights on the crests, a warm top light and a cool coloured shade, and a more distinct hue per
material. Pixel-aligned by construction: everything is painted from the sheet's own normal map, so every trim band and
tile stays where the kit's UVs expect it (an image model's repaint drifts).

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P realm/tools/kit_paint.py -- [sheet ...]

Reads realm/assets/village/T_<sheet>_BaseColor.png (+ _Normal.png when there is one); writes
realm/assets/village/painted/T_<sheet>_BaseColor.webp. Knobs per sheet: realm/data/kit_paint.json. The originals are
never touched; the game swaps the painted ones in with --kit-paint=painted (house_builder.gd).
"""
import bpy
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REALM = os.path.dirname(HERE)
KIT = os.path.join(REALM, "assets", "village")
OUT = os.path.join(KIT, "painted")


def load(path):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"  # the raw numbers: base colour stays in its own (sRGB) encoding
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    return img, px


def blur(a, r):
    """A box blur r pixels wide each way, wrapping (the sheets tile)."""
    if r <= 0:
        return a
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for k in range(-r, r + 1):
            acc += np.roll(out, k, axis=axis)
        out = acc / (2 * r + 1)
    return out


def paint(name, k):
    base_path = os.path.join(KIT, "T_%s_BaseColor.png" % name)
    img, px = load(base_path)
    rgb = px[..., :3].copy()
    alpha = px[..., 3:4]
    h, w = rgb.shape[:2]
    npath = os.path.join(KIT, "T_%s_Normal.png" % name)
    if os.path.exists(npath):
        _, npx = load(npath)
        if npx.shape[:2] != (h, w):
            npx = None
    else:
        npx = None
    if npx is not None:
        n = npx[..., :3] * 2.0 - 1.0
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
        # Blender's pixel rows run bottom-up; the sheet's "up" (the texture's +V) is +Y in the normal map (OpenGL).
        light = np.array(k.get("light", [0.0, 0.55, 0.83]), dtype=np.float32)
        light /= np.linalg.norm(light)
        lit = np.clip((n * light).sum(-1), 0.0, 1.0)
        flat = float(light[2])
        rel = lit - flat  # above 0: faces the top light; below: turns away
        # Curvature from the normal's divergence: crests (convex) above 0, grooves (concave) below.
        dx = np.roll(n[..., 0], -1, axis=1) - np.roll(n[..., 0], 1, axis=1)
        dy = np.roll(n[..., 1], -1, axis=0) - np.roll(n[..., 1], 1, axis=0)
        curv = blur(dx + dy, int(k.get("curv_blur", 2)))
        groove = np.clip(-curv * float(k.get("groove_gain", 6.0)), 0.0, 1.0)
        crest = np.clip(curv * float(k.get("crest_gain", 4.0)), 0.0, 1.0)
        # The steep sides of a tile or stone (its normal far from flat) read as its shaded edge.
        steep = np.clip((1.0 - n[..., 2]) * float(k.get("steep_gain", 2.0)), 0.0, 1.0)
    else:
        rel = np.zeros((h, w), np.float32)
        groove = crest = steep = rel
    # Deeper value steps: the sheet's own light and dark pulled apart round its middle.
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    mid = float(np.median(lum))
    contrast = float(k.get("contrast", 1.25))
    rgb = np.clip(mid + (rgb - mid) * contrast, 0.0, 1.0)
    # A more distinct hue: the material's own colour pulled toward its target (tile red, plaster cream...).
    tgt = k.get("hue")
    if tgt:
        t = np.array(tgt, np.float32)
        lum = (rgb @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
        tl = float(t @ np.array([0.299, 0.587, 0.114], np.float32))
        # Only where the sheet is coloured already: a trim sheet holds several materials in bands (the wood sheet's
        # grey stone and white strip), and a grey band keeps its grey.
        own = rgb.max(-1, keepdims=True) - rgb.min(-1, keepdims=True)
        mix = float(k.get("hue_mix", 0.45)) * np.clip(own / float(k.get("hue_floor", 0.12)), 0.0, 1.0)
        rgb = rgb * (1.0 - mix) + (t / max(tl, 1e-3)) * lum * mix
    # Saturation.
    lum = (rgb @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
    rgb = lum + (rgb - lum) * float(k.get("saturation", 1.2))
    # Warm top light, cool coloured shade.
    warm = np.array(k.get("warm", [1.08, 1.02, 0.9]), np.float32)
    cool = np.array(k.get("cool", [0.78, 0.82, 0.95]), np.float32)
    up = np.clip(rel * float(k.get("light_gain", 2.2)), 0.0, 1.0)[..., None]
    down = np.clip(-rel * float(k.get("shade_gain", 2.2)), 0.0, 1.0)[..., None]
    rgb = rgb * (1.0 + (warm - 1.0) * up) * (1.0 - (1.0 - cool) * down)
    # Dark grooves, the steep edges a little darker, painted highlights on the crests.
    rgb = rgb * (1.0 - float(k.get("groove", 0.55)) * groove[..., None])
    rgb = rgb * (1.0 - float(k.get("edge", 0.18)) * steep[..., None])
    rgb = rgb + float(k.get("crest", 0.14)) * crest[..., None] * warm
    # The kit sheet's own mean brightness kept (keep_mean): every tint laid on top (house_tiers.gd's washes and honey
    # stone and timber, look.json kit_tints in the one look and v3) was tuned on the kit's values, so the repaint moves
    # contrast, grooves, highlights and hue inside the sheet, never the material's overall value. gain on top.
    if k.get("keep_mean", True):
        w3 = np.array([0.299, 0.587, 0.114], np.float32)
        rgb = rgb * (float((px[..., :3] @ w3).mean()) / max(float((np.clip(rgb, 0.0, 1.0) @ w3).mean()), 1e-4))
    rgb = np.clip(rgb * float(k.get("gain", 1.0)), 0.0, 1.0)
    out = np.concatenate([rgb, alpha], -1)
    os.makedirs(OUT, exist_ok=True)
    o = bpy.data.images.new("painted_" + name, w, h, alpha=True)
    o.colorspace_settings.name = "Non-Color"
    o.pixels[:] = out.ravel()
    o.filepath_raw = os.path.join(OUT, "T_%s_BaseColor.webp" % name)
    o.file_format = "WEBP"
    bpy.context.scene.render.image_settings.quality = 92
    o.save()
    print("PAINTED %s -> %s (mid %.2f, groove %.1f%%, crest %.1f%%)" % (name, o.filepath_raw, mid, float(groove.mean()) * 100, float(crest.mean()) * 100))


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    knobs = json.load(open(os.path.join(REALM, "data", "kit_paint.json")))
    sheets = knobs.get("sheets", {})
    for name in (a or list(sheets.keys())):
        paint(name, dict(knobs.get("defaults", {}), **sheets.get(name, {})))


main()
