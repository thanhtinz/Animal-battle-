extends Node
## Grass-sharpness diagnostic probe (KE-HOACH 13e):
## dumps the baked ground texture, the water mask, the bake-size
## tile sources and renders at zoom 1.0 / 0.55 for offline
## measurement. Output dir passed as user arg (default before).
##   godot --path . res://tests/probe_grass.tscn -- /tmp/grass_after

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var outdir: String = args[0] if args.size() > 0 else "/tmp/grass_diag"
	DirAccess.make_dir_recursive_absolute(outdir)
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "grassland"
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
		u.visible = false
	for b in game.buildings:
		b.visible = false
	var world = game.world
	var bp: int = world.baked_image.get_width()
	var cell: int = bp / 64
	world.baked_image.save_png(outdir + "/bake.png")
	var mask := Image.create(bp, bp, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 1))
	for c in world.water:
		mask.fill_rect(Rect2i(c.x * cell, c.y * cell, cell, cell),
				Color(1, 1, 1, 1))
	mask.save_png(outdir + "/mask.png")
	for vn in ["grass_0", "grass_1", "grass_2"]:
		var tb: Image = world._tile_image_bake(vn)
		if tb != null:
			tb.save_png(outdir + "/tilebake_" + vn + ".png")
		var tex: Texture2D = world.ground_tex.get(vn, null)
		if tex != null:
			var simg := tex.get_image()
			simg.convert(Image.FORMAT_RGBA8)
			simg.save_png(outdir + "/src_" + vn + ".png")
	# Decals off for a clean ground read.
	for d in world.ground_decals:
		d.visible = false
	game.cam.zoom = Vector2.ONE
	game.cam.focus_on(Vector2(1050, 900))
	game.set_paused(true)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(outdir + "/render_z100.png")
	print("PROBE render z1.00 size=", img.get_size())
	game.cam.zoom = Vector2(0.55, 0.55)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(outdir + "/render_z055.png")
	print("PROBE SAVED ALL -> ", outdir)
	get_tree().quit()
