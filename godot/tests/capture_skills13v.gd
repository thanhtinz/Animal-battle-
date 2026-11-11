extends Node
## Captures the 13v skill presentation under Xvfb:
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_skills13v.tscn
## 1) the three HUD skill buttons (icons + cooldown sweeps +
##    seconds, gold-framed Ulti), then one cast shot per Ulti:
##    Vương Kiếm Giáng Thế (plunging sword), Vạn Hoa Khai Thiên
##    (bloom), Băng Hà Vĩnh Cửu (blizzard), Thiên Màn Bất Diệt
##    (dome). Heroes are force-spawned per character near the
##    player TC (fog-revealed ground), waves/beasts parked.

var game = null


func _snap(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("CAPTURE SAVED ", path, " size=", img.get_size())


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frame(pos: Vector2) -> void:
	game.cam.zoom = Vector2(1.4, 1.4)
	game.cam.focus_on(pos)


func _retire(hero: Unit) -> void:
	if hero != null:
		game.units.erase(hero)
		hero.queue_free()


func _ready() -> void:
	Net.auto = {"mp-name": "CaptureSkills13v"}
	game = load("res://main.tscn").instantiate()
	add_child(game)
	var guard := 0
	while (game.enemy_ai == null or game.player_tc == null) and guard < 1800:
		await get_tree().process_frame
		guard += 1
	game.home_quick_match()
	for i in range(6):
		await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = true
	if game.world.sky_layer != null:
		game.world.sky_layer.visible = false # clouds out of the frame
	var anchor: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(7, 7))
	var base: Vector2 = game.world.cell_center(anchor)

	# ---- 1) Skill buttons: Ngân Kỵ with Chiêu 2 + Ulti mid-CD.
	game.slot_chars[0] = "ngan_ky"
	var hero: Unit = game._make_unit(0, base, "king")
	hero.skill2_cd_t = 17.0
	hero.skill3_cd_t = 83.0
	_frame(base)
	await _snap("res://shots/empire_age_skill_buttons_v1.png")

	# ---- 2) Vương Kiếm Giáng Thế: plunge onto an enemy group.
	var foes: Array = []
	for off in [Vector2(90, -10), Vector2(130, 25), Vector2(105, 55)]:
		var f: Unit = game._make_unit(1, base + off, "militia")
		f.max_hp = 5000.0
		f.hp = 5000.0
		foes.append(f)
	hero.skill3_cd_t = 0.0
	game.cast_hero_skill3(hero, base + Vector2(108, 22))
	await _wait(0.40) # sword has slammed in; dust ring expanding
	await _snap("res://shots/empire_age_skill_ulti_ngan_ky_v1.png")
	_retire(hero)

	# ---- 3) Vạn Hoa Khai Thiên: bloom over wounded allies.
	game.slot_chars[0] = "kim_hoa"
	var h2: Unit = game._make_unit(0, base + Vector2(40, -205), "king")
	for off in [Vector2(45, 0), Vector2(-50, 15), Vector2(5, 55)]:
		var a: Unit = game._make_unit(0, h2.global_position + off, "militia")
		a.max_hp = 1000.0
		a.hp = 300.0
	_frame(h2.global_position)
	game.cast_hero_skill3(h2, h2.global_position)
	await _wait(0.30)
	await _snap("res://shots/empire_age_skill_ulti_kim_hoa_v1.png")
	_retire(h2)

	# ---- 4) Băng Hà Vĩnh Cửu: blizzard swallowing an enemy group.
	game.slot_chars[0] = "lam_bao"
	var h3: Unit = game._make_unit(0, base + Vector2(170, -210), "king")
	for off in [Vector2(120, 0), Vector2(155, 35), Vector2(100, 45)]:
		var f2: Unit = game._make_unit(1, h3.global_position + off, "militia")
		f2.max_hp = 5000.0
		f2.hp = 5000.0
	_frame(h3.global_position + Vector2(110, 20))
	game.cast_hero_skill3(h3, h3.global_position + Vector2(125, 20))
	await _wait(0.9)
	await _snap("res://shots/empire_age_skill_ulti_lam_bao_v1.png")
	_retire(h3)

	# ---- 5) Thiên Màn Bất Diệt: dome over the hero's group.
	game.slot_chars[0] = "bach_sa"
	var h4: Unit = game._make_unit(0, base + Vector2(-160, -350), "king")
	for off in [Vector2(50, 10), Vector2(-45, 30)]:
		game._make_unit(0, h4.global_position + off, "militia")
	_frame(h4.global_position)
	game.cast_hero_skill3(h4, h4.global_position + Vector2(5, 15))
	await _wait(0.9)
	await _snap("res://shots/empire_age_skill_ulti_bach_sa_v1.png")
	_retire(h4)

	print("CAPTURE SKILLS13V DONE")
	get_tree().quit()
