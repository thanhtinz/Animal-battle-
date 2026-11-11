extends Node
## Mode-choice panel capture v4 (13t: four entries — Đấu Thường
## / Đấu Hạng badges + Custom / Minigame buttons): boots the
## game, logs in as the seeded "HiepSi" account directly through
## Net, opens the BẮT ĐẦU mode-choice panel on the home screen
## and photographs it to
## res://shots/empire_age_home_mode_panel_v4.png.
## Needs a relay on Net.DEFAULT_URL seeded with that account
## (tests/capture_13t.sh runs one).
##
## Every timer passes process_always=true: once the home
## screen opens, Main pauses the tree, and a plain
## SceneTreeTimer never fires again.

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	Net.connect_to_server(Net.DEFAULT_URL)
	var waited := 0.0
	while not Net.connected and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	if Net.connected:
		# The seeded account already exists, so login (register
		# would be rejected as a duplicate).
		Net.login_account("HiepSi", "secret1")
	waited = 0.0
	while Net.account_name == "" and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	await get_tree().create_timer(1.5, true).timeout
	if game.home != null:
		game.home.refresh()
		game.home._open_mode_panel()
	await get_tree().create_timer(0.7, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_mode_panel_v4.png")
	print("MODE PANEL V4 CAPTURE SAVED size=", img.get_size())
	get_tree().quit()
