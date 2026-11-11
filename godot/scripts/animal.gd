class_name Animal
extends Node2D
## A wandering wild animal (CraftPix hunt pack) — decoration only for
## now; hunting lands in P3. Walks slowly between nearby walkable
## cells, idles, walks on. Uses the side-view row of its walk sheet
## (32x32 frames, 4 direction rows x 6 frames), flipped by direction.

var species: String = "deer" # deer | fox
var world = null # World (duck-typed)

var _spr: Sprite2D = null
var _atlas: AtlasTexture = null
var _target: Vector2 = Vector2.ZERO
var _wait := 0.0
var _anim_t := 0.0
var _life_t := 0.0 # 13o: breathing clock for the idle waits
var _seed := 0
var _pick_count := 0

## P4 MP lockstep: when true, wander targets come from a seeded RNG
## (same sequence on every client) instead of wall-clock randomness.
## Main sets this before world generation in MP matches; SP never
## touches it and keeps the time-seeded wander.
static var deterministic_mode := false

const FRAME := 32
const SPEED := 20.0


func _ready() -> void:
	z_index = 15
	var path := "res://assets/env/" + species + "_walk.png"
	if not ResourceLoader.exists(path):
		queue_free()
		return
	_atlas = AtlasTexture.new()
	_atlas.atlas = load(path)
	_atlas.region = Rect2(0, FRAME * 2, FRAME, FRAME)
	_spr = Sprite2D.new()
	_spr.texture = _atlas
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spr.scale = Vector2.ONE * 1.15
	add_child(_spr)
	_target = global_position
	_wait = float(_seed % 3)


func _process(delta: float) -> void:
	if _spr == null or world == null:
		return
	_life_t += delta
	if _wait > 0.0:
		_wait -= delta
		# 13o: stand on the row's first (standing) frame and breathe
		# instead of freezing on whatever walk frame came last.
		_atlas.region = Rect2(0, FRAME * 2, FRAME, FRAME)
		_spr.scale = Vector2.ONE * 1.15 \
				* (1.0 + sin(_life_t * 2.0 + float(_seed)) * 0.012)
		return
	_spr.scale = Vector2.ONE * 1.15
	var to := _target - global_position
	if to.length() < 4.0:
		_pick_target()
		return
	_spr.flip_h = to.x < 0.0
	global_position += to.normalized() * SPEED * delta
	_anim_t += delta
	var frame := int(_anim_t * 6.0) % 6
	_atlas.region = Rect2(frame * FRAME, FRAME * 2, FRAME, FRAME)


func _pick_target() -> void:
	_wait = 1.5 + float((_seed * 7) % 30) / 10.0
	if world == null:
		return
	var c: Vector2i = world.world_to_cell(global_position)
	var rng := RandomNumberGenerator.new()
	if deterministic_mode:
		rng.seed = _seed * 1000003 + _pick_count * 7919 + 13
		_pick_count += 1
	else:
		rng.seed = int(Time.get_ticks_msec()) + _seed * 131 + int(global_position.x)
	var dest := c + Vector2i(rng.randi_range(-5, 5), rng.randi_range(-4, 4))
	var walk: Vector2i = world.nearest_walkable(dest, 4)
	if walk.x >= 0:
		_target = world.cell_center(walk)
