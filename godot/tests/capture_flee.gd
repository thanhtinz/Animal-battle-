extends Node
## Flee capture: a lone villager gathering at a tree line is jumped
## by a wolf; the shot catches it mid-flee — exclamation callout up,
## sprinting back toward its Town Center.
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_flee.tscn

var game = null
var w = null


func _ready() -> void:
	Engine.time_scale = 1.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	game.choose_map(game.biome_id, game.layout_id) # close map panel, unpause
	w = game.world

	# Park the other starting villagers far away; keep one gatherer.
	var hero: Unit = null
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			if hero == null:
				hero = u
			else:
				u.global_position = w.cell_center(w.enemy_base + Vector2i(2, 2))
				u.state = "idle"
	# A tree a short run from the Town Center.
	var base: Vector2i = w.player_base
	var tnode: ResourceNode = null
	var bd := 1 << 30
	for n in w.nodes:
		if n.rtype == "wood":
			var d: int = absi(n.cell.x - base.x) + absi(n.cell.y - base.y)
			if d >= 6 and d < bd:
				bd = d
				tnode = n
	var tree: Vector2i = tnode.cell
	# Stage INSIDE the explored clearing so fog hides nothing: the
	# gatherer works a spot ~5 tiles out from the Town Center.
	hero.global_position = w.cell_center(w.nearest_walkable(base + Vector2i(5, 2)))
	hero.order_gather(tnode)
	hero.carry_type = "wood"
	hero.carry_amount = 6
	for i in range(6):
		await get_tree().process_frame

	# The wolf jumps it; the villager bolts for the TC. Shoot EARLY:
	# the wolf is still on its heels and the "!" callout is still up.
	var wolf = game.world._add_beast("wolf", "wolf",
			w.world_to_cell(hero.global_position) + Vector2i(2, 0))
	hero.take_damage(6.0, wolf)
	print("CAPTURE flee state=", hero.state)
	for i in range(5):
		await get_tree().process_frame
	game.cam.focus_on(hero.global_position + Vector2(60, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_flee_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_flee_v1.png state=", hero.state)
	get_tree().quit()
