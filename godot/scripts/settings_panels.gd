class_name SettingsPanels
extends CanvasLayer

## Personal settings (17d) — the profile gear's hub and its
## four panels, in the 13w modal dialect (centred panel, solid
## navy, 2px gold border, dim backdrop):
##
##   Hub       — exactly 4 entries: Đổi tên · Avatar ·
##               Danh hiệu · Trang trí.
##   Đổi tên   — rename with the server-enforced 30-day
##               cooldown (the panel shows the next date).
##   Avatar    — 2 tabs: Avatar (the owner's 20 anime
##               avatars, all free) and Khung avatar (the 11
##               owner frames + "Không khung". Frames are
##               ITEMS (rule change 2026-11-12): possession
##               is server-recorded; tapping any item opens
##               its detail popup — unowned items show
##               "Cách nhận: Nhận qua sự kiện", owned items
##               equip from the popup).
##   Danh hiệu — the full title catalogue from the profile
##               payload: name, how it's earned, owned state
##               and thời hạn; equipping uses the account's
##               display_title.
##   Trang trí — tabbed shell; only the first tab exists:
##               Bong bóng chat (bubble styles, same
##               ownership pattern).
##
## Everything here is presentation: picks go through Net ops
## and the server validates ownership/cooldown; the panels
## re-render from the profile_update reply.

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
const MODAL_BG := Color(0.035, 0.05, 0.11, 0.94)

# Frame catalogue mirrors (server cosmetics.go is the truth;
# these strings only label rows the profile already resolved).
const FRAME_NAMES := {
	"frame_01": "Dây Dâu Tây", "frame_03": "Mặt Mèo",
	"frame_04": "Hoa Hồng Bướm Xanh", "frame_05": "Sân Khấu Trái Tim",
	"frame_06": "Sao Vàng", "frame_07": "Cột Hy Lạp",
	"frame_08": "Mây Anh Đào", "frame_09": "Rèm Sân Khấu",
	"frame_10": "Cửa Sổ Anh Đào", "frame_11": "Đá Rêu Nấm",
	"frame_12": "Ruy Băng Sao",
}
const FRAME_UNLOCK := {
	"frame_01": "Sự kiện", "frame_03": "Sự kiện",
	"frame_04": "Sự kiện", "frame_05": "Sự kiện",
	"frame_06": "Sự kiện", "frame_07": "Sự kiện",
	"frame_08": "Sự kiện", "frame_09": "Sự kiện",
	"frame_10": "Sự kiện", "frame_11": "Sự kiện",
	"frame_12": "Sự kiện",
}
const BUBBLE_UNLOCK := {
	"mac_dinh": "Có sẵn cho mọi tài khoản",
	"hang": "Sự kiện",
	"vo_dich": "Sự kiện",
}

var game = null # Main (duck-typed)

var _body: VBoxContainer
var _view := "hub" # hub | rename | avatar | titles | decor
var _avatar_tab := "avatar" # avatar | frames
var _status_msg := ""
var _status_bad := false
var _rename_edit: LineEdit = null
var _detail_root: Control = null # item-detail popup (grant items)

class BubblePreview:
	extends Control
	var style_id := "mac_dinh"
	var sample := "Xin chào mọi người!"
	func _draw() -> void:
		ChatBubbles.paint(self, ThemeDB.fallback_font, size * 0.5, sample, style_id)


func setup(p_game) -> void:
	game = p_game
	layer = 56 # above the profile (50), below the MP lobby (60)
	_build()
	visible = false
	Net.profile_updated.connect(func(_p) -> void:
		if visible:
			_set_status("Đã lưu.", false)
			_render())
	Net.avatar_changed.connect(func(_a) -> void:
		if visible: _render())
	Net.display_name_changed.connect(func(n: String) -> void:
		if visible:
			_set_status("Đã đổi tên thành " + n, false)
			_render())
	Net.name_error.connect(func(msg: String) -> void:
		if visible:
			_set_status(msg, true)
			_render())
	Net.lobby_error.connect(func(msg: String) -> void:
		if visible:
			_set_status(msg, true)
			_render())


func _close_detail() -> void:
	if _detail_root != null:
		_detail_root.queue_free()
		_detail_root = null


func _center_label(text: String, fsize: int, col: Color) -> Label:
	var l := _label(text, fsize, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Item-detail popup (owner correction 2026-11-12 18:35):
## tapping ANY frame / title / bubble row opens this small
## navy/gold popup — preview, name, and either
## "Cách nhận: Nhận qua sự kiện" (unowned, no equip button)
## or "Đã sở hữu" + a "Trang bị" button (owned; "Đang dùng"
## when equipped). Equipping happens HERE, never by direct
## tap on a row. Player copy never mentions how items are
## distributed behind the scenes.
func _open_item_detail(kind: String, item_id: String, disp_name: String,
		is_owned: bool, is_equipped: bool, extra: String = "") -> void:
	_close_detail()
	_detail_root = Control.new()
	_detail_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_detail_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_detail())
	_detail_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_root.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var ps := _sb(MODAL_BG, 14, GOLD_TXT, 2)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 14
	ps.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", ps)
	cc.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	match kind:
		"frame":
			var holder := AvatarFrame.new()
			holder.custom_minimum_size = Vector2(120, 120)
			holder.set_content(Avatars.texture_for(Avatars.local_avatar()), item_id, true)
			var hc := CenterContainer.new()
			hc.add_child(holder)
			col.add_child(hc)
			col.add_child(_center_label(disp_name, 18, GOLD_TXT))
		"title":
			col.add_child(_center_label(disp_name, 22, GOLD_TXT))
		"bubble":
			var prev := BubblePreview.new()
			prev.style_id = item_id
			prev.custom_minimum_size = Vector2(250, 70)
			col.add_child(prev)
			col.add_child(_center_label(disp_name, 18, GOLD_TXT))
	if is_equipped:
		col.add_child(_center_label("Đang dùng", 14, GOLD_TXT))
	elif is_owned:
		col.add_child(_center_label("Đã sở hữu", 14, Color(0.55, 0.9, 0.55)))
		if extra != "":
			col.add_child(_center_label(extra, 12, MUTED))
		var eb := _button("Trang bị", true, 150)
		eb.pressed.connect(func() -> void: _equip_from_detail(kind, item_id, disp_name))
		var ec := CenterContainer.new()
		ec.add_child(eb)
		col.add_child(ec)
	else:
		col.add_child(_center_label("Cách nhận: Nhận qua sự kiện", 14, PAPER))
	var cb := _button("Đóng", false, 110)
	cb.pressed.connect(func() -> void: _close_detail())
	var bc := CenterContainer.new()
	bc.add_child(cb)
	col.add_child(bc)


func _equip_from_detail(kind: String, item_id: String, disp_name: String) -> void:
	match kind:
		"frame":
			Net.set_frame(item_id)
		"title":
			Net.set_title(item_id)
		"bubble":
			Net.set_bubble(item_id)
	_close_detail()
	_set_status("Đã trang bị " + disp_name + ".", false)
	_render()


## shot_open_frame_detail is the capture hook for the item
## popup: frames tab + the detail of one (usually unowned)
## frame.
func shot_open_frame_detail(fid: String) -> void:
	open("frames")
	var p: Dictionary = Net.auth_profile
	var owned: Array = p.get("owned_frames", [])
	_open_item_detail("frame", fid, String(FRAME_NAMES.get(fid, fid)),
		owned.has(fid), String(p.get("frame_id", "")) == fid)


func open(which: String = "hub") -> void:
	_view = which if which in ["hub", "rename", "avatar", "frames", "titles", "decor"] else "hub"
	if _view == "frames":
		_view = "avatar"
		_avatar_tab = "frames"
	elif _view == "avatar":
		_avatar_tab = "avatar"
	_status_msg = ""
	visible = true
	_render()


func close() -> void:
	_close_detail()
	visible = false


# ------------------------------------------------------------ shell

func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


# 17c rule: explicit content margins on every button stylebox
# (unset margins fall back to border width and shift text).
func _btn_sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := _sb(bg, radius, border, bw)
	s.content_margin_left = 1
	s.content_margin_right = 1
	s.content_margin_top = 0
	s.content_margin_bottom = 2
	return s


func _label(text: String, fsize: int, col: Color = PAPER) -> Label:
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


func _button(text: String, primary := false, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 38)
	b.add_theme_font_size_override("font_size", 14)
	if primary:
		b.add_theme_stylebox_override("normal", _btn_sb(Color(0.98, 0.8, 0.35), 8))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(1.0, 0.86, 0.45), 8))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.88, 0.7, 0.28), 8))
		b.add_theme_stylebox_override("disabled", _btn_sb(Color(0.35, 0.33, 0.28), 8))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_disabled_color", Color(0.6, 0.58, 0.52))
	else:
		b.add_theme_stylebox_override("normal", _btn_sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(0.18, 0.22, 0.32), 8, Color(1, 0.85, 0.4, 0.6), 1))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.09, 0.11, 0.19), 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_color_override("font_color", PAPER)
		b.add_theme_color_override("font_hover_color", PAPER)
	return b


func _tab_btn(text: String, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	if active:
		b.add_theme_stylebox_override("normal", _btn_sb(Color(0.98, 0.8, 0.35), 8, Color(0.72, 0.52, 0.10), 1))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(1.0, 0.86, 0.45), 8, Color(0.72, 0.52, 0.10), 1))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.98, 0.8, 0.35), 8, Color(0.72, 0.52, 0.10), 1))
		b.add_theme_color_override("font_color", Color(0.12, 0.09, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.02))
	else:
		b.add_theme_stylebox_override("normal", _btn_sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(0.18, 0.22, 0.32), 8, Color(1, 0.85, 0.4, 0.6), 1))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.09, 0.11, 0.19), 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_color_override("font_color", PAPER)
		b.add_theme_color_override("font_hover_color", PAPER)
	return b


func _card(pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _sb(CARD_BG, 12, PANEL_LINE, 1)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", s)
	return p


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close())
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 640)
	var ps := _sb(MODAL_BG, 14, GOLD_TXT, 2)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 14
	ps.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", ps)
	cc.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	panel.add_child(_body)


func _set_status(msg: String, bad: bool) -> void:
	_status_msg = msg
	_status_bad = bad


func _header(title: String, _back: bool) -> void:
	# Owner order 2026-11-12: NO "Quay lại" button on the
	# settings sub-panels — the red X is the only way out.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var t := _label(title, 20, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var x := Button.new()
	x.text = "X"
	x.custom_minimum_size = Vector2(36, 36)
	x.add_theme_font_size_override("font_size", 15)
	x.add_theme_stylebox_override("normal", _btn_sb(Color(0.62, 0.16, 0.13), 10))
	x.add_theme_stylebox_override("hover", _btn_sb(Color(0.75, 0.2, 0.16), 10))
	x.add_theme_stylebox_override("pressed", _btn_sb(Color(0.5, 0.12, 0.1), 10))
	x.add_theme_color_override("font_color", Color.WHITE)
	x.add_theme_color_override("font_hover_color", Color.WHITE)
	x.tooltip_text = "Đóng"
	x.pressed.connect(func() -> void: close())
	row.add_child(x)
	_body.add_child(row)


func _status_line() -> void:
	if _status_msg == "":
		return
	_body.add_child(_label_wrap(_status_msg, 13, RED if _status_bad else Color(0.55, 0.9, 0.55)))


func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return sc


func _fmt_date(unix_s: int) -> String:
	var d := Time.get_date_dict_from_unix_time(unix_s)
	return "%02d/%02d/%04d" % [int(d["day"]), int(d["month"]), int(d["year"])]


func _render() -> void:
	_close_detail()
	_render_body()


func _render_body() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_rename_edit = null
	match _view:
		"hub": _render_hub()
		"rename": _render_rename()
		"avatar": _render_avatar()
		"titles": _render_titles()
		"decor": _render_decor()
	_status_line()


# ------------------------------------------------------------ hub

func _hub_row(title: String, sub: String, view: String) -> Control:
	var card := _card(12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(_label(title, 17, PAPER))
	col.add_child(_label(sub, 13, MUTED))
	row.add_child(col)
	var go := _label(">", 20, GOLD)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(go)
	card.add_child(row)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func() -> void:
		_view = view
		_status_msg = ""
		_render())
	card.add_child(btn)
	return card


func _render_hub() -> void:
	_header("Cài đặt cá nhân", false)
	_body.add_child(_hub_row("Đổi tên", "Tên hiển thị — đổi 1 lần mỗi 30 ngày", "rename"))
	_body.add_child(_hub_row("Avatar", "Ảnh đại diện và khung avatar", "avatar"))
	_body.add_child(_hub_row("Danh hiệu", "Danh hiệu bạn sở hữu và đang dùng", "titles"))
	_body.add_child(_hub_row("Trang trí", "Bong bóng chat trong trận", "decor"))
	var note := _label_wrap("Mọi thay đổi đều được máy chủ kiểm chứng và lưu vào tài khoản của bạn.", 12, DIM)
	_body.add_child(note)


# ------------------------------------------------------------ rename

func _render_rename() -> void:
	_header("Đổi tên", true)
	var guest := Net.account_name == ""
	var p: Dictionary = Net.auth_profile
	var cur := Net.display_name()
	var card := _card(14)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.add_child(_label("Tên hiện tại", 13, MUTED))
	col.add_child(_label(cur if cur != "" else "(chưa đặt)", 20, PAPER))
	col.add_child(HSeparator.new())
	col.add_child(_label("Tên mới", 13, MUTED))
	_rename_edit = LineEdit.new()
	_rename_edit.text = cur
	_rename_edit.max_length = 16
	_rename_edit.custom_minimum_size = Vector2(0, 40)
	_rename_edit.add_theme_font_size_override("font_size", 16)
	_rename_edit.add_theme_stylebox_override("normal", _sb(FIELD_BG, 8, PANEL_LINE, 1))
	_rename_edit.add_theme_stylebox_override("focus", _sb(FIELD_BG, 8, GOLD_TXT, 1))
	_rename_edit.editable = not guest
	col.add_child(_rename_edit)
	col.add_child(_label_wrap("Quy định: 3–16 ký tự, gồm chữ cái, chữ số và dấu gạch dưới; tên không được trùng với người chơi khác. Mỗi tài khoản chỉ đổi tên 1 lần mỗi 30 ngày (lần đặt tên đầu tiên không tính).", 13, MUTED))
	var next_at := int(p.get("rename_next_at", 0))
	var now := int(Time.get_unix_time_from_system())
	var btn := _button("Đổi tên", true, 160)
	if guest:
		col.add_child(_label_wrap("Đăng nhập để đổi tên.", 13, RED))
		btn.disabled = true
	elif next_at > now:
		col.add_child(_label_wrap("Bạn đã đổi tên gần đây — đổi lại được từ %s." % _fmt_date(next_at), 13, RED))
		btn.disabled = true
	btn.pressed.connect(func() -> void:
		var nm := _rename_edit.text.strip_edges()
		if nm == "" or nm == Net.display_name():
			_set_status("Hãy nhập một tên mới khác tên hiện tại.", true)
			_render()
			return
		Net.rename(nm))
	col.add_child(btn)
	card.add_child(col)
	_body.add_child(card)


# ------------------------------------------------------------ avatar

func _render_avatar() -> void:
	_header("Avatar", true)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	var t1 := _tab_btn("Avatar", _avatar_tab == "avatar")
	t1.pressed.connect(func() -> void:
		_avatar_tab = "avatar"
		_render())
	tabs.add_child(t1)
	var t2 := _tab_btn("Khung avatar", _avatar_tab == "frames")
	t2.pressed.connect(func() -> void:
		_avatar_tab = "frames"
		_render())
	tabs.add_child(t2)
	_body.add_child(tabs)
	if _avatar_tab == "avatar":
		_render_avatar_tab()
	else:
		_render_frames_tab()


func _render_avatar_tab() -> void:
	_body.add_child(_label_wrap("Chọn ảnh đại diện — cả 20 ảnh đều miễn phí cho mọi tài khoản.", 13, MUTED))
	var sc := _scroll()
	var grid := GridContainer.new()
	grid.columns = 4 # owner order 2026-11-12: rows of 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	var sel := Avatars.local_avatar()
	for id in Avatars.IDS:
		grid.add_child(_avatar_cell(id, sel))
	_body.add_child(sc)


func _avatar_cell(id: String, sel: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(136, 136)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var is_sel := id == sel
	holder.add_theme_stylebox_override("panel",
		_sb(Color(0.08, 0.09, 0.14), 10, GOLD_TXT if is_sel else PANEL_LINE, 2 if is_sel else 1))
	var tr := TextureRect.new()
	tr.texture = Avatars.texture_for(id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = Avatars.display_name(id)
	btn.pressed.connect(func() -> void:
		Net.set_avatar(id)
		_set_status("Đã chọn " + Avatars.display_name(id) + ".", false)
		_render())
	holder.add_child(btn)
	col.add_child(holder)
	var nm := _label(Avatars.display_name(id) + (" · Đang dùng" if is_sel else ""), 12,
		GOLD_TXT if is_sel else MUTED)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)
	return col


func _render_frames_tab() -> void:
	var p: Dictionary = Net.auth_profile
	var owned: Array = p.get("owned_frames", [])
	var equipped := String(p.get("frame_id", ""))
	var my_avatar := Avatars.texture_for(Avatars.local_avatar())
	_body.add_child(_label_wrap("Khung bọc quanh avatar của bạn — chạm vào một khung để xem chi tiết và trang bị.", 13, MUTED))
	var sc := _scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	list.add_child(_frame_row("", "Không khung", "Mặc định — không dùng khung",
		true, equipped == "", my_avatar))
	for fid in AvatarFrame.frame_ids():
		var is_owned := owned.has(fid)
		var sub := "Đã sở hữu" if is_owned else String(FRAME_UNLOCK.get(fid, ""))
		list.add_child(_frame_row(fid, String(FRAME_NAMES.get(fid, fid)),
			sub, is_owned, equipped == fid, my_avatar))
	_body.add_child(sc)


func _frame_row(fid: String, fname: String, unlock: String, is_owned: bool,
		is_equipped: bool, my_avatar: Texture2D) -> Control:
	var card := _card(10)
	if not is_owned:
		card.modulate = Color(1, 1, 1, 0.55)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var holder := AvatarFrame.new()
	holder.custom_minimum_size = Vector2(84, 84)
	holder.set_content(my_avatar, fid, true)
	row.add_child(holder)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(_label(fname, 16, PAPER if is_owned else MUTED))
	col.add_child(_label_wrap(unlock, 12, MUTED))
	row.add_child(col)
	if is_equipped:
		var pill := _label("Đang dùng", 13, GOLD_TXT)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pill)
	card.add_child(row)
	# Tap anywhere on the row -> the item-detail popup
	# (equipping lives there, not on the row).
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func() -> void:
		_open_item_detail("frame", fid, fname, is_owned, is_equipped))
	card.add_child(tap)
	return card


# ------------------------------------------------------------ titles

func _render_titles() -> void:
	_header("Danh hiệu", true)
	var p: Dictionary = Net.auth_profile
	var rows: Array = p.get("title_rows", [])
	var equipped := String(p.get("display_title", ""))
	if Net.account_name == "":
		_body.add_child(_label_wrap("Đăng nhập để xem và dùng danh hiệu.", 13, RED))
		return
	if equipped != "":
		var clear_row := HBoxContainer.new()
		clear_row.add_theme_constant_override("separation", 10)
		var cl := _label("Đang dùng: " + equipped, 14, GOLD_TXT)
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		clear_row.add_child(cl)
		var cb := _button("Bỏ dùng", false, 96)
		cb.pressed.connect(func() -> void: Net.set_title(""))
		clear_row.add_child(cb)
		_body.add_child(clear_row)
	var sc := _scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for r in rows:
		list.add_child(_title_row(r))
	_body.add_child(sc)


func _title_row(r: Dictionary) -> Control:
	var owned := bool(r.get("owned", false))
	var equipped := bool(r.get("equipped", false))
	var card := _card(12)
	if not owned:
		card.modulate = Color(1, 1, 1, 0.55)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(_label(String(r.get("name", "")), 16, GOLD_TXT if owned else MUTED))
	col.add_child(_label_wrap(String(r.get("how", "")), 12, MUTED))
	if owned:
		col.add_child(_label("Thời hạn: " + String(r.get("expiry", "")), 12, PAPER))
	row.add_child(col)
	if equipped:
		var pill := _label("Đang dùng", 13, GOLD_TXT)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pill)
	card.add_child(row)
	var nm := String(r.get("name", ""))
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func() -> void:
		_open_item_detail("title", nm, nm, owned, equipped,
			"Thời hạn: " + String(r.get("expiry", ""))))
	card.add_child(tap)
	return card


# ------------------------------------------------------------ decor

func _render_decor() -> void:
	_header("Trang trí", true)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	# The shell's only tab for now — shown active (gold); future
	# decoration tabs slot in beside it.
	var t1 := _tab_btn("Bong bóng chat", true)
	tabs.add_child(t1)
	_body.add_child(tabs)
	var p: Dictionary = Net.auth_profile
	var owned: Array = p.get("owned_bubbles", [])
	var equipped := String(p.get("bubble_style", "mac_dinh"))
	_body.add_child(_label_wrap("Kiểu bong bóng khi bạn chat trong trận — bong bóng hiện trên đầu tướng khoảng 4 giây, theo đúng kiểu đang dùng.", 13, MUTED))
	var sc := _scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for bid in ChatBubbles.STYLE_IDS:
		list.add_child(_bubble_row(bid, owned.has(bid), equipped == bid))
	_body.add_child(sc)


func _bubble_row(bid: String, is_owned: bool, is_equipped: bool) -> Control:
	var st: Dictionary = ChatBubbles.STYLES[bid]
	var card := _card(12)
	if not is_owned:
		card.modulate = Color(1, 1, 1, 0.55)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var prev := BubblePreview.new()
	prev.style_id = bid
	prev.custom_minimum_size = Vector2(230, 64)
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(prev)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(_label(String(st.get("name", bid)), 16, PAPER if is_owned else MUTED))
	var sub := String(BUBBLE_UNLOCK.get(bid, "")) if not is_owned else "Đã sở hữu"
	if bid == ChatBubbles.STYLE_IDS[0]:
		sub = String(BUBBLE_UNLOCK.get(bid, ""))
	col.add_child(_label_wrap(sub, 12, MUTED))
	row.add_child(col)
	if is_equipped:
		var pill := _label("Đang dùng", 13, GOLD_TXT)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pill)
	card.add_child(row)
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func() -> void:
		_open_item_detail("bubble", bid, String(st.get("name", bid)), is_owned, is_equipped))
	card.add_child(tap)
	return card
