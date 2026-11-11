extends Node
## Leaderboard FULL-SCREEN capture (13m follow-up: the board
## must cover the viewport edge-to-edge, no home art margin):
## boots the game, logs in as the seeded "HiepSi" account
## through Net, opens the leaderboard from Home on the default
## Toàn server tab (rows + sticky "Hạng của tôi" footer) and
## photographs it to res://shots/empire_age_leaderboard_full.png.
## Needs a relay on Net.DEFAULT_URL seeded with that account
## (tests/capture_fullscreen.sh runs one).
##
## Every timer passes process_always=true: Main pauses the
## tree while the home screen is up.

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
	await get_tree().create_timer(1.2, true).timeout
	game.home_open_leaderboard()
	await get_tree().create_timer(1.5, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_leaderboard_full.png")
	print("LB FULL CAPTURE SAVED size=", img.get_size())
	get_tree().quit()
