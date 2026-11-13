class_name PostPanel
extends VBoxContainer

## Empire Age 17f — the shared social-post surface: a
## composer (text + optional gallery image) over a post
## list. Three modes share the one dialect:
##   "feed"     — the profile MXH Bảng tin (mine + friends')
##   "wall"     — the profile MXH Tường nhà (mine only)
##   "alliance" — the alliance screen's Bài viết tab
## All wire goes through Net's post caches; this control
## holds only the composer draft. Delete shows for my own
## posts, and for every post when can_moderate is set
## (alliance leader/deputy) — the server enforces the rule
## either way. NO comments in v1 (owner scope 2026-11-12).

const GOLD := Color(0.98, 0.8, 0.35)
const PAPER := Color(0.96, 0.94, 0.88)
const MUTED := Color(0.72, 0.76, 0.86)
const DIM := Color(0.55, 0.60, 0.72)
const FIELD_BG := Color(0.10, 0.12, 0.20)
const BTN_BG := Color(0.13, 0.16, 0.26)
const PANEL_LINE := Color(1, 0.85, 0.4, 0.35)
const LIKE_RED := Color(0.98, 0.35, 0.42)
const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"
const FA_HEART := 0xF004
const FA_IMAGE := 0xF03E
const FA_TRASH := 0xF1F8
const FA_XMARK := 0xF00D

var _mode := "feed"
var _can_moderate := false
var _fa_font: Font = null
var _draft_text: TextEdit
var _attach_id := ""
var _attach_chip: HBoxContainer
var _attach_tex: TextureRect
var _attach_name: Label
var _gallery: GridContainer
var _status: Label
var _list_box: VBoxContainer

static var _hero_tex_cache := {}


## Gallery image ids in picker order: the 20 anime avatars,
## then the 8 hero portraits.
static func gallery_ids() -> Array:
	var out: Array = []
	for id in Avatars.IDS:
		out.append(id)
	for hid in Characters.CHAR_IDS:
		out.append("hero:" + String(hid))
	return out


static func gallery_texture(image_id: String) -> Texture2D:
	if image_id.begins_with("hero:"):
		var hid := image_id.trim_prefix("hero:")
		if _hero_tex_cache.has(hid):
			return _hero_tex_cache[hid]
		var tex: Texture2D = null
		var path := "res://assets/avatars/avatar_sq_%s.png" % hid
		if ResourceLoader.exists(path):
			tex = load(path)
		_hero_tex_cache[hid] = tex
		return tex
	return Avatars.texture_for(image_id)


static func gallery_name(image_id: String) -> String:
	if image_id.begins_with("hero:"):
		return Characters.char_name(image_id.trim_prefix("hero:"))
	return Avatars.display_name(image_id)


func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


## Field stylebox with REAL text padding (owner order
## 2026-11-12: unset content margins fall back to the
## border width and text renders flush against the frame).
func _field_sb(bg: Color, border: Color, bw: int, text_edit := false) -> StyleBoxFlat:
	var s := _sb(bg, 8, border, bw)
	s.content_margin_left = 12
	s.content_margin_right = 12
	if text_edit:
		s.content_margin_top = 8
		s.content_margin_bottom = 8
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
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## An FA glyph centred inside a (flat) button.
func _btn_icon(btn: Button, cp: int, px: int, col: Color) -> void:
	var l := _fa(cp, px, col)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(l)


func _button(text: String, primary := false, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 38)
	else:
		b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 14)
	var sb := _sb(Color(0.98, 0.8, 0.35) if primary else BTN_BG, 8,
			Color(0.72, 0.52, 0.15) if primary else PANEL_LINE, 1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color",
			Color(0.1, 0.08, 0.02) if primary else PAPER)
	return b


## Builds the panel for a mode. Call once, right after new().
func setup(p_mode: String, p_can_moderate := false) -> void:
	_mode = p_mode
	_can_moderate = p_can_moderate
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_composer()
	_status = _label("", 12, Color(1.0, 0.62, 0.55))
	_status.visible = false
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 10)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	Net.post_feed_received.connect(func(_r) -> void: if _mode == "feed": _render())
	Net.post_wall_received.connect(func(_r) -> void: if _mode == "wall": _render())
	Net.post_alliance_received.connect(func(_r) -> void: if _mode == "alliance": _render())
	Net.post_created_received.connect(func(p: Dictionary) -> void:
		var ally := String(p.get("scope", "")) != ""
		if ally == (_mode == "alliance"):
			_clear_composer()
			refresh())
	Net.post_patched.connect(func(_p) -> void: _render())
	Net.post_removed.connect(func(_id) -> void: _render())
	Net.custom_avatar_ready.connect(func(_u) -> void: _render())
	Net.lobby_error.connect(func(msg: String) -> void:
		_status.text = msg
		_status.visible = true)
	_render()


## Re-requests this mode's list from the server.
func refresh() -> void:
	match _mode:
		"feed":
			Net.post_request_feed()
		"wall":
			Net.post_request_wall()
		"alliance":
			Net.post_request_alliance()


func _rows() -> Array:
	match _mode:
		"feed":
			return Net.post_feed_rows
		"wall":
			return Net.post_wall_rows
		"alliance":
			return Net.post_ally_rows
	return []


# ------------------------------------------------------------ composer

func _build_composer() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			_sb(Color(1, 1, 1, 0.045), 10, PANEL_LINE, 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	_draft_text = TextEdit.new()
	_draft_text.custom_minimum_size = Vector2(0, 62)
	_draft_text.placeholder_text = "Viết gì đó…"
	_draft_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_draft_text.add_theme_font_size_override("font_size", 14)
	_draft_text.add_theme_color_override("font_color", PAPER)
	_draft_text.add_theme_color_override("font_placeholder_color", DIM)
	_draft_text.add_theme_stylebox_override("normal",
			_field_sb(FIELD_BG, PANEL_LINE, 1, true))
	_draft_text.add_theme_stylebox_override("focus",
			_field_sb(FIELD_BG, GOLD, 1, true))
	vb.add_child(_draft_text)
	# Attach chip (hidden until an image is picked).
	_attach_chip = HBoxContainer.new()
	_attach_chip.add_theme_constant_override("separation", 8)
	_attach_chip.visible = false
	_attach_tex = TextureRect.new()
	_attach_tex.custom_minimum_size = Vector2(36, 36)
	_attach_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_attach_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_attach_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attach_chip.add_child(_attach_tex)
	_attach_name = _label("", 13, MUTED)
	_attach_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_attach_chip.add_child(_attach_name)
	var unattach := Button.new()
	unattach.flat = true
	unattach.custom_minimum_size = Vector2(30, 30)
	_btn_icon(unattach, FA_XMARK, 13, MUTED)
	unattach.pressed.connect(func() -> void: _set_attach(""))
	_attach_chip.add_child(unattach)
	vb.add_child(_attach_chip)
	# Action row: gallery toggle + Đăng.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var pick := _button("", false, 44)
	_btn_icon(pick, FA_IMAGE, 16, GOLD)
	pick.pressed.connect(func() -> void:
		_gallery.visible = not _gallery.visible)
	row.add_child(pick)
	row.add_child(_label("Đính kèm ảnh từ thư viện của game", 12, DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var post_btn := _button("Đăng bài", true, 110)
	post_btn.pressed.connect(_on_post_pressed)
	row.add_child(post_btn)
	vb.add_child(row)
	# Gallery grid (hidden until toggled).
	_gallery = GridContainer.new()
	_gallery.columns = 7
	_gallery.add_theme_constant_override("h_separation", 6)
	_gallery.add_theme_constant_override("v_separation", 6)
	_gallery.visible = false
	for gid in gallery_ids():
		var cell := TextureButton.new()
		cell.texture_normal = gallery_texture(gid)
		cell.ignore_texture_size = true
		cell.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		cell.custom_minimum_size = Vector2(44, 44)
		cell.tooltip_text = gallery_name(gid)
		var id := String(gid)
		cell.pressed.connect(func() -> void:
			_set_attach(id)
			_gallery.visible = false)
		_gallery.add_child(cell)
	vb.add_child(_gallery)
	add_child(card)


func _set_attach(id: String) -> void:
	_attach_id = id
	_attach_chip.visible = id != ""
	if id != "":
		_attach_tex.texture = gallery_texture(id)
		_attach_name.text = gallery_name(id)


func _clear_composer() -> void:
	_draft_text.text = ""
	_set_attach("")
	_gallery.visible = false


func _on_post_pressed() -> void:
	var text := _draft_text.text.strip_edges()
	if text == "" and _attach_id == "":
		_status.text = "Hãy viết gì đó hoặc đính kèm ảnh."
		_status.visible = true
		return
	_status.visible = false
	Net.post_create(_mode == "alliance", text, _attach_id)


# ------------------------------------------------------------ list

func _render() -> void:
	if _list_box == null:
		return
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	var rows := _rows()
	if rows.is_empty():
		var empty := _label("Chưa có bài viết nào.", 13, DIM)
		if _mode == "wall":
			empty.text = "Tường nhà còn trống — đăng bài đầu tiên của bạn."
		elif _mode == "alliance":
			empty.text = "Chưa có bài viết nào trong liên minh."
		else:
			empty.text = "Bảng tin trống — kết bạn và đăng bài để lấp đầy."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_box.add_child(empty)
		return
	for r in rows:
		_list_box.add_child(_post_item(r))


func _ago(ts: int) -> String:
	var d := int(Time.get_unix_time_from_system()) - ts
	if d < 60:
		return "Vừa xong"
	if d < 3600:
		return "%d phút trước" % int(d / 60)
	if d < 86400:
		return "%d giờ trước" % int(d / 3600)
	if d < 86400 * 30:
		return "%d ngày trước" % int(d / 86400)
	var dt := Time.get_datetime_dict_from_unix_time(ts)
	return "%02d/%02d/%d" % [int(dt.get("day", 1)), int(dt.get("month", 1)), int(dt.get("year", 2026))]


func _post_item(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var csb := _sb(Color(1, 1, 1, 0.045), 10, PANEL_LINE, 1)
	csb.content_margin_left = 12
	csb.content_margin_right = 12
	csb.content_margin_top = 10
	csb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", csb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	card.add_child(vb)
	# Header: framed avatar | name + time | delete.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var av_box := Control.new()
	av_box.custom_minimum_size = Vector2(44, 44)
	av_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var avf := AvatarFrame.new()
	avf.set_anchors_preset(Control.PRESET_FULL_RECT)
	avf.set_content(Avatars.texture_for_user(
			String(row.get("avatar_id", "")), String(row.get("author", ""))),
			String(row.get("frame_id", "")), false)
	av_box.add_child(avf)
	head.add_child(av_box)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 1)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_child(_label(Net.ally_disp(
			String(row.get("author_name", "?")), String(row.get("ally_tag", ""))),
			14, Color.WHITE))
	name_col.add_child(_label(_ago(int(row.get("at", 0))), 11, DIM))
	head.add_child(name_col)
	var pid := String(row.get("id", ""))
	if bool(row.get("mine", false)) or _can_moderate:
		var del := Button.new()
		del.flat = true
		del.custom_minimum_size = Vector2(32, 32)
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del.tooltip_text = "Xoá bài viết"
		_btn_icon(del, FA_TRASH, 13, MUTED)
		del.pressed.connect(func() -> void: Net.post_delete(pid))
		head.add_child(del)
	vb.add_child(head)
	# Body text (emoticon tokens render as inline stickers
	# through the shared Emotes rich builder).
	var text := String(row.get("text", ""))
	if text != "":
		vb.add_child(Emotes.make_rich(text, 14, PAPER))
	# Attached gallery image: aspect kept, height capped.
	var image_id := String(row.get("image", ""))
	if image_id != "":
		var tex := gallery_texture(image_id)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(0, 170)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(tr)
	# Like row.
	var like_row := HBoxContainer.new()
	like_row.add_theme_constant_override("separation", 6)
	var liked := bool(row.get("liked", false))
	var heart := Button.new()
	heart.flat = true
	heart.custom_minimum_size = Vector2(30, 28)
	_btn_icon(heart, FA_HEART, 15, LIKE_RED if liked else MUTED)
	heart.pressed.connect(func() -> void: Net.post_like(pid))
	like_row.add_child(heart)
	like_row.add_child(_label("%d lượt thích" % int(row.get("likes", 0)), 12, MUTED))
	vb.add_child(like_row)
	return card
