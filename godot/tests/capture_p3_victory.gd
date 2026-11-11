extends Node
## P3 victory capture: the enemy Town Center is destroyed for real
## (full HP burn via combat damage) and the CHIẾN THẮNG glass panel
## ends the match over a view of the player base.
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_p3_victory.tscn

var game = null
var w = null


func _ready() -> void:
	Engine.time_scale = 2.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	w = game.world

	game.cam.focus_on(game.player_tc.position + Vector2(game.player_tc.size) * World.TILE * 0.5)
	game.enemy_tc.take_damage(99999.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_p3_victory_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_p3_victory_v1.png over=", game.match_over)
	get_tree().quit()
