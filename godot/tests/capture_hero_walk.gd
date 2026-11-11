extends Node
## Zoomed walk capture (13n follow-up): xvfb-run godot
## res://tests/capture_hero_walk.tscn with HERO_CHAR=<char id> —
## records the rigged hero WALKING at zoom 4.5 (about 2x the v2
## GIF scale) in two camera-LOCKED segments (east, then south)
## as full-viewport PNG frames in /tmp/walkframes_<char>/ at
## 12 fps; the v3 GIFs in shots/ are centre-cropped from them
## with PIL, and the locked camera keeps the background pixel-
## static so leg-band motion can be measured frame to frame.
## Staging notes: the zoom is set BEFORE focus_on (its clamp
## uses the current zoom), the stage is a tree-free clearing
## scanned via world.is_solid, and clouds are switched off —
## drifting cloud shadows otherwise swamp the leg band.

var game = null
var w = null
var hero: Unit = null
var frame_i := 0
var char_id := "ngan_ky"
var out_dir := ""


func _snap() -> void:
	if hero != null:
		hero.visible = true # fog updates are frozen for the shoot
	game.cam.zoom = Vector2(4.5, 4.5)
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/f%03d.png" % frame_i)
	frame_i += 1


func _phase(frames: int) -> void:
	for i in range(frames):
		await get_tree().create_timer(1.0 / 12.0).timeout
		await _snap()


func _clear(c: Vector2i) -> bool:
	for y in range(c.y - 3, c.y + 4):
		for x in range(c.x - 4, c.x + 6):
			var n := Vector2i(x, y)
			if not w.in_bounds(n) or w.is_solid(n):
				return false
	return true


func _find_clearing(base: Vector2i) -> Vector2i:
	for r in range(0, 24):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = base + Vector2i(dx, dy)
				if _clear(c):
					return c
	return base


func _ready() -> void:
	char_id = OS.get_environment("HERO_CHAR")
	if char_id == "":
		char_id = "ngan_ky"
	out_dir = "/tmp/walkframes_" + char_id
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.hide_home()
	game.set_paused(false)
	game.world.set_sky_active(false) # clouds off for the shoot
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
	var stage: Vector2i = _find_clearing(tc_o + Vector2i(12, 8))
	hero = game._make_unit(0, w.cell_center(stage), "king")
	hero.state = "idle"
	hero.path.clear()
	game.cam.zoom = Vector2(4.5, 4.5) # BEFORE any focus_on clamp
	await get_tree().process_frame

	# Segment A: walk EAST 3 tiles; camera locked on the walk's
	# midpoint, raised to the body's centre line.
	game.cam.focus_on(hero.global_position + Vector2(48, -22))
	hero.order_move_cell(w.nearest_walkable(stage + Vector2i(3, 0)))
	await _phase(12)
	# Segment B: walk SOUTH 3 tiles; only the first frames are
	# kept, while the hero is well inside the crop.
	var cell_b: Vector2i = w.world_to_cell(hero.global_position)
	game.cam.focus_on(hero.global_position + Vector2(0, 0))
	hero.order_move_cell(w.nearest_walkable(cell_b + Vector2i(0, 3)))
	await _phase(5)
	print("WALK FRAMES SAVED ", frame_i, " char=", char_id,
			" stage=", stage)
	get_tree().quit()
