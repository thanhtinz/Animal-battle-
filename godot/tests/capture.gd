extends Node
## Captures one screenshot of the running game under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture.tscn

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.cam.position = Vector2(576, 1700)
	game.cam.zoom = Vector2.ONE
	# Select the villagers (selection rings + context panel) and send one to work.
	game.apply_box_selection(Rect2(Vector2(80, 1620), Vector2(420, 330)))
	var node = game.world.nearest_node_of_type(game.player_tc.global_position, "wood")
	if node != null and game.selection.size() > 0:
		game.selection[0].order_gather(node)
	await get_tree().create_timer(1.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_p2.png")
	print("CAPTURE SAVED res://shots/empire_age_p2.png size=", img.get_size())
	get_tree().quit()
