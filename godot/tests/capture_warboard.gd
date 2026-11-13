extends Node
## War board capture (2026-11-12): boots the game with NO
## account (the bracket board is public — guests may view
## it per DAI-CHIEN-LIEN-MINH-SPEC), opens the board via
## Main.home_open_war_board and photographs it:
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1152x648 res://tests/capture_warboard.tscn

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(5.0).timeout
	game.home_open_war_board()
	await get_tree().create_timer(2.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_warboard_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_warboard_v1.png size=", img.get_size())
	get_tree().quit()
