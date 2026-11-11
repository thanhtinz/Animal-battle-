extends Node

## 13y captures: the end-of-match result screen (victory +
## defeat), the Players modal staged as a 1v1 VERSUS match (no
## team wording anywhere), and the Settings modal with the
## unified 0..100 sliders. State is staged through the real
## accounting hooks (credit_owner, spawn_unit, kills, research,
## sampling) so the numbers on screen are the game's own.
## Run: godot --path . res://tests/capture_result13y.tscn (Xvfb)


func _boot() -> Node:
	Net.auto = {"mp-name": "Tin"}
	var g = load("res://main.tscn").instantiate()
	add_child(g)
	g.home_quick_match()
	for i in range(30):
		await get_tree().process_frame
	g.enemy_ai.waves_enabled = false
	g.center_on_own_tc()
	return g


func _free(g: Node) -> void:
	remove_child(g)
	g.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _building_of(g: Node, owner: int) -> Building:
	for b in g.buildings:
		if b.owner_id == owner and b.complete and not b.destroyed:
			return b
	return null


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	# ---------------- VICTORY (developed SP match) ----------------
	var g = await _boot()
	var tc0 := _building_of(g, 0)
	var tc1 := _building_of(g, 1)
	for r in ["food", "wood", "gold", "stone"]:
		g.credit_owner(0, r, 900)
		g.credit_owner(1, r, 420)
	g.resources.food = 99999
	g.resources.wood = 99999
	g.resources.gold = 99999
	g.resources.stone = 99999
	var anchor: Vector2i = g.world.nearest_walkable(
			g.player_tc.origin_cell + Vector2i(6, 6))
	var pos: Vector2 = g.world.cell_center(anchor)
	# Sample 1 at t=30 with the starting state.
	g.match_time = 30.0
	g._sample_stats()
	# Grow both economies/armies through the real hooks.
	for i in range(4):
		g.spawn_unit(tc0, "militia")
		g.spawn_unit(tc0, "archer")
	for i in range(2):
		g.spawn_unit(tc1, "militia")
	var house: Building = g._spawn_building("house", 0,
			g.world.nearest_walkable(g.player_tc.origin_cell + Vector2i(-5, 3)), false)
	house.add_progress(9999.0)
	for r in ["food", "wood", "gold", "stone"]:
		g.credit_owner(0, r, 1600)
		g.credit_owner(1, r, 500)
	g.set_team_age(0, 3)
	g.set_team_age(1, 2)
	g.match_time = 95.0
	g._sample_stats()
	# A small battle: two enemy militia fall to the player's.
	var atk: Unit = g._make_unit(0, pos + Vector2(-40, 0), "militia")
	for i in range(2):
		var vic: Unit = g._make_unit(1, pos + Vector2(40 + i * 30, 0), "militia")
		vic.take_damage(99999.0, atk)
	await get_tree().create_timer(2.2).timeout
	# The food line lives at the Storage (Age II+ is already set).
	var store: Building = g._spawn_building("storage", 0,
			g.world.nearest_walkable(g.player_tc.origin_cell + Vector2i(5, -3)), false)
	store.add_progress(9999.0)
	g.start_research("food")
	g._update_techs(9999.0)
	# A realistic burst of counted commands so APM is a real
	# number (order spam is what players actually do).
	g.selection = [atk]
	for i in range(40):
		g.issue_order(pos + Vector2(i * 2, 0))
	g.train_at(tc0, "villager")
	g.match_time = 160.0
	g._sample_stats()
	g.match_time = 213.0
	g.end_match("victory", "Thắng bằng quét sạch (annihilation)")
	for i in range(8):
		await get_tree().process_frame
	print("CAP13Y victory title=", g.hud._end_title.text,
			" rows=", g.hud._end_standings.get_child_count(),
			" blocks=", g.hud._end_breakdown.get_child_count(),
			" samples=", g.stat_series.size(),
			" panel pos=", g.hud._end_panel.position, " size=", g.hud._end_panel.size)
	await _snap("empire_age_result_victory_v1")
	await _free(g)
	# ---------------- DEFEAT ----------------
	g = await _boot()
	for r in ["food", "wood", "gold", "stone"]:
		g.credit_owner(0, r, 350)
		g.credit_owner(1, r, 1500)
	var dtc1 := _building_of(g, 1)
	for i in range(3):
		g.spawn_unit(dtc1, "cavalry")
	g.match_time = 45.0
	g._sample_stats()
	g.match_time = 96.0
	g.end_match("defeat", "Bị quét sạch — không còn Dân và công trình huấn luyện")
	for i in range(8):
		await get_tree().process_frame
	print("CAP13Y defeat title=", g.hud._end_title.text,
			" rows=", g.hud._end_standings.get_child_count())
	await _snap("empire_age_result_defeat_v1")
	# ---------------- PLAYERS staged as 1v1 VERSUS ----------------
	g.hud._end_panel.visible = false
	g.hud._end_dim.visible = false
	g.mp_mode = true
	g.local_slot = 0
	g.slot_names = ["Tin", "HoangNam"]
	g.slot_teams = [0, 1]
	g.slot_chars = ["ngan_ky", "bach_sa"]
	g.slot_eliminated = [false, false]
	g.slot_inert = [false, false]
	g.slot_tc_down = [false, false]
	g.mp_rally = [Vector2.ZERO, Vector2.ZERO]
	g.mp_techs = [{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	g.mp_wallets = [{"food": 800, "wood": 800, "gold": 800, "stone": 800},
			{"food": 800, "wood": 800, "gold": 800, "stone": 800}]
	g.mp_ages = [{"age": 2}, {"age": 3}]
	g.hud.toggle_tab("players")
	for i in range(6):
		await get_tree().process_frame
	var sub := ""
	for ch in g.hud._players_box.get_children():
		if ch is Label:
			sub = (ch as Label).text
			break
	print("CAP13Y players subtitle=", sub)
	await _snap("empire_age_panel_players_v3_versus")
	g.hud.toggle_tab("players")
	# ---------------- SETTINGS (unified sliders) ----------------
	g.hud._set_music_slider.value = 80.0
	g.hud._set_sfx_slider.value = 65.0
	g.hud._set_bright_slider.value = 50.0
	g.hud.toggle_tab("settings")
	for i in range(6):
		await get_tree().process_frame
	print("CAP13Y settings music=", g.hud._set_music_val.text,
			" sfx=", g.hud._set_sfx_val.text,
			" bright=", g.hud._set_bright_val.text,
			" bright_mult=", g.hud._brightness)
	await _snap("empire_age_panel_settings_v3")
	print("CAP13Y CAPTURE SAVED")
	get_tree().quit()


func _snap(slug: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % slug)
	print("CAP13Y ", slug)
