#!/usr/bin/env python3
"""Dựng nhân vật chibi bé trai bằng Blender Python (chạy: blender -b --python make_chibi_boy.py).
Mỗi bộ phận là 1 object, origin đặt đúng khớp xoay (vai/hông/cổ) để game điều khiển animation.
Xuất: assets/models/boy3d.glb + render thử shots3d/boy3d_front.png, boy3d_back.png"""
import bpy, math, os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT_GLB = os.path.join(ROOT, 'assets', 'models', 'boy3d.glb')
OUT_FRONT = os.path.join(ROOT, 'shots3d', 'boy3d_front.png')
OUT_BACK = os.path.join(ROOT, 'shots3d', 'boy3d_back.png')

# ---------- dọn scene ----------
bpy.ops.wm.read_factory_settings(use_empty=True)

MATS = {}
def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def mat(name, rgb, rough=0.65):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*(srgb2lin(c) for c in rgb), 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    MATS[name] = m
    return m

mat('Skin', (0.965, 0.765, 0.604), 0.6)
mat('Hair', (0.20, 0.188, 0.18), 0.5)
mat('Shirt', (0.941, 0.408, 0.102), 0.7)
mat('Shorts', (0.227, 0.247, 0.267), 0.8)
mat('Shoe', (0.96, 0.96, 0.96), 0.5)
mat('Dark', (0.15, 0.13, 0.12), 0.5)
mat('Cheek', (0.96, 0.63, 0.55), 0.9)

def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True

def ball(name, loc, scale, material, parent=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material:
        o.data.materials.append(MATS[material])
    smooth(o)
    if parent:
        o.parent = parent
    return o

def part(name, pivot):
    """Object rỗng làm khớp: các mesh con vẽ theo tọa độ LOCAL quanh pivot."""
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.location = pivot
    return e

def lball(part_obj, name, loc, scale, material, rot=(0, 0, 0)):
    """Thêm 1 khối cầu vào part, vị trí tính theo pivot của part (local)."""
    world = Vector(part_obj.location) + Vector(loc)
    o = ball(name, world, scale, material, rot=rot)
    # gắn vào part nhưng giữ nguyên hình dạng thế giới: đặt parent + matrix_parent_inverse
    o.parent = part_obj
    o.matrix_parent_inverse = part_obj.matrix_world.inverted()
    return o

# Nhân vật cao ~2.3, chân tại z=0, mặt hướng -Y
body = part('Body', (0, 0, 0.60))
lball(body, 'Torso', (0, 0, 0.42), (0.40, 0.325, 0.44), 'Shirt')
lball(body, 'Shorts', (0, 0, 0.03), (0.385, 0.325, 0.25), 'Shorts')

head = part('Head', (0, 0, 1.32))
lball(head, 'Skull', (0, 0, 0.46), (0.46, 0.435, 0.45), 'Skin')
lball(head, 'HairCap', (0, 0.035, 0.52), (0.478, 0.452, 0.42), 'Hair')
lball(head, 'HairTuft', (0, -0.245, 0.86), (0.135, 0.21, 0.115), 'Hair', rot=(math.radians(-38), 0, 0))
lball(head, 'HairFringe', (0, -0.335, 0.66), (0.36, 0.13, 0.12), 'Hair')
lball(head, 'EyeL', (0.155, -0.405, 0.47), (0.048, 0.03, 0.062), 'Dark')
lball(head, 'EyeR', (-0.155, -0.405, 0.47), (0.048, 0.03, 0.062), 'Dark')
lball(head, 'CheekL', (0.275, -0.345, 0.36), (0.062, 0.028, 0.045), 'Cheek')
lball(head, 'CheekR', (-0.275, -0.345, 0.36), (0.062, 0.028, 0.045), 'Cheek')
# miệng cười: nửa vòng torus dưới
bpy.ops.mesh.primitive_torus_add(major_radius=0.072, minor_radius=0.016,
                                 major_segments=24, minor_segments=8,
                                 location=Vector(head.location) + Vector((0, -0.425, 0.345)),
                                 rotation=(math.radians(90), 0, 0))
mouth = bpy.context.object
mouth.name = 'Mouth'
mouth.data.materials.append(MATS['Dark'])
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='DESELECT')
bpy.ops.object.mode_set(mode='OBJECT')
for v in mouth.data.vertices:
    if v.co.y > 0.001:  # nửa trên của torus trong mặt phẳng vòng (local Y) -> xoá, giữ nửa dưới = miệng cười
        v.select = True
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.delete(type='VERT')
bpy.ops.object.mode_set(mode='OBJECT')
smooth(mouth)
mouth.parent = head
mouth.matrix_parent_inverse = head.matrix_world.inverted()

def make_arm(side):  # side: +1 tay trái (x+), -1 tay phải (x-)
    a = part('ArmL' if side > 0 else 'ArmR', (side * 0.435, 0, 1.26))
    lball(a, 'Sleeve', (side * 0.015, 0, -0.03), (0.135, 0.135, 0.17), 'Shirt')
    lball(a, 'Arm', (side * 0.03, 0, -0.27), (0.088, 0.088, 0.235), 'Skin')
    lball(a, 'Fist', (side * 0.035, 0, -0.50), (0.098, 0.098, 0.098), 'Skin')
    return a

def make_leg(side):
    lg = part('LegL' if side > 0 else 'LegR', (side * 0.175, 0, 0.60))
    lball(lg, 'Leg', (0, 0, -0.22), (0.105, 0.105, 0.24), 'Skin')
    lball(lg, 'Shoe', (0, -0.045, -0.53), (0.125, 0.185, 0.085), 'Shoe')
    return lg

make_arm(1); make_arm(-1)
make_leg(1); make_leg(-1)

# ---------- ánh sáng + camera render thử ----------
def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

world = bpy.data.worlds.new('World')
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.82, 0.90, 0.97, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = 0.6

bpy.ops.object.light_add(type='AREA', location=(2.5, -3.0, 4.0))
key = bpy.context.object; key.data.energy = 260; key.data.shape = 'DISK'; key.data.size = 3.0
look_at(key, (0, 0, 1.1))
bpy.ops.object.light_add(type='AREA', location=(-3.0, 1.5, 2.0))
fill = bpy.context.object; fill.data.energy = 110; fill.data.size = 2.5
look_at(fill, (0, 0, 1.1))

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.device = 'CPU'
scene.cycles.use_denoising = True
scene.render.resolution_x = 700
scene.render.resolution_y = 800
scene.render.film_transparent = False

bpy.ops.object.camera_add(location=(1.7, -3.6, 1.75))
cam = bpy.context.object
scene.camera = cam
look_at(cam, (0, 0, 1.05))
scene.render.filepath = OUT_FRONT
bpy.ops.render.render(write_still=True)

cam.location = (-1.7, 3.6, 1.75)
look_at(cam, (0, 0, 1.05))
scene.render.filepath = OUT_BACK
bpy.ops.render.render(write_still=True)

# ---------- xuất glb ----------
os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', export_yup=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, 'tools', 'blender', 'chibi_boy.blend'))
print('EXPORTED', OUT_GLB)
