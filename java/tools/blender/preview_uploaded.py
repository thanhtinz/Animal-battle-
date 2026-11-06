#!/usr/bin/env python3
"""Render thử model GLB Tín gửi (Z-up kiểu trimesh): TỰ dò hướng dựng đứng bằng cách
thử các góc xoay root và chấm điểm theo bbox (chiều cao phải dọc Z, giày phải ở đáy).
Chạy: blender -b --python preview_uploaded.py -- <input.glb> <out_prefix>"""
import bpy, math, os, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
src, prefix = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
roots = [o for o in bpy.context.scene.objects if o.parent is None and o.type == 'EMPTY']
root = roots[0] if roots else None

def world_bbox():
    bpy.context.view_layer.update()
    mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
    shoe = None
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        c = Vector((0, 0, 0))
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
            c += w
        if 'sneaker' in o.name.lower():
            shoe = c / 8
    return mn, mx, shoe

best = None
for cand in [(0, 0, 0), (90, 0, 0), (-90, 0, 0), (0, 90, 0), (0, -90, 0), (0, 0, 90), (0, 0, -90), (180, 0, 0)]:
    if root:
        root.rotation_euler = tuple(math.radians(a) for a in cand)
        root.location = (0, 0, 0)
    mn, mx, shoe = world_bbox()
    if root:  # đưa về tâm + mặt đất TRƯỚC khi chấm điểm, để các ứng viên so được công bằng
        root.location = (-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z)
    mn, mx, shoe = world_bbox()
    ext = mx - mn
    height_axis = max(range(3), key=lambda i: ext[i])
    if height_axis != 2 or shoe is None:
        score = -1e9
    else:
        score = ext.z - abs(shoe.z - mn.z) * 4
    print('cand', cand, 'ext', tuple(round(v, 2) for v in ext), 'score', round(score, 2))
    if best is None or score > best[0]:
        best = (score, cand)
print('CHOSEN', best[1])
if root:
    root.rotation_euler = tuple(math.radians(a) for a in best[1])
mn, mx, shoe = world_bbox()
if root:
    root.location.x -= (mn.x + mx.x) / 2
    root.location.y -= (mn.y + mx.y) / 2
    root.location.z -= mn.z
mn, mx, shoe = world_bbox()
H = mx.z
print('final height', round(H, 2))

world = bpy.data.worlds.new('World')
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.82, 0.90, 0.97, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = 0.6

def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

bpy.ops.object.light_add(type='AREA', location=(3.0, -3.5, H * 1.2))
key = bpy.context.object; key.data.energy = 500; key.data.shape = 'DISK'; key.data.size = 4.0
look_at(key, (0, 0, H * 0.5))
bpy.ops.object.light_add(type='AREA', location=(-3.5, 2.0, H * 0.8))
fill = bpy.context.object; fill.data.energy = 200; fill.data.size = 3.0
look_at(fill, (0, 0, H * 0.5))

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.device = 'CPU'
scene.cycles.use_denoising = True
scene.render.resolution_x = 700
scene.render.resolution_y = 800

bpy.ops.object.camera_add(location=(H * 0.45, H * 1.25, H * 0.62))
cam = bpy.context.object
scene.camera = cam
look_at(cam, (0, 0, H * 0.48))
scene.render.filepath = prefix + '_a.png'
bpy.ops.render.render(write_still=True)

cam.location = (-H * 0.45, -H * 1.25, H * 0.62)
look_at(cam, (0, 0, H * 0.48))
scene.render.filepath = prefix + '_b.png'
bpy.ops.render.render(write_still=True)
print('PREVIEW DONE')
