"""Build the editable, modular Pacegasus prototype. Run with Blender --background --python.

No external Python packages. Source geometry is intentionally simple; this is not
an automatic reconstruction of the approved concept art.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'frontend/assets/models'
ART = ROOT / 'output/avatar'
OUT.mkdir(parents=True, exist_ok=True)
ART.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=.65):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


skin = material('Skin', (.72, .365, .18))
hair = material('Hair', (.034, .023, .02))
eye = material('Eyes', (.008, .006, .005), .24)
mouth = material('Smile', (.23, .062, .029))
shirt = material('Shirt', (.026, .03, .038))
shorts = material('Shorts', (.019, .022, .03))
gold = material('Pacegasus_Gold', (.73, .46, .12), .5)
white = material('Shoes_White', (.86, .87, .85))
sole = material('Soles', (.25, .27, .29))


def group(name, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    return obj


root = group('AvatarRoot')
upper = group('UpperBody', root, (0, 0, 1.0))
head = group('Head', upper, (0, 0, 1.04))
hair_slot = group('Slot_Hair', head)
top_slot = group('Slot_Top', upper)
bottom_slot = group('Slot_Bottom', root)
shoe_slot = group('Slot_Shoes', root)
stage_slot = group('Slot_Stage', root)
group('Socket_Back', upper, (0, .25, .35))
group('Socket_Hand_L', upper, (-.59, -.03, -.03))
group('Socket_Hand_R', upper, (.59, -.03, -.03))


def finish(obj, name, mat, parent):
    obj.name = name
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    obj.parent = parent
    return obj


def ball(name, pos, scale, mat, parent, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16)
    obj = bpy.context.object
    obj.location = pos
    obj.scale = scale
    obj.rotation_euler = rotation
    return finish(obj, name, mat, parent)


def tube(name, points, radius, mat, parent):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    poly = curve.splines.new('POLY')
    poly.points.add(len(points) - 1)
    for point, xyz in zip(poly.points, points):
        point.co = (*xyz, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.parent = parent
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    return obj


ball('Body_Base', (0, 0, .18), (.315, .205, .43), skin, upper)
ball('Neck', (0, 0, .60), (.14, .13, .17), skin, upper)
ball('Head_Base', (0, 0, 0), (.595, .43, .555), skin, head)
for sign, side in [(-1, 'L'), (1, 'R')]:
    ball('Ear_' + side, (sign * .579, 0, -.015), (.10, .09, .145), skin, head)
    ball('Arm_' + side, (sign * .431, 0, .19), (.105, .12, .32), skin, upper,
         (0, -sign * .36, 0))
    ball('Hand_' + side, (sign * .55, -.016, -.062), (.108, .11, .13), skin, upper)
    ball('Thumb_' + side, (sign * .492, -.091, -.055), (.048, .048, .073), skin, upper)
    ball('Leg_' + side, (sign * .174, 0, .54), (.13, .145, .32), skin, root)
    ball('Sock_' + side, (sign * .174, -.005, .267), (.132, .144, .12), white, shoe_slot)
    ball('Sole_' + side, (sign * .174, -.09, .082), (.158, .251, .07), sole, shoe_slot)
    ball('Midsole_' + side, (sign * .174, -.105, .111), (.162, .25, .058), white, shoe_slot)
    ball('Shoe_' + side, (sign * .174, -.10, .17), (.149, .231, .103), white, shoe_slot)
    for j in range(3):
        y = -.20 + j * .038
        tube('Lace_' + side + str(j), [(sign*.174-.075, y, .25),
             (sign*.174, y-.01, .267), (sign*.174+.075, y, .25)], .009, white, shoe_slot)
    ball('Heel_Gold_' + side, (sign * .174, .108, .205), (.058, .016, .07), gold, shoe_slot)
    ball('Eye_' + side, (sign * .213, -.398, .061), (.063, .034, .083), eye, head)
    # Sculpted, gently arched brows (inner ends are not raised in a worried pose).
    points = []
    for j in range(17):
        t = j / 16
        x = sign * (.13 + .16*t)
        points.append((x, -.375, .222 + .022*math.sin(math.pi*t)))
    tube('Brow_' + side, points, .023, hair, head)

ball('Nose', (0, -.439, -.035), (.058, .065, .066), skin, head)
tube('Closed_Smile', [(x, -.418 + .012*(x/.16)**2,
     -.187 + .062*(x/.16)**2) for x in [(-.16 + i*.01) for i in range(33)]],
     .009, mouth, head)

# Hair cap plus overlapping swept locks. All parts belong to one replaceable slot.
ball('Hair_Cap', (0, .058, .238), (.591, .419, .383), hair, hair_slot)
for i, (x, z, angle, size) in enumerate([
    (-.40, .31, -.50, .22), (-.22, .43, -.75, .27),
    (.015, .47, -.8, .29), (.25, .44, -.6, .25), (.44, .30, .2, .20),
    (-.27, .32, -.85, .28), (.00, .37, -.75, .30), (.23, .35, -.55, .25),
]):
    ball('Hair_Lock_' + str(i), (x, -.24, z), (.125, .14, size), hair, hair_slot,
         (0, angle, .05))


def ring_mesh(name, levels, mat, parent, n=48):
    vertices, faces = [], []
    for z, width, depth in levels:
        for i in range(n):
            a = 2 * math.pi*i/n
            vertices.append((width*math.cos(a), depth*math.sin(a), z))
    for row in range(len(levels)-1):
        for i in range(n):
            a = row*n+i
            b = row*n+(i+1)%n
            faces.append((a, b, b+n, a+n))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, parent)


# Tank top: elliptical rings terminate at a shaped neck opening, with open sides
# below the shoulders. No shirt fused into skin.
top = ring_mesh('Top_Starter', [(-.08, .334, .222), (.0, .329, .225),
    (.28, .301, .219), (.43, .303, .198)], shirt, top_slot)
# Shape the neckline and armholes rather than using a straight cylinder rim.
for i in range(48):
    a = 2*math.pi*i/48
    side = abs(math.cos(a))
    top.data.vertices[144+i].co.z = .40 + .13*math.exp(-((side-.70)/.20)**2) - .07*side**12
for sign in (-1, 1):
    vertices, faces = [], []
    for j in range(13):
        y = -.145 + j*.29/12
        z = .519 + .016*math.cos(y/.145*math.pi/2)
        vertices.extend([(sign*.165,y,z), (sign*.272,y,z)])
    for j in range(12):
        faces.append((j*2,j*2+1,j*2+3,j*2+2))
    mesh = bpy.data.meshes.new('Shoulder_Strap')
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new('Top_Strap_' + str(sign), mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj,obj.name,shirt,top_slot)
    solid = obj.modifiers.new('Fabric_Thickness','SOLIDIFY')
    solid.thickness = .008
ring_mesh('Shorts_Waist', [(.76,.329,.183),(.85,.329,.193),(.94,.327,.186)],shorts,bottom_slot)
for sign, side in [(-1, 'L'), (1, 'R')]:
    leg = ring_mesh('Shorts_' + side, [(.60, .155, .171),
        (.68, .164, .18), (.89, .165, .19), (.95, .163, .18)], shorts, bottom_slot)
    leg.location.x = sign*.166
    tube('Shorts_Piping_' + side, [(sign*.322, 0, z) for z in [.61, .70, .80, .91]],
         .009, gold, bottom_slot)

# Trace the supplied app logo into a single gold mesh, keeping the white image
# background off the shirt. This is geometry sampling, not a replacement logo.
logo = bpy.data.images.load(str(ROOT / 'frontend/assets/images/logo.png'))
w, h = logo.size
pixels = list(logo.pixels)
verts, faces = [], []
step = 3
for y in range(0, h, step):
    for x in range(0, w, step):
        r, g, b, a = pixels[4*(y*w+x):4*(y*w+x)+4]
        if a > .5 and r > .3 and r > b*1.35 and g > b*1.12:
            xx = (x/w-.5)*.43
            zz = .20 + y/h*.118
            size_x, size_z = step/w*.43, step/h*.118
            k = len(verts)
            for dx, dz in [(0,0), (size_x,0), (size_x,size_z), (0,size_z)]:
                vx = xx+dx
                yy = -.224*math.sqrt(max(.1, 1-(vx/.306)**2))-.004
                verts.append((vx, yy, zz+dz))
            faces.append((k, k+1, k+2, k+3))
mesh = bpy.data.meshes.new('Logo')
mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new('Top_Pacegasus_Logo', mesh)
bpy.context.collection.objects.link(obj)
finish(obj, obj.name, gold, top_slot)

# Gentle idle: hierarchical rigid-part animation is sufficient for this prototype.
# Feet remain planted; clothing, sockets and head follow the upper-body pivot.
scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 97
for frame, breath, tilt in [(1,0,0), (25,.008,.008), (49,.015,0), (73,.008,-.008), (97,0,0)]:
    upper.location.z = 1 + breath
    upper.rotation_euler[1] = tilt
    upper.keyframe_insert(data_path='location', frame=frame)
    upper.keyframe_insert(data_path='rotation_euler', frame=frame)
    head.rotation_euler[2] = -tilt*.8
    head.keyframe_insert(data_path='rotation_euler', frame=frame)
scene.frame_set(1)

# Interchangeable stationary bases. Both have their walking surface at z=0.
track_mat = material('Stage_Track', (.025, .030, .042))
violet_mat = material('Stage_Violet', (.105, .052, .19))
violet_edge = material('Stage_Lavender', (.46, .27, .73), .4)
stages = {key: group('Stage_' + key, stage_slot) for key in ['track', 'orbit']}


def disc(name, radius, depth, z, mat, parent):
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=radius, depth=depth,
                                     location=(0, 0, z))
    obj = finish(bpy.context.object, name, mat, parent)
    bevel = obj.modifiers.new('Soft_Edge', 'BEVEL')
    bevel.width = .025
    bevel.segments = 3
    obj.modifiers.new('Weighted_Normals', 'WEIGHTED_NORMAL')
    return obj


def rim(name, radius, z, mat, parent, thickness=.009):
    return tube(name, [(radius*math.cos(i*2*math.pi/96),
        radius*math.sin(i*2*math.pi/96), z) for i in range(97)], thickness, mat, parent)


disc('Track_Foundation', .78, .14, -.07, track_mat, stages['track'])
rim('Track_Gold_Edge', .753, -.012, gold, stages['track'], .014)
rim('Track_Lane_1', .62, .004, gold, stages['track'], .006)
rim('Track_Lane_2', .70, .004, gold, stages['track'], .006)
for i in range(3):
    y = -.60-i*.045
    tube('Track_Start_Mark_' + str(i), [(-.04,y,.008),(.04,y,.008)], .009, white, stages['track'])
disc('Orbit_Foot', .70, .055, -.145, violet_mat, stages['orbit'])
disc('Orbit_Rim', .78, .055, -.095, violet_edge, stages['orbit'])
disc('Orbit_Deck', .75, .085, -.04, violet_mat, stages['orbit'])
rim('Orbit_Halo', .715, .005, violet_edge, stages['orbit'], .012)
for i in range(8):
    a = 2*math.pi*i/8
    ball('Orbit_Stud_' + str(i), (.739*math.cos(a),.739*math.sin(a),-.036),
         (.02,.02,.02), gold, stages['orbit'])

world = bpy.data.worlds.new('Studio')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (.65,.65,.65,1)
world.node_tree.nodes['Background'].inputs[1].default_value = .5
scene.world = world
for name, loc, power, size in [('Key',(-3,-4,6),450,4), ('Fill',(4,-2,3),250,3), ('Rim',(0,3,5),350,3)]:
    bpy.ops.object.light_add(type='AREA', location=loc)
    light = bpy.context.object
    light.name = name
    light.data.energy = power
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (Vector((0,0,1.4))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(.45,-6,2.55))
camera = bpy.context.object
camera.rotation_euler = (Vector((0,0,1.35))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 3.30
scene.camera = camera
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.render.resolution_x, scene.render.resolution_y = 700, 850
scene.render.resolution_percentage = 100
scene.render.film_transparent = True


def export(filename, stage_key):
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    excluded = set()
    for key, stage in stages.items():
        if key != stage_key:
            excluded.update([stage, *stage.children_recursive])
    for child in root.children_recursive:
        child.select_set(child not in excluded)
    bpy.ops.export_scene.gltf(filepath=str(OUT / filename), export_format='GLB',
        use_selection=True, export_animations=True, export_animation_mode='SCENE',
        export_anim_scene_split_object=False, export_extras=True)


for key, color in [('starter', (.026,.030,.038)), ('cloud', (.67,.73,.78))]:
    shirt.diffuse_color = (*color,1)
    shirt.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*color,1)
    for stage_key in stages:
        for other_key, stage in stages.items():
            for child in stage.children_recursive:
                child.hide_render = other_key != stage_key
        asset_name = 'runner_' + key + '_' + stage_key
        export(asset_name + '.glb', stage_key)
        scene.render.filepath = str(OUT / (asset_name + '.png'))
        bpy.ops.render.render(write_still=True)
shirt.diffuse_color = (.026,.030,.038,1)
shirt.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.026,.030,.038,1)
for key, stage in stages.items():
    for child in stage.children_recursive:
        child.hide_render = key != 'track'
        child.hide_set(key != 'track')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'pacegasus_runner.blend'))
print('Avatar assets exported to', OUT)
