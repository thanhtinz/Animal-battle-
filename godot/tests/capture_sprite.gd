extends Node
## Captures the villager-sprite build under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_sprite.tscn
## Stages three villagers: one idles by the Town Center, one walks east,
## one chops at the nearest tree (waits until its state is "gather").

func _ready() -> void:
	Engine.time_scale = 3.0
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.apply_box_selection(Rect2(Vector2(80, 1620), Vector2(420, 330)))
	var sel: Array = game.selection
	if sel.size() >= 3:
		# Prefer a tree east/south-east of the TC so every actor fits one frame.
		var node: ResourceNode = null
		var best := INF
		for n in game.world.nodes:
			if n.rtype != "wood":
				continue
			var dc := Vector2(n.cell - game.player_tc.origin_cell)
			if dc.x < 2.0 or dc.y < -2.0:
				continue
			if dc.length() < best:
				best = dc.length()
				node = n
		if node == null:
			node = game.world.nearest_node_of_type(game.player_tc.global_position, "wood")
		if node != null:
			sel[0].order_gather(node)
		# The second villager sets off across the frame at the same time.
		var dest_cell: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(13, 6))
		game.order_move([sel[1]], game.world.cell_center(dest_cell))
		if node != null:
			# Wait until the gatherer is actually chopping.
			var start := Time.get_ticks_msec()
			while Time.get_ticks_msec() - start < 45000:
				if sel[0].state == "gather":
					break
				await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		# Frame the shot between the Town Center and the gatherer,
		# weighted toward the Town Center so the base stays in frame.
		var tc_mid: Vector2 = game.player_tc.position + Vector2(48, 48)
		var mid: Vector2 = tc_mid * 0.6 + sel[0].global_position * 0.4
		game.cam.focus_on(mid)
		game.cam.zoom = Vector2(1.2, 1.2)
		await get_tree().process_frame
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_villager_sprite.png")
	print("CAPTURE SAVED res://shots/empire_age_villager_sprite.png size=", img.get_size())
	get_tree().quit()
