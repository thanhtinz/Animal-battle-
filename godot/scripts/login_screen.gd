class_name LoginScreen
extends CanvasLayer
## Empire Age 13r — login / register screen, after Tín's
## reference 1: painted valley scene (login_bg, generated clean
## from the reference) and a dark-navy panel with an elaborate
## gold frame and a pointed bottom tip holding the whole auth
## form, centred vertically at the right of the scene. (The
## sliced EMPIRE AGE logo plaque that sat above the panel was
## removed on Tín's order 2026-11-10 — "Bỏ logo luôn".)
## [Đăng Nhập | Đăng Ký] tabs (active = red plaque), username
## and password fields with leading glyphs and an eye toggle,
## remember-me + forgot-password row, the big red plaque submit,
## an "Hoặc đăng nhập với" divider and three social buttons.
##
## Honest wiring: submit calls the REAL account API
## (Net.login_account / Net.register_account) and server errors
## are shown verbatim. There is NO password-recovery system and
## NO OAuth — "Quên mật khẩu?" and the social buttons answer
## with a "sắp ra mắt" toast instead of faking a flow. The
## remember-me checkbox persists only the session TOKEN
## (Net.remember_session) — never a password. A discreet guest
## link keeps the offline/guest mode reachable.

signal guest_chosen

const BG_TEX := preload("res://assets/login_bg.png")
const PLAQUE_TEX := preload("res://assets/plaque_red_btn.png")
# Real brand marks (13r polish): Google's official multicolour
# G asset + Font Awesome brand glyphs baked to textures by
# tools/build_brand_icons.py — no more hand-drawn glyphs.
const GOOGLE_TEX := preload("res://assets/icon_google.png")
const FACEBOOK_TEX := preload("res://assets/icon_facebook.png")
const APPLE_TEX := preload("res://assets/icon_apple.png")
const EYE_TEX := preload("res://assets/icon_eye.png")
const EYE_OFF_TEX := preload("res://assets/icon_eye_off.png")

const GOLD_TXT := Color(0.98, 0.83, 0.45)
const TXT := Color(0.94, 0.96, 0.99)
const TXT_DIM := Color(0.62, 0.66, 0.76)
const ERR_TXT := Color(1.0, 0.55, 0.45)

var _root: Control
var _bg_rect: TextureRect
var _panel: LoginPanelFrame
var _content_box: VBoxContainer
var _tab_login: Button
var _tab_register: Button
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _pass2_row: PanelContainer
var _pass2_edit: LineEdit
var _eye_rect: TextureRect
var _remember_box: Button
var _remember_check: GlassIcon
var _remember_on: bool = true
var _submit_btn: Button
var _status: Label
var _toast: Label
var _register_mode: bool = false
var _pending_submit: bool = false
var _poll: float = 0.0
var _shake_t: float = 0.0


class LoginPanelFrame:
	extends Control
	## The reference panel silhouette: navy body, double gold
	## frame, shoulders near the bottom and a centre point.
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var shoulder := h - 44.0
		var body := PackedVector2Array([
			Vector2(14, 0), Vector2(w - 14, 0), Vector2(w, 14),
			Vector2(w, shoulder), Vector2(w * 0.5 + 30, shoulder),
			Vector2(w * 0.5, h), Vector2(w * 0.5 - 30, shoulder),
			Vector2(0, shoulder), Vector2(0, 14)])
		draw_colored_polygon(body, Color(0.085, 0.115, 0.20))
		# Soft light from the top, kept inside the silhouette.
		for i in range(7):
			var t := float(i) / 7.0
			draw_rect(Rect2(12.0, 4.0 + i * 11.0, w - 24.0, 11.0),
					Color(0.13, 0.16, 0.26, 0.10 * (1.0 - t)))
		var rim := PackedVector2Array(body)
		rim.append(body[0])
		draw_polyline(rim, Color(0.98, 0.78, 0.32), 3.0, true)
		var inner := PackedVector2Array()
		for p in body:
			inner.append(Vector2(lerpf(p.x, w * 0.5, 0.035), lerpf(p.y, h * 0.5, 0.045)))
		inner.append(inner[0])
		draw_polyline(inner, Color(0.98, 0.78, 0.32, 0.45), 1.4, true)
		# Corner gems: small gold diamonds at the shoulders.
		for cx in [8.0, w - 8.0]:
			var c := Vector2(cx, shoulder)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]),
				Color(0.98, 0.8, 0.35))


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	Net.auth_error.connect(func(msg: String) -> void:
		if visible:
			_show_error(msg))
	Net.auth_ok.connect(func(_t: String, _p: Dictionary) -> void:
		_pending_submit = false)


func _process(delta: float) -> void:
	if not visible:
		return
	if _shake_t > 0.0:
		_shake_t -= delta
		var k := maxf(0.0, _shake_t / 0.4)
		_root.position.x = sin(_shake_t * 55.0) * 9.0 * k
		if _shake_t <= 0.0:
			_root.position.x = 0.0
	if _pending_submit:
		_poll += delta
		if _poll > 0.2:
			_poll = 0.0
			if Net.connected:
				_pending_submit = false
				_do_submit()


# ------------------------------------------------------------------ build

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


func _label(text: String, size: int, color: Color = TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_bg_rect = TextureRect.new()
	_bg_rect.texture = BG_TEX
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg_rect)

	# Panel: right side, vertically centred on the scene at
	# each tab's own height (set_tab moves it per tab). Initial
	# values = the login tab's (height 475, centre y 324).
	_panel = LoginPanelFrame.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -551.0
	_panel.offset_right = -93.0
	_panel.offset_top = 86.0
	_panel.offset_bottom = 561.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -551.0 + 50.0
	box.offset_right = -93.0 - 50.0
	box.offset_top = 86.0 + 12.0
	box.offset_bottom = 561.0 - 46.0
	box.add_theme_constant_override("separation", 5)
	_root.add_child(box)
	_content_box = box

	# -- tab switch -------------------------------------------------
	var track := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.086, 0.129, 0.208)
	tsb.set_corner_radius_all(10)
	tsb.border_color = Color(0.55, 0.48, 0.28, 0.55)
	tsb.set_border_width_all(1)
	tsb.content_margin_left = 4
	tsb.content_margin_right = 4
	tsb.content_margin_top = 4
	tsb.content_margin_bottom = 4
	track.add_theme_stylebox_override("panel", tsb)
	box.add_child(track)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	track.add_child(tabs)
	_tab_login = _tab_button("Đăng Nhập")
	_tab_login.pressed.connect(func() -> void: set_tab(false))
	tabs.add_child(_tab_login)
	_tab_register = _tab_button("Đăng Ký")
	_tab_register.pressed.connect(func() -> void: set_tab(true))
	tabs.add_child(_tab_register)

	# -- fields ------------------------------------------------------
	var user_row := _field_row("person")
	_user_edit = _field_edit("Tên tài khoản")
	user_row.add_child(_user_edit)
	box.add_child(_field_shell(user_row))

	var pass_row := _field_row("lock")
	_pass_edit = _field_edit("Mật khẩu")
	_pass_edit.secret = true
	pass_row.add_child(_pass_edit)
	var eye_btn := Button.new()
	eye_btn.flat = true
	eye_btn.custom_minimum_size = Vector2(40, 40)
	eye_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eye_btn.focus_mode = Control.FOCUS_NONE
	_eye_rect = TextureRect.new()
	_eye_rect.texture = EYE_TEX
	_eye_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_eye_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_eye_rect.set_anchors_preset(Control.PRESET_CENTER)
	_eye_rect.offset_left = -17
	_eye_rect.offset_right = 17
	_eye_rect.offset_top = -17
	_eye_rect.offset_bottom = 17
	_eye_rect.modulate = Color(1, 1, 1, 0.88)
	_eye_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eye_btn.add_child(_eye_rect)
	eye_btn.pressed.connect(_toggle_eye)
	pass_row.add_child(eye_btn)
	box.add_child(_field_shell(pass_row))

	var pass2_row := _field_row("lock")
	_pass2_edit = _field_edit("Nhập lại mật khẩu")
	_pass2_edit.secret = true
	pass2_row.add_child(_pass2_edit)
	_pass2_row = _field_shell(pass2_row)
	_pass2_row.visible = false
	box.add_child(_pass2_row)

	# -- remember / forgot -------------------------------------------
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	rrow.custom_minimum_size = Vector2(0, 28)
	box.add_child(rrow)
	_remember_box = Button.new()
	_remember_box.custom_minimum_size = Vector2(26, 26)
	_remember_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_remember_box.focus_mode = Control.FOCUS_NONE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.10, 0.11, 0.16)
	bsb.set_corner_radius_all(5)
	bsb.border_color = Color(0.98, 0.78, 0.32)
	bsb.set_border_width_all(1)
	_remember_box.add_theme_stylebox_override("normal", bsb)
	_remember_box.add_theme_stylebox_override("hover", bsb)
	_remember_box.add_theme_stylebox_override("pressed", bsb)
	_remember_check = GlassIcon.new()
	_remember_check.kind = "check"
	_remember_check.set_anchors_preset(Control.PRESET_FULL_RECT)
	_remember_box.add_child(_remember_check)
	_remember_box.pressed.connect(func() -> void: _set_remember(not _remember_on))
	rrow.add_child(_remember_box)
	var rem_lbl := _label("Ghi nhớ đăng nhập", 16)
	rem_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rem_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rem_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rrow.add_child(rem_lbl)
	# (the label is a sibling tap target too)
	rem_lbl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_set_remember(not _remember_on))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(spacer)
	var forgot := LinkButton.new()
	forgot.text = "Quên mật khẩu?"
	forgot.add_theme_font_size_override("font_size", 16)
	forgot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	forgot.add_theme_color_override("font_color", Color(0.87, 0.70, 0.38))
	forgot.add_theme_color_override("font_hover_color", GOLD_TXT)
	forgot.focus_mode = Control.FOCUS_NONE
	forgot.pressed.connect(func() -> void:
		_show_toast("Tính năng quên mật khẩu sắp ra mắt"))
	rrow.add_child(forgot)

	# -- submit --------------------------------------------------------
	_submit_btn = Button.new()
	_submit_btn.text = "Đăng Nhập"
	_submit_btn.custom_minimum_size = Vector2(326, 58)
	_submit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_submit_btn.focus_mode = Control.FOCUS_NONE
	_submit_btn.add_theme_font_size_override("font_size", 30)
	_submit_btn.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	_submit_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.85))
	_submit_btn.add_theme_color_override("font_shadow_color", Color(0.2, 0.02, 0.02, 0.9))
	_submit_btn.add_theme_constant_override("shadow_offset_x", 2)
	_submit_btn.add_theme_constant_override("shadow_offset_y", 2)
	var ps := _plaque_style()
	_submit_btn.add_theme_stylebox_override("normal", ps)
	_submit_btn.add_theme_stylebox_override("hover", ps)
	_submit_btn.add_theme_stylebox_override("pressed", ps)
	_submit_btn.add_theme_stylebox_override("disabled", ps)
	_submit_btn.pressed.connect(_on_submit_pressed)
	box.add_child(_submit_btn)

	_status = _label("", 14, ERR_TXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 10)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	# -- divider + social ----------------------------------------------
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 10)
	box.add_child(drow)
	drow.add_child(_divider_line())
	var dl := _label("Hoặc đăng nhập với", 15, Color(0.93, 0.95, 0.99))
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drow.add_child(dl)
	drow.add_child(_divider_line())

	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 15)
	box.add_child(srow)
	for kind in ["google", "facebook", "apple"]:
		srow.add_child(_social_button(kind))

	# -- guest link ------------------------------------------------------
	var guest := LinkButton.new()
	guest.text = "Chơi với tư cách Khách"
	guest.add_theme_font_size_override("font_size", 14)
	guest.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82, 0.85))
	guest.add_theme_color_override("font_hover_color", TXT)
	guest.focus_mode = Control.FOCUS_NONE
	guest.pressed.connect(func() -> void: guest_chosen.emit())
	var grow := HBoxContainer.new()
	grow.alignment = BoxContainer.ALIGNMENT_CENTER
	grow.add_child(guest)
	box.add_child(grow)

	# -- toast -----------------------------------------------------------
	_toast = _label("", 15, TXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -260
	_toast.offset_right = 260
	_toast.offset_top = -108
	_toast.offset_bottom = -76
	_toast.add_theme_stylebox_override("normal", _toast_sb())
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)

	set_tab(false)
	_set_remember(true)


func _toast_sb() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.06, 0.11, 0.92)
	s.set_corner_radius_all(10)
	s.border_color = Color(0.98, 0.78, 0.32, 0.7)
	s.set_border_width_all(1)
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _divider_line() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.56, 0.60, 0.70, 0.75)
	c.custom_minimum_size = Vector2(0, 2)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _tab_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 25)
	b.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
	return b


func _field_row(icon_kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ic := GlassIcon.new()
	ic.kind = icon_kind
	ic.custom_minimum_size = Vector2(28, 28)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate = Color(1, 1, 1, 0.9)
	row.add_child(ic)
	return row


func _field_shell(row: HBoxContainer) -> PanelContainer:
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(0, 52)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.082, 0.114, 0.196)
	s.set_corner_radius_all(10)
	s.border_color = Color(0.44, 0.49, 0.63, 0.85)
	s.set_border_width_all(1)
	s.content_margin_left = 14
	s.content_margin_right = 10
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	shell.add_theme_stylebox_override("panel", s)
	shell.add_child(row)
	return shell


func _field_edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	e.add_theme_font_size_override("font_size", 23)
	e.add_theme_color_override("font_color", TXT)
	e.add_theme_color_override("font_placeholder_color", Color(0.58, 0.63, 0.74))
	e.add_theme_color_override("caret_color", GOLD_TXT)
	var empty := StyleBoxEmpty.new()
	e.add_theme_stylebox_override("normal", empty)
	e.add_theme_stylebox_override("focus", empty)
	e.add_theme_stylebox_override("read_only", empty)
	e.text_submitted.connect(func(_t: String) -> void: _on_submit_pressed())
	return e


func _social_button(kind: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(68, 68)
	b.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.965, 0.97, 0.985)
	s.set_corner_radius_all(14)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", s)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.90, 0.91, 0.94)
	sh.set_corner_radius_all(14)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	# Real brand texture, optically centred: the rect is the
	# box the (ink-trimmed) glyph must fit, aspect preserved.
	var texs := {"google": GOOGLE_TEX, "facebook": FACEBOOK_TEX, "apple": APPLE_TEX}
	var boxes := {"google": 41.0, "facebook": 47.0, "apple": 44.0}
	var g := TextureRect.new()
	g.texture = texs[kind]
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	g.set_anchors_preset(Control.PRESET_CENTER)
	var half: float = boxes[kind] * 0.5
	g.offset_left = -half
	g.offset_right = half
	g.offset_top = -half
	g.offset_bottom = half
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(g)
	var names := {"google": "Google", "facebook": "Facebook", "apple": "Apple"}
	b.pressed.connect(func() -> void:
		_show_toast("Đăng nhập bằng %s sắp ra mắt" % names[kind]))
	return b


# ------------------------------------------------------------------ behaviour

func set_tab(register: bool) -> void:
	_register_mode = register
	_status.text = ""
	_pass2_row.visible = register
	_submit_btn.text = "Đăng Ký" if register else "Đăng Nhập"
	# The register form is one field taller, so its panel is
	# taller (533 vs 475) — but both tabs keep the panel
	# vertically centred on the scene (centre y 324); the
	# content box rides 12 below the panel top and stops 46
	# above its bottom tip, exactly as before.
	if register:
		_panel.offset_top = 57.0
		_panel.offset_bottom = 590.0
		_content_box.offset_top = 69.0
		_content_box.offset_bottom = 544.0
	else:
		_panel.offset_top = 86.0
		_panel.offset_bottom = 561.0
		_content_box.offset_top = 98.0
		_content_box.offset_bottom = 515.0
	var ps := _plaque_style()
	var flat := StyleBoxEmpty.new()
	_tab_login.add_theme_stylebox_override("normal", ps if not register else flat)
	_tab_login.add_theme_stylebox_override("hover", ps if not register else flat)
	_tab_login.add_theme_stylebox_override("pressed", ps if not register else flat)
	_tab_register.add_theme_stylebox_override("normal", ps if register else flat)
	_tab_register.add_theme_stylebox_override("hover", ps if register else flat)
	_tab_register.add_theme_stylebox_override("pressed", ps if register else flat)
	# The active plaque takes ~63% of the track (ref 1), the
	# inactive label the rest.
	_tab_login.size_flags_stretch_ratio = 1.0 if register else 1.7
	_tab_register.size_flags_stretch_ratio = 1.7 if register else 1.0
	_tab_login.add_theme_color_override("font_color",
			Color(1.0, 0.94, 0.78) if not register else Color(0.82, 0.86, 0.94))
	_tab_register.add_theme_color_override("font_color",
			Color(1.0, 0.94, 0.78) if register else Color(0.82, 0.86, 0.94))


func _set_remember(on: bool) -> void:
	_remember_on = on
	_remember_check.visible = on


func _toggle_eye() -> void:
	_pass_edit.secret = not _pass_edit.secret
	_eye_rect.texture = EYE_TEX if _pass_edit.secret else EYE_OFF_TEX


func _show_error(msg: String) -> void:
	_status.text = msg
	_shake_t = 0.4


func _show_toast(msg: String) -> void:
	_toast.text = msg
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_submit_pressed() -> void:
	if _pending_submit:
		return
	var user := _user_edit.text.strip_edges()
	var pw := _pass_edit.text
	if user == "" or pw == "":
		_show_error("Nhập tên tài khoản và mật khẩu.")
		return
	if _register_mode and _pass2_edit.text != pw:
		_show_error("Mật khẩu nhập lại không khớp.")
		return
	_status.text = ""
	Net.remember_session = _remember_on
	if Net.connected:
		_do_submit()
	else:
		Net.connect_to_server(Net.DEFAULT_URL)
		_pending_submit = true
		_status.text = "Đang kết nối máy chủ..."


func _do_submit() -> void:
	var user := _user_edit.text.strip_edges()
	if _register_mode:
		Net.register_account(user, _pass_edit.text)
	else:
		Net.login_account(user, _pass_edit.text)
	_status.text = "Đang xử lý..."


# ------------------------------------------------------------------ public API

func show_login() -> void:
	visible = true
	_user_edit.grab_focus()


func hide_login() -> void:
	visible = false
	_pending_submit = false


func is_showing() -> bool:
	return visible


## Test driver: fill the register form and submit it exactly as
## a user's tap would.
func submit_register_for_test(user: String, pw: String) -> void:
	set_tab(true)
	_user_edit.text = user
	_pass_edit.text = pw
	_pass2_edit.text = pw
	_on_submit_pressed()
