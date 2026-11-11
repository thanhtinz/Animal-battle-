extends Node
## Guest-state home capture for the name+Lv chip follow-up:
## boots the game with NO account, lets the home settle in
## its guest state (chip lines read "Khách" / "Chưa đăng
## nhập", top-right icons frameless) and photographs it:
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1280x720 res://tests/capture_home_guest_namelv.tscn

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(3.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_namelv_v1_guest.png")
	print("CAPTURE SAVED res://shots/empire_age_home_namelv_v1_guest.png size=", img.get_size())
	get_tree().quit()
