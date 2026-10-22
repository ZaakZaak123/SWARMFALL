"""W01 model study. Run in Blender with exec(compile(open(...).read(), ..., 'exec'))."""
import bpy, bmesh, math, json, os
from mathutils import Vector

OUT = r'D:\Develop\Roblox\SWARMFALL\production\weapons\W01\assets'
os.makedirs(OUT, exist_ok=True)
if bpy.data.collections.get('W01_REDESIGN'):
    raise RuntimeError('W01_REDESIGN already exists; preserve it before rebuilding')
col = bpy.data.collections.new('W01_REDESIGN')
bpy.context.scene.collection.children.link(col)
groups = {}
for name in ['body', 'mag', 'bolt', 'coil', 'prongU', 'prongD']:
    e = bpy.data.objects.new('W01_' + name, None)
    col.objects.link(e)
    e.empty_display_size = .12
    e['mechanism'] = name
    groups[name] = e
palette = {
    'navy': ((.058,.088,.13,1), .65, .32),
    'panel': ((.53,.64,.67,1), .55, .34),
    'dark': ((.015,.024,.035,1), .15, .6),
    'copper': ((.65,.245,.075,1), .8, .27),
    'steel': ((.26,.34,.40,1), .8, .28),
    'amber': ((1,.39,.055,1), .35, .35),
    'cyan': ((.025,.78,1,1), .15, .22),
    'white': ((.8,.88,.87,1), .2, .45),
}
mats={}
for key,(color,metal,rough) in palette.items():
    m=bpy.data.materials.new('W01_'+key)
    m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=color
    p.inputs['Metallic'].default_value=metal
    p.inputs['Roughness'].default_value=rough
    if key=='cyan':
        p.inputs['Emission Color'].default_value=color
        p.inputs['Emission Strength'].default_value=2
    m.diffuse_color=color
    mats[key]=m

def finish(o, name, material, group='body', bevel=.025):
    o.name=name
    for c in list(o.users_collection): c.objects.unlink(o)
    col.objects.link(o)
    o.parent=groups[group]
    o.data.materials.append(mats[material])
    if bevel:
        mod=o.modifiers.new('Manufactured edge', 'BEVEL')
        mod.width=bevel; mod.segments=2
    return o

def box(name, loc, size, material, group='body', bevel=.025, tilt=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o=bpy.context.object
    o.dimensions=size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler.y=tilt
    return finish(o,name,material,group,bevel)

def profile(name, points, width, material, group='body', center=0, bevel=.025):
    # Closed extrusion of a side silhouette in X/Z; +X points down the barrel.
    n=len(points)
    v=[(x,center+y*width/2,z) for y in [-1,1] for x,z in points]
    f=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    me=bpy.data.meshes.new(name); me.from_pydata(v,[],f); me.update()
    o=bpy.data.objects.new(name,me); col.objects.link(o)
    return finish(o,name,material,group,bevel)

def cyl(name, loc, radius, depth, material, group='body', axis='X', vertices=16, bevel=.012):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    o=bpy.context.object
    if axis=='X': o.rotation_euler.y=math.pi/2
    if axis=='Y': o.rotation_euler.x=math.pi/2
    return finish(o,name,material,group,bevel)

def ring(name,x,z,outer,inner,depth,material,group='body',cy=0,n=20):
    v=[]
    for xx,r in [(x-depth/2,outer),(x+depth/2,outer),(x-depth/2,inner),(x+depth/2,inner)]:
        v += [(xx,cy+r*math.cos(i*2*math.pi/n),z+r*math.sin(i*2*math.pi/n)) for i in range(n)]
    f=[]
    for i in range(n):
        j=(i+1)%n
        f += [(i,j,n+j,n+i),(2*n+j,2*n+i,3*n+i,3*n+j),
              (j,i,2*n+i,2*n+j),(n+i,n+j,3*n+j,3*n+i)]
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update()
    o=bpy.data.objects.new(name,me);col.objects.link(o)
    return finish(o,name,material,group,.008)

# Receiver: broad clean surfaces and deliberate stepped, chamfered silhouette.
profile('Receiver forged chassis',[(-.55,.15),(-.55,.62),(-.27,.8),(.94,.8),(1.38,.58),(1.38,.2),(.76,.08),(-.25,.08)],.58,'navy',bevel=.045)
profile('Upper bridge',[(-.5,.77),(-.35,.94),(.83,.94),(1.2,.76)],.34,'steel')
for side in [-1,1]:
    yy=side*.307
    profile('Ceramic receiver shell', [(-.40,.3),(-.40,.63),(-.18,.74),(.73,.74),(1.07,.54),(.85,.28),(.18,.22)],.055,'panel',center=yy,bevel=.018)
    profile('Rear dark inset',[(-.32,.38),(-.32,.58),(-.12,.67),(.21,.67),(.12,.38)],.016,'navy',center=side*.342,bevel=.008)
    box('Model amber slash',(.55,side*.344,.57),(.06,.022,.23),'amber',tilt=-.4,bevel=.006)
    for x,z in [(-.28,.32),(.83,.39)]:
        cyl('Recessed fastener',(x,side*.346,z),.037,.016,'dark',axis='Y',vertices=8,bevel=.002)
    # A restrained three segment power indicator, rather than full neon seams.
    for k in range(3): box('Charge readout',(.20+k*.105,side*.35,.37),(.065,.018,.035),'cyan',bevel=.003)

# Stock with an actual negative-space opening, cheek rest and rubber shoulder pad.
profile('Stock shoulder',[(-1.66,.14),(-1.66,.78),(-1.46,.83),(-.57,.66),(-.57,.47),(-1.4,.57),(-1.4,.12)],.3,'navy')
profile('Lower stock brace',[(-1.57,.06),(-1.57,.20),(-.56,.43),(-.50,.29)],.18,'steel',bevel=.018)
box('Shoulder pad',(-1.72,0,.43),(.14,.38,.83),'dark',bevel=.045)
profile('Cheek rest',[(-1.50,.8),(-1.4,.96),(-.86,.88),(-.77,.73)],.32,'panel')
for z in [.19,.32,.45,.58,.71]: box('Pad tread',(-1.80,0,z),(.018,.36,.025),'navy',bevel=.004)

profile('Pistol grip',[(-.45,.22),(-.12,.18),(-.28,-.66),(-.61,-.59),(-.65,-.48)],.27,'dark',bevel=.035)
profile('Grip backstrap',[(-.61,-.57),(-.50,-.64),(-.28,-.66),(-.26,-.53),(-.51,-.46)],.29,'navy',bevel=.018)
for k in range(4): box('Grip traction',(-.43,0,-.18-k*.1),(.24,.286,.025),'navy',bevel=.006)
# Open trigger guard with a separate trigger.
box('Guard lower',(.02,0,-.22),(.64,.11,.075),'steel',bevel=.025)
box('Guard front',(.31,0,-.06),(.075,.11,.36),'steel',bevel=.025)
profile('Trigger',[(.02,.14),(.11,.14),(.04,-.1),(-.04,-.11)],.055,'copper',bevel=.008)

box('Cell socket',(.83,0,.12),(.62,.46,.18),'navy',bevel=.035)
profile('Removable energy cassette',[(.56,.1),(1.05,.1),(1.12,-.64),(.61,-.66),(.5,-.5)],.37,'navy','mag',bevel=.04)
box('Cassette heel',(.82,0,-.66),(.64,.44,.12),'panel','mag',bevel=.025)
box('Cassette safety latch',(.82,0,.0),(.57,.41,.075),'amber','mag',bevel=.012)
for side in [-1,1]:
    box('Cell indicator recess',(.82,side*.19,-.29),(.28,.025,.43),'dark','mag',bevel=.015)
    for k in range(3): box('Cell'+str(k+1),(.82,side*.208,-.16-k*.13),(.19,.018,.075),'cyan','mag',bevel=.008)

# Induction assembly. Real annular windings with dark air gaps and a shielded lower grip.
axis=.52
cyl('Inductor inner sleeve',(1.98,0,axis),.145,1.58,'dark')
cyl('Heat',(2.02,0,axis),.112,1.64,'cyan')
for i in range(6):
    ring('Copper induction winding',1.42+i*.205,axis,.29,.19,.105,'copper','coil')
for i in [0,3]:
    for side in [-1,1]:
        box('Coil index lug',(1.42+i*.205,side*.27,axis),(.115,.075,.09),'steel','coil',bevel=.012)
ring('Rear insulated collar',1.24,axis,.34,.17,.18,'navy')
ring('Forward insulated collar',2.66,axis,.34,.18,.17,'navy')
profile('Lower handguard',[(1.17,.25),(2.62,.25),(2.52,.0),(1.4,-.04),(1.17,.09)],.48,'navy',bevel=.035)
for side in [-1,1]:
    profile('Handguard panel',[(1.28,.22),(2.43,.22),(2.34,.08),(1.42,.05)],.045,'panel',center=side*.252,bevel=.012)
    for i in range(4): box('Handguard cooling slot',(1.5+i*.21,side*.281,.16),(.08,.02,.09),'dark',bevel=.006,tilt=-.35)
box('Inductor dorsal shield',(1.98,0,.88),(1.56,.26,.09),'navy',bevel=.028)
for xx in [1.28,2.65]:
    box('Shield mounting rib',(xx,0,.77),(.12,.16,.27),'steel',bevel=.018)

# Short emitter, split top/bottom electrodes; distinctly an electrical weapon.
cyl('Emitter stem',(2.95,0,axis),.15,.58,'steel')
ring('Emitter lock',2.89,axis,.25,.135,.12,'navy')
ring('Emitter copper contact',3.14,axis,.28,.15,.08,'copper')
ring('Emitter nose',3.25,axis,.32,.155,.17,'navy')
cyl('Emitter aperture',(3.35,0,axis),.12,.035,'dark',bevel=.005)
cyl('Emitter lens',(3.377,0,axis),.068,.02,'cyan',bevel=.004)
for sign,group in [(1,'prongU'),(-1,'prongD')]:
    pts=[(3.17,axis+sign*.24),(3.42,axis+sign*.33),(3.94,axis+sign*.23),(4.02,axis+sign*.14),(3.79,axis+sign*.14),(3.43,axis+sign*.21),(3.17,axis+sign*.14)]
    if sign<0: pts=list(reversed(pts))
    profile('Arc electrode '+group,pts,.18,'steel',group,bevel=.018)
    box('Electrode ceramic cap',(3.82,0,axis+sign*.195),(.19,.2,.11),'panel',group,bevel=.018)
    box('Electrode tip',(3.96,0,axis+sign*.14),(.09,.12,.05),'cyan',group,bevel=.008)

# Charging slider and a compact open reflex sight.
box('Charging slot',(.04,-.355,.57),(.48,.03,.10),'dark',bevel=.012)
box('Bolt carriage',(-.02,-.38,.57),(.29,.055,.07),'steel','bolt',bevel=.012)
box('Charging handle',(-.09,-.46,.57),(.12,.18,.10),'amber','bolt',bevel=.015)
box('Sight foot',(.22,0,.99),(.48,.24,.10),'navy',bevel=.018)
for s in [-1,1]: box('Reflex side',(.20,s*.145,1.15),(.11,.055,.29),'navy',bevel=.018)
box('Reflex roof',(.2,0,1.31),(.11,.33,.055),'panel',bevel=.018)
box('Sight aiming bead',(.22,0,1.03),(.02,.025,.05),'amber',bevel=.003)

# Markers in the same model coordinates. Roblox conversion: (x,y,z) = (Y,Z,-X).
for name,loc in {'Muzzle':(3.96,0,axis),'Grip':(-.39,0,-.2),'ForeGrip':(1.7,0,.02),'MagPivot':(.82,0,-.2),'CoilPivot':(1.98,0,axis)}.items():
    e=bpy.data.objects.new(name,None);col.objects.link(e);e.location=loc;e.empty_display_size=.08;e.hide_render=True
    e['roblox_position']=[loc[1],loc[2],-loc[0]]
groups['coil'].location=(1.98,0,axis)
bpy.context.view_layer.update()
for o in list(groups['coil'].children): o.matrix_parent_inverse=groups['coil'].matrix_world.inverted()

# Typography is geometry on a flat receiver panel, so it survives export.
for side in [-1,1]:
    bpy.ops.object.text_add(location=(.12,side*.36,.60))
    o=bpy.context.object;o.data.body='W01';o.data.size=.13;o.data.extrude=.0005
    o.rotation_euler=(math.pi/2,0,0) if side==-1 else (math.pi/2,0,math.pi)
    o.data.align_x='LEFT' if side==-1 else 'RIGHT'
    bpy.ops.object.convert(target='MESH');finish(bpy.context.object,'W01 identification','white',bevel=0)

# Apply geometry modifiers and consolidate per animated subassembly.
bpy.ops.object.select_all(action='DESELECT')
for group,root in groups.items():
    meshes=[o for o in root.children if o.type=='MESH']
    for o in meshes:
        bpy.context.view_layer.objects.active=o
        for m in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
        o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.join()
    joined=bpy.context.object;joined.name='W01_mesh_'+group
    bm=bmesh.new();bm.from_mesh(joined.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(joined.data);bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    joined['subassembly']=group
    # Mark flat-shaded manufactured faces; bevel strips supply readable highlights.

# A shared colour atlas makes the export independent of Blender-only shader colours.
atlas=bpy.data.images.new('W01_palette',width=256,height=16,alpha=True)
keys=list(palette);pixels=[]
for y in range(16):
    for x in range(256): pixels.extend(palette[keys[min(7,x//32)]][0])
atlas.pixels=pixels;atlas.filepath_raw=os.path.join(OUT,'W01_palette.png');atlas.file_format='PNG';atlas.save()
for o in col.objects:
    if o.type!='MESH': continue
    uv=o.data.uv_layers.new(name='UVMap')
    o.data.uv_layers.active=uv
    uv.active_render=True
    for old in list(o.data.uv_layers)[:-1]: o.data.uv_layers.remove(old)
    for face in o.data.polygons:
        key=o.data.materials[face.material_index].name.removeprefix('W01_')
        u=(keys.index(key)+.5)/8
        for li in face.loop_indices: uv.data[li].uv=(u,.5)
for key,m in mats.items():
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas;tex.interpolation='Closest'
    m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])

# Preserve the startup scene in its own collection, then establish a useful modelling view.
for c in bpy.context.scene.collection.children:
    if c!=col: c.hide_render=True;c.hide_viewport=True
scene=bpy.context.scene
scene.world.color=(.15,.15,.15)
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.shading.type='MATERIAL'
            a.spaces.active.overlay.show_overlays=False
            r=a.spaces.active.region_3d
            r.view_location=(1.0,0,.33);r.view_distance=8
            r.view_rotation=Vector((1,-2,1.1)).to_track_quat('Z','Y')
bpy.ops.object.select_all(action='DESELECT')
for o in col.objects: o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['W01_mesh_body']
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'W01_arc_rifle_redesign.blend'))
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,'W01_arc_rifle_redesign.fbx'),use_selection=True,object_types={'MESH','EMPTY'},add_leaf_bones=False,bake_anim=False,axis_forward='-Z',axis_up='Y',path_mode='COPY',embed_textures=True)
report={'meshes':{},'markers':{},'export':'FBX, -Z forward / Y up','status':'Blender study; Roblox import and gameplay not verified'}
for o in col.objects:
    if o.type=='MESH':
        o.data.calc_loop_triangles()
        report['meshes'][o.name]={'vertices':len(o.data.vertices),'triangles':len(o.data.loop_triangles)}
    elif 'roblox_position' in o: report['markers'][o.name]=list(o['roblox_position'])
report['total_triangles']=sum(x['triangles'] for x in report['meshes'].values())
with open(os.path.join(OUT,'model_stats.json'),'w',encoding='utf8') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps(report,ensure_ascii=False))
