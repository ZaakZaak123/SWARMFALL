# Card textures (white, tintable): radial glow and a hex-cell pattern for the card art panel.
import math
import numpy as np
from PIL import Image

out = "build/icons/"
N = 256
y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
r = np.sqrt(x * x + y * y)
a = np.clip(1 - r, 0, 1) ** 2.2
img = np.dstack([np.full_like(a, 255), np.full_like(a, 255), np.full_like(a, 255), a * 255]).astype(np.uint8)
Image.fromarray(img, "RGBA").save(out + "glow.png")

# hex cells: thin bright edges, fading towards the bottom so the icon area reads
W, H = 512, 256
yy, xx = np.mgrid[0:H, 0:W].astype(float)
s = 20.0  # hex circumradius, pointy-top
cw, ch = s * math.sqrt(3), s * 1.5
best = np.full(xx.shape, 9.0)
for oy in (-1, 0, 1):
    row = np.floor(yy / ch) + oy
    off = np.where(row % 2 == 0, 0, cw / 2)
    for ox in (-1, 0, 1):
        col = np.floor((xx - off) / cw) + ox
        x0, y0 = col * cw + off + cw / 2, row * ch + s
        ax, ay = abs(xx - x0), abs(yy - y0)
        n = np.maximum(ax, ax / 2 + ay * math.sqrt(3) / 2) / (s * math.sqrt(3) / 2)
        best = np.minimum(best, n)
edge = np.clip((best - 0.86) / 0.08, 0, 1) * 0.85
fade = np.clip(1 - yy / H, 0, 1) ** 1.3
alpha = edge * fade * 255
img = np.dstack([np.full_like(alpha, 255)] * 3 + [alpha]).astype(np.uint8)
Image.fromarray(img, "RGBA").save(out + "hex.png")
print("ok")
