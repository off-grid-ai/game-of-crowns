"""Predicted brightness of a town under the one look, without the GPU (art target town-a/b: frame
brightness 0.33-0.42; docs/research/army-and-town-rules.md section 2, rule 7).

What a pixel of each surface comes to: the kit texture's mean colour (linear), times its tint as Godot
takes it (a material's albedo colour is sRGB, so a tint t multiplies linear light by about t^2.2), times
the light on it (data/look.json: the sun's energy and colour on the surface's slope, the shade's fill from
the sky and the ambient colour, the camera-side fill), through exposure, AgX, the contrast and saturation,
then the grade's LUT (assets/grade/*.png, read as the game reads it). The town is the crown seat's mix of
walls and roofs (data/assets.json house_kit tiers) at every bearing of the camera to the sun, so a town
framed into the sun counts as much as one framed with it.

The shade's and the sun's strengths are fitted once to batch 6 (Kingsmere km-cap: walls facing the lens
in shade at luma 0.15, the street's earth in the sun at 0.385, measured), so the numbers are relative to what we have seen, not absolute. A probe, not a render.

  python3 realm/tools/light_probe.py            # today's data
  python3 realm/tools/light_probe.py --was      # beside batch 6's light and walls
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

REALM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LUMA = np.array([0.2126, 0.7152, 0.0722])

# Batch 6's light and walls (look.json and assets.json house_kit before 45e62bfc / 32e76dbc): the fit.
BATCH6 = {
    "look": {"sun_elevation": 42.0, "sun_energy": 1.0, "shadow_opacity": 0.85, "ambient_energy": 1.8,
             "sun_color": [1.0, 0.95, 0.86], "ambient_color": [0.55, 0.65, 0.95], "sky_contribution": 0.8,
             "exposure": 1.12, "saturation": 1.3, "contrast": 1.15, "lut": "res://assets/grade/bold.png"},
    "kit": {"washes": [[0.97, 0.92, 0.82], [1.0, 1.0, 0.98], [0.96, 0.83, 0.6], [0.96, 0.84, 0.78], [0.86, 0.89, 0.9], [0.82, 0.74, 0.62]],
            "stone_tint": [1, 1, 1], "timber_tint": [1, 1, 1]},
}
SHADED_WALL_B6 = 0.15  # measured: km-cap, batch 6, walls facing the lens (stone and timber, in shade)
LIT_ROAD_B6 = 0.385  # measured: km-cap, batch 6, the street's earth in the sun
FRAMES_B6 = (0.214, 0.319)  # measured: batch 6 km-cap (d4.5) and km-d14, the whole frame but the panels
SKY = np.array([0.62, 0.74, 1.0])  # the clear sky's colour in the shade (Sky3D, day)


def read(rel):
    with open(os.path.join(REALM, rel)) as f:
        return json.load(f)


def lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((np.maximum(c, 0) + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def tex_mean(rel):
    a = np.asarray(Image.open(os.path.join(REALM, rel)).convert("RGB"), float) / 255.0
    return lin(a).reshape(-1, 3).mean(0)


def leaf_mean(rel):
    """A tree's leaves: the mean of its leaf texture's green texels (green over red and blue; the cut-out's clear texels
    are black and drop out)."""
    a = np.asarray(Image.open(os.path.join(REALM, rel)).convert("RGB"), float) / 255.0
    px = a.reshape(-1, 3)
    return lin(px[(px[:, 1] > px[:, 0]) & (px[:, 1] > px[:, 2])]).mean(0)


# Godot's AgX (servers/rendering/renderer_rd/shaders/effects/tonemap.glsl), columns as written there.
_IN = np.array([[0.54490813676363087053, 0.14044005884001287035, 0.088827411851915368603],
                [0.37377945959812267119, 0.75410959864013760045, 0.17887712465043811023],
                [0.081384976686407536266, 0.10543358536857773485, 0.73224999956948382528]]).T
_OUT = np.array([[1.9645509602733325934, -0.29932243390911083839, -0.16436833806080403409],
                 [-0.85585845117807513559, 1.3264510741502356027, -0.23822464068860595117],
                 [-0.10886710826831608324, -0.027084020983874825605, 1.402665347143271889]]).T


def agx(c):
    lo, hi = -12.4739311883324, 4.02606881166759
    c = _IN @ np.maximum(c, 0)
    c = (np.clip(np.log2(np.maximum(c, 1e-10)), lo, hi) - lo) / (hi - lo)
    x2 = c * c
    x4 = x2 * x2
    c = 15.5 * x4 * x2 - 40.14 * x4 * c + 31.96 * x4 - 6.868 * x2 * c + 0.4298 * x2 + 0.1191 * c - 0.00232
    return np.maximum(_OUT @ c, 0) ** 2.2


class Lut:
    def __init__(self, path):
        self.on = bool(path) and os.path.exists(path)
        if self.on:
            a = np.asarray(Image.open(path).convert("RGB"), float) / 255.0  # 33 tiles: red across, green down, blue by tile
            self.n = a.shape[0]
            self.cube = a.reshape(self.n, self.n, self.n, 3).transpose(1, 0, 2, 3)  # [blue][green][red]

    def __call__(self, c):
        if not self.on:
            return c
        p = np.clip(c, 0, 1) * (self.n - 1)
        i = np.minimum(p.astype(int), self.n - 2)
        f = p - i
        out = np.zeros(3)
        for db in (0, 1):
            for dg in (0, 1):
                for dr in (0, 1):
                    w = (f[2] if db else 1 - f[2]) * (f[1] if dg else 1 - f[1]) * (f[0] if dr else 1 - f[0])
                    out += w * self.cube[i[2] + db, i[1] + dg, i[0] + dr]
        return out


def screen(radiance, look, lut):
    c = srgb(agx(radiance * float(look.get("exposure", 1.0))))
    c = 0.5 + (c - 0.5) * float(look.get("contrast", 1.0))  # Godot's BCS after the tonemap
    c = c.mean() + (c - c.mean()) * float(look.get("saturation", 1.0))
    return lut(np.clip(c, 0, 1))


def tint(t):
    return lin(np.asarray(t, float)) if t is not None else np.ones(3)


def dirs(look, bearing, fill):
    """The sun's and the fill's light directions (toward the light), the lens looking along -z."""
    el = math.radians(float(look.get("sun_elevation", 35.0)))
    az = math.radians(bearing)  # 0: the sun behind the lens, 180: the lens looks into it
    sun = np.array([math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el)])
    fe = math.radians(float(fill.get("elevation", 30.0)))
    ft = math.radians(float(fill.get("turn", 0.0)))
    fd = np.array([-math.sin(ft) * math.cos(fe), math.sin(fe), math.cos(ft) * math.cos(fe)])
    return sun, fd


def light(n, look, bearing, k_amb, sky_share, k_sun=1.0, shadow_part=0.3):
    fill = look.get("fill", {}) if look.get("fill", {}).get("on", False) else {}
    sun, fd = dirs(look, bearing, fill)
    sc = lin(look.get("sun_color", [1, 1, 1])) * float(look.get("sun_energy", 1.0))
    nl = max(0.0, float(n @ sun))
    shadow = shadow_part * float(look.get("shadow_opacity", 1.0))  # a share of a lit face under a neighbour's shadow
    direct = k_sun * sc * nl * (1 - shadow)
    sky = float(look.get("sky_contribution", 0.8))
    amb = k_amb * float(look.get("ambient_energy", 1.0)) * sky_share * (sky * SKY + (1 - sky) * np.asarray(look.get("ambient_color", [0.5, 0.6, 0.9])))
    f = np.zeros(3)
    if fill:
        f = lin(fill.get("color", [1, 1, 1])) * float(fill.get("energy", 0.0)) * max(0.0, float(n @ fd))
    return direct + amb + f


WALL = np.array([0.0, 0.0, 1.0])  # facing the lens
ROOF = np.array([0.0, math.cos(math.radians(45)), math.sin(math.radians(45))])  # a 45 deg slope facing the lens
GROUND = np.array([0.0, 1.0, 0.0])


def walls(kit, albedo):
    """The crown seat's street walls: plaster in its washes, stone, and timber framing (a timber-framed
    face is about 30% timber), by the townhouse, merchant and burgher tiers' wall weights."""
    tiers = kit.get("tiers", {})
    w = {"plaster": 0.0, "stone": 0.0, "timber": 0.0}
    for t in ("townhouse", "merchant", "burgher", "cottage"):
        for mix, share in tiers.get(t, {}).get("walls", {"timber": 1}).items():
            if mix == "stone":
                w["stone"] += share
            elif mix == "stone_timber":
                w["stone"] += share * 0.45
                w["plaster"] += share * 0.55 * 0.7
                w["timber"] += share * 0.55 * 0.3
            elif mix == "plaster":
                w["plaster"] += share
            else:
                w["plaster"] += share * 0.7
                w["timber"] += share * 0.3
    s = sum(w.values())
    washes = kit.get("washes", [[1, 1, 1]])
    plaster = np.mean([albedo["plaster"] * tint(c) for c in washes], axis=0)
    stone = albedo["stone"] * tint(kit.get("stone_tint"))
    timber = albedo["timber"] * tint(kit.get("timber_tint"))
    return [(plaster, w["plaster"] / s), (stone, w["stone"] / s), (timber, w["timber"] / s)]


def predict(look, kit, albedo, k_amb, k_sun, lut, bearings):
    out = {"wall": [], "wall_backlit": None, "roof": [], "ground": [], "frame": []}
    roof_a = albedo["roof"]
    for b in bearings:
        wl = sum(share * float(screen(a * light(WALL, look, b, k_amb, 0.75, k_sun), look, lut) @ LUMA) for a, share in walls(kit, albedo))
        rl = float(screen(roof_a * light(ROOF, look, b, k_amb, 0.9, k_sun), look, lut) @ LUMA)
        gl = float(screen(albedo["ground"] * light(GROUND, look, b, k_amb, 1.0, k_sun), look, lut) @ LUMA)
        green = float(screen(albedo["green"] * light(GROUND, look, b, k_amb, 1.0, k_sun), look, lut) @ LUMA)
        out["wall"].append(wl)
        out["roof"].append(rl)
        out["ground"].append(gl)
        out["frame"].append(0.22 * wl + 0.30 * rl + 0.28 * gl + 0.20 * green)  # a town at mid zoom (research section 2)
        if b == 180:
            out["wall_backlit"] = wl
    return {k: (float(np.mean(v)) if isinstance(v, list) else v) for k, v in out.items()}


def main():
    look = read("data/look.json")
    kit = read("data/assets.json")["house_kit"]
    v = "assets/village/"
    paving = read("data/towns.json").get("paving", {})
    albedo = {
        "plaster": tex_mean(v + "T_Plaster_BaseColor.png"),
        "stone": tex_mean(v + "T_UnevenBrick_BaseColor.png"),
        "timber": tex_mean(v + "T_WoodTrim_BaseColor.png"),
        # The street's roofs: red tile, slate, thatch and shingle in their tints (roof_tints; team colour off on them).
        "roof": np.mean([tex_mean(v + "T_RoundTiles_BaseColor.png") * tint(kit["roof_tints"]["tile"]),
                         lin([0.36, 0.40, 0.48]), lin([0.62, 0.48, 0.26]), lin([0.40, 0.30, 0.22])], axis=0),
        "ground": tex_mean(v + "T_UnevenBrick_BaseColor.png") * tint(paving.get("tint", [1, 1, 1])),
        "green": leaf_mean("assets/nature/Leaves_NormalTree_C.png"),
    }
    bearings = list(range(0, 360, 30))
    lut_of = lambda lk: Lut(os.path.join(REALM, str(lk.get("lut", "")).replace("res://", "")))
    # Fit the shade to batch 6: its walls facing the lens, in shade (the sun on the far side).
    b6 = dict(BATCH6["look"])
    b6kit = dict(kit)
    b6kit.update(BATCH6["kit"])
    lut6 = lut_of(b6)
    road = tex_mean("assets/ground/painted_v2/dirt_road.png") * tint(read("data/ground.json")["roads"]["tint"])
    k_amb, k_sun = 0.1, 1.0
    for _ in range(12):  # the shade from the walls in shade, the sun from the earth in the sun, in turn
        lo, hi = 0.005, 2.0
        for _ in range(40):
            k_amb = (lo + hi) / 2
            shaded = sum(s * float(screen(a * light(WALL, b6, 180, k_amb, 0.75, k_sun), b6, lut6) @ LUMA) for a, s in walls(b6kit, albedo))
            lo, hi = (k_amb, hi) if shaded < SHADED_WALL_B6 else (lo, k_amb)
        lo, hi = 0.05, 3.0
        for _ in range(40):
            k_sun = (lo + hi) / 2
            lit = float(screen(road * light(GROUND, b6, 0, k_amb, 1.0, k_sun, 0.0), b6, lut6) @ LUMA)
            lo, hi = (k_sun, hi) if lit < LIT_ROAD_B6 else (lo, k_sun)
    rows = [("today", look, kit, lut_of(look))]
    if "--was" in sys.argv:
        rows.insert(0, ("batch 6", b6, b6kit, lut6))
    print("fitted to batch 6 (km-cap): shade %.3f, sun %.3f" % (k_amb, k_sun))
    print("%-8s %6s %8s %6s %6s %6s   (luma 0-1; target frame 0.33-0.42, town-a/b 0.42)" % ("", "walls", "backlit", "roofs", "ground", "frame"))
    frames = {}
    for name, lk, kt, lut in rows:
        p = predict(lk, kt, albedo, k_amb, k_sun, lut, bearings)
        frames[name] = p["frame"]
        print("%-8s %6.3f %8.3f %6.3f %6.3f %6.3f" % (name, p["wall"], p["wall_backlit"], p["roof"], p["ground"], p["frame"]))
    # The model's frame reads brighter than a real one (no people, no deep shade under eaves); batch 6's
    # measured frames carried by the ratio are nearer the truth, and an upper bound (luma is not linear).
    b6_frame = predict(b6, b6kit, albedo, k_amb, k_sun, lut6, bearings)["frame"]
    r = frames["today"] / b6_frame
    print("batch 6 measured frame luma: km-cap %.3f, km-d14 %.3f; today by the ratio (x%.2f): %.3f, %.3f" % (FRAMES_B6[0], FRAMES_B6[1], r, FRAMES_B6[0] * r, FRAMES_B6[1] * r))


if __name__ == "__main__":
    main()
