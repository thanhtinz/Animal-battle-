extends Node
## Hero animation capture (13j): xvfb-run godot
## res://tests/capture_king_anim.tscn — records Ngân Kỵ's
## procedural animation in four phases (idle breathing -> walk
## east with step dust -> attack lunges with the gold slash ->
## Xung Phong cast burst + buffed advance) as PNG frames in
## /tmp/kingframes/ at 12 fps; the GIF is assembled from them
## with PIL (see KE-HOACH 13j).

var game = null
var w = null
var king: Unit = null
var frame_i := 0
const OUT_DIR := "/tmp/kingframes"


func _snap() -> void:
	game.cam.zoom = Vector2(2.0, 2.0)
	game.cam.focus_on(king.global_position + Vector2(0, 10))
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/f%03d.png" % frame_i)
	frame_i += 1


func _phase(frames: int) -> void:
	for i in range(frames):
		await get_tree().create_timer(1.0 / 12.0).timeout
		await _snap()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	# Dismiss the Home boot screen (non-headless boots land on it
	# with the match paused behind) and start the world.
	game.hide_home()
	game.set_paused(false)
	game.world.set_sky_active(true)
	await get_tree().process_frame
	w = game.world
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	game.slot_chars[0] = "ngan_ky" # the staged draw
	# Lift the fog for the recording (the walk east leaves the
	# explored pocket — the GIF would be mostly black otherwise).
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
	var start_cell: Vector2i = w.nearest_walkable(tc_o + Vector2i(-4, -6))
	king = game._make_unit(0, w.cell_center(start_cell), "king")
	king.state = "idle"
	king.path.clear()
	await get_tree().process_frame

	# Phase 1: idle breathing (12 frames = 1 s).
	await _phase(12)
	# Phase 2: walk east ~5 tiles.
	king.order_move_cell(w.nearest_walkable(start_cell + Vector2i(5, 0)))
	await _phase(26)
	# Phase 3: attack an enemy militia planted ahead.
	var foe_cell: Vector2i = w.nearest_walkable(w.world_to_cell(king.global_position) + Vector2i(2, 0))
	var foe: Unit = game._make_unit(1, w.cell_center(foe_cell), "militia")
	foe.state = "idle"
	foe.path.clear()
	foe.hp = 100000.0
	foe.visible = true
	king.order_attack(foe)
	await _phase(24)
	# Phase 4: Xung Phong — the cast burst, then the buffed charge.
	game.cast_hero_skill(king)
	await _phase(18)
	print("ANIM FRAMES SAVED ", frame_i)
	get_tree().quit()
