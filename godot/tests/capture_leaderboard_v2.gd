extends Node
## Capture driver for the 17i leaderboard redesign
## (tests/capture_leaderboard_v2.sh): logs in against the
## seeded relay, opens the board via the real home entry
## (game.home_open_leaderboard) and switches it to the
## requested tab before saving.
##   --lb2-mode=ranked|friends|alliance
##   --lb2-account=<user>   (password is the seed "secret1")
##   --lb2-file=<absolute png path>
## Modelled on capture_tour_lb_alliance.gd.

func _ready() -> void:
	var mode := "ranked"
	var acct := "HiepSi"
	var out := "res://shots/empire_age_leaderboard_v2_server_v1.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lb2-mode="):
			mode = a.trim_prefix("--lb2-mode=")
		elif a.begins_with("--lb2-account="):
			acct = a.trim_prefix("--lb2-account=")
		elif a.begins_with("--lb2-file="):
			out = a.trim_prefix("--lb2-file=")
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	Net.connect_to_server(Net.DEFAULT_URL)
	var waited := 0.0
	while not Net.connected and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	if Net.connected:
		Net.login_account(acct, "secret1")
	waited = 0.0
	while Net.account_name == "" and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	# Safety net (the seed sets display names): without one
	# the game parks on the name panel and the board never
	# shows.
	if not Net.has_display_name():
		Net.set_display_name(acct)
		waited = 0.0
		while not Net.has_display_name() and waited < 10.0:
			await get_tree().create_timer(0.5, true).timeout
			waited += 0.5
	await get_tree().create_timer(1.2, true).timeout
	game.home_open_leaderboard()
	await get_tree().create_timer(0.8, true).timeout
	if mode != "ranked" and game.lobby != null:
		game.lobby._set_lb_mode(mode)
	await get_tree().create_timer(1.6, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("MPLOG lb2 shot saved mode=", mode, " size=", img.get_size())
	get_tree().quit()
