# SPOREFALL combat FX textures (DD-050). Procedural, deterministic. Output: build/fx/*.png
#   fire_fb.png   4x4 flipbook, coloured fireball: white-hot core -> orange -> dark red edge -> smoke
#   blast_fb.png  4x4 flipbook, greyscale energy burst (tinted by the particle colour)
#   smoke_fb.png  4x4 flipbook, soft turbulent puff growing and thinning
#   spark.png     long thin streak (VelocityParallel particles)
#   glow.png      soft dot
#   ring.png      thin shockwave ring with a soft inner trail
#   splat.png     irregular goo splat with droplets (white, tinted by Decal.Color3)
#   scorch.png    dark burn mark with a ragged edge
#   goo.png       glossy droplet
#   gem.png       not used (gems are meshes)
# Usage: python -I tools/fx/fx_tex.py
import math
import os

import numpy as np
from PIL import Image

OUT = "build/fx"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def value_noise(n, cells, seed):
    r = np.random.default_rng(seed)
    g = r.random((cells + 1, cells + 1))
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    t = np.linspace(0, cells, n, endpoint=False)
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    a = g[i][:, i]
    b = g[i + 1][:, i]
    c = g[i][:, i + 1]
    d = g[i + 1][:, i + 1]
    fy = f[:, None]
    fx = f[None, :]
    return (a * (1 - fy) + b * fy) * (1 - fx) + (c * (1 - fy) + d * fy) * fx


def fbm(n, seed, octaves=5, base=4):
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(n, base * 2**o, seed + o * 31) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def save(name, rgba):
    Image.fromarray(np.clip(rgba * 255, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))


def grid(n):
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    return x, y, np.sqrt(x * x + y * y), np.arctan2(y, x)


def flipbook(frames):
    n = frames[0].shape[0]
    sheet = np.zeros((n * 4, n * 4, 4))
    for i, f in enumerate(frames):
        r, c = divmod(i, 4)
        sheet[r * n : (r + 1) * n, c * n : (c + 1) * n] = f
    return sheet


N = 256
X, Y, R, A = grid(N)

# --- fireball (coloured) -------------------------------------------------------------------------
fire_frames = []
for i in range(16):
    t = i / 15
    turb = fbm(N, 100 + i, 5, 3)
    radius = 0.55 + 0.4 * (1 - (1 - t) ** 2)
    edge = radius * (0.8 + 0.5 * (turb - 0.5))
    d = R / np.maximum(edge, 1e-3)
    body = np.clip((1 - d) * 2.2, 0, 1)
    heat = np.clip((1 - d * (0.7 + t * 1.8)) * (1 - t * 0.9) * 1.3 + (turb - 0.5) * 0.5, 0, 1)
    # colour ramp by heat: smoke -> dark red -> orange -> yellow -> white
    stops = np.array([[0.16, 0.13, 0.14], [0.55, 0.12, 0.05], [1.0, 0.45, 0.08], [1.0, 0.82, 0.35], [1.0, 1.0, 0.92]])
    h = heat * 4
    k = np.clip(h.astype(int), 0, 3)
    f = (h - k)[..., None]
    col = stops[k] * (1 - f) + stops[np.clip(k + 1, 0, 4)] * f
    alpha = body * (1 - t ** 2.5) * (0.85 + 0.15 * turb)
    fire_frames.append(np.dstack([col, alpha]))
save("fire_fb.png", flipbook(fire_frames))

# --- energy blast (greyscale) --------------------------------------------------------------------
blast_frames = []
for i in range(16):
    t = i / 15
    turb = fbm(N, 300 + i, 4, 4)
    radius = 0.3 + 0.6 * (1 - (1 - t) ** 3)
    ring = np.exp(-(((R - radius) / (0.08 + 0.1 * t)) ** 2))
    core = np.clip(1 - R / max(0.05, 0.45 * (1 - t)), 0, 1) ** 1.5
    wisps = np.clip(turb * 1.6 - 0.6, 0, 1) * np.clip(1 - np.abs(R - radius * 0.8) / 0.3, 0, 1) * (1 - t)
    v = np.clip(ring * (0.5 + turb * 0.8) + core + wisps * 0.7, 0, 1)
    alpha = np.clip(v * 1.3, 0, 1) * (1 - t ** 2)
    blast_frames.append(np.dstack([v * 0.3 + 0.7, v * 0.3 + 0.7, v * 0.3 + 0.7, alpha]))
save("blast_fb.png", flipbook(blast_frames))

# --- smoke puff ----------------------------------------------------------------------------------
smoke_frames = []
for i in range(16):
    t = i / 15
    turb = fbm(N, 500 + i // 2, 5, 3)
    radius = 0.6 + 0.35 * t
    d = R / radius + (turb - 0.5) * 0.8
    body = np.clip(1 - d, 0, 1) ** 1.2
    shade = 0.75 + 0.25 * np.clip(-Y * 0.6 + turb * 0.5, 0, 1)
    alpha = np.clip(body * 1.5, 0, 1) * (1 - t) ** 1.3 * 0.9
    smoke_frames.append(np.dstack([shade, shade, shade, alpha]))
save("smoke_fb.png", flipbook(smoke_frames))

# --- spark streak ----------------------------------------------------------------------------------
sh, sw = 256, 64
yy, xx = np.mgrid[0:sh, 0:sw]
u = (xx / (sw - 1)) * 2 - 1
v = yy / (sh - 1)
width = 0.12 + 0.55 * v  # thin tail at the top, round head at the bottom
core = np.exp(-((u / width) ** 2) * 2.5)
along = np.clip(v * 1.2, 0, 1) ** 1.6 * np.clip((1 - v) * 10, 0, 1)
a = np.clip(core * along * 1.4, 0, 1)
save("spark.png", np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a]))

# --- glow ------------------------------------------------------------------------------------------
g = np.clip(1 - R, 0, 1) ** 2.4
save("glow.png", np.dstack([np.ones_like(g)] * 3 + [g]))

# --- ring ------------------------------------------------------------------------------------------
ring = np.exp(-(((R - 0.86) / 0.05) ** 2)) + 0.35 * np.exp(-(((R - 0.74) / 0.12) ** 2))
ring *= R < 1
save("ring.png", np.dstack([np.ones_like(ring)] * 3 + [np.clip(ring, 0, 1)]))

# --- goo splat ---------------------------------------------------------------------------------------
turb = fbm(N, 900, 5, 4)
lobes = 0.55 + 0.07 * np.sin(A * 3 + 1.3) + 0.05 * np.sin(A * 7 + 0.4) + (turb - 0.5) * 0.6
main = np.clip((lobes - R) * 9, 0, 1)
drops = np.zeros_like(R)
for k in range(14):
    ang = rng.uniform(0, 2 * math.pi)
    dist = rng.uniform(0.62, 0.92)
    rad = rng.uniform(0.025, 0.07)
    cx, cy = math.cos(ang) * dist, math.sin(ang) * dist
    drops = np.maximum(drops, np.clip((rad - np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)) * 60, 0, 1))
a = np.clip(main + drops, 0, 1)
shade = 0.8 + 0.2 * np.clip(1 - R / 0.6, 0, 1) + (turb - 0.5) * 0.25
save("splat.png", np.dstack([shade, shade, shade, a * 0.92]))

# --- scorch ------------------------------------------------------------------------------------------
turb = fbm(N, 1200, 5, 5)
d = R + (turb - 0.5) * 0.45
a = np.clip((0.85 - d) * 2.2, 0, 1) ** 1.2
dark = 0.05 + 0.12 * turb
save("scorch.png", np.dstack([dark, dark * 0.85, dark * 0.9, a * 0.85]))

# --- goo droplet -----------------------------------------------------------------------------------
n2 = 64
x2, y2, r2, _ = grid(n2)
body = np.clip((0.85 - r2) * 8, 0, 1)
hi = np.exp(-(((x2 + 0.3) ** 2 + (y2 + 0.35) ** 2) / 0.03))
shade = np.clip(0.75 + 0.25 * (-y2) + hi, 0, 1)
save("goo.png", np.dstack([shade, shade, shade, body]))
print("ok")
