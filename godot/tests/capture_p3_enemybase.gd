extends Node
## P3 enemy-base capture: the blue stronghold (Town Center, Barracks,
## Houses, Watch Tower in deep-blue art), revealed by a player scout
## parked at its edge so the Fog of War lifts exactly there.
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_p3_enemybase.tscn

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

	# Player scouts ring the enemy stronghold so the fog lifts over
	# the whole base (TC + Barracks + Houses + Tower).
	var player_vils: Array = []
	for u in game.units:
		if u.team == 0:
			player_vils.append(u)
	var ring := [Vector2i(-3, 1), Vector2i(5, 1), Vector2i(1, 6), Vector2i(1, -3)]
	for i in range(mini(ring.size(), player_vils.size())):
		var sc: Unit = player_vils[i]
		sc.global_position = w.cell_center(w.nearest_walkable(game.enemy_tc.origin_cell + ring[i]))
		sc.state = "idle"
		sc.path.clear()
	# One extra fresh scout for the fourth side if villagers ran out.
	while player_vils.size() < ring.size():
		var extra: Unit = game._make_unit(0, w.cell_center(w.nearest_walkable(
				game.enemy_tc.origin_cell + ring[player_vils.size()])), "villager")
		player_vils.append(extra)
	game.fog.update_fog()
	await get_tree().process_frame
	await get_tree().process_frame

	var focus: Vector2 = game.enemy_tc.position + Vector2(game.enemy_tc.size) * World.TILE * 0.5
	game.cam.zoom = Vector2(1.2, 1.2)
	game.cam.focus_on(focus + Vector2(10, 50))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_p3_enemybase_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_p3_enemybase_v1.png")
	get_tree().quit()
