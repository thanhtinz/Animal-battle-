extends Node
## Capture (17j verification): the REAL AllianceScreen joined
## view, leader's Thành viên tab, fed with a fixture payload
## whose members carry the longest display names the server
## allows (16 chars) — the worst case for the member-row
## action cluster ("Đuổi" clipped at the card edge before
## 17j). Fixture data, real screen code; output is a
## geometry check, not a gameplay shot.

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
	img.save_png("res://shots/empire_age_alliance17j_memberrow_v1.png")
	print("CAPTURE saved")
	get_tree().quit()
