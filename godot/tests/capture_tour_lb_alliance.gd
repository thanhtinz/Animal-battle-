extends Node
## TOUR capture: Leaderboard "Liên minh" tab against a store
## that really holds an alliance (seeded by
## tests/capture_tour_alliance.sh — Ally2Lead/Ally2Mem in
## "Hội Sông Lam 17b"). Adapted from capture_lb_alliance.gd.
## Needs the relay on Net.DEFAULT_URL still running.

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	Net.connect_to_server(Net.DEFAULT_URL)
	var waited := 0.0
	while not Net.connected and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	if Net.connected:
		Net.login_account("Ally2Lead", "secret1")
	waited = 0.0
	while Net.account_name == "" and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	# The seed accounts carry no display name yet: without one the
	# game parks on the name panel and the leaderboard never shows.
	if not Net.has_display_name():
		Net.set_display_name("Ally2Lead")
		waited = 0.0
		while not Net.has_display_name() and waited < 10.0:
			await get_tree().create_timer(0.5, true).timeout
			waited += 0.5
	await get_tree().create_timer(1.2, true).timeout
	game.home_open_leaderboard()
	await get_tree().create_timer(0.8, true).timeout
	if game.lobby != null:
		game.lobby._set_lb_mode("alliance")
	await get_tree().create_timer(1.2, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_leaderboard_tour_alliance_v1.png")
	print("TOUR LB ALLIANCE CAPTURE SAVED size=", img.get_size())
	get_tree().quit()
