class_name WelcomeScreen
extends CanvasLayer
## Empire Age 13r (Tín addendum) — the returning-player entry
## screen. Shown ONLY when boot restored a valid saved session:
## the painted scene full-bleed, NO logo (Tín: the welcome-back
## screen drops the plaque — the login form keeps it), and a
## bottom-centre cluster: the line "Chào mừng trở lại, <tên>!"
## directly above one big red-plaque "Bắt đầu" button, with a
## subtle "Đổi tài khoản" link beneath it so a returning player
## is never trapped in the wrong account.

signal start_pressed
signal switch_account_pressed

const BG_TEX := preload("res://assets/login_bg.png")
const PLAQUE_TEX := preload("res://assets/plaque_red_btn.png")

var _name_lbl: RichTextLabel
var _bg_rect: TextureRect
var _utils: EntryUtils


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _plaque_style() -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = PLAQUE_TEX
	s.texture_margin_left = 58.0
	s.texture_margin_right = 58.0
	s.texture_margin_top = 7.0
	s.texture_margin_bottom = 7.0
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 4
	s.content_margin_bottom = 6
	return s


func _build() -> void:
	_bg_rect = TextureRect.new()
	_bg_rect.texture = BG_TEX
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)

	# Soft dark backing (radial gradient, no hard edges) so the
	# welcome line and the subtle account link stay legible
	# over the bright river scene.
	var back := TextureRect.new()
	back.texture = _radial_backing()
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.offset_left = -420
	back.offset_right = 420
	back.offset_top = -240
	back.offset_bottom = 6
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.offset_left = -340
	col.offset_right = 340
	col.offset_top = -196
	col.offset_bottom = -34
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	_name_lbl = RichTextLabel.new()
	_name_lbl.bbcode_enabled = true
	_name_lbl.fit_content = true
	_name_lbl.scroll_active = false
	_name_lbl.add_theme_font_size_override("normal_font_size", 27)
	_name_lbl.add_theme_font_size_override("bold_font_size", 27)
	_name_lbl.add_theme_color_override("default_color", Color(0.97, 0.96, 0.99))
	_name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_name_lbl.add_theme_constant_override("shadow_offset_x", 2)
	_name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name_lbl)

	var start := Button.new()
	start.text = "Bắt đầu"
	start.custom_minimum_size = Vector2(326, 58)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.focus_mode = Control.FOCUS_NONE
	start.add_theme_font_size_override("font_size", 30)
	start.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	start.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.85))
	start.add_theme_color_override("font_shadow_color", Color(0.2, 0.02, 0.02, 0.9))
	start.add_theme_constant_override("shadow_offset_x", 2)
	start.add_theme_constant_override("shadow_offset_y", 2)
	var ps := _plaque_style()
	start.add_theme_stylebox_override("normal", ps)
	start.add_theme_stylebox_override("hover", ps)
	start.add_theme_stylebox_override("pressed", ps)
	start.pressed.connect(func() -> void: start_pressed.emit())
	col.add_child(start)

	var swap := LinkButton.new()
	swap.text = "Đổi tài khoản"
	swap.add_theme_font_size_override("font_size", 15)
	swap.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 0.8))
	swap.add_theme_color_override("font_hover_color", Color(0.97, 0.96, 0.99))
	swap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	swap.add_theme_constant_override("shadow_offset_x", 1)
	swap.add_theme_constant_override("shadow_offset_y", 1)
	swap.focus_mode = Control.FOCUS_NONE
	swap.pressed.connect(func() -> void: switch_account_pressed.emit())
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_child(swap)
	col.add_child(srow)

	# Utility column (13r follow-up, AvatarDK's EntryUi): this
	# screen is a full-width scene with no panel, so the column
	# takes AvatarDK's exact spot — right edge, cx = W − 62.
	_utils = EntryUtils.new()
	add_child(_utils)
	_utils.place(1152.0 - 62.0)
	_utils.bind_art(_bg_rect, "res://assets/login_bg.png")


## Radial dark gradient texture for the cluster backing:
## deep navy at the centre fading to fully transparent, so
## the cluster floats on the scene with no visible slab edge.
func _radial_backing() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var d := Vector2(float(x) / n - 0.5, float(y) / n - 0.5).length() * 2.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.44
			img.set_pixel(x, y, Color(0.015, 0.02, 0.05, a))
	return ImageTexture.create_from_image(img)


## Test driver: open the Thông báo info panel exactly as a
## tap on the bell button would.
func debug_open_notices() -> void:
	_utils.open_notices()


## Test driver: run the real Xoá cache action.
func debug_clear_cache() -> String:
	return _utils.debug_clear_cache()


func show_welcome() -> void:
	var nm := Net.display_name()
	_name_lbl.text = "[center]Chào mừng trở lại, [color=#f7cf6d]%s[/color]![/center]" % nm
	visible = true


func hide_welcome() -> void:
	visible = false


func is_showing() -> bool:
	return visible
