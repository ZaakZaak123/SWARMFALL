"""Render the vector icon specs (exported by tools/export_icons.luau) to a PNG contact sheet."""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

specs = json.load(open(sys.argv[1], encoding="utf-8"))
S = 120  # px per icon
names = sorted(specs)
cols = 8
rows = math.ceil(len(names) / cols)
img = Image.new("RGB", (cols * (S + 20), rows * (S + 40)), (11, 18, 29))
d = ImageDraw.Draw(img)
fg, cut = (84, 238, 255), (11, 18, 29)

def P(ox, oy, x, y):
    return ox + x * S / 100, oy + y * S / 100

for i, name in enumerate(names):
    ox, oy = (i % cols) * (S + 20) + 10, (i // cols) * (S + 40) + 10
    d.rectangle([ox, oy, ox + S, oy + S], fill=(17, 27, 42))
    for s in specs[name]:
        kind = s[0]; alt = kind.endswith("2"); kind = kind.rstrip("2"); c = cut if alt else fg
        if kind == "L":
            x1, y1, x2, y2, t = s[1:6]
            d.line([P(ox, oy, x1, y1), P(ox, oy, x2, y2)], fill=c, width=max(1, int(t * S / 100)))
            for x, y in ((x1, y1), (x2, y2)):
                r = t / 2
                d.ellipse([*P(ox, oy, x - r, y - r), *P(ox, oy, x + r, y + r)], fill=c)
        elif kind == "C":
            x, y, r = s[1:4]
            d.ellipse([*P(ox, oy, x - r, y - r), *P(ox, oy, x + r, y + r)], fill=c)
        elif kind == "R":
            x, y, r, t = s[1:5]
            d.ellipse([*P(ox, oy, x - r, y - r), *P(ox, oy, x + r, y + r)], outline=c, width=max(1, int(t * S / 100)))
        elif kind == "P":
            x, y, w, h = s[1:5]
            d.rounded_rectangle([*P(ox, oy, x - w / 2, y - h / 2), *P(ox, oy, x + w / 2, y + h / 2)], radius=h * S / 200, fill=c)
        elif kind in ("B", "D", "O"):
            if kind == "D":
                x, y, size = s[1:4]; w = h = size / math.sqrt(2); rot = 45
            else:
                x, y, w, h = s[1:5]; rot = s[5] if kind == "B" and len(s) > 5 else 0
            pts = []
            for px_, py_ in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
                a = math.radians(rot)
                pts.append(P(ox, oy, x + px_ * math.cos(a) - py_ * math.sin(a), y + px_ * math.sin(a) + py_ * math.cos(a)))
            if kind == "O":
                d.polygon(pts, outline=c, width=max(1, int(s[5] * S / 100)))
            else:
                d.polygon(pts, fill=c)
    d.text((ox, oy + S + 6), name, fill=(200, 210, 220))
img.save(sys.argv[2])
print("saved", sys.argv[2], len(names), "icons")
