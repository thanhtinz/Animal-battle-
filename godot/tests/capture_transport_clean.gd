extends Node
## Residue-cleanup verification captures (owner catch "Cắt hình
## còn trắng kìa"): side-view cart and wagon on open grass at
## zoom 2.2, a villager alongside for scale. The zoom companion
## shot is a NEAREST crop of this frame made offline.
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_transport_clean.tscn

func _ready() -> void:
	Engine.time_scale = 3.0
	Net.auto = {"capture": "transport_clean"}
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
	game.cam.zoom = Vector2.ONE * 2.2
	var tc_cell: Vector2i = game.player_tc.origin_cell
	# Cart (right-facing) with a villager on the same ground line.
	var base: Vector2i = game.world.nearest_walkable(tc_cell + Vector2i(8, 6))
	var cart = game._make_unit(0, game.world.cell_center(base), "cart", 0)
	cart.facing = "right"
	var ccell: Vector2i = cart.cell()
	var vil = game._make_unit(0, game.world.cell_center(
			game.world.nearest_walkable(ccell + Vector2i(4, 0))),
			"villager", 0)
	vil.facing = "down"
	# Wagon (right-facing) a few cells below the cart.
	var wbase: Vector2i = game.world.nearest_walkable(ccell + Vector2i(0, 5))
	var wagon = game._make_unit(0, game.world.cell_center(wbase), "wagon", 0)
	wagon.facing = "right"
	await get_tree().create_timer(0.9, true).timeout
	game.set_selection([cart])
	game.cam.focus_on((cart.global_position + wagon.global_position) * 0.5
			+ Vector2(30, -6))
	await get_tree().create_timer(0.4, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_transport_clean_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_transport_clean_v1.png size=", img.get_size())
	get_tree().quit()
