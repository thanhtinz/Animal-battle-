extends Node

## 13x max-content capture: the three rebuilt centred modals
## (Người chơi / Thống kê / Cài đặt). Boots a real match for the
## world/HUD, then stages a 4-player 2v2 slot state (very long
## name, one hero on the field, one eliminated, one disconnected,
## real gathered totals) and snaps each modal centred; prints
## each panel's position/size so centring is verifiable.
## Run: godot --path . res://tests/capture_panels13x.tscn (Xvfb)

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
	game.center_on_own_tc()
	# Stage a 4-player 2v2 match's slot state.
	game.mp_mode = true
	game.local_slot = 0
	game.slot_names = ["Tin", "Một Cái Tên Người Chơi Thật Dài Để Kiểm Tra Xuống Hàng",
			"HoangNam", "KhanhLy"]
	game.slot_teams = [0, 0, 1, 1]
	game.slot_chars = ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa"]
	game.slot_eliminated = [false, false, true, false]
	game.slot_inert = [false, false, false, true]
	game.slot_tc_down = [false, false, false, false]
	game.mp_rally = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	game.mp_techs = [{"levels": {}, "active": {}}, {"levels": {}, "active": {}},
			{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	var w0 := {"food": 7350, "wood": 6080, "gold": 5590, "stone": 5220}
	var w1 := {"food": 1750, "wood": 1380, "gold": 350, "stone": 260}
	game.mp_wallets = [w0, w1.duplicate(), w1.duplicate(), w1.duplicate()]
	game.mp_ages = [{"age": 4}, {"age": 3}, {"age": 2}, {"age": 3}]
	# Gathered totals so scores differ per player.
	for r in ["food", "wood", "gold", "stone"]:
		game.credit_owner(0, r, 1200)
		game.credit_owner(1, r, 640)
		game.credit_owner(3, r, 300)
	# Heroes on the field for slots 0 and 1 (portraits full
	# colour); slots 2/3 keep the dimmed "chưa xuất trận" state.
	var anchor: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(6, 6))
	var pos: Vector2 = game.world.cell_center(anchor)
	game._make_unit(0, pos, "king")
	game._make_unit(1, pos + Vector2(96, 40), "king")
	# --- Players modal ---
	game.hud.toggle_tab("players")
	for i in range(6):
		await get_tree().process_frame
	var mp: Dictionary = game.hud._modals["players"]
	print("CAP13X players pos=", (mp.panel as Control).position,
			" size=", (mp.panel as Control).size,
			" rows=", game.hud._players_box.get_child_count())
	await _snap("empire_age_panel_players_v2")
	game.hud.toggle_tab("players")
	# --- Statistics modal ---
	game.hud.toggle_tab("stats")
	for i in range(6):
		await get_tree().process_frame
	var ms: Dictionary = game.hud._modals["stats"]
	print("CAP13X stats pos=", (ms.panel as Control).position,
			" size=", (ms.panel as Control).size,
			" blocks=", game.hud._stats_box.get_child_count())
	await _snap("empire_age_panel_stats_v2")
	game.hud.toggle_tab("stats")
	# --- Settings modal ---
	game.hud.toggle_tab("settings")
	for i in range(6):
		await get_tree().process_frame
	var mg: Dictionary = game.hud._modals["settings"]
	print("CAP13X settings pos=", (mg.panel as Control).position,
			" size=", (mg.panel as Control).size)
	await _snap("empire_age_panel_settings_v2")
	print("CAP13X CAPTURE SAVED")
	get_tree().quit()


func _snap(slug: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % slug)
	print("CAP13X ", slug)
