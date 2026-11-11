extends Node
## Captures the defringed unit sprites at close zoom under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_units_clean.tscn
## Trains one Villager, one Militia and one Archer for real, parks them
## in a row on open grass south of the Town Center and frames them at
## 2.4x so the sprite edges (the point of the shot) are easy to judge.

var game = null
var w = null


func park(u: Unit, cell: Vector2i) -> void:
	var c: Vector2i = w.nearest_walkable(cell)
	if c.x < 0:
		return
	u.global_position = w.cell_center(c)
	u.state = "idle"
	u.path.clear()
	u.path_cells.clear()


func _ready() -> void:
	Engine.time_scale = 3.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	var tc_o: Vector2i = game.player_tc.origin_cell

	# A Barracks somewhere valid so the Militia + Archer can be trained.
	# (Preferred cells first, then a scan clamped to the map — negative
	# cells make can_place error out and would hang the capture.)
	var barr: Building = null
	var defsz: Vector2i = game.get_build_def("barracks").size
	var prefs: Array = [tc_o + Vector2i(5, 0), tc_o + Vector2i(5, 1), tc_o + Vector2i(4, 0),
			tc_o + Vector2i(-5, 0), tc_o + Vector2i(0, -5)]
	for cand in prefs:
		if w.can_place(cand, defsz):
			barr = game._spawn_building("barracks", 0, cand, true)
			break
	if barr == null:
		for cy in range(0, 64 - defsz.y):
			for cx in range(0, 64 - defsz.x):
				var cand := Vector2i(cx, cy)
				if w.can_place(cand, defsz):
					barr = game._spawn_building("barracks", 0, cand, true)
					break
			if barr != null:
				break
	print("CAPTURE barracks staged=", barr != null)

	game.resources.food += 600
	game.resources.gold += 600
	game.resources.wood += 600
	# No extra villager: the starting 3 + Militia + Archer exactly fill
	# the Town Center's 5 pop cap (an extra train would starve the Archer).
	if barr != null:
		game.train_militia()
		game.train_archer()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 90000:
		if game.pop_current() >= 5 and game.queued_total() == 0:
			break
		await get_tree().process_frame
	print("CAPTURE player units=", game.pop_current())

	var vil: Unit = null
	var mil: Unit = null
	var arc: Unit = null
	for u in game.units:
		if u.team != 0:
			continue
		if u.unit_type == "villager" and vil == null:
			vil = u
		elif u.unit_type == "militia":
			mil = u
		elif u.unit_type == "archer":
			arc = u
	# Park the trio in a row on open grass south of the Town Center.
	var row_cell: Vector2i = tc_o + Vector2i(1, 6)
	if vil != null:
		park(vil, row_cell)
	if mil != null:
		park(mil, row_cell + Vector2i(2, 0))
	if arc != null:
		park(arc, row_cell + Vector2i(4, 0))
	await get_tree().process_frame
	await get_tree().process_frame

	var mid: Vector2 = w.cell_center(row_cell + Vector2i(2, 0))
	game.cam.zoom = Vector2(2.4, 2.4) # zoom first: focus_on clamps by view size
	game.cam.focus_on(mid)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_units_clean.png")
	print("CAPTURE SAVED res://shots/empire_age_units_clean.png size=", img.get_size())
	get_tree().quit()
