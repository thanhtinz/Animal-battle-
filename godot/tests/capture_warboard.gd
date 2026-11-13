extends Node
## War board capture (2026-11-12): boots the game with NO
## account (the bracket board is public — guests may view
## it per DAI-CHIEN-LIEN-MINH-SPEC), opens the board via
## Main.open_war_board_shot and photographs it:
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1152x648 res://tests/capture_warboard.tscn

func _ready() -> void:
	print("CAPTURE boot start")
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	print("CAPTURE main added")
	await get_tree().create_timer(14.0).timeout
	# The login screen rides layer 90 — above every page —
	# until the entry flow dismisses it. Take the guest
	# door exactly like a player would, then open the
	# board from the home lobby.
	print("CAPTURE entering as guest")
	game._on_entry_guest()
	await get_tree().create_timer(2.0).timeout
	print("CAPTURE opening board")
	game.open_war_board_shot()
	await get_tree().create_timer(2.5).timeout
	# The headless viewport texture can lag the tree state
	# under CPU contention: pump real frames + force a draw
	# before reading the texture back.
	for i in range(8):
		RenderingServer.force_draw(true)
		await get_tree().process_frame
	print("CAPTURE board visible=", game.war_board_screen.visible)
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_warboard_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_warboard_v1.png size=", img.get_size())
	get_tree().quit()
