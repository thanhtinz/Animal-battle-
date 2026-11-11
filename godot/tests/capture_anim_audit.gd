extends Node
## 13o animation-audit captures under Xvfb:
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> \
##       res://tests/capture_anim_audit.tscn
## Boots ONE coast match, stages every class the 13o pass touched,
## then records short frame sequences per segment into
## res://shots/empire_age_anim_audit_v1/frames/<seg>/ — a PIL pass
## crops + assembles the GIFs afterwards. The base segment records
## twice: once with the flag-wave materials stripped (the honest
## "before": flags baked frozen) and once restored.

const FRAME_DIR := "res://shots/empire_age_anim_audit_v1/frames"
const STEP := 0.12

var game = null


func _ready() -> void:
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "grassland"
	ms.map_choice_done = true
	ms.chosen_layout = "coast"
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	# Lift fog for the verification frames.
	game.fog.set_process(false)
	for i in range(game.fog.state.size()):
		game.fog.state[i] = 2
	game.fog.queue_redraw()

	var base_centre: Vector2 = game.world.cell_center(game.world.player_base)
	var anchor: Vector2i = game.world.player_base + Vector2i(10, 6)
	# "late" arg: record only the cavalry/ram/beasts/ships segments
	# (the early ones are already on disk) — staging for the early
	# segments is skipped too, everything is null-guarded.
	var late: bool = OS.get_cmdline_user_args().has("late")

	var lineup := Vector2.ZERO
	if not late:
		_stage_base_extras(base_centre)
		lineup = _stage_lineup(anchor)
		_stage_gatherer(anchor)
	var beast_focus := _stage_beasts(anchor)
	var ship_focus := _stage_ships()
	var ram_data := _stage_ram(anchor)

	if not late:
		# --- base: flags frozen (before) -> flags waving (after)
		_set_flag_materials(false)
		await _record("base_before", 1.2, base_centre + Vector2(30, -20), 1.5)
		_set_flag_materials(true)
		await _record("base", 2.2, base_centre + Vector2(30, -20), 1.5)
		# --- idle lineup: breathing on single-frame idle rows
		await _record("lineup", 2.4, lineup, 2.1)
		# --- hurt: two hits on the lineup militia
		_hurt_militia(lineup)
		await _record("hurt", 2.2, lineup, 2.1)
		# --- villager work loop at the forest edge
		await _record("gather", 2.4, _gather_focus, 2.0)
	# --- cavalry crossing (gait bob over the leg cycle)
	if _cav != null and _cav_dest.x >= 0:
		_cav.order_move_cell(_cav_dest)
		await _record("cavalry", 2.2, _cav_focus, 1.9)
	else:
		print("SEGMENT cavalry SKIPPED (staging failed)")
	# --- ram: approach rock + battering thrust
	if _ram != null and _ram_target != null:
		_ram.order_attack(_ram_target)
		await _record("ram", 3.6, ram_data, 1.9)
	else:
		print("SEGMENT ram SKIPPED (staging failed)")
	# --- beasts breathing / wandering at their clearing
	if beast_focus != Vector2.ZERO:
		await _record("beasts", 3.0, beast_focus, 1.9)
	else:
		print("SEGMENT beasts SKIPPED (staging failed)")
	# --- ships bobbing + rolling at the dock
	await _record("ships", 3.0, ship_focus, 1.3)
	print("ANIM AUDIT CAPTURE DONE")
	get_tree().quit()


# ---------------------------------------------------------------- staging

func _reveal() -> void:
	for b in game.buildings:
		b.visible = true
	for u in game.units:
		u.visible = true
	for s in game.ships:
		s.visible = true
	for bst in game.world.beasts:
		bst.visible = true


func _record(seg: String, seconds: float, focus: Vector2, zoom: float) -> void:
	_reveal()
	game.cam.zoom = Vector2(zoom, zoom)
	game.cam.focus_on(focus)
	await get_tree().process_frame
	await get_tree().process_frame
	var dir := ProjectSettings.globalize_path(FRAME_DIR + "/" + seg)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := int(seconds / STEP)
	for i in range(n):
		await get_tree().create_timer(STEP).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir + "/f_%03d.png" % i)
	print("SEGMENT ", seg, " frames=", n)


func _set_flag_materials(on: bool) -> void:
	var sh: Shader = null
	if on:
		sh = load("res://shaders/flag_wave.gdshader")
	for b in game.buildings:
		if b.art_sprite == null:
			continue
		if not on:
			b.art_sprite.material = null
		elif Building.FLAG_TYPES.has(b.btype):
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("phase",
					float(absi(b.origin_cell.x * 31 + b.origin_cell.y * 57) % 628) / 100.0)
			b.art_sprite.material = mat


## Barracks (second flag) + two Houses (hearth smoke) + a Farm with
## three ripe plots (crop sway) around the player's Town Center.
func _stage_base_extras(base_centre: Vector2) -> void:
	var bc: Vector2i = game.world.world_to_cell(base_centre)
	_place_near("barracks", bc + Vector2i(6, 2))
	_place_near("house", bc + Vector2i(-5, 3))
	_place_near("house", bc + Vector2i(-5, -2))
	var farm := _place_near("farm", bc + Vector2i(5, 6))
	if farm == null:
		return
	var made := 0
	for dy in range(-2, 4):
		if made >= 3:
			break
		for dx in range(-2, 5):
			if made >= 3:
				break
			var c: Vector2i = farm.origin_cell + Vector2i(dx, dy)
			if not game.world.in_bounds(c) or game.world.is_solid(c) \
					or game.world.water.has(c):
				continue
			var fp := FieldPlot.new()
			fp.cell = c
			fp.farm = farm
			fp.stage = 3
			game.fields.append(fp)
			game.add_child(fp)
			made += 1


func _place_near(btype: String, near: Vector2i) -> Building:
	for r in range(0, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = near + Vector2i(dx, dy)
				if game.placement_valid_at(cand, btype):
					return game._spawn_building(btype, 0, cand, true)
	return null


var _lineup_militia: Unit = null


## One of each foot unit standing idle in a row — the spearman and
## cavalry idle rows are a single frame per direction, so any life
## in this segment is the 13o breathing layer.
func _stage_lineup(anchor: Vector2i) -> Vector2:
	var kinds := ["spearman", "cavalry", "militia", "archer", "villager"]
	var first := Vector2.ZERO
	for i in range(kinds.size()):
		var c: Vector2i = game.world.nearest_walkable(anchor + Vector2i(i * 2, 0), 3)
		if c.x < 0:
			continue
		var u: Unit = game._make_unit(0, game.world.cell_center(c), kinds[i])
		u.state = "idle"
		if kinds[i] == "militia":
			_lineup_militia = u
		if i == 2:
			first = u.global_position
	return first


func _hurt_militia(_focus: Vector2) -> void:
	if _lineup_militia == null:
		return
	_lineup_militia.take_damage(6.0)
	# Second hit lands mid-segment (timer is fire-and-forget here).
	get_tree().create_timer(1.1).timeout.connect(
			func() -> void:
				if is_instance_valid(_lineup_militia):
					_lineup_militia.take_damage(6.0))


var _gather_focus := Vector2.ZERO


func _stage_gatherer(anchor: Vector2i) -> void:
	var node: ResourceNode = null
	var bd := INF
	for n in game.world.nodes:
		if n.rtype != "wood":
			continue
		var d := Vector2(anchor).distance_squared_to(Vector2(n.cell))
		if d < bd:
			bd = d
			node = n
	if node == null:
		return
	var c: Vector2i = game.world.nearest_walkable(node.cell + Vector2i(1, 1), 3)
	if c.x < 0:
		return
	var v: Unit = game._make_unit(0, game.world.cell_center(c), "villager")
	v.order_gather(node)
	_gather_focus = node.global_position + Vector2(10, -6)


var _cav: Unit = null
var _cav_dest := Vector2i(-1, -1)
var _cav_focus := Vector2.ZERO


func _stage_beasts(anchor: Vector2i) -> Vector2:
	var wolves: Array = []
	var boar: Beast = null
	for bst in game.world.beasts:
		if bst.species == "wolf" and wolves.size() < 2:
			wolves.append(bst)
		if bst.species == "boar" and boar == null:
			boar = bst
	var spot: Vector2i = game.world.nearest_walkable(anchor + Vector2i(-13, 9), 8)
	if spot.x < 0:
		return Vector2.ZERO
	var centre: Vector2 = game.world.cell_center(spot)
	var i := 0
	for bst in wolves:
		var c: Vector2i = game.world.nearest_walkable(spot + Vector2i(i * 2, 0), 2)
		if c.x >= 0:
			bst.global_position = game.world.cell_center(c)
			bst.anchor = bst.global_position
		i += 1
	if boar != null:
		var c2: Vector2i = game.world.nearest_walkable(spot + Vector2i(1, 2), 2)
		if c2.x >= 0:
			boar.global_position = game.world.cell_center(c2)
			boar.anchor = boar.global_position
	# The cavalry crossing shares this side of the map.
	var cav_c: Vector2i = game.world.nearest_walkable(spot + Vector2i(-3, -6), 8)
	if cav_c.x >= 0:
		_cav = game._make_unit(0, game.world.cell_center(cav_c), "cavalry")
		_cav.state = "idle"
		_cav_dest = game.world.nearest_walkable(cav_c + Vector2i(13, 1), 6)
		_cav_focus = game.world.cell_center(cav_c + Vector2i(6, 0))
	return centre


var _ram: Unit = null
var _ram_target: Building = null


func _stage_ram(anchor: Vector2i) -> Vector2:
	var cell := Vector2i(-1, -1)
	for r in range(0, 12):
		if cell.x >= 0:
			break
		for dy in range(-r, r + 1):
			if cell.x >= 0:
				break
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = anchor + Vector2i(17, -3) + Vector2i(dx, dy)
				if game.placement_valid_at(cand, "tower"):
					cell = cand
					break
	if cell.x < 0:
		return Vector2.ZERO
	_ram_target = game._spawn_building("tower", 1, cell, true)
	var rc: Vector2i = game.world.nearest_walkable(cell + Vector2i(-5, 1), 3)
	if rc.x < 0:
		return Vector2.ZERO
	_ram = game._make_unit(0, game.world.cell_center(rc), "ram")
	_ram.state = "idle"
	return _ram.global_position + Vector2(70, 0)


## Dock + fleet staging (mirrors capture_ships_beasts).
func _stage_ships() -> Vector2:
	var dock: Building = null
	for r in range(0, 14):
		if dock != null:
			break
		for dy in range(-r, r + 1):
			if dock != null:
				break
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = Vector2i(16, 50) + Vector2i(dx, dy)
				if game.placement_valid_at(cand, "dock"):
					dock = game._spawn_building("dock", 0, cand, true)
					break
	if dock == null:
		return Vector2(528, 1680)
	var centre: Vector2 = dock.position + Vector2(dock.size) * World.TILE * 0.5
	var fb: Ship = game.spawn_ship(dock, "fishing_boat")
	var spot: FishSpot = game.world.nearest_fish_spot(centre)
	var sea_cell: Vector2i = game.world.nearest_navigable(
			dock.origin_cell + Vector2i(7, 7), 6)
	if spot != null and sea_cell.x >= 0:
		spot.cell = sea_cell
		spot.global_position = game.world.cell_center(sea_cell)
		var beside: Vector2i = game.world.nearest_navigable(sea_cell + Vector2i(2, 0), 3)
		if beside.x >= 0:
			fb.global_position = game.world.cell_center(beside)
		fb.order_fish(spot)
	var ws: Ship = game.spawn_ship(dock, "war_ship")
	ws.order_move_cell(ws.cell() + Vector2i(4, 1))
	var tr: Ship = game.spawn_ship(dock, "transport")
	tr.order_move_cell(tr.cell() + Vector2i(-3, 1))
	if spot != null:
		return (centre + spot.global_position) * 0.5 + Vector2(0, 40)
	return centre + Vector2(30, 90)
