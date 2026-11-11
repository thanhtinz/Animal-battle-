extends Node

## 13w capture driver: boots a single-player match, opens the
## rebuilt chat panel (centred modal), stages an MP-style full
## conversation (4 players, team scope, same-sender batching,
## very long names and 200-char messages for max-content wrap),
## snaps it centred, then drags it by its header with real input
## events and snaps it again in its dragged position.
## Run: godot --path . res://tests/capture_chat13w.tscn (Xvfb)

var game = null


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	Net.auto = {"mp-name": "Tin"}
	game = load("res://main.tscn").instantiate()
	add_child(game)
	game.home_quick_match()
	for i in range(30):
		await get_tree().process_frame
	var hud = game.hud
	hud.toggle_chat()
	for i in range(4):
		await get_tree().process_frame
	print("CHAT13W centred pos=", hud._chat_panel.position, " size=", hud._chat_panel.size)
	# Stage the panel's MP face (SP build honestly locks it; the
	# shot needs the populated online state): drop the SP notice
	# row, re-show the segmented control, unlock the input.
	var notice = hud._chat_rows.get_node_or_null("ChatNotice")
	if notice != null:
		hud._chat_rows.remove_child(notice)
		notice.queue_free()
	var seg = hud._chat_panel.find_child("ChatSeg", true, false)
	if seg != null:
		seg.visible = true
	hud._chat_team_btn.visible = true # SP build hides it (no allies)
	hud._chat_input.editable = true
	hud._chat_input.placeholder_text = "Nhập tin nhắn… (Enter để gửi)"
	hud._chat_send_btn.disabled = false
	# A full conversation: batching (3 in a row from one sender),
	# team scope, long names, long wrapping messages.
	var lines := [
		["HiepSi", "match", 0, "Chào mọi người, trận này đánh nhanh thắng nhanh nhé"],
		["HiepSi", "match", 0, "Mình lên đời II sớm rồi dồn lính qua cánh trái"],
		["HiepSi", "match", 0, "Ai có thừa gỗ thì để dành xây tháp canh ở giữa map"],
		["CongTuoc1", "match", 1, "Ok, mình đang gom cung thủ ở nhà, khoảng hai phút nữa là đủ quân"],
		["HoangDe1", "match", 2, "Bên mình bị nó quấy nông dân từ đầu trận, đang phải dựng tường gỗ quanh mỏ vàng, ai rảnh qua cứu với không là mất luôn khu kinh tế phía đông"],
		["CongTuoc1", "team", 1, "Đội nghe rõ: tập trung ở cổng giữa, chờ hiệu lệnh của mình rồi cùng xông lên một lượt"],
		["CongTuoc1", "team", 1, "Đừng ai đi lẻ, nó có kỵ binh cơ động lắm"],
		["Một Cái Tên Người Chơi Thật Dài Để Kiểm Tra", "match", 3, "Tên mình dài vậy thôi chứ đánh cũng thường thôi mọi người ơi"],
		["HiepSi", "match", 0, "Thấy kỵ binh của nó ở bờ sông rồi, rút dân về nhà chính ngay, đừng cố nhặt nốt đống thịt đó nữa, giữ dân là giữ kinh tế, mất dân đầu trận là thua luôn cả ván đấy mọi người ạ, nghiêm túc đấy"],
		["HoangDe1", "match", 2, "Đã rõ, mình kéo hết dân vào nhà chính rồi"],
		["HoangDe1", "match", 2, "Nó rút rồi, chắc hết máu với đội hình đó"],
		["CongTuoc1", "match", 1, "Tốt, vậy đúng kế hoạch: phút mười hai tổng tấn công cửa giữa"],
		["Một Cái Tên Người Chơi Thật Dài Để Kiểm Tra", "match", 3, "Mình theo cánh phải, có tháp canh yểm trợ rồi nên cứ yên tâm đẩy thẳng vào căn cứ của nó, nếu thấy lâu đài thì báo mình ngay để mình điều máy bắn đá qua hỗ trợ từ xa nhé"],
		["HiepSi", "team", 0, "Đội: giữ đội hình, cung thủ đứng sau thương binh"],
		["HoangDe1", "match", 2, "GG, trận hay đấy mọi người"],
	]
	for ln in lines:
		hud.add_chat_line(ln[0], ln[3], ln[1], ln[2])
	for i in range(6):
		await get_tree().process_frame
	print("CHAT13W blocks=", hud._chat_rows.get_child_count())
	await _snap("empire_age_panel_chat_v2")
	# Drag the panel by its header with real input events:
	# press on the title area, move up-right, release.
	var header = hud._chat_panel.find_child("ChatHeader", true, false)
	var hp: Vector2 = header.global_position
	var press := Vector2(hp.x + 90.0, hp.y + 23.0)
	var target := press + Vector2(344.0, -110.0)
	_push_button(press, true)
	for i in range(3):
		await get_tree().process_frame
	_push_motion(press, target)
	for i in range(4):
		await get_tree().process_frame
	_push_button(target, false)
	for i in range(3):
		await get_tree().process_frame
	print("CHAT13W dragged pos=", hud._chat_panel.position)
	await _snap("empire_age_panel_chat_v2_dragged")
	print("CHAT13W CAPTURE SAVED")
	get_tree().quit()


func _push_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev)


func _push_motion(from_pos: Vector2, to_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to_pos
	ev.global_position = to_pos
	ev.relative = to_pos - from_pos
	get_viewport().push_input(ev)


func _snap(slug: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % slug)
	print("CHAT13W ", slug)
