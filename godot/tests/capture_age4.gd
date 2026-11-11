extends Node
## Age IV capture: a staged player base (Castle + Barracks +
## Blacksmith + Tower added to the starting base) researches
## Imperial for real — resources granted, research started, timer
## shortened — and the shot is taken after completion: tier-4
## buildings everywhere and the IV badge in the HUD.
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_age4.tscn

var game = null
var w = null


func find_spot(size: Vector2i, near: Vector2i) -> Vector2i:
	for r in range(0, 18):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := near + Vector2i(dx, dy)
				if w.can_place(cand, size):
					return cand
	return Vector2i(-1, -1)


func _ready() -> void:
	Engine.time_scale = 3.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	game.choose_map(game.biome_id, game.layout_id) # close map panel, unpause
	w = game.world
	var base: Vector2i = w.player_base

	# Stage the Imperial prerequisites around the starting base.
	game.set_team_age(0, 3)
	game._spawn_building("castle", 0, find_spot(Vector2i(4, 4), base + Vector2i(-9, -3)), true)
	game._spawn_building("barracks", 0, find_spot(Vector2i(3, 3), base + Vector2i(6, 3)), true)
	game._spawn_building("blacksmith", 0, find_spot(Vector2i(3, 3), base + Vector2i(6, -4)), true)
	game._spawn_building("tower", 0, find_spot(Vector2i(1, 1), base + Vector2i(-4, 5)), true)
	game._spawn_building("market", 0, find_spot(Vector2i(3, 3), base + Vector2i(-8, 4)), true)
	# A few soldiers for life.
	for i in range(3):
		game._make_unit(0, w.cell_center(base + Vector2i(3 + i, 7)), "militia")
	game._make_unit(0, w.cell_center(base + Vector2i(6, 7)), "cavalry")

	# Research Imperial for real, fast-forwarded.
	game.resources["food"] = 1500
	game.resources["gold"] = 600
	var ok: bool = game.start_age_up4()
	game.age_timer = 0.2
	var guard := 0
	while game.age < 4 and guard < 600:
		await get_tree().process_frame
		guard += 1
	print("CAPTURE age-up started=", ok, " age=", game.age)

	game.cam.focus_on(game.player_tc.position + Vector2(game.player_tc.size) * World.TILE * 0.5 + Vector2(-40, 30))
	for i in range(6):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_age4_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_age4_v1.png")
	get_tree().quit()
