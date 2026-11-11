class_name Beast
extends Node2D
## Empire Age — a wild beast: a team-neutral hostile that extends
## the wandering-animal system (Animal) with territory, aggro and a
## food carcass. Beasts attack BOTH teams' units and never enter the
## base clearings: their chase is leashed to ~6 tiles around the
## territory anchor, and they abandon any hunt that drags them
## toward a base.
##
## Species (stats in Stats.BEAST_STATS, balance guard there):
##   wolf — pack predator, aggro 2.5 tiles, fast and fragile.
##   bear — solitary bruiser near forests, aggro 1.5 tiles, slow,
##          very tough.
##   boar — neutral grazer: NEVER aggros on its own; it only fights
##          back once damaged (provoked flag).
## Art: self-drawn pose sheets (walk cycle + attack + death poses,
## single facing + flip, like the Ram convention); the wolf has
## white (snow) and sand (desert) fur grades as extra sheets.

const LEASH_PX := 192.0 # 6 tiles from the territory anchor
const BASE_KEEP_OUT := 8.0 # tiles from either base centre
const ATTACK_DIST := 44.0

var species: String = "wolf" # wolf | bear | boar (stats key)
var skin: String = "wolf" # sheet name in assets/env/
var world: World = null
var game = null # Main (duck-typed); set by Main after generate()
var anchor: Vector2 = Vector2.ZERO # territory centre (world px)

var max_hp: float = 40.0
var hp: float = 40.0
var state: String = "wander" # wander | chase | return | dead
var target = null # Unit being hunted
var provoked: bool = false # boar: set by the first damage taken
var dormant: bool = false # test hook: the suite parks beasts for its
	# legacy sections (same pattern as EnemyAI.waves_enabled) and
	# section (x) wakes them; the real game never sets this.
var path: Array = [] # Vector2 waypoints

var _spr: Sprite2D = null
var _atlas: AtlasTexture = null
var _frames: Dictionary = {}
var _anim_t := 0.0
var _wait := 0.0
var _dest := Vector2.ZERO
var _scan_t := 0.0
var _repath_t := 0.0
var _atk_cd := 0.0
var _attack_show := 0.0
var _flash_t := 0.0
var _death_t := 0.0
var _stuck_t := 0.0
var _rng := RandomNumberGenerator.new()
# 13o presentation: idle breathing (the sheet's idle entry is a
# single still frame, so a waiting beast froze solid before this).
var _base_scale := 0.35
var _life_t := 0.0
var _phase := 0.0


func _ready() -> void:
	z_index = 16
	max_hp = Stats.beast_stat(species, "hp")
	hp = max_hp
	_rng.seed = int(anchor.x) * 131 + int(anchor.y) * 17 + 7
	_dest = global_position
	_wait = _rng.randf_range(0.5, 2.5)
	var sheet := "res://assets/env/" + skin + ".png"
	var meta := "res://assets/env/" + skin + "_frames.json"
	if not ResourceLoader.exists(sheet) or not ResourceLoader.exists(meta):
		return
	var f := FileAccess.open(meta, FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_frames = parsed
	_atlas = AtlasTexture.new()
	_atlas.atlas = load(sheet)
	_spr = Sprite2D.new()
	_spr.texture = _atlas
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var sc := float(_frames.get("scale", 0.35))
	_base_scale = sc
	_phase = float(absi(int(anchor.x) * 13 + int(anchor.y) * 7) % 628) / 100.0
	_spr.scale = Vector2(sc, sc)
	var cw := float(_frames.get("cell_w", 100))
	var ch := float(_frames.get("cell_h", 100))
	var bl := float(_frames.get("baseline", ch - 6))
	_spr.offset = Vector2(0, ch * 0.5 - bl)
	add_child(_spr)
	_set_frame(int(_frames.get("idle", 0)))


func cell() -> Vector2i:
	return world.world_to_cell(global_position)


func is_dead() -> bool:
	return state == "dead"


func _set_frame(idx: int) -> void:
	if _atlas == null or _frames.is_empty():
		return
	var cw := int(_frames.get("cell_w", 100))
	var ch := int(_frames.get("cell_h", 100))
	_atlas.region = Rect2(idx * cw, 0, cw, ch)


func _speed() -> float:
	return Stats.beast_stat(species, "speed")


# ---------------------------------------------------------------- combat

func take_damage(amount: float, attacker = null) -> void:
	if state == "dead":
		return
	hp -= amount
	_flash_t = 0.12
	provoked = true
	# Everything fights back when hurt (the boar's ONLY aggro rule).
	if attacker is Unit and not attacker.is_dead() and state != "chase":
		target = attacker
		state = "chase"
		_repath_t = 0.0
	if hp <= 0.0:
		hp = 0.0
		die()
	queue_redraw()


func die() -> void:
	if state == "dead":
		return
	state = "dead"
	_death_t = 1.6
	target = null
	path.clear()
	_set_frame(int(_frames.get("die", 5)))
	if world != null:
		world.add_carcass(cell(), int(Stats.beast_stat(species, "carcass")))
		world.beasts.erase(self)
	queue_redraw()


func _strike() -> void:
	if target == null or not is_instance_valid(target) or target.is_dead():
		return
	if target is Unit and target.garrisoned:
		return # the prey slipped inside a building
	target.take_damage(Stats.beast_stat(species, "atk"), self)
	_attack_show = 0.35


# ---------------------------------------------------------------- senses

func _near_base() -> bool:
	if world == null:
		return false
	var c := cell()
	return Vector2(c - world.player_base).length() < BASE_KEEP_OUT \
			or Vector2(c - world.enemy_base).length() < BASE_KEEP_OUT


func _scan() -> void:
	if game == null:
		return
	if species == "boar" and not provoked:
		return # grazers ignore passers-by until hurt
	var aggro := Stats.beast_stat(species, "aggro") * World.TILE
	var best = null
	var bd := aggro
	for u in game.units:
		if not u.is_targetable():
			continue
		var d := global_position.distance_to(u.global_position)
		if d < bd:
			bd = d
			best = u
	if best != null and not _near_base():
		target = best
		state = "chase"
		_repath_t = 0.0


func _target_lost() -> bool:
	return target == null or not is_instance_valid(target) or target.is_dead() \
			or (target is Unit and target.garrisoned)


# ---------------------------------------------------------------- movement

func _set_path_to(dest_cell: Vector2i) -> void:
	var cells: Array = world.get_path_cells(cell(), dest_cell, -1)
	path = world.cells_to_points(cells)
	if path.size() > 1 and global_position.distance_to(path[0]) < 10.0:
		path.pop_front()


func _follow_path(delta: float, spd: float) -> bool:
	if path.is_empty():
		return true
	var to: Vector2 = path[0] - global_position
	if to.length() <= 7.0:
		path.pop_front()
		return path.is_empty()
	var dir := to / to.length()
	global_position += dir * spd * delta
	if _spr != null and absf(dir.x) > 0.15:
		_spr.flip_h = dir.x < 0.0
	return false


func _wander_tick(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		_set_frame(int(_frames.get("idle", 0)))
		return
	var to := _dest - global_position
	if to.length() < 5.0:
		_wait = _rng.randf_range(1.0, 3.5)
		var c: Vector2i = world.world_to_cell(anchor) + Vector2i(
				_rng.randi_range(-5, 5), _rng.randi_range(-4, 4))
		var walk: Vector2i = world.nearest_walkable(c, 4)
		if walk.x >= 0 and not (Vector2(walk - world.player_base).length() < BASE_KEEP_OUT
				or Vector2(walk - world.enemy_base).length() < BASE_KEEP_OUT):
			_dest = world.cell_center(walk)
		return
	var dir := to / to.length()
	global_position += dir * _speed() * 0.35 * delta
	if _spr != null and absf(dir.x) > 0.15:
		_spr.flip_h = dir.x < 0.0
	_anim_t += delta
	_cycle_walk()


func _cycle_walk() -> void:
	var walk: Array = _frames.get("walk", [0])
	if walk.is_empty():
		return
	var idx := int(_anim_t * 6.5) % walk.size()
	_set_frame(int(walk[idx]))


func _chase_tick(delta: float) -> void:
	if _target_lost():
		target = null
		state = "return"
		_set_path_to(world.world_to_cell(anchor))
		return
	# Leash + base keep-out: abandon the hunt and head home.
	if global_position.distance_to(anchor) > LEASH_PX or _near_base():
		target = null
		state = "return"
		_set_path_to(world.world_to_cell(anchor))
		return
	var d := global_position.distance_to(target.global_position)
	if d <= ATTACK_DIST:
		path.clear()
		if _spr != null:
			_spr.flip_h = target.global_position.x < global_position.x
		_atk_cd -= delta
		if _atk_cd <= 0.0:
			_strike()
			_atk_cd = Stats.beast_stat(species, "cooldown")
		return
	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = 0.4
		_set_path_to(target.cell())
	if _follow_path(delta, _speed()):
		_set_path_to(target.cell())
	else:
		_anim_t += delta
		_cycle_walk()


func _process(delta: float) -> void:
	if world == null or dormant:
		return
	if game != null and game.paused:
		return
	if _flash_t > 0.0:
		_flash_t -= delta
		if _spr != null:
			_spr.modulate = Color(1.6, 1.2, 1.2) if _flash_t > 0.0 else Color.WHITE
	# 13o breathing: a slow chest rise (scale y a touch more than
	# x), strongest while the beast stands in its wander waits.
	_life_t += delta
	if _spr != null and state != "dead":
		var br := sin(_life_t * 1.9 + _phase)
		_spr.scale = Vector2(_base_scale * (1.0 + br * 0.008),
				_base_scale * (1.0 + br * 0.020))
	if _attack_show > 0.0:
		_attack_show -= delta
		_set_frame(int(_frames.get("attack", 4)))
	elif state == "chase":
		pass # walk cycle owns the frame
	if state == "dead":
		_death_t -= delta
		modulate.a = clampf(_death_t / 1.6, 0.0, 1.0)
		if _death_t <= 0.0:
			queue_free()
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.3
		if state == "wander":
			_scan()
	match state:
		"wander":
			_wander_tick(delta)
		"chase":
			_chase_tick(delta)
		"return":
			if _follow_path(delta, _speed() * 0.6):
				state = "wander"
				_wait = _rng.randf_range(0.5, 1.5)
			else:
				_anim_t += delta
				_cycle_walk()
	if hp < max_hp:
		queue_redraw()


func _draw() -> void:
	if hp < max_hp and state != "dead":
		var frac := clampf(hp / max_hp, 0.0, 1.0)
		# Neutral rust-red: beasts belong to neither faction.
		draw_rect(Rect2(-17, -44, 34, 4.0), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(-17, -44, 34 * frac, 4.0), Color(0.85, 0.4, 0.25))
