"""Renders compact Studio part dumps (rows: shape,sx,sy,sz,12 cf comps,r,g,b,neon,t; header
'#x,y,z,lookX,lookZ') from several camera angles relative to the character's facing.
usage: python tools/render_dump.py out.png dump1.txt [dump2.txt ...]"""
import json, math, subprocess, sys, os, tempfile

SHAPES = ["Block", "Ball", "Cylinder"]
ANGLES = [("side", math.pi / 2, -0.12), ("3/4 front", 0.75, -0.35), ("top-down", 0.0, -1.2)]


def load(path):
    lines = open(path, encoding="utf-8").read().strip().splitlines()
    hx, hy, hz, lx, lz = [float(v) for v in lines[0][1:].split(",")]
    parts = []
    for ln in lines[1:]:
        v = [float(x) for x in ln.split(",")]
        parts.append({"shape": SHAPES[int(v[0])], "size": v[1:4], "cf": v[4:16], "color": [int(c) for c in v[16:19]], "neon": v[19] > 0.5, "t": v[20]})
    return (hx, hy, hz), math.atan2(lx, lz), parts


views = []
for path in sys.argv[2:]:
    center, face, parts = load(path)
    name = os.path.splitext(os.path.basename(path))[0]
    for label, yawOff, pitch in ANGLES:
        views.append({"name": f"{name} · {label}", "parts": parts, "yaw": -(face + yawOff), "pitch": pitch, "center": list(center), "span": 9})
tmp = os.path.join(tempfile.gettempdir(), "swarm_views.json")
json.dump({"views": views, "cols": 3, "cell": 420}, open(tmp, "w"))
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "render_scene.py"), tmp, sys.argv[1]], check=True)
