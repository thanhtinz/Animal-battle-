class_name AllianceScreen
extends CanvasLayer

## Alliance screen (17a) — the REAL Liên minh system UI:
## server-backed alliances behind the leaderboard's Liên minh
## tab and the profile's Liên minh row. Layout = the owner's
## approved mock B (joined: profile card left + tabbed member
## board right) and the join mock (not joined: intro card +
## create form + search + recruiting list + invites), drawn in
## the game's PageShell dialect like TournamentScreen.
##
## Rules (server-enforced, mirrored here): accounts only;
## one alliance per account; cap 30; roles Hội trưởng / Phó
## (max 3) / Thành viên; join modes "Mở" (instant) and "Xin
## vào" (request → approve); weekly contribution from banked
## matches (win +30, played +10) drives the Liên minh
## leaderboard. Alliance chat is a lobby channel of its own —
## the "Chat liên minh" view below — never part of a match.

const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"
const FA_CROWN := 0xF521
const FA_USERS := 0xF0C0
const FA_USER_PLUS := 0xF234
const FA_COMMENTS := 0xF086
const FA_GEAR := 0xF013
const FA_LEAVE := 0xF2F5
const FA_PLUS := 0x2B
const FA_CHECK := 0xF00C
const FA_XMARK := 0xF00D

const GOLD := Color(1.0, 0.85, 0.4)
const GOLD_TXT := Color(0.98, 0.8, 0.35)
const PAPER := Color(0.92, 0.9, 0.84)
const MUTED := Color(0.62, 0.66, 0.75)
const DIM := Color(0.45, 0.48, 0.58)
const RED := Color(0.98, 0.5, 0.45)
const CARD_BG := Color(0.05, 0.07, 0.13)
const PANEL_LINE := Color(0.30, 0.34, 0.46)
const FIELD_BG := Color(0.04, 0.05, 0.10)
const BTN_BG := Color(0.13, 0.16, 0.24)

# Badge colour set (ids must match the server's AllianceBadges).
const BADGE_ORDER: Array = ["red", "blue", "teal", "green", "gold", "purple"]
const BADGE_COLORS := {
	"red": Color(0.45, 0.08, 0.10), "blue": Color(0.10, 0.25, 0.55),
	"teal": Color(0.05, 0.35, 0.38), "green": Color(0.10, 0.32, 0.12),
	"gold": Color(0.45, 0.35, 0.05), "purple": Color(0.25, 0.12, 0.42),
}
const BADGE_NAMES := {
	"red": "Đỏ", "blue": "Xanh dương", "teal": "Xanh ngọc",
	"green": "Xanh lá", "gold": "Vàng", "purple": "Tím",
}
const ROLE_NAMES := {"leader": "Hội trưởng", "deputy": "Phó", "member": "Thành viên"}

var game = null # Main (duck-typed)

var _body: VBoxContainer
var _status: Label
var _poll := 0.0
var _tab := "members"
var _sig := "\u0001" # payload signature: rebuild only on change
var _search_text := ""
var _create_open := false
var _invite_open := false
var _settings_open := false
var _chat_open := false
var _arm := "" # two-tap confirm key ("leave" / "disband" / "transfer:<user>")
var _arm_at := 0
var _chat_box: VBoxContainer = null
var _chat_scroll: ScrollContainer = null
var _chat_input: LineEdit = null
var _fa_font: Font = null
var _status_msg := "" # last action/error line; reapplied after every rebuild


class ShieldBadge:
	extends Control
	var fill: Color = Color(0.45, 0.08, 0.1)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([
				Vector2(0.07 * w, 0.04 * h), Vector2(0.93 * w, 0.04 * h),
				Vector2(0.93 * w, 0.46 * h), Vector2(0.80 * w, 0.72 * h),
				Vector2(0.5 * w, 0.97 * h), Vector2(0.20 * w, 0.72 * h),
				Vector2(0.07 * w, 0.46 * h)])
		draw_colored_polygon(pts, fill)
		var loop := PackedVector2Array(pts)
		loop.append(pts[0])
		draw_polyline(loop, Color(0.98, 0.8, 0.35, 0.9), 2.5)
		var c := Vector2(0.5 * w, 0.40 * h)
		var r := 0.19 * minf(w, h)
		var star := PackedVector2Array()
		for i in 10:
			var ang := -PI * 0.5 + i * PI / 5.0
			var rad := r if i % 2 == 0 else r * 0.45
			star.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(star, Color(1.0, 0.82, 0.3))


func setup(g) -> void:
	game = g


func _ready() -> void:
	layer = 50
	visible = false
	# PageShell dialect, built exactly like TournamentScreen:
	# the shell's bg style carries the content margins (title
	# zone on top, status strip at the bottom), the header is
	# the shell's own overlay, and the status line is a
	# bottom-anchored label outside the rebuilt body.
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bs := PageShell.bg_style()
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bs.content_margin_top = PageShell.CONTENT_TOP
	bs.content_margin_bottom = 34
	board.add_theme_stylebox_override("panel", bs)
	add_child(board)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	board.add_child(_body)
	add_child(PageShell.header("Liên minh", func() -> void: close()))
	_status = _label("", 13, Color(1.0, 0.75, 0.6))
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -28
	_status.offset_left = 16
	_status.offset_right = -16
	add_child(_status)
	Net.alliance_home_received.connect(func(_mine: Dictionary, _inv: Array) -> void:
		if visible:
			_render())
	Net.alliance_list_received.connect(func(_rows: Array) -> void:
		if visible and Net.alliance_mine.is_empty():
			_render())
	Net.chat_received.connect(func(scope: String, _f: int, _n: String, _t: String) -> void:
		if visible and _chat_open and scope == "alliance":
			_render_chat_lines()
			_scroll_chat_bottom())
	Net.lobby_error.connect(func(msg: String) -> void:
		if visible:
			_show_status(msg))


func open() -> void:
	visible = true
	_tab = "members"
	_chat_open = false
	_arm = ""
	_status_msg = ""
	_sig = "\u0001"
	_poll = 0.0
	if Net.account_name == "":
		_render()
		return
	Net.alliance_request_home()
	Net.alliance_request_list(_search_text)
	_render()


func close() -> void:
	visible = false
	_chat_open = false


func _process(delta: float) -> void:
	if not visible:
		return
	_poll += delta
	if _poll >= 2.5:
		_poll = 0.0
		if Net.account_name != "":
			Net.alliance_request_home()
			if Net.alliance_mine.is_empty():
				Net.alliance_request_list(_search_text)


# ------------------------------------------------------------ helpers

func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


func _card(pad: int = 12, bw: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _sb(CARD_BG, 12, PANEL_LINE, bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", s)
	return p


func _label(text: String, fsize: int, col: Color = PAPER, _bold := false) -> Label:
	# The project ships no bold face (emphasis is colour/size,
	# as in TournamentScreen); the _bold flag is kept for call
	# compatibility and adds the standard text shadow.
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label_wrap(text: String, fsize: int, col: Color = PAPER) -> Label:
	var l := _label(text, fsize, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _fa(cp: int, px: int, col: Color = PAPER) -> Label:
	if _fa_font == null:
		_fa_font = load(FA_FONT_PATH)
	var l := Label.new()
	l.text = String.chr(cp)
	l.add_theme_font_override("font", _fa_font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(px + 6, px + 6)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, primary := false, danger := false, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 38)
	b.add_theme_font_size_override("font_size", 14)
	if primary:
		b.add_theme_stylebox_override("normal", _sb(Color(0.98, 0.8, 0.35), 8))
		b.add_theme_stylebox_override("hover", _sb(Color(1.0, 0.86, 0.45), 8))
		b.add_theme_stylebox_override("pressed", _sb(Color(0.88, 0.7, 0.28), 8))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	elif danger:
		b.add_theme_stylebox_override("normal", _sb(BTN_BG, 8, Color(0.98, 0.5, 0.45, 0.55), 1))
		b.add_theme_stylebox_override("hover", _sb(Color(0.2, 0.2, 0.3), 8, Color(0.98, 0.5, 0.45, 0.8), 1))
		b.add_theme_stylebox_override("pressed", _sb(Color(0.1, 0.12, 0.2), 8, Color(0.98, 0.5, 0.45), 1))
		b.add_theme_color_override("font_color", RED)
		b.add_theme_color_override("font_hover_color", RED)
	else:
		b.add_theme_stylebox_override("normal", _sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_stylebox_override("hover", _sb(Color(0.18, 0.22, 0.32), 8, Color(1, 0.85, 0.4, 0.6), 1))
		b.add_theme_stylebox_override("pressed", _sb(Color(0.09, 0.11, 0.19), 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_color_override("font_color", PAPER)
		b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_stylebox_override("disabled", _sb(Color(1, 1, 1, 0.03), 8, Color(1, 1, 1, 0.10), 1))
	b.add_theme_color_override("font_disabled_color", DIM)
	return b


## Icon + text button (the mock's action rows): a panel with a
## centred FA glyph + label; returns the Button overlaying it
## is overkill — a Button with an HBox child that ignores the
## mouse reads identically and clicks natively.
func _icon_btn(text: String, cp: int, kind := "") -> Button:
	var b := _button("", kind == "primary", kind == "danger")
	b.custom_minimum_size = Vector2(0, 40)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 7)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	var col := PAPER
	if kind == "primary":
		col = Color(0.1, 0.08, 0.02)
	elif kind == "danger":
		col = RED
	hb.add_child(_fa(cp, 14, col))
	var l := _label(text, 14, col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	b.add_child(hb)
	return b


func _pill(text: String, fill: Color, txt_col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _sb(fill, 7)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label(text, 12, txt_col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _role_pill(role: String) -> PanelContainer:
	match role:
		"leader":
			return _pill("Hội trưởng", Color(0.98, 0.8, 0.35), Color(0.1, 0.08, 0.02))
		"deputy":
			return _pill("Phó", Color(0.2, 0.28, 0.45), PAPER)
		_:
			return _pill("Thành viên", Color(1, 1, 1, 0.06), MUTED)


func _field(placeholder: String, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(0, 38)
	e.add_theme_font_size_override("font_size", 14)
	e.add_theme_color_override("font_color", PAPER)
	e.add_theme_color_override("font_placeholder_color", DIM)
	e.add_theme_stylebox_override("normal", _sb(FIELD_BG, 8, PANEL_LINE, 1))
	e.add_theme_stylebox_override("focus", _sb(FIELD_BG, 8, GOLD, 1))
	return e


func _option(items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = selected
	o.custom_minimum_size = Vector2(0, 38)
	o.add_theme_font_size_override("font_size", 14)
	o.add_theme_color_override("font_color", PAPER)
	o.add_theme_stylebox_override("normal", _sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
	o.add_theme_stylebox_override("hover", _sb(Color(0.18, 0.22, 0.32), 8, Color(1, 0.85, 0.4, 0.6), 1))
	o.add_theme_stylebox_override("pressed", _sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
	return o


func _section(text: String, extra := "") -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(_label(text, 15, GOLD_TXT, true))
	if extra != "":
		hb.add_child(_label(extra, 13, DIM))
	return hb


func _badge(badge_id: String, px: int) -> ShieldBadge:
	var b := ShieldBadge.new()
	b.fill = BADGE_COLORS.get(badge_id, BADGE_COLORS["red"])
	b.custom_minimum_size = Vector2(px, px)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _avatar(avatar_id: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Characters.avatar_for(avatar_id)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _ago(unix: int) -> String:
	if unix <= 0:
		return "—"
	var d := int(Time.get_unix_time_from_system()) - unix
	if d < 90:
		return "vừa xong"
	if d < 3600:
		return "%d phút trước" % maxi(1, d / 60)
	if d < 86400:
		return "%d giờ trước" % (d / 3600)
	return "%d ngày trước" % (d / 86400)


func _date_str(unix: int) -> String:
	if unix <= 0:
		return "—"
	var d := Time.get_date_dict_from_unix_time(unix)
	return "%02d/%02d/%04d" % [int(d["day"]), int(d["month"]), int(d["year"])]


func _stat_row(k: String, v: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_child(_label(k, 14, MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	hb.add_child(_label(v, 14, PAPER))
	return hb


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
		_status.visible = true


## Two-tap confirm: first call arms the key (and re-renders so
## the button shows its confirm label), a second call within
## 5 s runs fn.
func _confirm_or(key: String, fn: Callable) -> void:
	var now := Time.get_ticks_msec()
	if _arm == key and now - _arm_at <= 5000:
		_arm = ""
		fn.call()
	else:
		_arm = key
		_arm_at = now
		_render()


func _armed(key: String) -> bool:
	return _arm == key and Time.get_ticks_msec() - _arm_at <= 5000


# ------------------------------------------------------------ render

func _render() -> void:
	if _body == null:
		return
	if _chat_open:
		return # chat view owns the surface; it updates itself
	# Rebuild only when the payload actually changed, so poll
	# refreshes never clobber a half-typed field.
	var sig := JSON.stringify([Net.alliance_mine, Net.alliance_invites,
			Net.alliance_rows, _tab, _create_open, _invite_open,
			_settings_open, _arm, Net.account_name])
	if sig == _sig:
		return
	_sig = sig
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if _status != null:
		_status.text = _status_msg
	if Net.account_name == "":
		_body.add_child(_guest_view())
		return
	if Net.alliance_mine.is_empty():
		_build_join()
	else:
		_build_joined()


func _show_status(msg: String) -> void:
	_status_msg = msg
	_set_status(msg)
	if _status != null:
		_status.visible = msg != ""


func _guest_view() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	var intro := _intro_card(false)
	vb.add_child(intro)
	var note := _label("Đăng nhập để tạo hoặc gia nhập liên minh, duyệt đơn và chat với đồng minh.",
			14, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(note)
	return vb


func _intro_card(with_create: bool) -> PanelContainer:
	var card := _card(18)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(76, 76)
	tile.add_theme_stylebox_override("panel", _sb(Color(0.10, 0.13, 0.22), 12))
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ic := _fa(FA_USERS, 32, GOLD_TXT)
	ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.add_child(ic)
	hb.add_child(tile)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_label("Liên minh", 20, GOLD_TXT, true))
	vb.add_child(_label_wrap("Cùng bạn bè lập một liên minh: đấu trận để góp điểm, "
			+ "leo hạng toàn server và trò chuyện trong kênh riêng của liên minh.", 13, MUTED))
	hb.add_child(vb)
	if with_create:
		var b := _button("Tạo liên minh", true, false, 176)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			_create_open = not _create_open
			_sig = "\u0001"
			_render())
		hb.add_child(b)
	card.add_child(hb)
	return card


# ------------------------------------------------------------ joined

func _build_joined() -> void:
	var mine: Dictionary = Net.alliance_mine
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(cols)
	# ---- left column: profile card + actions ----------------
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size = Vector2(372, 0)
	cols.add_child(left)
	left.add_child(_profile_card(mine))
	left.add_child(_actions_card(mine))
	if _invite_open and String(mine.get("my_role", "")) in ["leader", "deputy"]:
		left.add_child(_invite_card(mine))
	if _settings_open and String(mine.get("my_role", "")) == "leader":
		left.add_child(_settings_card(mine))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	# ---- right column: tabs + content -----------------------
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	right.add_child(tabs)
	var req_count := int(mine.get("requests_count", 0))
	tabs.add_child(_tab_btn("members", "Thành viên"))
	var req_label := "Yêu cầu"
	if req_count > 0:
		req_label += " (%d)" % req_count
	tabs.add_child(_tab_btn("requests", req_label))
	tabs.add_child(_tab_btn("activity", "Hoạt động"))
	var content := _card(14)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cv)
	match _tab:
		"requests":
			_fill_requests(cv, mine)
		"activity":
			_fill_activity(cv, mine)
		_:
			_fill_members(cv, mine)


func _tab_btn(id: String, text: String) -> Button:
	var b := _button(text)
	if _tab == id:
		b.add_theme_stylebox_override("normal", _sb(Color(0.98, 0.8, 0.35), 8))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_stylebox_override("hover", _sb(Color(0.98, 0.8, 0.35), 8))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	b.pressed.connect(func() -> void:
		_tab = id
		_arm = ""
		_sig = "\u0001"
		_render())
	return b


func _profile_card(mine: Dictionary) -> PanelContainer:
	var card := _card(16, 2)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 9)
	card.add_child(pv)
	var cc := CenterContainer.new()
	cc.add_child(_badge(String(mine.get("badge", "red")), 108))
	pv.add_child(cc)
	var nm := _label(String(mine.get("name", "")), 21, GOLD_TXT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(nm)
	if String(mine.get("desc", "")) != "":
		var ds := _label_wrap(String(mine.get("desc", "")), 12, MUTED)
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(ds)
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 8)
	pills.add_child(_pill("Cấp %d" % int(mine.get("level", 1)),
			Color(0.98, 0.8, 0.35), Color(0.1, 0.08, 0.02)))
	var rank := int(mine.get("rank", 0))
	pills.add_child(_pill("Hạng %d toàn server" % rank if rank > 0 else "Chưa xếp hạng",
			Color(1, 1, 1, 0.06), MUTED))
	pv.add_child(pills)
	var xrow := HBoxContainer.new()
	xrow.add_child(_label("XP liên minh", 13, MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xrow.add_child(sp)
	xrow.add_child(_label("%s / %s XP" % [_fmt(int(mine.get("xp_into", 0))),
			_fmt(int(mine.get("xp_next", 1)))], 13, PAPER))
	pv.add_child(xrow)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(1, int(mine.get("xp_next", 1)))
	bar.value = int(mine.get("xp_into", 0))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", _sb(Color(0.05, 0.06, 0.10, 0.9), 6))
	bar.add_theme_stylebox_override("fill", _sb(Color(0.85, 0.65, 0.20), 6))
	pv.add_child(bar)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _sb(Color(1, 1, 1, 0.08), 1))
	pv.add_child(sep)
	pv.add_child(_stat_row("Thành viên", "%d / %d" % [int(mine.get("members_count", 0)),
			int(mine.get("cap", 30))]))
	pv.add_child(_stat_row("Điểm tuần này", _fmt(int(mine.get("week", 0)))))
	pv.add_child(_stat_row("Hội trưởng", String(mine.get("leader_name", ""))))
	pv.add_child(_stat_row("Ngày lập", _date_str(int(mine.get("created_at", 0)))))
	return card


func _actions_card(mine: Dictionary) -> PanelContainer:
	var card := _card(12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	var role := String(mine.get("my_role", ""))
	var ally_id := String(mine.get("id", ""))
	if role in ["leader", "deputy"]:
		var inv := _icon_btn("Mời bạn bè", FA_USER_PLUS, "primary")
		inv.pressed.connect(func() -> void:
			_invite_open = not _invite_open
			_settings_open = false
			_sig = "\u0001"
			_render())
		vb.add_child(inv)
	var chatb := _icon_btn("Chat liên minh", FA_COMMENTS)
	chatb.pressed.connect(func() -> void: _open_chat(mine))
	vb.add_child(chatb)
	if role == "leader":
		var setb := _icon_btn("Cài đặt liên minh", FA_GEAR)
		setb.pressed.connect(func() -> void:
			_settings_open = not _settings_open
			_invite_open = false
			_sig = "\u0001"
			_render())
		vb.add_child(setb)
	if role == "leader":
		var hint := _label_wrap("Hội trưởng không rời trực tiếp được — hãy chuyển quyền "
				+ "ở tab Thành viên, hoặc giải tán liên minh:", 12, MUTED)
		vb.add_child(hint)
		var dis := _icon_btn("Đã chắc chắn — giải tán" if _armed("disband") else "Giải tán liên minh",
				FA_LEAVE, "danger")
		dis.pressed.connect(func() -> void:
			_confirm_or("disband", func() -> void:
				Net.alliance_disband(ally_id)
				_show_status("Đã giải tán liên minh.")))
		vb.add_child(dis)
	else:
		var leave := _icon_btn("Chắc chắn rời? Bấm lại" if _armed("leave") else "Rời liên minh",
				FA_LEAVE, "danger")
		leave.pressed.connect(func() -> void:
			_confirm_or("leave", func() -> void:
				Net.alliance_leave(ally_id)
				_show_status("Đã rời liên minh.")))
		vb.add_child(leave)
	return card


func _invite_card(mine: Dictionary) -> PanelContainer:
	var card := _card(12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	vb.add_child(_section("MỜI BẠN BÈ"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var edit := _field("Tên người chơi (tên hiển thị hoặc tên đăng nhập)…")
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var ally_id := String(mine.get("id", ""))
	var send := _button("Mời", true, false, 84)
	var do_invite := func() -> void:
		var nm := edit.text.strip_edges()
		if nm == "":
			_show_status("Hãy nhập tên người chơi muốn mời.")
			return
		Net.alliance_invite(ally_id, nm)
		_show_status("Đã gửi lời mời tới %s." % nm)
	send.pressed.connect(do_invite)
	edit.text_submitted.connect(func(_t: String) -> void: do_invite.call())
	row.add_child(send)
	vb.add_child(row)
	vb.add_child(_label_wrap("Người được mời sẽ thấy lời mời ở trang Liên minh của họ.",
			12, DIM))
	return card


func _settings_card(mine: Dictionary) -> PanelContainer:
	var card := _card(12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	vb.add_child(_section("CÀI ĐẶT LIÊN MINH"))
	vb.add_child(_label("Màu khiên", 13, MUTED))
	var badge_opt := _option(BADGE_ORDER.map(func(id: String) -> String:
			return "Khiên " + String(BADGE_NAMES[id])), 0)
	badge_opt.selected = maxi(0, BADGE_ORDER.find(String(mine.get("badge", "red"))))
	badge_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(badge_opt)
	vb.add_child(_label("Tuyển thành viên", 13, MUTED))
	var mode_opt := _option(["Mở — vào ngay không cần duyệt", "Xin vào — Hội trưởng/Phó duyệt đơn"], 0)
	mode_opt.selected = 1 if String(mine.get("mode", "request")) == "request" else 0
	mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(mode_opt)
	vb.add_child(_label("Mô tả", 13, MUTED))
	var desc_edit := _field("Mô tả ngắn về liên minh…", String(mine.get("desc", "")))
	desc_edit.max_length = 120
	vb.add_child(desc_edit)
	var ally_id := String(mine.get("id", ""))
	var save := _button("Lưu cài đặt", true)
	save.pressed.connect(func() -> void:
		Net.alliance_settings(ally_id, String(BADGE_ORDER[badge_opt.selected]),
				"open" if mode_opt.selected == 0 else "request",
				desc_edit.text.strip_edges())
		_settings_open = false
		_show_status("Đã lưu cài đặt liên minh."))
	vb.add_child(save)
	return card


func _member_header() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var n := _label("THÀNH VIÊN", 12, DIM)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(n)
	var r := _label("VAI TRÒ", 12, DIM)
	r.custom_minimum_size = Vector2(96, 0)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(r)
	var w := _label("TUẦN NÀY", 12, DIM)
	w.custom_minimum_size = Vector2(90, 0)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(w)
	var s := _label("TRẠNG THÁI", 12, DIM)
	s.custom_minimum_size = Vector2(118, 0)
	hb.add_child(s)
	return hb


func _fill_members(cv: VBoxContainer, mine: Dictionary) -> void:
	cv.add_child(_member_header())
	var my_role := String(mine.get("my_role", ""))
	var ally_id := String(mine.get("id", ""))
	for mem in mine.get("members", []):
		cv.add_child(_member_row(mem, my_role, ally_id))


func _member_row(mem: Dictionary, my_role: String, ally_id: String) -> PanelContainer:
	var row := PanelContainer.new()
	var self_row := String(mem.get("user", "")) == Net.account_name
	row.add_theme_stylebox_override("panel", _sb(Color(0.07, 0.10, 0.17, 0.55), 10,
			Color(0.98, 0.8, 0.35, 0.55) if self_row else PANEL_LINE, 1))
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 7)
	inner.add_theme_constant_override("margin_bottom", 7)
	row.add_child(inner)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	inner.add_child(hb)
	hb.add_child(_avatar(String(mem.get("avatar", "knight")), 40))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 6)
	var nm := _label(String(mem.get("name", "")), 15, PAPER, true)
	nrow.add_child(nm)
	if String(mem.get("role", "")) == "leader":
		nrow.add_child(_fa(FA_CROWN, 13, GOLD_TXT))
	if self_row:
		nrow.add_child(_label("(Bạn)", 12, DIM))
	nv.add_child(nrow)
	nv.add_child(_label("Cấp %d" % int(mem.get("level", 1)), 12, MUTED))
	hb.add_child(nv)
	var pill_wrap := CenterContainer.new()
	pill_wrap.custom_minimum_size = Vector2(96, 0)
	pill_wrap.add_child(_role_pill(String(mem.get("role", "member"))))
	hb.add_child(pill_wrap)
	var wk := _label(_fmt(int(mem.get("week", 0))), 14, PAPER)
	wk.custom_minimum_size = Vector2(90, 0)
	wk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(wk)
	# Status: online dot + text, fixed width like the mock.
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 6)
	st.custom_minimum_size = Vector2(118, 0)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var online := bool(mem.get("online", false))
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", _sb(
			Color(0.35, 0.85, 0.45) if online else Color(0.45, 0.48, 0.55), 5))
	st.add_child(dot)
	st.add_child(_label("Trực tuyến" if online else _ago(int(mem.get("seen", 0))),
			12, Color(0.45, 0.85, 0.55) if online else MUTED))
	hb.add_child(st)
	# Contextual actions (server re-checks every permission).
	var target := String(mem.get("user", ""))
	var t_role := String(mem.get("role", "member"))
	if not self_row and my_role in ["leader", "deputy"]:
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 6)
		acts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if my_role == "leader":
			if t_role == "member":
				var up := _small_btn("Lên Phó")
				up.pressed.connect(func() -> void:
					Net.alliance_role(ally_id, target, "deputy"))
				acts.add_child(up)
			elif t_role == "deputy":
				var down := _small_btn("Hạ Phó")
				down.pressed.connect(func() -> void:
					Net.alliance_role(ally_id, target, "member"))
				acts.add_child(down)
			var tr_key := "transfer:" + target
			var tr := _small_btn("Đã chắc? Bấm lại" if _armed(tr_key) else "Chuyển quyền")
			tr.pressed.connect(func() -> void:
				_confirm_or(tr_key, func() -> void:
					Net.alliance_transfer(ally_id, target)))
			acts.add_child(tr)
		if my_role == "leader" or t_role == "member":
			var kick := _small_btn("Đuổi")
			kick.pressed.connect(func() -> void:
				Net.alliance_kick(ally_id, target))
			acts.add_child(kick)
		hb.add_child(acts)
	return row


func _small_btn(text: String) -> Button:
	var b := _button(text)
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 12)
	return b


func _fill_requests(cv: VBoxContainer, mine: Dictionary) -> void:
	var my_role := String(mine.get("my_role", ""))
	if my_role not in ["leader", "deputy"]:
		cv.add_child(_label_wrap("Chỉ Hội trưởng và Phó mới xem và duyệt đơn xin vào.",
				13, MUTED))
		return
	var reqs: Array = mine.get("requests", [])
	if reqs.is_empty():
		cv.add_child(_label_wrap("Chưa có đơn xin vào nào.", 13, MUTED))
		return
	var ally_id := String(mine.get("id", ""))
	for rq in reqs:
		cv.add_child(_request_row(rq, ally_id))


func _request_row(rq: Dictionary, ally_id: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _sb(Color(0.07, 0.10, 0.17, 0.55), 10, PANEL_LINE, 1))
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 7)
	inner.add_theme_constant_override("margin_bottom", 7)
	row.add_child(inner)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	inner.add_child(hb)
	hb.add_child(_avatar(String(rq.get("avatar", "knight")), 40))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(_label(String(rq.get("name", "")), 15, PAPER, true))
	var sub := "Cấp %d · %s" % [int(rq.get("level", 1)), _ago(int(rq.get("at", 0)))]
	if String(rq.get("msg", "")) != "":
		sub += " · “%s”" % String(rq.get("msg", ""))
	nv.add_child(_label(sub, 12, MUTED))
	hb.add_child(nv)
	var user := String(rq.get("user", ""))
	var ok := _button("Duyệt", true, false, 76)
	ok.custom_minimum_size = Vector2(76, 34)
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void: Net.alliance_approve(ally_id, user))
	hb.add_child(ok)
	var no := _button("Từ chối", false, false, 84)
	no.custom_minimum_size = Vector2(84, 34)
	no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	no.pressed.connect(func() -> void: Net.alliance_reject(ally_id, user))
	hb.add_child(no)
	return row


func _fill_activity(cv: VBoxContainer, mine: Dictionary) -> void:
	var log: Array = mine.get("log", [])
	if log.is_empty():
		cv.add_child(_label_wrap("Chưa có hoạt động nào.", 13, MUTED))
		return
	for ev in log:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var t := _label_wrap("·  " + String(ev.get("text", "")), 13, PAPER)
		hb.add_child(t)
		hb.add_child(_label(_ago(int(ev.get("at", 0))), 12, DIM))
		cv.add_child(hb)


# ------------------------------------------------------------ chat view

## The alliance chat replaces the joined layout while open
## (mock B's "Chat liên minh" action). Lines live in
## Net.alliance_chat_lines (session transcript); the poll
## re-render is suspended here — this view updates itself from
## the chat_received signal.
func _open_chat(mine: Dictionary) -> void:
	_chat_open = true
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_chat_box = VBoxContainer.new()
	_chat_box.add_theme_constant_override("separation", 10)
	_chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_chat_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var back := _button("← Quay lại", false, false, 120)
	back.pressed.connect(func() -> void:
		_chat_open = false
		_sig = "\u0001"
		_render())
	head.add_child(back)
	head.add_child(_label("Chat liên minh — %s" % String(mine.get("name", "")),
			17, GOLD_TXT, true))
	_chat_box.add_child(head)
	var card := _card(12)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_box.add_child(card)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(_chat_scroll)
	_render_chat_lines()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_chat_input = _field("Nhắn cho liên minh…")
	_chat_input.max_length = 200
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_chat_input)
	var send := _button("Gửi", true, false, 84)
	var do_send := func() -> void:
		var t := _chat_input.text.strip_edges()
		if t == "":
			return
		_chat_input.text = ""
		Net.alliance_chat(t)
	send.pressed.connect(do_send)
	_chat_input.text_submitted.connect(func(_t: String) -> void: do_send.call())
	row.add_child(send)
	_chat_box.add_child(row)
	_scroll_chat_bottom()
	_chat_input.grab_focus()


func _render_chat_lines() -> void:
	if _chat_scroll == null or not is_instance_valid(_chat_scroll):
		return
	for c in _chat_scroll.get_children():
		_chat_scroll.remove_child(c)
		c.queue_free()
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 5)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_scroll.add_child(lv)
	if Net.alliance_chat_lines.is_empty():
		lv.add_child(_label_wrap("Chưa có tin nhắn nào — hãy chào mọi người!", 13, MUTED))
		return
	var my_name := Net.display_name()
	for ln in Net.alliance_chat_lines:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		var nm := String(ln.get("name", "?"))
		hb.add_child(_label(nm + ":", 13,
				Color(0.45, 0.9, 0.6) if nm == my_name else GOLD_TXT, true))
		hb.add_child(_label_wrap(String(ln.get("text", "")), 13, PAPER))
		lv.add_child(hb)


func _scroll_chat_bottom() -> void:
	if _chat_scroll == null or not is_instance_valid(_chat_scroll):
		return
	await get_tree().process_frame
	if _chat_scroll != null and is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = 1 << 30


# ------------------------------------------------------------ not joined

func _build_join() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(vb)
	vb.add_child(_intro_card(true))
	if _create_open:
		vb.add_child(_create_card())
	# Invites addressed to me live above the browser.
	if not Net.alliance_invites.is_empty():
		vb.add_child(_section("LỜI MỜI VÀO LIÊN MINH"))
		for inv in Net.alliance_invites:
			vb.add_child(_invite_row(inv))
	# Search row.
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	var search := _field("Tìm liên minh theo tên…", _search_text)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t: String) -> void: _search_text = t)
	search.text_submitted.connect(func(t: String) -> void:
		_search_text = t.strip_edges()
		Net.alliance_request_list(_search_text))
	srow.add_child(search)
	var find := _button("Tìm", false, false, 84)
	find.pressed.connect(func() -> void:
		_search_text = search.text.strip_edges()
		Net.alliance_request_list(_search_text))
	srow.add_child(find)
	vb.add_child(srow)
	vb.add_child(_section("LIÊN MINH ĐANG TUYỂN", "· %d liên minh" % Net.alliance_rows.size()))
	var card := _card(12)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lv)
	if Net.alliance_rows.is_empty():
		lv.add_child(_label_wrap("Chưa có liên minh nào — hãy lập liên minh đầu tiên!",
				13, MUTED))
	for rowd in Net.alliance_rows:
		lv.add_child(_join_row(rowd))
	vb.add_child(_label("Mỗi tài khoản chỉ thuộc một liên minh. Góp điểm cho liên minh "
			+ "bằng cách đấu trận: tham gia +10, thắng +30.", 12, DIM))


func _create_card() -> PanelContainer:
	var card := _card(14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	vb.add_child(_section("TẠO LIÊN MINH MỚI"))
	var name_edit := _field("Tên liên minh (3–24 ký tự)…")
	name_edit.max_length = 24
	vb.add_child(name_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 4)
	bcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bcol.add_child(_label("Màu khiên", 13, MUTED))
	var badge_opt := _option(BADGE_ORDER.map(func(id: String) -> String:
			return "Khiên " + String(BADGE_NAMES[id])), 0)
	badge_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bcol.add_child(badge_opt)
	row.add_child(bcol)
	var mcol := VBoxContainer.new()
	mcol.add_theme_constant_override("separation", 4)
	mcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mcol.add_child(_label("Tuyển thành viên", 13, MUTED))
	var mode_opt := _option(["Mở — vào ngay không cần duyệt", "Xin vào — duyệt đơn"], 1)
	mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mcol.add_child(mode_opt)
	row.add_child(mcol)
	vb.add_child(row)
	var desc_edit := _field("Mô tả ngắn (không bắt buộc)…")
	desc_edit.max_length = 120
	vb.add_child(desc_edit)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	var create := _button("Tạo liên minh", true, false, 160)
	create.pressed.connect(func() -> void:
		var nm := name_edit.text.strip_edges()
		if nm.length() < 3:
			_show_status("Tên liên minh phải có ít nhất 3 ký tự.")
			return
		Net.alliance_create(nm, String(BADGE_ORDER[badge_opt.selected]),
				"open" if mode_opt.selected == 0 else "request",
				desc_edit.text.strip_edges())
		_create_open = false)
	brow.add_child(create)
	var cancel := _button("Huỷ", false, false, 100)
	cancel.pressed.connect(func() -> void:
		_create_open = false
		_sig = "\u0001"
		_render())
	brow.add_child(cancel)
	vb.add_child(brow)
	vb.add_child(_label_wrap("Tạo liên minh miễn phí. Tên liên minh là duy nhất trên toàn server.",
			12, DIM))
	return card


func _invite_row(inv: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _sb(Color(0.07, 0.10, 0.17, 0.55), 10,
			Color(0.98, 0.8, 0.35, 0.55), 1))
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 12)
	inner.add_theme_constant_override("margin_right", 12)
	inner.add_theme_constant_override("margin_top", 8)
	inner.add_theme_constant_override("margin_bottom", 8)
	row.add_child(inner)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	inner.add_child(hb)
	hb.add_child(_badge(String(inv.get("badge", "red")), 50))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(_label(String(inv.get("name", "")), 16, GOLD_TXT, true))
	nv.add_child(_label("Cấp %d · %d/%d thành viên · %s mời bạn" % [
			int(inv.get("level", 1)), int(inv.get("members", 0)), 30,
			String(inv.get("by_name", ""))], 12, MUTED))
	hb.add_child(nv)
	var id := String(inv.get("id", ""))
	var ok := _button("Đồng ý", true, false, 92)
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void: Net.alliance_accept_invite(id))
	hb.add_child(ok)
	var no := _button("Từ chối", false, false, 92)
	no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	no.pressed.connect(func() -> void: Net.alliance_decline_invite(id))
	hb.add_child(no)
	return row


func _join_row(rowd: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _sb(Color(0.07, 0.10, 0.17, 0.55), 10, PANEL_LINE, 1))
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 12)
	inner.add_theme_constant_override("margin_right", 12)
	inner.add_theme_constant_override("margin_top", 8)
	inner.add_theme_constant_override("margin_bottom", 8)
	row.add_child(inner)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	inner.add_child(hb)
	hb.add_child(_badge(String(rowd.get("badge", "red")), 50))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(_label(String(rowd.get("name", "")), 16, GOLD_TXT, true))
	nv.add_child(_label("Cấp %d · %d/%d thành viên · Hội trưởng: %s" % [
			int(rowd.get("level", 1)), int(rowd.get("members", 0)),
			int(rowd.get("cap", 30)), String(rowd.get("leader_name", ""))], 12, MUTED))
	nv.add_child(_label("Tuyển thành viên: Mở — vào ngay" if String(rowd.get("mode", "")) == "open"
			else "Tuyển thành viên: Duyệt đơn xin vào", 12, DIM))
	hb.add_child(nv)
	var id := String(rowd.get("id", ""))
	var b: Button
	if bool(rowd.get("full", false)):
		b = _button("Đã đầy", false, false, 104)
		b.disabled = true
	elif bool(rowd.get("requested", false)):
		b = _button("Đã gửi · Huỷ", false, false, 118)
		b.pressed.connect(func() -> void:
			Net.alliance_cancel_request(id)
			_show_status("Đã huỷ đơn xin vào."))
	else:
		b = _button("Vào ngay" if String(rowd.get("mode", "")) == "open" else "Xin vào",
				true, false, 104)
		b.pressed.connect(func() -> void:
			Net.alliance_apply(id, "")
			_show_status("Đã gửi đơn — chờ Hội trưởng/Phó duyệt." if String(rowd.get("mode", "")) != "open"
					else "Đã gia nhập liên minh!"))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(b)
	return row
