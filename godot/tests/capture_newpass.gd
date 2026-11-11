extends Node
## In-game captures for the self-drawn pass (farm / wall / castle /
## new units), staged on the real match like capture_buildings_v4.
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_newpass.tscn

var game = null
var w = null


func stage(btype: String, prefs: Array, team: int = 0) -> Building:
	var defsz: Vector2i = game.get_build_def(btype).size
	for cand in prefs:
		if w.can_place(cand, defsz):
			return game._spawn_building(btype, team, cand, true)
	for dy in range(-14, 15):
		for dx in range(-14, 15):
			var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
			if w.can_place(cand, defsz):
				return game._spawn_building(btype, team, cand, true)
	return null


func park(u: Unit, cell: Vector2i) -> void:
	var c: Vector2i = w.nearest_walkable(cell)
	if c.x < 0:
		return
	u.global_position = w.cell_center(c)
	u.state = "idle"
	u.path.clear()
	u.path_cells.clear()
	u.guard_pos = u.global_position


func snap(name: String, focus: Vector2, zoom: float = 1.3) -> void:
	game.cam.zoom = Vector2(zoom, zoom)
	game.cam.focus_on(focus)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/" + name)
	print("CAPTURE SAVED res://shots/", name, " size=", img.get_size())


func _ready() -> void:
	Engine.time_scale = 3.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	game.enemy_ai.waves_enabled = false
	var tc_o: Vector2i = game.player_tc.origin_cell # (6, 54)
	var vils: Array = []
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			vils.append(u)

	# ---------- FARM frame ----------
	var farm = stage("farm", [tc_o + Vector2i(6, 5), tc_o + Vector2i(7, 5), tc_o + Vector2i(6, 6)])
	var stages := [0, 1, 2, 3, 2, 1]
	var si := 0
	if farm != null:
		for dy in range(0, 3):
			for dx in range(-2, 4):
				if si >= stages.size():
					break
				var cell: Vector2i = farm.origin_cell + Vector2i(1, 3) + Vector2i(dx, dy)
				if game.field_valid_at(cell):
					game.resources["wood"] += 100
					if game.confirm_field_placement(cell):
						var f: FieldPlot = game.field_at_cell(cell)
						f.set_stage(stages[si])
						si += 1
	# Villager visibly tending the ripest plot.
	if vils.size() > 0 and game.fields.size() > 0:
		var ripe: FieldPlot = game.fields[3] if game.fields.size() > 3 else game.fields[0]
		var tv: Unit = vils[0]
		park(tv, ripe.cell + Vector2i(1, 0))
		tv.target_field = ripe
		tv.state = "tend"
		tv.facing = "left"
	await snap("empire_age_farm_v1.png",
			w.cell_center(farm.origin_cell + Vector2i(1, 4)) if farm != null else Vector2(330, 1810))

	# ---------- WALL frame ----------
	var wall_base: Vector2i = tc_o + Vector2i(11, -2)
	var segs: Array = []
	for k in range(7):
		var cell := wall_base + Vector2i(k, 0)
		if k == 3:
			segs.append(game._spawn_building("gatewood", 0, cell, true))
		elif w.can_place(cell, Vector2i.ONE):
			segs.append(game._spawn_building("wallwood", 0, cell, true))
	if segs.size() > 1 and is_instance_valid(segs[1]):
		segs[1].take_damage(150.0) # show a damaged segment + HP bar
	var foe = game._make_unit(1, w.cell_center(wall_base + Vector2i(3, -2)), "militia")
	park(foe, wall_base + Vector2i(3, -2))
	foe.facing = "down"
	var guard1 = game._make_unit(0, w.cell_center(wall_base + Vector2i(2, 2)), "spearman")
	park(guard1, wall_base + Vector2i(2, 2))
	guard1.facing = "up"
	if vils.size() > 1:
		park(vils[1], wall_base + Vector2i(5, 2))
	await snap("empire_age_wall_v1.png", w.cell_center(wall_base + Vector2i(3, 0)))

	# ---------- CASTLE frame (whole base at Age III) ----------
	game.set_team_age(0, 3)
	var castle = stage("castle", [tc_o + Vector2i(13, 3), tc_o + Vector2i(13, 4), tc_o + Vector2i(12, 3)])
	await snap("empire_age_castle_v1.png",
			w.cell_center(castle.origin_cell + Vector2i(2, 2)) if castle != null else Vector2(430, 1830), 1.1)

	# ---------- NEW UNITS frame (a live skirmish) ----------
	var arena: Vector2i = tc_o + Vector2i(21, -11)
	var mine: Array = []
	mine.append(game._make_unit(0, w.cell_center(arena + Vector2i(0, 2)), "spearman"))
	mine.append(game._make_unit(0, w.cell_center(arena + Vector2i(1, 3)), "spearman"))
	mine.append(game._make_unit(0, w.cell_center(arena + Vector2i(3, 2)), "cavalry"))
	mine.append(game._make_unit(0, w.cell_center(arena + Vector2i(2, 4)), "ram"))
	var theirs: Array = []
	theirs.append(game._make_unit(1, w.cell_center(arena + Vector2i(1, -2)), "militia"))
	theirs.append(game._make_unit(1, w.cell_center(arena + Vector2i(3, -3)), "archer"))
	theirs.append(game._make_unit(1, w.cell_center(arena + Vector2i(5, -2)), "cavalry"))
	for i in range(mine.size()):
		mine[i].order_attack(theirs[i % theirs.size()])
	for i in range(theirs.size()):
		theirs[i].order_attack(mine[i % mine.size()])
	# Let the fight develop (attack anims, arrows, hit sparks).
	for i in range(50):
		await get_tree().process_frame
	await snap("empire_age_newunits_v1.png", w.cell_center(arena + Vector2i(2, 0)), 1.45)
	get_tree().quit()
