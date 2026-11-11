class_name ReplayBar
extends CanvasLayer

## Replay control bar (13h, controls completed 14a): play/pause
## and speed (0.5×/1×/2×/4×/8×) with Font Awesome glyphs, a
## timeline slider with EVENT MARKERS (age-ups + hero summons
## derived from the command log, eliminations from the sealed
## events sidecar, match end), the match clock, a FOLLOW-PLAYER
## perspective switcher (each slot's fog of war, or full vision),
## per-player chips (name, slot colour, live resources + age read
## straight from the sim), and "Thoát xem lại" back to the home
## screen's history panel. Seeking = restart + silent
## fast-forward re-simulation — see Main's replay feed.
## Spectator chrome only — the sim underneath is the untouched
## lockstep drive, and none of this exists in a live match.

var game = null

var _play_glyph: Label
var _speed_btn: Button
var _speed_glyph: Label
var _slider: HSlider
var _strip: MarkerStrip
var _clock: Label
var _result: Label
var _chips_box: VBoxContainer
var _follow_btns: Dictionary = {} # slot (-1 = full vision) -> Button
var _dragging: bool = false
var _chip_accum: float = 0.0

const AGES := ["", "I", "II", "III", "IV"]
const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"
const FA_PLAY := 0xF04B
const FA_PAUSE := 0xF04C
const FA_GAUGE := 0xF624


## Timeline marker strip: one diamond per marker, coloured by
## kind; clicking a point seeks there (same replay_seek as the
## slider, so state stays checksum-exact).
class MarkerStrip:
	extends Control
	var markers: Array = []
	var final_tick: int = 1
	var on_seek: Callable = Callable()
	const KIND_COLORS := {
		"age": Color(1.0, 0.8, 0.25),
		"hero": Color(0.78, 0.55, 1.0),
		"elim": Color(1.0, 0.36, 0.3),
		"end": Color(0.95, 0.95, 0.95),
	}

	func _draw() -> void:
		if final_tick <= 0:
			return
		for m in markers:
			var x := size.x * float(int(m["tick"])) / float(final_tick)
			var cx := clampf(x, 4.0, maxf(4.0, size.x - 4.0))
			var c: Color = KIND_COLORS.get(str(m["kind"]), Color.WHITE)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx, 1), Vector2(cx + 4, size.y * 0.5),
				Vector2(cx, size.y - 1), Vector2(cx - 4, size.y * 0.5)]), c)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and on_seek.is_valid() and final_tick > 0:
			var t := int(round(event.position.x / maxf(size.x, 1.0)
					* float(final_tick)))
			on_seek.call(t)


func _sb(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _label(text: String, size: int, color: Color = Color(0.94, 0.93, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _fa_label(codepoint: int, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = String.chr(codepoint)
	l.add_theme_font_override("font", load(FA_FONT_PATH))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func setup(p_game) -> void:
	game = p_game
	layer = 70
	_build()
	refresh_bar()
	refresh_follow()


func _build() -> void:
	# Player chips, top-left.
	_chips_box = VBoxContainer.new()
	_chips_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_chips_box.position = Vector2(12, 12)
	_chips_box.add_theme_constant_override("separation", 6)
	add_child(_chips_box)
	for slot in range(game.slot_count()):
		_chips_box.add_child(_make_chip(slot))
	# Exit, top-right.
	var exit_btn := Button.new()
	exit_btn.text = "Thoát xem lại"
	exit_btn.custom_minimum_size = Vector2(140, 40)
	exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	exit_btn.position = Vector2(-152, 12)
	exit_btn.add_theme_font_size_override("font_size", 16)
	exit_btn.add_theme_color_override("font_color", Color.WHITE)
	exit_btn.add_theme_stylebox_override("normal",
			_sb(Color(0.1, 0.05, 0.05, 0.85), 9, Color(0.9, 0.4, 0.3, 0.7), 1))
	exit_btn.add_theme_stylebox_override("hover",
			_sb(Color(0.75, 0.2, 0.15, 0.9), 9))
	exit_btn.pressed.connect(func() -> void: game.replay_exit())
	add_child(exit_btn)
	_build_follow_panel()
	# Result banner (hidden until the replay ends).
	_result = _label("", 24, Color(1, 0.87, 0.45))
	_result.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result.position = Vector2(-200, 64)
	_result.custom_minimum_size = Vector2(400, 34)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.visible = false
	add_child(_result)
	# Bottom control bar.
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -92
	bar.add_theme_stylebox_override("panel",
			_sb(Color(0.015, 0.02, 0.045, 0.94), 0, Color(1, 0.85, 0.4, 0.35), 0))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	bar.add_child(hb)
	add_child(bar)
	var play_btn := Button.new()
	play_btn.custom_minimum_size = Vector2(46, 44)
	play_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play_btn.add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0.3), 9))
	play_btn.add_theme_stylebox_override("hover", _sb(Color(1, 0.85, 0.4, 0.2), 9))
	_play_glyph = _fa_label(FA_PAUSE, 20, Color(1, 0.95, 0.85))
	_play_glyph.position = Vector2(14, 10)
	play_btn.add_child(_play_glyph)
	play_btn.pressed.connect(func() -> void: game.replay_toggle_play())
	hb.add_child(play_btn)
	_speed_btn = Button.new()
	_speed_btn.text = "1×"
	_speed_btn.custom_minimum_size = Vector2(78, 44)
	_speed_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speed_btn.add_theme_font_size_override("font_size", 17)
	_speed_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	var spd := _sb(Color(0, 0, 0, 0.3), 9)
	spd.content_margin_left = 30
	_speed_btn.add_theme_stylebox_override("normal", spd)
	_speed_btn.add_theme_stylebox_override("hover", _sb(Color(1, 0.85, 0.4, 0.2), 9))
	_speed_glyph = _fa_label(FA_GAUGE, 15, Color(1, 0.9, 0.55))
	_speed_glyph.position = Vector2(9, 14)
	_speed_btn.add_child(_speed_glyph)
	_speed_btn.pressed.connect(func() -> void: game.replay_cycle_speed())
	hb.add_child(_speed_btn)
	# Timeline column: marker strip over the slider, legend under.
	var tl := VBoxContainer.new()
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.add_theme_constant_override("separation", 2)
	hb.add_child(tl)
	_strip = MarkerStrip.new()
	_strip.custom_minimum_size = Vector2(0, 12)
	_strip.markers = game.replay_markers()
	_strip.final_tick = maxi(1, game.replay_final_tick())
	_strip.on_seek = func(t: int) -> void: game.replay_seek(t)
	tl.add_child(_strip)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = maxi(1, game.replay_final_tick())
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		game.replay_seek(int(_slider.value)))
	tl.add_child(_slider)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	tl.add_child(legend)
	legend.add_child(_label("◆ Lên đời", 11, Color(1.0, 0.8, 0.25)))
	legend.add_child(_label("◆ Triệu hồi nhân vật", 11, Color(0.78, 0.55, 1.0)))
	legend.add_child(_label("◆ Bị loại", 11, Color(1.0, 0.36, 0.3)))
	legend.add_child(_label("◆ Kết thúc", 11, Color(0.95, 0.95, 0.95)))
	_clock = _label("0:00 / 0:00", 16, Color(0.92, 0.92, 0.9))
	_clock.custom_minimum_size = Vector2(130, 0)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_clock)


## Follow-player switcher (14a): one chip per slot (its fog of
## war) plus "Toàn cảnh" for full vision. Top-right, under Exit.
func _build_follow_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-152, 60)
	panel.custom_minimum_size = Vector2(140, 0)
	panel.add_theme_stylebox_override("panel",
			_sb(Color(0.02, 0.03, 0.07, 0.82), 9, Color(1, 0.85, 0.4, 0.3), 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var title := _label("Góc nhìn", 13, Color(1, 0.87, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	vb.add_child(_make_follow_chip(-1, "Toàn cảnh", Color(0, 0, 0, 0)))
	for slot in range(game.slot_count()):
		vb.add_child(_make_follow_chip(slot, game.slot_names[slot],
				TeamColors.ui_color(slot)))
	add_child(panel)


func _make_follow_chip(slot: int, text: String, dot_color: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(124, 27)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.94, 0.93, 0.88))
	if slot >= 0:
		var dot := PanelContainer.new()
		dot.add_theme_stylebox_override("panel", _sb(dot_color, 5))
		dot.custom_minimum_size = Vector2(10, 10)
		dot.position = Vector2(7, 8)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
		var nm := _label(text, 13)
		nm.position = Vector2(24, 4)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
	else:
		b.text = text
	b.pressed.connect(func() -> void: game.replay_set_follow(slot))
	_follow_btns[slot] = b
	return b


func refresh_follow() -> void:
	if game == null:
		return
	var active: int = game.replay_follow_slot()
	for slot in _follow_btns.keys():
		var b: Button = _follow_btns[slot]
		if int(slot) == active:
			b.add_theme_stylebox_override("normal",
					_sb(Color(0.16, 0.12, 0.03, 0.95), 7, Color(1, 0.8, 0.3), 1))
			b.add_theme_stylebox_override("hover",
					_sb(Color(0.22, 0.16, 0.04, 0.95), 7, Color(1, 0.8, 0.3), 1))
		else:
			b.add_theme_stylebox_override("normal",
					_sb(Color(0, 0, 0, 0.25), 7, Color(1, 1, 1, 0.14), 1))
			b.add_theme_stylebox_override("hover",
					_sb(Color(1, 0.85, 0.4, 0.18), 7, Color(1, 1, 1, 0.14), 1))


func _make_chip(slot: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Chip%d" % slot
	chip.add_theme_stylebox_override("panel",
			_sb(Color(0.02, 0.03, 0.07, 0.78), 8, Color(1, 1, 1, 0.16), 1))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	chip.add_child(hb)
	var dot := PanelContainer.new()
	dot.add_theme_stylebox_override("panel",
			_sb(TeamColors.ui_color(slot), 6))
	dot.custom_minimum_size = Vector2(13, 13)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var nm := _label(game.slot_names[slot], 15, Color.WHITE)
	nm.name = "Name"
	hb.add_child(nm)
	for kind in ["food", "wood", "gold", "stone"]:
		var ic := GlassIcon.new()
		ic.kind = kind
		ic.custom_minimum_size = Vector2(16, 16)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ic)
		var v := _label("0", 14)
		v.name = "Res_" + kind
		hb.add_child(v)
	var age := _label("Đời I", 14, Color(1, 0.9, 0.55))
	age.name = "Age"
	hb.add_child(age)
	return chip


func _fmt_clock(ticks: int) -> String:
	var secs := ticks / 10
	return "%d:%02d" % [secs / 60, secs % 60]


func refresh_bar() -> void:
	if game == null:
		return
	if not _dragging:
		_slider.value = game.replay_current_tick()
	_clock.text = "%s / %s" % [_fmt_clock(game.replay_current_tick()),
			_fmt_clock(game.replay_final_tick())]
	_play_glyph.text = String.chr(FA_PAUSE if game.replay_is_playing() else FA_PLAY)
	_speed_btn.text = game.replay_speed_text()
	_chip_accum += 1.0 / 60.0
	if _chip_accum < 0.25:
		return
	_chip_accum = 0.0
	for slot in range(game.slot_count()):
		var chip := _chips_box.get_node_or_null("Chip%d" % slot)
		if chip == null:
			continue
		var w: Dictionary = game.mp_wallets[slot]
		for kind in ["food", "wood", "gold", "stone"]:
			var v := chip.find_child("Res_" + kind, true, false) as Label
			if v != null:
				v.text = str(int(w.get(kind, 0)))
		var age := chip.find_child("Age", true, false) as Label
		if age != null:
			var a := int(game.mp_ages[slot].get("age", 1))
			age.text = "Đời %s" % AGES[clampi(a, 1, 4)]


func show_result() -> void:
	var wt: int = game.replay_winner_team()
	if wt < 0:
		return
	var names: Array = []
	for slot in range(game.slot_count()):
		if game.team_of_slot(slot) == wt:
			names.append(game.slot_names[slot])
	_result.text = "Kết thúc — %s thắng" % ", ".join(names)
	_result.visible = true
