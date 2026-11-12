extends Node
## DESIGN MOCKUPS ONLY (throwaway capture tooling — NOT game code):
## the proposed Liên minh (alliance) page in the shipped page
## dialect (PageShell header + solid navy board + tournament/
## collection cards), three variants for the owner's A/B gate:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_alliance_mock.tscn
##   A) empire_age_alliance_mockA_v1.png    — one scroll column
##   B) empire_age_alliance_mockB_v1.png    — two columns + tabs
##   C) empire_age_alliance_mock_join_v1.png — not in an alliance

const GOLD := Color(0.98, 0.8, 0.35)
const GOLD_TXT := Color(0.96, 0.8, 0.45)
const PAPER := Color(0.96, 0.94, 0.88)
const MUTED := Color(0.72, 0.76, 0.86)
const DIM := Color(0.64, 0.7, 0.8)
const CARD := Color(0.05, 0.08, 0.16, 1.0)
const CARD_SOFT := Color(0.07, 0.1, 0.18, 0.55)
const CARD_BORDER := Color(1, 0.85, 0.4, 0.25)
const FIELD_BG := Color(0.02, 0.04, 0.09, 0.9)
const GREEN := Color(0.45, 0.95, 0.5)
const OFFLINE := Color(0.45, 0.48, 0.55)
const RED := Color(0.98, 0.5, 0.45)
const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"

const FA_USERS := 0xF0C0
const FA_USER_PLUS := 0xF234
const FA_COMMENTS := 0xF086
const FA_GEAR := 0xF013
const FA_CROWN := 0xF521
const FA_SEARCH := 0xF002
const FA_PLUS := 0x2B
const FA_LEAVE := 0xF2F5
const FA_CHECK := 0xF00C
const FA_XMARK := 0xF00D
const FA_BOLT := 0xF0E7

var _fa_font: Font = null
var _page: Control = null


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
		# Gold star at the shield's heart.
		var c := Vector2(0.5 * w, 0.40 * h)
		var r := 0.19 * minf(w, h)
		var star := PackedVector2Array()
		for i in 10:
			var ang := -PI * 0.5 + i * PI / 5.0
			var rad := r if i % 2 == 0 else r * 0.45
			star.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(star, Color(1.0, 0.82, 0.3))


# ------------------------------------------------------------ helpers

func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


func _card(pad: int = 12, bw: int = 1, bg: Color = CARD) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _sb(bg, 10, CARD_BORDER, bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", s)
	return p


func _label(text: String, fsize: int, col: Color = PAPER, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
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


func _icon_btn(text: String, cp: int, kind: String, min_w: float = 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	var txt_col := PAPER
	match kind:
		"primary":
			p.add_theme_stylebox_override("panel", _sb(Color(0.98, 0.8, 0.35), 8))
			txt_col = Color(0.1, 0.08, 0.02)
		"danger":
			p.add_theme_stylebox_override("panel",
					_sb(Color(0.13, 0.16, 0.24), 8, Color(0.98, 0.5, 0.45, 0.55), 1))
			txt_col = RED
		"disabled":
			p.add_theme_stylebox_override("panel",
					_sb(Color(1, 1, 1, 0.03), 8, Color(1, 1, 1, 0.10), 1))
			txt_col = DIM
		_:
			p.add_theme_stylebox_override("panel",
					_sb(Color(0.13, 0.16, 0.24), 8, Color(1, 0.85, 0.4, 0.35), 1))
	p.custom_minimum_size = Vector2(min_w, 38)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 7)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cp != 0:
		hb.add_child(_fa(cp, 14, txt_col))
	hb.add_child(_label(text, 14, txt_col))
	p.add_child(hb)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.add_child(btn)
	return p


func _pill(text: String, fill: Color, txt_col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _sb(fill, 7)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(_label(text, 12, txt_col, HORIZONTAL_ALIGNMENT_CENTER))
	return p


func _role_pill(role: String) -> PanelContainer:
	match role:
		"Hội trưởng":
			return _pill(role, Color(0.98, 0.8, 0.35), Color(0.1, 0.08, 0.02))
		"Phó":
			return _pill(role, Color(0.2, 0.28, 0.45), PAPER)
		_:
			return _pill(role, Color(1, 1, 1, 0.06), MUTED)


func _dot(online: bool) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(10, 10)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel",
			_sb(GREEN if online else OFFLINE, 5, Color(0, 0, 0, 0.4), 1))
	return p


func _avatar(id: String, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Characters.avatar_for(id)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _xp_bar(frac: float, h: float = 18.0) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(0, h)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Panel.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.add_theme_stylebox_override("panel",
			_sb(Color(1, 1, 1, 0.10), 6, Color(1, 0.85, 0.4, 0.30), 1))
	root.add_child(back)
	var fill := Panel.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.anchor_right = frac
	fill.offset_right = 0
	fill.add_theme_stylebox_override("panel", _sb(Color(0.98, 0.75, 0.30), 6))
	root.add_child(fill)
	return root


func _sp(w: float = 0.0, h: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _badge(fill: Color, px: int) -> ShieldBadge:
	var b := ShieldBadge.new()
	b.fill = fill
	b.custom_minimum_size = Vector2(px, px)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


# ------------------------------------------------------------ mock data

const MEMBERS: Array = [
	{"name": "Tín", "av": "knight", "role": "Hội trưởng", "ct": "3.850", "on": true, "seen": "Trực tuyến", "lv": 48},
	{"name": "Gà Con", "av": "mage", "role": "Phó", "ct": "3.420", "on": true, "seen": "Trực tuyến", "lv": 45},
	{"name": "MinhKhang", "av": "berserker", "role": "Phó", "ct": "3.105", "on": false, "seen": "2 giờ trước", "lv": 44},
	{"name": "BaoChau", "av": "archer", "role": "Thành viên", "ct": "2.940", "on": true, "seen": "Trực tuyến", "lv": 41},
	{"name": "TuanAnh", "av": "dragoon", "role": "Thành viên", "ct": "2.610", "on": true, "seen": "Trực tuyến", "lv": 40},
	{"name": "NgocLinh", "av": "paladin", "role": "Thành viên", "ct": "2.305", "on": false, "seen": "Hôm qua", "lv": 39},
	{"name": "DucHuy", "av": "assassin", "role": "Thành viên", "ct": "1.980", "on": true, "seen": "Trực tuyến", "lv": 37},
]

const REQUESTS: Array = [
	{"name": "KhanhLy", "av": "ranger", "lv": 36, "when": "2 giờ trước", "msg": "Xin chào, mình chơi mỗi ngày, rất mong được vào liên minh."},
	{"name": "VanDuc", "av": "knight", "lv": 33, "when": "5 giờ trước", "msg": ""},
]

const ALLIANCES: Array = [
	{"name": "ĐOÀN KỴ SĨ AURELION", "fill": Color(0.45, 0.08, 0.1), "meta": "Cấp 7 · 24/30 thành viên · Hội trưởng: Tín", "mode": "Tuyển: duyệt đơn", "sent": false},
	{"name": "HỘI RỒNG XANH", "fill": Color(0.05, 0.35, 0.38), "meta": "Cấp 5 · 18/30 thành viên · Hội trưởng: BaoNgoc", "mode": "Tuyển: mở", "sent": false},
	{"name": "THÁNH ĐIỆN VÀNG", "fill": Color(0.45, 0.35, 0.05), "meta": "Cấp 6 · 29/30 thành viên · Hội trưởng: DucAnh", "mode": "Sắp đầy", "sent": false},
	{"name": "BÓNG ĐÊM TĨNH LẶNG", "fill": Color(0.25, 0.12, 0.42), "meta": "Cấp 4 · 12/30 thành viên · Hội trưởng: NgocLinh", "mode": "Tuyển: duyệt đơn", "sent": true},
	{"name": "HỘI THỢ SĂN BÌNH MINH", "fill": Color(0.10, 0.32, 0.12), "meta": "Cấp 3 · 9/30 thành viên · Hội trưởng: SonLam", "mode": "Tuyển: mở", "sent": false},
]


# ------------------------------------------------------------ shared bits

func _member_row(m: Dictionary, own: bool = false) -> PanelContainer:
	var row := PanelContainer.new()
	var s := _sb(CARD_SOFT, 8, Color(0.98, 0.8, 0.35, 0.45) if own else Color(0, 0, 0, 0), 1 if own else 0)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", s)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	hb.add_child(_avatar(String(m["av"]), 38))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override("separation", 7)
	nm.add_child(_label(String(m["name"]), 15, GOLD_TXT if own else PAPER))
	if String(m["role"]) == "Hội trưởng":
		var cr := _fa(FA_CROWN, 12, GOLD)
		cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.add_child(cr)
	vb.add_child(nm)
	vb.add_child(_label("Cấp %d" % int(m["lv"]), 12, DIM))
	hb.add_child(vb)
	var rp := _role_pill(String(m["role"]))
	rp.custom_minimum_size = Vector2(96, 0)
	hb.add_child(rp)
	var ct := _label(String(m["ct"]), 15, PAPER, HORIZONTAL_ALIGNMENT_RIGHT)
	ct.custom_minimum_size = Vector2(110, 0)
	ct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ct)
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 6)
	st.custom_minimum_size = Vector2(118, 0)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_child(_dot(bool(m["on"])))
	st.add_child(_label(String(m["seen"]), 12, DIM))
	hb.add_child(st)
	return row


func _col_header() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var a := _label("NGƯỜI CHƠI", 12, DIM)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(a)
	var b := _label("VAI TRÒ", 12, DIM)
	b.custom_minimum_size = Vector2(96, 0)
	hb.add_child(b)
	var c := _label("ĐÓNG GÓP TUẦN", 12, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	c.custom_minimum_size = Vector2(110, 0)
	hb.add_child(c)
	var d := _label("TRẠNG THÁI", 12, DIM)
	d.custom_minimum_size = Vector2(118, 0)
	hb.add_child(d)
	return hb


func _section(text: String, extra: String = "") -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(_label(text, 15, GOLD_TXT))
	if extra != "":
		hb.add_child(_label(extra, 13, DIM))
	return hb


func _request_row(r: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	var s := _sb(CARD_SOFT, 8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", s)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	hb.add_child(_avatar(String(r["av"]), 38))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_child(_label("%s · Cấp %d · %s" % [String(r["name"]), int(r["lv"]), String(r["when"])], 14, PAPER))
	if String(r["msg"]) != "":
		vb.add_child(_label("“%s”" % String(r["msg"]), 12, DIM))
	hb.add_child(vb)
	var ok := _icon_btn("Duyệt", FA_CHECK, "primary", 92)
	ok.custom_minimum_size.y = 34
	hb.add_child(ok)
	var no := _icon_btn("Từ chối", FA_XMARK, "ghost", 92)
	no.custom_minimum_size.y = 34
	hb.add_child(no)
	return row


func _header_card() -> PanelContainer:
	var card := _card(12, 2)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	card.add_child(hb)
	hb.add_child(_badge(Color(0.45, 0.08, 0.1), 78))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override("separation", 9)
	nm.add_child(_label("ĐOÀN KỴ SĨ AURELION", 23, GOLD_TXT))
	nm.add_child(_pill("Cấp 7", Color(0.98, 0.8, 0.35), Color(0.1, 0.08, 0.02)))
	vb.add_child(nm)
	vb.add_child(_label("Hội trưởng: Tín · 24/30 thành viên · Lập ngày 12/09/2026", 13, MUTED))
	var xr := HBoxContainer.new()
	xr.add_theme_constant_override("separation", 9)
	xr.add_child(_label("XP liên minh", 13, DIM))
	xr.add_child(_xp_bar(0.685))
	xr.add_child(_label("4.250 / 6.200", 13, PAPER))
	vb.add_child(xr)
	hb.add_child(vb)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var r1 := _label("Hạng 12", 19, GOLD_TXT, HORIZONTAL_ALIGNMENT_RIGHT)
	stats.add_child(r1)
	stats.add_child(_label("toàn server", 12, DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	stats.add_child(_label("48.250 điểm tuần", 13, PAPER, HORIZONTAL_ALIGNMENT_RIGHT))
	hb.add_child(stats)
	return card


func _action_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(_icon_btn("Mời bạn bè", FA_USER_PLUS, "primary", 168))
	hb.add_child(_icon_btn("Chat liên minh", FA_COMMENTS, "ghost", 176))
	hb.add_child(_icon_btn("Cài đặt liên minh", FA_GEAR, "ghost", 188))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	hb.add_child(_icon_btn("Rời liên minh", FA_LEAVE, "danger", 160))
	return hb


func _page_root() -> VBoxContainer:
	_page = Control.new()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_page)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bs := PageShell.bg_style()
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bs.content_margin_top = PageShell.CONTENT_TOP
	bs.content_margin_bottom = 12
	board.add_theme_stylebox_override("panel", bs)
	_page.add_child(board)
	_page.add_child(PageShell.header("Liên minh", Callable()))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	board.add_child(vb)
	return vb


# ------------------------------------------------------------ variant A

func _build_a() -> void:
	var vb := _page_root()
	vb.add_child(_header_card())
	vb.add_child(_action_row())
	# Members.
	var mc := _card(10, 1)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 5)
	mc.add_child(mv)
	mv.add_child(_section("THÀNH VIÊN", "· 24/30 · sắp xếp theo đóng góp tuần"))
	mv.add_child(_col_header())
	for i in 4:
		mv.add_child(_member_row(MEMBERS[i], i == 0))
	var more := _label("Xem tất cả 24 thành viên", 13, GOLD_TXT, HORIZONTAL_ALIGNMENT_CENTER)
	mv.add_child(more)
	vb.add_child(mc)
	# Requests below members (the A trade-off: leaders scroll to them).
	var rc := _card(10, 1)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 5)
	rc.add_child(rv)
	var rh := _section("YÊU CẦU GIA NHẬP")
	rh.add_child(_pill("2", Color(0.98, 0.5, 0.45), Color(0.16, 0.05, 0.02)))
	rv.add_child(rh)
	for r in REQUESTS:
		rv.add_child(_request_row(r))
	vb.add_child(rc)


# ------------------------------------------------------------ variant B

func _tab(text: String, active: bool, count: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	if active:
		p.add_theme_stylebox_override("panel", _sb(Color(0.92, 0.7, 0.22), 8))
	else:
		p.add_theme_stylebox_override("panel",
				_sb(Color(0.05, 0.07, 0.15, 0.92), 8, Color(1, 0.85, 0.4, 0.55), 1))
	p.custom_minimum_size = Vector2(150, 38)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 7)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_label(text, 15, Color(0.16, 0.11, 0.02) if active else Color(0.88, 0.89, 0.94)))
	if count > 0:
		hb.add_child(_pill(str(count), Color(0.98, 0.5, 0.45), Color(0.16, 0.05, 0.02)))
	p.add_child(hb)
	return p


func _stat_row(k: String, v: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_child(_label(k, 14, MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	hb.add_child(_label(v, 14, PAPER))
	return hb


func _build_b() -> void:
	var vb := _page_root()
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	# Left: profile card + actions.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(372, 0)
	cols.add_child(left)
	var pc := _card(16, 2)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 7)
	pc.add_child(pv)
	var bc := CenterContainer.new()
	bc.add_child(_badge(Color(0.45, 0.08, 0.1), 108))
	pv.add_child(bc)
	pv.add_child(_label("ĐOÀN KỴ SĨ AURELION", 21, GOLD_TXT, HORIZONTAL_ALIGNMENT_CENTER))
	var pr := HBoxContainer.new()
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.add_child(_pill("Cấp 7", Color(0.98, 0.8, 0.35), Color(0.1, 0.08, 0.02)))
	pr.add_child(_pill("Hạng 12 toàn server", Color(1, 1, 1, 0.06), MUTED))
	pv.add_child(pr)
	pv.add_child(_xp_bar(0.685))
	var xpr := HBoxContainer.new()
	xpr.add_child(_label("XP liên minh", 12, DIM))
	var xsp := Control.new()
	xsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xpr.add_child(xsp)
	xpr.add_child(_label("4.250 / 6.200", 12, PAPER))
	pv.add_child(xpr)
	pv.add_child(_stat_row("Thành viên", "24/30"))
	pv.add_child(_stat_row("Điểm tuần", "48.250"))
	pv.add_child(_stat_row("Hội trưởng", "Tín"))
	pv.add_child(_stat_row("Ngày lập", "12/09/2026"))
	left.add_child(pc)
	var ac := _card(12, 1)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 8)
	ac.add_child(av)
	var b1 := _icon_btn("Mời bạn bè", FA_USER_PLUS, "primary")
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(b1)
	var b2 := _icon_btn("Chat liên minh", FA_COMMENTS, "ghost")
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(b2)
	var b3 := _icon_btn("Cài đặt liên minh", FA_GEAR, "ghost")
	b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(b3)
	var b4 := _icon_btn("Rời liên minh", FA_LEAVE, "danger")
	b4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(b4)
	left.add_child(ac)
	# Right: tabs + members.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	tabs.add_child(_tab("Thành viên", true))
	tabs.add_child(_tab("Yêu cầu", false, 2))
	tabs.add_child(_tab("Hoạt động", false))
	right.add_child(tabs)
	var mc := _card(12, 1)
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	mc.add_child(mv)
	mv.add_child(_col_header())
	for i in 7:
		mv.add_child(_member_row(MEMBERS[i], i == 0))
	mv.add_child(_label("Hiển thị 7/24 thành viên — cuộn để xem thêm", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	right.add_child(mc)


# ------------------------------------------------------------ join state

func _build_join() -> void:
	var vb := _page_root()
	# Info + create.
	var ic := _card(14, 2)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 14)
	ic.add_child(ih)
	var isq := PanelContainer.new()
	isq.custom_minimum_size = Vector2(76, 76)
	isq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	isq.add_theme_stylebox_override("panel",
			_sb(Color(0.13, 0.16, 0.24), 10, Color(1, 0.85, 0.4, 0.4), 1))
	var icn := _fa(FA_USERS, 34, GOLD)
	icn.set_anchors_preset(Control.PRESET_FULL_RECT)
	isq.add_child(icn)
	ih.add_child(isq)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 4)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	iv.add_child(_label("BẠN CHƯA THAM GIA LIÊN MINH", 18, GOLD_TXT))
	iv.add_child(_label_wrap("Gia nhập một liên minh để cùng đồng đội trò chuyện, nhận điểm đóng góp mỗi tuần và thi đấu trên bảng xếp hạng liên minh.", 14, MUTED))
	ih.add_child(iv)
	var create := _icon_btn("Tạo liên minh", FA_PLUS, "primary", 176)
	create.custom_minimum_size.y = 44
	create.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(create)
	vb.add_child(ic)
	# Search row.
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 10)
	var field := LineEdit.new()
	field.placeholder_text = "Tìm liên minh theo tên..."
	field.custom_minimum_size = Vector2(0, 40)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size", 15)
	field.add_theme_color_override("font_color", PAPER)
	field.add_theme_color_override("font_placeholder_color", DIM)
	field.add_theme_stylebox_override("normal", _sb(FIELD_BG, 8, Color(1, 1, 1, 0.28), 1))
	field.add_theme_stylebox_override("focus", _sb(FIELD_BG, 8, GOLD, 1))
	sr.add_child(field)
	var find := _icon_btn("Tìm", FA_SEARCH, "ghost", 110)
	find.custom_minimum_size.y = 40
	sr.add_child(find)
	vb.add_child(sr)
	# Alliance list.
	vb.add_child(_section("LIÊN MINH ĐANG TUYỂN", "· 128 liên minh"))
	for a in ALLIANCES:
		var row := PanelContainer.new()
		var s := _sb(CARD, 10, CARD_BORDER, 1)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", s)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)
		hb.add_child(_badge(a["fill"], 50))
		var av := VBoxContainer.new()
		av.add_theme_constant_override("separation", 2)
		av.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		av.add_child(_label(String(a["name"]), 17, GOLD_TXT))
		av.add_child(_label("%s · %s" % [String(a["meta"]), String(a["mode"])], 13, MUTED))
		hb.add_child(av)
		if bool(a["sent"]):
			var sent := _icon_btn("Đã gửi", FA_CHECK, "disabled", 118)
			sent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(sent)
		else:
			var join := _icon_btn("Xin vào", FA_USER_PLUS, "primary", 118)
			join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(join)
		vb.add_child(row)
	vb.add_child(_label("Mỗi người chơi chỉ ở trong 1 liên minh tại một thời điểm.", 12, DIM))


# ------------------------------------------------------------ capture flow

func _snap(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("CAPTURE SAVED ", path, " size=", img.get_size())


func _ready() -> void:
	_build_a()
	await _snap("res://shots/empire_age_alliance_mockA_v1.png")
	_page.queue_free()
	await get_tree().process_frame
	_build_b()
	await _snap("res://shots/empire_age_alliance_mockB_v1.png")
	_page.queue_free()
	await get_tree().process_frame
	_build_join()
	await _snap("res://shots/empire_age_alliance_mock_join_v1.png")
	print("ALLIANCE MOCKS DONE")
	get_tree().quit()
