extends Node
## Ships + beasts captures under Xvfb:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path <proj> \
##       res://tests/capture_ships_beasts.tscn -- ships|beasts
## Sets the map statics BEFORE Main instantiates, stages the scene
## (dock + fleet on the coast sea / a wolf pack threatening a
## villager with a bear by the trees), lifts Fog of War like the
## other verification captures, then saves one frame.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "ships"
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "grassland"
	ms.map_choice_done = true
	ms.chosen_layout = "coast" if mode == "ships" else "plains"
	var out := "res://shots/empire_age_ships_v1.png" if mode == "ships" \
			else "res://shots/empire_age_beasts_v1.png"
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	# Lift fog for the verification frame.
	game.fog.set_process(false)
	for i in range(game.fog.state.size()):
		game.fog.state[i] = 2
	game.fog.queue_redraw()
	var focus := Vector2(528, 1680)
	if mode == "ships":
		focus = _stage_ships(game)
	else:
		focus = _stage_beasts(game)
	game.cam.zoom = Vector2(1.15, 1.15)
	game.cam.focus_on(focus)
	await get_tree().create_timer(1.6).timeout
	for b in game.buildings:
		b.visible = true
	for u in game.units:
		u.visible = true
	for s in game.ships:
		s.visible = true
	for bst in game.world.beasts:
		bst.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("CAPTURE SAVED ", out, " size=", img.get_size())
	get_tree().quit()


## A dock on the sea shore south of the player base, a fishing boat
## working the nearest fish spot, a war ship and a transport nearby.
func _stage_ships(game) -> Vector2:
	var dock: Building = null
	for r in range(0, 14):
		if dock != null:
			break
		for dy in range(-r, r + 1):
			if dock != null:
				break
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = Vector2i(16, 50) + Vector2i(dx, dy)
				if game.placement_valid_at(cand, "dock"):
					dock = game._spawn_building("dock", 0, cand, true)
					break
	if dock == null:
		return Vector2(528, 1680)
	var centre: Vector2 = dock.position + Vector2(dock.size) * World.TILE * 0.5
	var fb: Ship = game.spawn_ship(dock, "fishing_boat")
	# Stage the worked spot on open water near the dock (this map's
	# natural spots cluster at the river mouth, out of frame): move
	# the nearest spot out to sea, park the boat beside it, order it.
	var spot: FishSpot = game.world.nearest_fish_spot(centre)
	var sea_cell: Vector2i = game.world.nearest_navigable(
			dock.origin_cell + Vector2i(7, 7), 6)
	if spot != null and sea_cell.x >= 0:
		spot.cell = sea_cell
		spot.global_position = game.world.cell_center(sea_cell)
		var beside: Vector2i = game.world.nearest_navigable(sea_cell + Vector2i(2, 0), 3)
		if beside.x >= 0:
			fb.global_position = game.world.cell_center(beside)
		fb.order_fish(spot)
	var ws: Ship = game.spawn_ship(dock, "war_ship")
	ws.order_move_cell(ws.cell() + Vector2i(4, 1))
	var tr: Ship = game.spawn_ship(dock, "transport")
	tr.order_move_cell(tr.cell() + Vector2i(-3, 1))
	if spot != null:
		return (centre + spot.global_position) * 0.5 + Vector2(0, 40)
	return centre + Vector2(30, 90)


## Three wolves from one den close in on a villager; a bear waits by
## the nearest trees inside the same frame.
func _stage_beasts(game) -> Vector2:
	var wolves: Array = []
	var bear: Beast = null
	for bst in game.world.beasts:
		if bst.species == "wolf" and wolves.size() < 3:
			wolves.append(bst)
		if bst.species == "bear" and bear == null:
			bear = bst
	if wolves.is_empty():
		return Vector2(672, 1344)
	var den: Vector2 = wolves[0].anchor
	for i in range(wolves.size()):
		wolves[i].global_position = den + Vector2(-40.0 + float(i) * 36.0, 14.0)
	var v: Unit = game._make_unit(0, den + Vector2(58, 6), "villager")
	v.state = "idle"
	if bear != null:
		# Put the bear beside the closest tree cluster to the den.
		var best_node: ResourceNode = null
		var bd := INF
		for n in game.world.nodes:
			if n.rtype != "wood":
				continue
			var d := den.distance_squared_to(n.global_position)
			if d < bd:
				bd = d
				best_node = n
		if best_node != null:
			var bc: Vector2i = game.world.nearest_walkable(best_node.cell + Vector2i(1, 1), 3)
			if bc.x >= 0:
				bear.global_position = game.world.cell_center(bc)
				bear.anchor = bear.global_position
	return den + Vector2(20, 10)
