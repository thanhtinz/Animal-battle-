extends Node
## 15g scale-pass captures: size comparison at a glance.
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_transport_scale.tscn
## Shot 1: trade cart (side view) on the same ground line as a
## villager + a militia, Market behind. Shot 2: the troop wagon
## (side view) beside three standing soldiers, five more aboard.
## Camera zooms to 1.6 so the comparison reads at a glance.

func _ready() -> void:
	Engine.time_scale = 3.0
	Net.auto = {"capture": "transport_scale"}
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	var guard := 0
	while (game.world == null or game.player_tc == null) and guard < 1800:
		await get_tree().process_frame
		guard += 1
	game.home_quick_match()
	if game.enemy_ai != null:
		game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = true
	game.resources = {"food": 5000, "wood": 5000, "gold": 5000, "stone": 500, "iron": 0}
	game.cam.zoom = Vector2.ONE * 1.6
	var tc_cell: Vector2i = game.player_tc.origin_cell
	var mkt = game._spawn_building("market", 0,
			game._test_spot_near(tc_cell + Vector2i(6, 0)), true, 0)

	# --- shot 1: cart + villager + militia on one ground line.
	var base: Vector2i = game.world.nearest_walkable(
			mkt.origin_cell + Vector2i(1, 4))
	var cart = game._make_unit(0, game.world.cell_center(base), "cart", 0)
	cart.facing = "right"
	var ccell: Vector2i = cart.cell()
	var vil = game._make_unit(0, game.world.cell_center(
			game.world.nearest_walkable(ccell + Vector2i(3, 0))),
			"villager", 0)
	vil.facing = "down"
	var mil = game._make_unit(0, game.world.cell_center(
			game.world.nearest_walkable(ccell + Vector2i(4, 0))),
			"militia", 0)
	mil.facing = "down"
	await get_tree().create_timer(0.8, true).timeout
	game.set_selection([cart])
	game.cam.focus_on(cart.global_position + Vector2(56, -14))
	await get_tree().create_timer(0.4, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_transport_scale_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_transport_scale_v1.png size=", img.get_size())

	# --- shot 2: wagon + three standing soldiers, five aboard.
	game.set_selection([])
	var wbase: Vector2i = game.world.nearest_walkable(
			tc_cell + Vector2i(12, 7))
	var wagon = game._make_unit(0, game.world.cell_center(wbase), "wagon", 0)
	wagon.facing = "right"
	var kinds := ["militia", "archer", "spearman", "militia", "villager"]
	var party: Array = []
	for i in range(5):
		party.append(game._make_unit(0, game.world.cell_center(
				game.world.nearest_walkable(wbase + Vector2i(1, i % 3))),
				kinds[i], 0))
	game.board_wagon_units(party, wagon, 0)
	var wcell: Vector2i = wagon.cell()
	for i in range(3):
		var su = game._make_unit(0, game.world.cell_center(
				game.world.nearest_walkable(wcell + Vector2i(3 + i, 0))),
				kinds[i], 0)
		su.facing = "down"
	await get_tree().create_timer(0.8, true).timeout
	game.set_selection([wagon])
	game.cam.focus_on(wagon.global_position + Vector2(64, -16))
	await get_tree().create_timer(0.4, true).timeout
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("res://shots/empire_age_transport_scale_v2.png")
	print("CAPTURE SAVED res://shots/empire_age_transport_scale_v2.png size=", img2.get_size())
	get_tree().quit()
