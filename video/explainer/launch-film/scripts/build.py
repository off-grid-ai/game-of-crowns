#!/usr/bin/env python3
"""The 0.5 launch film: Mac's final copy over the Codex paintings, with the game's own court as proof.

  python3 scripts/build.py          # 16:9, 1920 x 1080
  python3 scripts/build.py --v      # 9:16, 1080 x 1920 (the paintings' vertical exports)

Every shot is a picture moved by a slow camera: a key (t, cx, cy, s) puts source point (cx, cy) at the centre of
the frame at scale s. Shots overlap by XF seconds and the later one dissolves in over the earlier.
The words are Mac's copy, exactly; Gareth's are the game's.
"""
import sys, pathlib

V = "--v" in sys.argv
ROOT = pathlib.Path(__file__).resolve().parent.parent
W, H = (1080, 1920) if V else (1920, 1080)
XF = 0.7          # dissolve
BRONZE = "#B7A17D"
INK = "#F1EADB"

def art(name):  # the vertical export where there is one
    return (f"assets/v/{name}.png", 1080, 1920) if V and name.startswith("launch_") else \
           (f"assets/art/{name}.png" if name.startswith("launch_") else f"assets/art/{name}", 1920, 1080) if name.startswith("launch_") else None

# id, picture, (w, h), duration, camera keys [(t, cx, cy, s)], words [(text, t_in, style)]
def P(name):
    if name.startswith("launch_"):
        return (f"assets/v/{name}.png", 1080, 1920) if V else (f"assets/art/{name}.png", 1920, 1080)
    return {"house_crown": ("assets/art/house_crown.jpg", 1920, 1080),
            "throne": ("assets/art/throne.jpg", 1600, 900),
            "court": ("assets/ui/court.jpg", 2000, 1255)}[name]

def fit(w, h):  # the scale that just covers the frame
    return max(W / w, H / h)

SHOTS = []
def shot(id, name, dur, keys, words=()):
    src, w, h = P(name)
    f = fit(w, h)
    SHOTS.append(dict(id=id, src=src, w=w, h=h, dur=dur,
                      keys=[(t, cx, cy, s * f) for (t, cx, cy, s) in keys], words=list(words)))

if not V:
    shot("g", "launch_gareth_hall", 4.8, [(0, 960, 520, 1.0), (4.8, 940, 400, 1.14)],
         [("“Ten years ago, you took our enemy’s side in war.", -1, "q"), ("House Thornvale has not forgotten it.”", 1.6, "q")])
    shot("w", "launch_war_315", 2.6, [(0, 1100, 470, 1.05), (2.6, 1140, 440, 1.14)])
    shot("o", "launch_boy_orchard", 2.8, [(0, 960, 600, 1.0), (2.8, 960, 680, 1.32)])
    shot("k", "launch_king_throne", 3.0, [(0, 960, 540, 1.0), (3.0, 900, 470, 1.1)],
         [("You’re the king,", 0.4, "")])
    shot("r", "launch_gathering", 3.4, [(0, 960, 520, 1.03), (3.4, 1060, 520, 1.12)],
         [("and seven great houses want your throne.", 0.3, "")])
    shot("n", "launch_grain_gold", 3.6, [(0, 960, 540, 1.0), (3.6, 930, 510, 1.1)],
         [("All you’ve got to hold onto it is grain, gold", 0.4, "")])
    shot("c", "court", 3.4, [(0, 1125, 380, 1.55), (3.4, 1125, 400, 1.63)],
         [("and your word at court.", 0.3, "")])
    shot("a", "launch_fate_golden", 3.8, [(0, 960, 540, 1.0), (3.8, 900, 500, 1.08)],
         [("Rule well and history calls you the Golden.", 0.4, "")])
    shot("b", "launch_fate_bloody", 3.6, [(0, 900, 500, 1.08), (3.6, 860, 480, 1.16)],
         [("Mess it up and you’re the Bloody,", 0.6, "")])
    shot("d", "launch_fate_deposed", 3.8, [(0, 960, 540, 1.0), (3.8, 940, 600, 1.16)],
         [("or worse, the Deposed.", 0.5, "")])
else:
    shot("g", "launch_gareth_hall", 4.8, [(0, 540, 900, 1.0), (4.8, 540, 760, 1.12)],
         [("“Ten years ago,", -1, "q"), ("you took our enemy’s", -1, "q"), ("side in war.”", -1, "q")])
    shot("w", "launch_war_315", 2.6, [(0, 540, 900, 1.02), (2.6, 540, 860, 1.12)])
    shot("o", "launch_boy_orchard", 2.8, [(0, 540, 1000, 1.0), (2.8, 540, 1040, 1.22)])
    shot("k", "launch_king_throne", 3.0, [(0, 540, 960, 1.0), (3.0, 540, 900, 1.08)],
         [("You’re the king,", 0.4, "")])
    shot("r", "launch_gathering", 3.4, [(0, 540, 960, 1.02), (3.4, 560, 940, 1.1)],
         [("and seven great houses", 0.3, ""), ("want your throne.", 0.3, "")])
    shot("n", "launch_grain_gold", 3.6, [(0, 540, 960, 1.0), (3.6, 540, 920, 1.08)],
         [("All you’ve got to hold onto it", 0.4, ""), ("is grain, gold", 0.4, "")])
    shot("c", "court", 3.4, [(0, 1125, 420, 1.0), (3.4, 1125, 420, 1.05)],
         [("and your word at court.", 0.3, "")])
    shot("a", "launch_fate_golden", 3.8, [(0, 540, 960, 1.0), (3.8, 540, 920, 1.06)],
         [("Rule well and history", 0.4, ""), ("calls you the Golden.", 0.4, "")])
    shot("b", "launch_fate_bloody", 3.6, [(0, 540, 920, 1.06), (3.6, 540, 900, 1.12)],
         [("Mess it up and", 0.6, ""), ("you’re the Bloody,", 0.6, "")])
    shot("d", "launch_fate_deposed", 3.8, [(0, 540, 960, 1.0), (3.8, 540, 1000, 1.1)],
         [("or worse, the Deposed.", 0.5, "")])
END = 5.5
END_BG = P("launch_kingsmere_dusk")

# ---- writing ------------------------------------------------------------------------------------
LINE_PX = 66 if not V else 74
STYLE = f"""
@font-face {{ font-family:"EB Garamond"; src:url("assets/fonts/EBGaramond.ttf") format("truetype"); font-weight:400 800; }}
@font-face {{ font-family:"Cinzel"; src:url("assets/fonts/Cinzel.ttf") format("truetype"); font-weight:400 900; }}
#root {{ position:absolute; inset:0; overflow:hidden; background:transparent; }}
.in {{ position:absolute; inset:0; opacity:1; }}
.cam {{ position:absolute; left:0; top:0; transform-origin:0 0; }}
.cam img {{ position:absolute; left:0; top:0; display:block; }}
.shade {{ position:absolute; left:0; right:0; bottom:0; height:{'46%' if not V else '40%'};
  background:linear-gradient(180deg, rgba(10,11,12,0) 0%, rgba(10,11,12,.55) 55%, rgba(10,11,12,.78) 100%); }}
.words {{ position:absolute; left:{'8%' if not V else '7%'}; right:{'8%' if not V else '7%'}; bottom:{'11%' if not V else '13%'};
  text-align:center; font-family:"EB Garamond", serif; font-weight:500; font-size:{LINE_PX}px; line-height:1.18;
  letter-spacing:.005em; color:{INK}; text-shadow:0 2px 24px rgba(0,0,0,.55); }}
.words .ln {{ display:block; }}
.words .q {{ font-style:italic; }}
"""

def cam_js(sel, keys, w, h):
    out = []
    keys = [(t, min(max(cx, W / (2 * s)), w - W / (2 * s)), min(max(cy, H / (2 * s)), h - H / (2 * s)), s) for (t, cx, cy, s) in keys]
    for i, (t, cx, cy, s) in enumerate(keys):
        x, y = W / 2 - cx * s, H / 2 - cy * s
        if i == 0:
            out.append(f'tl.set("{sel}", {{ x:{x:.1f}, y:{y:.1f}, scale:{s:.4f} }}, 0);')
        else:
            pt = keys[i - 1][0]
            out.append(f'tl.to("{sel}", {{ x:{x:.1f}, y:{y:.1f}, scale:{s:.4f}, duration:{t - pt:.2f}, ease:"sine.inOut" }}, {pt});')
    return out

def scene(sh, first):
    sid = sh["id"]
    lines, js = [], []
    for i, (text, t, st) in enumerate(sh["words"]):
        lines.append(f'<span class="ln {st}" id="{sid}w{i}">{text}</span>')
        if t >= 0:
            js.append(f'tl.fromTo("#{sid}w{i}", {{ opacity:0, y:10 }}, {{ opacity:1, y:0, duration:.9, ease:"power2.out" }}, {t});')
    if not first:
        js.insert(0, f'tl.fromTo("#{sid}in", {{ opacity:0 }}, {{ opacity:1, duration:{XF}, ease:"sine.inOut" }}, 0);')
    js += cam_js(f"#{sid}cam", sh["keys"], sh["w"], sh["h"])
    deep = ' style="background:linear-gradient(180deg, rgba(10,11,12,0) 0%, rgba(10,11,12,.86) 40%, rgba(10,11,12,.94) 100%)"' if sh["id"] == "c" else ""
    words = f'<div class="shade"{deep}></div><div class="words">{"".join(lines)}</div>' if lines else ""
    return f"""<template>
  <style>{STYLE}</style>
  <div id="root" data-composition-id="{sid}" data-width="{W}" data-height="{H}">
    <div class="in" id="{sid}in">
      <div class="cam" id="{sid}cam" style="width:{sh['w']}px;height:{sh['h']}px"><img src="{sh['src']}" alt="" width="{sh['w']}" height="{sh['h']}"></div>
      {words}
    </div>
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
    {chr(10).join('    ' + j for j in js).strip()}
    tl.set({{}}, {{}}, {sh['dur']});
    window.__timelines["{sid}"] = tl;
  </script>
</template>
"""

def end_scene(dur):
    src, w, h = END_BG
    f = fit(w, h)
    cx, cy = w / 2, h / 2
    s0, s1 = f * 1.04, f * 1.10
    hook_px, sub_px, link_px = (92, 40, 30) if not V else (80, 40, 30)
    top = 0.13 if not V else 0.20
    return f"""<template>
  <style>{STYLE}
#e .seal {{ position:absolute; left:50%; top:{top*100:.0f}%; width:{110 if not V else 150}px; height:{110 if not V else 150}px; margin-left:-{55 if not V else 75}px; }}
#e .hook {{ position:absolute; left:6%; right:6%; top:{(top+0.15)*100:.0f}%; text-align:center; font-family:"EB Garamond", serif;
  font-weight:500; font-size:{hook_px}px; line-height:1.1; color:{INK}; text-shadow:0 2px 30px rgba(0,0,0,.6); }}
#e .sub {{ position:absolute; left:0; right:0; top:{(top+0.15)*100 + (13 if not V else 13):.0f}%; text-align:center; font-family:"EB Garamond", serif;
  font-weight:500; font-size:{sub_px}px; color:{INK}; opacity:.92; }}
#e .link {{ position:absolute; left:0; right:0; top:{(top+0.15)*100 + (19 if not V else 17):.0f}%; text-align:center; font-family:"EB Garamond", serif;
  font-size:{link_px}px; letter-spacing:.02em; color:{BRONZE}; }}
#e .veil {{ position:absolute; inset:0; background:radial-gradient(ellipse at 50% {top*100+12:.0f}%, rgba(8,9,11,.55), rgba(8,9,11,.15) 70%); }}
  </style>
  <div id="root" data-composition-id="e" data-width="{W}" data-height="{H}">
    <div class="in" id="ein"><div id="e">
      <div class="cam" id="ecam" style="width:{w}px;height:{h}px"><img src="{src}" alt="" width="{w}" height="{h}"></div>
      <div class="veil"></div>
      <img class="seal" id="eseal" src="assets/ui/seal.png" alt="Off Grid AI">
      <div class="hook" id="ehook">Find out what kind of king you’d be.</div>
      <div class="sub" id="esub">Free on any Apple Silicon Mac.</div>
      <div class="link" id="elink">alichherawalla.itch.io/game-of-crowns</div>
    </div></div>
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
    tl.fromTo("#ein", {{ opacity:0 }}, {{ opacity:1, duration:{XF}, ease:"sine.inOut" }}, 0);
    tl.set("#ecam", {{ x:{W/2 - cx*s0:.1f}, y:{H/2 - cy*s0:.1f}, scale:{s0:.4f} }}, 0);
    tl.to("#ecam", {{ x:{W/2 - cx*s1:.1f}, y:{H/2 - cy*s1:.1f}, scale:{s1:.4f}, duration:{dur}, ease:"sine.inOut" }}, 0);
    tl.fromTo("#eseal", {{ opacity:0, scale:.94 }}, {{ opacity:1, scale:1, duration:1.0, ease:"power2.out" }}, 0.5);
    tl.fromTo("#ehook", {{ opacity:0, y:12 }}, {{ opacity:1, y:0, duration:1.1, ease:"power2.out" }}, 0.9);
    tl.fromTo("#esub", {{ opacity:0 }}, {{ opacity:1, duration:.9 }}, 1.9);
    tl.fromTo("#elink", {{ opacity:0 }}, {{ opacity:1, duration:.9 }}, 2.3);
    tl.set({{}}, {{}}, {dur});
    window.__timelines["e"] = tl;
  </script>
</template>
"""

def main():
    comp = ROOT / ("compositions-v" if V else "compositions")
    comp.mkdir(exist_ok=True)
    hosts, t = [], 0.0
    for i, sh in enumerate(SHOTS):
        (comp / f"{sh['id']}.html").write_text(scene(sh, i == 0))
        hosts.append((sh["id"], t, sh["dur"]))
        t += sh["dur"] - XF
    (comp / "e.html").write_text(end_scene(END))
    hosts.append(("e", t, END))
    total = round(t + END, 2)
    H_ = [f'      <div id="h-{id}" data-composition-id="{id}" data-composition-src="{comp.name}/{id}.html" data-start="{s:.2f}" '
          f'data-duration="{d:.2f}" data-track-index="{i % 2}" data-track-kind="graphics" data-width="{W}" data-height="{H}" '
          f'style="z-index:{i + 1}"></div>' for i, (id, s, d) in enumerate(hosts)]
    audio = [
        f'      <audio id="a-bed" class="clip" src="assets/audio/bed.mp3" data-start="0" data-duration="{total}" data-volume="0.7" data-media-start="0" data-fade-in="0.4" data-fade-out="2.5" data-track-index="10"></audio>',
        f'      <audio id="a-bell" class="clip" src="assets/audio/toll_bell.mp3" data-start="0.2" data-duration="3.5" data-volume="0.3" data-media-start="0" data-fade-out="1.5" data-track-index="11"></audio>',
        f'      <audio id="a-seal" class="clip" src="assets/audio/seal.mp3" data-start="{hosts[-1][1] + 0.55:.2f}" data-duration="1.3" data-volume="0.6" data-media-start="0" data-track-index="12"></audio>',
    ]
    out = ROOT / ("index-v.html" if V else "index.html")
    out.write_text(f"""<!doctype html>
<html lang="en" data-resolution="{'portrait' if V else 'landscape'}">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width={W}, height={H}" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
    <style>* {{ margin:0; padding:0; box-sizing:border-box; }} html, body {{ margin:0; width:{W}px; height:{H}px; overflow:hidden; background:#0f1113; }}</style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="{total}" data-width="{W}" data-height="{H}">
{chr(10).join(H_)}
{chr(10).join(audio)}
    </div>
    <script>window.__timelines["main"] = gsap.timeline({{ paused: true }});</script>
  </body>
</html>
""")
    print("wrote", out.name, len(hosts), "scenes,", total, "s")

if __name__ == "__main__":
    main()
