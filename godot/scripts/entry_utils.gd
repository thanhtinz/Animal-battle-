class_name EntryUtils
extends Control
## Empire Age 13r follow-up — the 3-icon vertical utility
## column from AvatarDK's entry screens (EntryUi: 3 round
## buttons down one edge, tiny label under each), shared by
## the two entry BACKGROUNDS — LoginScreen and WelcomeScreen.
## The loading screen deliberately has none, exactly like
## AvatarDK's data-download screen.
##
##   1. Thông báo (FA bell)    → notices info panel
##   2. Xoá cache (FA trash)   → drop + reload the entry art
##                               cache, toast "Đã xoá bộ nhớ đệm"
##   3. Hỗ trợ    (FA headset) → support info panel
##
## Style mirrors AvatarDK's UTIL_* constants: 54px circles,
## dark navy translucent fill (0.03, 0.06, 0.11, 0.72), light
## rim (0.82, 0.89, 0.97, 0.8), white FA glyph ~26px, tiny
## white label under each button; centres start 53px from
## the top, 102px apart. The info panels speak Empire Age's
## own language instead: PageShell navy + gold frame, with
## AvatarDK's red close square (0.85, 0.17, 0.17) and an FA
## xmark. Glyph textures are baked from the genuine
## fa-solid-900 font by tools/build_brand_icons.py.
##
## Content is truthful only: the notices panel shows the
## CURRENT ranked season (number + end date) when the client
## holds a server profile, and the display-name fact; the
## support panel gives self-help steps. Nothing is invented —
## no fake events, no fake contact channels.

const BELL_TEX := preload("res://assets/icon_bell.png")
const TRASH_TEX := preload("res://assets/icon_trash.png")
const HEADSET_TEX := preload("res://assets/icon_headset.png")
const XMARK_TEX := preload("res://assets/icon_xmark.png")

## Entry art that "Xoá cache" reloads from disk, bypassing
## the ResourceCache (CACHE_MODE_IGNORE — the Godot equivalent
## of AvatarDK's clearTextureCache: Godot exposes no eviction
## for resources other scripts hold const preloads to, so the
## visible art is re-fetched fresh instead). Bound
## TextureRects are re-pointed at the fresh copies so the
## backgrounds update at once.
const ART_PATHS := [
	"res://assets/login_bg.png",
	"res://assets/loading_bg.png",
	"res://assets/login_logo.png",
	"res://assets/name_panel.png",
	"res://assets/plaque_red.png",
	"res://assets/plaque_red_btn.png",
	"res://assets/icon_google.png",
	"res://assets/icon_facebook.png",
	"res://assets/icon_apple.png",
	"res://assets/icon_eye.png",
	"res://assets/icon_eye_off.png",
	"res://assets/icon_bell.png",
	"res://assets/icon_trash.png",
	"res://assets/icon_headset.png",
	"res://assets/icon_xmark.png",
]

const BTN := 54.0
const CY0 := 53.0
const STEP := 102.0
const GLYPH_BOX := 26.0
const FILL := Color(0.03, 0.06, 0.11, 0.72)
const FILL_HOVER := Color(0.05, 0.09, 0.17, 0.85)
const RIM := Color(0.82, 0.89, 0.97, 0.8)

var _bound: Array = [] # Array of [TextureRect, String]
var _glyph_rects: Array = [] # Array of [TextureRect, Texture2D const]
var _info: Control
var _info_title: Label
var _info_body: Label
var _toast: Label
var _toast_tw: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_column()
	_build_info()
	_build_toast()


## Host screens place the column by its centre x — AvatarDK
## puts it at W−62 on a full-width scene; a host whose right
## side carries a panel passes the scene region's right edge.
func place(cx: float) -> void:
	for i in range(3):
		var cy := CY0 + i * STEP
		var btn: Button = get_meta("btn%d" % i)
		btn.position = Vector2(cx - BTN * 0.5, cy - BTN * 0.5)
		var lbl: Label = get_meta("lbl%d" % i)
		lbl.position = Vector2(cx - 48.0, cy + BTN * 0.5 + 3.0)


## Register a visible TextureRect whose texture "Xoá cache"
## should refresh from the reloaded cache entry.
func bind_art(rect: TextureRect, path: String) -> void:
	_bound.append([rect, path])


# ------------------------------------------------------------------ column

func _circle_sb(fill: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(int(BTN * 0.5))
	s.border_color = RIM
	s.set_border_width_all(2)
	return s


func _build_column() -> void:
	var kinds := [
		[BELL_TEX, "Thông báo", "res://assets/icon_bell.png"],
		[TRASH_TEX, "Xoá cache", "res://assets/icon_trash.png"],
		[HEADSET_TEX, "Hỗ trợ", "res://assets/icon_headset.png"],
	]
	var acts := [open_notices, _clear_cache, _open_support]
	for i in range(3):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(BTN, BTN)
		btn.size = Vector2(BTN, BTN)
		btn.focus_mode = Control.FOCUS_NONE
		var n := _circle_sb(FILL)
		var h := _circle_sb(FILL_HOVER)
		btn.add_theme_stylebox_override("normal", n)
		btn.add_theme_stylebox_override("hover", h)
		btn.add_theme_stylebox_override("pressed", h)
		var g := TextureRect.new()
		g.texture = kinds[i][0]
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.set_anchors_preset(Control.PRESET_CENTER)
		g.offset_left = -GLYPH_BOX * 0.5
		g.offset_right = GLYPH_BOX * 0.5
		g.offset_top = -GLYPH_BOX * 0.5
		g.offset_bottom = GLYPH_BOX * 0.5
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(g)
		_glyph_rects.append([g, kinds[i][2]])
		btn.pressed.connect(acts[i])
		add_child(btn)
		set_meta("btn%d" % i, btn)
		var lbl := Label.new()
		lbl.text = kinds[i][1]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(96, 16)
		lbl.size = Vector2(96, 16)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)
		set_meta("lbl%d" % i, lbl)


# ------------------------------------------------------------------ info panel

func _build_info() -> void:
	_info = Control.new()
	_info.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info.mouse_filter = Control.MOUSE_FILTER_STOP
	_info.visible = false
	add_child(_info)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.06, 0.45) # AvatarDK's info dim
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(dim)
	_info.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_info())

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 0)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -140
	panel.offset_bottom = 140
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PageShell.BG, 0.97)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.98, 0.78, 0.32)
	sb.set_border_width_all(2)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	_info.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	vb.add_child(trow)
	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 24)
	_info_title.add_theme_color_override("font_color", PageShell.TITLE_COLOR)
	_info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	trow.add_child(_info_title)
	var close := Button.new()
	close.custom_minimum_size = Vector2(36, 36)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.focus_mode = Control.FOCUS_NONE
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.85, 0.17, 0.17) # AvatarDK BTN_CLOSE
	csb.set_corner_radius_all(10)
	close.add_theme_stylebox_override("normal", csb)
	close.add_theme_stylebox_override("hover", csb)
	close.add_theme_stylebox_override("pressed", csb)
	var x := TextureRect.new()
	x.texture = XMARK_TEX
	x.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	x.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	x.set_anchors_preset(Control.PRESET_CENTER)
	x.offset_left = -10
	x.offset_right = 10
	x.offset_top = -10
	x.offset_bottom = 10
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close.add_child(x)
	_glyph_rects.append([x, "res://assets/icon_xmark.png"])
	close.pressed.connect(_close_info)
	trow.add_child(close)

	_info_body = Label.new()
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.add_theme_font_size_override("font_size", 16)
	_info_body.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98))
	_info_body.add_theme_constant_override("line_spacing", 6)
	vb.add_child(_info_body)


func _show_info(title: String, lines: Array) -> void:
	_info_title.text = title
	var parts: Array[String] = []
	for l in lines:
		parts.append("•  " + String(l))
	_info_body.text = "\n".join(parts)
	_info.visible = true


func _close_info() -> void:
	_info.visible = false


func open_notices() -> void:
	_show_info("Thông báo", _notice_lines())


func _open_support() -> void:
	_show_info("Hỗ trợ", [
		"Không vào được game hoặc bị mất kết nối: kiểm tra lại đường truyền mạng, chờ vài giây rồi thử vào lại.",
		"Hình ảnh hoặc chữ hiển thị lỗi: bấm nút Xoá cache ở cột tiện ích rồi vào lại game.",
		"Nếu vẫn chưa được: tắt hẳn game rồi mở lại.",
	])


func _notice_lines() -> Array:
	var lines: Array = []
	var rank: Dictionary = Net.auth_profile.get("rank", {})
	var season := int(rank.get("season", 0))
	var end := int(Net.auth_profile.get("season_end", 0))
	if Net.connected and season > 0:
		lines.append("Mùa xếp hạng hiện tại: Mùa %d." % season)
		if end > 0:
			var d := Time.get_date_dict_from_unix_time(end)
			lines.append("Mùa %d kết thúc vào ngày %02d/%02d/%d." % [
				season, int(d["day"]), int(d["month"]), int(d["year"])])
	lines.append("Tên hiển thị: đặt tên nhân vật khi đăng ký — tên này hiện ở sảnh, hồ sơ, bạn bè và BXH.")
	return lines


# ------------------------------------------------------------------ cache + toast

func _clear_cache() -> void:
	var fresh := {}
	for p in ART_PATHS:
		var r := ResourceLoader.load(p, "Texture2D",
				ResourceLoader.CACHE_MODE_IGNORE)
		if r != null:
			fresh[p] = r
	for pair in _bound:
		if is_instance_valid(pair[0]) and fresh.has(pair[1]):
			pair[0].texture = fresh[pair[1]]
	for pair in _glyph_rects:
		if is_instance_valid(pair[0]) and fresh.has(pair[1]):
			pair[0].texture = fresh[pair[1]]
	show_toast("Đã xoá bộ nhớ đệm")


func _build_toast() -> void:
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 15)
	_toast.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -260
	_toast.offset_right = 260
	_toast.offset_top = -62
	_toast.offset_bottom = -22
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.06, 0.11, 0.88) # AvatarDK toast pill
	s.set_corner_radius_all(20)
	s.border_color = Color(0.55, 0.69, 0.86, 0.9)
	s.set_border_width_all(1)
	_toast.add_theme_stylebox_override("normal", s)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


## Test driver: run the real Xoá cache action and report how
## many bound textures came back as genuinely fresh instances.
func debug_clear_cache() -> String:
	var before: Array = []
	for pair in _bound:
		var id := 0
		if is_instance_valid(pair[0]) and pair[0].texture != null:
			id = pair[0].texture.get_instance_id()
		before.append(id)
	_clear_cache()
	var changed := 0
	for i in range(_bound.size()):
		if is_instance_valid(_bound[i][0]) and _bound[i][0].texture != null \
				and _bound[i][0].texture.get_instance_id() != before[i]:
			changed += 1
	return "bound=%d reloaded=%d" % [_bound.size(), changed]


func show_toast(msg: String) -> void:
	_toast.text = msg
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.18)
	_toast_tw.tween_interval(1.8)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
