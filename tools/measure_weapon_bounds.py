"""Recompute original/optimized world-space bounds for exact Studio registration."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
sources={'W01':root/'production/weapons/W01/assets/W01_arc_rifle_redesign.blend',
         'W02':root/'production/weapons/W02/W02_vulcan.blend'}
ids=sys.argv[sys.argv.index('--')+1:]
for weapon in ids:
    folder=root/'production/weapons/optimized'/weapon
    entries={}
    for prefix,path in [('original',sources[weapon]),('optimized',folder/(weapon+'_optimized.blend'))]:
        bpy.ops.wm.open_mainfile(filepath=str(path))
        for ob in bpy.context.view_layer.objects:
            if ob.type!='MESH':continue
            if weapon=='W01' and (not ob.name.startswith('W01_mesh_') or ob.name.endswith('.001')):continue
            if weapon=='W02' and ob.name not in ('Chassis','Armor','Steel','Rubber','Pump','PumpRibs','Brass','Indicators'):continue
            vertices=[ob.matrix_world@v.co for v in ob.data.vertices]
            lo=Vector(tuple(min(v[i] for v in vertices) for i in range(3)))
            hi=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
            entry=entries.setdefault(ob.name,{'name':ob.name})
            entry[prefix+'_center']=list((lo+hi)/2)
            entry[prefix+'_size']=list(hi-lo)
    assert len(entries)==(6 if weapon=='W01' else 8)
    (folder/'bounds.json').write_text(json.dumps(list(entries.values()),indent=2))
    print('BOUNDS',weapon)
