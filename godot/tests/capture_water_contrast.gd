extends Node
## Water-contrast verification captures under Xvfb:
##   godot --path . res://tests/capture_water_contrast.tscn -- grass|snow|desert
## All modes frame the plains lake (cell 33,30) at zoom 1.15 in the
## chosen biome: grass -> empire_age_water_contrast_grass_v1.png,
## snow -> empire_age_water_contrast_snow_v1.png (the critical
## ice-vs-snow case), desert -> empire_age_water_contrast_desert_v1.png.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "grass"
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "desert" if mode == "desert" else \
			("snow" if mode == "snow" else "grassland")
	ms.chosen_layout = "plains"
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
	game.world.set_sky_active(false)
	var out := "res://shots/empire_age_water_contrast_grass_v1.png"
	if mode == "snow":
		out = "res://shots/empire_age_water_contrast_snow_v1.png"
	elif mode == "desert":
		out = "res://shots/empire_age_water_contrast_desert_v1.png"
	game.cam.zoom = Vector2(1.15, 1.15)
	game.cam.focus_on(game.world.cell_center(Vector2i(33, 30)))
	game.set_paused(true)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("CAPTURE SAVED ", out, " size=", img.get_size())
	get_tree().quit()
