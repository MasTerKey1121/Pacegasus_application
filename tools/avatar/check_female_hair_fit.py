"""Repeatable BVH intersection audit on the fitted Blender source."""
import bpy, json
from pathlib import Path
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
ART=Path('C:/Users/User/.codex/visualizations/2026/09/19/01a0b9c9-449e-76a3-b522-f0b05440c573/female_ponytail_v1')
bpy.ops.wm.open_mainfile(filepath=str(ART/'female_ponytail_fitted.blend'),load_ui=False)
scene=bpy.context.scene;rig=bpy.data.objects['Pacegasus_Rig']
hair=bpy.data.objects['Hair_Female_Ponytail']
names=['Base_Head','Base_Ear.L','Base_Ear.R','Top_RunningTee',
       'Visible_ArmHand.L','Visible_ArmHand.R','Face_Eye.L','Face_Eye.R','Face_Nose']
assert all(bpy.data.objects.get(name) for name in names)
report=[]
for action_name in ['Idle_Loop','Wave_Greeting']:
    action=bpy.data.actions[action_name];rig.animation_data.action=action
    start,end=action.frame_range
    for index in range(13):
        frame=start+(end-start)*index/12;scene.frame_set(int(frame),subframe=frame-int(frame))
        bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
        def tree(obj):
            e=obj.evaluated_get(deps);m=e.to_mesh()
            result=BVHTree.FromPolygons([e.matrix_world@v.co for v in m.vertices],[list(p.vertices) for p in m.polygons])
            e.to_mesh_clear();return result
        htree=tree(hair)
        hits={name:len(htree.overlap(tree(bpy.data.objects[name]))) for name in names}
        if any(hits.values()):
            e=hair.evaluated_get(deps);m=e.to_mesh()
            pairs=htree.overlap(tree(bpy.data.objects['Visible_ArmHand.R']))
            points=[e.matrix_world@m.polygons[a].center for a,b in pairs]
            print('COLLISION_BOUNDS',frame,[(min(p[i] for p in points),max(p[i] for p in points)) for i in range(3)],flush=True)
            e.to_mesh_clear()
        report.append({'action':action_name,'frame':round(frame,2),'intersections':hits})
target=ROOT/'tools/avatar/reports/female_ponytail_fit.json';target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(json.dumps(report,indent=2))
print('HAIR_FIT_AUDIT',len(report),'samples',max(max(r['intersections'].values()) for r in report),'maximum intersections',flush=True)
assert all(not any(r['intersections'].values()) for r in report),'Inspect fit report for collisions'
