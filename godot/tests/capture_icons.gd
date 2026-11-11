extends Node
## Captures the painted-icon HUD build under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_icons.tscn
## Base view with the full glass HUD: painted resource/pop/timer icons,
## age badge shield, round buttons and the 4 bottom action buttons.

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.cam.position = Vector2(576, 1700)
	game.cam.zoom = Vector2.ONE
	game.apply_box_selection(Rect2(Vector2(80, 1620), Vector2(420, 330)))
	await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_icons.png")
	print("CAPTURE SAVED res://shots/empire_age_icons.png size=", img.get_size())
	get_tree().quit()
