class_name SpectatorPanel
extends Control
## 15e-bis spectator panel — the observer's OWN panel (owner
## correction 2026-11-11: "lúc xem thì hiện panel xem chứ sao
## hiện lại panel người chơi"). Created and owned by Spectator
## (scripts/spectator.gd); HUD's people button routes here in
## observer mode instead of opening the players modal.
##
## Presentation-only, like the rest of 15e: it reads the sim
## (names, heroes, scores, ages, elimination state) and drives
## the Spectator camera modes; it never writes sim state and
## never sends commands. State lives in Spectator (mode /
## follow_slot / badge), so this panel and the spectator bar
## can never disagree — every control below calls the same
## Spectator.set_* functions the bar's buttons call, and the
## 0.4 s refresh re-reads that single source.
##
## Content: header "Người xem" + the stream badge (same text
## and colour rule as the bar), a Camera section (Tự do /
## Tự động + the current follow status line), and one row per
## slot — colour band, hero portrait, name, hero + age line,
## live score (Main.match_score_of, the result screen's own
## figure), status pill, and a "Theo dõi" action that closes
## the panel and engages FOLLOW on that slot. No player-only
## content lives here: no diplomacy, no gifting, no kicks.

const GOLD := Color(0.85, 0.64, 0.25, 0.95)
const GOLD_TXT := Color(0.96, 0.8, 0.45)
const GOLD_DIM := Color(0.85, 0.64, 0.25, 0.55)
const BORDER_DIM := Color(1, 1, 1, 0.14)
const TXT := Color(0.94, 0.96, 0.99)
const TXT_DIM := Color(0.64, 0.7, 0.8)
const GREEN := Color(0.45, 0.95, 0.55)
const DELAY_COL := Color(1.0, 0.62, 0.35)

const PANEL_SIZE := Vector2(600, 470)
const AGE_TXT: Array = ["", "Đời I – Hắc ám", "Đời II – Feudal",
		"Đời III – Lâu đài", "Đời IV – Đế quốc"]

const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"
const FA_EYE := 0xF06E
const FA_XMARK := 0xF00D
const FA_CROWN := 0xF521

var spec = null # Spectator (untyped: avoids a cyclic class ref)
var game = null # Main

var _badge_label: Label
var _status_label: Label
var _free_btn: Button
var _auto_btn: Button
var _rows_box: VBoxContainer
var _follow_btns := {} # slot -> Button (rebuilt every refresh)
var _sub_labels: Array = [] # row sub-line Labels (rebuilt every refresh)
var _refresh_acc := 0.0
var _fa_font: Font = null


## set_anchors_preset alone is a trap at build time: with
## keep_offsets=false it "preserves" the node's current rect
## by baking offset_right/bottom to minus the parent size,
## freezing a not-yet-laid-out control at 0x0 forever. Always
## zero the offsets after the preset (probed live, 15e-bis).
func _full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


func _ready() -> void:
	_full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _process(delta: float) -> void:
	if not visible or spec == null or game == null:
		return
	_refresh_acc += delta
	if _refresh_acc >= 0.4:
		_refresh_acc = 0.0
		refresh()


# ------------------------------------------------------------ build

func _sb(bg: Color, radius: int, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_color = border
	s.set_border_width_all(bw)
	return s


func _pad(l: int, t: int, r: int, b: int) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", l)
	mc.add_theme_constant_override("margin_top", t)
	mc.add_theme_constant_override("margin_right", r)
	mc.add_theme_constant_override("margin_bottom", b)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return mc


func _label(text: String, size: int, col: Color = TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _fa(cp: int, px: int, col: Color = TXT) -> Label:
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


## The in-match panels' close button (HUD._fa_button with
## FA_XMARK, radius 8, 32 px): a bordered square wearing the
## X glyph, clicked through a flat full-cover Button.
func _close_button() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
			_sb(Color(0.04, 0.07, 0.13, 0.72), 8, Color(1, 1, 1, 0.28), 1))
	p.custom_minimum_size = Vector2(32, 32)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(_fa(FA_XMARK, 16))
	p.add_child(cc)
	var b := Button.new()
	b.text = ""
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var e := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(s, e)
	_full_rect(b)
	b.pressed.connect(func() -> void: spec.set_panel_open(false))
	p.add_child(b)
	return p


func _cam_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", GOLD_TXT)
	b.add_theme_stylebox_override("normal",
			_sb(Color(1, 1, 1, 0.07), 6, Color(1, 1, 1, 0.16), 1))
	b.add_theme_stylebox_override("hover",
			_sb(Color(1, 1, 1, 0.14), 6, Color(1, 1, 1, 0.3), 1))
	b.add_theme_stylebox_override("pressed",
			_sb(Color(1, 1, 1, 0.2), 6, GOLD, 1))
	return b


func _build() -> void:
	# Dim backdrop — a tap outside the card closes, like the
	# HUD modals' backdrop.
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_full_rect(dim)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				spec.set_panel_open(false))
	add_child(dim)
	# Centred card — the 13x modal dialect: solid navy, 2 px
	# gold frame, radius 16.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.add_theme_stylebox_override("panel",
			_sb(Color(0.03, 0.05, 0.1, 0.94), 16, GOLD, 2))
	add_child(panel)
	var mc := _pad(12, 12, 12, 12)
	panel.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	mc.add_child(vb)
	# Header band (same inner-band shape as the HUD modals):
	# FA eye + gold title, the stream badge, the close button.
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel",
			_sb(Color(1, 1, 1, 0.04), 10, BORDER_DIM, 1))
	header.custom_minimum_size = Vector2(0, 46)
	vb.add_child(header)
	var hmc := _pad(10, 5, 8, 5)
	header.add_child(hmc)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	hmc.add_child(head)
	head.add_child(_fa(FA_EYE, 18, GOLD_TXT))
	head.add_child(_label("Người xem", 16, GOLD_TXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	_badge_label = _label("", 13, GREEN)
	_badge_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_badge_label)
	head.add_child(_close_button())
	# Camera section: the bar's two mode buttons + the status
	# line the bar shows ("Theo dõi: X" / auto / free).
	vb.add_child(_label("Camera", 12, TXT_DIM))
	var cam := HBoxContainer.new()
	cam.add_theme_constant_override("separation", 6)
	vb.add_child(cam)
	_free_btn = _cam_button("Tự do")
	_free_btn.pressed.connect(func() -> void: spec.set_free())
	cam.add_child(_free_btn)
	_auto_btn = _cam_button("Tự động")
	_auto_btn.pressed.connect(func() -> void: spec.set_auto())
	cam.add_child(_auto_btn)
	_status_label = _label("", 13)
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cam.add_child(_status_label)
	# Player list.
	vb.add_child(_label("Người chơi trong trận", 12, TXT_DIM))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = false
	sc.add_theme_stylebox_override("panel",
			_sb(Color(0.015, 0.03, 0.07, 0.85), 10, BORDER_DIM, 1))
	vb.add_child(sc)
	var rmc := MarginContainer.new()
	rmc.add_theme_constant_override("margin_left", 6)
	rmc.add_theme_constant_override("margin_top", 6)
	rmc.add_theme_constant_override("margin_right", 6)
	rmc.add_theme_constant_override("margin_bottom", 6)
	rmc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rmc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(rmc)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rmc.add_child(_rows_box)


# ------------------------------------------------------------ content

## Rebuilds the dynamic content from Spectator's single state
## source (mode / follow_slot / badge) plus the live sim
## figures. Called on open and every 0.4 s while open.
func refresh() -> void:
	if spec == null or game == null or _rows_box == null:
		return
	_badge_label.text = spec._badge_text()
	_badge_label.add_theme_color_override("font_color",
			DELAY_COL if Net.cfg_obs_delay > 0 else GREEN)
	match spec.mode:
		Spectator.MODE_FOLLOW:
			_status_label.text = "Đang theo dõi: %s" % spec._slot_name(spec.follow_slot)
		Spectator.MODE_AUTO:
			_status_label.text = "Camera tự động"
		_:
			_status_label.text = "Camera tự do"
	_free_btn.add_theme_color_override("font_color",
			GOLD_TXT if spec.mode == Spectator.MODE_FREE else TXT)
	_auto_btn.add_theme_color_override("font_color",
			GOLD_TXT if spec.mode == Spectator.MODE_AUTO else TXT)
	for ch in _rows_box.get_children():
		_rows_box.remove_child(ch)
		ch.free()
	_follow_btns.clear()
	_sub_labels.clear()
	for slot in range(game.slot_count()):
		_rows_box.add_child(_row_for(slot))
	# The sub-line fit needs the laid-out column width, which
	# only exists after this frame's layout — defer it (the
	# 0.4 s refresh re-runs both, so it stays fitted).
	call_deferred("_fit_sub_labels")


## 15c's skill-name rule, applied to the row sub-line: the
## full "Nhân vật: … · Đời … · …" line is never clipped and
## never wraps — its font shrinks (12 → 8) until the whole
## string fits the width the row actually granted it. The
## floor of 8 only suffices because the row gives the text
## column its width back (pill minimum sized to its widest
## status, tighter row padding/separation): the longest
## possible line is 214 px at 8, the narrowest grant 217.
func _fit_sub_labels() -> void:
	for sb in _sub_labels:
		if not is_instance_valid(sb):
			continue
		var avail: float = (sb as Label).size.x
		if avail <= 0.0:
			continue
		var f := (sb as Label).get_theme_default_font()
		var size := 12
		while size > 8 and f.get_string_size((sb as Label).text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > avail - 2.0:
			size -= 1
		(sb as Label).add_theme_font_size_override("font_size", size)


func _status_pill(text: String, col: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _sb(
			Color(col.r, col.g, col.b, 0.15), 9,
			Color(col.r, col.g, col.b, 0.55), 1))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pmc := _pad(9, 3, 9, 3)
	pill.add_child(pmc)
	var lb := _label(text, 11, col)
	# 64 = the widest status ("Mất kết nối", 61 px at 11)
	# plus slack; the old 76 starved the name column (below).
	lb.custom_minimum_size = Vector2(64, 0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pmc.add_child(lb)
	return pill


## One slot row: slot-colour band, hero portrait, name +
## hero/age line, the live match score, the status pill, and
## the Theo dõi action (disabled once the slot is eliminated;
## labelled "Đang theo dõi" on the slot being followed).
func _row_for(slot: int) -> PanelContainer:
	var following: bool = spec.mode == Spectator.MODE_FOLLOW \
			and spec.follow_slot == slot
	var eliminated: bool = slot < game.slot_eliminated.size() \
			and game.slot_eliminated[slot]
	var inert: bool = slot < game.slot_inert.size() \
			and game.slot_inert[slot]
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", _sb(
			Color(0.05, 0.08, 0.15, 0.9), 12,
			GOLD if following else BORDER_DIM, 2 if following else 1))
	var mc := _pad(8, 8, 8, 8)
	root.add_child(mc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	mc.add_child(row)
	var band := Panel.new()
	band.custom_minimum_size = Vector2(6, 0)
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = TeamColors.ui_color(slot)
	bsb.set_corner_radius_all(3)
	band.add_theme_stylebox_override("panel", bsb)
	row.add_child(band)
	var alive: bool = game.king_alive(slot)
	var char_id := String(game.char_for(slot))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sb(
			Color(0.02, 0.03, 0.07, 0.9), 8,
			GOLD_DIM if alive else BORDER_DIM, 1))
	frame.custom_minimum_size = Vector2(46, 46)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex = Characters.avatar_for(char_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not alive:
			tr.modulate = Color(1, 1, 1, 0.45)
		frame.add_child(tr)
	else:
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(_fa(FA_CROWN, 18, TXT_DIM))
		frame.add_child(cc)
	row.add_child(frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vb)
	var nm := _label(spec._slot_name(slot), 14)
	nm.clip_text = true
	vb.add_child(nm)
	var age: int = clampi(game.owner_age(slot), 1, AGE_TXT.size() - 1)
	var sub := "Nhân vật: %s · %s" % [
			str(Characters.kit_of(char_id).get("name", "")),
			String(AGE_TXT[age])]
	sub += " · đang chiến đấu" if alive else " · chưa xuất trận"
	var sb := _label(sub, 12, TXT_DIM)
	sb.clip_text = true
	vb.add_child(sb)
	_sub_labels.append(sb)
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	score_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(score_box)
	var scap := _label("Điểm", 10, TXT_DIM)
	scap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(scap)
	var sval := _label(str(game.match_score_of(slot)), 16, GOLD_TXT)
	sval.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sval.custom_minimum_size = Vector2(48, 0) # a 5-digit score is 46 px at 16
	score_box.add_child(sval)
	var status := "Đang chơi"
	var scol := GREEN
	if eliminated:
		status = "Đã bị loại"
		scol = Color(1.0, 0.55, 0.45)
	elif inert:
		status = "Mất kết nối"
		scol = Color(1.0, 0.85, 0.45)
	row.add_child(_status_pill(status, scol))
	var fb := _cam_button("Đang theo dõi" if following else "Theo dõi")
	fb.custom_minimum_size = Vector2(92, 34)
	fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fb.disabled = eliminated or following
	var s := slot
	fb.pressed.connect(func() -> void: _on_follow_pressed(s))
	row.add_child(fb)
	_follow_btns[slot] = fb
	return root


func _on_follow_pressed(slot: int) -> void:
	spec.set_follow(slot)
	spec.set_panel_open(false)
