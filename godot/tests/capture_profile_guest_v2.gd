extends Node
## Guest-state profile capture, full-screen follow-up (13l
## follow-up): same as capture_profile_guest.gd but writes
## the v2 filename — boots with NO account, opens the
## profile screen (guest variant) and photographs it:
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1280x720 res://tests/capture_profile_guest_v2.tscn

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(1.5).timeout
	game.open_profile_shot()
	await get_tree().create_timer(1.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_profile_guest_v2_full.png")
	print("CAPTURE SAVED res://shots/empire_age_profile_guest_v2_full.png size=", img.get_size())
	get_tree().quit()
