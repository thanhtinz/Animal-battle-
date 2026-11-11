extends Node
## Biome/layout captures under Xvfb:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path <proj> \
##       res://tests/capture_biomes.tscn -- desert|snow|falls|panel
## The map statics are set BEFORE Main instantiates so its _ready
## generates the right world (and, except for `panel`, never shows
## the boot map-choice overlay).

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "desert"
	var ms = load("res://scripts/main.gd")
	var out := ""
	var zoom := 0.5
	var focus := Vector2(672, 1344)
	var wait_s := 1.6
	match mode:
		"desert": # desert + Bờ biển: inland oasis lake, river, sea edge
			ms.chosen_biome = "desert"
			ms.chosen_layout = "coast"
			ms.map_choice_done = true
			out = "res://shots/empire_age_desert_v2.png"
			zoom = 0.5
			focus = Vector2(704, 1344)
			wait_s = 2.2
		"snow": # snow plains: base + frozen lake + falling snow
			ms.chosen_biome = "snow"
			ms.chosen_layout = "plains"
			ms.map_choice_done = true
			out = "res://shots/empire_age_snow_v3.png"
			zoom = 0.55
			focus = Vector2(1024, 717)
			wait_s = 3.0
		"falls": # grassland plains waterfall close-up at (12, 5..10)
			ms.chosen_biome = "grassland"
			ms.chosen_layout = "plains"
			ms.map_choice_done = true
			out = "res://shots/empire_age_waterfall_v3.png"
			zoom = 1.8
			focus = Vector2(384, 256)
			wait_s = 1.8
		_: # panel: boot state — map-choice overlay over the paused game
			out = "res://shots/empire_age_mapchoice_v1.png"
			wait_s = 0.8
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	if mode != "panel":
		game.cam.zoom = Vector2(zoom, zoom)
		game.cam.focus_on(focus)
		# Verification shots lift the Fog of War (frozen state array +
		# entity flags forced on) so the biome reads in full.
		game.fog.set_process(false)
		for i in range(game.fog.state.size()):
			game.fog.state[i] = 2
		game.fog.queue_redraw()
	await get_tree().create_timer(wait_s).timeout
	if mode != "panel":
		for b in game.buildings:
			b.visible = true
		for u in game.units:
			u.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("CAPTURE SAVED ", out, " size=", img.get_size())
	get_tree().quit()
