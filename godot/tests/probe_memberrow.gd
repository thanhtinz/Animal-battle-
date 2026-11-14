extends Node
## Probe (cont-empire-age 2026-11-13): measure the alliance
## member row at its REAL container width. The row lives in a
## VBox inside a ScrollContainer inside the content card (pad
## 14) of the right column: viewport 1152 - board margins 32
## - left column 372 - column gap 14 = right column 734;
## minus card padding 28 = 706 for the row. A second pass at
## 692 simulates the vertical scrollbar taking its share.
## Prints every button's rect and how far the LAST control
## (the "Đuổi" kick button for leader/deputy views) sticks
## out past the row's right edge — positive = clipped.

var _scr: CanvasLayer


func _mk_mem(user: String, name: String, role: String, week: int,
		online: bool, seen: int) -> Dictionary:
	return {"user": user, "name": name, "role": role, "level": 45,
		"week": week, "online": online, "seen": seen,
		"avatar": "knight"}


func _buttons(c: Control, out: Array) -> void:
	if c is Button:
		out.append(c)
	for ch in c.get_children():
		if ch is Control:
			_buttons(ch, out)


func _measure(tag: String, row: PanelContainer, width: float) -> void:
	var host := VBoxContainer.new()
	host.position = Vector2(20, 20)
	host.custom_minimum_size = Vector2(width, 0)
	host.size = Vector2(width, 0)
	add_child(host)
	host.add_child(row)
	await get_tree().process_frame
	await get_tree().process_frame
	var rr := row.get_global_rect()
	var btns: Array = []
	_buttons(row, btns)
	var parts: Array = []
	var worst := 0.0
	for b in btns:
		var br: Rect2 = (b as Button).get_global_rect()
		var over := br.end.x - rr.end.x
		worst = maxf(worst, over)
		parts.append("'%s'@x=%.0f..%.0f(w=%.0f,over=%.0f)" % [
			(b as Button).text, br.position.x, br.end.x, br.size.x, over])
	print("PROBE ", tag, " width=", width, " row_w=", rr.size.x,
		" row_min=", row.get_combined_minimum_size().x,
		" worst_over=", worst)
	for p in parts:
		print("PROBE   ", p)
	host.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	Net.account_name = "ProbeLeader"
	_scr = load("res://scripts/alliance_screen.gd").new()
	add_child(_scr)
	await get_tree().process_frame
	var now := int(Time.get_unix_time_from_system())
	# A: leader -> member, short name, online.
	await _measure("A leader>member short online",
		_scr._member_row(_mk_mem("ShotMem", "ShotMem", "member", 0, true, now),
			"leader", "a1"), 706)
	# B: leader -> member, longest name (16), big week, offline.
	await _measure("B leader>member longname week12345 offline",
		_scr._member_row(_mk_mem("NguyenVanTeo1234", "NguyenVanTeo1234",
			"member", 12345, false, now - 3 * 86400), "leader", "a1"), 706)
	# C: leader -> deputy, long name.
	await _measure("C leader>deputy longname",
		_scr._member_row(_mk_mem("NguyenVanTeo1234", "NguyenVanTeo1234",
			"deputy", 12345, true, now), "leader", "a1"), 706)
	# D: leader -> member with the transfer confirm ARMED
	# (button text grows to "Đã chắc? Bấm lại").
	_scr._arm = "transfer:NguyenVanTeo1234"
	_scr._arm_at = Time.get_ticks_msec()
	await _measure("D leader>member armed-transfer longname",
		_scr._member_row(_mk_mem("NguyenVanTeo1234", "NguyenVanTeo1234",
			"member", 12345, true, now), "leader", "a1"), 706)
	_scr._arm = ""
	# E: deputy -> member (kick only), long name.
	await _measure("E deputy>member longname",
		_scr._member_row(_mk_mem("NguyenVanTeo1234", "NguyenVanTeo1234",
			"member", 12345, true, now), "deputy", "a1"), 706)
	# F: same as B but the scroll container shows its bar.
	await _measure("F leader>member longname width692 (scrollbar)",
		_scr._member_row(_mk_mem("NguyenVanTeo1234", "NguyenVanTeo1234",
			"member", 12345, false, now - 3 * 86400), "leader", "a1"), 692)
	print("PROBE DONE")
	get_tree().quit()
