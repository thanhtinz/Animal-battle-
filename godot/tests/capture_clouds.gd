extends Node
## Capture: visible clouds (Tín's CraftPix pack) drifting over the
## grassland with their shadows on the ground.
##   godot --path . res://tests/capture_clouds.tscn
## Saves res://shots/empire_age_clouds_v1.png.

func _ready() -> void:
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "grassland"
	ms.chosen_layout = "plains"
	ms.map_choice_done = true
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	# Lift fog for the verification frame.
	game.fog.set_process(false)
	for i in range(game.fog.state.size()):
		game.fog.state[i] = 2
	game.fog.queue_redraw()
	for u in game.units:
		u.visible = true
	for b in game.buildings:
		b.visible = true
	# Stage three clouds across the frame above the player base.
	var focus: Vector2 = game.player_tc.position + Vector2(90, 130)
	var spots := [Vector2(-400, -230), Vector2(330, -190), Vector2(-90, -360)]
	for i in range(mini(3, game.world.clouds.size())):
		var pair: Dictionary = game.world.clouds[i]
		var cs: Sprite2D = pair["cloud"]
		cs.position = focus + spots[i]
		pair["shadow"].position = cs.position + World.CLOUD_SHADOW_OFFSET
	game.cam.zoom = Vector2.ONE
	game.cam.focus_on(focus)
	game.set_paused(true)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_clouds_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_clouds_v1.png size=", img.get_size())
	get_tree().quit()
