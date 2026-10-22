"""Renders live part dumps from Studio (see tools/dump_scene.luau) with the flat-shaded painter's
renderer, so poses / VFX can be checked when the Studio viewport cannot render.
usage: python tools/render_scene.py dump.json out.png
dump.json = {"views": [{"name", "parts": [...], "yaw", "pitch", "cell"?}]}"""
import json, math, sys
from PIL import Image, ImageDraw

data = json.load(open(sys.argv[1], encoding="utf-8"))
views = data["views"]
CELL = data.get("cell", 520)
cols = min(len(views), data.get("cols", 3))
rows = math.ceil(len(views) / cols)
img = Image.new("RGB", (cols * CELL, rows * CELL), (14, 20, 30))
d = ImageDraw.Draw(img, "RGBA")
try:
    from PIL import ImageFont
    FONT = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 14)
except Exception:
    FONT = None
LIGHT = (0.4, 0.8, -0.45)
ln = math.sqrt(sum(v * v for v in LIGHT)); LIGHT = tuple(v / ln for v in LIGHT)


def xf(cf, p):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    return (x + r00 * p[0] + r01 * p[1] + r02 * p[2], y + r10 * p[0] + r11 * p[1] + r12 * p[2], z + r20 * p[0] + r21 * p[1] + r22 * p[2])


def faces(part):
    sx, sy, sz = [v / 2 for v in part["size"]]
    cf = part["cf"]
    if part["shape"] == "Ball":
        return [("ball", xf(cf, (0, 0, 0)), sx)]
    out = []
    if part["shape"] == "Cylinder":
        n = 12
        ring = lambda xx: [xf(cf, (xx, sy * math.cos(2 * math.pi * k / n), sy * math.sin(2 * math.pi * k / n))) for k in range(n)]
        a, b = ring(-sx), ring(sx)
        for k in range(n):
            out.append(("poly", [a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]]))
        out.append(("poly", a)); out.append(("poly", b[::-1]))
        return out
    c = [xf(cf, (dx * sx, dy * sy, dz * sz)) for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]
    if part["shape"] == "Wedge":
        # Roblox wedge: full height at +Z, slope from the top-back edge down to the bottom-front edge
        idx = [(0, 1, 3), (4, 7, 5), (0, 4, 5, 1), (1, 5, 7, 3), (0, 3, 7, 4)]
        return [("poly", [c[i] for i in f]) for f in idx]
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return [("poly", [c[i] for i in f]) for f in idx]


def render(item, ox, oy):
    yaw, pitch = item.get("yaw", 2.5), item.get("pitch", -0.5)
    cy, sy_, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    center = item.get("center")

    def cam(p):
        x, y, z = p
        if center:
            x, y, z = x - center[0], y - center[1], z - center[2]
        x, z = x * cy - z * sy_, x * sy_ + z * cy
        y, z = y * cp - z * sp, y * sp + z * cp
        return (x, y, z)

    prims, allpts = [], []
    for part in item["parts"]:
        if part.get("t", 0) >= 0.97:
            continue
        for f in faces(part):
            if f[0] == "ball":
                c = cam(f[1]); prims.append((c[2], "ball", c, f[2], part)); allpts.append(c)
            else:
                pts = [cam(p) for p in f[1]]
                allpts += pts
                a, b, cc = pts[0], pts[1], pts[2]
                u = [b[i] - a[i] for i in range(3)]; v = [cc[i] - a[i] for i in range(3)]
                nrm = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
                if nrm[2] > 0:
                    continue
                prims.append((sum(p[2] for p in pts) / len(pts), "poly", pts, nrm, part))
    if not allpts:
        return
    span = item.get("span")
    if not span:
        xs = [p[0] for p in allpts]; ys = [p[1] for p in allpts]
        span = max(max(xs) - min(xs), max(ys) - min(ys), 0.01)
        mx, my = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    else:
        mx, my = 0, 0
    scale = (CELL - 40) / span
    S = lambda p: (ox + CELL / 2 + (p[0] - mx) * scale, oy + CELL / 2 - (p[1] - my) * scale)
    prims.sort(key=lambda t: -t[0])
    for pr in prims:
        part = pr[4]; col = part["color"]
        alpha = int(255 * (1 - part.get("t", 0)))
        if pr[1] == "ball":
            c, r = pr[2], pr[3] * scale
            x, y = S(c)
            shade = 1.0 if part["neon"] else 0.8
            d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(v * shade) for v in col) + (alpha,))
            continue
        nrm = pr[3]; ln_ = math.sqrt(sum(v * v for v in nrm)) or 1
        lam = max(0.0, -(nrm[0] * LIGHT[0] + nrm[1] * -LIGHT[1] + nrm[2] * LIGHT[2]) / ln_)
        shade = 1.0 if part["neon"] else 0.35 + 0.75 * lam
        fill = tuple(min(255, int(v * shade)) for v in col)
        d.polygon([S(p) for p in pr[2]], fill=fill + (alpha,), outline=tuple(int(v * 0.5) for v in fill) + (min(255, alpha),))
    d.text((ox + 10, oy + 8), item["name"], fill=(220, 230, 240), font=FONT)


for i, item in enumerate(views):
    render(item, (i % cols) * CELL, (i // cols) * CELL)
img.save(sys.argv[2]); print("saved", sys.argv[2])
