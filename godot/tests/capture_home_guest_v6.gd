extends Node
## Guest-state home-lobby capture for the unified bottom band
## (13i follow-up): boots the game with NO account (no Net
## auto-driver args), lets the home screen settle in its guest
## state (grey shield + "Chưa xếp hạng" + empty stars + the
## daily-line invitation) and photographs it under Xvfb:
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1280x720 res://tests/capture_home_guest_v6.tscn

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(3.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_lobby_v6_guest.png")
	print("CAPTURE SAVED res://shots/empire_age_home_lobby_v6_guest.png size=", img.get_size())
	get_tree().quit()
