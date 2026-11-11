"""Cuts the flat light-grey background out of concept PNGs (flood fill from the border), so TRELLIS
gets an RGBA image and needs no background-removal model.
   python3 cutout.py <in.png> <out.png>   (needs Pillow + numpy)"""
import sys
from collections import deque

import numpy as np
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
im = np.asarray(Image.open(src).convert("RGB")).astype(np.int16)
h, w, _ = im.shape
border = np.concatenate([im[0], im[-1], im[:, 0], im[:, -1]])
bg = np.median(border, axis=0)
near = np.abs(im - bg).max(axis=2) < 22          # background-like pixels
grey = (im.max(axis=2) - im.min(axis=2)) < 14     # neutral (the backdrop and its soft shadow)
cand = near | (grey & (np.abs(im - bg).max(axis=2) < 60))
seen = np.zeros((h, w), bool)
q = deque((y, x) for y in range(h) for x in (0, w - 1) if cand[y, x])
q.extend((y, x) for x in range(w) for y in (0, h - 1) if cand[y, x])
for y, x in q:
    seen[y, x] = True
while q:
    y, x = q.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not seen[ny, nx]:
            seen[ny, nx] = True
            q.append((ny, nx))
alpha = np.where(seen, 0, 255).astype(np.uint8)
rgba = np.dstack([im.astype(np.uint8), alpha])
Image.fromarray(rgba, "RGBA").save(out)
print(out, f"{(alpha > 0).mean():.0%} kept")
