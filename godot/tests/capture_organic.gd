extends Node
## Organic water-shape verification captures under Xvfb:
##   godot --path . res://tests/capture_organic.tscn -- pond|lake
## pond -> first plains pond close-up, same framing as the old
##         pond_align shot (zoom 2.3)   empire_age_pond_organic_v1.png
## lake -> plains lake wide view (zoom 1.15) empire_age_lake_organic_v1.png

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "pond"
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
	var focus := Vector2(1050, 960)
	var zoom := 2.3
	var out := "res://shots/empire_age_pond_organic_v1.png"
	if mode == "lake" or mode == "desert" or mode == "snow":
		focus = game.world.cell_center(Vector2i(33, 30))
		zoom = 1.15
		out = "res://shots/empire_age_lake_organic_v1.png"
		if mode == "desert":
			out = "res://shots/empire_age_oasis_organic_v1.png"
		elif mode == "snow":
			out = "res://shots/empire_age_lake_organic_snow_v1.png"
	else:
		var ponds: Array = game.world.features.get("ponds", [])
		if not ponds.is_empty() and not ponds[0].is_empty():
			focus = game.world.cell_center(ponds[0][ponds[0].size() / 2])
	game.cam.zoom = Vector2(zoom, zoom)
	game.cam.focus_on(focus)
	game.set_paused(true)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("CAPTURE SAVED ", out, " size=", img.get_size())
	get_tree().quit()
