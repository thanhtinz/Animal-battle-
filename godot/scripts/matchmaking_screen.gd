class_name MatchmakingScreen
extends Control
## Empire Age 13p — matchmaking waiting screen (ranked queue;
## 13t reuses the same painted screen for the NORMAL queue —
## start_queue's normal_mode only changes the long-wait status
## line, since the unranked queue has no MMR window).
##
## 13p follow-up 2 (Tín rejected the code-drawn frame as
## "Xấu vậy" and approved the painted mock v12 after
## iterating v3→v12): the presentation is now ONE painted
## artwork — assets/matchmaking_frame.png (ornate gold outer
## frame, crossed-swords crest, BLANK red ribbon, knights /
## castle scene, glowing ring at the centre; the inner shield
## frame and the two flags of the first generations were
## removed on Tín's orders). The art is CONTAIN-fitted over
## the dimmed lobby — letterboxed, always fully visible,
## never cropped — and only the live elements are real nodes:
## the ribbon title, the count-up timer inside the painted
## ring, the spinner + status row, and the cancel plaque.
##
## Every live element is laid out from the art's displayed
## rect by fractions MEASURED on the approved mock
## (shots/empire_age_matchmaking_mock_v12.png); the art is
## 2240×1120 and fractions are (x/2240, y/1120):
##   title  centre (0.4991, 0.2205), width ≈ 0.321 of art w
##   timer  centre (0.4978, 0.5268), width ≤ 0.155 of art w
##   ring   centre (0.4978, 0.5518), inner disc Ø 0.199 art w
##   status centre (0.4978, 0.6214) — one centred unit
##   cancel centre (0.5000, 0.8393), size (0.2098, 0.0857)
## Font sizes are fitted by measuring the game font against
## those width targets, not eyeballed.
##
## Pure presentation: the lobby owns the queue protocol
## (Net.queue_join / queue_leave, queue_joined / queue_left /
## match_found). This screen only renders the wait and emits
## cancel_pressed. The status line honestly widens at 30 s —
## the server's MMR window really does grow with wait time
## (server/matchmaking.go queueWindow). There is NO player
## rank line: the approved mock has none.

signal cancel_pressed

const ART_TEX := preload("res://assets/matchmaking_frame.png")
const ART_SIZE := Vector2(2240.0, 1120.0)

const GOLD_TXT := Color(0.96, 0.8, 0.45)
const TXT := Color(0.94, 0.96, 0.99)

var _art_rect: TextureRect
var _title_lbl: Label
var _timer_lbl: Label
var _status_lbl: Label
var _spinner: MmSpinner
var _srow: HBoxContainer
var _cancel_btn: MmCancelButton
var _art := Rect2()
var _start_msec: int = 0
var _phase: float = 0.0
var _built: bool = false
var _normal_mode: bool = false # 13t: normal queue (no MMR window to widen)


class MmSpinner:
	extends Control
	var phase := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.36
		var w := maxf(2.0, minf(size.x, size.y) * 0.10)
		draw_arc(c, r, phase, phase + PI * 1.45, 24,
				Color(0.92, 0.94, 0.98), w, true)
		draw_arc(c, r, phase + PI * 1.62, phase + TAU, 12,
				Color(0.92, 0.94, 0.98, 0.35), w, true)


class MmCancelButton:
	extends Control
	signal pressed
	var _hover := false
	var _down := false
	var _lbl: Label
	var _glyph_cx := -1.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		_lbl = Label.new()
		_lbl.text = "Hủy ghép"
		_lbl.add_theme_font_size_override("font_size", 22)
		_lbl.add_theme_color_override("font_color", Color(1, 0.93, 0.85))
		_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		_lbl.add_theme_constant_override("shadow_offset_x", 1)
		_lbl.add_theme_constant_override("shadow_offset_y", 2)
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_lbl)

	## The ✕ + text group is centred as one unit (measured
	## with the label's own font), like the approved mock.
	func _relayout() -> void:
		if size.x < 10.0:
			return
		var fs := maxi(16, int(size.y * 0.46))
		_lbl.add_theme_font_size_override("font_size", fs)
		var font := _lbl.get_theme_default_font()
		var tw := font.get_string_size(_lbl.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		var glyph_w := size.y * 0.42
		var gap := size.y * 0.22
		var x0 := (size.x - glyph_w - gap - tw) * 0.5
		_glyph_cx = x0 + glyph_w * 0.5
		_lbl.size = Vector2(tw + 4.0, size.y)
		# The label's minimum height can exceed the plaque's
		# (the theme font's line height), so centre its actual
		# rect on the plaque instead of pinning it to y=0.
		_lbl.position = Vector2(x0 + glyph_w + gap,
				(size.y - _lbl.size.y) * 0.5)
		queue_redraw()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.58, 0.1, 0.11) if _hover \
				else Color(0.48, 0.08, 0.09)
		if _down:
			sb.bg_color = Color(0.38, 0.06, 0.07)
		sb.border_color = Color(0.95, 0.73, 0.28)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(maxi(8, int(size.y * 0.2)))
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		# Drawn ✕ glyph (not a text cross).
		var gx := _glyph_cx if _glyph_cx >= 0.0 else size.x * 0.30
		var c := Vector2(gx, size.y * 0.5)
		var col := Color(1, 0.85, 0.45)
		var arm := size.y * 0.17
		var wdt := maxf(3.0, size.y * 0.075)
		draw_line(c + Vector2(-arm, -arm), c + Vector2(arm, arm), col, wdt, true)
		draw_line(c + Vector2(arm, -arm), c + Vector2(-arm, arm), col, wdt, true)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_down = true
					queue_redraw()
				elif _down:
					_down = false
					queue_redraw()
					pressed.emit()
				accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_relayout()
		elif what == NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_down = false
			queue_redraw()


func _init() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP


func build() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	# The painted artwork; _layout() gives it the exact
	# contain-fit rect, so STRETCH_SCALE cannot distort it.
	_art_rect = TextureRect.new()
	_art_rect.texture = ART_TEX
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_art_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_art_rect)
	# Title on the painted ribbon.
	_title_lbl = _mk_label("Đang ghép trận", 38, GOLD_TXT)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_title_lbl)
	# Count-up timer inside the painted ring.
	_timer_lbl = _mk_label("00:00", 84, Color(1, 0.85, 0.42))
	_timer_lbl.add_theme_color_override("font_outline_color",
			Color(0.3, 0.16, 0.02, 0.9))
	_timer_lbl.add_theme_constant_override("outline_size", 4)
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_timer_lbl)
	# Status row: spinner + text, centred as one unit.
	_srow = HBoxContainer.new()
	_srow.alignment = BoxContainer.ALIGNMENT_CENTER
	_srow.add_theme_constant_override("separation", 8)
	_srow.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_srow)
	_spinner = MmSpinner.new()
	_spinner.custom_minimum_size = Vector2(20, 20)
	_spinner.mouse_filter = MOUSE_FILTER_IGNORE
	_srow.add_child(_spinner)
	_status_lbl = _mk_label("Đang tìm đối thủ...", 20, TXT)
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_srow.add_child(_status_lbl)
	# Cancel plaque.
	_cancel_btn = MmCancelButton.new()
	_cancel_btn.pressed.connect(func() -> void: cancel_pressed.emit())
	add_child(_cancel_btn)
	resized.connect(_layout)
	_layout()


## Largest font size whose rendered width for `text` is at
## most `target_w`, measured with the game's own font.
func _fit_font_size(l: Label, text: String, target_w: float,
		start_size: int) -> int:
	var font := l.get_theme_default_font()
	var sz := start_size
	while sz > 8:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, sz).x <= target_w:
			break
		sz -= 1
	return sz


func _art_point(fx: float, fy: float) -> Vector2:
	return _art.position + Vector2(fx * _art.size.x, fy * _art.size.y)


## Positions everything from the art's contain-fit rect,
## which is recomputed from the CURRENT viewport size (the
## lobby builds this screen before the viewport has a real
## size, so start_queue() re-runs the layout once shown, and
## `resized` keeps it right afterwards). All fractions are
## the measured mock-v12 values listed in the header.
func _layout() -> void:
	if not _built:
		return
	var vp := get_viewport_rect().size
	if vp.x < 200.0:
		vp = Vector2(1152, 648)
	var scl := minf(vp.x / ART_SIZE.x, vp.y / ART_SIZE.y)
	_art = Rect2((vp - ART_SIZE * scl) * 0.5, ART_SIZE * scl)
	_art_rect.position = _art.position
	_art_rect.size = _art.size
	var aw := _art.size.x
	var ah := _art.size.y
	# Title: fitted so its width ≈ 0.321 of the art width,
	# centred on the painted ribbon at (0.4991, 0.2205).
	var tsz := _fit_font_size(_title_lbl, _title_lbl.text,
			0.321 * aw, int(0.055 * aw) + 8)
	_title_lbl.add_theme_font_size_override("font_size", tsz)
	var tsize := Vector2(0.70 * aw, 0.11 * ah)
	_title_lbl.position = _art_point(0.4991, 0.2205) - tsize * 0.5
	_title_lbl.size = tsize
	# Timer: fitted under the 0.155 width cap so it always
	# sits inside the painted ring; centred (0.4978, 0.5268).
	var msz := _fit_font_size(_timer_lbl, "00:00",
			0.155 * aw, int(0.075 * aw) + 8)
	_timer_lbl.add_theme_font_size_override("font_size", msz)
	_timer_lbl.add_theme_constant_override("outline_size",
			maxi(2, int(0.002 * aw)))
	var msize := Vector2(0.50 * aw, 0.17 * ah)
	_timer_lbl.position = _art_point(0.4978, 0.5268) - msize * 0.5
	_timer_lbl.size = msize
	# Status row centred as one unit on (0.4978, 0.6214).
	_status_lbl.add_theme_font_size_override("font_size",
			maxi(12, int(0.0179 * aw)))
	var spin := maxf(14.0, 0.0152 * aw)
	_spinner.custom_minimum_size = Vector2(spin, spin)
	_srow.add_theme_constant_override("separation",
			maxi(4, int(0.0067 * aw)))
	var ssize := Vector2(0.80 * aw, 0.055 * ah)
	_srow.position = _art_point(0.4978, 0.6214) - ssize * 0.5
	_srow.size = ssize
	# Cancel plaque: centre (0.5000, 0.8393), size
	# (0.2098, 0.0857) of the art rect — clear of the ring
	# above and the frame's bottom bar below (mock v12).
	var csize := Vector2(0.2098 * aw, 0.0857 * ah)
	_cancel_btn.position = _art_point(0.5, 0.8393) - csize * 0.5
	_cancel_btn.size = csize
	# Relayout the plaque's inner group explicitly: the size
	# is often first set before the button enters the tree
	# (or to an unchanged value later), in which case
	# NOTIFICATION_RESIZED never reaches it and the label
	# would stay at the origin under the ✕ glyph.
	_cancel_btn._relayout()


func _mk_label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


## Shows the screen and starts the wait clock at `since_msec`.
## `normal_mode` (13t) is the unranked queue: identical painted
## screen, but the long-wait status line stays honest — there is
## no MMR window widening behind it.
func start_queue(since_msec: int, normal_mode: bool = false) -> void:
	_layout()
	_normal_mode = normal_mode
	_start_msec = since_msec
	_phase = 0.0
	_found = -1
	visible = true
	_update_readout()


## 13z: live found-players progress pushed by the server
## ({queue_status}) — how many of the eight seats are filled.
var _found := -1
var _need := 8


func set_found(found: int, need: int) -> void:
	_found = found
	_need = need
	if visible and _built:
		_update_readout()


func stop_queue() -> void:
	visible = false


func is_open() -> bool:
	return visible and _built


## Capture hook: pretend the wait started `sec` seconds ago.
func set_elapsed_for_test(sec: float) -> void:
	_start_msec = Time.get_ticks_msec() - int(sec * 1000.0)
	_update_readout()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _start_msec) / 1000.0


func _update_readout() -> void:
	var el := _elapsed()
	_timer_lbl.text = "%02d:%02d" % [int(el) / 60, int(el) % 60]
	# 13z: once the server reports queue progress, the honest
	# found-count IS the status ("Đã tìm thấy X/8 người chơi");
	# the elapsed-based lines cover the moments before the first
	# report lands.
	if _found >= 0:
		_status_lbl.text = "Đã tìm thấy %d/%d người chơi" % [_found, _need]
	else:
		_status_lbl.text = "Đang tìm đối thủ..." if el < 30.0 \
				else ("Vẫn đang tìm đối thủ..." if _normal_mode
						else "Đang mở rộng phạm vi tìm kiếm...")


func _process(delta: float) -> void:
	if not visible or not _built:
		return
	_phase += delta
	_update_readout()
	_spinner.phase = _phase * 2.4
	_spinner.queue_redraw()
