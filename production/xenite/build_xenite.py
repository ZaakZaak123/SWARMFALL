"""Blender --background --factory-startup --python production/xenite/build_xenite.py.
Original low-poly geometry; JSON contains exact triangles in Roblox coordinates.
"""
import bpy, bmesh, json, zlib, struct
from pathlib import Path
from mathutils import Vector, Matrix
OUT=Path(__file__).resolve().parent
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
PALETTE=[(.34,.025,.24),(.59,.025,.36),(.77,.04,.43),(.91,.09,.52),(.98,.23,.64),(.49,.035,.32),(.26,.03,.21),(1,.12,.53),(1,.62,.85),(.20,.19,.22),(.32,.29,.31)]
MATS=[]
for i,rgb in enumerate(PALETTE):
    m=bpy.data.materials.new('Facet_%d'%i);m.diffuse_color=(*rgb,1);m.use_nodes=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    linear=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb)
    bs.inputs['Base Color'].default_value=(*linear,1);bs.inputs['Roughness'].default_value=.36
    bs.inputs['Metallic'].default_value=.12
    if i==8:
        bs.inputs['Emission Color'].default_value=(*linear,1);bs.inputs['Emission Strength'].default_value=1.5
    MATS.append(m)
# Front (-Y): asymmetric clipped shoulder, bevels, broad facets. No subdivision.
outline=[(-.56,.05),(-.91,.44),(-1.03,1.13),(-.66,2.33),(-.31,2.77),(.58,2.86),(.94,2.35),(1.03,1.12),(.61,.14)]
bm=bmesh.new()
for depth,scale,dx,dz in [(-.63,.81,-.02,.05),(-.13,1,0,0),(.62,.73,-.04,.12)]:
    for x,z in outline: bm.verts.new((x*scale+dx,depth,(z-1.4)*scale+1.4+dz))
bm.verts.new((-.12,-.84,1.22));bm.verts.new((.24,-.78,2.04))
bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bmesh.ops.dissolve_limit(bm,angle_limit=.001,verts=list(bm.verts),edges=list(bm.edges))
faces=[[v.co.copy() for v in f.verts] for f in bm.faces];normals=[f.normal.copy() for f in bm.faces];bm.free()
def distance(v): return v.z-.94*v.x-.18*v.y-1.31
def clip(poly,limit,above):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da,db=distance(a)-limit,distance(b)-limit
        ina=da>=-1e-8 if above else da<=1e-8;inb=db>=-1e-8 if above else db<=1e-8
        if ina: result.append(a)
        if ina!=inb: result.append(a.lerp(b,da/(da-db)))
    return result
body,core=[],[]
for poly,n in zip(faces,normals):
    facet=4 if n.z>.55 else (1 if n.x<-.25 else 3 if n.z>.15 else 2) if n.y<-.5 else 0 if n.x<-.4 else 5
    # A narrow emissive fissure wraps around the whole solid, with pink mineral rims.
    for lo,hi,mi in [(-100,-.075,facet),(-.075,-.022,7),(-.022,.022,8),(.022,.075,7),(.075,100,facet)]:
        p=clip(clip(poly,lo,True),hi,False)
        if len(p)>=3: (core if mi==8 else body).append((p,mi))
def mesh_object(name,polys):
    verts,inds,mats=[],[],[]
    for polygon,mi in polys:
        start=len(verts);verts.extend([list(v) for v in polygon])
        for i in range(1,len(polygon)-1):
            if (polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0]).length<1e-7: continue
            inds.append([start,start+i,start+i+1]);mats.append(mi)
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],inds);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    for m in MATS: me.materials.append(m)
    for p,mi in zip(me.polygons,mats): p.material_index=mi
    colors=me.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    for p in me.polygons:
        for li in p.loop_indices: colors.data[li].color=(*PALETTE[p.material_index],1)
    return ob
shard_body=mesh_object('ShardBody',body);shard_core=mesh_object('ShardVein',core)
def transformed(polys,k,pos,angle):
    mat=Matrix.Translation(Vector(pos))@Matrix.Rotation(angle,4,'Z')@Matrix.Scale(k,4)
    return [([mat@v for v in p],mi) for p,mi in polys]
cluster_body,cluster_core=[],[]
for k,pos,angle in [(1,(.08,.1,.13),-.10),(.55,(-.85,-.04,.12),.40),(.64,(.84,.24,.09),-.60)]:
    cluster_body+=transformed(body,k,pos,angle);cluster_core+=transformed(core,k,pos,angle)
for i,(x,y,k) in enumerate([(-.73,.39,.42),(.84,-.04,.36),(-.34,-.38,.30),(.31,-.38,.38),(.34,.58,.32)]):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=k,location=(x,y,.12))
    rock=bpy.context.object;rock.scale=(1.25,.95,.50);bpy.context.view_layer.update()
    for p in rock.data.polygons: cluster_body.append(([rock.matrix_world@rock.data.vertices[v].co for v in p.vertices],9+i%2))
    bpy.data.objects.remove(rock,do_unlink=True)
objects=[shard_body,shard_core,mesh_object('ClusterBody',cluster_body),mesh_object('ClusterVein',cluster_core)]
data={};report={}
for ob in objects:
    me=ob.data;me.calc_loop_triangles()
    data[ob.name]={'vertices':[[round(v.co.x,6),round(v.co.z,6),round(-v.co.y,6)] for v in me.vertices],
        'triangles':[[*t.vertices] for t in me.loop_triangles],
        'colors':[[*PALETTE[me.polygons[t.polygon_index].material_index]] for t in me.loop_triangles]}
    report[ob.name]={'triangles':len(me.loop_triangles),'vertices':len(me.vertices)}
report['shardTriangles']=sum(report[n]['triangles'] for n in ['ShardBody','ShardVein'])
report['clusterTriangles']=sum(report[n]['triangles'] for n in ['ClusterBody','ClusterVein'])
assert report['shardTriangles']<=200 and report['clusterTriangles']<=650,report
(OUT/'geometry.json').write_text(json.dumps(data,separators=(',',':')))
(OUT/'geometry-report.json').write_text(json.dumps(report,indent=2))
# One tiny shared color atlas: two MeshParts per model, no material splitting.
def png_chunk(kind,data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
pixels=b''.join(b'\0'+b''.join(bytes([round(c*255) for c in PALETTE[x//8]])+b'\xff' for x in range(88)) for y in range(8))
(OUT/'palette.png').write_bytes(b'\x89PNG\r\n\x1a\n'+png_chunk(b'IHDR',struct.pack('>IIBBBBB',88,8,8,6,0,0,0))+png_chunk(b'IDAT',zlib.compress(pixels))+png_chunk(b'IEND',b''))
atlas=bpy.data.images.load(str(OUT/'palette.png'))
surface=bpy.data.materials.new('Xenite Mineral');surface.use_nodes=True
bs=next(n for n in surface.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
bs.inputs['Roughness'].default_value=.36
tex=surface.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas;tex.interpolation='Closest'
surface.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
for ob in objects:
    me=ob.data;uv=me.uv_layers.new(name='PaletteUV')
    for p in me.polygons:
        for li in p.loop_indices: uv.data[li].uv=((p.material_index+.5)/11,.5)
    if not ob.name.endswith('Vein'):
        me.materials.clear();me.materials.append(surface)
        for p in me.polygons: p.material_index=0
    else:
        me.materials.clear();me.materials.append(MATS[8])
        for p in me.polygons: p.material_index=0
    # Face colors in geometry.json remain authoritative; FBX uses the palette.
    for attr in list(me.color_attributes): me.color_attributes.remove(attr)
for group,names in [('shard',['ShardBody','ShardVein']),('cluster',['ClusterBody','ClusterVein'])]:
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(ob.name in names)
    bpy.context.view_layer.objects.active=bpy.data.objects[names[0]]
    bpy.ops.export_scene.fbx(filepath=str(OUT/(group+'.fbx')),use_selection=True,object_types={'MESH'},add_leaf_bones=False,bake_anim=False,axis_forward='-Z',axis_up='Y',path_mode='COPY',embed_textures=True)
# Render the production models offline with transparent backgrounds.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32
scene.render.resolution_x=1000;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=True
scene.world.color=(.28,.28,.28)
def point_at(ob,p): ob.rotation_euler=(Vector(p)-ob.location).to_track_quat('-Z','Y').to_euler()
for pos,power,size in [((-3,-4,6),550,4),((4,-1,4),360,3),((1,4,5),650,3)]:
    bpy.ops.object.light_add(type='AREA',location=pos);l=bpy.context.object;l.data.energy=power;l.data.shape='DISK';l.data.size=size;point_at(l,(0,0,1.3))
bpy.ops.object.camera_add(location=(4,-7,4.3));camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=4.25
point_at(camera,(0,0,1.48));scene.camera=camera
for ob in objects: ob.hide_render=ob.name.startswith('Shard')
scene.render.filepath=str(OUT/'cluster-preview.png');bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'xenite.blend'));bpy.ops.render.render(write_still=True)
for ob in objects: ob.hide_render=ob.name.startswith('Cluster')
camera.data.ortho_scale=3.5;point_at(camera,(0,0,1.43));scene.render.filepath=str(OUT/'shard-preview.png');bpy.ops.render.render(write_still=True)
print('XENITE_GEOMETRY',json.dumps(report))
