"""The Warcraft III look's colour grade (Mac: 'Warcraft 3 is exactly what we want'; realm/data/look.json lut):
colour pushed richer, the mids a touch brighter, shadows clean and cool, greens kept vivid. Writes
assets/grade/bold.png in golden-hour.png's layout (33 tiles: red across, green down, blue by tile).
Run once: python3 make_bold_lut.py (its .import mirrors storybook.png's: a 3D texture, 33 slices)."""
import os
import numpy as np
import cv2

N = 33
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "grade", "bold.png")
r, g, b = np.meshgrid(np.linspace(0, 1, N), np.linspace(0, 1, N), np.linspace(0, 1, N), indexing="xy")
c = np.stack([r, g, b], axis=-1)
lum = (c @ np.array([0.2126, 0.7152, 0.0722]))[..., None]
c = lum + (c - lum) * 1.18                       # richer colour (WC3's saturated palette)
mids = 4 * lum * (1 - lum)
c = c + mids * 0.03                               # mids a touch brighter: readable at the RTS camera
c = c + (1 - lum) ** 3 * 0.035 * np.array([-0.3, 0.0, 1.0])  # clean, cool shadows
c = np.clip(c, 0, 1)
img = np.concatenate([c[:, :, k, :] for k in range(N)], axis=1)
cv2.imwrite(OUT, (img[:, :, ::-1] * 255 + 0.5).astype(np.uint8))
print(OUT)
