extends Node
## Captures the three 13s action panels under Xvfb:
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_panels.tscn
## Stages an Age-IV town (Blacksmith / Barracks / camps / Market /
## Castle placed instantly), a mid-progress research, a Barracks
## queue of 3 with the front item mid-training, then shoots the
## Công nghệ, Huấn luyện and Xây dựng panels in turn.

var game = null


func _place(bt: String) -> Building:
	var bsize: Vector2i = game.get_build_def(bt).size
	var cell := Vector2i(-1, -1)
	for r in range(0, 18):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
				if game.world.can_place(cand, bsize):
					cell = cand
					break
			if cell.x >= 0:
				break
		if cell.x >= 0:
			break
	if cell.x < 0:
		return null
	game.enter_placement(bt)
	if not game.confirm_placement(cell):
		return null
	for b in game.buildings:
		if b.btype == bt and b.team == 0 and not b.complete:
			b.progress = 1.0
			b.complete = true
			if b.art_sprite != null:
				b.art_sprite.visible = true
			game.on_building_complete(b)
			return b
	return null


func _snap(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("CAPTURE SAVED ", path, " size=", img.get_size())


func _ready() -> void:
	# Skip the entry flow: a non-entry auto arg makes Main boot
	# straight into the SP match (the headless-test path). Net's
	# own auto driver stays disarmed (its phase is only set when
	# the args are parsed in Net._ready).
	Net.auto = {"mp-name": "CapturePanels"}
	game = load("res://main.tscn").instantiate()
	add_child(game)
	# _boot_build spans several frames; wait for the match setup.
	var guard := 0
	while (game.enemy_ai == null or game.player_tc == null) and guard < 1800:
		await get_tree().process_frame
		guard += 1
	# Boot lands on the home lobby; enter the SP match (the
	# lobby's own Đấu Thường path).
	game.home_quick_match()
	for i in range(6):
		await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = true
	game.resources.food = 5000
	game.resources.wood = 5000
	game.resources.gold = 5000
	game.resources.stone = 5000
	game.set_team_age(0, 4)

	var barr: Building = null
	for bt in ["blacksmith", "barracks", "lumber_camp", "mining_camp",
			"farm", "market", "castle", "storage", "house", "house"]:
		var b := _place(bt)
		if bt == "barracks":
			barr = b
		print("CAPTURE placed ", bt, " -> ", b != null)

	# Tech state: two lines partly researched + one mid-research.
	game.tech_levels["melee"] = 2
	game.tech_levels["inf_armor"] = 1
	game.tech_levels["wood"] = 1
	game.tech_levels["wheel"] = 1
	game.start_research("bow")
	if game.tech_active.has("barracks"):
		var rec: Dictionary = game.tech_active["barracks"]
		rec["timer"] = float(rec["duration"]) * 0.45

	# Frame the town.
	var focus: Vector2 = game.player_tc.position \
			+ Vector2(game.player_tc.size) * World.TILE * 0.5 + Vector2(60, 40)
	game.cam.zoom = Vector2(1.15, 1.15)
	game.cam.focus_on(focus)
	await get_tree().process_frame

	# 1) Technology panel.
	game.hud.toggle_tab("tech")
	await _snap("res://shots/empire_age_panel_tech_v1.png")

	# 2) Training panel: select the Barracks (auto-opens), queue 3.
	if barr != null:
		game.train_at(barr, "militia")
		game.train_at(barr, "archer")
		game.train_at(barr, "cavalry")
		barr.train_timer = barr._train_time() * 0.45
		game.selected_building = barr
		await get_tree().process_frame
		await get_tree().process_frame
	await _snap("res://shots/empire_age_panel_train_v1.png")

	# 3) Build panel: no stone left, so stone buildings show why.
	game.selected_building = null
	game.resources.stone = 0
	game.hud.toggle_tab("build")
	await _snap("res://shots/empire_age_panel_build_v1.png")

	get_tree().quit()
