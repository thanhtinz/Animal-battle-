extends Node
## Offline (BAD band) home capture for the ping-meter
## correction: boots the game with NO server/account, so
## Net never connects — the ping glyph must sit in band 0
## (red base dot at the fan's base, grey arcs, "—" text):
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1280x720 res://tests/capture_home_ping_bad.tscn

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(3.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_ping_v2_bad.png")
	print("CAPTURE SAVED res://shots/empire_age_home_ping_v2_bad.png size=", img.get_size())
	get_tree().quit()
