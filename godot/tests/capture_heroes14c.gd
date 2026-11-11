extends Node
## Captures the 14c hero presentation under Xvfb:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_heroes14c.tscn
## 1) the Collection screen with all 8 heroes (lobby overlay),
## 2) Phong Linh in a live match — player name overhead tinted
##    by slot colour + the three skill buttons with her icons,
## 3) Cuồng Phong Nộ (cyclone Ulti) mid-cast, pulling enemies.

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

	# ---- 1) Collection: all eight heroes on the roster grid.
	game._ensure_lobby()
	game.lobby._show_characters()
	await _wait(0.5)
	await _snap("res://shots/empire_age_heroes8_collection_v1.png")
	game.lobby.visible = false

	# ---- enter a quick match for the in-match shots.
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

	# ---- 2) Phong Linh in match: name overhead + skill buttons.
	game.slot_chars[0] = "phong_linh"
	var hero: Unit = game._make_unit(0, base, "king")
	hero.skill2_cd_t = 12.0
	hero.skill3_cd_t = 45.0
	for off in [Vector2(46, 18), Vector2(-42, 30)]:
		game._make_unit(0, base + off, "militia")
	game.cam.zoom = Vector2(1.4, 1.4)
	game.cam.focus_on(base)
	await _wait(0.4)
	await _snap("res://shots/empire_age_heroes8_match_v1.png")

	# ---- 3) Cuồng Phong Nộ mid-cast: enemies spiral into the eye.
	hero.skill3_cd_t = 0.0
	var eye := base + Vector2(105, 10)
	for off in [Vector2(70, -25), Vector2(120, 30), Vector2(95, 55)]:
		var f: Unit = game._make_unit(1, base + off, "militia")
		f.max_hp = 5000.0
		f.hp = 5000.0
	game.cam.focus_on(eye)
	game.cast_hero_skill3(hero, eye)
	await _wait(1.1) # cyclone spinning, enemies visibly pulled in
	await _snap("res://shots/empire_age_heroes8_skill_v1.png")

	print("CAPTURE HEROES14C DONE")
	get_tree().quit()
