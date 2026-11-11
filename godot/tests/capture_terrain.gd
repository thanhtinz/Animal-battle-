extends Node
## Captures the new terrain tileset under Xvfb:
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path <proj> res://tests/capture_terrain.tscn
## Lake-shore shot: the base (7,55) and the lake (33,30) are ~36 cells
## apart, so at 1152x648 a combined frame would bury the Town Center
## behind the minimap — this frames the lake and its sand shore ring
## with the surrounding grassland instead.

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	# View ~768x432 world px centred on the lake (cell (33,30)).
	game.cam.zoom = Vector2(1.5, 1.5)
	game.cam.focus_on(Vector2(1072, 976))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_terrain.png")
	print("CAPTURE SAVED res://shots/empire_age_terrain.png size=", img.get_size())
	get_tree().quit()
