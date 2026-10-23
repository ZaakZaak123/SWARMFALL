# EN_RUNNER В«Р‘РµРіСѓРЅВ» вЂ” procedural model. Run headless:
#   blender -b --factory-startup --python assets/models/runner/build_runner.py -- <out_dir> [render]
# Units: 1 Blender unit = 1 stud. Creature faces -Y, stands on Z=0.
# Output: runner.blend, runner.fbx (one mesh per game part), optional preview PNGs.
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
OUT = argv[0] if argv else "."
RENDER = len(argv) > 1 and argv[1] == "render"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# Part colours (match Creatures.luau palette: shell 245,100,50 / dark 165,55,35 / eye 255,230,90)
COLORS = {
    "Shell": (245, 100, 50),
    "Flesh": (120, 38, 30),
    "Head": (150, 50, 32),
    "Mandibles": (235, 215, 170),
    "Eyes": (255, 230, 90),
    "Leg": (95, 32, 26),
}


def srgb(c):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    return (lin(c[0]), lin(c[1]), lin(c[2]), 1)


def material(name, emit=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    col = srgb(COLORS[name])
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.35 if name == "Shell" else 0.6
    if emit:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 6
    return m


MATS = {k: material(k, emit=(k == "Eyes")) for k in COLORS}

# ---------------------------------------------------------------------------------------------
# bmesh helpers: every piece is added into a part's bmesh, transformed in place.


def add_sphere(bm, center, radii, segs=14, rings=9, deform=None, cut_below=None):
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = [v for v in geom["verts"]]
    for v in verts:
        p = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2]))
        if deform:
            p = deform(p)
        v.co = p + Vector(center)
    if cut_below is not None:
        doomed = [v for v in verts if v.co.z < cut_below - 1e-4]
        bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    return verts


def add_cone(bm, a, b, r1, r2, segs=7):
    a, b = Vector(a), Vector(b)
    d = b - a
    geom = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=True, segments=segs, radius1=r1, radius2=r2, depth=d.length
    )
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    mat = Matrix.Translation((a + b) / 2) @ rot
    bmesh.ops.transform(bm, matrix=mat, verts=geom["verts"])


def make_obj(name, bm, mat_name, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(MATS[mat_name])
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    return ob


# ---------------------------------------------------------------------------------------------
BODY_Z = 1.55  # spine height


def thorax_deform(p):
    # Pinch the front, swell the back of the thorax; flatter belly.
    t = (p.y + 1) / 2
    k = 0.85 + 0.25 * t
    z = p.z if p.z > 0 else p.z * 0.75
    return Vector((p.x * k, p.y, z))


def abdomen_deform(p):
    # Teardrop pointing backwards (+Y), lifted tail.
    t = max(0.0, p.y)
    k = 1 - 0.55 * t * t
    return Vector((p.x * k, p.y, p.z * k + 0.25 * t * t))


# Flesh: thorax core + abdomen + neck
bm = bmesh.new()
add_sphere(bm, (0, -0.35, BODY_Z - 0.05), (0.78, 1.05, 0.6), segs=12, rings=7, deform=thorax_deform)
add_sphere(bm, (0, 1.25, BODY_Z + 0.05), (0.95, 1.25, 0.78), segs=12, rings=8, deform=abdomen_deform)
add_cone(bm, (0, 2.35, BODY_Z + 0.45), (0, 3.05, BODY_Z + 0.95), 0.22, 0.02, segs=6)  # tail stinger
add_sphere(bm, (0, -1.35, BODY_Z - 0.1), (0.45, 0.4, 0.38), segs=10, rings=7)  # neck
flesh = make_obj("Flesh", bm, "Flesh")

# Shell: overlapping dorsal plates (thorax 3, abdomen 3) + spine spikes
bm = bmesh.new()
# (y, rx, ry, rz, centre z): each plate sits proud of the flesh, the next one tucks under it.
plates = [
    (-0.95, 0.8, 0.55, 0.52, BODY_Z + 0.02),
    (-0.2, 0.92, 0.6, 0.6, BODY_Z + 0.04),
    (0.6, 1.05, 0.58, 0.78, BODY_Z + 0.12),
    (1.25, 1.0, 0.56, 0.74, BODY_Z + 0.2),
    (1.85, 0.74, 0.46, 0.56, BODY_Z + 0.32),
    (2.3, 0.42, 0.34, 0.36, BODY_Z + 0.45),
]
for i, (y, rx, ry, rz, z0) in enumerate(plates):

    def plate_deform(p, ry=ry):
        # Lift the rear edge so each plate overlaps the next one like armour; flat underside.
        z = p.z if p.z > 0 else p.z * 0.45
        return Vector((p.x, p.y, z + max(0.0, p.y) / ry * 0.1))

    add_sphere(bm, (0, y, z0), (rx, ry, rz), segs=12, rings=7, deform=plate_deform)
    # spike on the ridge
    if i < 5:
        top = Vector((0, y + ry * 0.2, z0 + rz + 0.02))
        add_cone(bm, top - Vector((0, 0, 0.15)), top + Vector((0, 0.35, 0.42 - i * 0.04)), 0.12, 0.0, segs=5)
# side spurs on the thorax shoulders
for s in (1, -1):
    add_cone(bm, (s * 0.65, -0.7, BODY_Z + 0.2), (s * 1.15, -0.45, BODY_Z + 0.55), 0.13, 0.0, segs=5)
shell = make_obj("Shell", bm, "Shell")


# Head: low wedge skull with a brow ridge
def head_deform(p):
    t = (1 - p.y) / 2  # 1 at the snout (-Y)
    w = 1 - 0.35 * t
    z = p.z * (1 - 0.3 * t) - 0.12 * t
    return Vector((p.x * w, p.y, z))


bm = bmesh.new()
add_sphere(bm, (0, -1.95, BODY_Z - 0.12), (0.62, 0.62, 0.42), segs=14, rings=9, deform=head_deform)
add_sphere(bm, (0, -1.85, BODY_Z + 0.2), (0.6, 0.32, 0.14), segs=12, rings=6)  # brow ridge
for s in (1, -1):  # cheek horns sweeping back
    add_cone(bm, (s * 0.45, -1.8, BODY_Z + 0.2), (s * 0.85, -1.2, BODY_Z + 0.7), 0.1, 0.0, segs=5)
head = make_obj("Head", bm, "Head")

# Mandibles: two curved, tapered pincers + small palps
bm = bmesh.new()
for s in (1, -1):
    pts = [
        Vector((s * 0.32, -2.3, BODY_Z - 0.32)),
        Vector((s * 0.48, -2.75, BODY_Z - 0.38)),
        Vector((s * 0.36, -3.15, BODY_Z - 0.42)),
        Vector((s * 0.06, -3.38, BODY_Z - 0.45)),
    ]
    radii = [0.13, 0.1, 0.065, 0.02]
    for k in range(3):
        add_cone(bm, pts[k], pts[k + 1], radii[k], radii[k + 1], segs=6)
    add_cone(bm, (s * 0.2, -2.35, BODY_Z - 0.45), (s * 0.28, -2.75, BODY_Z - 0.8), 0.06, 0.02, segs=5)
mand = make_obj("Mandibles", bm, "Mandibles")

# Eyes: a large and two small glowing eyes per side + a visor slit
bm = bmesh.new()
for s in (1, -1):
    add_sphere(bm, (s * 0.33, -2.35, BODY_Z + 0.05), (0.17, 0.13, 0.11), segs=8, rings=5)
    add_sphere(bm, (s * 0.46, -2.12, BODY_Z + 0.16), (0.08, 0.08, 0.07), segs=6, rings=4)
    add_sphere(bm, (s * 0.5, -1.95, BODY_Z + 0.02), (0.07, 0.07, 0.06), segs=6, rings=4)
add_sphere(bm, (0, -2.42, BODY_Z - 0.02), (0.18, 0.09, 0.05), segs=8, rings=4)
eyes = make_obj("Eyes", bm, "Eyes")


# Legs: hip -> knee (raised, outward) -> foot (sharp claw tip). Origin at the hip.
def make_leg(name, side, hip_y, splay):
    hip = Vector((side * 0.62, hip_y, BODY_Z - 0.15))
    knee = Vector((side * 1.55, hip_y + splay * 0.35, BODY_Z + 0.7))
    ankle = Vector((side * 2.05, hip_y + splay * 0.75, 0.55))
    foot = Vector((side * 2.15, hip_y + splay * 0.95, 0.0))
    bm = bmesh.new()
    add_sphere(bm, hip, (0.2, 0.2, 0.2), segs=8, rings=5)
    add_cone(bm, hip, knee, 0.24, 0.16, segs=7)
    add_sphere(bm, knee, (0.19, 0.19, 0.19), segs=8, rings=5)
    add_cone(bm, knee, ankle, 0.16, 0.1, segs=7)
    add_cone(bm, ankle, foot, 0.1, 0.0, segs=6)
    # serrated spur on the shin
    mid = (knee + ankle) / 2
    add_cone(bm, mid, mid + Vector((side * 0.25, -splay * 0.1, 0.18)), 0.05, 0.0, segs=4)
    ob = make_obj(name, bm, "Leg")
    # origin -> hip
    ob.data.transform(Matrix.Translation(-hip))
    ob.location = hip
    return ob


legs = [
    make_leg("LegFR", 1, -0.7, -1),
    make_leg("LegFL", -1, -0.7, -1),
    make_leg("LegBR", 1, 0.45, 1),
    make_leg("LegBL", -1, 0.45, 1),
]

parts = [shell, flesh, head, mand, eyes] + legs
tris = 0
for ob in parts:
    me = ob.data
    me.calc_loop_triangles()
    tris += len(me.loop_triangles)
    print(f"PART {ob.name:10s} tris={len(me.loop_triangles):5d} dims={tuple(round(d, 2) for d in ob.dimensions)}")
print("TOTAL_TRIS", tris)

bpy.ops.wm.save_as_mainfile(filepath=f"{OUT}/runner.blend")
bpy.ops.export_scene.fbx(
    filepath=f"{OUT}/runner.fbx",
    use_selection=False,
    object_types={"MESH"},
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z",
    axis_up="Y",
    mesh_smooth_type="FACE",
    add_leaf_bones=False,
    bake_anim=False,
)
print("EXPORTED", f"{OUT}/runner.fbx")

if RENDER:
    # Simple studio: ground, key/rim lights, Cycles CPU (viewport GPU drivers are broken here).
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (
        0.05,
        0.05,
        0.06,
        1,
    )
    ground.data.materials.append(gm)
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.02, 0.025, 0.035, 1)
    scene.world = world
    for name, loc, energy, size in (("Key", (4, -5, 6), 900, 4), ("Rim", (-4, 5, 4), 700, 3), ("Fill", (-5, -3, 2), 200, 5)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.size = size
        lo = bpy.data.objects.new(name, light)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 1)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(lo)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    try:
        scene.render.engine = "CYCLES"
    except TypeError as e:
        print("ENGINE", e)
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.resolution_x = 640
    scene.render.resolution_y = 480
    target = Vector((0, -0.2, 1.1))
    for view, d in (("threequarter", (-1.0, -1.1, 0.75)), ("side", (-1.0, 0.0, 0.15)), ("front", (0.0, -1.0, 0.3)), ("top", (0.0, -0.05, 1.0))):
        direction = Vector(d).normalized()
        cam.location = target + direction * 11
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{OUT}/preview_{view}.png"
        bpy.ops.render.render(write_still=True)
        print("RENDERED", view)
