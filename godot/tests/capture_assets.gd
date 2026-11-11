extends Node
## Captures the asset-integration build under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_assets.tscn
## Stages the player base: a villager chops at a CraftPix tree, another
## harvests a berry bush, a trained Militia and Archer stand by the
## Barracks, and the camera frames trees + rocks + the base together.

func _ready() -> void:
	Engine.time_scale = 3.0
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# Build a barracks instantly south of the Town Center for the shot.
	var w = game.world
	var bcell := Vector2i(-1, -1)
	for dy in range(3, 11):
		for dx in range(-6, 11):
			var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
			if w.can_place(cand, game.get_build_def("barracks").size):
				bcell = cand
				break
		if bcell.x >= 0:
			break
	if bcell.x < 0:
		for dy in range(-8, 9):
			for dx in range(-8, 9):
				var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
				if w.can_place(cand, game.get_build_def("barracks").size):
					bcell = cand
					break
			if bcell.x >= 0:
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
				game.on_building_complete(barr)

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

	# Send one villager to a tree and one to a berry bush.
	var vils: Array = []
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			vils.append(u)
	var tree: ResourceNode = w.nearest_node_of_type(game.player_tc.global_position, "wood")
	if tree != null and vils.size() > 0:
		vils[0].order_gather(tree)
	var bush: ResourceNode = w.nearest_node_of_type(game.player_tc.global_position, "food")
	if bush != null and vils.size() > 1:
		vils[1].order_gather(bush)
	# Park the soldiers in a neat row south of the Town Center.
	var row_cells := [Vector2i(12, 58), Vector2i(14, 58)]
	var soldiers: Array = []
	var idx := 0
	for u in game.units:
		if u.team == 0 and u.unit_type != "villager" and idx < row_cells.size():
			u.order_move_cell(w.nearest_walkable(row_cells[idx]))
			soldiers.append(u)
			idx += 1
	# Wait until everyone is in position / at work (generous real-time cap).
	var start2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start2 < 90000:
		var ready_all := true
		for s in soldiers:
			if s.state == "move":
				ready_all = false
		if vils.size() > 0 and vils[0].state != "gather" and vils[0].state != "return":
			ready_all = false
		if vils.size() > 1 and vils[1].state != "gather" and vils[1].state != "return":
			ready_all = false
		if ready_all:
			break
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	game.cam.focus_on(game.player_tc.position + Vector2(170, 150))
	game.cam.zoom = Vector2(1.1, 1.1)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_assets.png")
	print("CAPTURE SAVED res://shots/empire_age_assets.png size=", img.get_size())
	get_tree().quit()
