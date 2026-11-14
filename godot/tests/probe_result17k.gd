extends Node
## Probe (17k, cont-empire-age 2026-11-14): stage an 8-slot
## free-for-all on a bare Main instance — slots 5/6/7 fell in
## that order (elim ticks 100/200/300), slot 7 staged as the
## top SCORER via gathered_totals — and print what the result
## screen builds: Main.result_placements(), the MVP spotlight
## text, every standings row's text, and the banner context
## for two different local slots. Verifies AOV spec §1: the
## standings follow PLACEMENT, the MVP follows SCORE, fallen
## rows carry "Đã bị loại", and the banner names the local
## placement (final even for the first-fallen slot).

var _fails := 0


func _collect(root: Node) -> String:
	var s := ""
	var walk: Array = [root]
	while not walk.is_empty():
		var nd: Node = walk.pop_back()
		if nd is Label:
			s += (nd as Label).text + "|"
		for ch in nd.get_children():
			walk.append(ch)
	return s


func _expect(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PROBE PASS ", name)
	else:
		_fails += 1
		print("PROBE FAIL ", name, " | ", detail)


func _ready() -> void:
	var g = load("res://main.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	g.mp_mode = true
	g.local_slot = 0
	g.slot_teams = [0, 1, 2, 3, 4, 5, 6, 7]
	g.slot_names = ["An", "Bình", "Chi", "Dũng", "Hà", "Giang", "Hải", "Kiên"]
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
		g.mp_ages.append({"age": 1})
	# Deterministic scores: the bare instance's base scores are
	# slot0=35 / slot1=95 / rest 0, so gathered gaps of 200+
	# pin the survivor order to 0,1,2,3,4 while slot 7 — last
	# place by survival — is the runaway top scorer.
	g.gathered_totals[0] = {"food": 10000}
	g.gathered_totals[1] = {"food": 8000}
	g.gathered_totals[2] = {"food": 6000}
	g.gathered_totals[3] = {"food": 4000}
	g.gathered_totals[4] = {"food": 2000}
	g.gathered_totals[7] = {"food": 50000}
	_expect("placements = survival order",
			g.result_placements() == [0, 1, 2, 3, 4, 7, 6, 5],
			"placements=%s" % [g.result_placements()])
	_expect("slot 7 is the top scorer",
			g.match_score_of(7) > g.match_score_of(0),
			"s7=%d s0=%d" % [g.match_score_of(7), g.match_score_of(0)])
	g.hud.show_end_panel("victory", 600.0, "Thắng")
	await get_tree().process_frame
	var mvp_txt := _collect(g.hud._end_mvp)
	_expect("MVP spotlight = top scorer (Kiên), not placement #1",
			mvp_txt.contains("Kiên") and mvp_txt.contains("MVP"), mvp_txt)
	_expect("standings have 8 rows",
			g.hud._end_standings.get_child_count() == 8,
			"rows=%d" % g.hud._end_standings.get_child_count())
	var row0 := _collect(g.hud._end_standings.get_child(0))
	_expect("row 1 = placement 1 (An, #1, no MVP, not eliminated)",
			row0.contains("An") and row0.contains("#1")
			and not row0.contains("MVP") and not row0.contains("Đã bị loại"),
			row0)
	var row5 := _collect(g.hud._end_standings.get_child(5))
	_expect("row 6 = Kiên (#6) with MVP tag + eliminated status",
			row5.contains("Kiên") and row5.contains("#6")
			and row5.contains("MVP") and row5.contains("Đã bị loại"),
			row5)
	var row7 := _collect(g.hud._end_standings.get_child(7))
	_expect("row 8 = first-fallen Giang (#8), eliminated, no MVP",
			row7.contains("Giang") and row7.contains("#8")
			and row7.contains("Đã bị loại") and not row7.contains("MVP"),
			row7)
	_expect("banner context names local placement 1/8",
			g.hud._end_context.text.contains("Hạng 1/8"),
			g.hud._end_context.text)
	g.local_slot = 5
	g.hud.show_end_panel("defeat", 600.0, "Thua")
	await get_tree().process_frame
	_expect("first-fallen local placement is final (Hạng 8/8)",
			g.hud._end_context.text.contains("Hạng 8/8"),
			g.hud._end_context.text)
	g.slot_teams = [0, 0, 1, 1, 2, 2, 3, 3]
	_expect("team match: no placements",
			g.result_placements().is_empty(),
			"placements=%s" % [g.result_placements()])
	print("PROBE DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
