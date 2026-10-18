"""Standalone approval model only; does not modify the app or shop catalog.

Run with Blender --background --python tools/avatar/build_golden_wings_preview.py.
"""
import math
from pathlib import Path

import bpy
from mathutils import Vector

OUT = Path('C:/Users/User/.codex/visualizations/2026/09/19/01a0b9c9-449e-76a3-b522-f0b05440c573/golden_wings_v1')
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def material(name, color, metallic=.65, roughness=.34):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    return mat


gold = material('Warm yellow gold', (.83, .43, .055))
light_gold = material('Honey gold coverts', (.95, .58, .12), .58)
quill_gold = material('Subtle feather ridge', (.98, .64, .20), .62, .4)
parts = []


def feather(name, base, tip, width, mat, side, layer=0, ridge=True):
    """Closed curved lenticular feather, not an intersecting ellipsoid."""
    a, b = Vector(base), Vector(tip)
    direction = b - a
    axis = Vector((-direction.z, 0, direction.x)).normalized()
    verts, faces = [], []
    steps, ring = 24, 12
    for j in range(steps + 1):
        t = j / steps
        # Narrow root, full rounded shoulder, tapered but rounded pointed tip.
        profile = max(.012, math.sin(math.pi * t) ** .62)
        profile *= 1.12 - .38 * t
        center = a.lerp(b, t)
        center.x += side * .13 * math.sin(math.pi * t)
        center.y -= .075 * math.sin(math.pi * t)
        for k in range(ring):
            angle = 2 * math.pi * k / ring
            p = center + axis * (width * profile * math.cos(angle))
            p.y += width * .27 * profile * math.sin(angle)
            verts.append(tuple(p))
    for j in range(steps):
        for k in range(ring):
            n = j * ring + k
            nxt = j * ring + (k + 1) % ring
            faces.append((n, nxt, nxt + ring, n + ring))
    faces.extend([tuple(reversed(range(ring))), tuple(steps * ring + k for k in range(ring))])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    parts.append(obj)
    if ridge and layer == 0:
        # A restrained raised spine that follows the feather's surface.
        curve = bpy.data.curves.new(name + ' shaft', 'CURVE')
        curve.dimensions = '3D'
        curve.bevel_depth = .009
        curve.bevel_resolution = 2
        spline = curve.splines.new('POLY')
        spline.points.add(15)
        for i, point in enumerate(spline.points):
            t = .12 + .77 * i / 15
            p = a.lerp(b, t)
            p.x += side * .13 * math.sin(math.pi * t)
            p.y -= .075 * math.sin(math.pi * t) + width * .27 * math.sin(math.pi * t) ** .62
            point.co = (*p, 1)
            point.radius = math.sin(math.pi * t) * .7
        shaft = bpy.data.objects.new(name + ' ridge', curve)
        bpy.context.collection.objects.link(shaft)
        shaft.data.materials.append(quill_gold)
        parts.append(shaft)
    return obj


# A swept upper fan, broad middle and a short, downward-facing inner skirt.
# (root x,z, tip x,z, half-width); mirrored exactly for a wearable pair.
fan = [
    (1.00, 1.12, 2.78, 3.10, .145),
    (.99, 1.02, 2.78, 2.66, .153),
    (.96, .91, 2.73, 2.26, .163),
    (.90, .79, 2.62, 1.80, .176),
    (.83, .66, 2.40, 1.31, .182),
    (.74, .53, 2.13, .84, .186),
    (.64, .43, 1.84, .37, .181),
    (.54, .35, 1.56, -.08, .174),
    (.44, .30, 1.25, -.43, .158),
    (.34, .28, .92, -.62, .147),
    (.27, .29, .64, -.58, .132),
    (.24, .35, .40, -.39, .110),
]

for side, label in [(-1, 'L'), (1, 'R')]:
    start = len(parts)
    for i, (bx, bz, tx, tz, width) in enumerate(fan):
        feather(f'{label} primary {i:02}', (side * bx, .06 + i * .005, bz),
                (side * tx, .04, tz), width, gold, side)
    # Two staggered overlapping coverts over the long feather roots.
    for row, factor in [(0, .46), (1, .25)]:
        for i, (bx, bz, tx, tz, width) in enumerate(fan):
            root = Vector((side * bx, -.065 - row * .09, bz))
            delta = Vector((side * (tx - bx), 0, tz - bz))
            base = root - delta * (.05 if row == 0 else .11)
            tip = root + delta * factor
            feather(f'{label} covert {row}-{i:02}', base, tip,
                    width * (.88 if row == 0 else .72),
                    light_gold if (i + row) % 3 else gold, side, row + 1, False)
    for obj in parts[start:]:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        if obj.type == 'CURVE':
            bpy.ops.object.convert(target='MESH')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts[start:]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[start]
    bpy.ops.object.join()
    wing = bpy.context.object
    wing.name = f'Golden_Wing.{label}'
    wing['attachment'] = 'back / upper spine; left and right separate meshes'

wings = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for obj in wings:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT / 'golden_wings_v1.glb'),
                          export_format='GLB', use_selection=True, export_animations=False)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.resolution_x = 1500
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.world.color = (.20, .20, .20)
scene.view_settings.view_transform = 'AgX'
scene.render.image_settings.file_format = 'PNG'

backdrop = material('Backdrop charcoal blue', (.028, .036, .055), 0, .8)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 2, 1))
plane = bpy.context.object
plane.rotation_euler = (math.pi / 2, 0, 0)
plane.data.materials.append(backdrop)
plane.name = 'Preview backdrop - not exported'


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


for name, position, power, size, color in [
    ('Key softbox', (-3, -4, 7), 1100, 5, (1, .88, .65)),
    ('Fill softbox', (4, -3, 3), 900, 4, (.80, .88, 1)),
    ('Top rim', (0, .8, 6), 1300, 3, (1, .72, .31)),
]:
    bpy.ops.object.light_add(type='AREA', location=position)
    light = bpy.context.object
    light.name = name
    light.data.energy = power
    light.data.shape = 'DISK'
    light.data.size = size
    light.data.color = color
    aim(light, (0, 0, 1.1))

bpy.ops.object.camera_add(location=(0, -12, 2.4))
cam = bpy.context.object
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 6.7
aim(cam, (0, 0, 1.2))
scene.camera = cam
scene.render.filepath = str(OUT / 'golden_wings_front.png')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'golden_wings_v1.blend'))
bpy.ops.render.render(write_still=True)
cam.location = (3.4, -11, 3.4)
aim(cam, (0, 0, 1.2))
scene.render.filepath = str(OUT / 'golden_wings_angle.png')
bpy.ops.render.render(write_still=True)
print('GOLDEN_WINGS_PREVIEW_COMPLETE', OUT)
