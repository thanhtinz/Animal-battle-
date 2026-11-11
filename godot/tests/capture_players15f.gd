extends Node
## 15f capture staging (functional shot): an SP quick match
## where the local player is an account whose display name is
## "Tin". The players panel must head itself "Tin đấu với Máy"
## and the local player's own card must carry the same name —
## the resolved display name (15d's source), never the old
## "Bạn" placeholder.

var game = null


func _ready() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--players-name-shot="):
			shot = a.trim_prefix("--players-name-shot=")
	Net.account_name = "tinpro"
	Net.auth_profile = {"display_name": "Tin"}
	game = load("res://main.tscn").instantiate()
	add_child(game)
	var guard := 0
	while game.home == null and guard < 1800:
		await get_tree().process_frame
		guard += 1
	await get_tree().create_timer(0.6).timeout
	game.home_quick_match()
	for i in range(6):
		await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	game.hud.toggle_tab("players")
	await get_tree().create_timer(0.9).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	print("MPLOG playersname header should read 'Tin đấu với Máy'")
	if shot != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("MPLOG players name shot saved")
	get_tree().quit()
