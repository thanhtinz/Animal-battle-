extends Node
## Guest-state home-lobby capture for the avatar-only chip +
## diamond-pip rank pill (13i follow-up): boots the game with
## NO account (no Net auto-driver args), lets the home screen
## settle in its guest state (avatar alone top-left; grey
## emblem + "Chưa xếp hạng" + all-empty diamond pips on the
## floating rank pill) and photographs it under Xvfb:
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1280x720 res://tests/capture_home_guest_v8.tscn

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(3.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_lobby_v8_guest.png")
	print("CAPTURE SAVED res://shots/empire_age_home_lobby_v8_guest.png size=", img.get_size())
	get_tree().quit()
