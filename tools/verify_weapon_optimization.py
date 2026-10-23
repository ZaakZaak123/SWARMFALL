"""Blender CPU render comparisons plus FBX round-trip checks, no external modules."""
import bpy,json,numpy as np
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'production/weapons/optimized'
report={}
for w,expected in [('W01',4134),('W02',4376)]:
    result={}
    for view in ('hero','side'):
        images=[]
        for state in ('before','after'):
            img=bpy.data.images.load(str(root/w/(view+'_'+state+'.png')),check_existing=False)
            pixels=np.empty(img.size[0]*img.size[1]*4,dtype=np.float32);img.pixels.foreach_get(pixels)
            images.append(pixels.reshape(img.size[1],img.size[0],4));bpy.data.images.remove(img)
        a,b=images;ma=a[:,:,3]>.5;mb=b[:,:,3]>.5;union=ma|mb
        result[view]={'silhouette_iou':float((ma&mb).sum()/union.sum()),'mean_rgb_difference_0_to_1':float(np.abs(a[:,:,:3]-b[:,:,:3])[union].mean())}
        assert result[view]['silhouette_iou']>.98,(w,view,result[view])
        pair=np.concatenate(images,axis=1)
        image=bpy.data.images.new(w+' '+view+' original left optimized right',width=pair.shape[1],height=pair.shape[0],alpha=True)
        image.pixels.foreach_set(pair.ravel());image.filepath_raw=str(root/w/(view+'_comparison.png'));image.file_format='PNG';image.save();bpy.data.images.remove(image)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(root/w/(w+'_optimized.fbx')))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    for o in meshes:o.data.calc_loop_triangles()
    count=sum(len(o.data.loop_triangles) for o in meshes)
    assert count==expected,(w,count,expected)
    assert len(meshes)==(6 if w=='W01' else 8)
    result['roundtrip']={'meshes':len(meshes),'triangles':count}
    report[w]=result
(root/'verification.json').write_text(json.dumps(report,indent=2))
print('VERIFICATION='+json.dumps(report))
