extends Node
## P3 combat capture: a live skirmish near the player base — player
## Militia + Archer against enemy (blue) Militia + Archer, orders
## issued for real, shot taken mid-fight with arrows in flight, hit
## sparks flying and HP bars up.
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_p3_combat.tscn

var game = null
var w = null


func _ready() -> void:
	Engine.time_scale = 1.6
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	w = game.world

	# Arena: a genuinely empty 7x7 patch near the player Town Center
	# (no trees/nodes/decor inside), so nobody hides behind a tree.
	var arena := Vector2i(-1, -1)
	for dy in range(-14, 4):
		for dx in range(4, 18):
			var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
			var clear := true
			for yy in range(cand.y, cand.y + 7):
				for xx in range(cand.x, cand.x + 7):
					if w.is_solid(Vector2i(xx, yy)):
						clear = false
			if clear:
				arena = cand + Vector2i(3, 3)
				break
		if arena.x >= 0:
			break
	if arena.x < 0:
		arena = w.nearest_walkable(game.player_tc.origin_cell + Vector2i(10, -6))
	var pm: Unit = game._make_unit(0, w.cell_center(arena), "militia")
	var pa: Unit = game._make_unit(0, w.cell_center(w.nearest_walkable(arena + Vector2i(-2, 2))), "archer")
	var em: Unit = game._make_unit(1, w.cell_center(w.nearest_walkable(arena + Vector2i(3, 0))), "militia")
	var ea: Unit = game._make_unit(1, w.cell_center(w.nearest_walkable(arena + Vector2i(5, 2))), "archer")
	# Pre-damage everyone a little so HP bars read in the still.
	for u in [pm, pa, em, ea]:
		u.hp = u.max_hp * 0.72
	pm.order_attack(em)
	pa.order_attack(ea)
	em.order_attack(pm)
	ea.order_attack(pa)

	game.cam.zoom = Vector2(1.9, 1.9)
	game.cam.focus_on(w.cell_center(arena) + Vector2(40, 0))
	# Let the fight develop; grab the frame the moment arrows are
	# actually in the air (or after 4.5 s at the latest).
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 4500:
		await get_tree().process_frame
		if Time.get_ticks_msec() - start > 1100 and game.projectiles.size() > 0:
			break
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_p3_combat_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_p3_combat_v1.png proj=", game.projectiles.size())
	get_tree().quit()
