"""Fit the approved ponytail to the existing avatar, without changing its face.

Exports standalone hair and both animated avatar combinations. Source blends
remain untouched. Run in Blender background mode.
"""
import bpy, math, json, struct, copy, shutil, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

def render_preview():
    if '--no-renders' not in sys.argv:
        bpy.ops.render.render(write_still=True)

ROOT=Path(__file__).resolve().parents[2]
ART=Path('C:/Users/User/.codex/visualizations/2026/09/19/01a0b9c9-449e-76a3-b522-f0b05440c573')
OUT=ART/'female_ponytail_v1';OUT.mkdir(parents=True,exist_ok=True)
ASSETS=ROOT/'frontend/assets/models'
bpy.ops.wm.open_mainfile(filepath=str(ART/'avatar_wave_v8/pacegasus_wave_v8.blend'),load_ui=False)
scene=bpy.context.scene;rig=bpy.data.objects['Pacegasus_Rig']
rig.animation_data.action=None
for bone in rig.pose.bones:bone.matrix_basis.identity()
bpy.context.view_layer.update()
head=bpy.data.objects['Base_Head'];deps=bpy.context.evaluated_depsgraph_get()
evaluated=head.evaluated_get(deps);headmesh=evaluated.to_mesh()
points=[evaluated.matrix_world@v.co for v in headmesh.vertices]
faces=[list(p.vertices) for p in headmesh.polygons]
bvh=BVHTree.FromPolygons(points,faces)
center=Vector([(min(v[i] for v in points)+max(v[i] for v in points))/2 for i in range(3)])
evaluated.to_mesh_clear()
print('HEAD_CENTER',tuple(center),flush=True)

def mat(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    shader=m.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.58
    return m

brown=mat('Ponytail chestnut',(.16,.060,.027))
highlight=mat('Ponytail warm ridges',(.195,.080,.037))
tie_mat=mat('Ponytail dark brown tie',(.050,.021,.012))
hair=[]

def surface(direction,offset=.045):
    p,n,_,_=bvh.ray_cast(center,Vector(direction).normalized(),3)
    assert p is not None
    return p+Vector(direction).normalized()*offset

def make_mesh(name,verts,faces,material):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj)
    mesh.materials.append(material)
    for poly in mesh.polygons:poly.use_smooth=True
    hair.append(obj);return obj

# Scalp is sampled directly from the actual head, not a generic sphere.
verts=[];faces=[];rings=40;segments=128
for j in range(rings+1):
    for k in range(segments):
        phi=2*math.pi*k/segments
        front=max(0,math.cos(phi))
        # Lower the temple edge to the top of each ear, not a high cut-out.
        ear_notch=.27*math.exp(-((abs(math.sin(phi))-1)/.07)**2)
        limit=1.92-.94*front**1.7-ear_notch
        theta=.008+(limit-.008)*j/rings
        direction=(math.sin(theta)*math.sin(phi),-math.sin(theta)*math.cos(phi),math.cos(theta))
        ray=Vector(direction)
        knot_axis=Vector((0,.65,.76)).normalized()
        flow_phi=math.atan2(ray.dot(knot_axis.cross(Vector((1,0,0)))),ray.x)
        offset=.035+.012*(1+math.cos(flow_phi*18))
        verts.append(tuple(surface(direction,offset)))
for j in range(rings):
    for k in range(segments):
        a=j*segments+k;b=j*segments+(k+1)%segments
        faces.append((a,a+segments,b+segments,b))
cap=make_mesh('Ponytail scalp fitted to Base_Head',verts,faces,brown)
solid=cap.modifiers.new('Scalp thickness','SOLIDIFY');solid.thickness=.025;solid.offset=1
bpy.context.view_layer.objects.active=cap
bpy.ops.object.modifier_apply(modifier=solid.name)

def catmull(points,t):
    n=len(points)-1;x=t*n;i=min(int(x),n-1);u=x-i
    p0=points[max(0,i-1)];p1=points[i];p2=points[i+1];p3=points[min(n,i+2)]
    return .5*((2*p1)+(-p0+p2)*u+(2*p0-5*p1+4*p2-p3)*u*u+(-p0+3*p1-3*p2+p3)*u*u*u)

def strand(name,path,width,depth,material= brown,taper=True,steps=48,root_taper=False):
    path=list(map(Vector,path));vertices=[];polys=[];ring=12
    for j in range(steps+1):
        t=j/steps;p=catmull(path,t)
        tangent=(catmull(path,min(1,t+.001))-catmull(path,max(0,t-.001))).normalized()
        axis=Vector((1,0,0));axis=(axis-tangent*axis.dot(tangent)).normalized()
        if name.startswith('Ponytail face frame'):
            axis=Vector((-tangent.z,0,tangent.x)).normalized()
        normal=tangent.cross(axis).normalized()
        profile=(.55+.45*math.sin(math.pi*t))*(max(.035,(1-t)**.38) if taper else 1)
        if root_taper:profile*=min(1,.04+t*12)*min(1,.04+(1-t)*12)
        for k in range(ring):
            a=2*math.pi*k/ring
            # Broad sculpted locks with shallow flowing longitudinal channels.
            groove=1+.055*math.cos(a*5)
            vertices.append(tuple(p+axis*(math.cos(a)*width*profile*groove)+normal*(math.sin(a)*depth*profile)))
    for j in range(steps):
        for k in range(ring):
            a=j*ring+k;b=j*ring+(k+1)%ring
            polys.append((a,b,b+ring,a+ring))
    polys.extend([tuple(reversed(range(ring))),tuple(steps*ring+k for k in range(ring))])
    return make_mesh(name,vertices,polys,material)

# Swept crown ridges are sculpted into the continuous cap above, so they
# cannot look like floating ropes or expose chopped-off strand ends.

# High tie and a swept ponytail well behind the back of the oversized head.
tie_center=surface((0,.65,.76),.12)
print('TIE_CENTER',tuple(tie_center),flush=True)
for i in range(7):
    offset=(i-3)*.083
    start=tie_center+Vector((offset*.45,.05,.015))
    path=[start,start+Vector((offset*.5,.28,.27)),
          Vector((offset*1.12,1.40,3.98)),
          Vector((offset*1.18,1.57,3.38)),
          Vector((offset*.85+.035,1.62,2.80)),
          Vector((offset*.65+.055,1.69,2.37-abs(i-3)*.055))]
    strand('Ponytail flowing lock %02d'%i,path,.115,.23,
           highlight if i in [1,5] else brown,True)

# Face-framing locks track outside cheeks; never across eyes or nose.
for side in [-1,1]:
    path=[Vector((side*.025,-.81,3.68)),Vector((side*.30,-.87,3.84)),
          Vector((side*.65,-.86,3.72)),Vector((side*.88,-.76,3.24)),
          Vector((side*.86,-.84,2.85)),Vector((side*.77,-.82,2.62))]
    strand('Ponytail face frame '+str(side),path,.145,.08,brown,True,64,True)

bpy.ops.mesh.primitive_torus_add(major_radius=.235,minor_radius=.045,
    major_segments=40,minor_segments=10,location=tie_center)
tie=bpy.context.object;tie.name='Ponytail tie';tie.rotation_euler=(math.pi/2-.35,0,0)
tie.data.materials.append(tie_mat);hair.append(tie)
for p in tie.data.polygons:p.use_smooth=True
bpy.ops.object.select_all(action='DESELECT')
for obj in hair:obj.select_set(True)
bpy.context.view_layer.objects.active=cap;bpy.ops.object.join()
hair_obj=bpy.context.object;hair_obj.name='Hair_Female_Ponytail'

# Project any buried strand vertices outside the actual head/ears. This also
# corrects chords between sampled scalp points without guessing head radii.
collision_trees=[bvh]
for _ in range(3):
    for vertex in hair_obj.data.vertices:
        for tree in collision_trees:
            p,n,_,distance=tree.find_nearest(vertex.co)
            if p is not None and (vertex.co-p).dot(n)<.024:
                vertex.co=p+n*.026
hair_obj.data.update()

# Store wearable-only source, then bind its unchanged rest geometry to Head.
library=OUT/'ponytail_library.blend'
bpy.data.libraries.write(str(library),{hair_obj})
bpy.ops.export_scene.gltf(filepath=str(OUT/'female_ponytail.glb'),export_format='GLB',use_selection=True,export_animations=False)
shutil.copyfile(OUT/'female_ponytail.glb',ASSETS/'female_ponytail.glb')

def bind(obj,armature):
    group=obj.vertex_groups.new(name='Head');group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    modifier=obj.modifiers.new('Follow existing Head bone','ARMATURE');modifier.object=armature
    obj.parent=armature

def remove_old_hair():
    old=bpy.data.objects.get('Hair_Male_Swept')
    if old:bpy.data.objects.remove(old,do_unlink=True)

def variants(path):
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]);binary=raw[20+length:]
    ext='KHR_materials_variants';doc.setdefault('extensionsUsed',[]).append(ext)
    colors={'starter_tee_white':(.92,.92,.92,1),'shop_tee_purple':(.30,.075,.52,1),'shop_tee_brown':(.24,.105,.045,1)}
    doc.setdefault('extensions',{})[ext]={'variants':[{'name':n} for n in colors]}
    node=next(n for n in doc['nodes'] if n.get('name')=='Top_RunningTee')
    for primitive in doc['meshes'][node['mesh']]['primitives']:
        original=doc['materials'][primitive['material']]
        if 'gold' in original['name'].lower():continue
        mappings=[]
        for vi,(name,color) in enumerate(colors.items()):
            material=copy.deepcopy(original);material['name']=name+' / '+original['name']
            material['pbrMetallicRoughness']['baseColorFactor']=[c*.78 for c in color[:3]]+[1] if 'seams' in original['name'] else list(color)
            index=len(doc['materials']);doc['materials'].append(material)
            mappings.append({'material':index,'variants':[vi]})
        primitive.setdefault('extensions',{})[ext]={'mappings':mappings}
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546C67,2,20+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+binary)

def export_avatar(name):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.context.scene.objects:
        if obj.type in ['MESH','ARMATURE']:obj.select_set(True)
    target=OUT/name
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,
        export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True)
    variants(target);shutil.copyfile(target,ASSETS/name)

remove_old_hair();bind(hair_obj,rig)
rig.animation_data.action=bpy.data.actions['Idle_Loop'];scene.frame_set(1)
scene.render.resolution_x=1000;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.cycles.samples=24;scene.render.film_transparent=False
camera=scene.camera;camera.data.type='ORTHO';camera.data.ortho_scale=5.0
focus=Vector((0,.35,2.2))
for name,location in [('front',(0,-10,2.8)),('side',(10,0,2.8)),('back',(0,10,2.8))]:
    camera.location=location;camera.rotation_euler=(focus-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/('fit_'+name+'.png'));render_preview()
visibility={o.name:o.hide_render for o in scene.objects if o.type=='MESH'}
for obj in scene.objects:
    if obj.type=='MESH':obj.hide_render=obj!=hair_obj
scene.render.resolution_x=384;scene.render.resolution_y=384;scene.render.film_transparent=True
camera.location=(0,-10,3.4);focus=Vector((0,.35,3.25))
camera.rotation_euler=(focus-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=3.2
scene.render.filepath=str(ASSETS/'items/starter_hair_female.png');render_preview()
for name,hidden in visibility.items():bpy.data.objects[name].hide_render=hidden
scene.render.film_transparent=False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'female_ponytail_fitted.blend'))
export_avatar('pacegasus_female_ponytail.glb')

# Validate fitted meshes against face, ears, torso and hands at rest/greeting.
report=[]
for action_name,frames in [('Idle_Loop',[1,20,40]),('Wave_Greeting',[1,15,30,45,60])]:
    rig.animation_data.action=bpy.data.actions[action_name]
    for frame in frames:
        scene.frame_set(frame);bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
        def tree(obj):
            evaluated=obj.evaluated_get(deps);mesh=evaluated.to_mesh()
            tree=BVHTree.FromPolygons([evaluated.matrix_world@v.co for v in mesh.vertices],[list(p.vertices) for p in mesh.polygons])
            evaluated.to_mesh_clear();return tree
        htree=tree(hair_obj)
        hits={}
        for name in ['Base_Head','Base_Ear.L','Base_Ear.R','Top_RunningTee','Base_ArmHand.L','Base_ArmHand.R']:
            obj=bpy.data.objects.get(name)
            if obj:hits[name]=len(htree.overlap(tree(obj)))
        report.append({'action':action_name,'frame':frame,'intersections':hits})
(OUT/'fit_report.json').write_text(json.dumps(report,indent=2))

# Preserve compatibility with the already purchasable back accessory.
bpy.ops.wm.open_mainfile(filepath=str(ART/'golden_wings_v2/pacegasus_golden_wings.blend'),load_ui=False)
scene=bpy.context.scene;rig=bpy.data.objects['Pacegasus_Rig'];remove_old_hair()
with bpy.data.libraries.load(str(library),link=False) as (src,dst):dst.objects=['Hair_Female_Ponytail']
obj=dst.objects[0];scene.collection.objects.link(obj);bind(obj,rig)
rig.animation_data.action=bpy.data.actions['Idle_Loop'];scene.frame_set(1)
export_avatar('pacegasus_female_ponytail_wings.glb')
print('FEMALE_PONYTAIL_COMPLETE',OUT,flush=True)
