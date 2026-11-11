extends Node
## Two-heroes in-game shot (13j final model): xvfb-run godot
## res://tests/capture_king.tscn — the player's hero (Ngân Kỵ,
## drawn for slot 0) stands before his Castle among Militia and
## Cavalry; the AI's hero (Lam Bào — note the black hair of Tín's
## fix) faces him a few tiles away with his own troops. Characters
## carry NO team colour: each player's NAME floats over their
## hero, tinted with the slot colour (red "Bạn" / blue "Máy").

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
	# Skip the Home boot screen (it only opens on non-headless
	# boots and pauses the match behind it).
	(load("res://scripts/main.gd") as GDScript).map_choice_done = true
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	# The staged draw: Ngân Kỵ for the player, Lam Bào for the AI.
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
	var hero: Unit = game._make_unit(0, front, "king")
	hero.state = "idle"
	hero.path.clear()
	var spots := [
		["militia", Vector2(-52, 10)], ["militia", Vector2(54, 12)],
		["archer", Vector2(-96, 26)], ["spearman", Vector2(98, 28)],
		["cavalry", Vector2(-130, -6)],
	]
	for s in spots:
		var u: Unit = game._make_unit(0, front + s[1], String(s[0]))
		u.state = "idle"
		u.path.clear()
	# The AI hero + escort, ~5.5 tiles east.
	var foe_pos: Vector2 = front + Vector2(180, 6)
	var foe: Unit = game._make_unit(1, foe_pos, "king")
	foe.state = "idle"
	foe.path.clear()
	for s in [["militia", Vector2(-46, 14)], ["militia", Vector2(48, 16)],
			["cavalry", Vector2(120, -2)]]:
		var u: Unit = game._make_unit(1, foe_pos + s[1], String(s[0]))
		u.state = "idle"
		u.path.clear()
	# A few frames for unit setup + the aura poll, then FREEZE
	# the sim (a staged still — live units would wander into a
	# brawl) and lift the fog so both parties read clearly.
	for i in range(6):
		await get_tree().process_frame
	game.set_paused(true)
	game.fog.visible = false
	game.fog.set_process(false)
	for u in game.units:
		u.visible = true

	game.cam.zoom = Vector2(1.5, 1.5)
	game.cam.focus_on(front + Vector2(58, 30))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_heroes_ingame_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_heroes_ingame_v1.png size=", img.get_size())
	get_tree().quit()
