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
const FA_BULLHORN := 0xF0A1
const FA_TASKS := 0xF0AE

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

# Badge model (17e addendum): icon 1..10 + colour 0..7 (slot
# colours) — see scripts/ally_badge.gd (AllyBadge) and the
# server's validBadgeIconColor. The 17a shield-colour strings
# are gone from the wire.
const ROLE_NAMES := {"leader": "Hội trưởng", "deputy": "Phó", "member": "Thành viên"}

var game = null # Main (duck-typed)

var _body: VBoxContainer
var _status: Label
var _poll := 0.0
var _tab := "members"
var _sig := "\u0001" # payload signature: rebuild only on change
var _search_text := ""
var _create_open := false
var _create_preset: Dictionary = {}
var _invite_open := false
var _settings_open := false
var _notice_open := false # 17b notice editor card
var _member_sort := "week" # 17b: "week" | "level" | "recent"
var _detail_user := "" # 17b: member-detail card target ("" = closed)
var _chat_open := false
var _arm := "" # two-tap confirm key ("leave" / "disband" / "transfer:<user>")
var _arm_at := 0
var _chat_box: VBoxContainer = null
var _chat_scroll: ScrollContainer = null
var _chat_input: LineEdit = null
var _fa_font: Font = null
var _status_msg := "" # last action/error line; reapplied after every rebuild


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
	Net.chat_received.connect(func(scope: String, _f: int, _n: String, _t: String, _tag: String, _bub: String) -> void:
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
	_notice_open = false
	_detail_user = ""
	_member_sort = "week"
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


## 17c: button stylebox with EXPLICIT content margins. A
## code-created StyleBoxFlat leaves its content margins unset
## (-1) and Godot then falls back to the BORDER width as the
## margin — so the dark buttons (1px border) laid their text
## out in a box 2px smaller per axis than the gold ones (0px
## border): the active tab's padding genuinely differed from
## the inactive tabs' (measured on the 17b captures, probe in
## tests/probe_tabgeom2.gd). Explicit margins make every state
## geometrically identical. The vertical pair is 0/2 instead
## of 1/1 — same total, centre 1px higher: the tab font's line
## box centres the ink ~1px BELOW the pill centre (measured
## ink centroid dy +0.7..+1.2px), so the ink now lands centred.
func _btn_sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := _sb(bg, radius, border, bw)
	s.content_margin_left = 1
	s.content_margin_right = 1
	s.content_margin_top = 0
	s.content_margin_bottom = 2
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
		b.add_theme_stylebox_override("normal", _btn_sb(Color(0.98, 0.8, 0.35), 8))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(1.0, 0.86, 0.45), 8))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.88, 0.7, 0.28), 8))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	elif danger:
		b.add_theme_stylebox_override("normal", _btn_sb(BTN_BG, 8, Color(0.98, 0.5, 0.45, 0.55), 1))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(0.2, 0.2, 0.3), 8, Color(0.98, 0.5, 0.45, 0.8), 1))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.1, 0.12, 0.2), 8, Color(0.98, 0.5, 0.45), 1))
		b.add_theme_color_override("font_color", RED)
		b.add_theme_color_override("font_hover_color", RED)
	else:
		b.add_theme_stylebox_override("normal", _btn_sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(0.18, 0.22, 0.32), 8, Color(1, 0.85, 0.4, 0.6), 1))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.09, 0.11, 0.19), 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_color_override("font_color", PAPER)
		b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_stylebox_override("disabled", _btn_sb(Color(1, 1, 1, 0.03), 8, Color(1, 1, 1, 0.10), 1))
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
	# 17c: vertical pair 0.5/3.5 instead of 2/2 — same total
	# height, content centre 1.5px higher: at this font size
	# the label ink measured ~1.5px low in the pill (17b
	# captures), it now lands centred.
	s.content_margin_top = 0.5
	s.content_margin_bottom = 3.5
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


## A field stylebox with REAL text padding (owner order
## 2026-11-12: with content margins unset Godot falls back
## to the border width and text renders flush against the
## frame — every field in this screen pads L/R 12).
func _field_sb(border: Color) -> StyleBoxFlat:
	var s := _sb(FIELD_BG, 8, border, 1)
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s


func _field(placeholder: String, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(0, 38)
	e.add_theme_font_size_override("font_size", 14)
	e.add_theme_color_override("font_color", PAPER)
	e.add_theme_color_override("font_placeholder_color", DIM)
	e.add_theme_stylebox_override("normal", _field_sb(PANEL_LINE))
	e.add_theme_stylebox_override("focus", _field_sb(GOLD))
	return e


func _option(items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = selected
	o.custom_minimum_size = Vector2(0, 38)
	o.add_theme_font_size_override("font_size", 14)
	o.add_theme_color_override("font_color", PAPER)
	# Same text-padding rule as the fields (L/R 12) — the
	# dropdown label must not sit flush against the frame.
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := _sb(bg, 8, border, 1)
		s.content_margin_left = 12
		s.content_margin_right = 12
		return s
	o.add_theme_stylebox_override("normal", mk.call(BTN_BG, Color(1, 0.85, 0.4, 0.35)))
	o.add_theme_stylebox_override("hover", mk.call(Color(0.18, 0.22, 0.32), Color(1, 0.85, 0.4, 0.6)))
	o.add_theme_stylebox_override("pressed", mk.call(BTN_BG, Color(1, 0.85, 0.4, 0.35)))
	return o


func _section(text: String, extra := "") -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(_label(text, 15, GOLD_TXT, true))
	if extra != "":
		hb.add_child(_label(extra, 13, DIM))
	return hb


## The alliance badge of a wire row: the FLAG (17f §1).
func _badge_of(row: Dictionary, px: int) -> Control:
	var tr := AllyBadge.make(int(row.get("badge_icon", 1)),
			int(row.get("badge_color", 0)), px)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return tr


## Icon + colour badge picker (create form + leader
## settings). The choice lives in `state` ({"icon", "color"});
## taps repaint the preview, grid rings and swatch rings IN
## PLACE — no _render, so sibling form fields keep drafts.
## 17f §2 tightening: grid cells are a FIXED 50px, swatches
## a FIXED 32px (6px gaps — never expand-fill), and the
## preview is the FLAG at preview_px height.
func _badge_picker(state: Dictionary, preview_px: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var prev := AllyBadge.make(int(state.get("icon", 1)),
			int(state.get("color", 0)), preview_px)
	pv.add_child(prev)
	var pname := _label("", 12, GOLD_TXT, true)
	pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pname)
	box.add_child(pv)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 5)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_label("Biểu tượng", 12, MUTED))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	var cells: Array = []
	for i in range(1, 11):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(50, 50)
		var tb := TextureButton.new()
		tb.texture_normal = AllyBadge.icon_texture(i)
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var idx := i
		tb.pressed.connect(func() -> void:
			state["icon"] = idx)
		cell.add_child(tb)
		grid.add_child(cell)
		cells.append(cell)
	right.add_child(_label("Màu huy hiệu", 12, MUTED))
	var swrow := HBoxContainer.new()
	swrow.add_theme_constant_override("separation", 6)
	right.add_child(swrow)
	var swatches: Array = []
	for c in 8:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(32, 32)
		sw.focus_mode = Control.FOCUS_NONE
		var ci := c
		sw.pressed.connect(func() -> void:
			state["color"] = ci)
		swrow.add_child(sw)
		swatches.append(sw)
	box.add_child(right)
	var refresh := func() -> void:
		var icon := AllyBadge.icon_id(int(state.get("icon", 1)))
		var col := AllyBadge.color_of(int(state.get("color", 0)))
		prev.set_badge(icon, int(state.get("color", 0)))
		pname.text = AllyBadge.icon_name(icon)
		for j in cells.size():
			var cell2: PanelContainer = cells[j]
			var on := (j + 1) == icon
			cell2.add_theme_stylebox_override("panel", _sb(
					Color(0.10, 0.13, 0.22, 0.9), 8,
					GOLD if on else PANEL_LINE, 2 if on else 1))
			var tb2: TextureButton = cell2.get_child(0)
			tb2.modulate = col
		for j in swatches.size():
			var sw2: Button = swatches[j]
			var on2 := j == int(state.get("color", 0))
			var sbx := _sb(TeamColors.ui_color(j), 8,
					GOLD if on2 else PANEL_LINE, 2 if on2 else 1)
			sw2.add_theme_stylebox_override("normal", sbx)
			sw2.add_theme_stylebox_override("hover", sbx)
			sw2.add_theme_stylebox_override("pressed", sbx)
	for i in range(1, 11):
		var tb3: TextureButton = (cells[i - 1] as PanelContainer).get_child(0)
		tb3.pressed.connect(refresh)
	for c in 8:
		(swatches[c] as Button).pressed.connect(refresh)
	refresh.call()
	return box


func _avatar(avatar_id: String, px: int, user := "") -> TextureRect:
	var t := TextureRect.new()
	# 17d: member rows carry ACCOUNT avatar ids (anime set).
	# 17f §5: a "custom" id resolves through the owner-aware
	# path when the row's account is known.
	t.texture = Avatars.texture_for_user(avatar_id, user) \
			if user != "" else Avatars.texture_for(avatar_id)
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
			_settings_open, _notice_open, _member_sort, _detail_user,
			Net.friends_rows, _arm, Net.account_name])
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
	# The column scrolls: with tag + crown + notice the profile
	# card outgrows 720p, and the action buttons must stay
	# reachable (when everything fits, nothing changes).
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(372, 0)
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size = Vector2(372, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)
	left.add_child(_profile_card(mine))
	left.add_child(_actions_card(mine))
	if _invite_open and String(mine.get("my_role", "")) in ["leader", "deputy"]:
		left.add_child(_invite_card(mine))
	if _notice_open and String(mine.get("my_role", "")) in ["leader", "deputy"]:
		left.add_child(_notice_card(mine))
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
	# 17f §4: the Bài viết tab (alliance posts).
	tabs.add_child(_tab_btn("posts", "Bài viết"))
	var req_label := "Yêu cầu"
	if req_count > 0:
		req_label += " (%d)" % req_count
	tabs.add_child(_tab_btn("requests", req_label))
	tabs.add_child(_tab_btn("quests", "Nhiệm vụ"))
	tabs.add_child(_tab_btn("activity", "Hoạt động"))
	if _detail_user != "":
		right.add_child(_member_detail_card(mine))
	if _tab == "posts":
		# The posts surface carries its own composer + scroll;
		# it fills the tab area directly (no card wrapper).
		# Moderation (delete others' posts) shows for the
		# leader + deputies; the server enforces it too.
		var pp := PostPanel.new()
		pp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right.add_child(pp)
		pp.setup("alliance",
				String(mine.get("my_role", "")) in ["leader", "deputy"])
		pp.refresh()
		return
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
		"quests":
			_fill_quests(cv, mine)
		"activity":
			_fill_activity(cv, mine)
		_:
			_fill_members(cv, mine)


func _tab_btn(id: String, text: String) -> Button:
	var b := _button(text)
	# 17c: the four tabs share the row evenly — equal widths,
	# equal 8px gaps, and the row's edges flush with the
	# content card below (before, the pills huddled at the
	# left at natural widths over a full-width card).
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _tab == id:
		# Same construction as the dark tabs (1px border +
		# _btn_sb margins) so the active state changes only
		# colours, never the label's box. The border is a deep
		# gold edge shade, invisible against the gold fill.
		var edge := Color(0.72, 0.52, 0.15)
		b.add_theme_stylebox_override("normal", _btn_sb(Color(0.98, 0.8, 0.35), 8, edge, 1))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(1.0, 0.86, 0.45), 8, edge, 1))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.88, 0.7, 0.28), 8, edge, 1))
		b.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.02))
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
	cc.add_child(_badge_of(mine, 108))
	pv.add_child(cc)
	var nm := _label(String(mine.get("name", "")), 21, GOLD_TXT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(nm)
	# 17b: the alliance tag under the name.
	if String(mine.get("tag", "")) != "":
		var tg := _label("[%s]" % String(mine.get("tag", "")), 13, GOLD)
		tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(tg)
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
	# 17b: last week's champion carries the crown marker.
	if bool(mine.get("champion", false)):
		var crowns := HBoxContainer.new()
		crowns.alignment = BoxContainer.ALIGNMENT_CENTER
		crowns.add_theme_constant_override("separation", 6)
		crowns.add_child(_fa(FA_CROWN, 13, GOLD_TXT))
		crowns.add_child(_label("Vô địch tuần trước", 13, GOLD_TXT, true))
		pv.add_child(crowns)
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
	# 17b: the notice board sits at the card's foot.
	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _sb(Color(1, 1, 1, 0.08), 1))
	pv.add_child(sep2)
	var nhead := HBoxContainer.new()
	nhead.add_theme_constant_override("separation", 6)
	nhead.add_child(_fa(FA_BULLHORN, 12, GOLD_TXT))
	nhead.add_child(_label("THÔNG BÁO", 12, GOLD_TXT, true))
	pv.add_child(nhead)
	var notice := String(mine.get("notice", ""))
	if notice != "":
		pv.add_child(_label_wrap(notice, 13, PAPER))
		if String(mine.get("notice_by", "")) != "":
			pv.add_child(_label("— %s · %s" % [String(mine.get("notice_by", "")),
					_ago(int(mine.get("notice_at", 0)))], 11, DIM))
	else:
		pv.add_child(_label_wrap("Chưa có thông báo nào.", 12, DIM))
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
			_notice_open = false
			if _invite_open:
				Net.request_friends() # 17b: feed the friend picker
			_sig = "\u0001"
			_render())
		vb.add_child(inv)
	var chatb := _icon_btn("Chat liên minh", FA_COMMENTS)
	# 17e: alliance chat MOVED to the chat hub (the owner's
	# "toàn bộ chat gom về một chỗ") — this button opens the
	# hub on its Liên minh tab. The internal view below stays
	# only for the 17b capture harnesses.
	chatb.pressed.connect(func() -> void:
		if game != null and game.has_method("home_open_chat_hub"):
			game.home_open_chat_hub("alliance")
		else:
			_open_chat(mine))
	vb.add_child(chatb)
	if role in ["leader", "deputy"]:
		var notb := _icon_btn("Thông báo liên minh", FA_BULLHORN)
		notb.pressed.connect(func() -> void:
			_notice_open = not _notice_open
			_invite_open = false
			_settings_open = false
			_sig = "\u0001"
			_render())
		vb.add_child(notb)
	if role == "leader":
		var setb := _icon_btn("Cài đặt liên minh", FA_GEAR)
		setb.pressed.connect(func() -> void:
			_settings_open = not _settings_open
			_invite_open = false
			_notice_open = false
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
	vb.add_child(_label_wrap("Người được mời cũng nhận một thư trong Hộp thư và trả lời "
			+ "ở trang Liên minh của họ.", 12, DIM))
	# 17b friend picker: tap a friend to invite them through
	# the same server invite path (username resolution).
	vb.add_child(_section("CHỌN TỪ BẠN BÈ"))
	if Net.friends_rows.is_empty():
		vb.add_child(_label_wrap("Chưa có bạn bè nào trong danh sách — hãy thêm bạn "
				+ "ở trang Bạn bè, hoặc mời bằng tên ở trên.", 12, DIM))
	for f in Net.friends_rows:
		vb.add_child(_friend_pick_row(f, mine, ally_id))
	return card


## One friend-picker row: avatar, name (+ their [TAG] if any),
## online state, and a Mời button (disabled for yourself and
## for members of THIS alliance).
func _friend_pick_row(f: Dictionary, mine: Dictionary, ally_id: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(_avatar(String(f.get("avatar_id", "knight")), 32, String(f.get("user", ""))))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(_label(Net.ally_disp(String(f.get("display_name",
			String(f.get("user", "?")))), String(f.get("ally_tag", ""))), 13, PAPER))
	var online := bool(f.get("online", false))
	nv.add_child(_label("Trực tuyến" if online else "Ngoại tuyến", 11,
			Color(0.45, 0.85, 0.55) if online else DIM))
	hb.add_child(nv)
	var fuser := String(f.get("user", ""))
	var already := false
	for mem in mine.get("members", []):
		if String(mem.get("user", "")) == fuser:
			already = true
	var b := _small_btn("Đã ở liên minh" if already else "Mời")
	b.disabled = already or fuser == Net.account_name
	if not b.disabled:
		b.pressed.connect(func() -> void:
			Net.alliance_invite(ally_id, fuser)
			_show_status("Đã gửi lời mời tới %s." % String(f.get("display_name", fuser))))
	hb.add_child(b)
	return hb


## 17b notice editor (leader/deputy): one short line, max 140
## characters, pushed live to every member's screen.
func _notice_card(mine: Dictionary) -> PanelContainer:
	var card := _card(12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	vb.add_child(_section("THÔNG BÁO LIÊN MINH"))
	var edit := _field("Thông báo cho cả liên minh…", String(mine.get("notice", "")))
	edit.max_length = 140
	vb.add_child(edit)
	var ally_id := String(mine.get("id", ""))
	var save := _button("Đăng thông báo", true)
	save.pressed.connect(func() -> void:
		Net.alliance_notice(ally_id, edit.text.strip_edges())
		_notice_open = false
		_show_status("Đã cập nhật thông báo liên minh."))
	vb.add_child(save)
	vb.add_child(_label_wrap("Tối đa 140 ký tự. Mọi thành viên đang mở trang "
			+ "Liên minh sẽ thấy thông báo mới ngay.", 12, DIM))
	return card


func _settings_card(mine: Dictionary) -> PanelContainer:
	var card := _card(12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	vb.add_child(_section("CÀI ĐẶT LIÊN MINH"))
	# 17b: the alliance tag (2–5 letters/digits, unique).
	vb.add_child(_label("Tag liên minh (2–5 ký tự chữ/số)", 13, MUTED))
	var tag_edit := _field("VD: SL123", String(mine.get("tag", "")))
	tag_edit.max_length = 5
	vb.add_child(tag_edit)
	vb.add_child(_label("Huy hiệu liên minh", 13, MUTED))
	var badge_state := {"icon": int(mine.get("badge_icon", 1)),
			"color": int(mine.get("badge_color", 0))}
	vb.add_child(_badge_picker(badge_state, 76))
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
		Net.alliance_settings(ally_id, tag_edit.text.strip_edges(),
				int(badge_state["icon"]), int(badge_state["color"]),
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


const MEMBER_SORTS: Array = ["week", "level", "recent"]
const MEMBER_SORT_NAMES: Array = ["Đóng góp tuần", "Cấp", "Hoạt động gần nhất"]


func _fill_members(cv: VBoxContainer, mine: Dictionary) -> void:
	# 17b sort bar: Đóng góp tuần · Cấp · Hoạt động gần nhất.
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	srow.add_child(_label("Sắp xếp:", 13, MUTED))
	var opt := _option(MEMBER_SORT_NAMES, maxi(0, MEMBER_SORTS.find(_member_sort)))
	opt.custom_minimum_size = Vector2(210, 34)
	opt.add_theme_font_size_override("font_size", 13)
	opt.item_selected.connect(func(idx: int) -> void:
		_member_sort = String(MEMBER_SORTS[idx])
		_sig = "\u0001"
		_render())
	srow.add_child(opt)
	cv.add_child(srow)
	cv.add_child(_member_header())
	var my_role := String(mine.get("my_role", ""))
	var ally_id := String(mine.get("id", ""))
	var members: Array = (mine.get("members", []) as Array).duplicate()
	match _member_sort:
		"level":
			members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if int(a.get("level", 1)) != int(b.get("level", 1)):
					return int(a.get("level", 1)) > int(b.get("level", 1))
				return int(a.get("week", 0)) > int(b.get("week", 0)))
		"recent":
			members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var oa := bool(a.get("online", false))
				var ob := bool(b.get("online", false))
				if oa != ob:
					return oa
				return int(a.get("seen", 0)) > int(b.get("seen", 0)))
		_:
			members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("week", 0)) > int(b.get("week", 0)))
	for mem in members:
		cv.add_child(_member_row(mem, my_role, ally_id))


## 17b member detail card: everything the alliance record
## already knows about one member — level, role, join date,
## this week's contribution + banked matches/wins, and their
## last-online state. No extra data is collected for it.
func _member_detail_card(mine: Dictionary) -> PanelContainer:
	var mem: Dictionary = {}
	for m in mine.get("members", []):
		if String(m.get("user", "")) == _detail_user:
			mem = m
			break
	var card := _card(12, 2)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	card.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_avatar(String(mem.get("avatar", "knight")), 44, String(mem.get("user", ""))))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(_label(String(mem.get("name", _detail_user)), 16, PAPER, true))
	nv.add_child(_label("Cấp %d" % int(mem.get("level", 1)), 12, MUTED))
	head.add_child(nv)
	head.add_child(_role_pill(String(mem.get("role", "member"))))
	var close_b := _small_btn("Đóng")
	close_b.custom_minimum_size = Vector2(64, 30)
	close_b.pressed.connect(func() -> void:
		_detail_user = ""
		_sig = "\u0001"
		_render())
	head.add_child(close_b)
	vb.add_child(head)
	if mem.is_empty():
		vb.add_child(_label_wrap("Thành viên này không còn trong liên minh.", 13, MUTED))
		return card
	vb.add_child(_stat_row("Ngày gia nhập", _date_str(int(mem.get("joined_at", 0)))))
	vb.add_child(_stat_row("Đóng góp tuần này", _fmt(int(mem.get("week", 0)))))
	vb.add_child(_stat_row("Trận đã đấu tuần này", str(int(mem.get("week_games", 0)))))
	vb.add_child(_stat_row("Trận thắng tuần này", str(int(mem.get("week_wins", 0)))))
	var online := bool(mem.get("online", false))
	vb.add_child(_stat_row("Trạng thái", "Đang trực tuyến" if online
			else "Hoạt động " + _ago(int(mem.get("seen", 0)))))
	return card


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
	hb.add_child(_avatar(String(mem.get("avatar", "knight")), 40, String(mem.get("user", ""))))
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
	# 17b: every row opens the member detail card.
	var detail := _small_btn("Chi tiết")
	detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail.pressed.connect(func() -> void:
		_detail_user = String(mem.get("user", ""))
		_sig = "\u0001"
		_render())
	hb.add_child(detail)
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
	hb.add_child(_avatar(String(rq.get("avatar", "knight")), 40, String(rq.get("user", ""))))
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


## 17b weekly quests tab: three collective quests fed by the
## members' banked matches (server-side). Completing one
## grants alliance XP + weekly points, once per week; the
## slate resets every Monday.
func _fill_quests(cv: VBoxContainer, mine: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 7)
	head.add_child(_fa(FA_TASKS, 14, GOLD_TXT))
	head.add_child(_label("NHIỆM VỤ TUẦN CỦA LIÊN MINH", 13, GOLD_TXT, true))
	cv.add_child(head)
	cv.add_child(_label_wrap("Mọi trận ghi sổ của thành viên đều tính chung. "
			+ "Hoàn thành để nhận XP và điểm tuần cho cả liên minh — "
			+ "nhiệm vụ làm mới vào thứ Hai hằng tuần.", 12, DIM))
	var quests: Array = mine.get("quests", [])
	if quests.is_empty():
		cv.add_child(_label_wrap("Chưa có nhiệm vụ nào.", 13, MUTED))
		return
	for q in quests:
		cv.add_child(_quest_row(q))


func _quest_row(q: Dictionary) -> PanelContainer:
	var done := bool(q.get("done", false))
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _sb(Color(0.07, 0.10, 0.17, 0.55), 10,
			Color(0.98, 0.8, 0.35, 0.55) if done else PANEL_LINE, 1))
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 12)
	inner.add_theme_constant_override("margin_right", 12)
	inner.add_theme_constant_override("margin_top", 9)
	inner.add_theme_constant_override("margin_bottom", 9)
	row.add_child(inner)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	inner.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var lb := _label(String(q.get("label", "")), 15, PAPER, true)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lb)
	if done:
		top.add_child(_pill("Đã hoàn thành", Color(0.98, 0.8, 0.35), Color(0.1, 0.08, 0.02)))
	top.add_child(_label("%s / %s" % [_fmt(int(q.get("prog", 0))),
			_fmt(int(q.get("target", 1)))], 14, GOLD_TXT if done else PAPER))
	vb.add_child(top)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(1, int(q.get("target", 1)))
	bar.value = mini(int(q.get("prog", 0)), int(q.get("target", 1)))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", _sb(Color(0.05, 0.06, 0.10, 0.9), 6))
	bar.add_theme_stylebox_override("fill", _sb(
			Color(0.98, 0.8, 0.35) if done else Color(0.85, 0.65, 0.20), 6))
	vb.add_child(bar)
	vb.add_child(_label("Thưởng: +%d XP liên minh · +%d điểm tuần" % [
			int(q.get("xp", 0)), int(q.get("pts", 0))], 12, DIM))
	return row


func _fill_activity(cv: VBoxContainer, mine: Dictionary) -> void:
	# 17b: past weekly champions (the crown history) sit
	# above the activity log.
	var champs: Array = mine.get("champions", [])
	if not champs.is_empty():
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 7)
		head.add_child(_fa(FA_CROWN, 13, GOLD_TXT))
		head.add_child(_label("VÔ ĐỊCH CÁC TUẦN TRƯỚC", 13, GOLD_TXT, true))
		cv.add_child(head)
		for c in champs:
			var wk := String(c.get("week", ""))
			var parts := wk.split("-")
			var wtxt := wk
			if parts.size() == 3:
				wtxt = "%s/%s/%s" % [parts[2], parts[1], parts[0]]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(_label_wrap("Tuần %s — %s" % [wtxt,
					String(c.get("name", ""))], 13, PAPER))
			row.add_child(_label("%s điểm" % _fmt(int(c.get("points", 0))), 12, GOLD_TXT))
			cv.add_child(row)
		var sep := HSeparator.new()
		sep.add_theme_stylebox_override("separator", _sb(Color(1, 1, 1, 0.08), 1))
		cv.add_child(sep)
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
		# 17b: [TAG] before the sender's name.
		hb.add_child(_label(Net.ally_disp(nm, String(ln.get("tag", ""))) + ":", 13,
				Color(0.45, 0.9, 0.6) if nm == my_name else GOLD_TXT, true))
		# 17d (§7.2B): the sender's equipped bubble style also
		# skins their alliance-chat lines (text colour).
		var tcol := PAPER
		var bub := String(ln.get("bubble", "mac_dinh"))
		if bub != "mac_dinh" and ChatBubbles.STYLES.has(bub):
			tcol = ChatBubbles.STYLES[bub]["text"]
		# 17e: voice lines + emoticon tokens render rich here
		# too (never as raw token text).
		if bool(ln.get("voice", false)):
			hb.add_child(_label_wrap("Tin nhắn thoại • %d giây" % int(ceil(float(ln.get("dur", 0.0)))), 13, MUTED))
		else:
			var body := Emotes.make_rich(String(ln.get("text", "")), 13, tcol)
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(body)
		lv.add_child(hb)


func _scroll_chat_bottom() -> void:
	if _chat_scroll == null or not is_instance_valid(_chat_scroll):
		return
	await get_tree().process_frame
	if _chat_scroll != null and is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = 1 << 30


# ------------------------------------------------------------ capture hooks

## Capture-harness helpers (17b shots): jump straight to a
## tab, optionally with a member's detail card open, or into
## the chat view. Not used by normal play.
func shot_set_tab(tab: String, member_user := "") -> void:
	_tab = tab
	_detail_user = member_user
	_sig = "\u0001"
	_render()


func shot_open_chat() -> void:
	if not Net.alliance_mine.is_empty():
		_open_chat(Net.alliance_mine)


## Capture hook: open the create-alliance form (badge picker),
## optionally with a preset badge selection for the shot.
func shot_open_create(icon := 1, color_idx := 0) -> void:
	_create_open = true
	_create_preset = {"icon": icon, "color": color_idx}
	_sig = "\u0001"
	_render()


# ------------------------------------------------------------ not joined

func _build_join() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(vb)
	vb.add_child(_intro_card(true))
	if _create_open:
		# 17f §2: the create card is CENTRED at max ~900px
		# instead of stretching the full page width.
		var center := CenterContainer.new()
		var ccard := _create_card()
		ccard.custom_minimum_size = Vector2(900, 0)
		center.add_child(ccard)
		vb.add_child(center)
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


## One labelled form field (17f §2): small gold label ABOVE
## the input, tight 3px pairing.
func _labelled_field(text: String, field: Control) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.add_child(_label(text, 12, GOLD_TXT, true))
	vb.add_child(field)
	return vb


func _create_card() -> PanelContainer:
	var card := _card(14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	vb.add_child(_section("TẠO LIÊN MINH MỚI"))
	var badge_state: Dictionary = _create_preset.duplicate() \
			if not _create_preset.is_empty() else {"icon": 1, "color": 0}
	# 17f §2 (owner, on v1: "vẫn chưa đẹp chưa gọn"): the
	# caller centres this card at max ~900px wide; inside,
	# two tightened columns — labelled fields left, the
	# badge studio right, heights balanced (the studio
	# stretches to the fields' height and its picker sits
	# vertically centred).
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	vb.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var name_edit := _field("3–24 ký tự…")
	name_edit.max_length = 24
	left.add_child(_labelled_field("Tên liên minh", name_edit))
	# 17b: the tag is chosen at creation (leader-editable later).
	var tag_edit := _field("2–5 ký tự chữ/số, VD: SL123…")
	tag_edit.max_length = 5
	left.add_child(_labelled_field("Tag", tag_edit))
	var mode_opt := _option(["Mở — vào ngay không cần duyệt", "Xin vào — duyệt đơn"], 1)
	mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_labelled_field("Tuyển thành viên", mode_opt))
	var desc_edit := _field("Mô tả ngắn (không bắt buộc)…")
	desc_edit.max_length = 120
	left.add_child(_labelled_field("Mô tả", desc_edit))
	var studio := PanelContainer.new()
	var ssb := _sb(Color(1, 1, 1, 0.045), 10, Color(1, 0.85, 0.4, 0.35), 1)
	ssb.content_margin_left = 14
	ssb.content_margin_right = 14
	ssb.content_margin_top = 10
	ssb.content_margin_bottom = 10
	studio.add_theme_stylebox_override("panel", ssb)
	studio.custom_minimum_size = Vector2(452, 0)
	cols.add_child(studio)
	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 6)
	studio.add_child(svb)
	svb.add_child(_label("Huy hiệu liên minh", 13, MUTED))
	var sp1 := Control.new()
	sp1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svb.add_child(sp1)
	svb.add_child(_badge_picker(badge_state, 100))
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svb.add_child(sp2)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	var create := _button("Tạo liên minh", true, false, 160)
	create.pressed.connect(func() -> void:
		var nm := name_edit.text.strip_edges()
		if nm.length() < 3:
			_show_status("Tên liên minh phải có ít nhất 3 ký tự.")
			return
		var tg := tag_edit.text.strip_edges()
		if tg.length() < 2:
			_show_status("Tag liên minh phải có 2–5 ký tự (chỉ chữ và số).")
			return
		Net.alliance_create(nm, tg, int(badge_state["icon"]),
				int(badge_state["color"]),
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
	var hint := _label("Tạo miễn phí · Tên và tag là duy nhất trên toàn server",
			12, DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(hint)
	vb.add_child(brow)
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
	hb.add_child(_badge_of(inv, 50))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(_label(Net.ally_disp(String(inv.get("name", "")),
			String(inv.get("tag", ""))), 16, GOLD_TXT, true))
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
	hb.add_child(_badge_of(rowd, 50))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(_label(Net.ally_disp(String(rowd.get("name", "")),
			String(rowd.get("tag", ""))), 16, GOLD_TXT, true))
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
