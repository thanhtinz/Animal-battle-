extends Node
## P3 fog capture: camera straddling the edge of the player's vision
## early in the match — home base fully lit at the bottom, explored
## dim further out, unexplored map solid black above; the minimap
## (bottom-left) shows the same fog.
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_p3_fog.tscn

var game = null
var w = null


func _ready() -> void:
	Engine.time_scale = 1.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	w = game.world

	# A lone villager scouted a little north earlier: the strip it
	# walked stays explored-dim after it comes home.
	var scout: Unit = null
	for u in game.units:
		if u.team == 0:
			scout = u
			break
	var tc_c: Vector2i = game.player_tc.origin_cell
	var north: Vector2i = w.nearest_walkable(tc_c + Vector2i(1, -9))
	scout.global_position = w.cell_center(north)
	game.fog.update_fog()
	scout.global_position = w.cell_center(w.nearest_walkable(tc_c + Vector2i(1, 4)))
	game.fog.update_fog()
	await get_tree().process_frame
	await get_tree().process_frame

	game.cam.zoom = Vector2(1.0, 1.0)
	game.cam.focus_on(w.cell_center(tc_c) + Vector2(16, -170))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_p3_fog_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_p3_fog_v1.png")
	get_tree().quit()
