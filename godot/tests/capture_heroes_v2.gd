extends Node
## Two-heroes in-game shot, 13n edition: xvfb-run godot
## res://tests/capture_heroes_v2.tscn — as capture_king.gd (the
## player's Ngân Kỵ before his Castle, the AI's Lam Bào opposite,
## names overhead, troops in team colours) but both heroes are
## caught WALKING toward each other, frozen at a stride extreme
## so the rig's leg swing reads in the still: legs apart,
## weapons in hand.

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
	(load("res://scripts/main.gd") as GDScript).map_choice_done = true
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	game.slot_chars[0] = "ngan_ky"
	game.slot_chars[1] = "lam_bao"
	var tc_o: Vector2i = game.player_tc.origin_cell

	var castle_spot := find_spot(Vector2i(4, 4), tc_o + Vector2i(-2, -8))
	var castle: Building = game._spawn_building("castle", 0, castle_spot, true)
	print("CAPTURE castle=", castle != null)

	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			u.global_position = w.cell_center(w.nearest_walkable(tc_o + Vector2i(4, 2)))
			u.state = "idle"
			u.path.clear()

	var csize: Vector2i = game.get_build_def("castle")["size"]
	var front_cell := castle.origin_cell + Vector2i(csize.x / 2, csize.y + 2)
	var front: Vector2 = w.cell_center(front_cell) + Vector2(0, 6)
	var hero: Unit = game._make_unit(0, front + Vector2(60, 96), "king")
	# No escort troops this time: the lane belongs to the two
	# heroes alone so the walking stride reads clean.
	var foe_pos: Vector2 = front + Vector2(210, 96)
	var foe: Unit = game._make_unit(1, foe_pos, "king")
	# Pose them marching toward each other WITHOUT live orders:
	# at this machine's frame rate a live approach closes the
	# gap and turns into a fight before the freeze. A hand-set
	# move state + path point gives the same walk pose the sim
	# produces (the freeze below sets the stride phase).
	hero.state = "move"
	hero.path = [hero.global_position + Vector2(96, 0)]
	foe.state = "move"
	foe.path = [foe.global_position + Vector2(-96, 0)]
	for i in range(2):
		await get_tree().process_frame
	game.set_paused(true)
	game.fog.visible = false
	game.fog.set_process(false)
	for u in game.units:
		u.visible = true
	# Freeze both at a stride extreme and pose them once by hand
	# (the sim is paused; _king_tick is presentation-only).
	for h in [hero, foe]:
		h._king_phase = PI * 0.5
		h._king_tick(0.001)

	# Frame tight on the pair: midpoint between the two heroes
	# at freeze time, zoomed so the stride reads.
	var mid: Vector2 = (hero.global_position + foe.global_position) * 0.5
	game.cam.zoom = Vector2(2.2, 2.2)
	game.cam.focus_on(mid + Vector2(0, 10))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_heroes_ingame_v2.png")
	print("CAPTURE SAVED res://shots/empire_age_heroes_ingame_v2.png size=", img.get_size())
	get_tree().quit()
