extends Node

## 13z + 13y-AOV captures:
##  1. empire_age_8p_start_v1 — a REAL 8-slot queue-style match
##     booted locally (Main's MP boot with an 8-player config):
##     eight bases in the eight slot colours on the plains ring.
##  2. empire_age_8p_players_v1 — the Players panel of that
##     match: eight rows, free-for-all wording (no "Đội").
##  3. empire_age_result_aov_v1 — the AOV-style result screen
##     for the same 8-player match, its counters grown through
##     the game's own hooks (credit_owner, staged kills,
##     buildings, stat records) before end_match.
## Run: godot --path . res://tests/capture_8p.tscn (Xvfb)

const NAMES8 := ["Tin", "MinhAnh", "HoangNam", "KhanhLy",
		"TuanAnh", "PhuongThao", "DucHuy", "BaoNgoc"]
const CHARS8 := ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa",
		"kim_hoa", "ngan_ky", "bach_sa", "lam_bao"]


func _snap(slug: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % slug)
	print("CAP8P ", slug)


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	# Boot a real 8-player FFA match through Main's MP path
	# (the same statics Net.begin_match installs).
	Net.my_slot = 0
	Net.ranked = false
	Net.queued_room = true
	Net.pending_cfg = {"seed": 12345, "biome": "grassland", "layout": "plains"}
	var players: Array = []
	for i in range(8):
		players.append({"slot": i, "name": NAMES8[i], "team": i,
				"account": false, "char": CHARS8[i], "skin": ""})
	var ms = load("res://scripts/main.gd")
	ms.mp_config = {"seed": 12345, "biome": "grassland",
			"layout": "plains", "players": players}
	ms.mp_active = true
	ms.map_choice_done = true
	var g = load("res://main.tscn").instantiate()
	add_child(g)
	for i in range(40):
		await get_tree().process_frame
	print("CAP8P slots=", g.slot_count(), " bases=", g.world.base_centres.size(),
			" units=", g.units.size())
	# The MP boot freezes Engine.time_scale until server ticks
	# flow; this staged match has no server, so unfreeze it or
	# the camera, fog and timers never move.
	Engine.time_scale = 1.0
	# Whole-map view: fog lifted for the shot only.
	for i in range(g.fog.state.size()):
		g.fog.state[i] = 2
	g.fog.update_fog()
	g.cam.zoom = Vector2(0.34, 0.34)
	g.cam.focus_on(Vector2(1024, 1024))
	for i in range(10):
		await get_tree().process_frame
	await _snap("empire_age_8p_start_v1")
	# Players panel over the live 8-slot match.
	g.cam.zoom = Vector2(1.0, 1.0)
	g.center_on_own_tc()
	g.hud.toggle_tab("players")
	for i in range(6):
		await get_tree().process_frame
	await _snap("empire_age_8p_players_v1")
	g.hud.toggle_tab("players")
	# ---- Grow an end-of-match state through the real hooks ----
	var tcs := {}
	for b in g.buildings:
		if b.btype == "town_center" and b.complete:
			tcs[b.owner_id] = b
	# Varied economies per slot.
	for s in range(8):
		var f: int = [5200, 3100, 4600, 2400, 3800, 1900, 2900, 1500][s]
		g.credit_owner(s, "food", f)
		g.credit_owner(s, "wood", f / 2)
		g.credit_owner(s, "gold", f / 4)
	# A battle near slot 0's base: slot 0's archers drop units
	# belonging to slots 3, 5 and 6 (kills + losses are credited
	# by the real damage path).
	var anchor: Vector2i = g.world.nearest_walkable(
			g.world.base_centres[0] + Vector2i(6, 6))
	var pos: Vector2 = g.world.cell_center(anchor)
	var atk: Unit = g._make_unit(0, pos + Vector2(-40, 0), "archer")
	for vic_slot in [3, 3, 5, 6, 6, 6]:
		var vic: Unit = g._make_unit(vic_slot, pos + Vector2(40, 0), "militia")
		vic.take_damage(99999.0, atk)
	await get_tree().create_timer(2.0).timeout
	# One razed enemy house (slot 5) credited to slot 0.
	var h5: Building = g._spawn_building("house", 5,
			g.world.nearest_walkable(g.world.base_centres[0] + Vector2i(9, 2)), false)
	h5.add_progress(9999.0)
	h5.take_damage(99999.0, atk)
	await get_tree().create_timer(1.5).timeout
	# Trained counts via real TC queues for a few slots.
	for s in [0, 2, 4]:
		if tcs.has(s):
			g.spawn_unit(tcs[s], "militia")
			g.spawn_unit(tcs[s], "villager")
	# APM: the stat records the result screen reads.
	for s in range(8):
		g._stat_rec(s)["actions"] = [312, 148, 265, 96, 204, 71, 158, 55][s]
	g.match_time = 754.0
	g._sample_stats()
	g.end_match("victory", "Thắng bằng quét sạch (annihilation)")
	for i in range(8):
		await get_tree().process_frame
	print("CAP8P result rows=", g.hud._end_standings.get_child_count(),
			" mvp children=", g.hud._end_mvp.get_child_count())
	await _snap("empire_age_result_aov_v1")
	print("CAP8P CAPTURE SAVED")
	get_tree().quit()
