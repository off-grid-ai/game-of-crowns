#!/usr/bin/env python3
"""Cut B, "Every lord remembers", 9:16 (Shorts, TikTok, Reels): writes index.html and compositions/ from the shot list below.

Every panel shot is a real play frame from one run (docs/play/r13-politics and r14-siege, Winter 316 -> Summer 320),
3024 x 1898, moved by a camera: the frame sits in #cam with its top-left at the origin, and a camera
key (cx, cy, s) puts source point (cx, cy) at screen point (sx, sy) at scale s.
World shots are clean, interface-free stills from cinematics.gd (3840 x 2160).
"""
import json, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
W, H = 1080, 1920
PIC = 1380  # the picture window; the caption band below it is charcoal
BRONZE = "#B7A17D"

# ---- shots -------------------------------------------------------------------------------------
# kind "frame": one image moved by camera keys [(t, cx, cy, s, sx, sy, ease)]
# marks: bronze lines drawn on the frame in source pixels (x, y, w, t) or left rules (x, y, h, t)
# lines: on-screen type [(text, t_in)], bronze=words to tint
VEIL = 440  # px of the picture covered from the top, so the houses table above the Hand stays out of shot
SHOTS = [
    dict(id="v1", start=0.0, dur=3.4, img="assets/world/seat_Lionmoor.jpg", iw=3840, ih=2160,
         cam=[(0, 1920, 1100, 0.70, 540, 690, None), (3.4, 1960, 1090, 0.74, 540, 690, "sine.inOut")],
         lines=[("A kingdom where", 0.0), ("every lord remembers", 0.0), ("what you did.", 0.0)], hold_first=True),
    dict(id="v2", start=3.4, dur=4.0, img="assets/play/b05.jpg", iw=3024, ih=1898,
         cam=[(0, 2672, 600, 1.55, 540, 690, None), (4.0, 2672, 600, 1.60, 540, 690, "sine.inOut")],
         rules=[(2356, 255, 125, 0.5)],
         lines=[("One lady left", 0.8), ("court unheard.", 0.9)]),
    dict(id="v3", start=7.4, dur=4.2, img="assets/play/b05.jpg", iw=3024, ih=1898,
         cam=[(0, 450, 1323, 1.20, 540, 720, None), (4.2, 450, 1323, 1.23, 540, 720, "sine.inOut")],
         veil=VEIL, marks=[(328, 1312, 368, 1.0)],
         lines=[("Her house", 1.4), ("didn't forget.", 1.5)]),
    dict(id="v4", start=11.6, dur=3.6, img="assets/play/b05.jpg", iw=3024, ih=1898,
         cam=[(0, 450, 1323, 1.23, 540, 720, None), (3.6, 450, 1323, 1.23, 540, 720, "sine.inOut")],
         veil=VEIL, marks=[(55, 1594, 770, 0.5)],
         lines=[("Then they wanted", 1.0), ("the throne.", 1.1)]),
    dict(id="v5", start=15.2, dur=3.0, img="assets/play/b08.jpg", iw=3024, ih=1898,
         cam=[(0, 2672, 560, 1.55, 540, 690, None), (3.0, 2672, 560, 1.60, 540, 690, "sine.inOut")],
         rules=[(2356, 390, 122, 0.3)],
         lines=[("And they marched.", 0.8)]),
    dict(id="v6", start=18.2, dur=4.4, img="assets/play/b09.jpg", iw=3024, ih=1898,
         cam=[(0, 1700, 790, 1.02, 540, 690, None), (4.4, 1700, 780, 1.06, 540, 690, "sine.inOut")],
         lines=[("She had words", 1.2), ("for the King.", 1.3)]),
    dict(id="v7", start=22.6, dur=4.4, end=True),
]
TOTAL = 27.0

AUDIO = [  # id, file, start, dur, volume, media_start, extra
    ("a-bed", "assets/audio/march.mp3", 0, TOTAL, 0.6, 0, 'data-fade-in="0.3" data-fade-out="2.0"'),
    ("a-page1", "assets/audio/page.mp3", 3.42, 0.43, 0.7, 0, ""),
    ("a-horn", "assets/audio/war_horn.mp3", 15.2, 3.0, 0.35, 0, 'data-fade-out="1.0"'),
    ("a-page2", "assets/audio/page.mp3", 18.22, 0.43, 0.6, 0, ""),
    ("a-seal", "assets/audio/seal.mp3", 22.92, 1.3, 0.7, 0, ""),
]

# ---- writing -----------------------------------------------------------------------------------
STYLE = """
@font-face { font-family:"EB Garamond"; src:url("assets/fonts/EBGaramond.ttf") format("truetype"); font-weight:400 800; }
@font-face { font-family:"Cinzel"; src:url("assets/fonts/Cinzel.ttf") format("truetype"); font-weight:400 900; }
#root { position:absolute; inset:0; overflow:hidden; background:#151719; }
.cam { position:absolute; left:0; top:0; transform-origin:0 0; }
.cam img { position:absolute; left:0; top:0; display:block; }
.mark { position:absolute; height:7px; background:%s; transform-origin:0 50%%; border-radius:2px; }
.rule { position:absolute; width:8px; background:%s; transform-origin:50%% 0; border-radius:2px; }
.shade { position:absolute; left:0; right:0; bottom:0; height:520px;
  background:linear-gradient(180deg, rgba(21,23,25,0) 0%%, rgba(21,23,25,.62) 58%%, rgba(21,23,25,.82) 100%%); }
.pic { position:absolute; left:0; top:0; width:1080px; height:1380px; overflow:hidden; }
.veil { position:absolute; left:0; right:0; top:0; background:linear-gradient(180deg, #151719 0%%, #151719 94%%, rgba(21,23,25,0) 100%%); }
.band { position:absolute; left:0; right:0; top:1380px; bottom:0; background:#151719; }
.lines { position:absolute; left:72px; right:72px; top:1452px; font-family:"EB Garamond", serif; font-weight:500;
  font-size:88px; line-height:1.08; letter-spacing:-0.01em; color:#EFE7D6; text-shadow:0 2px 18px rgba(0,0,0,.45); }
.lines .ln { display:block; }
.lines .w { display:inline-block; }

.top .shade { top:0; bottom:auto; background:linear-gradient(0deg, rgba(21,23,25,0) 0%%, rgba(21,23,25,.62) 58%%, rgba(21,23,25,.82) 100%%); }
.top .lines { bottom:auto; top:96px; }
.top .lines .ln { top:0; bottom:auto; }
.q { color:%s; }
.cursor { position:absolute; left:0; top:0; width:64px; height:64px; z-index:5; }
""" % (BRONZE, BRONZE, BRONZE)


def cam_tweens(sel, keys, ox=0):
    out = []
    for i, (t, cx, cy, s, sx, sy, ease) in enumerate(keys):
        x, y = sx - cx * s, sy - cy * s
        if i == 0:
            out.append(f'tl.set("{sel}", {{ x:{x:.1f}, y:{y:.1f}, scale:{s} }}, {ox + t});')
        else:
            pt = keys[i - 1][0]
            out.append(f'tl.to("{sel}", {{ x:{x:.1f}, y:{y:.1f}, scale:{s}, duration:{t - pt:.2f}, ease:"{ease}" }}, {ox + pt});')
    return out


def lines_html(sh):
    if not sh.get("lines"):
        return "", []
    html, js = [], []
    for li, (text, t) in enumerate(sh["lines"]):
        words = text.split(" ")
        spans = []
        for wi, w in enumerate(words):
            cls = "w"
            if sh.get("final") and wi == len(words) - 1 and w.endswith("?"):
                w = w[:-1] + '<span class="q">?</span>'
            spans.append(f'<span class="w" id="{sh["id"]}l{li}w{wi}">{w}</span>')
        html.append(f'<span class="ln" id="{sh["id"]}l{li}">{" ".join(spans)}</span>')
        hold = sh.get("hold_first") and t == 0
        for wi in range(len(words)):
            sel = f'#{sh["id"]}l{li}w{wi}'
            if hold:
                continue  # on screen at frame 0: the thumbnail
            js.append(f'tl.fromTo("{sel}", {{ opacity:0, y:18 }}, {{ opacity:1, y:0, duration:.5, ease:"power3.out" }}, {t + wi * 0.05:.2f});')
        if sh.get("replace") and li + 1 < len(sh["lines"]):
            nt = sh["lines"][li + 1][1]
            js.append(f'tl.to("#{sh["id"]}l{li}", {{ opacity:0, duration:.25, ease:"power2.in" }}, {nt - 0.3:.2f});')
    css_pos = ""
    if sh.get("replace"):
        # one line at a time, stacked in the same place
        css_pos = f'<style>#{sh["id"]} .lines .ln {{ position:absolute; left:0; bottom:0; }}</style>'
    return css_pos + '<div class="lines">' + "".join(html) + "</div>", js


def frame_html(prefix, img, iw, ih, marks=(), rules=()):
    parts = [f'<div class="cam" id="{prefix}cam" style="width:{iw}px;height:{ih}px"><img src="{img}" alt="" width="{iw}" height="{ih}">']
    for i, (x, y, w, t) in enumerate(marks):
        parts.append(f'<div class="mark" id="{prefix}m{i}" style="left:{x}px;top:{y}px;width:{w}px"></div>')
    for i, (x, y, h, t) in enumerate(rules):
        parts.append(f'<div class="rule" id="{prefix}r{i}" style="left:{x}px;top:{y}px;height:{h}px"></div>')
    parts.append("</div>")
    return "".join(parts)


def mark_tweens(prefix, marks=(), rules=(), ox=0):
    js = []
    for i, (_, _, _, t) in enumerate(marks):
        js.append(f'tl.fromTo("#{prefix}m{i}", {{ scaleX:0 }}, {{ scaleX:1, duration:.45, ease:"power3.out" }}, {ox + t});')
    for i, (_, _, _, t) in enumerate(rules):
        js.append(f'tl.fromTo("#{prefix}r{i}", {{ scaleY:0, opacity:1 }}, {{ scaleY:1, duration:.35, ease:"power3.out" }}, {ox + t});')
        if i + 1 < len(rules):
            js.append(f'tl.to("#{prefix}r{i}", {{ opacity:.0, duration:.3 }}, {ox + rules[i + 1][3]});')
    return js


END_CARD = {"title": "assets/world/title.png", "line": "Free on Apple Silicon.",
            "link": "github.com/off-grid-ai/game-of-crowns"}


def end_scene(sh):
    sid = sh["id"]
    return f"""<template>
  <style>{STYLE}
#{sid}t {{ position:absolute; left:60px; top:640px; width:960px; height:auto; }}
#{sid}l {{ position:absolute; left:0; right:0; top:1010px; text-align:center; font-family:"EB Garamond", serif;
  font-weight:500; font-size:64px; color:#EFE7D6; }}
#{sid}u {{ position:absolute; left:0; right:0; top:1110px; text-align:center; font-family:"EB Garamond", serif;
  font-weight:500; font-size:38px; letter-spacing:.01em; color:{BRONZE}; }}
  </style>
  <div id="root" data-composition-id="{sid}" data-width="{W}" data-height="{H}">
    <img id="{sid}t" src="{END_CARD['title']}" alt="Game of Crowns">
    <div id="{sid}l">{END_CARD['line']}</div>
    <div id="{sid}u">{END_CARD['link']}</div>
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
    tl.fromTo("#{sid}t", {{ clipPath:"inset(0 100% 0 0)", opacity:1 }}, {{ clipPath:"inset(0 0% 0 0)", duration:.9, ease:"power2.inOut" }}, 0.15);
    tl.fromTo("#{sid}l", {{ opacity:0, y:18 }}, {{ opacity:1, y:0, duration:.5, ease:"power3.out" }}, 1.05);
    tl.fromTo("#{sid}u", {{ opacity:0, y:14 }}, {{ opacity:1, y:0, duration:.5, ease:"power3.out" }}, 1.35);
    tl.set({{}}, {{}}, {sh["dur"]});
    window.__timelines["{sid}"] = tl;
  </script>
</template>
"""


def scene(sh):
    if sh.get("end"):
        return end_scene(sh)
    sid = sh["id"]
    body, js = [], []
    if sh.get("flip"):
        body.append(f'<div class="cam" id="{sid}cam" style="width:{sh["iw"]}px;height:{sh["ih"]}px">')
        for i, f in enumerate(sh["flip"]):
            body.append(f'<img id="{sid}f{i}" src="assets/play/{f}.jpg" alt="" width="{sh["iw"]}" height="{sh["ih"]}" style="opacity:{1 if i == 0 else 0}">')
        body.append("</div>")
        step = sh["dur"] / len(sh["flip"])
        for i in range(1, len(sh["flip"])):
            js.append(f'tl.set("#{sid}f{i}", {{ opacity:1 }}, {i * step:.2f});')
        js += cam_tweens(f"#{sid}cam", sh["cam"])
    else:
        body.append(frame_html(sid, sh["img"], sh["iw"], sh["ih"], sh.get("marks", ()), sh.get("rules", ())))
        js += cam_tweens(f"#{sid}cam", sh["cam"])
        js += mark_tweens(sid, sh.get("marks", ()), sh.get("rules", ()))
    if sh.get("cut"):
        c = sh["cut"]
        body.append(f'<div id="{sid}b" style="position:absolute;inset:0;opacity:0">'
                    + frame_html(sid + "b", c["img"], sh["iw"], sh["ih"], c.get("marks", ())) + "</div>")
        js.append(f'tl.set("#{sid}b", {{ opacity:1 }}, {c["at"]});')
        js += cam_tweens(f"#{sid}bcam", c["cam"], ox=c["at"])
        js += mark_tweens(sid + "b", c.get("marks", ()), ox=c["at"])
    if sh.get("cursor"):
        (t0, x0, y0), (t1, x1, y1) = sh["cursor"]
        k = sh["cam"]
        # cursor points are in source pixels of the first frame; convert with the camera at that moment
        def to_screen(t, x, y):
            # linear between the two camera keys is close enough for a pointer that lands at the end
            _, cx, cy, s, sx, sy, _ = k[0] if t <= k[0][0] else k[-1] if t >= k[-1][0] else k[0]
            if k[0][0] < t < k[-1][0]:
                a = (t - k[0][0]) / (k[-1][0] - k[0][0])
                a = a * a * (3 - 2 * a)
                c0, c1 = k[0], k[-1]
                cx = c0[1] + (c1[1] - c0[1]) * a; cy = c0[2] + (c1[2] - c0[2]) * a
                s = c0[3] + (c1[3] - c0[3]) * a; sx, sy = c0[4], c0[5]
            return sx + (x - cx) * s, sy + (y - cy) * s
        ax, ay = to_screen(t0, x0, y0)
        bx, by = to_screen(t1, x1, y1)
        body.append(f'<div class="cursor" id="{sid}cur"><svg viewBox="0 0 24 24" width="64" height="64">'
                    '<path d="M5 3l14 8-6.2 1.6L10 19z" fill="#EFE7D6" stroke="#151719" stroke-width="1.4" stroke-linejoin="round"/></svg></div>')
        js.append(f'tl.fromTo("#{sid}cur", {{ x:{ax:.0f}, y:{ay:.0f}, opacity:0 }}, {{ x:{bx:.0f}, y:{by:.0f}, opacity:1, duration:{t1 - t0:.2f}, ease:"power3.out" }}, {t0});')
        p = sh["press"]
        js.append(f'tl.to("#{sid}cur", {{ scale:.86, duration:.08 }}, {p});')
        js.append(f'tl.to("#{sid}cur", {{ scale:1, duration:.25, ease:"back.out(2)" }}, {p + 0.08});')
        js.append(f'tl.to("#{sid}cur", {{ opacity:0, duration:.01 }}, {sh["cut"]["at"]});')
    veil = f'<div class="veil" style="height:{sh["veil"]}px"></div>' if sh.get("veil") else ""
    body.insert(0, '<div class="pic">')
    body.append(veil + '</div><div class="band"></div>')
    lh, ljs = lines_html(sh)
    body.append(lh)
    js += ljs
    cls = ' class="final"' if sh.get("final") else ' class="top"' if sh.get("top") else ""
    return f"""<template>
  <style>{STYLE}</style>
  <div id="root" data-composition-id="{sid}" data-width="{W}" data-height="{H}"><div id="{sid}"{cls} style="position:absolute;inset:0">
    {"".join(body)}
  </div></div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
    {chr(10).join("    " + j for j in js).strip()}
    tl.set({{}}, {{}}, {sh["dur"]});
    window.__timelines["{sid}"] = tl;
  </script>
</template>
"""


def main():
    comp = ROOT / "compositions"
    comp.mkdir(exist_ok=True)
    hosts = []
    for i, sh in enumerate(SHOTS):
        (comp / f'{sh["id"]}.html').write_text(scene(sh))
        hosts.append(f'      <div id="h-{sh["id"]}" data-composition-id="{sh["id"]}" data-composition-src="compositions/{sh["id"]}.html" '
                     f'data-start="{sh["start"]:.2f}" data-duration="{sh["dur"]:.2f}" data-track-index="{i % 2}" data-track-kind="graphics" '
                     f'data-width="{W}" data-height="{H}" style="z-index:{i + 1}"></div>')
    audio = [f'      <audio id="{a}" class="clip" src="{f}" data-start="{s:.2f}" data-duration="{d:.2f}" data-volume="{v}" '
             f'data-media-start="{m}" data-track-index="{10 + i}" {x}></audio>' for i, (a, f, s, d, v, m, x) in enumerate(AUDIO)]
    (ROOT / "index.html").write_text(f"""<!doctype html>
<html lang="en" data-resolution="portrait">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width={W}, height={H}" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
    <style>
      * {{ margin:0; padding:0; box-sizing:border-box; }}
      html, body {{ margin:0; width:{W}px; height:{H}px; overflow:hidden; background:#151719; }}
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="{TOTAL}" data-width="{W}" data-height="{H}">
{chr(10).join(hosts)}
{chr(10).join(audio)}
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({{ paused: true }});
    </script>
  </body>
</html>
""")
    print("wrote", len(SHOTS), "scenes,", TOTAL, "s")


if __name__ == "__main__":
    main()
