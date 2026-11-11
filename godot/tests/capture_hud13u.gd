extends Node

## 13u capture driver: boots a single-player match staged like
## the panel captures (Age IV town, research lines at several
## states, gathered totals) and snaps the reworked HUD: FA icons
## + avatar/name top-left, horizontal build/train panels, tech
## tree, chat, players, settings and the statistics panel.
## Run: godot --path . res://tests/capture_hud13u.tscn (Xvfb)

var game = null


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	Net.auto = {"mp-name": "Tin"}
	game = load("res://main.tscn").instantiate()
	add_child(game)
	game.home_quick_match()
	for i in range(30):
		await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = true
	game.resources.food = 5000
	game.resources.wood = 5000
	game.resources.gold = 5000
	game.resources.stone = 5000
	game.set_team_age(0, 4)
	# Gathered totals so the statistics panel shows real numbers.
	game.credit_owner(0, "food", 2450)
	game.credit_owner(0, "wood", 1980)
	game.credit_owner(0, "gold", 640)
	game.credit_owner(0, "stone", 420)
	game.credit_owner(1, "food", 1710)
	game.credit_owner(1, "wood", 1230)
	game.credit_owner(1, "gold", 310)
	game.credit_owner(1, "stone", 260)
	# Research buildings, placed instantly (same pattern as the
	# panel capture driver).
	var placed := {}
	for bt in ["barracks", "blacksmith", "lumber_camp", "storage", "market", "castle"]:
		var b = _place(bt)
		if b != null:
			placed[bt] = b
	# Tech at several tree states: completed lines (food/wood),
	# a mid line (melee 1/3), one actively researching (bow).
	game.tech_levels["food"] = 3
	game.tech_levels["wood"] = 2
	game.tech_levels["melee"] = 1
	if game.start_research("bow") and game.tech_active.has("barracks"):
		var rec: Dictionary = game.tech_active["barracks"]
		rec["timer"] = float(rec.get("duration", 30.0)) * 0.4
	game.center_on_own_tc()
	# 1) Plain HUD: FA icons + avatar/name top-left.
	await _snap("empire_age_hud_icons_v1")
	# 2) Build panel on its fullest tab (Kinh tế, 7 cards).
	game.hud.toggle_tab("build")
	for i in range(4):
		await get_tree().process_frame
	await _snap("empire_age_panel_build_h_v1")
	game.hud.toggle_tab("build") # close
	# 3) Training panel bound to the Barracks (horizontal row).
	if placed.has("barracks"):
		game.selected_building = placed["barracks"]
	for i in range(4):
		await get_tree().process_frame
	await _snap("empire_age_panel_train_h_v1")
	# 4) Tech tree with completed/researching nodes + detail.
	# The Town Center group's age cards fill the first screen,
	# so scroll the tree down to the Barracks chains.
	game.hud.toggle_tab("tech")
	game.hud._select_tech_node("bow", 0)
	for i in range(4):
		await get_tree().process_frame
	var tsc = game.hud._pages["tech"].get_child(1)
	if tsc is ScrollContainer:
		tsc.scroll_vertical = 620
	for i in range(3):
		await get_tree().process_frame
	await _snap("empire_age_panel_techtree_v1")
	game.hud.toggle_tab("tech") # close
	# 5) Chat panel (SP honest state).
	game.hud.toggle_chat()
	for i in range(3):
		await get_tree().process_frame
	await _snap("empire_age_panel_chat_v1")
	game.hud.toggle_chat()
	# (Players panel: separate driver — capture_players4 stages
	# a 4-player match setup for the max-content shot.)
	# 7) Settings panel.
	game.hud.toggle_tab("settings")
	for i in range(3):
		await get_tree().process_frame
	await _snap("empire_age_panel_settings_v1")
	game.hud.toggle_tab("settings")
	# 8) Statistics panel (resource-bar entry).
	game.hud.toggle_tab("stats")
	for i in range(4):
		await get_tree().process_frame
	await _snap("empire_age_panel_stats_v1")
	get_tree().quit()


func _place(btype: String):
	var bsize: Vector2i = game.get_build_def(btype).size
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
	game.enter_placement(btype)
	if not game.confirm_placement(cell):
		return null
	for b in game.buildings:
		if b.btype == btype and b.team == 0 and not b.complete:
			b.progress = 1.0
			b.complete = true
			if b.art_sprite != null:
				b.art_sprite.visible = true
			game.on_building_complete(b)
			return b
	return null


func _snap(slug: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % slug)
	print("CAP13U ", slug)
