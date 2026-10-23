"""Build W02 in Blender background mode. Coordinates: +X muzzle, +Z up.
Roblox mapping: (Y, Z, -X). Meshes use solid materials, no texture dependency.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parent
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
COLORS = {'Chassis':(39,48,61), 'Armor':(202,79,29), 'Steel':(112,128,141),
          'Rubber':(19,23,29), 'Pump':(210,89,31), 'PumpRibs':(32,38,45),
          'Brass':(204,153,68), 'Indicators':(255,177,65)}
materials = {}
for key, rgb in COLORS.items():
    m = bpy.data.materials.new(key); m.use_nodes = True
    color = tuple((v/255/12.92 if v/255 <= .04045 else ((v/255+.055)/1.055)**2.4) for v in rgb)+(1,)
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=color
    bs.inputs['Metallic'].default_value=.65 if key not in ('Rubber','PumpRibs') else .05
    bs.inputs['Roughness'].default_value=.36 if key != 'Rubber' else .75
    if key == 'Indicators':
        bs.inputs['Emission Color'].default_value=color
        bs.inputs['Emission Strength'].default_value=1.8
    m.diffuse_color=color; materials[key]=m
pieces = {k:[] for k in COLORS}

def finish(o, key, bevel=.02):
    o.data.materials.append(materials[key]); pieces[key].append(o)
    if bevel:
        mod=o.modifiers.new('Machined edge','BEVEL');mod.width=bevel;mod.segments=2
    return o

def box(loc,size,key,bevel=.02,tilt=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object;o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.rotation_euler.y=tilt
    return finish(o,key,bevel)

def profile(points,width,key,center=0):
    n=len(points);verts=[(x,center+y*width/2,z) for y in (-1,1) for x,z in points]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    me=bpy.data.meshes.new(key);me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(key,me);scene.collection.objects.link(ob)
    return finish(ob,key)

def cyl(loc,r,depth,key,axis='X',n=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=depth,location=loc)
    o=bpy.context.object
    o.rotation_euler=(0,math.pi/2,0) if axis=='X' else (math.pi/2,0,0)
    return finish(o,key,.008)

def tube(x,y,z,r,inner,length,key,n=16):
    verts=[]
    for xx,rr in ((x-length/2,r),(x+length/2,r),(x-length/2,inner),(x+length/2,inner)):
        verts += [(xx,y+rr*math.cos(i*2*math.pi/n),z+rr*math.sin(i*2*math.pi/n)) for i in range(n)]
    faces=[]
    for i in range(n):
        j=(i+1)%n
        faces += [(i,j,n+j,n+i),(2*n+j,2*n+i,3*n+i,3*n+j),(j,i,2*n+i,2*n+j),(n+i,n+j,3*n+j,3*n+i)]
    me=bpy.data.meshes.new('Bored barrel');me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new('Bored barrel',me);scene.collection.objects.link(ob)
    return finish(ob,key,.006)

# Receiver with ceramic side armor and a recessed ejection window.
profile([(-.65,.1),(-.65,.62),(-.42,.85),(.78,.85),(1.25,.61),(1.25,.16),(.65,.05)],.69,'Chassis')
for side in (-1,1):
    profile([(-.52,.22),(-.52,.61),(-.3,.75),(.55,.75),(.91,.54),(.72,.24)],.045,'Armor',side*.365)
    box((.4,side*.397,.51),(.65,.022,.23),'Rubber',.015)
    box((.42,side*.414,.51),(.43,.015,.13),'Steel',.007)
    for x in (-.39,.78): cyl((x,side*.405,.32),.045,.025,'Steel','Y',8)
    for x in (-.28,-.16,-.04): box((x,side*.4,.5),(.045,.02,.14),'Brass',.004,tilt=-.35)
    # Four spare shells on each side, clearly separated caps and hulls.
    for x in (-.43,-.22,-.01,.20):
        cyl((x,side*.43,.86),.075,.29,'Armor','Y')
        cyl((x,side*.60,.86),.078,.055,'Brass','Y')

# Recoil stock with a real open triangular brace, padded cheek rest and ribbed butt.
profile([(-1.57,.0),(-1.57,.62),(-1.4,.72),(-.63,.57),(-.63,.4),(-1.35,.48),(-1.35,.04)],.33,'Chassis')
profile([(-1.48,.02),(-1.43,.15),(-.64,.37),(-.6,.23)],.18,'Steel')
box((-1.61,0,.33),(.15,.43,.76),'Rubber',.045)
box((-1.1,0,.69),(.65,.38,.14),'Armor',.035,tilt=.08)
for z in (.08,.21,.34,.47,.60): box((-1.696,0,z),(.025,.40,.035),'Chassis',.004)
profile([(-.27,.22),(.03,.18),(-.03,-.55),(-.31,-.53),(-.43,-.39)],.29,'Rubber')
for z in (-.12,-.23,-.34,-.45):box((-.21,0,z),(.25,.306,.03),'Chassis',.006)
box((.25,0,-.18),(.60,.12,.07),'Steel')
box((.54,0,-.04),(.07,.12,.29),'Steel')
box((.22,0,.01),(.075,.08,.22),'Brass',tilt=-.25)

# Two true hollow barrels, front brake collars and segmented ventilated heatshield.
for side in (-1,1):
    y=side*.215
    tube(2.42,y,.47,.185,.125,2.5,'Steel')
    tube(3.69,y,.47,.238,.129,.27,'Chassis')
    tube(3.83,y,.47,.213,.133,.075,'Steel')
    cyl((3.1,y,.47),.126,.025,'Rubber') # dark bore rear wall
    for x in (1.34,2.0,2.65,3.28):
        tube(x,y,.47,.212,.184,.07,'Chassis')
    # Discrete segments leave visible cooling gaps instead of painted fake holes.
    for i in range(6):
        x=1.35+i*.29
        box((x,side*.40,.66),(.17,.055,.20),'Chassis',.012,tilt=.15)
        box((x,side*.434,.68),(.09,.02,.09),'Armor',.005)
box((2.11,0,.79),(2.30,.20,.09),'Chassis')
for x in (1.28,1.55,1.82,2.09,2.36,2.63,2.9):box((x,0,.86),(.10,.26,.06),'Steel',.006)
box((3.26,0,.86),(.14,.24,.30),'Chassis')
box((3.26,0,1.025),(.06,.06,.045),'Indicators',.004)
for side in (-1,1):box((-.23,side*.135,.96),(.14,.055,.24),'Chassis')

# Moving pump at the existing IK foregrip, plus visible action rods.
profile([(1.23,-.32),(2.49,-.32),(2.57,-.15),(2.45,.17),(1.22,.17),(1.10,-.12)],.73,'Pump')
for i in range(7):box((1.26+i*.17,0,-.10),(.065,.78,.42),'PumpRibs',.015)
for side in (-1,1):box((1.12,side*.27,.20),(1.75,.065,.065),'PumpRibs',.01)
cyl((1.04,0,-.12),.15,.28,'Steel')

# Merge by material and motion group, preserving origins in model coordinates.
manifest={'mapping':'Roblox = (Blender Y, Blender Z, -Blender X)','parts':[]}
for key,objects in pieces.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
    ob=bpy.context.object;ob.name=key
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    ob.data.calc_loop_triangles()
    manifest['parts'].append({'name':key,'rgb':COLORS[key],'group':'pump' if key.startswith('Pump') else None,'triangles':len(ob.data.loop_triangles)})
manifest['triangles']=sum(p['triangles'] for p in manifest['parts'])
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'W02_vulcan.blend'))
bpy.ops.export_scene.fbx(filepath=str(OUT/'W02_vulcan.fbx'),object_types={'MESH'},apply_scale_options='FBX_SCALE_ALL',axis_forward='-Z',axis_up='Y',bake_anim=False,add_leaf_bones=False)
print('W02_REPORT='+json.dumps(manifest))

# CPU render works without the unavailable Vulkan viewport.
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32
scene.render.resolution_x=1100;scene.render.resolution_y=700;scene.render.resolution_percentage=100
world=bpy.data.worlds.new('Studio');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.08,.10,.15,1);scene.world=world
target=Vector((1,0,.28))
for name,loc,power,size in [('Key',(1,-4,6),850,5),('Rim',(0,4,4),1100,4),('Front',(6,-1,2),350,3)]:
    light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size
    ob=bpy.data.objects.new(name,light);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=6.4
for name,loc in [('hero',(7,-9,5)),('side',(1,-12,1.5))]:
    cam.location=loc;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/('preview_'+name+'.png'));bpy.ops.render.render(write_still=True)
