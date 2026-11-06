# Amusement Park - Blender procedural scene generator
# Run in Blender: Scripting > Open > Run Script
# Creates a colorful, spacious, toy-like 3D amusement park environment.
import bpy, math, random
from mathutils import Vector

random.seed(17)
# -------------------- reset --------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.materials, bpy.data.curves, bpy.data.meshes):
    pass

# -------------------- materials --------------------
def mat(name, color, rough=0.72, metallic=0.0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=rough; bs.inputs['Metallic'].default_value=metallic
    return m

GRASS=mat('Meadow green',(0.28,.62,.30)); GRASS2=mat('Fresh grass',(.42,.73,.34))
STONE=mat('Warm lavender stone',(.63,.56,.68)); STONE2=mat('Paving light',(.78,.71,.77))
PINK=mat('Candy pink',(1,.34,.48)); RED=mat('Coral red',(.88,.16,.19)); ORANGE=mat('Tangerine',(1,.43,.12))
YELLOW=mat('Sunshine yellow',(1,.76,.16)); BLUE=mat('Sky blue',(.16,.55,.9)); NAVY=mat('Deep blue',(.10,.25,.52))
TEAL=mat('Mint teal',(.18,.72,.68)); CREAM=mat('Vanilla cream',(1,.91,.72)); WHITE=mat('Cloud white',(1,.97,.9))
BROWN=mat('Warm wood',(.42,.22,.12)); WOOD2=mat('Light wood',(.68,.39,.19)); METAL=mat('Painted metal',(.25,.34,.43),.4,.35)
DARK=mat('Dark details',(.12,.13,.19)); WATER=mat('Turquoise water',(.08,.58,.78),.24,.12)

# -------------------- helpers --------------------
def assign(obj, material):
    if material: obj.data.materials.append(material)
    return obj

def bevel(obj, amount=.15, segments=3):
    if obj.type=='MESH':
        mod=obj.modifiers.new('Soft rounded edges','BEVEL'); mod.width=amount; mod.segments=segments
        obj.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return obj

def cube(name, loc, scale, material, bevel_amt=.12):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o=bpy.context.object; o.name=name
    o.dimensions=scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(o,material)
    if bevel_amt: bevel(o,bevel_amt)
    return o

def uv(name, loc, scale, material, segments=24, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=loc); o=bpy.context.object; o.name=name
    o.scale=scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True); assign(o,material)
    for p in o.data.polygons: p.use_smooth=True
    return o

def cyl(name, loc, radius, depth, material, vertices=32, bevel_amt=.06):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc); o=bpy.context.object; o.name=name; assign(o,material)
    if bevel_amt: bevel(o,bevel_amt,3)
    for p in o.data.polygons: p.use_smooth=True
    return o

def torus(name, loc, major, minor, material, rot=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48, minor_segments=12, location=loc, rotation=rot)
    o=bpy.context.object; o.name=name; assign(o,material)
    for p in o.data.polygons: p.use_smooth=True
    return o

def rod(name, a, b, radius, material, vertices=16):
    a,b=Vector(a),Vector(b); d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length, location=(a+b)/2)
    o=bpy.context.object; o.name=name; o.rotation_mode='QUATERNION'; o.rotation_quaternion=d.to_track_quat('Z','Y'); assign(o,material)
    bevel(o,radius*.35,2)
    return o

def curve_line(name, points, radius, material, cyclic=False):
    cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'; cu.resolution_u=16; cu.bevel_depth=radius; cu.bevel_resolution=4
    sp=cu.splines.new('POLY'); sp.points.add(len(points)-1)
    for p,co in zip(sp.points,points): p.co=(*co,1)
    sp.use_cyclic_u=cyclic
    ob=bpy.data.objects.new(name,cu); bpy.context.collection.objects.link(ob); assign(ob,material); return ob

def text_obj(body, loc, size, material):
    cu=bpy.data.curves.new('Park sign lettering','FONT'); cu.body=body; cu.size=size; cu.extrude=.025; cu.align_x='CENTER'
    ob=bpy.data.objects.new(body,cu); bpy.context.collection.objects.link(ob); ob.location=loc; assign(ob,material); return ob

# -------------------- floating island / terrain --------------------
cube('Large park foundation',(0,0,-1.15),(160,132,3),GRASS,1.3)
# rounded perimeter retaining edge
cube('Front island trim',(0,-66,-.35),(160,1.2,1.5),BROWN,.4)
cube('Back island trim',(0,66,-.35),(160,1.2,1.5),BROWN,.4)
cube('Left island trim',(-80,0,-.35),(1.2,132,1.5),BROWN,.4)
cube('Right island trim',(80,0,-.35),(1.2,132,1.5),BROWN,.4)
# Main plaza, intentionally very wide and open
cube('Grand central plaza',(0,-2,.15),(82,70,.7),STONE,.8)
# paving tile pattern
for x in range(-38,40,5):
    for y in range(-34,31,5):
        if random.random()<.82:
            cube('Paving tile',(x,y,.53),(4.65,4.65,.10),STONE2 if random.random()<.72 else STONE,.12)
# center medallion
cyl('Central round medallion',(0,0,.67),10,.22,NAVY,64,.08)
cyl('Medallion inner',(0,0,.81),8.8,.12,YELLOW,64,.06)
# star emblem using 2D curve polygon extrusion
star_pts=[]
for i in range(10):
    ang=math.pi/2+i*math.pi/5; r=6 if i%2==0 else 2.8
    star_pts.append((r*math.cos(ang),r*math.sin(ang),.91))
curve_line('Golden star outline',star_pts,.25,ORANGE,True)

# -------------------- gardens --------------------
for x,y in [(-54,-35),(-54,32),(54,-35),(54,32),(-32,43),(32,43),(-32,-45),(32,-45)]:
    cyl('Garden island',(x,y,.55),6,.45,GRASS2,48,.18)
    for j in range(7):
        a=j*math.tau/7; xx=x+4*math.cos(a); yy=y+4*math.sin(a)
        uv('Flower head',(xx,yy,1.25),(.55,.55,.32),random.choice([PINK,YELLOW,WHITE,TEAL]))
        cyl('Flower center',(xx,yy,1.55),.16,.12,ORANGE,16,.02)
    # shrubs
    for j in range(5):
        a=j*math.tau/5; uv('Round shrub',(x+2.6*math.cos(a),y+2.6*math.sin(a),1.25),(1.1,1.1,.9),GRASS)

# trees, simple soft toy forms
def tree(x,y,s=1):
    cyl('Tree trunk',(x,y,1.8*s),.55*s,3.6*s,BROWN,16,.12)
    uv('Tree canopy',(x,y,4.2*s),(2.5*s,2.4*s,2.5*s),GRASS2)
    uv('Tree canopy highlight',(x-.9*s,y-.4*s,5*s),(1.45*s,1.35*s,1.5*s),GRASS)
for x,y,s in [(-68,-45,1.2),(-68,42,1.2),(68,-43,1.2),(68,42,1.2),(-42,51,.9),(42,52,.9),(-58,0,.8),(58,2,.8)]: tree(x,y,s)

# -------------------- castle entrance at rear --------------------
# entrance wall and towers
cube('Castle main wall',(0,54,8),(35,5,15),CREAM,.5)
cube('Castle gate dark opening',(0,51.35,4.7),(9,1,9),NAVY,.25)
# arch top over doorway
uv('Gate arch left',(-4.5,51.1,9),(1.3,1,3),YELLOW)
uv('Gate arch right',(4.5,51.1,9),(1.3,1,3),YELLOW)
for x in [-16,16]:
    cyl('Castle tower',(x,53,8),4,16,PINK,32,.2)
    cyl('Tower upper band',(x,53,16.4),4.2,1,YELLOW,32,.1)
    # cone roof
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=4.7, radius2=0, depth=7, location=(x,53,21.5)); assign(bpy.context.object,RED); bpy.context.object.name='Castle cone roof'
    cube('Tower flag pole',(x,53,27),(0.25,.25,6),METAL,.04)
    cube('Tower flag',(x+1.5,53,28),(3,0.18,1.5),YELLOW,.08)
# center sign
cube('Castle sign plate',(0,50.9,14),(14,.8,3),NAVY,.25)
text_obj('FUN PARK',(0,50.42,13.4),1.6,WHITE)
# approach steps
for i in range(5): cube('Castle approach step',(0,40+i*2,.65+i*.16),(24-i*2,2,.45),STONE2,.12)

# -------------------- ferris wheel left --------------------
fx,fy,fz=-59,22,17
# support legs
rod('Ferris wheel support', (fx-7,fy-3,1),(fx,fy,fz),.55,RED)
rod('Ferris wheel support',(fx+7,fy-3,1),(fx,fy,fz),.55,RED)
torus('Ferris wheel outer rim',(fx,fy,fz),14,.45,PINK,(math.pi/2,0,0))
torus('Ferris wheel inner rim',(fx,fy,fz),10,.25,YELLOW,(math.pi/2,0,0))
# spokes in wheel plane XZ
for i in range(12):
    a=i*math.tau/12
    rod('Ferris wheel spoke',(fx,fy,fz),(fx+14*math.cos(a),fy,fz+14*math.sin(a)),.18,BLUE)
# gondolas placed around ring
for i in range(10):
    a=i*math.tau/10
    gx=fx+14*math.cos(a); gz=fz+14*math.sin(a)
    rod('Gondola hanger',(gx,fy,gz),(gx,fy,gz-2.2),.12,METAL)
    cube('Ferris wheel gondola',(gx,fy,gz-3),(3,2.5,2.2),[ORANGE,YELLOW,TEAL,PINK][i%4],.45)
    uv('Gondola roof',(gx,fy,gz-1.75),(1.8,1.5,.35),RED)

# -------------------- roller coaster right / rear --------------------
# supports
for x in [24,34,44,54,64,72]:
    for y in [35,47]: cyl('Coaster support',(x,y,7),.35,14,METAL,16,.04)
# track loop and rolling hills in XZ plane, with depth variation
pts=[]
for i in range(121):
    t=i/120*math.tau
    pts.append((49+13*math.cos(t),40,18+13*math.sin(t)))
curve_line('Roller coaster loop',pts,.55,RED,False)
pts2=[]
for i in range(90):
    x=22+i*0.62; z=15+6*math.sin(i/89*math.pi*2.2)+2*math.sin(i/89*math.pi*5)
    pts2.append((x,40,z))
curve_line('Roller coaster hills',pts2,.55,PINK,False)
# coaster train
for i in range(3):
    cube('Coaster car',(30+i*2.2,39,18),(2.2,1.7,1.2),YELLOW,.3)

# -------------------- central fountain + mascot statue --------------------
cyl('Fountain base',(0,27,.9),9,.8,STONE2,64,.2)
cyl('Fountain water',(0,27,1.35),7.7,.18,WATER,64,.08)
torus('Fountain rim',(0,27,1.55),8,.3,CREAM)
cyl('Fountain pedestal',(0,27,2.6),2.2,2.5,TEAL,32,.2)
uv('Mascot statue body',(0,27,5.1),(2.4,1.8,2.5),CREAM)
uv('Mascot statue head',(0,26.5,8),(2.8,2,2.6),ORANGE)
uv('Mascot left ear',(-1.9,26.5,10),(1,1,1.7),ORANGE); uv('Mascot right ear',(1.9,26.5,10),(1,1,1.7),ORANGE)
uv('Mascot muzzle',(0,24.65,7.4),(1.2,.5,.8),CREAM)
for ex in [-.85,.85]: uv('Mascot eye',(ex,24.55,8.4),(.25,.18,.35),DARK)
uv('Mascot nose',(0,24.2,7.9),(.35,.25,.25),DARK)
# fountain water jets
for a in range(8):
    ang=a*math.tau/8; x=5.5*math.cos(ang); y=27+5.5*math.sin(ang)
    rod('Fountain jet',(x,y,1.5),(x*.8,y-27+27,4.2),.09,BLUE)

# -------------------- carousel right --------------------
cyl('Carousel platform',(57,4,1.1),11,1.1,PINK,64,.2)
cyl('Carousel floor',(57,4,1.72),10.3,.18,CREAM,64,.1)
cyl('Carousel center pole',(57,4,8),.45,13,YELLOW,32,.08)
# roof as cone + canopy ring
bpy.ops.mesh.primitive_cone_add(vertices=64, radius1=12, radius2=1.3, depth=5, location=(57,4,13)); assign(bpy.context.object,PINK); bpy.context.object.name='Carousel canopy'
torus('Carousel canopy trim',(57,4,10.5),11.7,.25,YELLOW)
for i in range(8):
    a=i*math.tau/8; x=57+7.2*math.cos(a); y=4+7.2*math.sin(a)
    rod('Carousel pole',(x,y,2),(x,y,10.8),.12,BLUE)
    # stylized ride animal
    uv('Carousel ride animal',(x,y,4.2),(1.2,.65,1.25),WHITE if i%2 else ORANGE)
    uv('Carousel ride head',(x,y-.35,5.2),(.7,.65,.7),WHITE if i%2 else ORANGE)

# -------------------- food stalls --------------------
def stall(x,y,accent=RED,label='SNACKS'):
    cube('Food stall counter',(x,y,2.2),(9,5,3),CREAM,.3)
    cube('Food stall front',(x,y-2.56,2.1),(8.5,.18,1.8),accent,.06)
    for xx in [x-4.7,x+4.7]: cube('Stall post',(xx,y,5.2),(.35,.35,6),BROWN,.06)
    cube('Stall canopy',(x,y,7.7),(10,6,.5),accent,.18)
    for i in range(5):
        cube('Canopy stripe',(x-4+i*2,y,8.0),(1,.08,.12),WHITE,.02)
    text_obj(label,(x,y-2.72,2.15),.85,WHITE)
    for xx in [x-2.5,x,x+2.5]: cube('Snack display',(xx,y-1.4,3.8),(1.6,1.2,.8),YELLOW,.18)
stall(-47,-12,RED,'POPCORN')
stall(46,-22,TEAL,'ICE CREAM')
stall(-62,5,ORANGE,'TICKETS')

# -------------------- benches / lamps / crates / balloons --------------------
def bench(x,y,rot=0):
    # seat and back, rotated as a group using object rotation
    parts=[]
    parts.append(cube('Bench seat',(x,y,1.7),(5,1.1,.35),WOOD2,.12))
    parts.append(cube('Bench back',(x,y+.45,2.8),(5,.35,1.8),BROWN,.12))
    for xx in [x-1.8,x+1.8]:
        parts.append(cube('Bench leg',(xx,y,1.0),(.35,.45,1.5),METAL,.08))
    for o in parts: o.rotation_euler[2]=rot
for x,y,r in [(-36,-25,0),(36,-25,0),(-36,25,math.pi),(36,25,math.pi),(-15,42,0),(15,42,0)]: bench(x,y,r)

def lamp(x,y):
    cyl('Lamp post',(x,y,4),.16,7,METAL,16,.04)
    uv('Lamp globe',(x,y,7.8),(.75,.75,.75),YELLOW)
    uv('Lamp cap',(x,y,8.45),(.45,.45,.25),DARK)
for x,y in [(-43,-38),(43,-38),(-43,37),(43,37),(-22,-42),(22,-42),(-22,39),(22,39),(-65,-15),(65,-15)]: lamp(x,y)
# colorful balloon bundles
for x,y in [(-65,-28),(64,28),(-30,5),(30,-8)]:
    for i,c in enumerate([PINK,BLUE,YELLOW,TEAL]):
        xx=x+(i%2)*1.1; yy=y+(i//2)*.7
        uv('Balloon',(xx,yy,4.5+(i%2)*1.2),(.75,.75,1),c)
        curve_line('Balloon string',[(xx,yy,3.7),(xx,yy,2.3)],.025,WHITE)
# decorative crates
for x,y in [(-55,-20),(-52,-18),(58,-28),(62,-26),(35,14)]:
    cube('Wooden crate',(x,y,1.8),(2.7,2.7,2.7),WOOD2,.18)
    cube('Crate cross',(x,y-1.38,1.8),(2.3,.08,.22),YELLOW,.04)
    cube('Crate cross',(x,y-1.4,1.8),(.22,.08,2.3),YELLOW,.04)

# -------------------- surrounding paths and water features --------------------
# decorative shallow ponds at the front corners
for x in [-68,68]:
    cube('Pond',(x,-55,.25),(20,12,.25),WATER,2)
    for j in range(4):
        uv('Pond lily pad',(x-5+j*3,-54+random.uniform(-3,3),.48),(1.4,1,.12),GRASS2)
# path border paving strips
for x in [-74,74]: cube('Side promenade',(x,0,.45),(5,100,.35),STONE2,.2)

# -------------------- camera, lighting, world --------------------
world=bpy.context.scene.world
world.color=(.22,.22,.22)
world.use_nodes=True; world.node_tree.nodes['Background'].inputs[0].default_value=(.42,.62,.85,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.65
# lighting
bpy.ops.object.light_add(type='AREA', location=(-35,-40,95)); key=bpy.context.object; key.name='Large softbox'; key.data.energy=16000; key.data.shape='DISK'; key.data.size=65
bpy.ops.object.light_add(type='AREA', location=(55,25,55)); fill=bpy.context.object; fill.name='Warm fill'; fill.data.energy=8500; fill.data.size=45
# camera overview, slightly elevated isometric
bpy.ops.object.camera_add(location=(112,-150,132)); cam=bpy.context.object; cam.name='Park overview camera'
target=Vector((0,2,7)); direction=target-Vector(cam.location); cam.rotation_euler=direction.to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=205
scene=bpy.context.scene; scene.camera=cam
scene.render.engine='BLENDER_EEVEE_NEXT'
scene.eevee.taa_render_samples=64
scene.render.resolution_x=1800; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath='//amusement_park_preview.png'
scene.view_settings.view_transform='AgX'
# Set viewport to camera and material color
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
# save blend beside script when run
blend_path=bpy.path.abspath('//amusement_park.blend')
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
bpy.ops.render.render(write_still=True)
print('Created:', blend_path)
