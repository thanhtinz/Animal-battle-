class_name NamePanel
extends CanvasLayer
## Empire Age 13r — "Đặt Tên Nhân Vật" panel, after Tín's
## reference 3. The panel is ONE baked artwork (assets/
## name_panel.png: ornate gold frame, scroll+quill crest, red
## title plaque, the field, the caption and the Xác Nhận button
## are all painted in). Only three live elements ride on top,
## laid out by fractions of the artwork measured when the asset
## was cut (tools/build_entry_assets.py):
##   field  (0.2034, 0.4477) → (0.7897, 0.5957)  transparent edit
##   dice   (0.7940, 0.4561) → (0.9000, 0.6005)  transparent hit
##   button (0.2190, 0.7136) → (0.7810, 0.8748)  transparent hit
##   error  (0.1086, 0.6101) → (0.8931, 0.6462)  red label strip
## The baked placeholder text shows through the transparent
## edit until the player focuses/types — a cover strip then
## hides it so typed text never doubles up with the painting.
## The cover is sampled FROM the artwork itself: the field's
## text area with every row averaged to a single colour, which
## erases the glyphs while keeping the painted gradient and
## shading row-for-row.
##
## Rules (the baked caption, enforced client-side AND by the
## server): 3–16 characters, Unicode letters + digits + "_".

const PANEL_TEX := preload("res://assets/name_panel.png")
const BG_TEX := preload("res://assets/login_bg.png")
## The field's TEXT AREA (measured on the artwork): the painted
## person glyph sits at 0.102–0.191, the placeholder text at
## 0.229–0.572, the dice at 0.802–0.897. The live edit covers
## exactly the text area, so typing starts where the painted
## placeholder starts — right of the glyph.
const FIELD_FR := Rect2(0.2034, 0.4477, 0.7897 - 0.2034, 0.5957 - 0.4477)
const DICE_FR := Rect2(0.7940, 0.4561, 0.9000 - 0.7940, 0.6005 - 0.4561)
const BUTTON_FR := Rect2(0.2190, 0.7136, 0.7810 - 0.2190, 0.8748 - 0.7136)
const ERROR_FR := Rect2(0.1086, 0.6101, 0.8931 - 0.1086, 0.6462 - 0.6101)
## The cover strip: the field's text lane, interior only (just
## inside the gold border), from just left of the placeholder's
## first word to just before the dice.
const PLACEHOLDER_FR := Rect2(0.1980, 0.4550, 0.7900 - 0.1980, 0.5880 - 0.4550)

const NAME_A := ["Hiệp", "Chiến", "Long", "Phong", "Thiết", "Ngọc",
		"Tuyết", "Minh", "Hoàng", "Thiên", "Bạch", "Ngân", "Kim",
		"Sơn", "Hải", "Vũ", "Tinh", "Nguyệt", "Vân", "Liệt"]
const NAME_B := ["Sĩ", "Binh", "Kỵ", "Tướng", "Vương", "Đế", "Hầu",
		"Bá", "Kiếm", "Cung", "Thần", "Phong", "Long", "Hổ", "Sư",
		"Quân", "Anh", "Hào", "Chúa", "Linh"]
const NAME_C := ["", "", "", "", "9", "99", "_1", "7", "88"]

var _panel: TextureRect
var _edit: LineEdit
var _cover: TextureRect
var _error: Label
var _flash: ColorRect
var _rng := RandomNumberGenerator.new()


## Build the placeholder cover: sample the field's text area
## from the artwork and average every row to one colour. The
## painted glyphs dissolve; the field's own gradient and edge
## shading survive, so the cover is invisible as a patch.
func _make_cover_texture() -> Texture2D:
	var img := PANEL_TEX.get_image()
	if img == null or img.is_empty():
		var flat := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		flat.fill(Color(0.075, 0.10, 0.16))
		return ImageTexture.create_from_image(flat)
	var tw := img.get_width()
	var th := img.get_height()
	var region := Rect2i(int(PLACEHOLDER_FR.position.x * tw),
			int(PLACEHOLDER_FR.position.y * th),
			int(PLACEHOLDER_FR.size.x * tw), int(PLACEHOLDER_FR.size.y * th))
	var strip := img.get_region(region)
	# Per row, average only the DARKEST 60% of sampled pixels:
	# the painted glyphs are the bright minority, so they drop
	# out entirely instead of lightening the row into a smear.
	for y in range(strip.get_height()):
		var samples: Array[Color] = []
		var x := 0
		while x < strip.get_width():
			samples.append(strip.get_pixel(x, y))
			x += 3
		samples.sort_custom(func(a: Color, b: Color) -> bool:
			return a.get_luminance() < b.get_luminance())
		var keep := maxi(1, int(samples.size() * 0.6))
		var acc := Vector3.ZERO
		for i in range(keep):
			var c := samples[i]
			acc += Vector3(c.r, c.g, c.b)
		var avg := acc / float(keep)
		var col := Color(avg.x, avg.y, avg.z)
		for xx in range(strip.get_width()):
			strip.set_pixel(xx, y, col)
	return ImageTexture.create_from_image(strip)


func _init() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build()
	visible = false
	Net.name_error.connect(func(msg: String) -> void:
		if visible:
			show_error(msg))


func _frac_rect(fr: Rect2) -> Rect2:
	var ps := _panel.size
	return Rect2(fr.position * ps, fr.size * ps)


func _build() -> void:
	# The panel floats over the (dimmed) login scene, per the
	# reference flow — its own copy of the scene art, so it
	# looks the same whatever screen it was reached from.
	var bg := TextureRect.new()
	bg.texture = BG_TEX
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = TextureRect.new()
	_panel.texture = PANEL_TEX
	_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Natural aspect 1160×831; display height ≈ 600 of 648.
	var ph := 600.0
	var pw := ph * 1160.0 / 831.0
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -pw * 0.5
	_panel.offset_right = pw * 0.5
	_panel.offset_top = -ph * 0.5
	_panel.offset_bottom = ph * 0.5
	add_child(_panel)

	_cover = TextureRect.new()
	_cover.texture = _make_cover_texture()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_SCALE
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	_panel.add_child(_cover)

	_edit = LineEdit.new()
	_edit.max_length = 24
	_edit.add_theme_font_size_override("font_size", 25)
	_edit.add_theme_color_override("font_color", Color(0.93, 0.94, 0.97))
	_edit.add_theme_color_override("caret_color", Color(0.98, 0.83, 0.45))
	_edit.add_theme_color_override("selection_color", Color(0.35, 0.3, 0.12))
	var empty := StyleBoxEmpty.new()
	_edit.add_theme_stylebox_override("normal", empty)
	_edit.add_theme_stylebox_override("focus", empty)
	_edit.add_theme_stylebox_override("read_only", empty)
	_edit.text_changed.connect(func(_t: String) -> void: _sync_cover())
	_edit.focus_entered.connect(func() -> void: _sync_cover())
	_edit.focus_exited.connect(func() -> void: _sync_cover())
	_edit.text_submitted.connect(func(_t: String) -> void: confirm())
	_panel.add_child(_edit)

	var dice := Button.new()
	dice.focus_mode = Control.FOCUS_NONE
	var flat := StyleBoxEmpty.new()
	dice.add_theme_stylebox_override("normal", flat)
	dice.add_theme_stylebox_override("hover", flat)
	dice.add_theme_stylebox_override("pressed", flat)
	dice.add_theme_stylebox_override("focus", flat)
	dice.pressed.connect(roll_dice)
	_panel.add_child(dice)
	dice.set_meta("fr", DICE_FR)

	var confirm_btn := Button.new()
	confirm_btn.focus_mode = Control.FOCUS_NONE
	confirm_btn.add_theme_stylebox_override("normal", flat)
	confirm_btn.add_theme_stylebox_override("hover", flat)
	confirm_btn.add_theme_stylebox_override("pressed", flat)
	confirm_btn.add_theme_stylebox_override("focus", flat)
	confirm_btn.pressed.connect(confirm)
	_panel.add_child(confirm_btn)
	confirm_btn.set_meta("fr", BUTTON_FR)

	_error = Label.new()
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_error.add_theme_font_size_override("font_size", 16)
	_error.add_theme_color_override("font_color", Color(1.0, 0.5, 0.42))
	_error.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_error.add_theme_constant_override("shadow_offset_x", 1)
	_error.add_theme_constant_override("shadow_offset_y", 1)
	_error.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error.set_meta("fr", ERROR_FR)
	_panel.add_child(_error)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_flash)

	# Position the overlays once the panel has its size.
	_panel.resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	if _panel == null or _panel.size.x < 10.0:
		return
	_edit.position = _frac_rect(FIELD_FR).position + Vector2(4, 0)
	_edit.size = _frac_rect(FIELD_FR).size - Vector2(8, 0)
	_cover.position = _frac_rect(PLACEHOLDER_FR).position
	_cover.size = _frac_rect(PLACEHOLDER_FR).size
	for child in _panel.get_children():
		if child.has_meta("fr"):
			var r := _frac_rect(child.get_meta("fr"))
			child.position = r.position
			child.size = r.size


func _sync_cover() -> void:
	# The baked placeholder stays visible (with the caret in
	# front of it) until the player actually types — only then
	# does the cover hide it so the two texts never overlap.
	_cover.visible = _edit.text != ""


# ------------------------------------------------------------------ behaviour

func roll_dice() -> void:
	var nm := ""
	for _try in range(12):
		nm = NAME_A[_rng.randi_range(0, NAME_A.size() - 1)] \
				+ NAME_B[_rng.randi_range(0, NAME_B.size() - 1)] \
				+ NAME_C[_rng.randi_range(0, NAME_C.size() - 1)]
		if validate(nm) == "":
			break
	_edit.text = nm
	_error.text = ""
	_sync_cover()
	_flash_over(DICE_FR)


func _flash_over(fr: Rect2) -> void:
	var r := _frac_rect(fr)
	_flash.position = r.position
	_flash.size = r.size
	_flash.color = Color(1, 1, 1, 0.22)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.25)


## "" when valid, else the Vietnamese error to show.
static func validate(nm: String) -> String:
	var n := nm.length()
	if n < 3 or n > 16:
		return "Tên phải từ 3 – 16 ký tự (chữ, số và _)"
	for i in range(n):
		var c := nm[i]
		if c == "_":
			continue
		if c >= "0" and c <= "9":
			continue
		if c.to_lower() != c.to_upper():
			continue
		return "Tên chỉ gồm chữ, số và _ (không dấu cách/ký tự lạ)"
	return ""


func confirm() -> void:
	var nm := _edit.text.strip_edges()
	var err := validate(nm)
	if err != "":
		show_error(err)
		return
	_error.text = ""
	_flash_over(BUTTON_FR)
	Net.set_display_name(nm)


func show_error(msg: String) -> void:
	_error.text = msg


# ------------------------------------------------------------------ public API

func show_panel() -> void:
	visible = true
	_error.text = ""
	_edit.grab_focus()


func hide_panel() -> void:
	visible = false


func is_showing() -> bool:
	return visible


# Test-driver hooks (the register flow check drives the real UI).
func debug_dice() -> void:
	roll_dice()


func debug_text() -> String:
	return _edit.text


func debug_confirm() -> void:
	confirm()
