extends Node

## 13u max-content capture: the Players panel in a 4-player
## match setup (2v2). Boots a real match for the world/HUD, then
## stages the match's slot presentation state (names, teams,
## characters, one eliminated, one disconnected) and opens the
## panel — the shot renders the panel's real MP branch.
## Run: godot --path . res://tests/capture_players4.tscn (Xvfb)

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
	game.slot_names = ["Tin", "MinhAnh", "HoangNam", "KhanhLy"]
	game.slot_teams = [0, 0, 1, 1]
	game.slot_chars = ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa"]
	game.slot_eliminated = [false, false, true, false]
	game.slot_inert = [false, false, false, true]
	game.slot_tc_down = [false, false, false, false]
	game.mp_rally = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	game.mp_techs = [{"levels": {}, "active": {}}, {"levels": {}, "active": {}},
			{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	var w0 := {"food": 500, "wood": 400, "gold": 200, "stone": 150}
	game.mp_wallets = [w0.duplicate(), w0.duplicate(), w0.duplicate(), w0.duplicate()]
	game.mp_ages = [{"age": 4}, {"age": 3}, {"age": 2}, {"age": 3}]
	game.hud.toggle_tab("players")
	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_panel_players_v1.png")
	print("CAP13U players4")
	get_tree().quit()
