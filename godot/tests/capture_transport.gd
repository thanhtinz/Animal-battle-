extends Node
## 15g transport captures under Xvfb:
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_transport.tscn
## Shot 1: a trade cart mid-route with its route line visible
## (cart selected). Shot 2: a loaded wagon selected — the
## selection chip reads the manifest (5/5) and the unload row
## is up.

func _ready() -> void:
	Engine.time_scale = 3.0
	Net.auto = {"capture": "transport"} # skips the entry/login flow (Main._entry_applies)
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	# Windowed boot lands on the entry/home flow first and the
	# world is generated late in Main._ready — poll for it
	# instead of assuming a fixed frame count.
	var guard := 0
	while (game.world == null or game.player_tc == null) and guard < 1800:
		await get_tree().process_frame
		guard += 1
	game.home_quick_match() # hide the home lobby + choose_map: unpauses into the match
	if game.enemy_ai != null:
		game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = true
	game.resources = {"food": 5000, "wood": 5000, "gold": 5000, "stone": 500, "iron": 0}
	var tc_cell: Vector2i = game.player_tc.origin_cell
	var mkt_home = game._spawn_building("market", 0,
			game._test_spot_near(tc_cell + Vector2i(6, 0)), true, 0)
	var mkt_far = game._spawn_building("market", 0,
			game._test_spot_near(tc_cell + Vector2i(26, 10)), true, 0)
	# --- shot 1: cart mid-route, selected, route line drawn.
	var cart = game._make_unit(0, game.world.cell_center(
			game.world.nearest_walkable(mkt_home.origin_cell + Vector2i(1, 3))),
			"cart", 0)
	game.assign_trade_route(cart, mkt_far)
	await get_tree().create_timer(1.6, true).timeout # ~5 game-seconds in
	game.set_selection([cart])
	var mid_route: Vector2 = (mkt_home.position + mkt_far.position) * 0.5 \
			+ Vector2(48, 48)
	game.cam.focus_on(mid_route)
	await get_tree().create_timer(0.4, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_transport_cart_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_transport_cart_v1.png size=", img.get_size())
	# --- shot 2: a wagon loaded with five, selected.
	game.set_selection([])
	var wcell: Vector2i = game.world.nearest_walkable(tc_cell + Vector2i(10, 6))
	var wagon = game._make_unit(0, game.world.cell_center(wcell), "wagon", 0)
	var kinds := ["militia", "archer", "spearman", "militia", "villager"]
	var party: Array = []
	for i in range(5):
		party.append(game._make_unit(0, game.world.cell_center(
				game.world.nearest_walkable(wcell + Vector2i(1, i % 3))),
				kinds[i], 0))
	game.board_wagon_units(party, wagon, 0)
	await get_tree().process_frame
	game.set_selection([wagon])
	game.cam.focus_on(wagon.global_position)
	await get_tree().create_timer(0.9, true).timeout
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("res://shots/empire_age_transport_load_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_transport_load_v1.png size=", img2.get_size())
	get_tree().quit()
