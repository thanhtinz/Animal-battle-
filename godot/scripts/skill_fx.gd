class_name SkillFX
extends Node2D
## 13v skill presentation layer — Tín: "làm VFX đẹp đẹp nha".
##
## Built on the Godot 4.4 techniques the 13v research pass adopted
## (see KE-HOACH 13v VFX-NOTES):
##   * GPUParticles2D + ParticleProcessMaterial for every burst and
##     zone emitter — one_shot + explosiveness = 1 for impacts,
##     continuous emitters for zones; colour ramps and scale
##     curves as GradientTexture1D / CurveTexture resources;
##     local_coords = false wherever the emitter must trail a
##     moving source.
##   * canvas_item shaders for the two big area reads: the Thiên
##     Màn dome (rim glow + travelling scan shimmer) and the Băng
##     Hà frost disc (rotating swirl bands).
##   * Procedural PIL textures (tools/build_skill_assets.py):
##     fx_glow / fx_ring / fx_petal / fx_shard / fx_streak /
##     fx_flake.
##
## Everything here is PRESENTATION ONLY: Main's deterministic
## skill sim calls in at cast / zone / impact moments; nothing in
## this file feeds back into sim state, checksums or snapshots.
## Live nodes are pooled by lifetime and freed by timers, with a
## hard cap like the VFX layer's.

const MAX_LIVE := 90

var _live: Array = [] # Array[Node] — timed effect roots
var _handles := {} # int -> Node2D (travelling shot visuals)
var _next_handle := 1

var _tex_glow: Texture2D
var _tex_ring: Texture2D
var _tex_petal: Texture2D
var _tex_shard: Texture2D
var _tex_streak: Texture2D
var _tex_flake: Texture2D
var _dome_shader: Shader
var _frost_shader: Shader

const DOME_GLSL := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform float fade = 1.0;
void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float fill = smoothstep(1.0, 0.90, r) * 0.14;
	float rim = smoothstep(0.86, 0.995, r) * smoothstep(1.0, 0.97, r) * 0.6;
	float scan = 0.05 * (0.5 + 0.5 * sin(UV.y * 44.0 - TIME * 2.2)) * (1.0 - r);
	COLOR = vec4(tint.rgb, (fill + rim + scan) * fade);
}
"""

const FROST_GLSL := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform float fade = 1.0;
void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float ang = atan(c.y, c.x);
	float swirl = 0.5 + 0.5 * sin(ang * 3.0 + r * 11.0 - TIME * 1.6);
	float a = smoothstep(1.0, 0.5, r) * (0.07 + 0.14 * swirl);
	COLOR = vec4(tint.rgb, a * fade);
}
"""


func _ready() -> void:
	_tex_glow = load("res://assets/vfx/fx_glow.png")
	_tex_ring = load("res://assets/vfx/fx_ring.png")
	_tex_petal = load("res://assets/vfx/fx_petal.png")
	_tex_shard = load("res://assets/vfx/fx_shard.png")
	_tex_streak = load("res://assets/vfx/fx_streak.png")
	_tex_flake = load("res://assets/vfx/fx_flake.png")
	_dome_shader = Shader.new()
	_dome_shader.code = DOME_GLSL
	_frost_shader = Shader.new()
	_frost_shader.code = FROST_GLSL
	z_index = 97


func _ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var pts := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in range(colors.size()):
		pts.append(float(i) / maxf(1.0, float(colors.size() - 1)))
		cols.append(colors[i])
	g.offsets = pts
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _scale_curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


## One GPUParticles2D emitter with a fully-built process material.
func _emitter(tex: Texture2D, amount: int, lifetime: float,
		one_shot: bool, opts: Dictionary) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = float(opts.get("explosiveness", 0.9 if one_shot else 0.0))
	p.local_coords = bool(opts.get("local_coords", true))
	p.visibility_rect = Rect2(-900, -900, 1800, 1800)
	p.z_index = int(opts.get("z", 4))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = float(opts.get("emit_radius", 4.0))
	m.direction = Vector3(opts.get("dir", Vector2(0, -1)).x,
			opts.get("dir", Vector2(0, -1)).y, 0)
	m.spread = float(opts.get("spread", 45.0))
	m.initial_velocity_min = float(opts.get("vel_min", 40.0))
	m.initial_velocity_max = float(opts.get("vel_max", 90.0))
	m.gravity = Vector3(0, float(opts.get("gravity", 0.0)), 0)
	m.damping_min = float(opts.get("damp_min", 0.0))
	m.damping_max = float(opts.get("damp_max", 0.0))
	m.scale_min = float(opts.get("scale_min", 0.7))
	m.scale_max = float(opts.get("scale_max", 1.3))
	if opts.has("ramp"):
		m.color_ramp = _ramp(opts["ramp"])
	if opts.has("scale_curve"):
		m.scale_curve = _scale_curve(opts["scale_curve"])
	p.process_material = m
	return p


func _track(node: Node, life: float) -> void:
	add_child(node)
	_live.append(node)
	if _live.size() > MAX_LIVE:
		var old: Node = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := create_tween()
	tw.tween_interval(life)
	tw.tween_callback(func() -> void:
		_live.erase(node)
		if is_instance_valid(node):
			node.queue_free())


func _burst(pos: Vector2, tex: Texture2D, amount: int, life: float,
		ramp: Array, opts: Dictionary = {}) -> void:
	var root := Node2D.new()
	root.position = pos
	var o := {"ramp": ramp}
	for k in opts:
		o[k] = opts[k]
	root.add_child(_emitter(tex, amount, life, true, o))
	_track(root, life + 0.25)


func _sprite(tex: Texture2D, pos: Vector2, size: float, col: Color,
		z := 3) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.modulate = col
	s.z_index = z
	if tex != null:
		var ts := tex.get_size()
		if ts.x > 0.0:
			s.scale = Vector2.ONE * (size / ts.x)
	return s


# ---------------------------------------------------------------- casts
## Cast flash at the hero: coloured mote burst + a rising ring.
func cast_fx(pos: Vector2, col: Color) -> void:
	_burst(pos + Vector2(0, -22), _tex_glow, 12, 0.5,
			[col, Color(col.r, col.g, col.b, 0.0)],
			{"emit_radius": 10.0, "vel_min": 25.0, "vel_max": 65.0,
			"dir": Vector2(0, -1), "spread": 70.0})
	var ring := _sprite(_tex_ring, pos, 30.0, col, 3)
	_track(ring, 0.45)
	var tw := create_tween()
	tw.tween_property(ring, "scale", ring.scale * 2.6, 0.42)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.42)


## Kiếm Khí / Thương Băng travelling shots: a glowing head sprite
## + a continuous streak emitter (local_coords = false so the
## particles stay behind as a trail). Returns a handle Main moves
## every frame and ends at impact / range-out.
func spawn_shot(kind: String, pos: Vector2, dir: Vector2) -> int:
	var root := Node2D.new()
	root.position = pos
	root.rotation = dir.angle()
	var head: Sprite2D
	var trail_col: Color
	if kind == "ice_spear":
		head = _sprite(_tex_shard, Vector2.ZERO, 44.0,
				Color(0.75, 0.92, 1.0), 6)
		head.rotation = PI * 0.25 # shard art points up; aim along +x
		trail_col = Color(0.62, 0.85, 1.0, 0.85)
	else:
		head = _sprite(_tex_streak, Vector2.ZERO, 74.0,
				Color(1.0, 0.82, 0.42), 6)
		trail_col = Color(1.0, 0.62, 0.25, 0.85)
	root.add_child(head)
	var trail := _emitter(_tex_streak if kind != "ice_spear" else _tex_shard,
			26, 0.34, false,
			{"local_coords": false, "emit_radius": 3.0,
			"vel_min": 4.0, "vel_max": 18.0, "spread": 26.0,
			"dir": Vector2(-1, 0), "z": 5,
			"ramp": [trail_col, Color(trail_col.r, trail_col.g, trail_col.b, 0.0)],
			"scale_min": 0.5, "scale_max": 1.0})
	root.add_child(trail)
	add_child(root)
	var h := _next_handle
	_next_handle += 1
	_handles[h] = root
	return h


func move_shot(handle: int, pos: Vector2) -> void:
	var n: Node2D = _handles.get(handle)
	if n != null and is_instance_valid(n):
		n.position = pos


func end_shot(handle: int, impact_col: Color) -> void:
	var n: Node2D = _handles.get(handle)
	_handles.erase(handle)
	if n == null or not is_instance_valid(n):
		return
	var pos := n.position
	n.queue_free()
	_burst(pos, _tex_glow, 10, 0.4,
			[impact_col, Color(impact_col.r, impact_col.g, impact_col.b, 0.0)],
			{"emit_radius": 6.0, "vel_min": 30.0, "vel_max": 80.0,
			"spread": 180.0})


## Thiên Thạch Ma Thuật (16b): a violet-glowing arcane meteor
## falls from the sky and slams in — dust ring, debris burst,
## crater glow. Calls back for the camera shake at the impact
## frame. (Same plunge body the old roster's falling-blade
## visual used; the projectile is now a glowing orb, tinted
## arcane violet — no hero-specific asset.)
func plunge_fx(pos: Vector2, on_impact: Callable) -> void:
	var root := Node2D.new()
	root.position = pos
	var sword := _sprite(_tex_glow, Vector2(0, -330), 120.0,
			Color(0.72, 0.5, 1.0, 0.95), 8)
	root.add_child(sword)
	# Warning ring on the ground while the sword falls.
	var ring := _sprite(_tex_ring, Vector2.ZERO, 128.0,
			Color(0.72, 0.5, 1.0, 0.75), 3)
	root.add_child(ring)
	add_child(root)
	_live.append(root)
	var tw := create_tween()
	tw.tween_property(sword, "position:y", -46.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		on_impact.call()
		ring.queue_free()
		_burst(pos, _tex_glow, 22, 0.6,
				[Color(0.85, 0.65, 1.0), Color(0.5, 0.3, 0.9, 0.0)],
				{"emit_radius": 16.0, "vel_min": 60.0, "vel_max": 190.0,
				"dir": Vector2(0, -0.4), "spread": 180.0, "gravity": 260.0})
		var dust := _sprite(_tex_ring, pos, 60.0, Color(0.85, 0.7, 0.5, 0.65), 3)
		_track(dust, 0.65)
		var dtw := create_tween()
		dtw.tween_property(dust, "scale", dust.scale * 4.6, 0.6)
		dtw.parallel().tween_property(dust, "modulate:a", 0.0, 0.6)
		var glow := _sprite(_tex_glow, pos, 150.0, Color(0.7, 0.5, 1.0, 0.5), 2)
		_track(glow, 0.5)
		var gtw := create_tween()
		gtw.tween_property(glow, "modulate:a", 0.0, 0.5)
	)
	tw.tween_interval(0.55)
	tw.tween_callback(func() -> void:
		_live.erase(root)
		if is_instance_valid(root):
			root.queue_free())


## Thánh Quang Phán Xét: a pillar of light with rising rays.
func pillar_fx(pos: Vector2, radius: float) -> void:
	var root := Node2D.new()
	root.position = pos
	var beam := _sprite(_tex_glow, Vector2(0, -120), radius * 1.5,
			Color(1.0, 0.95, 0.72, 0.55), 5)
	beam.scale.y *= 3.4
	root.add_child(beam)
	var ring := _sprite(_tex_ring, Vector2.ZERO, radius * 2.0,
			Color(1.0, 0.9, 0.5, 0.85), 3)
	root.add_child(ring)
	root.add_child(_emitter(_tex_streak, 20, 0.8, false,
			{"emit_radius": radius * 0.7, "vel_min": 60.0, "vel_max": 130.0,
			"dir": Vector2(0, -1), "spread": 24.0, "z": 6,
			"ramp": [Color(1.0, 0.96, 0.75, 0.9), Color(1.0, 0.9, 0.5, 0.0)],
			"scale_min": 0.5, "scale_max": 0.9}))
	_track(root, 0.95)
	var tw := create_tween()
	tw.tween_property(beam, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.9).set_delay(0.25)


## Vạn Hoa Khai Thiên: bloom flash, expanding double ring, sparkle rain.
func bloom_fx(pos: Vector2, radius: float) -> void:
	_burst(pos, _tex_petal, 26, 1.1,
			[Color(1.0, 0.75, 0.85, 0.95), Color(1.0, 0.6, 0.75, 0.0)],
			{"emit_radius": radius * 0.8, "vel_min": 15.0, "vel_max": 55.0,
			"dir": Vector2(0, 1), "spread": 180.0, "gravity": 34.0})
	_burst(pos, _tex_glow, 18, 0.7,
			[Color(1.0, 0.9, 0.6, 0.9), Color(1.0, 0.8, 0.45, 0.0)],
			{"emit_radius": radius * 0.5, "vel_min": 30.0, "vel_max": 95.0,
			"dir": Vector2(0, -1), "spread": 180.0})
	for i in range(2):
		var ring := _sprite(_tex_ring, pos, 40.0 + i * 26.0,
				Color(1.0, 0.8, 0.5, 0.8), 3)
		_track(ring, 0.8)
		var tw := create_tween()
		tw.tween_property(ring, "scale", ring.scale * (radius * 2.0 / (40.0 + i * 26.0)), 0.75)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.75)


## Freeze landing (Thương Băng first hit): crystal burst + a
## lingering frost puff at the victim.
func freeze_fx(pos: Vector2) -> void:
	_burst(pos + Vector2(0, -20), _tex_shard, 12, 0.55,
			[Color(0.8, 0.93, 1.0, 0.95), Color(0.5, 0.75, 1.0, 0.0)],
			{"emit_radius": 8.0, "vel_min": 35.0, "vel_max": 95.0,
			"spread": 180.0, "gravity": 120.0})
	var puff := _sprite(_tex_glow, pos + Vector2(0, -18), 64.0,
			Color(0.65, 0.85, 1.0, 0.4), 4)
	_track(puff, 1.5)
	var tw := create_tween()
	tw.tween_property(puff, "modulate:a", 0.0, 1.5).set_delay(0.6)


## A shield shimmer pop when a dome shield first covers a unit.
func shield_fx(pos: Vector2) -> void:
	var ring := _sprite(_tex_ring, pos + Vector2(0, -20), 44.0,
			Color(1.0, 0.92, 0.6, 0.8), 4)
	_track(ring, 0.5)
	var tw := create_tween()
	tw.tween_property(ring, "scale", ring.scale * 1.35, 0.45)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.45)


# ---------------------------------------------------------------- 14c
## A lightning / energy arc between two points (Lôi Chấn's dash
## trail, chain segments and mark/snipe links): a stretched
## streak + a bright end burst, gone in a blink.
func arc_fx(from: Vector2, to: Vector2, col: Color) -> void:
	var d := to - from
	var len := maxf(d.length(), 8.0)
	var root := Node2D.new()
	root.position = from + d * 0.5
	root.rotation = d.angle()
	var s := _sprite(_tex_streak, Vector2.ZERO, len,
			Color(col.r, col.g, col.b, 0.95), 6)
	s.scale.y *= 0.55
	root.add_child(s)
	var core := _sprite(_tex_streak, Vector2.ZERO, len * 0.9,
			Color(1.0, 1.0, 1.0, 0.75), 7)
	core.scale.y *= 0.22
	root.add_child(core)
	_track(root, 0.22)
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.22)
	_burst(to, _tex_glow, 8, 0.32,
			[col, Color(col.r, col.g, col.b, 0.0)],
			{"emit_radius": 5.0, "vel_min": 30.0, "vel_max": 85.0,
			"spread": 180.0})


## Diệm Phiến Toàn: a fan of flame along the facing direction.
func fan_fx(pos: Vector2, dir: Vector2) -> void:
	var root := Node2D.new()
	root.position = pos + Vector2(0, -18)
	root.rotation = dir.angle()
	var glow := _sprite(_tex_glow, Vector2(52, 0), 130.0,
			Color(1.0, 0.55, 0.2, 0.5), 5)
	glow.scale = Vector2(1.5, 0.72)
	root.add_child(glow)
	root.add_child(_emitter(_tex_streak, 22, 0.5, true,
			{"emit_radius": 8.0, "vel_min": 90.0, "vel_max": 190.0,
			"dir": Vector2(1, 0), "spread": 55.0, "z": 6,
			"ramp": [Color(1.0, 0.85, 0.45, 0.95), Color(0.95, 0.4, 0.12, 0.0)],
			"scale_min": 0.6, "scale_max": 1.2}))
	root.add_child(_emitter(_tex_glow, 14, 0.6, true,
			{"emit_radius": 8.0, "vel_min": 60.0, "vel_max": 140.0,
			"dir": Vector2(1, 0), "spread": 60.0, "z": 6,
			"ramp": [Color(1.0, 0.7, 0.3, 0.9), Color(0.9, 0.3, 0.1, 0.0)],
			"scale_min": 0.5, "scale_max": 1.0}))
	_track(root, 0.7)
	var tw := create_tween()
	tw.tween_property(glow, "modulate:a", 0.0, 0.45)


## Phượng Hỏa Giáng: a phoenix of fire dives from the sky and
## bursts over the target — modelled on plunge_fx's structure.
func phoenix_fx(pos: Vector2, radius: float, on_impact: Callable) -> void:
	var root := Node2D.new()
	root.position = pos
	var bird := _sprite(_tex_glow, Vector2(120, -300), 170.0,
			Color(1.0, 0.62, 0.2, 0.95), 8)
	bird.scale = Vector2(1.6, 0.8)
	root.add_child(bird)
	var trail := _emitter(_tex_streak, 24, 0.5, false,
			{"local_coords": false, "emit_radius": 6.0,
			"vel_min": 6.0, "vel_max": 22.0, "spread": 30.0,
			"dir": Vector2(0.35, 1), "z": 7,
			"ramp": [Color(1.0, 0.75, 0.35, 0.9), Color(0.92, 0.35, 0.1, 0.0)],
			"scale_min": 0.6, "scale_max": 1.2})
	trail.position = bird.position
	root.add_child(trail)
	var ring := _sprite(_tex_ring, Vector2.ZERO, radius * 1.7,
			Color(1.0, 0.5, 0.2, 0.7), 3)
	root.add_child(ring)
	add_child(root)
	_live.append(root)
	var tw := create_tween()
	tw.tween_property(bird, "position", Vector2(0, -30), 0.36) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(trail, "position", Vector2(0, -30), 0.36) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		on_impact.call()
		bird.queue_free()
		trail.queue_free()
		ring.queue_free()
		_burst(pos + Vector2(0, -16), _tex_glow, 30, 0.7,
				[Color(1.0, 0.8, 0.4), Color(0.92, 0.35, 0.1, 0.0)],
				{"emit_radius": radius * 0.5, "vel_min": 70.0, "vel_max": 210.0,
				"dir": Vector2(0, -0.5), "spread": 180.0, "gravity": 240.0})
		var dust := _sprite(_tex_ring, pos, 60.0, Color(1.0, 0.6, 0.25, 0.6), 3)
		_track(dust, 0.7)
		var dtw := create_tween()
		dtw.tween_property(dust, "scale", dust.scale * (radius * 2.2 / 60.0), 0.65)
		dtw.parallel().tween_property(dust, "modulate:a", 0.0, 0.65)
		var glow2 := _sprite(_tex_glow, pos, radius * 2.0,
				Color(1.0, 0.55, 0.2, 0.5), 2)
		_track(glow2, 0.55)
		var gtw := create_tween()
		gtw.tween_property(glow2, "modulate:a", 0.0, 0.55)
	)
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		_live.erase(root)
		if is_instance_valid(root):
			root.queue_free())


# ---------------------------------------------------------------- zones
## A lingering zone visual; Main spawns it with the sim zone and it
## lives `dur` seconds, fading at the end. Kinds: heal_rain
## (petals + rising sparkles + ground ring), blizzard (driving
## snow + swirl frost disc), dome (shader dome + shield sparkles).
func zone_fx(kind: String, pos: Vector2, radius: float, dur: float) -> void:
	var root := Node2D.new()
	root.position = pos
	match kind:
		"heal_rain":
			var ring := _sprite(_tex_ring, Vector2.ZERO, radius * 2.0,
					Color(1.0, 0.72, 0.82, 0.55), 2)
			root.add_child(ring)
			root.add_child(_emitter(_tex_petal, 30, 1.5, false,
					{"emit_radius": radius * 0.9, "vel_min": 6.0, "vel_max": 20.0,
					"dir": Vector2(0, 1), "spread": 40.0, "gravity": 26.0, "z": 6,
					"ramp": [Color(1.0, 0.78, 0.86, 0.95), Color(1.0, 0.62, 0.74, 0.55)],
					"scale_min": 0.7, "scale_max": 1.2}))
			root.add_child(_emitter(_tex_glow, 16, 1.3, false,
					{"emit_radius": radius * 0.85, "vel_min": 10.0, "vel_max": 26.0,
					"dir": Vector2(0, -1), "spread": 60.0, "z": 5,
					"ramp": [Color(0.75, 1.0, 0.8, 0.0), Color(0.75, 1.0, 0.8, 0.8),
						Color(0.75, 1.0, 0.8, 0.0)],
					"scale_min": 0.35, "scale_max": 0.7}))
		"blizzard":
			var disc := _sprite(_tex_glow, Vector2.ZERO, radius * 2.1,
					Color(0.75, 0.9, 1.0, 1.0), 2)
			var sm := ShaderMaterial.new()
			sm.shader = _frost_shader
			sm.set_shader_parameter("tint", Color(0.75, 0.9, 1.0))
			disc.material = sm
			root.add_child(disc)
			root.add_child(_emitter(_tex_flake, 64, 1.6, false,
					{"emit_radius": radius, "vel_min": 55.0, "vel_max": 120.0,
					"dir": Vector2(0.85, 0.5), "spread": 36.0, "z": 6,
					"ramp": [Color(0.92, 0.97, 1.0, 1.0), Color(0.8, 0.9, 1.0, 0.55)],
					"scale_min": 0.6, "scale_max": 1.3}))
			root.add_child(_emitter(_tex_streak, 18, 0.7, false,
					{"emit_radius": radius * 0.8, "vel_min": 90.0, "vel_max": 170.0,
					"dir": Vector2(1, 0.25), "spread": 16.0, "z": 5,
					"ramp": [Color(0.85, 0.93, 1.0, 0.5), Color(0.85, 0.93, 1.0, 0.0)],
					"scale_min": 0.6, "scale_max": 1.2}))
		"dome":
			var dome := _sprite(_tex_glow, Vector2(0, -radius * 0.32),
					radius * 2.15, Color(1.0, 0.9, 0.55, 1.0), 3)
			var sm2 := ShaderMaterial.new()
			sm2.shader = _dome_shader
			sm2.set_shader_parameter("tint", Color(1.0, 0.9, 0.55))
			dome.material = sm2
			root.add_child(dome)
			var ring2 := _sprite(_tex_ring, Vector2.ZERO, radius * 2.0,
					Color(1.0, 0.88, 0.5, 0.8), 3)
			root.add_child(ring2)
			root.add_child(_emitter(_tex_glow, 14, 1.8, false,
					{"emit_radius": radius * 0.92, "vel_min": 8.0, "vel_max": 22.0,
					"dir": Vector2(0, -1), "spread": 180.0, "z": 5,
					"ramp": [Color(1.0, 0.93, 0.65, 0.0), Color(1.0, 0.93, 0.65, 0.75),
						Color(1.0, 0.93, 0.65, 0.0)],
					"scale_min": 0.3, "scale_max": 0.6}))
		"storm":
			var sdisc := _sprite(_tex_glow, Vector2.ZERO, radius * 2.1,
					Color(0.55, 0.68, 1.0, 0.35), 2)
			root.add_child(sdisc)
			var sring := _sprite(_tex_ring, Vector2.ZERO, radius * 2.0,
					Color(0.62, 0.76, 1.0, 0.8), 3)
			root.add_child(sring)
			root.add_child(_emitter(_tex_streak, 30, 0.5, false,
					{"emit_radius": radius * 0.9, "vel_min": 130.0, "vel_max": 230.0,
					"dir": Vector2(0.15, 1), "spread": 14.0, "z": 6,
					"ramp": [Color(0.8, 0.88, 1.0, 0.9), Color(0.55, 0.7, 1.0, 0.0)],
					"scale_min": 0.5, "scale_max": 1.0}))
			root.add_child(_emitter(_tex_glow, 12, 0.8, false,
					{"emit_radius": radius * 0.85, "vel_min": 12.0, "vel_max": 34.0,
					"dir": Vector2(0, -1), "spread": 180.0, "z": 5,
					"ramp": [Color(0.65, 0.78, 1.0, 0.0), Color(0.65, 0.78, 1.0, 0.7),
						Color(0.65, 0.78, 1.0, 0.0)],
					"scale_min": 0.3, "scale_max": 0.6}))
		"fire_ground":
			var fdisc := _sprite(_tex_glow, Vector2.ZERO, radius * 2.05,
					Color(1.0, 0.5, 0.16, 0.4), 2)
			root.add_child(fdisc)
			var fring := _sprite(_tex_ring, Vector2.ZERO, radius * 2.0,
					Color(1.0, 0.58, 0.22, 0.75), 3)
			root.add_child(fring)
			root.add_child(_emitter(_tex_glow, 26, 1.1, false,
					{"emit_radius": radius * 0.9, "vel_min": 16.0, "vel_max": 44.0,
					"dir": Vector2(0, -1), "spread": 50.0, "z": 6,
					"ramp": [Color(1.0, 0.72, 0.3, 0.85), Color(0.92, 0.35, 0.1, 0.0)],
					"scale_min": 0.5, "scale_max": 1.1}))
			root.add_child(_emitter(_tex_streak, 10, 0.6, false,
					{"emit_radius": radius * 0.8, "vel_min": 30.0, "vel_max": 70.0,
					"dir": Vector2(0, -1), "spread": 30.0, "z": 5,
					"ramp": [Color(1.0, 0.85, 0.45, 0.8), Color(1.0, 0.5, 0.15, 0.0)],
					"scale_min": 0.4, "scale_max": 0.8}))
		"arrow_rain":
			var aring := _sprite(_tex_ring, Vector2.ZERO, radius * 2.0,
					Color(0.75, 0.95, 0.8, 0.7), 3)
			root.add_child(aring)
			root.add_child(_emitter(_tex_streak, 40, 0.55, false,
					{"emit_radius": radius * 0.95, "vel_min": 200.0, "vel_max": 300.0,
					"dir": Vector2(0.3, 1), "spread": 8.0, "z": 6,
					"ramp": [Color(0.9, 1.0, 0.92, 0.95), Color(0.7, 0.9, 0.75, 0.0)],
					"scale_min": 0.45, "scale_max": 0.8}))
		"cyclone":
			var cdisc := _sprite(_tex_glow, Vector2.ZERO, radius * 2.1,
					Color(0.62, 0.95, 0.9, 1.0), 2)
			var csm := ShaderMaterial.new()
			csm.shader = _frost_shader
			csm.set_shader_parameter("tint", Color(0.62, 0.95, 0.9))
			cdisc.material = csm
			root.add_child(cdisc)
			var cring := _sprite(_tex_ring, Vector2.ZERO, radius * 2.0,
					Color(0.7, 1.0, 0.95, 0.85), 3)
			root.add_child(cring)
			root.add_child(_emitter(_tex_streak, 34, 0.8, false,
					{"emit_radius": radius * 0.85, "vel_min": 70.0, "vel_max": 140.0,
					"dir": Vector2(1, -0.2), "spread": 40.0, "z": 6,
					"ramp": [Color(0.85, 1.0, 0.97, 0.8), Color(0.6, 0.95, 0.9, 0.0)],
					"scale_min": 0.5, "scale_max": 1.1}))
			root.add_child(_emitter(_tex_glow, 16, 1.2, false,
					{"emit_radius": radius * 0.9, "vel_min": 10.0, "vel_max": 30.0,
					"dir": Vector2(0, -1), "spread": 180.0, "z": 5,
					"ramp": [Color(0.7, 1.0, 0.95, 0.0), Color(0.7, 1.0, 0.95, 0.7),
						Color(0.7, 1.0, 0.95, 0.0)],
					"scale_min": 0.3, "scale_max": 0.65}))
	add_child(root)
	_live.append(root)
	if _live.size() > MAX_LIVE:
		var old: Node = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	# Fade the whole zone out over its last second.
	var tw := create_tween()
	tw.tween_interval(maxf(dur - 1.0, 0.0))
	tw.tween_property(root, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func() -> void:
		_live.erase(root)
		if is_instance_valid(root):
			root.queue_free())
