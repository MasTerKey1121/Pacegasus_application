"""Connect feather layers and fit a rigid, spine-weighted accessory to v8.

Approval source stays unchanged; generated GLBs are bundled for the shop.
"""
import bpy
from pathlib import Path
from mathutils import Vector
import json, struct, copy, sys

def render_preview():
    if '--no-renders' not in sys.argv:
        bpy.ops.render.render(write_still=True)

ROOT = Path(__file__).resolve().parents[2]
ART = Path('C:/Users/User/.codex/visualizations/2026/09/19/01a0b9c9-449e-76a3-b522-f0b05440c573')
OUT = ART / 'golden_wings_v2'
OUT.mkdir(parents=True, exist_ok=True)
ASSETS = ROOT / 'frontend/assets/models'
bpy.ops.wm.open_mainfile(filepath=str(ART / 'golden_wings_v1/golden_wings_v1.blend'))
wings = [o for o in bpy.context.scene.objects if o.name.startswith('Golden_Wing.')]
for obj in wings:
    bpy.ops.object.select_all(action='DESELECT')
    # Continuous hidden spar runs through every feather root, including the
    # three overlapping rows. It is fused into the final watertight geometry.
    side = -1 if obj.name.endswith('L') else 1
    curve = bpy.data.curves.new('Continuous feather spar', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = .15
    curve.bevel_resolution = 3
    spline = curve.splines.new('POLY')
    roots = [(1,1.12),(.99,1.02),(.96,.91),(.90,.79),(.83,.66),(.74,.53),(.64,.43),(.54,.35),(.44,.30),(.34,.28),(.27,.29),(.24,.35)]
    spline.points.add(len(roots)-1)
    for point,(x,z) in zip(spline.points,roots):
        point.co = (side*x,.015,z,1)
    spar = bpy.data.objects.new('Hidden root connection',curve)
    bpy.context.collection.objects.link(spar)
    spar.select_set(True)
    bpy.context.view_layer.objects.active=spar
    bpy.ops.object.convert(target='MESH')
    obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.join()
    # Union real surfaces, not just a collection of floating/intersecting parts.
    obj.data.remesh_voxel_size=.018
    bpy.ops.object.voxel_remesh()
    smooth=obj.modifiers.new('Soften union','SMOOTH');smooth.factor=.5;smooth.iterations=2
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    dec=obj.modifiers.new('Mobile geometry','DECIMATE');dec.ratio=.38
    bpy.ops.object.modifier_apply(modifier=dec.name)
    obj.data.materials.clear()
    obj.data.materials.append(bpy.data.materials['Warm yellow gold'])
    for p in obj.data.polygons:p.use_smooth=True
    # Count connected components; retain only substantial connected wing.
    adjacency=[[] for _ in obj.data.vertices]
    for e in obj.data.edges:
        a,b=e.vertices;adjacency[a].append(b);adjacency[b].append(a)
    remaining=set(range(len(adjacency)));components=[]
    while remaining:
        seed=remaining.pop();component={seed};stack=[seed]
        while stack:
            for n in adjacency[stack.pop()]:
                if n in remaining:remaining.remove(n);component.add(n);stack.append(n)
        components.append(component)
    print('WING_COMPONENTS',obj.name,sorted(map(len,components),reverse=True))
    # Tiny detached ridge voxels are not part of the accessory.
    largest=max(components,key=len)
    import bmesh
    bm=bmesh.new();bm.from_mesh(obj.data);bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in largest],context='VERTS')
    bm.to_mesh(obj.data);bm.free()

bpy.ops.object.select_all(action='DESELECT')
for obj in wings:obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'product_golden_wings.glb'),export_format='GLB',use_selection=True,export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'golden_wings_connected.blend'))
scene=bpy.context.scene
scene.cycles.samples=24
scene.render.filepath=str(OUT/'golden_wings_connected.png')
render_preview()
scene.render.resolution_x=384;scene.render.resolution_y=384
scene.render.film_transparent=True
scene.camera.data.ortho_scale=7
for obj in scene.objects:
    if obj.name.startswith('Preview backdrop'):obj.hide_render=True
scene.render.filepath=str(ASSETS/'items/shop_golden_wings.png')
render_preview()

# Transfer connected geometry into the original rig scene, not a new lookalike.
wing_data=[(o.name,o.data.copy()) for o in wings]
source=ART/'avatar_wave_v8/pacegasus_wave_v8.blend'
# Save connected objects to an appendable library before changing scenes.
library=OUT/'connected_wings_library.blend'
bpy.data.libraries.write(str(library),set(wings))
bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False)
rig=bpy.data.objects['Pacegasus_Rig']
print('RIG_BONES',[(b.name,tuple(b.head_local)) for b in rig.data.bones])
print('BODY_BOUNDS',[(o.name,tuple(o.dimensions),tuple(o.location)) for o in bpy.context.scene.objects if o.type=='MESH' and o.name in ['Base_Head','Top_RunningTee','Base_Body']])
with bpy.data.libraries.load(str(library),link=False) as (src,dst):
    dst.objects=[name for name in src.objects if name.startswith('Golden_Wing.')]
bone=rig.data.bones.get('Attach_Back')
assert bone is not None,'Inspect chest/spine attachment bone'
for obj in dst.objects:
    bpy.context.collection.objects.link(obj)
    # 1.25 times the previous .46 fit, scaled around each root.
    # Keep the requested upper-back attachment position unchanged.
    side = -1 if obj.name.endswith('L') else 1
    for v in obj.data.vertices:
        p=v.co.copy()
        v.co=((p.x-side*.24)*.575+side*.11,
              .56-p.y*.575, 1.93+(p.z-.30)*.575)
    obj.location=(0,0,0)
    obj.rotation_euler=(0,0,0)
    obj.scale=(1,1,1)
    group=obj.vertex_groups.new(name=bone.name)
    group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    modifier=obj.modifiers.new('Follow upper spine','ARMATURE');modifier.object=rig
    obj.parent=rig
    obj['slot']='back';obj['item_code']='shop_golden_wings'
rig.animation_data.action=bpy.data.actions['Idle_Loop']
bpy.context.scene.frame_set(1)
scene=bpy.context.scene
scene.render.resolution_x=1200;scene.render.resolution_y=1200
scene.render.resolution_percentage=100;scene.cycles.samples=24
scene.render.film_transparent=False
camera=scene.camera
center=Vector((0,0,2.2))
camera.data.type='ORTHO';camera.data.ortho_scale=4.7
for name,location in [('avatar_front',(0,-10,2.6)),('avatar_back',(0,10,2.6)),('avatar_side',(8,5,2.6))]:
    camera.location=location;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/(name+'.png'))
    render_preview()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'pacegasus_golden_wings.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in scene.objects:
    if obj.type in ['MESH','ARMATURE']:obj.select_set(True)
target=OUT/'pacegasus_golden_wings_export.glb'
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True)

# Preserve every shirt color choice on the combined rig as on the base GLB.
raw=target.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
doc=json.loads(raw[20:20+length]);binary=raw[20+length:]
ext='KHR_materials_variants'
doc.setdefault('extensionsUsed',[]).append(ext)
colors={'starter_tee_white':(.92,.92,.92,1),'shop_tee_purple':(.30,.075,.52,1),'shop_tee_brown':(.24,.105,.045,1)}
doc.setdefault('extensions',{})[ext]={'variants':[{'name':n} for n in colors]}
node=next(n for n in doc['nodes'] if n.get('name')=='Top_RunningTee')
for primitive in doc['meshes'][node['mesh']]['primitives']:
    original=doc['materials'][primitive['material']]
    if 'gold' in original['name'].lower():continue
    mappings=[]
    for vi,(name,color) in enumerate(colors.items()):
        mat=copy.deepcopy(original);mat['name']=name+' / '+original['name']
        mat['pbrMetallicRoughness']['baseColorFactor']=[c*.78 for c in color[:3]]+[1] if 'seams' in original['name'] else list(color)
        index=len(doc['materials']);doc['materials'].append(mat)
        mappings.append({'material':index,'variants':[vi]})
    primitive.setdefault('extensions',{})[ext]={'mappings':mappings}
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
target.write_bytes(struct.pack('<III',0x46546C67,2,20+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+binary)
import shutil
shutil.copyfile(target, ASSETS/'pacegasus_golden_wings.glb')
print('WINGS_FIT_COMPLETE',target,[(a['name']) for a in doc.get('animations',[])])
