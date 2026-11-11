extends Node
## Custom view capture (13t): the multiplayer lobby's menu IS
## the Custom view — create/join by 5-char code, the two queue
## buttons, and the new "Đánh với máy" entry that replaced bot
## play's old home behind Đấu Thường. Boots the game, logs in
## as the seeded "HiepSi" account directly through Net, opens
## the Custom view via Main's home entry (home_open_rooms) and
## photographs it to res://shots/empire_age_custom_bot_v1.png.
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
		Net.login_account("HiepSi", "secret1")
	waited = 0.0
	while Net.account_name == "" and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	await get_tree().create_timer(1.5, true).timeout
	game.home_open_rooms()
	await get_tree().create_timer(1.0, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_custom_bot_v1.png")
	print("CUSTOM BOT CAPTURE SAVED size=", img.get_size())
	get_tree().quit()
