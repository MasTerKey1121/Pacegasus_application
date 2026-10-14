"""Render real starter-item thumbnails and add a shirt-only glTF variant."""
import bpy, json, struct, copy
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'frontend/assets/models'
THUMBS=OUT/'items';THUMBS.mkdir(parents=True,exist_ok=True)
SOURCE=Path('C:/Users/User/.codex/visualizations/2026/09/19/01a0b9c9-449e-76a3-b522-f0b05440c573/avatar_wave_v8/pacegasus_wave_v8.blend')
raw=(OUT/'pacegasus_wave_male_v8.glb').read_bytes()
json_length=struct.unpack_from('<I',raw,12)[0]
document=json.loads(raw[20:20+json_length]);binary=raw[20+json_length:]
colors={'starter_tee_white':(.92,.92,.92,1), 'shop_tee_purple':(.30,.075,.52,1), 'shop_tee_brown':(.24,.105,.045,1)}
def add_variants(raw, target):
    length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length]);bin_chunk=raw[20+length:]
    ext='KHR_materials_variants';doc.setdefault('extensionsUsed',[]).append(ext)
    doc.setdefault('extensions',{})[ext]={'variants':[{'name':name} for name in colors]}
    node=next(n for n in doc['nodes'] if n.get('name')=='Top_RunningTee');changed=[]
    for p in doc['meshes'][node['mesh']]['primitives']:
        original=doc['materials'][p['material']]
        if 'gold' in original['name'].lower():continue
        mappings=[]
        for vi,(name,color) in enumerate(colors.items()):
            material=copy.deepcopy(original);material['name']=name+' / '+original['name']
            value=list(color)
            if 'seams' in original['name']:value=[c*.78 for c in value[:3]]+[1]
            material['pbrMetallicRoughness']['baseColorFactor']=value
            index=len(doc['materials']);doc['materials'].append(material);mappings.append({'material':index,'variants':[vi]})
        p.setdefault('extensions',{})[ext]={'mappings':mappings};changed.append(original['name'])
    assert len(changed)==2,changed
    encoded=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    output=struct.pack('<III',0x46546C67,2,20+len(encoded)+len(bin_chunk))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+bin_chunk
    target.write_bytes(output);return len(output)
output_size=add_variants(raw,OUT/'pacegasus_starter_v9.glb')
assert binary==raw[20+json_length:] # Geometry, skin weights and animations unchanged.
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),load_ui=False)
scene=bpy.context.scene;rig=bpy.data.objects['Pacegasus_Rig'];rig.animation_data.action=bpy.data.actions['Idle_Loop'];scene.frame_set(1)
objects=[o for o in scene.objects if o.type=='MESH']
for o in scene.objects:
    if o.type in ('LIGHT','CAMERA'):o.hide_set(False)
groups={
 'starter_hair':['Hair_Male_Swept'],
 'starter_face':['Base_Head','Base_Ear.L','Base_Ear.R','Face_Eye.L','Face_Eye.R','Face_Nose','Face_Brow.L','Face_Brow.R','Face_ClosedSmile'],
 'starter_tee_black':['Top_RunningTee'],
 'starter_tee_white':['Top_RunningTee'],
 'shop_tee_purple':['Top_RunningTee'],
 'shop_tee_brown':['Top_RunningTee'],
 'starter_shorts':['Bottom_RunningShorts'],
 'starter_socks':['Socks.L','Socks.R'],
 'starter_shoes':['Shoes_Running.L','Shoes_Running.R'],
}
scene.render.resolution_x=384;scene.render.resolution_y=384;scene.render.resolution_percentage=100
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.cycles.samples=24
shirt=bpy.data.objects['Top_RunningTee'];original_materials=list(shirt.data.materials)
for code,names in groups.items():
    for o in objects:o.hide_render=o.name not in names;o.hide_set(o.name not in names)
    for i,material in enumerate(original_materials):
        shirt.data.materials[i]=material
        if code in colors and 'gold' not in material.name.lower():
            new=material.copy();new.name='Thumbnail '+code+' '+material.name
            color=colors[code]
            if 'seams' in material.name:color=tuple(c*.78 for c in color[:3])+(1,)
            new.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=color
            shirt.data.materials[i]=new
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    points=[]
    for name in names:
        o=bpy.data.objects[name];e=o.evaluated_get(deps);m=e.to_mesh();points.extend(e.matrix_world @ v.co for v in m.vertices);e.to_mesh_clear()
    low=Vector([min(v[i] for v in points) for i in range(3)]);high=Vector([max(v[i] for v in points) for i in range(3)]);center=(low+high)/2
    camera=scene.camera;camera.location=center+Vector((2,-10,2.5) if code=='starter_shoes' else (0,-10,1))
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=max(high-low)*1.3
    scene.render.filepath=str(THUMBS/(code+'.png'));bpy.ops.render.render(write_still=True)
for i,m in enumerate(original_materials):shirt.data.materials[i]=m
shirt.hide_set(False);bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
data=bpy.data.meshes.new_from_object(shirt.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
points=[shirt.matrix_world @ v.co for v in data.vertices]
center=Vector([(min(v[i] for v in points)+max(v[i] for v in points))/2 for i in range(3)])
for v,p in zip(data.vertices,points):v.co=p-center
product=bpy.data.objects.new('Product export',data);scene.collection.objects.link(product)
shirt.name='Source shirt';product.name='Top_RunningTee'
for o in scene.objects:o.select_set(False)
product.select_set(True);bpy.context.view_layer.objects.active=product
path=OUT/'product_running_tee.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False)
add_variants(path.read_bytes(),path)
print('STARTER_ASSETS_COMPLETE',len(groups),output_size,path.stat().st_size)
