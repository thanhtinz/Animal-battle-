extends Node
## Right-rail capture (Tín's rail follow-up: the "+" chip is
## gone from the friends column's bottom and the "<" arrow
## lives in that slot; the separate mid-height floating arrow
## is removed): boots the game, logs in as the seeded
## "HiepSi" account through Net, photographs the plain home
## lobby (no panel open) to
## res://shots/empire_age_home_rail_arrow_v1.png.
## Needs a relay on Net.DEFAULT_URL seeded with that account
## (tests/capture_mode_panel_v6.sh runs one).
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
	if game.home != null:
		game.home.refresh()
	await get_tree().create_timer(0.7, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_rail_arrow_v1.png")
	print("RAIL ARROW CAPTURE SAVED size=", img.get_size())
	get_tree().quit()
