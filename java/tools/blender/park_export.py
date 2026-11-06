#!/usr/bin/env python3
"""Mở amusement_park.blend của Tín, chỉ xuất GLB cho game (không render).
Chạy: blender -b gen/park/amusement_park.blend --python tools/blender/park_export.py"""
import bpy, os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
verts = 0
for o in meshes:
    verts += len(o.data.vertices)
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
print('PARK objects:', len(meshes), 'verts:', verts)
print('PARK bbox min:', tuple(round(v, 1) for v in mn), 'max:', tuple(round(v, 1) for v in mx))
glb = os.path.join(ROOT, 'assets', 'models', 'park.glb')
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', export_yup=True)
print('PARK GLB:', glb, os.path.getsize(glb))
