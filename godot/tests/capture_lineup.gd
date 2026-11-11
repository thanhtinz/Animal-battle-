extends Node
## Lineup capture for the unit display-scale pass (v3: the villager
## exception — the civilian must read as the smallest person in frame):
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_lineup.tscn
## A House and a Barracks stand behind a row of the four infantry types
## (Villager, Militia, Archer, Spearman) at zoom 1 (the default
## camera), so unit-vs-building and villager-vs-soldier proportions
## can be judged in one glance.

var game = null
var w = null


func find_spot(size: Vector2i, near: Vector2i) -> Vector2i:
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := near + Vector2i(dx, dy)
				if cand.x >= 0 and cand.y >= 0 and w.can_place(cand, size):
					return cand
	return Vector2i(-1, -1)


func _ready() -> void:
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	var tc_o: Vector2i = game.player_tc.origin_cell

	var house_spot := find_spot(Vector2i(2, 2), tc_o + Vector2i(3, -6))
	var house: Building = game._spawn_building("house", 0, house_spot, true)
	var barr_spot := find_spot(Vector2i(3, 3), tc_o + Vector2i(4, -3))
	var barr: Building = game._spawn_building("barracks", 0, barr_spot, true)
	print("CAPTURE house=", house != null, " barracks=", barr != null)

	# Park the starting villagers north of the TC so the row stays clean.
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			u.global_position = w.cell_center(w.nearest_walkable(tc_o + Vector2i(-2, -4)))
			u.state = "idle"
			u.path.clear()
	# Row of units on the open ground NORTH of the base (the player TC
	# sits near the map's south edge, so a southern row would clip);
	# the House/Barracks/TC stay in frame below the row.
	var row_y: int = tc_o.y - 9
	var kinds := ["villager", "militia", "archer", "spearman"]
	var gaps := [0, 2, 4, 6]
	var row_first := Vector2.ZERO
	var row_last := Vector2.ZERO
	for i in range(kinds.size()):
		var cell := Vector2i(tc_o.x - 1 + gaps[i], row_y)
		cell = w.nearest_walkable(cell)
		var u: Unit = game._make_unit(0, w.cell_center(cell), kinds[i])
		u.state = "idle"
		u.path.clear()
		if i == 0:
			row_first = u.global_position
		row_last = u.global_position
	var mid := (row_first + row_last) * 0.5
	await get_tree().process_frame
	await get_tree().process_frame

	game.cam.zoom = Vector2.ONE # zoom first: focus_on clamps by view size
	game.cam.focus_on(mid + Vector2(0, 70))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_lineup_v3.png")
	print("CAPTURE SAVED res://shots/empire_age_lineup_v3.png size=", img.get_size())
	get_tree().quit()
