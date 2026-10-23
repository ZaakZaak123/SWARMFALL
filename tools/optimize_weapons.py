"""Loss-bounded weapon mesh optimization, run with Blender --background --python.
Keep original blend/FBX files. Audit candidates before choosing a production budget.
"""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'production/weapons/optimized'
OUT.mkdir(parents=True, exist_ok=True)
SOURCES = {'W01': ROOT/'production/weapons/W01/assets/W01_arc_rifle_redesign.blend',
           'W02': ROOT/'production/weapons/W02/W02_vulcan.blend'}

def triangles(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)

def tree(me):
    me.calc_loop_triangles()
    return BVHTree.FromPolygons([v.co for v in me.vertices], [list(t.vertices) for t in me.loop_triangles], all_triangles=True)

def deviation(original, simplified):
    bvh=tree(simplified)
    samples=[v.co for v in original.vertices]
    original.calc_loop_triangles()
    samples += [sum((original.vertices[i].co for i in t.vertices),Vector())/3 for t in original.loop_triangles]
    values=sorted(bvh.find_nearest(v)[3] for v in samples)
    reverse=tree(original)
    values += [reverse.find_nearest(v.co)[3] for v in simplified.vertices]
    return {'max':max(values,default=0),'rms':math.sqrt(sum(v*v for v in values)/max(1,len(values)))}

def simplify(ob, ratio):
    bpy.context.view_layer.objects.active=ob
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
    bm.to_mesh(ob.data);bm.free()
    mod=ob.modifiers.new('Coplanar cleanup','DECIMATE');mod.decimate_type='DISSOLVE'
    mod.angle_limit=math.radians(.05);mod.delimit={'MATERIAL','UV'}
    bpy.ops.object.modifier_apply(modifier=mod.name)
    if ratio<1:
        mod=ob.modifiers.new('Bounded edge collapse','DECIMATE');mod.ratio=ratio
        mod.use_collapse_triangulate=True;mod.delimit={'MATERIAL','UV'}
        bpy.ops.object.modifier_apply(modifier=mod.name)

report={}
BUILD = '--build' in sys.argv
for weapon,path in SOURCES.items():
    bpy.ops.wm.open_mainfile(filepath=str(path))
    meshes=[o for o in bpy.context.view_layer.objects if o.type=='MESH' and
            ((weapon=='W01' and o.name.startswith('W01_mesh_') and not o.name.endswith('.001')) or
             (weapon=='W02' and o.name in ('Chassis','Armor','Steel','Rubber','Pump','PumpRibs','Brass','Indicators')))]
    assert len(meshes)==(6 if weapon=='W01' else 8)
    report[weapon]={'original':sum(triangles(o) for o in meshes),'candidates':[]}
    originals={o.name:o.data.copy() for o in meshes}
    for ratio in ((.25,) if BUILD else (.4,.3,.25,.2)):
        parts=[]
        for ob in meshes:
            ob.data=originals[ob.name].copy()
            simplify(ob,ratio)
            err=deviation(originals[ob.name],ob.data)
            parts.append({'name':ob.name,'triangles':triangles(ob),**err})
        candidate={'ratio':ratio,'triangles':sum(p['triangles'] for p in parts),'max_error':max(p['max'] for p in parts),'rms_max':max(p['rms'] for p in parts),'parts':parts}
        report[weapon]['candidates'].append(candidate)
        print('CANDIDATE',weapon,ratio,candidate['triangles'],candidate['max_error'],flush=True)
    if BUILD:
        folder=OUT/weapon;folder.mkdir(exist_ok=True)
        bpy.ops.object.select_all(action='DESELECT')
        for ob in meshes:ob.select_set(True)
        bpy.ops.export_scene.fbx(filepath=str(folder/(weapon+'_optimized.fbx')),use_selection=True,object_types={'MESH'},apply_scale_options='FBX_SCALE_ALL',axis_forward='-Z',axis_up='Y',bake_anim=False,add_leaf_bones=False,path_mode='COPY',embed_textures=True)
        # Save source model with only its production objects, no old round-trip scene.
        for sc in list(bpy.data.scenes):
            if sc!=bpy.context.scene:bpy.data.scenes.remove(sc)
        for ob in meshes:
            world=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=world
        for ob in list(bpy.data.objects):
            if ob not in meshes:bpy.data.objects.remove(ob,do_unlink=True)
        bounds=[]
        for ob in meshes:
            pts=[ob.matrix_world@v.co for v in originals[ob.name].vertices]
            lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)))
            hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
            pts2=[ob.matrix_world@v.co for v in ob.data.vertices]
            lo2=Vector(tuple(min(p[i] for p in pts2) for i in range(3)))
            hi2=Vector(tuple(max(p[i] for p in pts2) for i in range(3)))
            bounds.append({'name':ob.name,'original_center':list((lo+hi)/2),'original_size':list(hi-lo),
                           'optimized_center':list((lo2+hi2)/2),'optimized_size':list(hi2-lo2)})
        (folder/'bounds.json').write_text(json.dumps(bounds,indent=2))
        bpy.ops.wm.save_as_mainfile(filepath=str(folder/(weapon+'_optimized.blend')))
        scene=bpy.context.scene
        scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.seed=17
        scene.render.resolution_x=640;scene.render.resolution_y=400;scene.render.resolution_percentage=100
        scene.render.film_transparent=True
        world=bpy.data.worlds.new('Comparison');world.use_nodes=True
        world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.14,.18,1);scene.world=world
        target=Vector((1,0,.3))
        for name,loc,power,size in [('Key',(1,-4,6),850,5),('Rim',(0,4,4),1100,4),('Front',(6,-1,2),350,3)]:
            light=bpy.data.lights.new(name,'AREA');light.energy=power;light.size=size
            ob=bpy.data.objects.new(name,light);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
        cam=bpy.data.objects.new('ComparisonCamera',bpy.data.cameras.new('ComparisonCamera'));scene.collection.objects.link(cam);scene.camera=cam
        cam.data.type='ORTHO';cam.data.ortho_scale=6.4
        optimized={ob.name:ob.data for ob in meshes}
        for view,location in [('hero',(7,-9,5)),('side',(1,-12,1.0))]:
            cam.location=location;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
            for state in (('after',) if '--after-only' in sys.argv else ('before','after')):
                for ob in meshes:ob.data=originals[ob.name] if state=='before' else optimized[ob.name]
                scene.render.filepath=str(folder/(view+'_'+state+'.png'));bpy.ops.render.render(write_still=True)
                print('RENDER',weapon,view,state,flush=True)
(OUT/('production_report.json' if BUILD else 'audit.json')).write_text(json.dumps(report,indent=2))
