"""Procedural SPOREFALL skybox (DD-042): a dusk alien sky rendered into the six Roblox Sky faces.

python tools/skybox.py out_dir [--debug] [--size 1024]

The sky is a function of view direction, so the faces join without seams:
  gradient   deep indigo zenith -> violet -> magenta/amber horizon glow (warmest toward the sunset)
  nebula     two fBm layers (pink, teal) brightest near the horizon band
  stars      hashed points, fading into the glow
  planet     a ringed violet gas giant low in the north, a pale moon in the south-east
--debug writes direction-coded colours + face labels to verify the face orientation in Studio.
"""
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw

out = sys.argv[1]
debug = "--debug" in sys.argv
N = 1024
if "--size" in sys.argv:
    N = int(sys.argv[sys.argv.index("--size") + 1])
os.makedirs(out, exist_ok=True)

# Face basis: (forward, right, image-up) in Roblox world space (+Y up), measured in Studio with --debug
# (2026-10-24): SkyboxLf sits at +X and SkyboxRt at -X; Up/Dn are rotated so image-up points along +/-X.
FACES = {
    "Ft": (np.array([0, 0, -1.0]), np.array([1.0, 0, 0]), np.array([0, 1.0, 0])),
    "Bk": (np.array([0, 0, 1.0]), np.array([-1.0, 0, 0]), np.array([0, 1.0, 0])),
    "Lf": (np.array([1.0, 0, 0]), np.array([0, 0, 1.0]), np.array([0, 1.0, 0])),
    "Rt": (np.array([-1.0, 0, 0]), np.array([0, 0, -1.0]), np.array([0, 1.0, 0])),
    "Up": (np.array([0, 1.0, 0]), np.array([0, 0, -1.0]), np.array([1.0, 0, 0])),
    "Dn": (np.array([0, -1.0, 0]), np.array([0, 0, -1.0]), np.array([-1.0, 0, 0])),
}
if "--faces" in sys.argv:
    exec(open(sys.argv[sys.argv.index("--faces") + 1]).read())


def dirs_for(face):
    f, r, u = FACES[face]
    s = (np.arange(N) + 0.5) / N * 2 - 1
    xs, ys = np.meshgrid(s, -s)
    d = f[None, None, :] + xs[..., None] * r[None, None, :] + ys[..., None] * u[None, None, :]
    return d / np.linalg.norm(d, axis=-1, keepdims=True)


def hash3(p):
    p = np.floor(p).astype(np.int64)
    h = (p[..., 0] * 73856093) ^ (p[..., 1] * 19349663) ^ (p[..., 2] * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(p):
    i = np.floor(p)
    f = p - i
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * hash3(i + np.array([dx, dy, dz]))
    return out


def fbm(p, oct=5):
    a, s, total = 0.5, 1.0, 0
    for _ in range(oct):
        total = total + a * vnoise(p * s)
        s *= 2.03
        a *= 0.5
    return total


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def col(r, g, b):
    return np.array([r, g, b], dtype=np.float64) / 255.0


# matches Lighting:GetSunDirection() at ClockTime 17.75, latitude 20 (the dusk theme)
SUN = np.array([-0.997, 0.05, -0.06]); SUN /= np.linalg.norm(SUN)
night = "--night" in sys.argv
PLANET = np.array([-0.3, 0.3, 0.9]); PLANET /= np.linalg.norm(PLANET)
MOON = np.array([0.7, 0.42, -0.58]); MOON /= np.linalg.norm(MOON)


def sky(d):
    y = d[..., 1]
    h = np.clip(y, -1, 1)
    zen, mid, hor = col(18, 10, 40), col(62, 28, 98), col(196, 70, 140)
    if night:
        zen, mid, hor = col(6, 4, 16), col(24, 10, 40), col(90, 24, 60)
    c = mix(hor, mid, h / 0.35)
    c = mix(c, zen, (h - 0.35) / 0.65)
    # below horizon: dark plum haze (mostly hidden by terrain)
    c = mix(c, col(40, 18, 52), -h / 0.25)
    # sunset warmth
    sd = np.clip((d @ SUN), 0, 1)
    glow = sd ** 8 * np.clip(1 - np.abs(y) * 2.4, 0, 1) * (0.15 if night else 0.8)
    c = c + glow[..., None] * col(255, 150, 70) * 0.9
    if not night:
        c = c + (sd ** 400)[..., None] * col(255, 220, 170) * 0.9
    # nebula
    band = np.exp(-((y - 0.18) / 0.32) ** 2)
    n1 = fbm(d * 2.6 + 3.1)
    n2 = fbm(d * 4.3 + 11.7)
    pink = np.clip((n1 - 0.48) * 2.6, 0, 1) ** 1.6 * band
    teal = np.clip((n2 - 0.52) * 2.8, 0, 1) ** 1.8 * (0.4 + band * 0.6)
    c = c + pink[..., None] * col(255, 80, 170) * 0.55 + teal[..., None] * col(60, 230, 210) * 0.35
    # stars
    p = d * 380
    sv = hash3(p)
    star = (sv > 0.9965).astype(np.float64) * np.clip((y - 0.05) * 3, 0, 1) * (1 - glow * 2).clip(0, 1)
    tw = hash3(p + 17.0)
    c = c + (star * (0.5 + tw))[..., None] * col(230, 230, 255)
    # planet with ring
    pd = np.arccos(np.clip(d @ PLANET, -1, 1))
    R = 0.27
    disc = pd < R
    # shading: light from the sun side
    ld = np.clip((d - PLANET[None, None, :] * np.cos(pd)[..., None]) @ SUN * 4 + 0.5, 0, 1)
    stripes = 0.5 + 0.5 * np.sin((d @ np.array([0.2, 1.0, 0.1])) * 140 + fbm(d * 9.0) * 4)
    pc = mix(col(70, 36, 120), col(180, 120, 220), ld * 0.8 + stripes * 0.2)
    c = np.where(disc[..., None], pc * (0.55 + 0.45 * ld[..., None]), c)
    rim = np.exp(-((pd - R) / 0.012) ** 2)
    c = c + rim[..., None] * col(255, 170, 230) * 0.6
    # ring: an ellipse in the planet's tangent plane, tilted; the lower half passes in front of the disc
    e1 = np.cross(PLANET, np.array([0, 1.0, 0])); e1 /= np.linalg.norm(e1)
    e2 = np.cross(e1, PLANET)
    dp = np.maximum(d @ PLANET, 1e-3)
    ga, gb = (d @ e1) / dp, (d @ e2) / dp
    tilt = 0.32
    ra = ga * math.cos(tilt) + gb * math.sin(tilt)
    rb = -ga * math.sin(tilt) + gb * math.cos(tilt)
    big = math.tan(R) * 2.1
    ell = np.sqrt((ra / big) ** 2 + (rb / (big * 0.2)) ** 2)
    band = np.clip((ell - 0.6) * 12, 0, 1) * np.clip((1.0 - ell) * 12, 0, 1)
    band = band * (0.55 + 0.45 * np.sin(ell * 70)) * (d @ PLANET > 0)
    hidden = disc & (rb > 0)
    ringc = mix(col(255, 190, 235), col(200, 150, 255), np.clip((ell - 0.6) * 2.5, 0, 1))
    c = np.where(hidden[..., None], c, mix(c, ringc, band * 0.85))
    # moon
    md = np.arccos(np.clip(d @ MOON, -1, 1))
    c = np.where((md < 0.05)[..., None], col(235, 230, 255) * (0.8 + 0.2 * fbm(d * 40)[..., None]), c)
    c = c + (np.exp(-(md / 0.09) ** 2))[..., None] * col(180, 170, 255) * 0.25
    return np.clip(c, 0, 1)


for face in FACES:
    d = dirs_for(face)
    if debug:
        img = ((d + 1) / 2 * 255).astype(np.uint8)
        im = Image.fromarray(img)
        dr = ImageDraw.Draw(im)
        dr.rectangle([N // 2 - 90, N // 2 - 60, N // 2 + 90, N // 2 + 60], fill=(0, 0, 0))
        dr.text((N // 2 - 40, N // 2 - 20), face, fill=(255, 255, 255))
        dr.text((10, 10), "TOP-LEFT", fill=(0, 0, 0))
    else:
        im = Image.fromarray((sky(d) ** (1 / 1.05) * 255).astype(np.uint8))
    im.save(os.path.join(out, f"sky_{face}.png"))
    print("wrote", face)
