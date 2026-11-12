extends Node
## In-match chat-bubble shot (17d): xvfb-run godot
## res://tests/capture_bubble17d.tscn — two staged heroes in
## an SP match; slot 0's hero carries a "vo_dich" (champion)
## bubble, slot 1's hero a "hang" (rank) bubble, triggered
## through the REAL Main.show path (chat_bubbles.show_bubble,
## the same call _mp_on_chat makes). Fog state is filled
## visible for the staged still (the layer's fog gate reads
## the cell data).

var game = null
var w = null


func _ready() -> void:
	(load("res://scripts/main.gd") as GDScript).map_choice_done = true
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	game.slot_chars[0] = "knight"
	game.slot_chars[1] = "mage"
	var tc_o: Vector2i = game.player_tc.origin_cell
	var front: Vector2 = w.cell_center(tc_o + Vector2i(6, 3))
	var hero: Unit = game._make_unit(0, front, "king")
	hero.state = "idle"
	hero.path.clear()
	var foe: Unit = game._make_unit(1, front + Vector2(190, 10), "king")
	foe.state = "idle"
	foe.path.clear()
	for i in range(6):
		await get_tree().process_frame
	game.set_paused(true)
	# Lift the fog for the still: hide the overlay AND mark
	# every cell visible so the bubble layer's fog gate passes.
	game.fog.visible = false
	game.fog.set_process(false)
	game.fog.state.fill(2)
	for u in game.units:
		u.visible = true
	# The real bubble path (what a chat line triggers).
	game.chat_bubbles.show_bubble(0, "Đánh trận này thôi mọi người!", "vo_dich")
	game.chat_bubbles.show_bubble(1, "Ta tới đây!", "hang")
	game.cam.zoom = Vector2(1.5, 1.5)
	game.cam.focus_on(front + Vector2(95, 20))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_settings17d_bubble_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_settings17d_bubble_v1.png size=", img.get_size())
	get_tree().quit()
