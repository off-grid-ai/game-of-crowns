"""The one look's colour grade (realm/data/look.json lut; art-direction-report.md: lifted warm
mid-tones, slightly quieter greens, cool shadows). Writes assets/grade/storybook.png, a 33x33x33 LUT as
33 tiles side by side (red across a tile, green down it, blue by tile: the layout golden-hour.png uses,
imported as a 3D texture with 33 horizontal slices). Run once: python3 make_storybook_lut.py."""
import os
import numpy as np
import cv2

N = 33
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "grade", "storybook.png")

r, g, b = np.meshgrid(np.linspace(0, 1, N), np.linspace(0, 1, N), np.linspace(0, 1, N), indexing="xy")  # r across, g down, b by tile
c = np.stack([r, g, b], axis=-1)
lum = (c @ np.array([0.2126, 0.7152, 0.0722]))[..., None]
mids = 4 * lum * (1 - lum)
c = c + mids * 0.035 * np.array([1.0, 0.7, 0.25])            # lift the mid-tones, warm
green = np.clip((c[..., 1:2] - np.maximum(c[..., 0:1], c[..., 2:3])) * 3, 0, 1)
c = c + (lum - c) * 0.22 * green                              # greens a little quieter (olive, sage)
c = c + (1 - lum) ** 2 * 0.03 * np.array([-0.4, 0.0, 1.0])   # shadows a touch cool
c = np.clip(c, 0, 1)
tiles = [c[:, :, k, :] for k in range(N)]                     # blue = tile index
img = np.concatenate(tiles, axis=1)
cv2.imwrite(OUT, (img[:, :, ::-1] * 255 + 0.5).astype(np.uint8))
print(OUT, img.shape)
