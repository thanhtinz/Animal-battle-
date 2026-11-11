extends Node
## Captures the base VFX under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_vfx_base.tscn
## Stages: a completed Blacksmith (chimney smoke runs continuously), a
## House under construction with a villager actively building (dust
## puffs + hammer glints fire from the real build loop), and a villager
## mid-gather at a tree. Just before the shot, one volley goes through
## the real event handlers (gather burst on the tree, build effect on
## the site) so fresh particles are mid-flight in frame.

var game = null
var w = null


func player_villagers() -> Array:
	var out: Array = []
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			out.append(u)
	return out


func wait_until(cond: Callable, timeout_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _ready() -> void:
	Engine.time_scale = 3.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	w = game.world
	var tc_o: Vector2i = game.player_tc.origin_cell # (6, 54)

	# Completed Blacksmith east of the TC (smoke starts immediately).
	var smith = null
	for cand in [tc_o + Vector2i(10, 1), tc_o + Vector2i(9, 0), tc_o + Vector2i(10, 4)]:
		if w.can_place(cand, game.get_build_def("blacksmith").size):
			smith = game._spawn_building("blacksmith", 0, cand, true)
			break
	var vils := player_villagers()
	# Villager 1 gathers FIRST: its walk to the forest takes longer
	# than any construction we stage afterwards (an earlier cut of
	# this scene waited for the gather after starting the build, and
	# the building always completed before the shot).
	var tree: ResourceNode = w.nearest_node_of_type(game.player_tc.global_position, "wood")
	if tree != null and vils.size() >= 2:
		vils[1].order_gather(tree)
	var gathering: bool = await wait_until(
			func() -> bool: return vils.size() >= 2 and vils[1].state == "gather", 60000)
	# Barracks site south of the TC, spawned only now: its 10 s build
	# cannot finish before the shot.
	var site = null
	for cand in [tc_o + Vector2i(5, 4), tc_o + Vector2i(4, 4), tc_o + Vector2i(6, 3)]:
		if w.can_place(cand, game.get_build_def("barracks").size):
			site = game._spawn_building("barracks", 0, cand, false)
			break
	print("CAPTURE staged: smith=", smith != null, " site=", site != null)
	if site != null and vils.size() >= 1:
		vils[0].global_position = w.cell_center(w.nearest_walkable(site.origin_cell + Vector2i(1, -1)))
		vils[0].order_build(site)
	var building: bool = await wait_until(
			func() -> bool: return vils.size() >= 1 and vils[0].state == "build", 30000)
	print("CAPTURE states: building=", building, " gathering=", gathering,
			" site_complete=", site.complete if site != null else "n/a")
	# Frame first (tighter zoom so particles read at still size), then
	# volley so fresh effects are mid-flight in frame.
	game.cam.zoom = Vector2(1.6, 1.6)
	game.cam.focus_on(Vector2(520, 1790))
	await get_tree().process_frame
	if tree != null:
		game.on_node_gathered(tree)
		game.on_node_gathered(tree)
	# Same handler on the stone cluster mid-frame: grey sparks read
	# clearly against grass where the tree's green flecks blend in.
	var rock: ResourceNode = w.nearest_node_of_type(Vector2(470, 1760), "stone")
	if rock != null:
		game.on_node_gathered(rock)
		game.on_node_gathered(rock)
	if site != null and vils.size() >= 1:
		game.on_build_effect(site, vils[0])
		game.on_build_effect(site, vils[0])
		game.on_build_effect(site, vils[0])
	print("CAPTURE base live effects at shot: ", game.vfx.live_count())
	await get_tree().create_timer(0.08).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_vfx_base.png")
	print("CAPTURE SAVED res://shots/empire_age_vfx_base.png size=", img.get_size())
	get_tree().quit()
