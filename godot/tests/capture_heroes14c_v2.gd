extends Node
## 14c-fix capture: TWO new heroes (Phong Linh + Lôi Chấn) in a
## live match after the sprite colour grade — the v1 shot showed
## Phong Linh washed-out/ghostly against the grass. Staged exactly
## like capture_heroes14c.gd, output under a NEW filename.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_heroes14c_v2.tscn

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

	# Phong Linh (the washed-out case) + Lôi Chấn beside her, with
	# villagers and militia alongside for colour comparison.
	game.slot_chars[0] = "phong_linh"
	var hero1: Unit = game._make_unit(0, base, "king")
	hero1.skill2_cd_t = 12.0
	hero1.skill3_cd_t = 45.0
	game.slot_chars[0] = "loi_chan"
	var hero2: Unit = game._make_unit(0, base + Vector2(96, 26), "king")
	hero2.skill2_cd_t = 20.0
	for off in [Vector2(44, 34), Vector2(-46, 22), Vector2(140, 44)]:
		game._make_unit(0, base + off, "villager")
	game._make_unit(0, base + Vector2(58, -20), "militia")
	game.cam.zoom = Vector2(1.4, 1.4)
	game.cam.focus_on(base + Vector2(48, 16))
	await _wait(0.4)
	await _snap("res://shots/empire_age_heroes8_match_v2.png")

	print("CAPTURE HEROES14C V2 DONE")
	get_tree().quit()
