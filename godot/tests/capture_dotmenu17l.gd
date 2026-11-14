extends Node
## Capture (17l verification): the REAL AllianceScreen joined
## view, leader's Thành viên tab, same fixture as the 17j
## member-row capture (longest display names the server
## allows). Two shots: the member list where every row now
## ends in ONE three-dot button, and the same list with the
## row menu OPEN on the plain-member row — the fullest menu a
## leader sees (Chi tiết · Phong Phó · Chuyển quyền · Đuổi
## khỏi liên minh). The menu is opened by emitting the real
## button's pressed signal, so the shot exercises the real
## wiring. Fixture data, real screen code.

func _dots_buttons(c: Node, out: Array) -> void:
	if c is Button and (c as Button).text == String.chr(0xF142):
		out.append(c)
	for ch in c.get_children():
		_dots_buttons(ch, out)


func _ready() -> void:
	var now := int(Time.get_unix_time_from_system())
	Net.account_name = "ProbeLeader"
	Net.alliance_invites = []
	Net.alliance_rows = []
	Net.friends_rows = []
	Net.alliance_mine = {
		"id": "a1", "name": "Hội Sông Lam", "tag": "HKL1",
		"badge_icon": 2, "badge_color": 1, "level": 1,
		"xp_into": 120, "xp_next": 500, "rank": 2,
		"desc": "Chung một chiến tuyến", "my_role": "leader",
		"members_count": 3, "cap": 30, "week": 375,
		"leader_name": "ProbeLeader", "created_at": now - 90000,
		"notice": "", "requests_count": 0, "requests": [],
		"quests": [], "activity": [], "chat": [],
		"members": [
			{"user": "ProbeLeader", "name": "ProbeLeader",
				"role": "leader", "level": 45, "week": 240,
				"online": true, "seen": now, "avatar": "knight"},
			{"user": "NguyenVanTeo1234", "name": "NguyenVanTeo1234",
				"role": "member", "level": 38, "week": 12345,
				"online": true, "seen": now, "avatar": "knight"},
			{"user": "TranThiBichNgoc9", "name": "TranThiBichNgoc9",
				"role": "deputy", "level": 41, "week": 9876,
				"online": false, "seen": now - 3 * 86400,
				"avatar": "knight"},
		],
	}
	var scr = load("res://scripts/alliance_screen.gd").new()
	add_child(scr)
	scr.visible = true
	scr._render()
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_alliance17l_dotmenu_list_v1.png")
	print("CAPTURE list saved")
	# Rows render sorted by week desc: NguyenVanTeo1234 (the
	# plain member, 12345) is the FIRST row, so its three-dot
	# button is the first one in tree order.
	var dots: Array = []
	_dots_buttons(scr, dots)
	print("CAPTURE dots buttons found: ", dots.size())
	if dots.size() > 0:
		(dots[0] as Button).pressed.emit()
		for i in 10:
			await get_tree().process_frame
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png("res://shots/empire_age_alliance17l_dotmenu_open_v1.png")
		print("CAPTURE open saved")
	get_tree().quit()
