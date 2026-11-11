extends Node
## Working capture for the villager-exception scale pass:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_villager.tscn
## Two villagers gather at a tree line with a Militia standing guard
## beside them, so the smaller civilian reads against a soldier in a
## real working frame.

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	var w = game.world
	var tc_pos: Vector2 = game.player_tc.global_position
	var node = w.nearest_node_of_type(tc_pos, "wood")
	if node == null:
		node = w.nearest_node_of_type(tc_pos, "food")
	print("CAPTURE node=", node != null)
	# Send two starting villagers to work the node.
	var workers: Array = []
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			workers.append(u)
	for i in range(mini(2, workers.size())):
		workers[i].order_gather(node)
	# Park a Militia guard on the walkable cell right beside the node.
	var guard_cell: Vector2i = w.nearest_walkable(w.world_to_cell(node.global_position) + Vector2i(2, 1))
	var guard: Unit = game._make_unit(0, w.cell_center(guard_cell), "militia")
	guard.state = "idle"
	guard.path.clear()
	await get_tree().create_timer(6.0).timeout
	game.cam.zoom = Vector2.ONE
	game.cam.focus_on(node.global_position + Vector2(30, 26))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_villager_v3.png")
	print("CAPTURE SAVED res://shots/empire_age_villager_v3.png size=", img.get_size())
	get_tree().quit()
