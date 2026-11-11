extends Node
## Leaderboard "Liên minh" tab capture: boots the game, logs
## in as the seeded "HiepSi" account through Net, opens the
## leaderboard from Home, switches it to the Liên minh tab
## (an honest empty state — no alliance system exists yet)
## and photographs it to res://shots/empire_age_leaderboard_v5.png.
## Needs a relay on Net.DEFAULT_URL seeded with that account
## (tests/capture_v7.sh runs one).
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
	await get_tree().create_timer(0.8, true).timeout
	if game.lobby != null:
		game.lobby._set_lb_mode("alliance")
	await get_tree().create_timer(0.8, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_leaderboard_v5.png")
	print("LB ALLIANCE CAPTURE SAVED size=", img.get_size())
	get_tree().quit()
