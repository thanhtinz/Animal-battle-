extends Node
## Visual-polish verification captures under Xvfb:
##   godot --path . res://tests/capture_polish.tscn -- water|ground|pond
## water  -> coast sea + shore (grassland/coast)  empire_age_water_fix_v1.png
## ground -> open grassland flowers/dirt          empire_age_ground_polish_v1.png
## pond   -> pond close-up (grassland/plains)     empire_age_pond_align_v1.png

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "ground"
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "grassland"
	ms.chosen_layout = "coast" if mode == "water" else "plains"
	ms.map_choice_done = true
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	game.fog.set_process(false)
	for i in range(game.fog.state.size()):
		game.fog.state[i] = 2
	game.fog.queue_redraw()
	for u in game.units:
		u.visible = true
	for b in game.buildings:
		b.visible = true
	var focus := Vector2(1050, 900) # open grass SW of the lake
	var zoom := 1.15
	var out := "res://shots/empire_age_ground_polish_v1.png"
	if mode == "water":
		# River mouth + south sea shore of the coast layout. Clouds
		# are staged out of frame (seeded drift parks one on the
		# river mouth; the cloud cap is verified in the ground shot).
		game.world.set_sky_active(false)
		focus = game.world.cell_center(Vector2i(30, 55))
		zoom = 1.25
		out = "res://shots/empire_age_water_fix_v1.png"
	elif mode == "pond":
		var ponds: Array = game.world.features.get("ponds", [])
		if not ponds.is_empty() and not ponds[0].is_empty():
			focus = game.world.cell_center(ponds[0][ponds[0].size() / 2])
		else:
			focus = game.world.cell_center(Vector2i(27, 30))
		zoom = 2.3
		out = "res://shots/empire_age_pond_align_v1.png"
	game.cam.zoom = Vector2(zoom, zoom)
	game.cam.focus_on(focus)
	game.set_paused(true)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("CAPTURE SAVED ", out, " size=", img.get_size())
	get_tree().quit()
