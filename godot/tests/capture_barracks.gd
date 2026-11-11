extends Node
## Captures the Barracks camp-sprite build under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_barracks.tscn
## Stages a completed Barracks (real camp compound art) next to the Town
## Center, with a trained Militia and Archer parked in front of it.

func _ready() -> void:
	Engine.time_scale = 3.0
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# Build a barracks instantly beside the Town Center for the shot.
	# Prefer a spot east of the TC so both buildings frame well together.
	var w = game.world
	var bsize: Vector2i = game.get_build_def("barracks").size
	var anchor: Vector2i = game.player_tc.origin_cell + Vector2i(4, 0)
	var cands: Array = []
	for dy in range(-4, 13):
		for dx in range(-9, 15):
			cands.append(game.player_tc.origin_cell + Vector2i(dx, dy))
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(anchor) < b.distance_squared_to(anchor))
	var bcell := Vector2i(-1, -1)
	for cand in cands:
		if w.can_place(cand, bsize):
			bcell = cand
			break
	var barr = null
	if bcell.x >= 0:
		game.resources.wood += 200
		game.enter_placement("barracks")
		if game.confirm_placement(bcell):
			for b in game.buildings:
				if b.btype == "barracks":
					barr = b
			if barr != null:
				barr.progress = 1.0
				barr.complete = true
				if barr.art_sprite != null:
					barr.art_sprite.visible = true
				game.on_building_complete(barr)
	print("CAPTURE barracks placed at ", bcell, " sprite=", barr.art_sprite if barr != null else null)

	# Train one Militia and one Archer for real (queues run at 3x speed).
	game.resources.food += 500
	game.resources.gold += 500
	game.resources.wood += 500
	game.train_militia()
	game.train_archer()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 60000:
		var have_m := false
		var have_a := false
		for u in game.units:
			if u.team == 0 and u.unit_type == "militia":
				have_m = true
			if u.team == 0 and u.unit_type == "archer":
				have_a = true
		if have_m and have_a:
			break
		await get_tree().process_frame

	# Park the soldiers in a row just south of the camp gate.
	if barr != null:
		var row_cells := [barr.origin_cell + Vector2i(1, bsize.y + 1),
				barr.origin_cell + Vector2i(2, bsize.y + 1)]
		var idx := 0
		for u in game.units:
			if u.team == 0 and u.unit_type != "villager" and idx < row_cells.size():
				u.order_move_cell(w.nearest_walkable(row_cells[idx]))
				idx += 1
		var start2 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start2 < 60000:
			var ready_all := true
			for u in game.units:
				if u.team == 0 and u.unit_type != "villager" and u.state == "move":
					ready_all = false
			if ready_all:
				break
			await get_tree().process_frame

	await get_tree().create_timer(0.4).timeout
	# Frame the Town Center and the Barracks together.
	var tc_center: Vector2 = game.player_tc.position + Vector2(game.player_tc.size) * World.TILE * 0.5
	var focus := tc_center
	if barr != null:
		var b_center: Vector2 = barr.position + Vector2(barr.size) * World.TILE * 0.5
		focus = (tc_center + b_center) * 0.5 + Vector2(0, 30)
	game.cam.zoom = Vector2(1.3, 1.3) # zoom first: focus_on clamps by view size
	game.cam.focus_on(focus)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_barracks.png")
	print("CAPTURE SAVED res://shots/empire_age_barracks.png size=", img.get_size())
	get_tree().quit()
