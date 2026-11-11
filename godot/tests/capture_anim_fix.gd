extends Node
## 13o fix-up captures (the first audit run framed the cavalry and
## the beasts wrong — the subjects left the crop):
##   xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> \
##       res://tests/capture_anim_fix.tscn
## - cavalry: the camera FOLLOWS the horse across its run.
## - beasts: wolves/boar are pinned to a clearing and held in
##   their wander-wait (idle frame + 13o breathing) for the take.
## Frames land in the same folders the assembler reads
## (frames/cavalry, frames/beasts), overwriting the bad takes.

const FRAME_DIR := "res://shots/empire_age_anim_audit_v1/frames"
const STEP := 0.12

var game = null


func _ready() -> void:
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "grassland"
	ms.map_choice_done = true
	ms.chosen_layout = "plains"
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	game.fog.set_process(false)
	for i in range(game.fog.state.size()):
		game.fog.state[i] = 2
	game.fog.queue_redraw()
	_reveal()

	var anchor: Vector2i = game.world.player_base + Vector2i(12, 8)
	await _cavalry_take(anchor)
	if not OS.get_cmdline_user_args().has("cavonly"):
		await _beasts_take(anchor)
	print("ANIM FIX CAPTURE DONE")
	get_tree().quit()


func _reveal() -> void:
	for b in game.buildings:
		b.visible = true
	for u in game.units:
		u.visible = true
	for s in game.ships:
		s.visible = true
	for bst in game.world.beasts:
		bst.visible = true


func _save(seg: String, i: int) -> void:
	var dir := ProjectSettings.globalize_path(FRAME_DIR + "/" + seg)
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir + "/f_%03d.png" % i)


func _cavalry_take(_anchor: Vector2i) -> void:
	# Run across the base clearing itself: guaranteed open grass,
	# no forest A* weaving, no map-edge camera clamp.
	var base: Vector2i = game.world.player_base
	var start: Vector2i = game.world.nearest_walkable(base + Vector2i(-5, 5), 6)
	if start.x < 0:
		print("SEGMENT cavalry SKIPPED (no clearing)")
		return
	var cav: Unit = game._make_unit(0, game.world.cell_center(start), "cavalry")
	var dest: Vector2i = game.world.nearest_walkable(base + Vector2i(3, 5), 6)
	if dest.x < 0:
		print("SEGMENT cavalry SKIPPED (no dest)")
		return
	cav.order_move_cell(dest)
	game.cam.zoom = Vector2(2.2, 2.2)
	# One focus on the run's midpoint: per-frame re-focus fights
	# the camera's own input handling and the horse leaves centre;
	# a short crossing framed once stays in view end to end.
	var mid: Vector2 = (cav.global_position
			+ game.world.cell_center(dest)) * 0.5
	game.cam.focus_on(mid)
	await get_tree().process_frame
	var n := 20
	for i in range(n):
		await get_tree().create_timer(STEP).timeout
		_save("cavalry", i)
	print("SEGMENT cavalry frames=", n)


func _beasts_take(_anchor: Vector2i) -> void:
	# Anchor on the first beast itself — guaranteed walkable land.
	if game.world.beasts.is_empty():
		print("SEGMENT beasts SKIPPED (no beasts in world)")
		return
	var spot: Vector2i = game.world.world_to_cell(game.world.beasts[0].global_position)
	spot = game.world.nearest_walkable(spot, 4)
	if spot.x < 0:
		print("SEGMENT beasts SKIPPED (no walkable near beast)")
		return
	var centre: Vector2 = game.world.cell_center(spot)
	var placed: Array = []
	var i := 0
	for bst in game.world.beasts:
		if placed.size() >= 3:
			break
		var c: Vector2i = game.world.nearest_walkable(
				spot + Vector2i(i * 2 - 2, (i % 2) * 2), 3)
		if c.x < 0:
			continue
		bst.global_position = game.world.cell_center(c)
		bst.anchor = bst.global_position
		bst.state = "wander"
		bst.target = null
		placed.append(bst)
		i += 1
	game.cam.zoom = Vector2(1.9, 1.9)
	game.cam.focus_on(centre)
	var n := 22
	for k in range(n):
		# Hold them in the wander-wait: idle frame + breathing,
		# no drifting out of frame between grabs.
		for bst in placed:
			bst._wait = 1.0
			bst.visible = true
		await get_tree().create_timer(STEP).timeout
		_save("beasts", k)
	print("SEGMENT beasts frames=", n, " placed=", placed.size())
