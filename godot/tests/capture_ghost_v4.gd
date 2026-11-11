extends Node
## Ghost-preview check for the v4 smooth building pass:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_ghost_v4.tscn
## Enters placement mode for a Barracks next to the player Town Center
## (valid, green tint) so the Overlay ghost draws the smooth tier art,
## then saves one frame.

var game = null


func _ready() -> void:
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var tc_o: Vector2i = game.player_tc.origin_cell
	game.enter_placement("barracks")
	game._placing_cell = tc_o + Vector2i(5, 1)
	game._placing_valid = true
	game.overlay.queue_redraw()
	game.cam.zoom = Vector2(1.25, 1.25)
	game.cam.focus_on(Vector2(330, 1810))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_ghost_v4.png")
	print("CAPTURE SAVED res://shots/empire_age_ghost_v4.png size=", img.get_size())
	get_tree().quit()
