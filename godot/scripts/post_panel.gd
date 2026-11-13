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
## either way.
##
## 17g adds the interaction row on every post: Like ·
## Bình luận (Facebook-style two-level comments, fetched
## lazily per post, state kept here keyed by post id) ·
## Chia sẻ (to my wall / my alliance via a chooser popup),
## plus a flag REPORT button in the header of OTHER
## people's posts (mine keep the trash button there).

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
const FA_FLAG := 0xF024 # 17g report (cmap-verified in fa-solid-900)
const FA_COMMENT := 0xF075 # 17g comments
const FA_SHARE := 0xF064 # 17g share

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
var _scroll: ScrollContainer
# 17g comment/share state, keyed by post id. Kept across
# _render() rebuilds so an open thread survives like
# patches landing elsewhere in the list.
var _cmt_open := {}
var _cmt_rows := {}
var _cmt_reply := {} # post_id -> {id, name}
var _cmt_drafts := {} # post_id -> String
var _share_layer: CanvasLayer = null
var _share_root: Control = null

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
		s.content_margin_top = 12
		s.content_margin_bottom = 12
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
	sb.content_margin_top = 0
	sb.content_margin_bottom = 2
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color",
			Color(0.1, 0.08, 0.02) if primary else PAPER)
	return b


## A compact action-row button (17g): FA glyph + caption in
## one centred row, BTN_BG pill like the rest of the panel.
func _action_btn(cp: int, text: String, col: Color = PAPER) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	var sb := _sb(BTN_BG, 8, PANEL_LINE, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 0
	sb.content_margin_bottom = 2
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _fa(cp, 13, col)
	hb.add_child(ic)
	var lb := _label(text, 12, col)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lb)
	b.add_child(hb)
	# A Button is NOT a container: it never measures its
	# children, so without an explicit width the pill
	# collapses to ~34px and the caption spills outside
	# (found on the 17g captures). Measure the content.
	var need := 20.0 + 6.0 \
			+ ic.get_combined_minimum_size().x \
			+ lb.get_combined_minimum_size().x
	b.custom_minimum_size = Vector2(need, 30)
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
	_scroll = ScrollContainer.new()
	var scroll := _scroll
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
	Net.post_comments_received.connect(func(pid: String, rows: Array) -> void:
		_cmt_rows[pid] = rows
		_render())
	Net.post_reported.connect(func(_p) -> void:
		_toast("Đã gửi báo cáo", false))
	Net.lobby_error.connect(func(msg: String) -> void:
		_status.text = msg
		_status.add_theme_color_override("font_color", Color(1.0, 0.62, 0.55))
		_status.visible = true)
	_render()


## Status line for action feedback: errors (lobby_error)
## stay until replaced; SUCCESS toasts fade after a few
## seconds.
func _toast(msg: String, is_error: bool) -> void:
	_status.text = msg
	_status.add_theme_color_override("font_color",
			Color(1.0, 0.62, 0.55) if is_error else Color(0.55, 0.95, 0.6))
	_status.visible = true
	if not is_error:
		var keep := msg
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_inside_tree() and _status.text == keep:
				_status.visible = false)


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
	# Owner order 2026-11-12: NO outer frame around the
	# composer — the bar sits directly on the panel.
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	# Row 1: my avatar + writing field + Đăng bài at one
	# height — one tidy bar instead of a big empty box
	# (owner: "khung đăng bài viết xấu").
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	var my_av := AvatarFrame.new()
	my_av.custom_minimum_size = Vector2(46, 46)
	my_av.set_content(Avatars.texture_for_user(Avatars.local_avatar(),
			Net.account_name),
			String(Net.auth_profile.get("frame_id", "")), false)
	row1.add_child(my_av)
	_draft_text = TextEdit.new()
	_draft_text.custom_minimum_size = Vector2(0, 46)
	_draft_text.placeholder_text = "Viết gì đó…"
	_draft_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_draft_text.add_theme_font_size_override("font_size", 14)
	_draft_text.add_theme_color_override("font_color", PAPER)
	_draft_text.add_theme_color_override("font_placeholder_color", DIM)
	_draft_text.add_theme_stylebox_override("normal",
			_field_sb(FIELD_BG, PANEL_LINE, 1, true))
	var focus_sb := _field_sb(FIELD_BG, GOLD, 1, true)
	_draft_text.add_theme_stylebox_override("focus", focus_sb)
	# Owner order 2026-11-12: the image icon sits INSIDE
	# the input field, icon only, no caption. The field's
	# right margin grows so text never runs under the icon.
	for sbx in [_draft_text.get_theme_stylebox("normal"),
			_draft_text.get_theme_stylebox("focus")]:
		(sbx as StyleBoxFlat).content_margin_right = 46
	_draft_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	var field_wrap := Control.new()
	field_wrap.custom_minimum_size = Vector2(0, 46)
	field_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_wrap.add_child(_draft_text)
	var pick := Button.new()
	pick.focus_mode = Control.FOCUS_NONE
	for sn in ["normal", "hover", "pressed", "focus"]:
		pick.add_theme_stylebox_override(sn, _sb(Color(0, 0, 0, 0), 8))
	_btn_icon(pick, FA_IMAGE, 16, GOLD)
	pick.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	pick.anchor_left = 1.0
	pick.anchor_right = 1.0
	pick.offset_left = -40
	pick.offset_right = -6
	pick.offset_top = -17
	pick.offset_bottom = 17
	pick.pressed.connect(func() -> void:
		_gallery.visible = not _gallery.visible)
	field_wrap.add_child(pick)
	row1.add_child(field_wrap)
	var post_btn := _button("Đăng bài", true, 104)
	post_btn.custom_minimum_size = Vector2(104, 46)
	post_btn.pressed.connect(_on_post_pressed)
	row1.add_child(post_btn)
	vb.add_child(row1)
	# The attach chip lives directly under row 1 and only
	# takes space while an image is attached.
	_attach_chip = HBoxContainer.new()
	_attach_chip.add_theme_constant_override("separation", 6)
	_attach_chip.visible = false
	_attach_tex = TextureRect.new()
	_attach_tex.custom_minimum_size = Vector2(28, 28)
	_attach_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_attach_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_attach_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attach_chip.add_child(_attach_tex)
	_attach_name = _label("", 12, MUTED)
	_attach_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_attach_chip.add_child(_attach_name)
	var unattach := Button.new()
	unattach.flat = true
	unattach.custom_minimum_size = Vector2(26, 26)
	_btn_icon(unattach, FA_XMARK, 12, MUTED)
	unattach.pressed.connect(func() -> void: _set_attach(""))
	_attach_chip.add_child(unattach)
	vb.add_child(_attach_chip)
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
	add_child(vb)


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
		_toast("Hãy viết gì đó hoặc đính kèm ảnh.", true)
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
	else:
		# 17g: OTHER people's posts carry the REPORT flag in
		# the same corner. Once reported it stays gold +
		# disabled ("Đã báo cáo"); the server records it.
		var reported := bool(row.get("reported_by_me", false))
		var flag := Button.new()
		flag.flat = true
		flag.focus_mode = Control.FOCUS_NONE
		flag.custom_minimum_size = Vector2(32, 32)
		flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		flag.tooltip_text = "Đã báo cáo" if reported else "Báo cáo bài viết"
		flag.disabled = reported
		_btn_icon(flag, FA_FLAG, 13, GOLD if reported else MUTED)
		if not reported:
			flag.pressed.connect(func() -> void: Net.post_report(pid))
		head.add_child(flag)
	vb.add_child(head)
	# Body: a SHARE renders the sharer line + the embedded
	# original card; a normal post renders its own text +
	# attached gallery image (aspect kept, height capped).
	if bool(row.get("shared", false)):
		vb.add_child(_label("Đã chia sẻ bài viết", 12, DIM))
		vb.add_child(_share_card(row))
	else:
		var text := String(row.get("text", ""))
		if text != "":
			vb.add_child(Emotes.make_rich(text, 14, PAPER))
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
	# Action row (17g): like · Bình luận (N) · Chia sẻ.
	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	var liked := bool(row.get("liked", false))
	var heart := Button.new()
	heart.flat = true
	heart.custom_minimum_size = Vector2(30, 28)
	_btn_icon(heart, FA_HEART, 15, LIKE_RED if liked else MUTED)
	heart.pressed.connect(func() -> void: Net.post_like(pid))
	act_row.add_child(heart)
	var like_lb := _label("%d lượt thích" % int(row.get("likes", 0)), 12, MUTED)
	like_lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	act_row.add_child(like_lb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_row.add_child(spacer)
	var cmt_count := int(row.get("comments", 0))
	if _cmt_rows.has(pid):
		cmt_count = (_cmt_rows[pid] as Array).size()
	var cmt_btn := _action_btn(FA_COMMENT, "Bình luận (%d)" % cmt_count)
	cmt_btn.pressed.connect(func() -> void:
		var open := not bool(_cmt_open.get(pid, false))
		_cmt_open[pid] = open
		if open and not _cmt_rows.has(pid):
			Net.post_request_comments(pid)
		_render())
	act_row.add_child(cmt_btn)
	var share_btn := _action_btn(FA_SHARE, "Chia sẻ")
	share_btn.pressed.connect(func() -> void: _open_share_chooser(pid))
	act_row.add_child(share_btn)
	vb.add_child(act_row)
	# Inline comment section under the post (17g).
	if bool(_cmt_open.get(pid, false)):
		vb.add_child(_comment_section(row))
	return card


## The embedded ORIGINAL card of a share post: original
## author's header + text + image inside a bordered inner
## panel — or the tombstone line when it was deleted.
func _share_card(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var csb := _sb(Color(0, 0, 0, 0.22), 8, PANEL_LINE, 1)
	csb.content_margin_left = 10
	csb.content_margin_right = 10
	csb.content_margin_top = 8
	csb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", csb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	if bool(row.get("orig_gone", false)):
		vb.add_child(_label("Bài viết gốc đã bị xoá", 13, DIM))
		return card
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var av_box := Control.new()
	av_box.custom_minimum_size = Vector2(32, 32)
	av_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var avf := AvatarFrame.new()
	avf.set_anchors_preset(Control.PRESET_FULL_RECT)
	avf.set_content(Avatars.texture_for_user(
			String(row.get("orig_avatar_id", "")), String(row.get("orig_author", ""))),
			String(row.get("orig_frame_id", "")), false)
	av_box.add_child(avf)
	head.add_child(av_box)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 1)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_child(_label(String(row.get("orig_author_name", "?")), 13, Color.WHITE))
	name_col.add_child(_label(_ago(int(row.get("orig_ts", 0))), 11, DIM))
	head.add_child(name_col)
	vb.add_child(head)
	var otext := String(row.get("orig_text", ""))
	if otext != "":
		vb.add_child(Emotes.make_rich(otext, 13, PAPER))
	var oimg := String(row.get("orig_image", ""))
	if oimg != "":
		var tex := gallery_texture(oimg)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(0, 140)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(tr)
	return card


# ------------------------------------------------------------ comments (17g)

## The inline comment section of one post: top-level
## comments with their replies indented under the root
## (Facebook's two levels — the server stores replies
## against the root only), then the reply chip + composer.
func _comment_section(row: Dictionary) -> VBoxContainer:
	var pid := String(row.get("id", ""))
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	var rows: Array = _cmt_rows.get(pid, [])
	var tops: Array = []
	var replies := {}
	for c in rows:
		var par := String(c.get("parent_id", ""))
		if par == "":
			tops.append(c)
		else:
			if not replies.has(par):
				replies[par] = []
			(replies[par] as Array).append(c)
	if rows.is_empty():
		sec.add_child(_label("Chưa có bình luận nào.", 12, DIM))
	for c in tops:
		sec.add_child(_comment_item(pid, c, false))
		for r in replies.get(String(c.get("id", "")), []):
			sec.add_child(_comment_item(pid, r, true))
	# Reply chip (same language as the chat hub's): who I
	# am answering, with an X to cancel.
	if _cmt_reply.has(pid):
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 6)
		var lb := _label("Đang trả lời %s" % String((_cmt_reply[pid] as Dictionary).get("name", "")),
				12, Color(0.55, 0.75, 1.0))
		lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(lb)
		var x := Button.new()
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(24, 24)
		_btn_icon(x, FA_XMARK, 11, Color(1.0, 0.62, 0.55))
		x.pressed.connect(func() -> void:
			_cmt_reply.erase(pid)
			_render())
		chip.add_child(x)
		sec.add_child(chip)
	# Composer: one per post, draft kept across rebuilds.
	var comp := HBoxContainer.new()
	comp.add_theme_constant_override("separation", 8)
	var le := LineEdit.new()
	le.placeholder_text = "Viết bình luận…"
	le.text = String(_cmt_drafts.get(pid, ""))
	le.custom_minimum_size = Vector2(0, 38)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", 13)
	le.add_theme_color_override("font_color", PAPER)
	le.add_theme_color_override("font_placeholder_color", DIM)
	le.add_theme_stylebox_override("normal", _field_sb(FIELD_BG, PANEL_LINE, 1))
	le.add_theme_stylebox_override("focus", _field_sb(FIELD_BG, GOLD, 1))
	le.text_changed.connect(func(t: String) -> void: _cmt_drafts[pid] = t)
	le.text_submitted.connect(func(_t: String) -> void: _send_comment(pid))
	comp.add_child(le)
	var send := _button("Gửi", true, 64)
	send.pressed.connect(func() -> void: _send_comment(pid))
	comp.add_child(send)
	sec.add_child(comp)
	return sec


func _send_comment(pid: String) -> void:
	var text := String(_cmt_drafts.get(pid, "")).strip_edges()
	if text == "":
		return
	var parent := String((_cmt_reply.get(pid, {}) as Dictionary).get("id", ""))
	_cmt_drafts[pid] = ""
	_cmt_reply.erase(pid)
	Net.post_comment(pid, parent, text)
	_render()


func _set_reply(pid: String, cid: String, who: String) -> void:
	_cmt_reply[pid] = {"id": cid, "name": who}
	_render()


## One comment row: framed avatar, name + time, text, and
## the small Trả lời / Xoá text actions. Replies are the
## same row, indented, with a smaller avatar.
func _comment_item(pid: String, c: Dictionary, is_reply: bool) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	if is_reply:
		var gutter := Control.new()
		gutter.custom_minimum_size = Vector2(30, 1)
		hb.add_child(gutter)
	var sz := 24 if is_reply else 28
	var av_box := Control.new()
	av_box.custom_minimum_size = Vector2(sz, sz)
	av_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var avf := AvatarFrame.new()
	avf.set_anchors_preset(Control.PRESET_FULL_RECT)
	avf.set_content(Avatars.texture_for_user(
			String(c.get("avatar_id", "")), String(c.get("author", ""))),
			String(c.get("frame_id", "")), false)
	av_box.add_child(avf)
	hb.add_child(av_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_label(Net.ally_disp(
			String(c.get("author_name", "?")), String(c.get("ally_tag", ""))),
			12, Color.WHITE))
	head.add_child(_label(_ago(int(c.get("at", 0))), 11, DIM))
	col.add_child(head)
	col.add_child(Emotes.make_rich(String(c.get("text", "")), 13, PAPER))
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 12)
	var cid := String(c.get("id", ""))
	var cname := String(c.get("author_name", ""))
	var rep := Button.new()
	rep.flat = true
	rep.focus_mode = Control.FOCUS_NONE
	rep.text = "Trả lời"
	rep.custom_minimum_size = Vector2(0, 20)
	rep.add_theme_font_size_override("font_size", 11)
	rep.add_theme_color_override("font_color", MUTED)
	rep.add_theme_color_override("font_hover_color", PAPER)
	rep.pressed.connect(func() -> void: _set_reply(pid, cid, cname))
	acts.add_child(rep)
	if bool(c.get("can_delete", false)):
		var del := Button.new()
		del.flat = true
		del.focus_mode = Control.FOCUS_NONE
		del.custom_minimum_size = Vector2(24, 20)
		del.tooltip_text = "Xoá bình luận"
		_btn_icon(del, FA_TRASH, 10, MUTED)
		del.pressed.connect(func() -> void: Net.post_comment_delete(cid))
		acts.add_child(del)
	col.add_child(acts)
	hb.add_child(col)
	return hb


# ------------------------------------------------------------ share chooser (17g)

## The share chooser: a small centred popup (same overlay
## pattern as the settings item-detail popup — a CanvasLayer
## so the viewport capture sees it) with the two targets.
## "Về liên minh" disables with a note when I have none.
func _open_share_chooser(pid: String) -> void:
	_close_share_chooser()
	if _share_layer == null:
		_share_layer = CanvasLayer.new()
		_share_layer.layer = 70
		add_child(_share_layer)
	_share_root = Control.new()
	_share_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_share_layer.add_child(_share_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_share_chooser())
	_share_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_share_root.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	var ps := _sb(Color(0.05, 0.06, 0.12, 0.98), 12, GOLD, 2)
	ps.content_margin_left = 16
	ps.content_margin_right = 16
	ps.content_margin_top = 14
	ps.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", ps)
	cc.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := _label("Chia sẻ bài viết", 16, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var bw := _button("Về trang cá nhân", true)
	bw.pressed.connect(func() -> void:
		_close_share_chooser()
		Net.post_share(pid, "wall")
		_toast("Đã chia sẻ về trang cá nhân", false))
	col.add_child(bw)
	var has_ally := not Net.alliance_mine.is_empty()
	var ba := _button("Về liên minh", false)
	if has_ally:
		ba.pressed.connect(func() -> void:
			_close_share_chooser()
			Net.post_share(pid, "alliance")
			_toast("Đã chia sẻ về liên minh", false))
	else:
		ba.disabled = true
	col.add_child(ba)
	if not has_ally:
		var note := _label("Chưa có liên minh", 12, DIM)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(note)
	var cancel := _button("Huỷ", false)
	cancel.pressed.connect(func() -> void: _close_share_chooser())
	col.add_child(cancel)


func _close_share_chooser() -> void:
	if _share_root != null:
		_share_root.queue_free()
		_share_root = null


# ------------------------------------------------------------ capture seams (17g)

## First row id by ownership ("" when none) — capture use.
func shot_first_post_id(want_mine: bool) -> String:
	for r in _rows():
		if bool(r.get("mine", false)) == want_mine:
			return String(r.get("id", ""))
	return ""


func shot_open_comments(pid: String) -> void:
	_cmt_open[pid] = true
	Net.post_request_comments(pid)
	_render()


func shot_comments_loaded(pid: String) -> bool:
	return _cmt_rows.has(pid)


## Sets the reply target to the post's first top-level
## comment (capture (b): the reply chip in the composer).
func shot_reply_first(pid: String) -> void:
	for c in _cmt_rows.get(pid, []):
		if String(c.get("parent_id", "")) == "":
			_set_reply(pid, String(c.get("id", "")),
					String(c.get("author_name", "")))
			return


func shot_open_share(pid: String) -> void:
	_open_share_chooser(pid)


## Scrolls the post list to the very bottom (captures: an
## open thread / a share card sits below the fold).
func shot_scroll_bottom() -> void:
	if _scroll != null:
		_scroll.scroll_vertical = 100000


## Scrolls so the BOTTOM of one post's card meets the
## viewport's bottom edge (captures: an opened comment
## section ends with its composer — scroll-to-bottom of
## the whole list overshoots when later posts exist).
func shot_show_post_bottom(pid: String) -> void:
	if _scroll == null or _list_box == null:
		return
	var rows := _rows()
	for i in rows.size():
		if String(rows[i].get("id", "")) == pid:
			var card := _list_box.get_child(i) as Control
			if card == null:
				return
			var target := int(card.position.y + card.size.y \
					- _scroll.size.y + 16)
			_scroll.scroll_vertical = maxi(0, target)
			return
