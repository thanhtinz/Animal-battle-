extends Node
## Probe (17l): the member-row three-dot menu, exercised at
## the UI level on the REAL AllianceScreen. Asserts:
##  - the entry list for every viewer/target combination
##    matches the gating the old per-row buttons had;
##  - kick is a two-tap confirm: the first tap only ARMS
##    (screen._arm == "kick:<user>", no kick fired), and the
##    reopened menu shows "Đã chắc? Bấm lại";
##  - the leader's own row and a plain member's view hold
##    Chi tiết only.
## Prints PASS/FAIL lines; quits with the verdict.

var _scr: CanvasLayer
var _fails := 0


func _mk_mem(user: String, role: String) -> Dictionary:
	return {"user": user, "name": user, "role": role, "level": 10,
		"week": 5, "online": true, "seen": 0, "avatar": "knight"}


func _check(tag: String, ok: bool, extra := "") -> void:
	if ok:
		print("PASS ", tag)
	else:
		_fails += 1
		print("FAIL ", tag, " ", extra)


## Ordered walk collecting each menu item's TEXT label (the
## FA glyph label beside it is a single char — skipped).
func _collect_labels(n: Node, out: Array) -> void:
	if n is Button:
		for ch in n.get_children():
			if ch is HBoxContainer:
				for g in ch.get_children():
					if g is Label and (g as Label).text.length() > 1:
						out.append((g as Label).text)
	for ch in n.get_children():
		_collect_labels(ch, out)


func _menu_labels() -> Array:
	var out: Array = []
	if _scr.get("_menu_root") != null:
		_collect_labels(_scr.get("_menu_root"), out)
	return out


func _find_btn(n: Node, text_part: String) -> Button:
	if n is Button:
		for ch in n.get_children():
			if ch is HBoxContainer:
				for g in ch.get_children():
					if g is Label and (g as Label).text.find(text_part) >= 0:
						return n as Button
	for ch in n.get_children():
		var hit := _find_btn(ch, text_part)
		if hit != null:
			return hit
	return null


func _menu_btn_with(text_part: String) -> Button:
	if _scr.get("_menu_root") == null:
		return null
	return _find_btn(_scr.get("_menu_root"), text_part)


func _open(mem: Dictionary, my_role: String) -> Array:
	var anchor := Button.new()
	add_child(anchor)
	_scr.call("_open_member_menu", anchor, mem,
		my_role, "a1", String(mem.get("user", "")) == Net.account_name)
	var labels := _menu_labels()
	_scr.call("_close_row_menu")
	anchor.queue_free()
	return labels


func _ready() -> void:
	Net.account_name = "ProbeLeader"
	Net.alliance_invites = []
	Net.alliance_rows = []
	Net.friends_rows = []
	Net.alliance_mine = {}
	_scr = load("res://scripts/alliance_screen.gd").new()
	add_child(_scr)
	await get_tree().process_frame

	var member := _mk_mem("MemA", "member")
	var deputy := _mk_mem("DepA", "deputy")
	var leader_self := _mk_mem("ProbeLeader", "leader")

	_check("leader>member entries",
		_open(member, "leader") == ["Chi tiết", "Phong Phó", "Chuyển quyền", "Đuổi khỏi liên minh"],
		str(_open(member, "leader")))
	_check("leader>deputy entries",
		_open(deputy, "leader") == ["Chi tiết", "Hạ Phó", "Chuyển quyền", "Đuổi khỏi liên minh"],
		str(_open(deputy, "leader")))
	_check("leader>self entries",
		_open(leader_self, "leader") == ["Chi tiết"],
		str(_open(leader_self, "leader")))
	_check("deputy>member entries",
		_open(member, "deputy") == ["Chi tiết", "Đuổi khỏi liên minh"],
		str(_open(member, "deputy")))
	_check("deputy>deputy entries",
		_open(deputy, "deputy") == ["Chi tiết"],
		str(_open(deputy, "deputy")))
	_check("member>member entries",
		_open(member, "member") == ["Chi tiết"],
		str(_open(member, "member")))

	# Kick two-tap: first tap arms only, reopened menu shows
	# the confirm label, and the arm key names the target.
	var anchor := Button.new()
	add_child(anchor)
	_scr.call("_open_member_menu", anchor, member, "leader", "a1", false)
	var kick_btn := _menu_btn_with("Đuổi khỏi liên minh")
	_check("kick entry present", kick_btn != null)
	if kick_btn != null:
		kick_btn.pressed.emit()
		_check("kick first tap arms only",
			String(_scr.get("_arm")) == "kick:MemA",
			"arm=" + String(_scr.get("_arm")))
		_check("menu closed after tap", _scr.get("_menu_root") == null)
		_scr.call("_open_member_menu", anchor, member, "leader", "a1", false)
		_check("reopened menu shows confirm label",
			_menu_labels().has("Đã chắc? Bấm lại"),
			str(_menu_labels()))
		_scr.call("_close_row_menu")
	anchor.queue_free()

	print("PROBE DOTMENU ", "ALL PASS" if _fails == 0 else "FAILURES=%d" % _fails)
	get_tree().quit()
