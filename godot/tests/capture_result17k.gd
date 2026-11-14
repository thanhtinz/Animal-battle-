extends Node
## Capture (17k verification): the REAL result screen of a
## staged 8-slot free-for-all, worst case per the AOV spec's
## mandatory check — full 8 players, longest display names
## (16 chars), 4–5 digit numbers. Slots 5/6/7 fell in that
## order; slot 7 (placement #6) is the top scorer, so the MVP
## spotlight and its row tag must sit on row 6, NOT row 1.
## The local player is slot 5, the FIRST to fall: the banner
## must read Hạng 8/8 and the gold-framed local row sits last,
## marked "Đã bị loại". Fixture state, real screen code.

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	Net.auto = {"mp-name": "Tin"}
	var g = load("res://main.tscn").instantiate()
	add_child(g)
	g.home_quick_match()
	for i in range(30):
		await get_tree().process_frame
	g.mp_mode = true
	g.local_slot = 5
	g.slot_teams = [0, 1, 2, 3, 4, 5, 6, 7]
	g.slot_names = ["NguyenVanTeo1234", "TranThiBichNgoc9", "PhamVanDucAnh777",
			"HoangThiThuHien5", "VuQuocBaoLong888", "DangThiMaiPhuong",
			"BuiVanThanhSonn1", "DoThiNgocTrang22"]
	g.slot_chars = ["knight", "archer", "mage", "paladin",
			"berserker", "dragoon", "assassin", "ranger"]
	g.slot_eliminated = [false, false, false, false, false, true, true, true]
	g.slot_inert = [false, false, false, false, false, false, false, false]
	g.mp_elim_order = [5, 6, 7]
	g.mp_elim_tick = {5: 100, 6: 200, 7: 300}
	g.slot_tc_down = [false, false, false, false, false, false, false, false]
	g.mp_rally = []
	g.mp_techs = []
	g.mp_wallets = []
	g.mp_ages = []
	for i in range(8):
		g.mp_rally.append(Vector2.ZERO)
		g.mp_techs.append({"levels": {}, "active": {}})
		g.mp_wallets.append({"food": 800, "wood": 800, "gold": 800, "stone": 800})
		g.mp_ages.append({"age": 2})
	g.gathered_totals[0] = {"food": 10000, "wood": 5200, "gold": 2600}
	g.gathered_totals[1] = {"food": 8000, "wood": 4100, "gold": 1900}
	g.gathered_totals[2] = {"food": 6000, "wood": 3300, "gold": 1500}
	g.gathered_totals[3] = {"food": 4000, "wood": 2400, "gold": 1100}
	g.gathered_totals[4] = {"food": 2000, "wood": 1300, "gold": 700}
	g.gathered_totals[7] = {"food": 50000, "wood": 21000, "gold": 9800}
	for s in range(8):
		var rec: Dictionary = g._stat_rec(s)
		rec["kills"] = [42, 35, 28, 19, 12, 8, 15, 51][s]
		rec["lost"] = [11, 17, 23, 29, 31, 38, 26, 9][s]
		rec["trained"] = [64, 58, 49, 40, 33, 21, 27, 72][s]
		rec["built"] = [18, 15, 14, 11, 9, 6, 8, 20][s]
		rec["razed"] = [7, 5, 4, 3, 2, 1, 2, 9][s]
		rec["actions"] = [9640, 8320, 7110, 5980, 4230, 2870, 3560, 11240][s]
	g.match_time = 754.0
	g._sample_stats()
	g.hud.show_end_panel("defeat", 754.0,
			"Bị quét sạch — không còn Dân và công trình huấn luyện")
	for i in range(12):
		await get_tree().process_frame
	print("CAP17K rows=", g.hud._end_standings.get_child_count(),
			" context=", g.hud._end_context.text,
			" placements=", g.result_placements())
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_result17k_aov_v1.png")
	# Second shot scrolled to the bottom of the result body:
	# rows 6–8 (MVP row, both remaining eliminated rows, and the
	# gold-framed local row at #8).
	var sc: ScrollContainer = null
	var walk: Array = [g.hud._end_panel]
	while not walk.is_empty() and sc == null:
		var nd: Node = walk.pop_back()
		if nd is ScrollContainer:
			sc = nd
			break
		for ch in nd.get_children():
			walk.append(ch)
	if sc != null:
		await get_tree().process_frame
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value * 0.20)
	for i in range(8):
		await get_tree().process_frame
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("res://shots/empire_age_result17k_aov_v2.png")
	print("CAPTURE saved")
	get_tree().quit()
