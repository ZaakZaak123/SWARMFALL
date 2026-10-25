"""Original survivor laboratory frame. Blender Z is up; the open front faces -Y."""
import bpy
import math
from mathutils import Vector

ROOT = 'D:/Develop/Roblox/SWARMFALL/production/environment/specimen_frame/'
COLLECTION = 'SF_SpecimenFrame'
col = bpy.data.collections.new(COLLECTION)
bpy.context.scene.collection.children.link(col)
for obj in list(bpy.context.scene.objects):
    obj.hide_set(True)
    obj.hide_render = True

palette = [(0.16, .20, .18, 1), (.33, .37, .30, 1), (.67, .48, .23, 1),
           (.83, .68, .32, 1), (.07, .10, .095, 1), (.47, .69, .56, 1)]
image = bpy.data.images.new('SF_FramePalette', width=96, height=16, alpha=False)
image.pixels = [v for y in range(16) for x in range(96) for v in palette[x // 16]]
image.filepath_raw = ROOT + 'frame_palette.png'
image.file_format = 'PNG'
image.save()
mat = bpy.data.materials.new('SF_SalvagePalette')
mat.use_nodes = True
bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Roughness'].default_value = .72
tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
tex.image = image
tex.interpolation = 'Closest'
mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])

pieces = []
def finish(obj, name, color):
    obj.name = name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    uv = obj.data.uv_layers.active or obj.data.uv_layers.new(name='PaletteUV')
    for loop in uv.data:
        loop.uv = ((color + .5) / len(palette), .5)
    pieces.append(obj)
    return obj

def box(name, loc, size, color, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        m = obj.modifiers.new('Manufactured edges', 'BEVEL')
        m.width, m.segments = bevel, 1
        bpy.ops.object.modifier_apply(modifier=m.name)
    return finish(obj, name, color)

def cylinder(name, loc, radius, depth, color, vertices=12, rotation=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    if rotation:
        obj.rotation_euler = rotation
    return finish(obj, name, color)

cylinder('Foot', (0, 0, .33), 2.6, .66, 0)
cylinder('Lower seal', (0, 0, 1.22), 2.13, .23, 2)
cylinder('Upper seal', (0, 0, 6.93), 2.13, .23, 2)
cylinder('Cap', (0, 0, 7.35), 2.32, .61, 1)
cylinder('Cap inset', (0, 0, 7.72), 1.72, .16, 0)
cylinder('Valve stem', (0, .5, 8.0), .2, .42, 2)
box('Valve handle', (0, .5, 8.25), (1.3, .24, .18), 3, .05)
for x in [-2.08, 2.08]:
    for y in [-.91, .91]:
        box('Frame rail', (x, y, 4.0), (.26, .34, 6.2), 0, .045)
        box('Rail collar', (x, y, 1.07), (.42, .50, .44), 2, .04)
        box('Rail collar', (x, y, 6.84), (.42, .50, .44), 2, .04)
for z in [2.0, 3.0, 4.0, 5.0, 6.0]:
    box('Fill graduation', (-2.28, -.98, z), (.24, .08, .055), 3)
box('Service backing', (0, 1.9, 4.05), (1.1, .42, 5.6), 1, .1)
for z in [2.4, 3.8, 5.2]:
    box('Back fastener', (0, 1.64, z), (.65, .08, .15), 2)
cylinder('Filter', (2.45, 1.28, 2.1), .43, 2.8, 1)
for z in [.76, 3.44]:
    cylinder('Filter clamp', (2.45, 1.28, z), .49, .15, 2)
box('Console', (0, -2.05, .98), (1.7, .9, .58), 0, .1)
box('Display', (-.2, -2.515, 1.05), (.85, .025, .22), 5)
for x in [.4, .65]:
    cylinder('Button', (x, -2.55, .98), .075, .08, 3, 8, (math.pi/2, 0, 0))
for x in [-1.65, 1.65]:
    for y in [-1.4, 1.4]:
        cylinder('Anchor bolt', (x, y, .73), .14, .16, 2, 6)

bpy.ops.object.select_all(action='DESELECT')
for obj in pieces:
    obj.select_set(True)
bpy.context.view_layer.objects.active = pieces[0]
bpy.ops.object.join()
obj = bpy.context.object
obj.name = 'SpecimenFrame'
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
obj.data.calc_loop_triangles()
print('FRAME_TRIANGLES', len(obj.data.loop_triangles))
bpy.ops.wm.save_as_mainfile(filepath=ROOT + 'specimen_frame.blend')
bpy.ops.export_scene.fbx(filepath=ROOT + 'specimen_frame.fbx', use_selection=True,
    apply_unit_scale=True, bake_space_transform=True, axis_forward='-Z', axis_up='Y',
    path_mode='COPY', embed_textures=True, add_leaf_bones=False)
