class_name Lobby
extends CanvasLayer
## Empire Age P4 — multiplayer lobby (glass style, same palette as
## the HUD). Reached from the boot map panel's "Chơi mạng" button.
##
## Menu view: guest name, server address, Tạo phòng (host config =
## the map panel's current biome/layout selection), Vào phòng by
## code. Room view: big room code, player rows (slot / name / team /
## ready / host+you badges), Ready toggle, host-only Start (enabled
## at ≥2 players, all ready), Rời phòng.
##
## All state comes from the Net autoload's signals; this layer owns
## no game state. On match_started it hides and Net.begin_match()
## reloads the scene into the MP match.

const GLASS_BG := Color(0.04, 0.07, 0.13, 0.94)
const BORDER := Color(1, 1, 1, 0.28)
const GOLD := Color(0.85, 0.64, 0.25, 0.95)
const GOLD_TXT := Color(0.96, 0.8, 0.45)
const TXT := Color(0.94, 0.96, 0.99)
const TXT_DIM := Color(0.64, 0.7, 0.8)
const GREEN := Color(0.45, 0.95, 0.5)
const RED := Color(0.98, 0.5, 0.45)
const FIELD_BG := Color(0.02, 0.04, 0.09, 0.9)

var game = null # Main (duck-typed)

var _root: Control
var _menu_box: VBoxContainer
var _room_box: VBoxContainer
var _name_edit: LineEdit
var _addr_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _code_label: Label
var _config_label: Label
var _players_box: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _ready_state: bool = false
var _pending: String = "" # "", "create", "join" — runs once Net connects
var _pending_auth: String = "" # "", "login", "register"
var _signals_bound: bool = false
# P4 stage 2: accounts + lobby chat + leaderboard.
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _auth_box: VBoxContainer
var _auth_info: Label
var _auth_status: Label
var _logout_btn: Button
var _chat_log: RichTextLabel
var _chat_edit: LineEdit
var _lb_data: Array = []
# P4 stage 3: ranked queue + leaderboard mode toggle.
var _ranked_btn: Button
var _ranked_hint: Label
var _mm: MatchmakingScreen
var _queue_since: int = 0
var _queue_normal: bool = false # 13t: the open queue screen is the NORMAL queue
# Stage 5 (13g addendum): the leaderboard is a full-screen board
# (reference restyle) with three tabs and a sticky "my rank"
# footer fed by the server's LeaderboardV2 payload.
var _lb_mode: String = "ranked" # "ranked" | "friends" | "alliance"
var _lb_me: Dictionary = {}
var _lb_root: Control
var _lb_rows_box: VBoxContainer
var _lb_tabs: Dictionary = {}
var _lb_cols: MarginContainer
var _lb_cols_hb: HBoxContainer
var _lb_scroll: ScrollContainer
var _lb_empty_box: CenterContainer
var _lb_empty_inner: VBoxContainer
var _lb_fa_font: Font
var _lb_footer: PanelContainer
var _lb_footer_box: HBoxContainer
var _lb_board_tex: Texture2D
var _lb_gold_tex: Texture2D
var _lb_return_home: bool = false
var _panel_cc: Control
# P4 stage 4: seasonal rank ladder presentation (badge + texts).
var _rank_row: HBoxContainer
var _rank_badge: RankBadge
var _rank_text: Label
var _rank_peak: Label
var _avatar_btns: Dictionary = {} # avatar id -> TextureButton (account block)
var _chars_root: Control # character collection overlay
# 15a custom-match expansion: create form, room browser, host
# config editor + host-power buttons.
var _room_name_edit: LineEdit
var _room_pass_edit: LineEdit
var _public_check: CheckBox
var _obs_check: CheckBox
var _dip_check: CheckBox
var _delay_opt: OptionButton # 15e: spectator delay choice (create form)
var _obs_box: VBoxContainer # 15e: host's per-observer kick rows
var _join_pass_edit: LineEdit
var _browser_box: VBoxContainer
var _browse_search: LineEdit
var _browse_pass_edit: LineEdit
var _browse_rows: VBoxContainer
var _obs_label: Label
var _cfg_box: VBoxContainer
var _cfg_biome_opt: OptionButton
var _cfg_layout_opt: OptionButton
var _cfg_name_edit: LineEdit
var _cfg_public_check: CheckBox
var _cfg_obs_check: CheckBox
var _cfg_dip_check: CheckBox
var _cfg_delay_opt: OptionButton # 15e: spectator delay choice (room config)
var _cfg_pass_edit: LineEdit
var _cfg_pass_touch: CheckBox
var _cfg_populated_key: String = ""


class LbTab:
	extends Control
	signal pressed
	var text := ""
	var active := false
	var _lbl: Label

	func _init(p_text: String) -> void:
		text = p_text
		mouse_filter = Control.MOUSE_FILTER_STOP
		_lbl = Label.new()
		_lbl.text = text
		_lbl.add_theme_font_size_override("font_size", 17)
		_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lbl)
		_apply()

	func set_active(a: bool) -> void:
		active = a
		_apply()
		queue_redraw()

	func _apply() -> void:
		if _lbl != null:
			_lbl.add_theme_color_override("font_color",
					Color(0.16, 0.11, 0.02) if active else Color(0.88, 0.89, 0.94))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var s := 16.0
		var pts := PackedVector2Array([Vector2(s, 2), Vector2(w - 2, 2),
				Vector2(w - s, h - 2), Vector2(2, h - 2)])
		draw_colored_polygon(pts, Color(0.92, 0.7, 0.22) if active
				else Color(0.05, 0.07, 0.15, 0.92))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(1, 0.85, 0.4, 0.55), 1.5)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				pressed.emit()
				accept_event()


class WreathNum:
	extends Control
	var pos: int = 0
	var on_gold: bool = false # #1 sits on the gold bar: darker metal
	var _lbl: Label

	const METALS := [Color(0.98, 0.8, 0.35), Color(0.83, 0.86, 0.92),
			Color(0.87, 0.56, 0.3)]

	func _init(p_pos: int) -> void:
		pos = p_pos
		_lbl = Label.new()
		_lbl.text = str(pos)
		_lbl.add_theme_font_size_override("font_size", 26)
		_lbl.add_theme_color_override("font_color",
				METALS[pos - 1] if pos >= 1 and pos <= 3 else Color(0.92, 0.92, 0.9))
		_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lbl)

	func _metal() -> Color:
		var col: Color = METALS[pos - 1]
		return col.darkened(0.42) if on_gold else col

	func set_on_gold(v: bool) -> void:
		on_gold = v
		if pos >= 1 and pos <= 3:
			_lbl.add_theme_color_override("font_color", _metal())
		queue_redraw()

	# Laurel wreath for the top 3 (model-style): two branches of
	# individual tapered leaves sweep from a tie at the bottom
	# centre up both sides of the number, open at the top. Each
	# leaf is a small diamond laid along an ellipse, tilted
	# outward like real laurel, with a darker centre vein.
	func _wreath_angle(branch: int, t: float) -> float:
		var a := lerpf(PI * 0.5 + 0.40, PI * 1.5 - 0.32, t)
		return PI - a if branch == 1 else a

	func _draw() -> void:
		if pos < 1 or pos > 3:
			return
		var col: Color = _metal()
		var dark := col.darkened(0.38)
		var c := size * 0.5
		var rx := size.x * 0.37
		var ry := size.y * 0.44
		for branch in 2:
			# Stem under the leaves.
			var stem := PackedVector2Array()
			var segs := 16
			for i in segs + 1:
				var a := _wreath_angle(branch, float(i) / float(segs))
				stem.append(c + Vector2(cos(a) * rx, sin(a) * ry))
			draw_polyline(stem, dark, 1.6)
			# Leaves, biggest mid-branch.
			var leaves := 8
			for i in leaves:
				var t := 0.05 + 0.90 * float(i) / float(leaves - 1)
				var a := _wreath_angle(branch, t)
				var base := c + Vector2(cos(a) * rx, sin(a) * ry)
				var tang := Vector2(-sin(a) * rx, cos(a) * ry).normalized()
				if branch == 1:
					tang = -tang
				var out := (base - c).normalized()
				var dir := (tang * 0.82 + out * 0.45).normalized()
				var perp := Vector2(-dir.y, dir.x)
				var len := 10.5 + sin(t * PI) * 4.5
				var wid := 3.4
				var leaf_col := col.lightened(0.10 if i % 2 == 0 else -0.02)
				var tip := base + dir * len
				var mid := base + dir * len * 0.48
				draw_colored_polygon(PackedVector2Array([
						base - perp * wid * 0.35,
						mid + perp * wid,
						tip,
						mid - perp * wid]), leaf_col)
				draw_line(base + dir * 1.5, base + dir * len * 0.8,
						dark, 0.8)
		# Tie berry where the branches meet at the bottom.
		draw_circle(c + Vector2(0, ry + 1.0), 2.4, col.lightened(0.15))
		draw_circle(c + Vector2(0, ry + 1.0), 1.1, dark)


func _sb(border_col: Color, bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.border_color = border_col
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.bg_color = bg
	return s


func _label(text: String, size: int, col: Color = TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_stylebox_override("normal", _sb(BORDER, Color(1, 1, 1, 0.05), 9))
	b.add_theme_stylebox_override("hover", _sb(GOLD, Color(0.85, 0.64, 0.25, 0.16), 9))
	b.add_theme_stylebox_override("pressed", _sb(GOLD, Color(0.85, 0.64, 0.25, 0.28), 9))
	b.add_theme_stylebox_override("disabled", _sb(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.02), 9))
	b.add_theme_color_override("font_disabled_color", TXT_DIM)
	return b


func _field(placeholder: String, def: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = def
	e.custom_minimum_size = Vector2(240, 36)
	e.add_theme_font_size_override("font_size", 15)
	e.add_theme_color_override("font_color", TXT)
	e.add_theme_color_override("font_placeholder_color", TXT_DIM)
	e.add_theme_stylebox_override("normal", _sb(BORDER, FIELD_BG, 8))
	e.add_theme_stylebox_override("focus", _sb(GOLD, FIELD_BG, 8))
	return e


func _check(text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", 14)
	c.add_theme_color_override("font_color", TXT)
	return c


# 15e spectator delay choices: index <-> seconds. The GDD names
# no values; these are the conservative genre-standard defaults
# (chờ Tín chốt — see KE-HOACH 15e).
const DELAY_SECONDS: Array = [0, 60, 120]


func _delay_option() -> OptionButton:
	var o := OptionButton.new()
	o.add_item("Tắt (xem trực tiếp)")
	o.add_item("60 giây")
	o.add_item("120 giây")
	o.add_theme_font_size_override("font_size", 14)
	return o


func _delay_seconds(idx: int) -> int:
	return int(DELAY_SECONDS[clampi(idx, 0, DELAY_SECONDS.size() - 1)])


func _delay_index(sec: int) -> int:
	var i := DELAY_SECONDS.find(sec)
	return i if i >= 0 else 0


## Capture hook: preset the create form's delay selector.
func set_delay_for_test(idx: int) -> void:
	if _delay_opt != null:
		_delay_opt.select(clampi(idx, 0, DELAY_SECONDS.size() - 1))


func setup(p_game) -> void:
	game = p_game
	_build()
	_bind_signals()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_panel_cc = CenterContainer.new()
	_panel_cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel_cc)
	var cc := _panel_cc
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(GOLD, GLASS_BG, 16))
	cc.add_child(panel)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 22)
	mc.add_theme_constant_override("margin_right", 22)
	mc.add_theme_constant_override("margin_top", 18)
	mc.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(mc)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	mc.add_child(outer)
	# No panel heading: the map panel's "Chơi mạng" button is the one
	# place the feature is named (Tín: a repeated title here is dead
	# weight). Content starts directly with the status line.
	_status = _label("", 13, TXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status)
	_build_menu(outer)
	_build_room(outer)
	_build_browser(outer)
	_build_leaderboard_v2()
	_build_characters()
	_build_matchmaking()
	_show_menu()


func _build_menu(parent: VBoxContainer) -> void:
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	parent.add_child(_menu_box)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	_menu_box.add_child(nrow)
	nrow.add_child(_label("Tên:", 15))
	_name_edit = _field("Tên của bạn", "Người chơi")
	nrow.add_child(_name_edit)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	_menu_box.add_child(arow)
	arow.add_child(_label("Máy chủ:", 15))
	_addr_edit = _field("ws://...", Net.DEFAULT_URL)
	arow.add_child(_addr_edit)
	_build_account(_menu_box)
	# 15a create options: display name, password, visibility,
	# observers — the room carries all of it from creation.
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	_menu_box.add_child(rrow)
	rrow.add_child(_label("Tên phòng:", 15))
	_room_name_edit = _field("Tên phòng (hiện ở danh sách phòng)")
	rrow.add_child(_room_name_edit)
	var prow2 := HBoxContainer.new()
	prow2.add_theme_constant_override("separation", 8)
	_menu_box.add_child(prow2)
	prow2.add_child(_label("Mật khẩu:", 15))
	_room_pass_edit = _field("Để trống = không khóa phòng")
	_room_pass_edit.secret = true
	prow2.add_child(_room_pass_edit)
	var crow2 := HBoxContainer.new()
	crow2.add_theme_constant_override("separation", 14)
	crow2.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_child(crow2)
	_public_check = _check("Công khai (hiện ở danh sách phòng)")
	crow2.add_child(_public_check)
	_obs_check = _check("Cho phép người xem")
	crow2.add_child(_obs_check)
	_dip_check = _check("Ngoại giao (liên minh trong trận)")
	crow2.add_child(_dip_check)
	# 15e: the anti-cheat spectator delay, chosen at creation
	# (the host can also change it later in the room config).
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_child(drow)
	drow.add_child(_label("Trì hoãn người xem:", 15))
	_delay_opt = _delay_option()
	drow.add_child(_delay_opt)
	var create_btn := _button("Tạo phòng")
	create_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create_btn.pressed.connect(_on_create_pressed)
	_menu_box.add_child(create_btn)
	var hint := _label("Phòng dùng khu vực + địa hình đang chọn ở panel bản đồ.", 12, TXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(hint)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 8)
	jrow.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_child(jrow)
	_code_edit = _field("Mã phòng (5 ký tự)")
	_code_edit.custom_minimum_size = Vector2(170, 36)
	_code_edit.max_length = 5
	jrow.add_child(_code_edit)
	_join_pass_edit = _field("Mật khẩu")
	_join_pass_edit.custom_minimum_size = Vector2(130, 36)
	_join_pass_edit.secret = true
	jrow.add_child(_join_pass_edit)
	var join_btn := _button("Vào phòng")
	join_btn.custom_minimum_size = Vector2(120, 38)
	join_btn.pressed.connect(_on_join_pressed)
	jrow.add_child(join_btn)
	var obs_btn := _button("Vào xem")
	obs_btn.custom_minimum_size = Vector2(110, 38)
	obs_btn.pressed.connect(_on_observe_pressed)
	jrow.add_child(obs_btn)
	var browse_btn := _button("Danh sách phòng")
	browse_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	browse_btn.pressed.connect(_show_browser)
	_menu_box.add_child(browse_btn)
	var normal_btn := _button("Ghép trận thường")
	normal_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	normal_btn.pressed.connect(_on_normal_pressed)
	_menu_box.add_child(normal_btn)
	_ranked_btn = _button("Đấu xếp hạng")
	_ranked_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ranked_btn.pressed.connect(_on_ranked_pressed)
	_menu_box.add_child(_ranked_btn)
	_ranked_hint = _label("", 12, TXT_DIM)
	_ranked_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(_ranked_hint)
	# Bot play lives in the Custom view now (13t): Đấu Thường on
	# the home panel matchmakes online, so the single-player setup
	# view is reached from here.
	var bot_btn := _button("Đánh với máy")
	bot_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bot_btn.pressed.connect(func() -> void: if game != null: game.open_setup_from_lobby())
	_menu_box.add_child(bot_btn)
	var back_btn := _button("Quay lại")
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func() -> void: if game != null: game.close_lobby())
	_menu_box.add_child(back_btn)


## Account block in the menu view: guest play stays the default —
## login is optional. When logged in, the name field locks to the
## account name (the server enforces the same lock).
func _build_account(parent: VBoxContainer) -> void:
	_auth_box = VBoxContainer.new()
	_auth_box.add_theme_constant_override("separation", 6)
	parent.add_child(_auth_box)
	var urow := HBoxContainer.new()
	urow.add_theme_constant_override("separation", 8)
	_auth_box.add_child(urow)
	urow.add_child(_label("Tài khoản:", 15))
	_user_edit = _field("Tên đăng nhập (3–20 ký tự)")
	urow.add_child(_user_edit)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	_auth_box.add_child(prow)
	prow.add_child(_label("Mật khẩu:", 15))
	_pass_edit = _field("Mật khẩu (≥ 6 ký tự)")
	_pass_edit.secret = true
	prow.add_child(_pass_edit)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	_auth_box.add_child(brow)
	var login_btn := _button("Đăng nhập")
	login_btn.custom_minimum_size = Vector2(130, 36)
	login_btn.pressed.connect(_on_login_pressed)
	brow.add_child(login_btn)
	var reg_btn := _button("Đăng ký")
	reg_btn.custom_minimum_size = Vector2(130, 36)
	reg_btn.pressed.connect(_on_register_pressed)
	brow.add_child(reg_btn)
	_auth_status = _label("", 12, TXT_DIM)
	_auth_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_auth_box.add_child(_auth_status)
	_auth_info = _label("", 14, GOLD_TXT)
	_auth_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_auth_info.visible = false
	parent.add_child(_auth_info)
	_logout_btn = _button("Đăng xuất")
	_logout_btn.custom_minimum_size = Vector2(130, 36)
	_logout_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_logout_btn.visible = false
	_logout_btn.pressed.connect(func() -> void:
		Net.logout_account()
		_refresh_auth())
	parent.add_child(_logout_btn)
	# Seasonal rank line: drawn badge + rank text + season peak /
	# previous season (filled by _refresh_auth from the profile).
	_rank_row = HBoxContainer.new()
	_rank_row.add_theme_constant_override("separation", 10)
	_rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rank_row.visible = false
	parent.add_child(_rank_row)
	_rank_badge = RankBadge.new()
	_rank_badge.setup(0, 0, 3)
	_rank_row.add_child(_rank_badge)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 1)
	_rank_row.add_child(rv)
	_rank_text = _label("", 16, GOLD_TXT)
	rv.add_child(_rank_text)
	_rank_peak = _label("", 12, TXT_DIM)
	rv.add_child(_rank_peak)
	_build_avatar_row(parent)


## Profile avatar row (17d catalogue): the avatar is a FREE
## pick among the owner's twenty anime avatars — decoupled
## from the hero draw (Net.set_avatar persists it on the
## account; guests keep it locally). The full picker with
## frames lives in the profile's settings panels; this row
## is the lobby shortcut. The "Nhân vật" button opens the
## collection screen (heroes — a separate surface).
func _build_avatar_row(parent: VBoxContainer) -> void:
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(srow)
	srow.add_child(_label("Avatar:", 15))
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	srow.add_child(grid)
	for id in Avatars.IDS:
		var b := TextureButton.new()
		b.texture_normal = Avatars.texture_for(id)
		b.custom_minimum_size = Vector2(40, 40)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.tooltip_text = Avatars.display_name(id)
		var aid: String = id
		b.pressed.connect(func() -> void:
			Net.set_avatar(aid)
			_refresh_avatar_row())
		grid.add_child(b)
		_avatar_btns[id] = b
	var coll := _button("Nhân vật")
	coll.custom_minimum_size = Vector2(110, 40)
	coll.pressed.connect(func() -> void: _show_characters())
	srow.add_child(coll)
	_refresh_avatar_row()


func _refresh_avatar_row() -> void:
	var cur := Avatars.local_avatar()
	for id in _avatar_btns:
		var b: TextureButton = _avatar_btns[id]
		b.modulate = Color(1, 1, 1, 1) if String(id) == cur \
				else Color(0.62, 0.62, 0.66, 0.85)


## The character collection ("Nhân vật"): the eight mains with
## portrait + kit lines (they are ASSIGNED by draw each match —
## there is nothing to equip). 16b: the wuxia skin teasers are
## UNBOUND from this page (the skin sets belonged to the old
## roster) — the dormant skin data stays in Characters for a
## future cosmetic system, but nothing here draws it.
func _build_characters() -> void:
	_chars_root = Control.new()
	_chars_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chars_root.visible = false
	_root.add_child(_chars_root)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/home_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chars_root.add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chars_root.add_child(dim)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 10
	board.offset_top = 8
	board.offset_right = -10
	board.offset_bottom = -8
	board.add_theme_stylebox_override("panel", _lb_board_style())
	_chars_root.add_child(board)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	board.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var back := _button("‹")
	back.custom_minimum_size = Vector2(52, 40)
	back.pressed.connect(func() -> void: _chars_root.visible = false)
	head.add_child(back)
	head.add_child(_label("NHÂN VẬT", 26, Color(1, 0.87, 0.45)))
	vb.add_child(head)
	vb.add_child(_label("Mỗi trận, hệ thống bốc thăm ngẫu nhiên 1 nhân vật cho bạn. Kỹ năng thuộc về nhân vật được bốc thăm.", 13, TXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for id in Characters.CHAR_IDS:
		grid.add_child(_char_card(id))


func _char_card(id: String) -> PanelContainer:
	var kit := Characters.kit_of(id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _lb_sb(Color(0.05, 0.08, 0.16, 0.85), 10))
	# EXPAND so the grid's columns share the board's full width
	# (a GridContainer otherwise keeps columns at minimum width,
	# squeezing the text into a sliver).
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 14c: horizontal card (portrait left, text right) — with the
	# roster at eight, the old portrait-on-top card wrapped its
	# text into ~10 lines and the second row fell off the board.
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	card.add_child(hb)
	var tr := TextureRect.new()
	tr.texture = Characters.framed_avatar_for(id)
	tr.custom_minimum_size = Vector2(84, 84)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tr)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	vb.add_child(_label(Characters.char_name(id), 16, GOLD_TXT))
	var a := _label("Hào quang %s — %s" % [String(kit.get("aura", "")), String(kit.get("aura_desc", ""))], 11)
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(a)
	var s := _label("Chiêu %s (hồi %ds) — %s" % [String(kit.get("skill", "")),
			int(Stats.hero_cd(id)), String(kit.get("skill_desc", ""))], 11)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(s)
	return card


func _show_characters() -> void:
	_chars_root.visible = true


## Fills a badge + rank label pair from a profile rank Dictionary.
func _fill_rank_widgets(badge: RankBadge, text_lbl: Label, peak_lbl: Label) -> void:
	var r: Dictionary = Net.auth_profile.get("rank", {})
	if r.is_empty():
		return
	badge.setup(int(r.get("tier", 0)), int(r.get("stars", 0)),
			int(r.get("star_cap", 3)), bool(r.get("emperor", false)))
	text_lbl.text = String(r.get("rank_text", ""))
	if peak_lbl != null:
		var lines := "Đỉnh mùa: %s" % String(r.get("peak_text", ""))
		if int(r.get("prev_season", 0)) > 0:
			lines += "\nMùa trước (Mùa %d): %s" % [int(r.get("prev_season", 0)),
					String(r.get("prev_season_text", ""))]
		peak_lbl.text = lines


func _refresh_auth() -> void:
	var logged := Net.account_name != ""
	_auth_box.visible = not logged
	_auth_info.visible = logged
	_logout_btn.visible = logged
	_rank_row.visible = logged
	_name_edit.editable = not logged
	if logged:
		_name_edit.text = Net.display_name()
		_auth_info.text = "Tài khoản: %s — MMR %d · Thắng %d · Thua %d · %d trận" % [
			Net.display_name(), int(Net.auth_profile.get("mmr", 1000)),
			int(Net.auth_profile.get("wins", 0)),
			int(Net.auth_profile.get("losses", 0)),
			int(Net.auth_profile.get("matches", 0))]
		_fill_rank_widgets(_rank_badge, _rank_text, _rank_peak)
	elif _auth_status != null:
		_auth_status.text = "Chơi khách vẫn được — đăng nhập để lưu thành tích."
	if _ranked_btn != null:
		_ranked_btn.disabled = not logged
		_ranked_hint.text = "Ghép trận 1v1 theo MMR — đăng nhập mới đấu xếp hạng được." \
			if not logged else \
			"Ghép trận 1v1 theo MMR, trọng tài máy chủ phân định kết quả."
	_refresh_avatar_row()


func _on_login_pressed() -> void:
	_ensure_connected()
	if Net.connected:
		Net.login_account(_user_edit.text.strip_edges(), _pass_edit.text)
	else:
		_pending_auth = "login"


func _on_register_pressed() -> void:
	_ensure_connected()
	if Net.connected:
		Net.register_account(_user_edit.text.strip_edges(), _pass_edit.text)
	else:
		_pending_auth = "register"

func _build_room(parent: VBoxContainer) -> void:
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 10)
	parent.add_child(_room_box)
	_code_label = _label("Phòng -----", 26, GOLD_TXT)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(_code_label)
	_config_label = _label("", 13, TXT_DIM)
	_config_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(_config_label)
	_obs_label = _label("", 12, TXT_DIM)
	_obs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(_obs_label)
	_obs_box = VBoxContainer.new()
	_obs_box.add_theme_constant_override("separation", 4)
	_room_box.add_child(_obs_box)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_room_box.add_child(_players_box)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	_room_box.add_child(brow)
	_ready_btn = _button("Sẵn sàng")
	_ready_btn.pressed.connect(_on_ready_pressed)
	brow.add_child(_ready_btn)
	_start_btn = _button("Bắt đầu trận")
	_start_btn.pressed.connect(func() -> void: Net.request_start())
	brow.add_child(_start_btn)
	var lb_btn := _button("Bảng xếp hạng")
	lb_btn.pressed.connect(func() -> void: open_leaderboard())
	brow.add_child(lb_btn)
	var leave_btn := _button("Rời phòng")
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.pressed.connect(_on_leave_pressed)
	_room_box.add_child(leave_btn)
	_build_room_config(_room_box)
	_build_room_chat(_room_box)


## Host config editor (15a): the full room config the sim and
## server support — map, name, visibility, observers, password.
## Host-only and custom rooms only; the server enforces the
## same rules (host + lobby phase), this block only mirrors
## them. Fields are (re)populated when the room/host changes,
## never on every broadcast, so typing is not clobbered.
func _build_room_config(parent: VBoxContainer) -> void:
	_cfg_box = VBoxContainer.new()
	_cfg_box.add_theme_constant_override("separation", 6)
	_cfg_box.visible = false
	parent.add_child(_cfg_box)
	_cfg_box.add_child(_label("Cấu hình phòng (chủ phòng)", 14, GOLD_TXT))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	_cfg_box.add_child(mrow)
	mrow.add_child(_label("Khu vực:", 14))
	_cfg_biome_opt = OptionButton.new()
	for bid in Biomes.ORDER:
		_cfg_biome_opt.add_item(String(Biomes.data(bid).get("name", bid)))
	mrow.add_child(_cfg_biome_opt)
	mrow.add_child(_label("Địa hình:", 14))
	_cfg_layout_opt = OptionButton.new()
	for lid in World.LAYOUT_NAMES.keys():
		_cfg_layout_opt.add_item(String(World.LAYOUT_NAMES[lid]))
	mrow.add_child(_cfg_layout_opt)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	_cfg_box.add_child(nrow)
	nrow.add_child(_label("Tên phòng:", 14))
	_cfg_name_edit = _field("Tên phòng")
	nrow.add_child(_cfg_name_edit)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 14)
	_cfg_box.add_child(orow)
	_cfg_public_check = _check("Công khai")
	orow.add_child(_cfg_public_check)
	_cfg_obs_check = _check("Cho phép người xem")
	orow.add_child(_cfg_obs_check)
	_cfg_dip_check = _check("Ngoại giao")
	orow.add_child(_cfg_dip_check)
	_cfg_pass_touch = _check("Đổi mật khẩu:")
	orow.add_child(_cfg_pass_touch)
	_cfg_pass_edit = _field("Để trống = bỏ khóa")
	_cfg_pass_edit.custom_minimum_size = Vector2(170, 32)
	_cfg_pass_edit.secret = true
	orow.add_child(_cfg_pass_edit)
	var drow2 := HBoxContainer.new()
	drow2.add_theme_constant_override("separation", 8)
	_cfg_box.add_child(drow2)
	drow2.add_child(_label("Trì hoãn người xem:", 14))
	_cfg_delay_opt = _delay_option()
	drow2.add_child(_cfg_delay_opt)
	var save_btn := _button("Lưu cấu hình")
	save_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	save_btn.pressed.connect(_on_save_config_pressed)
	_cfg_box.add_child(save_btn)


func _on_save_config_pressed() -> void:
	var biome := String(Biomes.ORDER[_cfg_biome_opt.selected]) \
			if _cfg_biome_opt.selected >= 0 else Net.cfg_biome
	var layout := String(World.LAYOUT_NAMES.keys()[_cfg_layout_opt.selected]) \
			if _cfg_layout_opt.selected >= 0 else Net.cfg_layout
	Net.set_config_full({
		"biome": biome, "layout": layout,
		"room_name": _cfg_name_edit.text.strip_edges(),
		"public": _cfg_public_check.button_pressed,
		"allow_obs": _cfg_obs_check.button_pressed,
		"diplomacy": _cfg_dip_check.button_pressed,
		"obs_delay": _delay_seconds(_cfg_delay_opt.selected),
		"set_pass": _cfg_pass_touch.button_pressed,
		"room_pass": _cfg_pass_edit.text})
	_cfg_pass_touch.button_pressed = false
	_cfg_pass_edit.clear()
	_set_status("Đã lưu cấu hình phòng.")


## Lobby chat (scope "lobby"): message list + input under the
## player list. Pure relay on the server — never touches the sim.
func _build_room_chat(parent: VBoxContainer) -> void:
	parent.add_child(_label("Trò chuyện", 14, GOLD_TXT))
	_chat_log = RichTextLabel.new()
	_chat_log.custom_minimum_size = Vector2(540, 104)
	_chat_log.bbcode_enabled = false
	_chat_log.scroll_following = true
	_chat_log.add_theme_font_size_override("normal_font_size", 13)
	_chat_log.add_theme_color_override("default_color", TXT)
	_chat_log.add_theme_stylebox_override("normal", _sb(BORDER, FIELD_BG, 8))
	parent.add_child(_chat_log)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	parent.add_child(crow)
	_chat_edit = _field("Nhập tin nhắn… (Enter để gửi)")
	_chat_edit.custom_minimum_size = Vector2(400, 36)
	_chat_edit.max_length = 200
	_chat_edit.text_submitted.connect(func(_t: String) -> void: _send_lobby_chat())
	crow.add_child(_chat_edit)
	var send_btn := _button("Gửi")
	send_btn.custom_minimum_size = Vector2(90, 36)
	send_btn.pressed.connect(_send_lobby_chat)
	crow.add_child(send_btn)


func _send_lobby_chat() -> void:
	var text := _chat_edit.text.strip_edges()
	if text == "":
		return
	_chat_edit.clear()
	Net.send_chat("lobby", text)


## Room browser (15a): the server lists PUBLIC custom rooms
## waiting in their lobby. Search filters client-side over the
## last payload (room name / host / code); one shared password
## field serves whichever locked room the player picks.
func _build_browser(parent: VBoxContainer) -> void:
	_browser_box = VBoxContainer.new()
	_browser_box.add_theme_constant_override("separation", 10)
	_browser_box.visible = false
	parent.add_child(_browser_box)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	_browser_box.add_child(srow)
	_browse_search = _field("Tìm theo tên phòng, chủ phòng, mã…")
	_browse_search.custom_minimum_size = Vector2(340, 36)
	_browse_search.text_changed.connect(func(_t: String) -> void: _fill_browser())
	srow.add_child(_browse_search)
	var ref_btn := _button("Làm mới")
	ref_btn.custom_minimum_size = Vector2(110, 36)
	ref_btn.pressed.connect(func() -> void: Net.request_room_list())
	srow.add_child(ref_btn)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	_browser_box.add_child(prow)
	prow.add_child(_label("Mật khẩu (nếu phòng khóa):", 14))
	_browse_pass_edit = _field("")
	_browse_pass_edit.custom_minimum_size = Vector2(200, 36)
	_browse_pass_edit.secret = true
	prow.add_child(_browse_pass_edit)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 264)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_browser_box.add_child(scroll)
	_browse_rows = VBoxContainer.new()
	_browse_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_browse_rows)
	var back_btn := _button("Quay lại")
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_show_menu)
	_browser_box.add_child(back_btn)


func _show_browser() -> void:
	_menu_box.visible = false
	_room_box.visible = false
	_browser_box.visible = true
	_ensure_connected()
	Net.request_room_list()
	_fill_browser()


## Capture hook (15a): open the room browser programmatically.
func show_browser_for_test() -> void:
	_show_browser()


func _fill_browser() -> void:
	if _browse_rows == null:
		return
	for ch in _browse_rows.get_children():
		ch.queue_free()
	var q := _browse_search.text.strip_edges().to_lower()
	var shown := 0
	for row in Net.room_list_rows:
		var hay := "%s %s %s" % [String(row.get("name", "")),
				String(row.get("host", "")), String(row.get("code", ""))]
		if q != "" and not hay.to_lower().contains(q):
			continue
		shown += 1
		_browse_rows.add_child(_browser_row(row))
	if shown == 0:
		var l := _label("Chưa có phòng công khai nào đang chờ." if q == ""
				else "Không thấy phòng nào khớp.", 14, TXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_browse_rows.add_child(l)


func _browser_row(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.04), 8))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	vb.add_child(_label(String(row.get("name", "Phòng")), 15, GOLD_TXT))
	var bname := String(Biomes.data(String(row.get("biome", ""))).get("name", String(row.get("biome", "")))) \
			if Biomes.is_valid(String(row.get("biome", ""))) else String(row.get("biome", ""))
	var age := int(row.get("age_sec", 0))
	var age_txt := "vừa tạo" if age < 60 else "%d phút trước" % (age / 60)
	var sub := "Chủ: %s · %s · %s · %s" % [String(row.get("host", "?")), bname,
			String(World.LAYOUT_NAMES.get(String(row.get("layout", "")), String(row.get("layout", "")))),
			age_txt]
	if bool(row.get("has_password", false)):
		sub += " · Có mật khẩu"
	if bool(row.get("allow_obs", false)):
		sub += " · Cho xem"
	if int(row.get("obs_delay", 0)) > 0:
		sub += " · Trễ xem %ds" % int(row.get("obs_delay", 0))
	vb.add_child(_label(sub, 12, TXT_DIM))
	hb.add_child(_label("%d/4" % int(row.get("players", 0)), 15, TXT))
	var code := String(row.get("code", ""))
	var join_b := _button("Vào")
	join_b.custom_minimum_size = Vector2(80, 34)
	join_b.pressed.connect(func() -> void:
		Net.join_room(code, _player_name(), _browse_pass_edit.text))
	hb.add_child(join_b)
	if bool(row.get("allow_obs", false)):
		var obs_b := _button("Xem")
		obs_b.custom_minimum_size = Vector2(80, 34)
		obs_b.pressed.connect(func() -> void:
			Net.observe_room(code, _player_name(), _browse_pass_edit.text))
		hb.add_child(obs_b)
	return card


## Leaderboard board: a FULL-SCREEN board covering the
## viewport edge-to-edge (opaque, square corners — 13m
## follow-up). Since 13q its fill is the shared info-page
## background and its header the shared page header
## (PageShell — same solid navy + back pill + title as
## Hồ sơ / Bạn bè).
## 17i (BXH half): the interior follows the approved
## friends-panel language — ONE slate content card under
## the header holding a segmented tab row (Toàn server /
## Bạn bè / Liên minh; active = gold fill, dark text), a column
## header row aligned exactly with the row grid, ROW
## CARDS (laurel-wreath badges for the top 3, framed
## avatar, name + ladder sub-line, emblem texture + tier
## name, khanda + dot-formatted MMR; #1 gold-gradient,
## #2/#3 subtle silver/bronze tints, my row gold-bordered)
## and the "Hạng của tôi" footer folded INTO the card as
## its bottom strip — its position is computed by the
## server over the FULL ordering (LeaderboardV2), not
## just the visible top 20. Empty states are centred in
## the card (big muted FA icon + one line).
## The Liên minh tab (17a) ranks the server's alliances
## by weekly contribution points (server mode "alliance").
## (The server's wins/losses board mode "wl" still exists
## in the protocol and in _lb_score_text/_lb_sub_text for
## other callers; it simply has no tab here anymore.)

# The friends-panel card dialect (home_lobby.gd's FR_*
# constants), copied so the two screens read as one family.
const LB_CARD_BG := Color(0.05, 0.07, 0.13)
const LB_CARD_LINE := Color(0.30, 0.34, 0.46)
const LB_ROW_BG := Color(1, 1, 1, 0.045)
const LB_ROW_LINE := Color(1, 1, 1, 0.08)
const LB_MUTED := Color(0.62, 0.66, 0.75)
const LB_GOLD := Color(0.98, 0.8, 0.35)
const LB_FA_PATH := "res://assets/fonts/fa-solid-900.ttf"
const LB_FA_TROPHY := 0xF091
const LB_FA_GROUP := 0xF0C0
const LB_FA_SHIELD := 0xF3ED
const LB_FA_KHANDA := 0xF66D
# Row-grid column widths, shared by the header row and
# every row card so the two align exactly.
const LB_COL_RANK := 64.0
const LB_COL_TIER := 210.0
const LB_COL_POINTS := 150.0
const LB_COL_LEVEL := 80.0
const LB_COL_WEEK := 130.0


## One Font Awesome glyph as a label (the chat hub /
## friends pattern: vendored fa-solid font + chr()).
func _lb_fa(cp: int, px: int, col: Color) -> Label:
	if _lb_fa_font == null:
		_lb_fa_font = load(LB_FA_PATH)
	var l := Label.new()
	l.text = String.chr(cp)
	l.add_theme_font_override("font", _lb_fa_font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Button stylebox, 17c calibration: EXPLICIT content
## margins (L/R 10, T 0, B 2) so bordered and borderless
## states lay text out in the same box (same helper as
## the friends panel's _fr_btn_sb).
func _lb_btn_sb(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 0
	s.content_margin_bottom = 2
	return s


## Row-card stylebox (friends dialect): radius 10,
## content margins L/R 12, T/B 9.
func _lb_row_sb(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s

func _lb_sb(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


## Vertical-gradient texture with baked rounded corners, used
## for the board backdrop and the #1 gold bar (StyleBoxFlat has
## no gradient fill). `stops` = [[t, Color], ...] top → bottom.
func _lb_gradient_tex(w: int, h: int, radius: float, stops: Array) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(maxi(h - 1, 1))
		var col := _lb_grad_at(stops, t)
		for x in w:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var cx := clampf(px, radius, float(w) - radius)
			var cy := clampf(py, radius, float(h) - radius)
			var d := Vector2(px, py).distance_to(Vector2(cx, cy))
			var a := 1.0
			if d > 0.0:
				a = clampf(radius - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	return ImageTexture.create_from_image(img)


func _lb_grad_at(stops: Array, t: float) -> Color:
	if t <= float(stops[0][0]):
		return stops[0][1]
	for i in range(1, stops.size()):
		if t <= float(stops[i][0]):
			var t0 := float(stops[i - 1][0])
			var t1 := float(stops[i][0])
			var f := (t - t0) / maxf(t1 - t0, 0.0001)
			return (stops[i - 1][1] as Color).lerp(stops[i][1], f)
	return stops[stops.size() - 1][1]


func _lb_board_style() -> StyleBoxTexture:
	if _lb_board_tex == null:
		_lb_board_tex = _lb_gradient_tex(160, 160, 14.0, [
			[0.0, Color(0.11, 0.16, 0.31, 0.97)],
			[0.35, Color(0.05, 0.085, 0.19, 0.97)],
			[1.0, Color(0.015, 0.025, 0.075, 0.98)]])
	var s := StyleBoxTexture.new()
	s.texture = _lb_board_tex
	s.set_texture_margin_all(16)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _lb_gold_style() -> StyleBoxTexture:
	if _lb_gold_tex == null:
		_lb_gold_tex = _lb_gradient_tex(256, 64, 10.0, [
			[0.0, Color(1.0, 0.87, 0.45)],
			[0.45, Color(0.95, 0.71, 0.24)],
			[1.0, Color(0.72, 0.48, 0.10)]])
	var s := StyleBoxTexture.new()
	s.texture = _lb_gold_tex
	s.set_texture_margin_all(12)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


func _fmt_num(n: int) -> String:
	var neg := n < 0
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if neg else "") + digits + out


func _build_leaderboard_v2() -> void:
	_lb_root = Control.new()
	_lb_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lb_root.visible = false
	_root.add_child(_lb_root)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Full-bleed (Tín, 13m follow-up): no inset offsets — the
	# board spans the whole viewport edge-to-edge. Its fill
	# is the shared info-page background (PageShell, 13q):
	# the same solid deep navy as Hồ sơ and Bạn bè — the old
	# per-page gradient and the home-art backdrop under it
	# are gone. Content margins keep the board's 16px sides,
	# with the top pushed below the shared header
	# (PageShell.CONTENT_TOP).
	var board_sb := PageShell.bg_style()
	board_sb.content_margin_left = 16
	board_sb.content_margin_right = 16
	board_sb.content_margin_top = PageShell.CONTENT_TOP
	board_sb.content_margin_bottom = 10
	board.add_theme_stylebox_override("panel", board_sb)
	_lb_root.add_child(board)
	# Header: the shared page header (PageShell, 13q) —
	# identical back pill + title to Hồ sơ / Bạn bè,
	# overlaid on the board.
	_lb_root.add_child(PageShell.header("Bảng xếp hạng",
			Callable(self, "_close_leaderboard")))
	# ONE content card (17i dialect): slate fill, 1px line,
	# radius 12, uniform 14px padding — everything else
	# lives inside it.
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = LB_CARD_BG
	csb.set_corner_radius_all(12)
	csb.border_color = LB_CARD_LINE
	csb.set_border_width_all(1)
	csb.content_margin_left = 14
	csb.content_margin_right = 14
	csb.content_margin_top = 14
	csb.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", csb)
	board.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	# Segmented tab row inside the card: three equal
	# buttons (active = gold fill + dark text).
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for spec in [["ranked", "Toàn server"], ["friends", "Bạn bè"], ["alliance", "Liên minh"]]:
		var b := Button.new()
		b.text = spec[1]
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		var mode: String = spec[0]
		b.pressed.connect(func() -> void: _set_lb_mode(mode))
		_lb_tabs[mode] = b
		tabs.add_child(b)
	vb.add_child(tabs)
	_lb_paint_tabs()
	# Column headers, aligned EXACTLY with the row grid:
	# the header row is inset by the row cards' own 12px
	# content margin on both sides, then mirrors the row
	# cells (LB_COL_* widths, 10px separation). Its labels
	# are (re)built per mode by _lb_paint_cols().
	_lb_cols = MarginContainer.new()
	_lb_cols.add_theme_constant_override("margin_left", 12)
	_lb_cols.add_theme_constant_override("margin_right", 12)
	_lb_cols_hb = HBoxContainer.new()
	_lb_cols_hb.add_theme_constant_override("separation", 10)
	_lb_cols.add_child(_lb_cols_hb)
	vb.add_child(_lb_cols)
	# The list.
	_lb_scroll = ScrollContainer.new()
	_lb_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_lb_scroll)
	_lb_rows_box = VBoxContainer.new()
	_lb_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lb_rows_box.add_theme_constant_override("separation", 8)
	_lb_scroll.add_child(_lb_rows_box)
	# Centred empty state (one surface, swapped with the
	# scroll): big muted FA icon + one short line.
	_lb_empty_box = CenterContainer.new()
	_lb_empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lb_empty_box.visible = false
	vb.add_child(_lb_empty_box)
	_lb_empty_inner = VBoxContainer.new()
	_lb_empty_inner.add_theme_constant_override("separation", 10)
	_lb_empty_box.add_child(_lb_empty_inner)
	# Divider over the footer strip.
	var div := PanelContainer.new()
	div.custom_minimum_size = Vector2(0, 1)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(1, 1, 1, 0.10)
	div.add_theme_stylebox_override("panel", dsb)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(div)
	# Sticky footer, folded INTO the card as its bottom
	# strip: a row card with a gold border — the viewer's
	# own row + full-order position.
	_lb_footer = PanelContainer.new()
	_lb_footer.add_theme_stylebox_override("panel",
			_lb_row_sb(LB_ROW_BG, Color(1, 0.85, 0.4, 0.7), 1))
	_lb_footer_box = HBoxContainer.new()
	_lb_footer_box.add_theme_constant_override("separation", 10)
	_lb_footer.add_child(_lb_footer_box)
	vb.add_child(_lb_footer)


## Tab button states: the active mode is gold with dark
## text; the rest are subtle dark (friends _fr dialect).
func _lb_paint_tabs() -> void:
	for mode in _lb_tabs:
		var b: Button = _lb_tabs[mode]
		if mode == _lb_mode:
			b.add_theme_stylebox_override("normal", _lb_btn_sb(LB_GOLD, 9))
			b.add_theme_stylebox_override("hover", _lb_btn_sb(Color(1.0, 0.86, 0.45), 9))
			b.add_theme_stylebox_override("pressed", _lb_btn_sb(Color(0.88, 0.7, 0.28), 9))
			b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
			b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
			b.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.02))
		else:
			b.add_theme_stylebox_override("normal", _lb_btn_sb(Color(1, 1, 1, 0.04), 9))
			b.add_theme_stylebox_override("hover", _lb_btn_sb(Color(1, 1, 1, 0.09), 9))
			b.add_theme_stylebox_override("pressed", _lb_btn_sb(Color(1, 1, 1, 0.07), 9))
			b.add_theme_color_override("font_color", TXT)
			b.add_theme_color_override("font_hover_color", TXT)
			b.add_theme_color_override("font_pressed_color", TXT)


func _lb_col_label(text: String, w: float, align: HorizontalAlignment) -> Label:
	var l := _label(text, 13, LB_MUTED)
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _lb_col_spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## (Re)builds the column header labels for the current
## mode, mirroring the row grid cell for cell.
func _lb_paint_cols() -> void:
	if _lb_cols_hb == null:
		return
	for ch in _lb_cols_hb.get_children():
		_lb_cols_hb.remove_child(ch)
		ch.queue_free()
	if _lb_mode == "alliance":
		_lb_cols_hb.add_child(_lb_col_label("HẠNG", LB_COL_RANK, HORIZONTAL_ALIGNMENT_CENTER))
		_lb_cols_hb.add_child(_lb_col_spacer(31))
		var a2 := _lb_col_label("LIÊN MINH", 0, HORIZONTAL_ALIGNMENT_LEFT)
		a2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lb_cols_hb.add_child(a2)
		_lb_cols_hb.add_child(_lb_col_label("CẤP", LB_COL_LEVEL, HORIZONTAL_ALIGNMENT_CENTER))
		_lb_cols_hb.add_child(_lb_col_label("ĐIỂM TUẦN", LB_COL_WEEK, HORIZONTAL_ALIGNMENT_RIGHT))
	else:
		_lb_cols_hb.add_child(_lb_col_label("HẠNG", LB_COL_RANK, HORIZONTAL_ALIGNMENT_CENTER))
		_lb_cols_hb.add_child(_lb_col_spacer(44))
		var p2 := _lb_col_label("NGƯỜI CHƠI", 0, HORIZONTAL_ALIGNMENT_LEFT)
		p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lb_cols_hb.add_child(p2)
		_lb_cols_hb.add_child(_lb_col_label("BẬC HẠNG", LB_COL_TIER, HORIZONTAL_ALIGNMENT_LEFT))
		_lb_cols_hb.add_child(_lb_col_label("ĐIỂM", LB_COL_POINTS, HORIZONTAL_ALIGNMENT_RIGHT))


## The centred empty state: hides the scroll, shows the
## icon + line surface instead.
func _lb_show_empty(cp: int, line: String) -> void:
	for ch in _lb_empty_inner.get_children():
		_lb_empty_inner.remove_child(ch)
		ch.queue_free()
	var ic := _lb_fa(cp, 44, Color(0.45, 0.48, 0.58))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lb_empty_inner.add_child(ic)
	var l := _label(line, 15, LB_MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lb_empty_inner.add_child(l)
	_lb_scroll.visible = false
	_lb_empty_box.visible = true


func _lb_hide_empty() -> void:
	_lb_empty_box.visible = false
	_lb_scroll.visible = true


func _set_lb_mode(mode: String) -> void:
	_lb_mode = mode
	_lb_data = []
	_lb_me = {}
	Net.request_leaderboard(mode)
	_fill_leaderboard()


func open_leaderboard() -> void:
	_show_lb()


## Opens the board straight on the ranked (ladder) tab.
func open_ranked_leaderboard() -> void:
	_lb_mode = "ranked"
	_show_lb()


func _show_lb() -> void:
	_panel_cc.visible = false
	_lb_root.visible = true
	Net.request_leaderboard(_lb_mode)
	_fill_leaderboard()


func is_leaderboard_open() -> bool:
	return _lb_root != null and _lb_root.visible


func _close_leaderboard() -> void:
	_lb_root.visible = false
	if _lb_return_home:
		_lb_return_home = false
		if game != null:
			game.close_lobby() # back to the home screen
		return
	_panel_cc.visible = true
	if Net.room_code != "":
		_show_room()
	else:
		_show_menu()


func _lb_score_text(row: Dictionary) -> String:
	if _lb_mode == "wl":
		return str(int(row.get("wins", 0)))
	return _fmt_num(int(row.get("mmr", 1000)))


func _lb_sub_text(row: Dictionary) -> String:
	if _lb_mode == "wl":
		return "Thắng %d · Thua %d" % [int(row.get("wins", 0)), int(row.get("losses", 0))]
	return String(row.get("rank_text", ""))


func _lb_tier_name(row: Dictionary) -> String:
	var short := String(row.get("rank_short", ""))
	var parts := short.split(" ")
	if parts.size() > 1 and ["I", "II", "III"].has(parts[parts.size() - 1]):
		parts.remove_at(parts.size() - 1)
		return " ".join(parts)
	return short


## The rank cell (LB_COL_RANK wide): the laurel-wreath
## badge for the top 3 (owner art language), a plain
## gold-grey number for the rest.
func _lb_rank_cell(pos: int, on_gold: bool) -> Control:
	if pos >= 1 and pos <= 3:
		var wn := WreathNum.new(pos)
		wn.custom_minimum_size = Vector2(LB_COL_RANK, 54)
		wn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if on_gold:
			wn.set_on_gold(true)
		return wn
	var l := _label(str(pos), 20,
			Color(0.30, 0.22, 0.05) if on_gold else Color(0.80, 0.78, 0.72))
	l.custom_minimum_size = Vector2(LB_COL_RANK, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## The row tint for a position: #1 the gold gradient,
## #2/#3 subtle silver/bronze tints, my own row (outside
## the tints) gold-bordered, the rest the standard row
## card. Shared by the player and alliance rows.
func _lb_pos_style(pos: int, mine: bool) -> StyleBox:
	if pos == 1:
		var g := _lb_gold_style()
		g.content_margin_left = 12
		g.content_margin_right = 12
		g.content_margin_top = 9
		g.content_margin_bottom = 9
		return g
	if pos == 2:
		return _lb_row_sb(Color(0.75, 0.78, 0.85, 0.10),
				Color(0.83, 0.86, 0.92, 0.35))
	if pos == 3:
		return _lb_row_sb(Color(0.85, 0.55, 0.28, 0.10),
				Color(0.87, 0.56, 0.30, 0.35))
	if mine:
		return _lb_row_sb(LB_ROW_BG, Color(1, 0.85, 0.4, 0.7))
	return _lb_row_sb(LB_ROW_BG, LB_ROW_LINE)


## One board row as a ROW CARD (also used, with footer
## styling, for "my rank"): rank cell, framed avatar,
## name + ladder sub-line, emblem texture + tier name,
## khanda + dot-formatted score — on the LB_COL_* grid
## the column header mirrors.
func _lb_card(pos: int, row: Dictionary, footer: bool = false) -> PanelContainer:
	var on_gold := pos == 1 and not footer
	var mine := not footer and Net.account_name != "" \
			and String(row.get("user", "")) == Net.account_name
	var card := PanelContainer.new()
	if footer:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, 0)
		card.add_theme_stylebox_override("panel", flat)
	else:
		card.add_theme_stylebox_override("panel", _lb_pos_style(pos, mine))
	var name_col := Color(0.14, 0.10, 0.02) if on_gold else Color.WHITE
	var sub_col := Color(0.34, 0.25, 0.09) if on_gold else Color(0.75, 0.79, 0.88)
	var tier_col := Color(0.16, 0.11, 0.02) if on_gold else RankBadge.tier_color(
			int(row.get("rank_tier", 0)),
			bool(row.get("emperor", false))).lightened(0.3)
	var score_col := Color(0.24, 0.15, 0.02) if on_gold else Color(1, 0.95, 0.8)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	if footer:
		var mine_box := VBoxContainer.new()
		mine_box.custom_minimum_size = Vector2(84, 0)
		mine_box.alignment = BoxContainer.ALIGNMENT_CENTER
		mine_box.add_theme_constant_override("separation", 0)
		var cap := _label("HẠNG CỦA TÔI", 10, Color(0.8, 0.85, 0.95))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mine_box.add_child(cap)
		var big := _label(str(pos), 26, Color(1, 0.9, 0.5))
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mine_box.add_child(big)
		hb.add_child(mine_box)
	else:
		hb.add_child(_lb_rank_cell(pos, on_gold))
	# Avatar (17d): the row account's own avatar + equipped
	# frame, composed by the shared helper (static first
	# frame at this size) — the friends-row treatment.
	var av := AvatarFrame.new()
	av.custom_minimum_size = Vector2(44, 44)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.set_content(Avatars.texture_for_user(String(row.get("avatar_id", "")),
			String(row.get("user", ""))), String(row.get("frame_id", "")), false)
	hb.add_child(av)
	# Name + sub-line (rank text with star progress). The
	# [TAG] prefix rides along when a row carries one
	# (Net.ally_disp, as on the other surfaces).
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_box.add_theme_constant_override("separation", 1)
	var nm := _label(Net.ally_disp(
			String(row.get("display_name", String(row.get("user", "?")))),
			String(row.get("ally_tag", ""))), 16, name_col)
	name_box.add_child(nm)
	name_box.add_child(_label(_lb_sub_text(row), 13, sub_col))
	hb.add_child(name_box)
	# Tier cell: emblem texture + tier name.
	var centre := HBoxContainer.new()
	centre.custom_minimum_size = Vector2(LB_COL_TIER, 0)
	centre.add_theme_constant_override("separation", 8)
	var em := TextureRect.new()
	em.texture = RankBadge.emblem_texture(int(row.get("rank_tier", 0)),
			bool(row.get("emperor", false)))
	em.custom_minimum_size = Vector2(26, 34)
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(em)
	var tn := _label(_lb_tier_name(row), 16, tier_col)
	tn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centre.add_child(tn)
	hb.add_child(centre)
	# Score cell: FA khanda + value, right-aligned.
	var score := HBoxContainer.new()
	score.custom_minimum_size = Vector2(LB_COL_POINTS, 0)
	score.alignment = BoxContainer.ALIGNMENT_END
	score.add_theme_constant_override("separation", 6)
	var sic := _lb_fa(LB_FA_KHANDA, 15,
			Color(0.35, 0.22, 0.04) if on_gold else Color(0.98, 0.83, 0.4))
	sic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score.add_child(sic)
	var sv := _label(_lb_score_text(row), 20, score_col)
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score.add_child(sv)
	hb.add_child(score)
	return card


func _fill_leaderboard() -> void:
	if _lb_rows_box == null:
		return
	_lb_paint_tabs()
	_lb_paint_cols()
	_lb_hide_empty()
	for ch in _lb_rows_box.get_children():
		_lb_rows_box.remove_child(ch)
		ch.queue_free()
	for ch in _lb_footer_box.get_children():
		_lb_footer_box.remove_child(ch)
		ch.queue_free()
	if _lb_mode == "alliance":
		_fill_lb_alliance()
		return
	# Footer first (it also renders while rows load).
	if Net.account_name == "":
		var gl := _label("Đăng nhập để xem hạng của bạn.", 15, Color(0.85, 0.88, 0.95))
		gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lb_footer_box.add_child(gl)
	elif not _lb_me.is_empty() and _lb_me.get("row") is Dictionary:
		var my_card := _lb_card(int(_lb_me.get("pos", 0)),
				_lb_me["row"], true)
		my_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lb_footer_box.add_child(my_card)
	else:
		var wl := _label("Đang tải hạng của bạn…", 15, Color(0.85, 0.88, 0.95))
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lb_footer_box.add_child(wl)
	# Rows.
	if _lb_mode == "friends" and Net.account_name == "":
		_lb_show_empty(LB_FA_GROUP,
				"Đăng nhập để xem bảng xếp hạng bạn bè.")
		return
	if Net.leaderboard_mode != _lb_mode:
		var l := _label("Đang tải…", 16, TXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lb_rows_box.add_child(l)
		return
	if _lb_data.is_empty():
		if _lb_mode == "friends":
			_lb_show_empty(LB_FA_GROUP, "Chưa có bạn nào có thành tích.")
		else:
			_lb_show_empty(LB_FA_TROPHY,
					"Chưa có tài khoản nào có thành tích.")
		return
	var pos := 0
	for row in _lb_data:
		pos += 1
		_lb_rows_box.add_child(_lb_card(pos, row))


## The Liên minh tab (17a): alliances ranked by weekly
## contribution points (server-computed order), the viewer's
## own alliance in the sticky footer, and one clear way into
## the alliance screen. Badge chip colours mirror the
## alliance screen's fixed shield set.


func _fill_lb_alliance() -> void:
	# Footer: the viewer's own alliance (or the honest note).
	if Net.account_name == "":
		var gl := _label("Đăng nhập để xem liên minh của bạn.", 15, Color(0.85, 0.88, 0.95))
		gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lb_footer_box.add_child(gl)
	elif Net.leaderboard_mode != "alliance":
		var wl := _label("Đang tải hạng liên minh…", 15, Color(0.85, 0.88, 0.95))
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lb_footer_box.add_child(wl)
	elif not _lb_me.is_empty() and _lb_me.get("row") is Dictionary:
		var r: Dictionary = _lb_me["row"]
		var mine := _label("Liên minh của bạn: #%d · %s · %s điểm tuần" % [
				int(_lb_me.get("pos", 0)), String(r.get("name", "")),
				_lb_fmt_num(int(r.get("week", 0)))], 15, Color(0.85, 0.88, 0.95))
		mine.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lb_footer_box.add_child(mine)
		_lb_footer_box.add_child(_lb_open_alliance_btn())
	else:
		var note := _label("Bạn chưa thuộc liên minh nào.", 15, Color(0.85, 0.88, 0.95))
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lb_footer_box.add_child(note)
		_lb_footer_box.add_child(_lb_open_alliance_btn())
	# Rows.
	if Net.leaderboard_mode != "alliance":
		var l := _label("Đang tải…", 16, TXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lb_rows_box.add_child(l)
		return
	if _lb_data.is_empty():
		_lb_show_empty(LB_FA_SHIELD, "Chưa có liên minh nào trên server.")
		return
	var pos := 0
	for row in _lb_data:
		pos += 1
		_lb_rows_box.add_child(_lb_alliance_card(pos, row))


func _lb_fmt_num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _lb_open_alliance_btn() -> Button:
	var b := Button.new()
	b.text = "Mở trang Liên minh"
	b.custom_minimum_size = Vector2(190, 40)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal",
			_lb_btn_sb(LB_GOLD, 8))
	b.add_theme_stylebox_override("hover",
			_lb_btn_sb(Color(1.0, 0.86, 0.45), 8))
	b.add_theme_stylebox_override("pressed",
			_lb_btn_sb(Color(0.88, 0.7, 0.28), 8))
	b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	b.pressed.connect(func() -> void:
		_close_leaderboard()
		if game != null and game.has_method("home_open_alliance"):
			game.home_open_alliance())
	return b


func _lb_alliance_card(pos: int, row: Dictionary) -> PanelContainer:
	var on_gold := pos == 1
	# My own alliance's row is gold-bordered (outside the
	# top-3 tints), matched by alliance id.
	var mine := false
	if not _lb_me.is_empty() and _lb_me.get("row") is Dictionary:
		var my_id := String((_lb_me["row"] as Dictionary).get("id", ""))
		mine = my_id != "" and my_id == String(row.get("id", ""))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _lb_pos_style(pos, mine))
	var name_col := Color(0.14, 0.10, 0.02) if on_gold else Color.WHITE
	var sub_col := Color(0.34, 0.25, 0.09) if on_gold else Color(0.75, 0.79, 0.88)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	hb.add_child(_lb_rank_cell(pos, on_gold))
	# The alliance PENNANT badge (ally_badge.gd — the
	# hanging-banner mark), ~30px.
	var badge := AllyBadge.make(int(row.get("badge_icon", 1)),
			int(row.get("badge_color", 0)), 30)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(badge)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := _label(Net.ally_disp(String(row.get("name", "")),
			String(row.get("tag", ""))), 16, name_col)
	nv.add_child(nm)
	nv.add_child(_label("%d/%d thành viên · Hội trưởng: %s" % [
			int(row.get("members", 0)), int(row.get("cap", 30)),
			String(row.get("leader_name", ""))], 12, sub_col))
	# 17b: the weekly-race crown holder carries a gold marker.
	if bool(row.get("champion", false)):
		var crown := _label("Vô địch tuần trước", 12,
				Color(0.24, 0.15, 0.02) if on_gold else Color(1, 0.84, 0.3))
		nv.add_child(crown)
	hb.add_child(nv)
	# Level cell (its own column, per the header grid).
	var lv := _label("Cấp %d" % int(row.get("level", 1)), 15, name_col)
	lv.custom_minimum_size = Vector2(LB_COL_LEVEL, 0)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lv)
	# Weekly points cell, right-aligned.
	var wv := VBoxContainer.new()
	wv.custom_minimum_size = Vector2(LB_COL_WEEK, 0)
	wv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wk := _label(_lb_fmt_num(int(row.get("week", 0))), 17,
			Color(0.24, 0.15, 0.02) if on_gold else Color(1, 0.95, 0.8))
	wk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wv.add_child(wk)
	var wl := _label("điểm tuần", 11, sub_col)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wv.add_child(wl)
	hb.add_child(wv)
	return card


## Ranked queue waiting presentation (13p): the ornate
## full-screen matchmaking screen replaces the old in-panel
## queue box. The queue protocol is unchanged (queue_join /
## queue_leave); match_found drops the lobby into the ranked
## room view via joined_room, and stop_queue() closes the
## screen on every view switch below.
func _build_matchmaking() -> void:
	_mm = MatchmakingScreen.new()
	_root.add_child(_mm)
	_mm.build()
	_mm.cancel_pressed.connect(_on_queue_cancel)


func _show_queue() -> void:
	_menu_box.visible = false
	_room_box.visible = false
	_panel_cc.visible = false
	if _lb_root != null:
		_lb_root.visible = false
	_queue_since = Time.get_ticks_msec()
	_set_status("")
	# No rank line on the waiting screen: the painted
	# matchmaking art Tín approved (mock v12) has none.
	_mm.start_queue(_queue_since, _queue_normal)


func is_queue_open() -> bool:
	return _mm != null and _mm.is_open()


## Capture hooks (Net's auto driver): seed the wait clock for
## the ~28 s screenshot state, and drive the cancel path
## through the exact button handler.
func set_queue_elapsed_for_test(sec: float) -> void:
	if _mm != null:
		_mm.set_elapsed_for_test(sec)


func cancel_queue_for_test() -> void:
	_on_queue_cancel()


func _on_ranked_pressed() -> void:
	if Net.account_name == "":
		_set_status("Đăng nhập để đấu xếp hạng (ghép trận + MMR).")
		return
	_queue_normal = false
	_ensure_connected()
	if Net.connected:
		Net.queue_join()
	else:
		_pending = "ranked"
		_set_status("Đang nối máy chủ...")


## Normal queue (13t): Đấu Thường matchmakes online now — the
## same painted waiting screen as ranked, but guests are allowed
## and nothing touches MMR or the ladder.
func _on_normal_pressed() -> void:
	_queue_normal = true
	_ensure_connected()
	if Net.connected:
		Net.queue_join_normal(_player_name())
	else:
		_pending = "normal"
		_set_status("Đang nối máy chủ...")


func _on_queue_cancel() -> void:
	Net.queue_leave()
	_show_menu()


## Ranked screenshot driver hook (Net's auto driver).
func press_ranked_for_test() -> void:
	_on_ranked_pressed()


## Normal-queue screenshot driver hook (Net's auto driver).
func press_normal_for_test() -> void:
	_on_normal_pressed()


func _bind_signals() -> void:
	if _signals_bound:
		return
	_signals_bound = true
	Net.room_updated.connect(_refresh_room)
	Net.joined_room.connect(func(_code: String, _slot: int) -> void: _show_room())
	Net.lobby_error.connect(func(msg: String) -> void: _set_status(msg))
	Net.match_started.connect(_on_match_started)
	Net.connection_closed.connect(func() -> void: _set_status("Mất kết nối máy chủ"))
	Net.chat_received.connect(_on_chat_received)
	Net.auth_ok.connect(func(_t: String, _p: Dictionary) -> void:
		_auth_status.text = "Đăng nhập thành công."
		_refresh_auth())
	Net.auth_error.connect(func(msg: String) -> void: _auth_status.text = msg)
	Net.auth_out.connect(func() -> void: _refresh_auth())
	Net.avatar_changed.connect(func(_id: String) -> void: _refresh_avatar_row())
	Net.leaderboard_received.connect(func(rows: Array, mode: String, me: Dictionary) -> void:
		_lb_data = rows
		_lb_me = me
		_lb_mode = Net.leaderboard_mode
		if is_leaderboard_open():
			_fill_leaderboard())
	Net.queue_joined_notice.connect(func(_mmr: int) -> void: _show_queue())
	Net.queue_status_notice.connect(func(found: int, need: int, _q: String) -> void:
		if _mm != null:
			_mm.set_found(found, need))
	Net.queue_left_notice.connect(func() -> void:
		if is_queue_open():
			_show_menu())
	# 15a: host kick / room closure land us back on the menu
	# with the reason on the status line; the browser refills
	# itself whenever a fresh list lands while it is open.
	Net.kicked_notice.connect(func() -> void:
		_show_menu()
		_set_status("Bạn đã bị chủ phòng mời ra khỏi phòng."))
	Net.room_closed_notice.connect(func() -> void:
		_show_menu()
		_set_status("Phòng đã đóng."))
	Net.room_list_received.connect(func(_rows: Array) -> void:
		if _browser_box != null and _browser_box.visible:
			_fill_browser())


func _on_chat_received(scope: String, _from: int, sender_name: String, text: String, ally_tag: String = "", _bubble: String = "mac_dinh") -> void:
	if scope != "lobby" or _chat_log == null:
		return
	# 17b: [TAG] before the sender's name when they have one.
	_chat_log.text += "%s: %s\n" % [Net.ally_disp(sender_name, ally_tag), text]


func _process(_delta: float) -> void:
	if _pending_auth != "" and Net.connected:
		var what := _pending_auth
		_pending_auth = ""
		if what == "login":
			Net.login_account(_user_edit.text.strip_edges(), _pass_edit.text)
		elif what == "register":
			Net.register_account(_user_edit.text.strip_edges(), _pass_edit.text)
	if _pending != "" and Net.connected:
		var what := _pending
		_pending = ""
		if what == "create":
			var biome := String(game.mp_host_biome()) if game != null else "grassland"
			var layout := String(game.mp_host_layout()) if game != null else "plains"
			Net.create_room(_player_name(), biome, layout, {
				"room_name": _room_name_edit.text.strip_edges(),
				"room_pass": _room_pass_edit.text,
				"public": _public_check.button_pressed,
				"allow_obs": _obs_check.button_pressed,
				"diplomacy": _dip_check.button_pressed,
				"obs_delay": _delay_seconds(_delay_opt.selected)})
		elif what == "join":
			Net.join_room(_code_edit.text.strip_edges(), _player_name(),
					_join_pass_edit.text)
		elif what == "observe":
			Net.observe_room(_code_edit.text.strip_edges(), _player_name(),
					_join_pass_edit.text)
		elif what == "ranked":
			Net.queue_join()
		elif what == "normal":
			Net.queue_join_normal(_player_name())


func open() -> void:
	visible = true
	_refresh_auth()
	if Net.room_code != "":
		_show_room()
		_refresh_room()
	else:
		_show_menu()
	if not Net.connected:
		Net.connect_to_server(_addr_edit.text.strip_edges())


## Home-lobby entry points (13g): the home screen's buttons land
## on the matching lobby view directly.
func open_for_rooms() -> void:
	open()


func open_for_account() -> void:
	open()


func open_for_ranked() -> void:
	open()
	if Net.account_name != "":
		_on_ranked_pressed()
	else:
		_set_status("Đăng nhập để đấu xếp hạng (ghép trận + MMR).")


## Home mode panel → Đấu Thường (13t): land in the lobby and join
## the normal queue straight away (guests included).
func open_for_normal() -> void:
	open()
	_on_normal_pressed()


func open_for_leaderboard() -> void:
	_lb_return_home = true
	open()
	open_ranked_leaderboard()


## Home settings write the relay address here so every connect
## path (rooms / ranked / account) uses the same server.
func set_server_url(url: String) -> void:
	if url.strip_edges() != "":
		_addr_edit.text = url.strip_edges()


func close() -> void:
	visible = false


func _show_menu() -> void:
	_panel_cc.visible = true
	_menu_box.visible = true
	_room_box.visible = false
	if _browser_box != null:
		_browser_box.visible = false
	if _lb_root != null:
		_lb_root.visible = false
	if _mm != null:
		_mm.stop_queue()
	_set_status("")


func _show_room() -> void:
	_panel_cc.visible = true
	_menu_box.visible = false
	_room_box.visible = true
	if _browser_box != null:
		_browser_box.visible = false
	if _lb_root != null:
		_lb_root.visible = false
	if _mm != null:
		_mm.stop_queue()
	_ready_state = false
	_ready_btn.text = "Sẵn sàng"
	_refresh_room()


func _set_status(msg: String) -> void:
	_status.text = msg


func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Người chơi"


func _on_create_pressed() -> void:
	_ensure_connected()
	_pending = "create"
	_set_status("Đang tạo phòng...")


func _on_join_pressed() -> void:
	if _code_edit.text.strip_edges().length() < 5:
		_set_status("Nhập mã phòng 5 ký tự")
		return
	_ensure_connected()
	_pending = "join"
	_set_status("Đang vào phòng...")


func _on_observe_pressed() -> void:
	if _code_edit.text.strip_edges().length() < 5:
		_set_status("Nhập mã phòng 5 ký tự")
		return
	_ensure_connected()
	_pending = "observe"
	_set_status("Đang vào xem phòng...")


func _ensure_connected() -> void:
	if not Net.connected:
		Net.connect_to_server(_addr_edit.text.strip_edges())


func _on_ready_pressed() -> void:
	_ready_state = not _ready_state
	_ready_btn.text = "Huỷ sẵn sàng" if _ready_state else "Sẵn sàng"
	Net.set_ready(_ready_state)


func _on_leave_pressed() -> void:
	Net.leave_room()
	_ready_state = false
	_show_menu()
	_set_status("")


func _on_match_started(_cfg: Dictionary) -> void:
	visible = false
	Net.begin_match()


func _refresh_room() -> void:
	if is_leaderboard_open():
		return # the leaderboard panel owns the view right now
	if _room_box == null or not _room_box.visible:
		if Net.room_code != "":
			_show_room()
		else:
			return
	_code_label.text = "Phòng %s" % Net.room_code
	var bname := String(Biomes.data(Net.cfg_biome).get("name", Net.cfg_biome)) \
			if Biomes.is_valid(Net.cfg_biome) else Net.cfg_biome
	_config_label.text = "Bản đồ: %s · %s%s" % [bname,
			String(World.LAYOUT_NAMES.get(Net.cfg_layout, Net.cfg_layout)),
			" · Đấu xếp hạng" if Net.ranked else (
					" · Ghép trận thường" if Net.queued_room else "")]
	# 15a: the room's public face — name + access flags — sits
	# under the map line so joiners see the full config pre-ready.
	if not Net.ranked and not Net.queued_room:
		var flags := "Phòng: %s · %s%s%s%s%s" % [Net.cfg_room_name,
				"Công khai" if Net.cfg_public else "Riêng tư",
				" · Có mật khẩu" if Net.cfg_has_password else "",
				" · Cho người xem" if Net.cfg_allow_obs else "",
				" · Ngoại giao" if Net.cfg_diplomacy else "",
				" · Trì hoãn người xem: %ds" % Net.cfg_obs_delay if Net.cfg_obs_delay > 0 else ""]
		_config_label.text += "\n" + flags
	if Net.is_observer:
		_obs_label.text = "Bạn đang xem phòng này — không có quân, chỉ xem và trò chuyện."
	elif Net.room_observers.is_empty():
		_obs_label.text = ""
	else:
		_obs_label.text = "Người xem: %s" % ", ".join(Net.room_observers)
	# 15e: the host of a custom room can remove an observer (the
	# kick also bans their return — server KickObserver). Rows
	# rebuild with the room view; everyone else just sees the
	# name list above.
	for ch in _obs_box.get_children():
		ch.queue_free()
	if Net.is_host and not Net.ranked and not Net.queued_room \
			and not Net.is_observer:
		for oname in Net.room_observers:
			var orow2 := HBoxContainer.new()
			orow2.add_theme_constant_override("separation", 8)
			orow2.alignment = BoxContainer.ALIGNMENT_CENTER
			_obs_box.add_child(orow2)
			orow2.add_child(_label("Người xem: %s" % String(oname), 12, TXT))
			var kick_b := _button("Đuổi")
			kick_b.custom_minimum_size = Vector2(64, 28)
			var nm := String(oname)
			kick_b.pressed.connect(func() -> void: Net.kick_observer(nm))
			orow2.add_child(kick_b)
	for ch in _players_box.get_children():
		ch.queue_free()
	var all_ready := Net.players.size() >= 2
	for p in Net.players:
		_players_box.add_child(_player_row(p))
		if not bool(p.get("ready", false)) or not bool(p.get("connected", true)):
			all_ready = false
	# Queue rooms (ranked AND normal, 13t) skip ready/start
	# entirely: the server starts the match on its countdown once
	# both players are in.
	_ready_btn.visible = not Net.ranked and not Net.queued_room
	_start_btn.visible = Net.is_host and not Net.ranked and not Net.queued_room
	_start_btn.disabled = not (Net.is_host and all_ready)
	_ready_btn.disabled = false
	# 15a: observers get no ready/start; the host of a custom
	# room gets the config editor (populated once per room/host).
	if Net.is_observer:
		_ready_btn.visible = false
		_start_btn.visible = false
	var host_custom := Net.is_host and not Net.ranked and not Net.queued_room \
			and not Net.is_observer
	_cfg_box.visible = host_custom
	if host_custom:
		var key := Net.room_code + ":" + str(Net.host_slot)
		if _cfg_populated_key != key:
			_cfg_populated_key = key
			_cfg_name_edit.text = Net.cfg_room_name
			_cfg_public_check.button_pressed = Net.cfg_public
			_cfg_obs_check.button_pressed = Net.cfg_allow_obs
			_cfg_dip_check.button_pressed = Net.cfg_diplomacy
			_cfg_delay_opt.select(_delay_index(Net.cfg_obs_delay))
			var bi := Biomes.ORDER.find(Net.cfg_biome)
			if bi >= 0:
				_cfg_biome_opt.select(bi)
			var li := World.LAYOUT_NAMES.keys().find(Net.cfg_layout)
			if li >= 0:
				_cfg_layout_opt.select(li)


func _player_row(p: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _sb(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.04), 8))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	var slot := int(p.get("slot", 0))
	hb.add_child(_label("Ô %d" % (slot + 1), 15, GOLD_TXT))
	var nm := String(p.get("name", "?"))
	if slot == Net.my_slot:
		nm += " (Bạn)"
	if slot == Net.host_slot:
		nm += " · Chủ phòng"
	# Player names wear their SLOT colour (TeamColors) + the colour's
	# name, so a 4-player room reads its 4 colours before the match.
	hb.add_child(_label(nm, 15, TeamColors.ui_color(slot).lightened(0.35)))
	hb.add_child(_label("Màu " + TeamColors.color_name(slot), 13,
			TeamColors.ui_color(slot).lightened(0.35)))
	hb.add_child(_label("Đội %d" % (int(p.get("team", 0)) + 1), 14, TXT_DIM))
	if bool(p.get("account", false)):
		hb.add_child(_label("Tài khoản", 13, GOLD_TXT))
	else:
		hb.add_child(_label("Khách", 13, TXT_DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	# 15a host powers (custom rooms only): kick also bans the
	# player from THIS room; transfer hands over the host role.
	if Net.is_host and not Net.ranked and not Net.queued_room \
			and not Net.is_observer and slot != Net.my_slot:
		var kick_b := _button("Đuổi")
		kick_b.custom_minimum_size = Vector2(64, 30)
		kick_b.pressed.connect(func() -> void: Net.kick_player(slot))
		hb.add_child(kick_b)
		var tr_b := _button("Nhường chủ")
		tr_b.custom_minimum_size = Vector2(104, 30)
		tr_b.pressed.connect(func() -> void: Net.transfer_host(slot))
		hb.add_child(tr_b)
	if not bool(p.get("connected", true)):
		hb.add_child(_label("Mất kết nối", 14, RED))
	elif bool(p.get("ready", false)):
		hb.add_child(_label("Sẵn sàng", 14, GREEN))
	else:
		hb.add_child(_label("Chưa sẵn sàng", 14, TXT_DIM))
	return row
