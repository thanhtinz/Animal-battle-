#!/usr/bin/env python3
"""Sau khi generator của Tín tạo amusement_park.blend: mở file, đổi render sang Cycles CPU
(EEVEE không chạy headless ở sandbox), render preview + xuất GLB cho game.
Chạy: blender -b gen/park/amusement_park.blend --python tools/blender/park_finish.py"""
import bpy, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.device = 'CPU'
scene.cycles.use_denoising = True
scene.render.resolution_x = 1500
scene.render.resolution_y = 1000
scene.render.filepath = os.path.join(ROOT, 'shots3d', 'park_preview.png')
bpy.ops.render.render(write_still=True)

glb = os.path.join(ROOT, 'assets', 'models', 'park.glb')
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', export_yup=True)
print('PARK DONE', glb, os.path.getsize(glb))
