extends Node
## Captures the 16b medieval roster under Xvfb:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_heroes16b.tscn
## 1) the Collection screen with the NEW 8 heroes (lobby overlay),
## 2) the Knight in a live match — player name overhead + the ONE
##    skill button (Khiên Sư Tử, mid-cooldown sweep),
## 3) the Berserker's Rìu Xoáy Cuồng Nộ mid-cast, ringed by foes.

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

	# ---- 1) Collection: the new eight on the roster grid.
	game._ensure_lobby()
	game.lobby._show_characters()
	await _wait(0.5)
	await _snap("res://shots/empire_age_medieval8_collection_v1.png")
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

	# ---- 2) Knight in match: name overhead + ONE skill button.
	game.slot_chars[0] = "knight"
	var hero: Unit = game._make_unit(0, base, "king")
	hero.skill_cd_t = 25.0 # mid-cooldown: sweep + seconds on the button
	for off in [Vector2(46, 18), Vector2(-42, 30)]:
		game._make_unit(0, base + off, "militia")
	game.cam.zoom = Vector2(1.4, 1.4)
	game.cam.focus_on(base)
	await _wait(0.4)
	await _snap("res://shots/empire_age_medieval8_match_v1.png")

	# ---- 3) Berserker whirlwind mid-cast, ringed by enemies.
	game.units.erase(hero)
	hero.queue_free()
	game.slot_chars[0] = "berserker"
	var bk: Unit = game._make_unit(0, base, "king")
	for off in [Vector2(48, -6), Vector2(-44, 22), Vector2(10, 52), Vector2(-16, -46)]:
		var f: Unit = game._make_unit(1, base + off, "militia")
		f.max_hp = 5000.0
		f.hp = 5000.0
	game.cam.focus_on(base)
	await _wait(0.3)
	game.cast_hero_skill(bk)
	await _wait(0.35) # fan FX + hit sparks in flight
	await _snap("res://shots/empire_age_medieval8_skill_v1.png")

	print("CAPTURE HEROES16B DONE")
	get_tree().quit()
