extends Node
## Captures the 4 new buildings (Lumber Camp, Storage, Market, Dock)
## under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_newbuildings.tscn
## Main frame: a wide shot (zoom 0.6) covering the player base — with
## the Lumber Camp, Storage and Market staged around the Town Center —
## and the lake, where the Dock stands at the shoreline (its only
## legal placement). Bonus frames: the Build panel open on the base
## (9 cards, incl. the two art-thumbnail cards) and the Market selected
## (exchange rows visible in the selection chip).

var game = null
var w = null


func stage(btype: String, prefs: Array) -> Building:
	var defsz: Vector2i = game.get_build_def(btype).size
	for cand in prefs:
		if w.can_place(cand, defsz):
			return game._spawn_building(btype, 0, cand, true)
	for dy in range(-14, 15):
		for dx in range(-14, 15):
			var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
			if w.can_place(cand, defsz):
				return game._spawn_building(btype, 0, cand, true)
	return null


func stage_dock() -> Building:
	var defsz: Vector2i = game.get_build_def("dock").size
	# Shoreline cells nearest to the player base first (shorter walk
	# for the camera frame): scan by distance to the Town Center.
	var spots: Array = []
	for yy in range(0, World.MAP_H - defsz.y + 1):
		for xx in range(0, World.MAP_W - defsz.x + 1):
			var cand := Vector2i(xx, yy)
			if w.can_place(cand, defsz) and game.is_shore_spot(cand, defsz):
				spots.append(cand)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - game.player_tc.origin_cell).length() < (b - game.player_tc.origin_cell).length())
	if spots.is_empty():
		return null
	return game._spawn_building("dock", 0, spots[0], true)


func park(u: Unit, cell: Vector2i) -> void:
	var c: Vector2i = w.nearest_walkable(cell)
	if c.x < 0:
		return
	u.global_position = w.cell_center(c)
	u.state = "idle"
	u.path.clear()
	u.path_cells.clear()


func _ready() -> void:
	Engine.time_scale = 3.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	var tc_o: Vector2i = game.player_tc.origin_cell # (6, 54)

	# Staged in a loose row east of the Town Center so one wide frame
	# can hold the base buildings and the lake's west shore together.
	var lumber = stage("lumber_camp", [Vector2i(12, 50), Vector2i(12, 51), Vector2i(11, 50), Vector2i(13, 49), Vector2i(12, 49)])
	var storage = stage("storage", [Vector2i(16, 53), Vector2i(16, 52), Vector2i(17, 53), Vector2i(15, 53), Vector2i(16, 54)])
	var market = stage("market", [Vector2i(20, 50), Vector2i(20, 51), Vector2i(19, 50), Vector2i(21, 49), Vector2i(20, 49)])
	var dock = stage_dock()
	print("CAPTURE staged: lumber=", lumber.origin_cell if lumber != null else Vector2i(-1, -1),
			" storage=", storage.origin_cell if storage != null else Vector2i(-1, -1),
			" market=", market.origin_cell if market != null else Vector2i(-1, -1),
			" dock=", dock.origin_cell if dock != null else Vector2i(-1, -1))

	# Park the starting villagers: two by the new base buildings, one
	# down by the Dock.
	var vils: Array = []
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			vils.append(u)
	if vils.size() >= 1 and lumber != null:
		park(vils[0], lumber.origin_cell + Vector2i(1, lumber.size.y))
	if vils.size() >= 2 and market != null:
		park(vils[1], market.origin_cell + Vector2i(1, market.size.y))
	if vils.size() >= 3 and dock != null:
		park(vils[2], dock.origin_cell + Vector2i(1, dock.size.y))
	await get_tree().process_frame
	await get_tree().process_frame

	# Main frame: base + lake in one wide shot.
	game.cam.zoom = Vector2(0.62, 0.62)
	game.cam.focus_on(Vector2(930, 1380))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_newbuildings_v2.png")
	print("CAPTURE SAVED res://shots/empire_age_newbuildings_v2.png size=", img.get_size())

	# Bonus frame 1: Build panel open over the base (9 cards).
	game.cam.zoom = Vector2(1.25, 1.25)
	if market != null:
		game.cam.focus_on(market.position + Vector2(48, 60))
	game.hud.toggle_tab("build")
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("res://shots/empire_age_newbuildings_panel_v2.png")
	print("CAPTURE SAVED res://shots/empire_age_newbuildings_panel_v2.png")
	game.hud.toggle_tab("build")

	# Bonus frame 2: Market selected — exchange rows in the chip.
	if market != null:
		game.clear_selection()
		game.selected_building = market
		game.resources.food = 250 # some sell buttons light up
		game.resources.gold = 120
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var img3 := get_viewport().get_texture().get_image()
		img3.save_png("res://shots/empire_age_newbuildings_market_v2.png")
		print("CAPTURE SAVED res://shots/empire_age_newbuildings_market_v2.png")
	get_tree().quit()
