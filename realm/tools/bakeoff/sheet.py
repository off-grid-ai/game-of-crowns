"""Bake-off sheet: rows = sources, columns = house | keep | trees | target crop.
   python3 sheet.py <bakeoff dir>   (renders in <dir>/renders/<cell>.png; previews in <dir>/storeprev; concepts in <dir>/concepts)
Needs Pillow. A missing cell is drawn as 'not rendered'."""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageOps

D = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
TARGET = os.path.join(REPO, "docs/art/target/01-town.jpg")
W, H, LW = 520, 390, 300
CROPS = {"house": (140, 640, 520, 925), "keep": (1180, 0, 1920, 555), "trees": (0, 590, 400, 1000)}

def r(p): return os.path.join(D, "renders", p)
def sp(p): return os.path.join(D, "storeprev", p)
def c(p): return os.path.join(D, "concepts", p)

ROWS = [
    ("TARGET 01-town.jpg (crops)", None),
    ("A  Quaternius kit (have, $0)\nkeep = castle_builder WIP", [r("a_house.png"), r("a_keep.png"), r("a_trees.png")]),
    ("Today: Sketchfab pack ($0)", [r("pack_house.png"), r("pack_keep.png"), r("pack_trees.png")]),
    ("B  EnesKececi Village+Castle\n(Fab, ~$146 + ~$93) store", [sp("enes-stylized-medieval-village.jpg"), sp("enes-stylized-medieval-castle.jpg"), None]),
    ("B  Other Ocean $35 + Red panda\ncastle $35 (Unity) store", [sp("otherocean-fantasy-modular-env.jpg"), sp("handpainted-castle-pack.jpg"), None]),
    ("C  Codex concept (2D input)", [c("house.png"), c("keep.png"), c("trees.png")]),
    ("C  TRELLIS 3D (free HF Space)", [r("ai_trellis_house.png"), r("ai_trellis_keep.png"), r("ai_trellis_trees.png")]),
    ("C  Hunyuan3D-2 (free HF Space)", [r("ai_hunyuan_house.png"), r("ai_hunyuan_keep.png"), r("ai_hunyuan_trees.png")]),
]
try:
    F = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
    FS = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 18)
except Exception:
    F = FS = ImageFont.load_default()

tgt = Image.open(TARGET).convert("RGB")
crops = [ImageOps.fit(tgt.crop(CROPS[k]), (W, H)) for k in ("house", "keep", "trees")]
sheet = Image.new("RGB", (LW + 4 * W + 50, 60 + len(ROWS) * (H + 10)), (24, 24, 28))
d = ImageDraw.Draw(sheet)
for i, h in enumerate(["house", "keep (castle)", "trees", "target crop (house)"]):
    d.text((LW + i * (W + 10) + 10, 18), h, fill=(240, 230, 200), font=F)
for ri, (label, cells) in enumerate(ROWS):
    y = 60 + ri * (H + 10)
    d.multiline_text((12, y + 12), label, fill=(240, 230, 200), font=FS, spacing=6)
    imgs = crops if cells is None else cells
    for ci in range(3):
        x = LW + ci * (W + 10)
        im = imgs[ci]
        if isinstance(im, str):
            im = Image.open(im).convert("RGB") if os.path.exists(im) else None
        if im is None:
            d.rectangle((x, y, x + W, y + H), outline=(80, 80, 80))
            d.text((x + 20, y + H // 2), "not rendered / n.a.", fill=(120, 120, 120), font=FS)
        else:
            sheet.paste(ImageOps.fit(im, (W, H)), (x, y))
    sheet.paste(crops[0] if cells is None else ImageOps.fit(tgt, (W, H)), (LW + 3 * (W + 10), y))
out = os.path.join(D, "bakeoff.jpg")
sheet.save(out, quality=88)
print(out)
