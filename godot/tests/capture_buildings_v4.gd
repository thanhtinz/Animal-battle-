extends Node
## Captures the building-art pass under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_buildings.tscn
## Stages the full player base — Town Center, House, Barracks, Mining
## Camp, Watch Tower, Blacksmith (all tier-1 art at the 1.5x scale) —
## with units parked north (behind) and south (in front) of the Barracks
## and the Town Center to show the y-sort overlap. A second frame with
## the Build panel open is saved alongside for a layout sanity check.

var game = null
var w = null


func stage(btype: String, prefs: Array) -> Building:
	var defsz: Vector2i = game.get_build_def(btype).size
	for cand in prefs:
		if w.can_place(cand, defsz):
			return game._spawn_building(btype, 0, cand, true)
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
			if w.can_place(cand, defsz):
				return game._spawn_building(btype, 0, cand, true)
	return null


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

	var barr = stage("barracks", [tc_o + Vector2i(5, 0), tc_o + Vector2i(5, 1), tc_o + Vector2i(4, 0)])
	var house = stage("house", [tc_o + Vector2i(-3, 1), tc_o + Vector2i(-3, 0), tc_o + Vector2i(0, 4)])
	var camp = stage("mining_camp", [tc_o + Vector2i(5, 4), tc_o + Vector2i(4, 4), tc_o + Vector2i(6, 4)])
	var tower = stage("tower", [tc_o + Vector2i(1, -3), tc_o + Vector2i(0, -3), tc_o + Vector2i(4, -3)])
	var smith = stage("blacksmith", [tc_o + Vector2i(10, 1), tc_o + Vector2i(9, 0), tc_o + Vector2i(10, 4)])
	print("CAPTURE staged: barracks=", barr != null, " house=", house != null,
			" camp=", camp != null, " tower=", tower != null, " smith=", smith != null)

	# Train a fuller cast for real: 1 extra villager, a Militia, an Archer.
	game.resources.food += 600
	game.resources.gold += 600
	game.resources.wood += 600
	game.train_villager()
	if barr != null:
		game.train_militia()
		game.train_archer()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 90000:
		if game.pop_current() >= 6 and game.queued_total() == 0:
			break
		await get_tree().process_frame
	print("CAPTURE player units=", game.pop_current())

	# Park the cast by type: villagers behind the Barracks and the Town
	# Center (north -> the roofs cover them), the Militia + Archer in
	# front of the Barracks (south -> they cover its base), one villager
	# in front of the Mining Camp.
	var vils: Array = []
	var mil: Unit = null
	var arc: Unit = null
	for u in game.units:
		if u.team != 0:
			continue
		if u.unit_type == "villager":
			vils.append(u)
		elif u.unit_type == "militia":
			mil = u
		elif u.unit_type == "archer":
			arc = u
	if barr != null and vils.size() >= 2:
		var bo: Vector2i = barr.origin_cell
		park(vils[0], bo + Vector2i(0, -1))
		park(vils[1], bo + Vector2i(2, -1))
	if barr != null and mil != null:
		park(mil, barr.origin_cell + Vector2i(0, barr.size.y))
	if barr != null and arc != null:
		park(arc, barr.origin_cell + Vector2i(2, barr.size.y))
	if vils.size() >= 3:
		park(vils[2], tc_o + Vector2i(1, -1))
	if vils.size() >= 4 and camp != null:
		park(vils[3], camp.origin_cell + Vector2i(1, camp.size.y))
	await get_tree().process_frame
	await get_tree().process_frame

	# Frame the whole base.
	var focus := Vector2(330, 1810)
	game.cam.zoom = Vector2(1.25, 1.25) # zoom first: focus_on clamps by view size
	game.cam.focus_on(focus)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_buildings_v4.png")
	print("CAPTURE SAVED res://shots/empire_age_buildings_v4.png size=", img.get_size())

	# Second frame: Build panel open (layout fit check for 5 cards).
	game.hud.toggle_tab("build")
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("res://shots/empire_age_buildings_panel_v4.png")
	print("CAPTURE SAVED res://shots/empire_age_buildings_panel_v4.png")
	get_tree().quit()
