"""Concept catalogue sheet: every concept PNG in a folder as a labelled grid, by group.
   python3 concept_sheet.py <concepts dir> [out.jpg]   (needs Pillow)"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

D = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(D, "concepts.jpg")
GROUPS = [
    ("Buildings", ["house", "townhouse_2", "townhouse_3", "cottage", "cottage_2", "cottage_3", "farmhouse_barn",
                   "inn", "church", "mill", "watermill", "granary", "forge", "armoury", "barracks", "stables",
                   "guard_tower", "gatehouse", "keep", "manor", "market_stall"]),
    ("Animals", ["cow", "ox", "horse", "pig", "sheep", "goat", "chicken", "dog"]),
    ("Farm", ["haystack", "pen", "well", "cart", "wagon", "crops", "trees"]),
    ("Props", ["barrels", "crates", "banner_pole", "anvil", "weapon_rack"]),
]
CELL, COLS, PAD, HEAD = 300, 7, 8, 44
try:
    F = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 26)
    FS = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 18)
except OSError:
    F = FS = ImageFont.load_default()

known = {n for _, ns in GROUPS for n in ns}
extra = sorted(f[:-4] for f in os.listdir(D) if f.endswith(".png") and f[:-4] not in known)
groups = GROUPS + ([("Other", extra)] if extra else [])
rows = sum(HEAD + -(-len(ns) // COLS) * (CELL + 30) for _, ns in groups)
sheet = Image.new("RGB", (COLS * (CELL + PAD) + PAD, rows + PAD), (24, 24, 28))
d = ImageDraw.Draw(sheet)
y = PAD
for title, names in groups:
    d.text((PAD, y + 8), title, fill=(240, 230, 200), font=F)
    y += HEAD
    for i, n in enumerate(names):
        x = PAD + (i % COLS) * (CELL + PAD)
        yy = y + (i // COLS) * (CELL + 30)
        p = os.path.join(D, n + ".png")
        if os.path.exists(p):
            sheet.paste(Image.open(p).convert("RGB").resize((CELL, CELL)), (x, yy))
        else:
            d.rectangle((x, yy, x + CELL, yy + CELL), outline=(80, 80, 80))
            d.text((x + 12, yy + CELL // 2), "pending", fill=(120, 120, 120), font=FS)
        d.text((x + 4, yy + CELL + 4), n, fill=(220, 220, 220), font=FS)
    y += -(-len(names) // COLS) * (CELL + 30)
sheet.save(OUT, quality=88)
print(OUT)
