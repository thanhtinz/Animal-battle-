extends Node
## 15d capture staging (functional shot): an SP quick match
## where the local player is an account whose display name is
## "Tin". Two heroes stand by the player base — the local hero's
## overhead label must read "Tin" (the owner's rule: the name
## over a hero's head IS the player name, never the old "Bạn"
## placeholder) and the bot hero's "Máy", matching the names
## the players panel shows for the same owners.

var game = null


func _ready() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero-name-shot="):
			shot = a.trim_prefix("--hero-name-shot=")
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
	for bst in game.world.beasts:
		bst.dormant = true
	if game.world.sky_layer != null:
		game.world.sky_layer.visible = false
	var anchor: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(7, 7))
	var base: Vector2 = game.world.cell_center(anchor)
	game.slot_chars[0] = "ngan_ky"
	game.slot_chars[1] = "kim_hoa"
	var h1 = game._make_unit(0, base, "king")
	var h2 = game._make_unit(1, base + Vector2(170, 26), "king")
	print("MPLOG heroname slot0=", game.hero_display_name(0),
			" slot1=", game.hero_display_name(1),
			" heroes=", h1 != null, "/", h2 != null)
	game.cam.zoom = Vector2(1.4, 1.4)
	game.cam.focus_on(base + Vector2(85, 10))
	await get_tree().create_timer(0.9).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if shot != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("MPLOG heroname shot saved")
	get_tree().quit()
