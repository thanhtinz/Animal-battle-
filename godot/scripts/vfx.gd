class_name VFX
extends Node2D
## Shared lightweight effects layer (built 2026-11-08, Tín's VFX pass).
## One Node2D owned by Main at a high z_index; every effect is a plain
## Sprite2D with a runtime-generated soft texture (radial dot, ring,
## spark streak, 4-point star) animated by hand in _process — no
## particle nodes, no per-frame allocations beyond spawning.
##
## Live effects are hard-capped at MAX_LIVE; spawning past the cap
## recycles the oldest effect. Effects always free themselves.
##
## Palettes: PLAYER = warm gold/red (the player's Roman red/gold),
## ENEMY = deep blue/silver (designed for the P3 enemy faction — the
## combat entry points hit_spark / death_smoke / arrow_trail already
## accept a palette and are exercised by the test suite; they get real
## callers when combat lands in P3).

const MAX_LIVE := 240

const PALETTE_SPARK := {
	"player": [Color(1.0, 0.78, 0.30), Color(1.0, 0.45, 0.22), Color(1.0, 0.92, 0.65)],
	"enemy": [Color(0.30, 0.50, 1.0), Color(0.72, 0.80, 0.95), Color(0.55, 0.75, 1.0)],
	# Per-SLOT palettes (team-colors pass): slot0/1 mirror the legacy
	# player/enemy sets; slot2 = greens, slot3 = ambers. Callers key
	# these via TeamColors.vfx_palette(owner_id).
	"slot0": [Color(1.0, 0.78, 0.30), Color(1.0, 0.45, 0.22), Color(1.0, 0.92, 0.65)],
	"slot1": [Color(0.30, 0.50, 1.0), Color(0.72, 0.80, 0.95), Color(0.55, 0.75, 1.0)],
	"slot2": [Color(0.55, 1.0, 0.45), Color(0.25, 0.80, 0.30), Color(0.85, 1.0, 0.70)],
	"slot3": [Color(1.0, 0.85, 0.30), Color(1.0, 0.62, 0.15), Color(1.0, 0.95, 0.60)],
	# 13z slots 4-7, keyed to the approved queue colours.
	"slot4": [Color(0.78, 0.55, 1.0), Color(0.55, 0.30, 0.95), Color(0.92, 0.80, 1.0)],
	"slot5": [Color(1.0, 0.68, 0.30), Color(1.0, 0.45, 0.10), Color(1.0, 0.85, 0.55)],
	"slot6": [Color(0.40, 1.0, 0.90), Color(0.10, 0.80, 0.70), Color(0.75, 1.0, 0.95)],
	"slot7": [Color(1.0, 0.62, 0.82), Color(0.95, 0.35, 0.62), Color(1.0, 0.85, 0.92)],
}
const PALETTE_SMOKE := {
	"player": Color(0.60, 0.53, 0.46, 0.50),
	"enemy": Color(0.40, 0.50, 0.78, 0.55),
	"slot0": Color(0.60, 0.53, 0.46, 0.50),
	"slot1": Color(0.40, 0.50, 0.78, 0.55),
	"slot2": Color(0.45, 0.58, 0.42, 0.50),
	"slot3": Color(0.62, 0.55, 0.38, 0.50),
	"slot4": Color(0.52, 0.44, 0.66, 0.50),
	"slot5": Color(0.66, 0.52, 0.40, 0.50),
	"slot6": Color(0.42, 0.60, 0.56, 0.50),
	"slot7": Color(0.66, 0.50, 0.56, 0.50),
}
const FOAM_COLOR := Color(0.97, 0.99, 1.0, 0.68)
const RIPPLE_COLOR := Color(0.78, 0.90, 1.0, 0.50)
const SHIMMER_COLOR := Color(0.85, 0.95, 1.0, 0.85)

var game = null # Main (duck-typed) — used for the pause flag
var world = null # World (duck-typed) — water/shore cell data
var cam: Camera2D = null # view rect for shimmer/ripple placement

var ambient_enabled := true # water + chimney emitters (tests toggle this)

var _live: Array = [] # Array[Dictionary] effect records
var _tex_dot: Texture2D
var _tex_ring: Texture2D
var _tex_streak: Texture2D
var _tex_star: Texture2D
var _rng := RandomNumberGenerator.new()

# Water ambience state.
var _water_cells: Array = [] # Array[Vector2i]
var _shore_foam: Array = [] # Array[{pos: Vector2, dir: Vector2}]
var _foam_idx := 0
var _foam_timer := 0.0
var _shimmer_timer := 0.0
var _ripple_timer := 3.0
# Blacksmith chimney smoke state.
var _smoke_timer := 0.0
# Biome ambience: "water" (grassland lake) | "desert" (oasis water +
# drifting sand glints) | "snow" (falling snow, lake frozen over).
var ambient_mode := "water"
var _sand_timer := 0.0
var _snow_timer := 0.0
# Waterfall foam/mist anchors (world positions from World).
var falls_points: Array = []
var _falls_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	_tex_dot = _make_dot_texture()
	_tex_ring = _make_ring_texture()
	_tex_streak = _make_streak_texture()
	_tex_star = _make_star_texture()


## Called by Main once the world is generated: collects the lake's
## water cells and precomputes a foam anchor (point + direction toward
## open water) for every shore cell.
func bind(p_game, p_world, p_cam) -> void:
	game = p_game
	world = p_world
	cam = p_cam
	_water_cells.clear()
	_shore_foam.clear()
	if world == null:
		return
	ambient_mode = String(world.biome().get("ambient", "water"))
	falls_points = world.falls_foam_points()
	if ambient_mode == "snow":
		# The lake is frozen: no foam, shimmer or ripples on ice.
		return
	for c in world.water:
		_water_cells.append(c)
		if not world.ground_tile_key(c).begins_with("shore"):
			continue
		var land_sum := Vector2.ZERO
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if world._is_land(c + d):
				land_sum += Vector2(d)
		if land_sum == Vector2.ZERO:
			continue
		var to_water := -land_sum.normalized()
		_shore_foam.append({
			"pos": world.cell_center(c) + to_water * 12.0,
			"dir": to_water,
		})
	# Shuffle once so the round-robin foam cycle has no spatial sweep.
	for i in range(_shore_foam.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = _shore_foam[i]
		_shore_foam[i] = _shore_foam[j]
		_shore_foam[j] = tmp


func live_count() -> int:
	return _live.size()


# ---------------------------------------------------------------- textures

func _make_dot_texture() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var centre := Vector2(s, s) * 0.5
	for y in range(s):
		for x in range(s):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre) / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _make_ring_texture() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var centre := Vector2(s, s) * 0.5
	for y in range(s):
		for x in range(s):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre) / (s * 0.5)
			var band := 1.0 - clampf(absf(d - 0.86) / 0.14, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, band * band))
	return ImageTexture.create_from_image(img)


func _make_streak_texture() -> Texture2D:
	var w := 24
	var h := 6
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var nx := absf((float(x) + 0.5) / w * 2.0 - 1.0)
			var ny := absf((float(y) + 0.5) / h * 2.0 - 1.0)
			var a := pow(clampf(1.0 - nx, 0.0, 1.0), 1.5) * clampf(1.0 - ny, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_star_texture() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var nx := (float(x) + 0.5) / s * 2.0 - 1.0
			var ny := (float(y) + 0.5) / s * 2.0 - 1.0
			var arm_a := pow(clampf(1.0 - absf(nx), 0.0, 1.0), 3.0) * pow(clampf(1.0 - absf(ny), 0.0, 1.0), 0.35)
			var arm_b := pow(clampf(1.0 - absf(ny), 0.0, 1.0), 3.0) * pow(clampf(1.0 - absf(nx), 0.0, 1.0), 0.35)
			var core := clampf(1.0 - Vector2(nx, ny).length(), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(arm_a, arm_b) + core * 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- spawning

func _kill_oldest() -> void:
	if _live.is_empty():
		return
	var e: Dictionary = _live.pop_front()
	if is_instance_valid(e.node):
		e.node.queue_free()


func _spawn(kind: String, tex: Texture2D, pos: Vector2, col: Color, life: float,
		s0: float, s1: float, vel := Vector2.ZERO, grav := 0.0, drag := 0.0,
		rot := 0.0, dir := Vector2.ZERO) -> void:
	while _live.size() >= MAX_LIVE:
		_kill_oldest()
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.position = pos
	spr.rotation = rot
	spr.scale = Vector2.ONE * s0
	spr.modulate = Color(col.r, col.g, col.b, col.a)
	add_child(spr)
	_live.append({
		"node": spr, "kind": kind, "t": 0.0, "life": life,
		"col": Color(col.r, col.g, col.b), "a0": col.a,
		"s0": s0, "s1": s1, "vel": vel, "grav": grav, "drag": drag,
		"base": pos, "dir": dir,
	})


## Radial spray of soft dots (dust, leaves, debris). `grav` positive
## pulls them down (leaves), negative floats them up.
func burst(pos: Vector2, colors: Array, count := 8, speed := 60.0, life := 0.45,
		size := 7.0, grav := 60.0) -> void:
	for i in range(count):
		var ang := _rng.randf() * TAU
		var sp := speed * _rng.randf_range(0.35, 1.0)
		var col: Color = colors[_rng.randi_range(0, colors.size() - 1)]
		_spawn("dot", _tex_dot, pos, col, life * _rng.randf_range(0.7, 1.25),
				size / 32.0 * _rng.randf_range(0.7, 1.3), size / 32.0 * 0.4,
				Vector2(cos(ang), sin(ang)) * sp, grav, 1.6)


## Slow rising smoke/dust cloud: dots that grow and fade.
func puff(pos: Vector2, col := Color(0.62, 0.58, 0.52, 0.5), count := 5,
		rise := 26.0, life := 1.4, size := 16.0) -> void:
	for i in range(count):
		var off := Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-3.0, 3.0))
		_spawn("dot", _tex_dot, pos + off, col, life * _rng.randf_range(0.75, 1.3),
				size / 32.0 * _rng.randf_range(0.6, 0.9), size / 32.0 * _rng.randf_range(1.5, 2.1),
				Vector2(_rng.randf_range(-4.0, 4.0), -rise * _rng.randf_range(0.7, 1.2)), 0.0, 0.4)


## One tiny star sparkle that pops in and out.
func glint(pos: Vector2, col := Color(1.0, 0.9, 0.55, 0.9), size := 12.0, life := 0.5) -> void:
	_spawn("glint", _tex_star, pos, col, life, size / 32.0, size / 32.0,
			Vector2(_rng.randf_range(-3.0, 3.0), -4.0), 0.0, 0.0, _rng.randf() * 0.6 - 0.3)


## Expanding fading ring (ripples, completion shockwave).
func ripple(pos: Vector2, col := Color(0.8, 0.9, 1.0, 0.5), max_r := 26.0, life := 1.6) -> void:
	# Ring texture: radius sits at 0.86 of the half-size, so the drawn
	# radius is scale * 64 * 0.43.
	_spawn("ring", _tex_ring, pos, col, life, 4.0 / 27.5, max_r / 27.5)


## Brief radial glow.
func flash(pos: Vector2, col := Color(1.0, 0.95, 0.8, 0.85), size := 60.0, life := 0.3) -> void:
	_spawn("flash", _tex_dot, pos, col, life, size / 32.0 * 0.6, size / 32.0 * 1.15)


## One oriented spark streak travelling along `dir` (projectile trails).
func trail_segment(pos: Vector2, dir: Vector2, col: Color, life := 0.25) -> void:
	var v := dir.normalized() * 30.0
	_spawn("streak", _tex_streak, pos, col, life, 0.9, 0.5, v, 0.0, 0.0, dir.angle())


# ---------------------------------------------------------------- combat-ready (P3 callers)

## Melee/ranged impact: streak sparks + a small flash, tinted by faction.
func hit_spark(pos: Vector2, palette := "player") -> void:
	var colors: Array = PALETTE_SPARK.get(palette, PALETTE_SPARK["player"])
	for i in range(10):
		var ang := _rng.randf() * TAU
		var sp := _rng.randf_range(50.0, 130.0)
		var col: Color = colors[_rng.randi_range(0, colors.size() - 1)]
		_spawn("streak", _tex_streak, pos, col, _rng.randf_range(0.18, 0.34),
				1.0, 0.55, Vector2(cos(ang), sin(ang)) * sp, 150.0, 2.2, ang)
	flash(pos, Color(colors[0], 0.55), 34.0, 0.22)


## Death: tinted smoke cloud + a few falling sparks.
func death_smoke(pos: Vector2, palette := "player") -> void:
	var smoke: Color = PALETTE_SMOKE.get(palette, PALETTE_SMOKE["player"])
	puff(pos + Vector2(0, -8), smoke, 8, 30.0, 1.6, 18.0)
	var colors: Array = PALETTE_SPARK.get(palette, PALETTE_SPARK["player"])
	burst(pos + Vector2(0, -10), colors, 5, 40.0, 0.5, 6.0, 130.0)


## One frame of an arrow's trail (P3 projectile code will call this
## per step); tinted by faction.
func arrow_trail(pos: Vector2, dir: Vector2, palette := "player") -> void:
	var colors: Array = PALETTE_SPARK.get(palette, PALETTE_SPARK["player"])
	trail_segment(pos, dir, Color(colors[2], 0.65), 0.22)


# ---------------------------------------------------------------- update loop

func _process(delta: float) -> void:
	if game != null and game.paused:
		return
	# 1) advance + reap effects.
	var i := _live.size() - 1
	while i >= 0:
		var e: Dictionary = _live[i]
		e.t += delta
		var tn: float = clampf(float(e.t) / float(e.life), 0.0, 1.0)
		if tn >= 1.0:
			if is_instance_valid(e.node):
				e.node.queue_free()
			_live.remove_at(i)
			i -= 1
			continue
		var spr: Sprite2D = e.node
		match String(e.kind):
			"dot":
				e.vel = Vector2(e.vel) * maxf(0.0, 1.0 - float(e.drag) * delta)
				e.vel = Vector2(e.vel) + Vector2(0, float(e.grav) * delta)
				spr.position += Vector2(e.vel) * delta
				spr.scale = Vector2.ONE * lerpf(float(e.s0), float(e.s1), tn)
				spr.modulate = Color(e.col, float(e.a0) * (1.0 - tn))
			"streak":
				e.vel = Vector2(e.vel) * maxf(0.0, 1.0 - float(e.drag) * delta)
				e.vel = Vector2(e.vel) + Vector2(0, float(e.grav) * delta)
				spr.position += Vector2(e.vel) * delta
				spr.rotation = Vector2(e.vel).angle()
				spr.scale = Vector2.ONE * lerpf(float(e.s0), float(e.s1), tn)
				spr.modulate = Color(e.col, float(e.a0) * (1.0 - tn))
			"glint":
				spr.position += Vector2(e.vel) * delta
				var pop := sin(PI * tn)
				spr.scale = Vector2.ONE * float(e.s0) * pop
				spr.modulate = Color(e.col, float(e.a0) * pop)
			"ring":
				var ease := 1.0 - pow(1.0 - tn, 2.0)
				spr.scale = Vector2.ONE * lerpf(float(e.s0), float(e.s1), ease)
				spr.modulate = Color(e.col, float(e.a0) * pow(1.0 - tn, 1.4))
			"flash":
				spr.scale = Vector2.ONE * lerpf(float(e.s0), float(e.s1), tn)
				spr.modulate = Color(e.col, float(e.a0) * pow(1.0 - tn, 2.0))
			"foam":
				var pulse := sin(PI * tn)
				spr.position = Vector2(e.base) + Vector2(e.dir) * (pulse * 3.0 - 1.5)
				spr.scale = Vector2.ONE * float(e.s0) * (0.85 + 0.3 * pulse)
				spr.modulate = Color(e.col, float(e.a0) * pulse)
		i -= 1
	# 2) ambient emitters.
	if ambient_enabled:
		_update_water(delta)
		_update_chimneys(delta)
		_update_falls(delta)
		if ambient_mode == "desert":
			_update_sand(delta)
		elif ambient_mode == "snow":
			_update_snowfall(delta)


## Waterfalls: foam ripples at each base + an occasional mist puff.
func _update_falls(delta: float) -> void:
	if falls_points.is_empty() or cam == null:
		return
	_falls_timer -= delta
	if _falls_timer > 0.0:
		return
	_falls_timer = 1.15
	var view := _view_rect()
	for p in falls_points:
		if not view.grow(40.0).has_point(p):
			continue
		ripple(p + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-3.0, 3.0)),
				Color(0.9, 0.97, 1.0, 0.55), 20.0, 1.3)
		if _rng.randf() < 0.45:
			_spawn("dot", _tex_dot, p + Vector2(0, -4), Color(1, 1, 1, 0.5),
					1.4, 0.5, 1.1, Vector2(_rng.randf_range(-3.0, 3.0), -9.0), 0.0, 0.3)


## Desert: warm glints drifting across in-view sand (heat shimmer
## suggestion) — a few star sparkles on random land cells.
func _update_sand(delta: float) -> void:
	if world == null or cam == null:
		return
	_sand_timer -= delta
	if _sand_timer > 0.0:
		return
	_sand_timer = 0.45
	var view := _view_rect()
	for tries in range(6):
		var c := Vector2i(
			randi_range(int(view.position.x / World.TILE), int(view.end.x / World.TILE)),
			randi_range(int(view.position.y / World.TILE), int(view.end.y / World.TILE)))
		if world.in_bounds(c) and not world.water.has(c):
			glint(world.cell_center(c) + Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-10.0, 10.0)),
					Color(1.0, 0.85, 0.5, 0.75), _rng.randf_range(7.0, 11.0), 0.8)
			return


## Snow: light falling snow across the camera view — small soft
## dots with a slow downward drift, spawned sparsely (hard-capped
## by MAX_LIVE like every other effect).
func _update_snowfall(delta: float) -> void:
	if cam == null:
		return
	_snow_timer -= delta
	if _snow_timer > 0.0:
		return
	_snow_timer = 0.14
	var view := _view_rect()
	for k in range(2):
		var pos := Vector2(
			_rng.randf_range(view.position.x, view.end.x),
			view.position.y + _rng.randf_range(0.0, view.size.y * 0.35))
		_spawn("dot", _tex_dot, pos, Color(1.0, 1.0, 1.0, 0.85), _rng.randf_range(2.2, 3.2),
				_rng.randf_range(0.10, 0.20), _rng.randf_range(0.10, 0.20),
				Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(17.0, 27.0)), 0.0, 0.02)


func _view_rect() -> Rect2:
	if cam == null:
		return Rect2()
	var view := get_viewport_rect().size / cam.zoom
	return Rect2(cam.position - view * 0.5, view).grow(16.0)


func _random_water_cell(in_view: bool) -> Vector2i:
	if _water_cells.is_empty():
		return Vector2i(-1, -1)
	var view := _view_rect() if in_view else Rect2()
	for tries in range(8):
		var c: Vector2i = _water_cells[_rng.randi_range(0, _water_cells.size() - 1)]
		if not in_view or view.has_point(world.cell_center(c)):
			return c
	return Vector2i(-1, -1)


func _update_water(delta: float) -> void:
	if world == null or _water_cells.is_empty():
		return
	# Shore foam: round-robin over the shuffled shore anchors so the
	# whole shoreline breathes with staggered phases.
	if not _shore_foam.is_empty():
		_foam_timer -= delta
		if _foam_timer <= 0.0:
			_foam_timer = 0.13
			for k in range(2):
				var f: Dictionary = _shore_foam[_foam_idx % _shore_foam.size()]
				_foam_idx += 1
				_spawn("foam", _tex_dot, f.pos, FOAM_COLOR, 2.6,
						19.0 / 32.0, 19.0 / 32.0, Vector2.ZERO, 0.0, 0.0, 0.0, f.dir)
	# Surface shimmer: glints on in-view water only.
	_shimmer_timer -= delta
	if _shimmer_timer <= 0.0:
		_shimmer_timer = 0.3
		var c := _random_water_cell(true)
		if c.x >= 0:
			glint(world.cell_center(c) + Vector2(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0)),
					SHIMMER_COLOR, _rng.randf_range(8.0, 12.0), 0.9)
	# Ripple rings every ~2.5-4 s, preferring in-view water.
	_ripple_timer -= delta
	if _ripple_timer <= 0.0:
		_ripple_timer = _rng.randf_range(2.5, 4.0)
		var c2 := _random_water_cell(true)
		if c2.x < 0:
			c2 = _random_water_cell(false)
		if c2.x >= 0:
			ripple(world.cell_center(c2) + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0)),
					RIPPLE_COLOR, _rng.randf_range(22.0, 32.0), _rng.randf_range(1.4, 1.9))


func _update_chimneys(delta: float) -> void:
	_smoke_timer -= delta
	if _smoke_timer > 0.0:
		return
	_smoke_timer = 0.7
	if game == null:
		return
	for b in game.buildings:
		if b.btype == "blacksmith" and b.complete:
			var r: Rect2 = b.art_display_rect()
			var anchor: Vector2 = b.position + r.position + Vector2(r.size.x * 0.70, r.size.y * 0.10)
			puff(anchor, Color(0.66, 0.64, 0.62, 0.50), 1, 24.0, 1.6, 13.0)
			if _rng.randf() < 0.2:
				glint(anchor + Vector2(0, 6), Color(1.0, 0.55, 0.2, 0.9), 9.0, 0.45)
		elif b.btype == "house" and b.complete and _rng.randf() < 0.55:
			# 13o: House art carries a real chimney (upper right) —
			# hearth smoke, thinner and slower than the forge's.
			# (The Town Center art has NO chimney — a flag instead —
			# so it gets the flag wave, not smoke; see KE-HOACH 13o.)
			var r2: Rect2 = b.art_display_rect()
			var anchor2: Vector2 = b.position + r2.position \
					+ Vector2(r2.size.x * 0.79, r2.size.y * 0.05)
			puff(anchor2, Color(0.78, 0.76, 0.73, 0.38), 1, 17.0, 1.9, 10.0)
