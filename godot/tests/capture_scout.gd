extends Node
## Early-match capture for the match-start flow doc: a fresh game
## must show 1 Town Center + 3 villagers + 1 scout cavalry.
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_scout.tscn


func _ready() -> void:
	# Skip the entry flow (see capture_panels.gd for why).
	Net.auto = {"mp-name": "CaptureScout"}
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	var guard := 0
	while game.player_tc == null and guard < 1800:
		await get_tree().process_frame
		guard += 1
	# Boot lands on the home lobby; enter the SP match.
	game.home_quick_match()
	for i in range(6):
		await get_tree().process_frame
	# Stage the photo: line the four starting units up in the open
	# south of the TC (at spawn they stand hidden behind its art).
	var tc_c: Vector2 = game.player_tc.position \
			+ Vector2(game.player_tc.size) * World.TILE * 0.5
	var row := 0
	for u in game.units:
		if u.team == 0:
			u.global_position = tc_c + Vector2(-72 + row * 48, 118)
			row += 1
	await get_tree().process_frame
	var focus: Vector2 = game.player_tc.position \
			+ Vector2(game.player_tc.size) * World.TILE * 0.5
	game.cam.focus_on(focus)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_scout_start_v1.png")
	print("CAPTURE SAVED scout size=", img.get_size())
	get_tree().quit()
