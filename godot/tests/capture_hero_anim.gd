extends Node
## Per-character rig animation capture (13n): xvfb-run godot
## res://tests/capture_hero_anim.tscn with HERO_CHAR=<char id> —
## records the character's articulated animation in four phases
## (idle breathing -> walk east with real leg swings -> attack
## swings -> active-skill cast pose) as PNG frames in
## /tmp/heroframes_<char>/ at 12 fps; the GIFs in shots/ are
## assembled from them with PIL (see KE-HOACH 13n).

var game = null
var w = null
var hero: Unit = null
var frame_i := 0
var char_id := "ngan_ky"
var out_dir := ""


func _snap(follow := true) -> void:
	if hero != null:
		hero.visible = true # fog updates are frozen for the shoot
	game.cam.zoom = Vector2(2.5, 2.5)
	if follow:
		game.cam.focus_on(hero.global_position + Vector2(0, 6))
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/f%03d.png" % frame_i)
	frame_i += 1


func _phase(frames: int, follow := true) -> void:
	for i in range(frames):
		await get_tree().create_timer(1.0 / 12.0).timeout
		await _snap(follow)


func _ready() -> void:
	char_id = OS.get_environment("HERO_CHAR")
	if char_id == "":
		char_id = "ngan_ky"
	out_dir = "/tmp/heroframes_" + char_id
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.hide_home()
	game.set_paused(false)
	game.world.set_sky_active(true)
	await get_tree().process_frame
	w = game.world
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	game.slot_chars[0] = char_id # the staged draw
	game.fog.visible = false
	game.fog.set_process(false)
	for u in game.units:
		u.visible = true
	var tc_o: Vector2i = game.player_tc.origin_cell
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			u.global_position = w.cell_center(w.nearest_walkable(tc_o + Vector2i(5, 3)))
			u.state = "idle"
			u.path.clear()
	# Stage well inside the map: near the west edge the camera
	# clamp (half-view at zoom 2.5 = 230 world px) pushes the
	# hero off-centre no matter how often we focus.
	var start_cell: Vector2i = w.nearest_walkable(tc_o + Vector2i(7, 4))
	hero = game._make_unit(0, w.cell_center(start_cell), "king")
	hero.state = "idle"
	hero.path.clear()
	await get_tree().process_frame

	# Phase 1: idle breathing (8 frames).
	await _phase(8)
	# Phase 2: walk east 4 tiles — the leg-swing showcase. The
	# camera LOCKS (aimed 64 world px east of the start) so the
	# background stays pixel-static and the GIF compresses like
	# the v1 one; the hero crosses the crop under his own steps.
	game.cam.focus_on(hero.global_position + Vector2(64, 6))
	hero.order_move_cell(w.nearest_walkable(start_cell + Vector2i(4, 0)))
	await _phase(26, false)
	# Phase 3: attack an enemy militia planted ahead.
	var foe_cell: Vector2i = w.nearest_walkable(w.world_to_cell(hero.global_position) + Vector2i(2, 0))
	var foe: Unit = game._make_unit(1, w.cell_center(foe_cell), "militia")
	foe.state = "idle"
	foe.path.clear()
	foe.hp = 100000.0
	foe.visible = true
	hero.order_attack(foe)
	await _phase(24)
	# Phase 4: the active-skill cast pose.
	game.cast_hero_skill(hero)
	await _phase(16)
	print("HERO ANIM FRAMES SAVED ", frame_i, " char=", char_id)
	get_tree().quit()
