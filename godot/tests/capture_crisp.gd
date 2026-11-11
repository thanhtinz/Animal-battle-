extends Node
## Verification captures for the crisp-ground bake + oasis palm fix:
##   godot --path . res://tests/capture_crisp.tscn -- crisp|oasis
## crisp -> open grassland mid-zoom     empire_age_grass_crisp_v3.png
## oasis -> desert oasis + palm ring    empire_age_oasis_trees_fix_v2.png

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "crisp"
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "desert" if mode == "oasis" else "grassland"
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
	var focus := Vector2(1050, 900) # open grass SW of the lake
	var zoom := 1.15
	var out := "res://shots/empire_age_grass_crisp_v3.png"
	if mode == "oasis":
		# The plains lake reads as an oasis in the desert grade; the
		# palm ring dresses its shores.
		focus = game.world.cell_center(Vector2i(31, 31))
		zoom = 1.35
		out = "res://shots/empire_age_oasis_trees_fix_v2.png"
	game.cam.zoom = Vector2(zoom, zoom)
	game.cam.focus_on(focus)
	game.set_paused(true)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("CAPTURE SAVED ", out, " size=", img.get_size())
	get_tree().quit()
