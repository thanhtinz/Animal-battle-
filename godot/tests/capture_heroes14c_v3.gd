extends Node
## 14c-fix2 capture: a NEW hero (Phong Linh) standing IMMEDIATELY
## beside an ORIGINAL hero (Ngân Kỵ) on the same ground line, plus
## a second pair (Kim Hoa + Lôi Chấn) — proves the chibi proportion
## parity after the turnaround regeneration. Output NEW filename.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_heroes14c_v3.tscn

var game = null


func _snap(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("CAPTURE SAVED ", path, " size=", img.get_size())


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _ready() -> void:
	Net.auto = {"mp-name": "Tin"}
	game = load("res://main.tscn").instantiate()
	add_child(game)
	var guard := 0
	while game.home == null and guard < 1800:
		await get_tree().process_frame
		guard += 1
	await _wait(0.6)

	game.home_quick_match()
	for i in range(6):
		await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = true
	if game.world.sky_layer != null:
		game.world.sky_layer.visible = false
	var anchor: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(7, 7))
	var base: Vector2 = game.world.cell_center(anchor)

	# Pair 1 (same ground line): NEW Phong Linh beside ORIGINAL
	# Ngân Kỵ. Pair 2: ORIGINAL Kim Hoa beside NEW Lôi Chấn.
	game.slot_chars[0] = "phong_linh"
	game._make_unit(0, base, "king")
	game.slot_chars[0] = "ngan_ky"
	game._make_unit(0, base + Vector2(54, 0), "king")
	game.slot_chars[0] = "kim_hoa"
	game._make_unit(0, base + Vector2(168, 10), "king")
	game.slot_chars[0] = "loi_chan"
	game._make_unit(0, base + Vector2(222, 10), "king")
	for off in [Vector2(28, 36), Vector2(196, 44), Vector2(-40, 26)]:
		game._make_unit(0, base + off, "villager")
	game.cam.zoom = Vector2(1.4, 1.4)
	game.cam.focus_on(base + Vector2(110, 12))
	await _wait(0.4)
	await _snap("res://shots/empire_age_heroes8_match_v3.png")

	print("CAPTURE HEROES14C V3 DONE")
	get_tree().quit()
