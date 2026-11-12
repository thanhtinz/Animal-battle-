class_name TournamentScreen
extends CanvasLayer

## Tournament screen (15h) — the client face of the
## server-side tournament system. MINIMAL FUNCTIONAL UI in
## the shared info-page dialect (PageShell solid navy page,
## gold back pill + title): the server owns every rule
## (bracket, check-in, walkovers, disputes, rewards) and this
## screen only renders the detail payload it is handed,
## refreshing on a poll while open. Entry point: the home
## rail's trophy chip (Main.home_open_tournament).
##
## Views: a list (open/running/finished tournaments + a
## create form) and a detail (entrants, standings, bracket
## as text rows per round, per-match actions: check-in,
## Vào trận, khiếu nại, and the creator's controls).

const GOLD := Color(0.98, 0.8, 0.35)
const PAPER := Color(0.96, 0.94, 0.88)
const MUTED := Color(0.72, 0.76, 0.86)
const CARD_BG := Color(0.05, 0.07, 0.13, 1.0)

var game = null

var _root: Control
var _title: Label
var _scroll_box: VBoxContainer
var _status: Label
var _view := "list" # list | detail
var _current_id := ""
var _poll := 0.0
var _create_open := false

# Create-form controls (rebuilt with the list view).
var _name_edit: LineEdit
var _format_opt: OptionButton
var _bracket_opt: OptionButton
var _size_opt: OptionButton
var _partner_edit: LineEdit


func setup(p_game) -> void:
	game = p_game
	layer = 50 # above home (40), below the MP lobby (60)
	_build()
	visible = false
	Net.tourn_list_received.connect(func(_rows) -> void:
		if visible and _view == "list":
			_render_list())
	Net.tourn_detail_received.connect(func(t) -> void:
		if visible and _view == "detail" \
				and String(t.get("id", "")) == _current_id:
			_render_detail())
	Net.lobby_error.connect(func(msg) -> void:
		if visible:
			_set_status(msg))
	Net.match_started.connect(func(_cfg) -> void:
		# Our tournament room started: hand over to the match
		# scene exactly like the lobby does. When the lobby
		# exists it runs the same hand-off; begin_match is a
		# scene reload, so guard to the visible case or to
		# no-lobby sessions to avoid a double reload.
		if not Net.tourn_room.is_empty() \
				and (visible or (game != null and game.lobby == null)):
			visible = false
			Net.begin_match())


func open() -> void:
	_view = "list"
	_current_id = ""
	visible = true
	_title.text = "Giải đấu"
	Net.tourn_request_list()
	_render_list()


func open_detail(id: String) -> void:
	if id == "":
		open()
		return
	_view = "detail"
	_current_id = id
	visible = true
	Net.tourn_request_detail(id)
	_render_detail()


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_poll += delta
	if _poll < 2.5:
		return
	_poll = 0.0
	if _view == "detail" and _current_id != "":
		Net.tourn_request_detail(_current_id)
	elif _view == "list":
		Net.tourn_request_list()


func _on_back() -> void:
	if _view == "detail":
		open()
	else:
		close()


# ------------------------------------------------------------ build

func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


func _label(text: String, fsize: int, color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	# No autowrap by default: a wrapping label inside an HBox
	# collapses to its longest-word minimum width and stacks
	# its text vertically (seen in the first capture). Long
	# prose uses _label_wrapped() in full-width VBox slots.
	return l


func _label_wrapped(text: String, fsize: int, color: Color = PAPER) -> Label:
	var l := _label(text, fsize, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, on_press: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	if primary:
		b.add_theme_stylebox_override("normal",
				_sb(Color(0.98, 0.8, 0.35), 8))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
	else:
		b.add_theme_stylebox_override("normal",
				_sb(Color(0.13, 0.16, 0.24), 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_color_override("font_color", PAPER)
	b.pressed.connect(on_press)
	return b


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bs := PageShell.bg_style()
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bs.content_margin_top = PageShell.CONTENT_TOP
	bs.content_margin_bottom = 34
	board.add_theme_stylebox_override("panel", bs)
	_root.add_child(board)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	board.add_child(vb)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_scroll_box = VBoxContainer.new()
	_scroll_box.add_theme_constant_override("separation", 8)
	_scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_scroll_box)
	_root.add_child(PageShell.header("Giải đấu", Callable(self, "_on_back")))
	_title = _root.get_child(_root.get_child_count() - 1).get_child(1) as Label
	_status = _label("", 13, Color(1.0, 0.75, 0.6))
	_status.position = Vector2(16, 0) # y set in _ready layout below
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -28
	_status.offset_left = 16
	_status.offset_right = -16
	_root.add_child(_status)


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg


func _clear() -> void:
	for c in _scroll_box.get_children():
		_scroll_box.remove_child(c)
		c.queue_free()


# ------------------------------------------------------------ labels

func _format_label(f: String) -> String:
	return "Đội 2v2" if f == "team" else "Đơn 1v1"


func _bracket_label(b: String) -> String:
	match b:
		"single_elim":
			return "Loại trực tiếp"
		"double_elim":
			return "Nhánh thắng – nhánh thua"
		"round_robin":
			return "Vòng tròn"
		"group_knockout":
			return "Vòng bảng + loại trực tiếp"
	return b


func _state_label(s: String) -> String:
	match s:
		"open":
			return "Đang mở đăng ký"
		"checkin":
			return "Đang check-in"
		"running":
			return "Đang diễn ra"
		"finished":
			return "Đã kết thúc"
		"cancelled":
			return "Đã huỷ"
		"pending":
			return "Chờ"
		"ready":
			return "Sẵn sàng"
		"live":
			return "Đang đấu"
		"done":
			return "Đã xong"
		"disputed":
			return "Đang khiếu nại"
	return s


func _side_label(m: Dictionary, side: String) -> String:
	if not bool(m.get(side + "_set", false)):
		return "—"
	if String(m.get(side + "_label", "")) == "":
		return "(bye)"
	return String(m.get(side + "_label", ""))


# ------------------------------------------------------------ list view

func _render_list() -> void:
	_title.text = "Giải đấu"
	_clear()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_label("Các giải đấu", 17, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_button("Tạo giải", func() -> void:
		_create_open = not _create_open
		_render_list(), true))
	_scroll_box.add_child(top)
	if _create_open:
		_scroll_box.add_child(_create_form())
	if Net.account_name == "":
		_scroll_box.add_child(_label_wrapped(
			"Đăng nhập tài khoản để xem và tham gia giải đấu.", 14, MUTED))
		return
	if Net.tourn_list_rows.is_empty():
		_scroll_box.add_child(_label("Chưa có giải nào.", 14, MUTED))
	for row in Net.tourn_list_rows:
		_scroll_box.add_child(_list_row(row))


func _list_row(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			_sb(CARD_BG, 10, Color(1, 0.85, 0.4, 0.25), 1))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var name_l := _label(String(row.get("name", "")), 16, GOLD)
	vb.add_child(name_l)
	var meta := "%s · %s · Đã đăng ký %d/%d · %s · Tạo bởi %s" % [
		_format_label(String(row.get("format", ""))),
		_bracket_label(String(row.get("bracket", ""))),
		int(row.get("entered", 0)), int(row.get("size", 0)),
		_state_label(String(row.get("state", ""))),
		String(row.get("creator_name", ""))]
	if String(row.get("state", "")) == "finished" \
			and String(row.get("champion_name", "")) != "":
		meta += " · Vô địch: " + String(row.get("champion_name", ""))
	vb.add_child(_label(meta, 13, MUTED))
	var id := String(row.get("id", ""))
	hb.add_child(_button("Xem", func() -> void: open_detail(id), true))
	return card


func _create_form() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			_sb(CARD_BG, 10, Color(1, 0.85, 0.4, 0.25), 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	vb.add_child(_label("Tạo giải mới", 15, GOLD))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Tên giải (tối đa 40 ký tự)"
	_name_edit.max_length = 40
	vb.add_child(_name_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	_format_opt = OptionButton.new()
	_format_opt.add_item("Đơn 1v1", 0)
	_format_opt.add_item("Đội 2v2", 1)
	row.add_child(_format_opt)
	_bracket_opt = OptionButton.new()
	_bracket_opt.add_item("Loại trực tiếp", 0)
	_bracket_opt.add_item("Nhánh thắng – nhánh thua", 1)
	_bracket_opt.add_item("Vòng tròn", 2)
	_bracket_opt.add_item("Vòng bảng + loại trực tiếp", 3)
	row.add_child(_bracket_opt)
	_size_opt = OptionButton.new()
	_size_opt.add_item("4 đội", 0)
	_size_opt.add_item("8 đội", 1)
	_size_opt.add_item("16 đội", 2)
	row.add_child(_size_opt)
	vb.add_child(_button("Tạo giải", func() -> void:
		var formats := ["solo", "team"]
		var brackets := ["single_elim", "double_elim",
				"round_robin", "group_knockout"]
		var sizes := [4, 8, 16]
		Net.tourn_create(_name_edit.text,
				formats[_format_opt.selected],
				brackets[_bracket_opt.selected],
				sizes[_size_opt.selected])
		_create_open = false, true))
	return card


# ------------------------------------------------------------ detail view

func _render_detail() -> void:
	var d := Net.tourn_detail
	if d.is_empty() or String(d.get("id", "")) != _current_id:
		return
	_title.text = String(d.get("name", "Giải đấu"))
	_clear()
	var state := String(d.get("state", ""))
	var head := "%s · %s · %d suất · %s · Tạo bởi %s" % [
		_format_label(String(d.get("format", ""))),
		_bracket_label(String(d.get("bracket", ""))),
		int(d.get("size", 0)), _state_label(state),
		String(d.get("creator_name", ""))]
	_scroll_box.add_child(_label_wrapped(head, 14, MUTED))
	if state == "finished":
		_scroll_box.add_child(_label("Vô địch: %s · Á quân: %s" % [
			String(d.get("champion_name", "")),
			String(d.get("runner_up_name", ""))], 16, GOLD))
	_scroll_box.add_child(_detail_actions(d))
	# Entrants.
	var entries: Array = d.get("entries", [])
	_scroll_box.add_child(_label("Đội tham gia (%d)" % entries.size(), 16, GOLD))
	if entries.is_empty():
		_scroll_box.add_child(_label("Chưa có đội nào đăng ký.", 13, MUTED))
	for e in entries:
		var tag := " (đội của bạn)" if bool(e.get("is_mine", false)) else ""
		_scroll_box.add_child(_label("#%d · %s%s" % [
			int(e.get("id", 0)), String(e.get("label", "")), tag], 14))
	# Standings (league stages).
	var standings: Dictionary = d.get("standings", {})
	for stage in ["rr", "ga", "gb"]:
		if not standings.has(stage):
			continue
		var sname: String = {"rr": "Bảng xếp hạng", "ga": "Bảng A", "gb": "Bảng B"}[stage]
		_scroll_box.add_child(_label(sname, 16, GOLD))
		var pos := 1
		for r in (standings[stage] as Array):
			_scroll_box.add_child(_label("%d. %s — Thắng %d · Điểm %d" % [
				pos, String(r.get("label", "")), int(r.get("wins", 0)),
				int(r.get("score", 0))], 14))
			pos += 1
	# Matches grouped by stage + round, in payload order.
	_scroll_box.add_child(_label("Các trận đấu", 16, GOLD))
	var last_key := ""
	for m in (d.get("matches", []) as Array):
		var key := String(m.get("stage", "")) + "/" + str(int(m.get("round", 0)))
		if key != last_key:
			last_key = key
			_scroll_box.add_child(_label(_group_label(m), 14, GOLD))
		_scroll_box.add_child(_match_row(d, m))
	if (d.get("matches", []) as Array).is_empty():
		_scroll_box.add_child(_label(
			"Bracket sẽ hiện khi người tạo giải mở check-in.", 13, MUTED))
	# Audit log tail.
	var log_lines: Array = d.get("log", [])
	if not log_lines.is_empty():
		_scroll_box.add_child(_label("Nhật ký giải", 16, GOLD))
		for line in log_lines:
			_scroll_box.add_child(_label_wrapped("· " + String(line), 12, MUTED))


func _group_label(m: Dictionary) -> String:
	match String(m.get("stage", "")):
		"main", "wb":
			return String(m.get("label", ""))
		"lb":
			return "Nhánh thua · Vòng %d" % int(m.get("round", 0))
		"gf":
			return "Chung kết tổng"
		"rr":
			return "Vòng %d" % int(m.get("round", 0))
		"ga":
			return "Bảng A · Vòng %d" % int(m.get("round", 0))
		"gb":
			return "Bảng B · Vòng %d" % int(m.get("round", 0))
		"ko":
			return "Vòng loại trực tiếp"
	return String(m.get("label", ""))


func _detail_actions(d: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var state := String(d.get("state", ""))
	var id := _current_id
	var my_entry := int(d.get("my_entry", 0))
	if state == "open":
		if my_entry == 0:
			var pe: LineEdit = null
			if String(d.get("format", "")) == "team":
				pe = LineEdit.new()
				pe.placeholder_text = "Tên tài khoản đồng đội"
				pe.custom_minimum_size = Vector2(220, 0)
				_partner_edit = pe
				hb.add_child(pe)
			hb.add_child(_button("Đăng ký", func() -> void:
				Net.tourn_register(id, pe.text if pe != null else ""), true))
		else:
			hb.add_child(_label("Bạn đã đăng ký (đội #%d)." % my_entry, 14, MUTED))
			# Only the captain can withdraw the entry.
			for e in (d.get("entries", []) as Array):
				if int(e.get("id", 0)) == my_entry \
						and String(e.get("captain", "")) == Net.account_name:
					hb.add_child(_button("Huỷ đăng ký", func() -> void:
						Net.tourn_unregister(id)))
	if bool(d.get("is_creator", false)):
		if state == "open":
			hb.add_child(_button("Mở check-in", func() -> void:
				Net.tourn_start(id), true))
		if state == "open" or state == "checkin":
			hb.add_child(_button("Huỷ giải", func() -> void:
				Net.tourn_cancel(id)))
	return hb


func _match_row(d: Dictionary, m: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			_sb(CARD_BG, 10, Color(1, 0.85, 0.4, 0.18), 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var state := String(m.get("state", ""))
	var line := "%s: %s  vs  %s — %s" % [
		String(m.get("label", "")), _side_label(m, "a"),
		_side_label(m, "b"), _state_label(state)]
	if state == "done" or state == "disputed":
		if bool(m.get("bye", false)):
			line += " (bye)"
		elif bool(m.get("walkover", false)):
			line += " (xử thắng)"
		elif bool(m.get("played", false)):
			line += " · Tỉ số điểm %d – %d" % [
				int(m.get("score_a", 0)), int(m.get("score_b", 0))]
		if String(m.get("winner_label", "")) != "":
			line += " · Thắng: " + String(m.get("winner_label", ""))
	vb.add_child(_label_wrapped(line, 14))
	if state == "ready" or state == "live":
		var checks := "Check-in: %s %s · %s %s" % [
			_side_label(m, "a"),
			"đã sẵn sàng" if bool(m.get("check_a", false)) else "chưa sẵn sàng",
			_side_label(m, "b"),
			"đã sẵn sàng" if bool(m.get("check_b", false)) else "chưa sẵn sàng"]
		if bool(m.get("frozen", false)):
			checks += " · Đang đóng băng vì khiếu nại"
		vb.add_child(_label_wrapped(checks, 12, MUTED))
	var actions := _match_actions(d, m)
	if actions != null:
		vb.add_child(actions)
	return card


func _match_actions(d: Dictionary, m: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var id := _current_id
	var mid := int(m.get("id", 0))
	var state := String(m.get("state", ""))
	var my_side := int(m.get("my_side", -1))
	var added := false
	if my_side >= 0 and state == "ready":
		var checked := bool(m.get("check_a", false)) if my_side == 0 \
				else bool(m.get("check_b", false))
		if not checked:
			hb.add_child(_button("Check-in", func() -> void:
				Net.tourn_checkin(id, mid), true))
			added = true
		elif bool(m.get("check_a", false)) and bool(m.get("check_b", false)) \
				and not bool(m.get("frozen", false)):
			hb.add_child(_button("Vào trận", func() -> void:
				Net.tourn_play(id, mid)
				_set_status("Đã vào phòng trận — chờ đối thủ và trọng tài bắt đầu…"), true))
			added = true
	if my_side >= 0 and state == "live":
		hb.add_child(_button("Vào trận", func() -> void:
			Net.tourn_play(id, mid), true))
		added = true
	if my_side >= 0 and state == "done" and bool(m.get("played", false)) \
			and String(d.get("state", "")) in ["checkin", "running"] \
			and String(m.get("replay_id", "")) != "":
		var rid := String(m.get("replay_id", ""))
		hb.add_child(_button("Khiếu nại", func() -> void:
			Net.tourn_dispute(id, mid, rid)))
		added = true
	if bool(d.get("is_creator", false)):
		if state == "ready":
			hb.add_child(_button("Xử thắng: " + _side_label(m, "a"), func() -> void:
				Net.tourn_walkover(id, mid, 0)))
			hb.add_child(_button("Xử thắng: " + _side_label(m, "b"), func() -> void:
				Net.tourn_walkover(id, mid, 1)))
			added = true
		if state == "live":
			hb.add_child(_button("Đặt lại trận", func() -> void:
				Net.tourn_reset_match(id, mid)))
			added = true
		if state == "disputed":
			hb.add_child(_button("Giữ kết quả", func() -> void:
				Net.tourn_resolve(id, mid, true), true))
			hb.add_child(_button("Đấu lại", func() -> void:
				Net.tourn_resolve(id, mid, false)))
			added = true
	return hb if added else null
