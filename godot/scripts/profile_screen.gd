class_name ProfileScreen
extends CanvasLayer

## Profile screen (13l) — what opens when the home avatar is
## tapped, modelled on Tín's template and rebuilt for our data.
##
## Follow-up (13q follow-up 3, Tín's painted template v2):
## the page is rebuilt after the template he sent: a
## full-screen PAINTED SCENE background (the home scene
## art across the whole screen — follow-up 3b then removed
## the big character portrait that briefly filled the
## right zone, per Tín's "Bỏ hình nhân vật thay background
## vào", so the scene is now the only background), the
## PageShell back pill + "Hồ sơ" title floating over the
## scene at (11, 11) with NO header band and NO divider,
## and the account content in a FLOATING PANEL on the left:
## ornate gold border + corner gems, PageShell.BG interior,
## clear scene gaps on the left/top/bottom. The panel
## carries the account: portrait with an "Lv.N" badge,
## name, "ID: <n>" with a copy button, an XP bar to the
## next level, a settings gear, Danh hiệu / Liên minh rows
## (both honestly empty — no title or alliance system
## exists yet), the current + previous season rank cards
## with ribbon header strips, and one bordered stats box
## (Trận / Tỷ lệ thắng / Uy tín) with divided columns.
## (This supersedes the 13q solid-page + header-band
## arrangement for THIS page only; Bạn bè / Bảng xếp hạng
## keep the shared PageShell page + header untouched.)
##
## Everything renders from Net.auth_profile (server payload):
## id, level/xp (derived server-side from recorded matches),
## credit ("Uy tín"), season_stars, rank + prev_rank views.
## Guests get the same frame with a login prompt instead of
## stats — the account panel (lobby) stays the one place that
## registers/logs in.

## Left/right zone split of the full-screen layout.
const ZONE_SPLIT := 0.46

## Floating-panel insets (13q follow-up 3): clear scene
## gaps around the panel — left and bottom 14; top 81 so
## the panel clears the floating back pill + title (the
## pill occupies y 11..55).
const PANEL_LEFT := 14.0
const PANEL_TOP := 81.0
const PANEL_BOTTOM := 14.0

const GOLD := Color(0.98, 0.8, 0.35)
const GOLD_DEEP := Color(0.85, 0.6, 0.16)
const PAPER := Color(0.96, 0.94, 0.88)
const MUTED := Color(0.72, 0.76, 0.86)
# Owner order 2026-11-12: profile stats + settings button use
# Font Awesome (CSS-style) icons, not the drawn glass glyphs.
const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"
const FA_GEAR := 0xF013
const FA_KHANDA := 0xF66D
const FA_TROPHY := 0xF091
const FA_SHIELD := 0xF3ED

var game = null

var _fa_font: Font = null
var _root: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween


class StarIcon:
	extends Control
	## One drawn gold star (the rank cards' ★ — a polygon,
	## never a text glyph).

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array()
		for i in 10:
			var ang := -PI * 0.5 + i * PI / 5.0
			var rad := r if i % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(pts, Color(1.0, 0.82, 0.3))
		var loop := PackedVector2Array(pts)
		loop.append(pts[0])
		draw_polyline(loop, Color(0.45, 0.3, 0.05, 0.9), 1.2)


class XPBar:
	extends Control
	## Gold XP progress bar to the next level (ratio 0..1).

	var ratio: float = 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.10)
		bg.set_corner_radius_all(6)
		bg.border_color = Color(1, 0.85, 0.4, 0.30)
		bg.set_border_width_all(1)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		if ratio > 0.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(0.98, 0.75, 0.30)
			fill.set_corner_radius_all(6)
			var w := maxf(size.x * ratio, 10.0)
			draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(w, size.y)))


class MiniGlyph:
	extends Control
	## Small line glyphs the icon set doesn't carry: "copy"
	## (two overlapping sheets) and "pencil".

	var kind: String = "copy":
		set(v):
			kind = v
			queue_redraw()

	const INK := Color(0.90, 0.92, 0.97)

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var u := s / 24.0 # icons.gd logical space
		if kind == "copy":
			var back := StyleBoxFlat.new()
			back.bg_color = Color(0, 0, 0, 0)
			back.border_color = Color(INK, 0.65)
			back.set_border_width_all(maxi(1, int(1.6 * u)))
			back.set_corner_radius_all(int(3 * u))
			draw_style_box(back, Rect2(Vector2(8, 3) * u, Vector2(13, 14) * u))
			var front := StyleBoxFlat.new()
			front.bg_color = Color(0.10, 0.12, 0.20)
			front.border_color = INK
			front.set_border_width_all(maxi(1, int(1.6 * u)))
			front.set_corner_radius_all(int(3 * u))
			draw_style_box(front, Rect2(Vector2(3, 7) * u, Vector2(13, 14) * u))
		else: # pencil, diagonal
			var body := PackedVector2Array([
				Vector2(4, 20) * u, Vector2(4.8, 15.2) * u,
				Vector2(15.6, 4.4) * u, Vector2(19.6, 8.4) * u,
				Vector2(8.8, 19.2) * u])
			draw_colored_polygon(body, Color(0.98, 0.80, 0.35))
			var tip := PackedVector2Array([
				Vector2(4, 20) * u, Vector2(4.8, 15.2) * u,
				Vector2(8.8, 19.2) * u])
			draw_colored_polygon(tip, Color(0.15, 0.10, 0.05))
			draw_line(Vector2(14.2, 5.8) * u, Vector2(18.2, 9.8) * u,
					Color(0.85, 0.25, 0.20), 2.2 * u)


class CornerGems:
	extends Control
	## Gold diamonds pinned to the panel corners (the painted
	## frame language of the mode panel, drawn).

	func _draw() -> void:
		for c in [Vector2(2, 2), Vector2(size.x - 2, 2),
				Vector2(2, size.y - 2), Vector2(size.x - 2, size.y - 2)]:
			var r := 5.5
			var pts := PackedVector2Array([c + Vector2(0, -r),
					c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			draw_colored_polygon(pts, Color(0.98, 0.80, 0.35))
			var inner := PackedVector2Array()
			for p in pts:
				inner.append(c + (p - c) * 0.45)
			draw_colored_polygon(inner, Color(0.85, 0.20, 0.15))


func setup(p_game) -> void:
	game = p_game
	layer = 50 # above home (40), below the MP lobby (60)
	_build()
	visible = false
	Net.auth_ok.connect(func(_t, _p) -> void: if visible: _refresh())
	Net.auth_out.connect(func() -> void: if visible: _refresh())
	# 17d: cosmetics equips / renames land as profile_update.
	Net.profile_updated.connect(func(_p) -> void: if visible: _refresh())
	Net.avatar_changed.connect(func(_a) -> void: if visible: _refresh())
	Net.display_name_changed.connect(func(_n) -> void: if visible: _refresh())
	# 17a: the Liên minh row renders from the live alliance
	# payload and re-renders when a fresh one lands.
	Net.alliance_home_received.connect(func(_m: Dictionary, _i: Array) -> void:
		if visible: _refresh())


func open() -> void:
	visible = true
	if Net.account_name != "":
		Net.alliance_request_home()
	_refresh()


func close() -> void:
	visible = false


# ------------------------------------------------------------ build

func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


func _label(text: String, fsize: int, color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# BACKGROUND (13q follow-up 3): a full-bleed painted
	# scene — the home scene art cover-fit across the WHOLE
	# screen (no solid page colour, no home UI). The
	# floating panel and the header float over it.
	var scene := TextureRect.new()
	scene.texture = load("res://assets/home_bg.png")
	scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scene)

	# (13q follow-up 3b, Tín: "Bỏ hình nhân vật thay
	# background vào") — the big character portrait that
	# used to fill the right zone is GONE: the painted
	# scene above is now the ONLY background, spanning
	# the full screen behind and around the panel. Only
	# the small panel avatar next to the name remains.

	# LEFT: the FLOATING PANEL (13q follow-up 3) — a card
	# with an ornate gold border on all sides + corner
	# gems, PageShell.BG interior, inset from the screen
	# edges by clear scene gaps (left PANEL_LEFT, top
	# PANEL_TOP so it clears the floating back pill +
	# title, bottom PANEL_BOTTOM); its right edge sits at
	# the zone split as before. The body's vertical slack
	# absorbs the insets; nothing is repacked or clipped.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = ZONE_SPLIT
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = PANEL_LEFT
	_panel.offset_top = PANEL_TOP
	_panel.offset_right = 0
	_panel.offset_bottom = -PANEL_BOTTOM
	_panel.add_theme_stylebox_override("panel",
			_sb(PageShell.BG, 10, Color(0.98, 0.8, 0.35, 0.85), 2))
	_root.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 11)
	margin.add_child(_body)
	var gems := CornerGems.new()
	gems.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(gems)

	# Header (PageShell geometry, kept per Tín's addendum
	# "Phải thêm tittle vào"): the gold back pill in the
	# screen's top-left corner at (11, 11) with the "Hồ sơ"
	# title immediately beside it — the identical pill +
	# title Bạn bè and Bảng xếp hạng carry — but on THIS
	# page they float directly over the painted scene:
	# the 13q header BAND (full-width strip + gold divider)
	# is gone.
	_root.add_child(PageShell.back_button(Callable(self, "close")))
	_root.add_child(PageShell.title_label("Hồ sơ"))

	# Toast (bottom-centre).
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel",
			_sb(Color(0.05, 0.06, 0.12, 0.95), 10, Color(1, 0.85, 0.4, 0.5), 1))
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -150
	_toast.offset_right = 150
	_toast.offset_top = -98
	_toast.offset_bottom = -62
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)
	_toast_label = _label("", 15, PAPER)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate = Color(1, 1, 1, 1)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


# ------------------------------------------------------------ content

func _fmt_num(n: int) -> String:
	# Vietnamese thousand separators: 6212 -> "6.212".
	var neg := n < 0
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if neg else "") + digits + out


## A Font Awesome glyph as a tintable Label (same pattern as
## alliance_screen._fa / hud._fa).
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


func _icon_button(kind: String, tip: String) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(40, 40)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",
			_sb(Color(0.03, 0.04, 0.08, 0.6), 20, Color(1, 0.85, 0.4, 0.4), 1))
	holder.add_child(panel)
	# Only caller is the settings gear (owner order 2026-11-12:
	# FA icon, not the drawn glyph).
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(_fa(FA_GEAR, 18, PAPER))
	holder.add_child(cc)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = tip
	holder.add_child(btn)
	return {"holder": holder, "btn": btn}


func _refresh() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var guest := Net.account_name == ""
	var p: Dictionary = Net.auth_profile
	# 17d: the account avatar comes from the anime catalogue
	# (Avatars) and wears the equipped frame via the shared
	# AvatarFrame helper (animated here).
	var avatar_id := Avatars.normalize_id(
			String(p.get("avatar_id", Avatars.local_avatar())) if not guest
			else Avatars.local_avatar())
	var portrait := Avatars.texture_for(avatar_id)

	# ---- header: portrait + Lv badge | name / ID / XP | gear
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var av_box := Control.new()
	av_box.custom_minimum_size = Vector2(100, 100)
	var av_frame := AvatarFrame.new()
	av_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	av_frame.set_content(portrait, String(p.get("frame_id", "")), true)
	av_box.add_child(av_frame)
	var lv_badge := PanelContainer.new()
	var lv_sb := _sb(Color(0.55, 0.38, 0.06, 0.98), 6, Color(1, 0.88, 0.5, 0.9), 1)
	lv_sb.content_margin_left = 8
	lv_sb.content_margin_right = 8
	lv_sb.content_margin_top = 1
	lv_sb.content_margin_bottom = 1
	lv_badge.add_theme_stylebox_override("panel", lv_sb)
	lv_badge.position = Vector2(6, 76)
	var lv_text := "Lv.%d" % int(p.get("level", 1)) if not guest else "Khách"
	lv_badge.add_child(_label(lv_text, 13, Color.WHITE))
	av_box.add_child(lv_badge)
	head.add_child(av_box)

	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 4)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if guest:
		name_col.add_child(_label("Khách", 23, Color.WHITE))
		var hint := _label("Bạn đang chơi với tư cách khách.", 14, MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_col.add_child(hint)
	else:
		# 17b: [TAG] before the name when the account is in an
		# alliance (tag resolved into the profile server-side).
		name_col.add_child(_label(Net.ally_disp(Net.display_name(),
				String(p.get("ally_tag", ""))), 23, Color.WHITE))
		var id_row := HBoxContainer.new()
		id_row.add_theme_constant_override("separation", 6)
		var acc_id := int(p.get("id", 0))
		id_row.add_child(_label("ID: %s" % (_fmt_num(acc_id) if acc_id > 0 else "—"),
				15, MUTED))
		var copy_holder := Control.new()
		copy_holder.custom_minimum_size = Vector2(24, 24)
		var glyph := MiniGlyph.new()
		glyph.kind = "copy"
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy_holder.add_child(glyph)
		var copy_btn := Button.new()
		copy_btn.flat = true
		copy_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		copy_btn.tooltip_text = "Chép ID"
		copy_btn.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(str(acc_id))
			_show_toast("Đã chép ID"))
		copy_holder.add_child(copy_btn)
		id_row.add_child(copy_holder)
		name_col.add_child(id_row)
		var xp_row := HBoxContainer.new()
		xp_row.add_theme_constant_override("separation", 8)
		var bar := XPBar.new()
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var for_next := maxi(1, int(p.get("xp_for_next", 100)))
		bar.ratio = float(int(p.get("xp_into_level", 0))) / float(for_next)
		xp_row.add_child(bar)
		xp_row.add_child(_label("%d/%d XP" % [int(p.get("xp_into_level", 0)), for_next],
				12, MUTED))
		name_col.add_child(xp_row)
	head.add_child(name_col)

	# 17d: the gear opens the personal-settings hub (Đổi tên /
	# Avatar / Danh hiệu / Trang trí).
	var gear := _icon_button("gear", "Cài đặt")
	gear["btn"].pressed.connect(func() -> void:
		if game != null and game.has_method("home_open_settings_panels"):
			game.home_open_settings_panels("hub"))
	head.add_child(gear["holder"])
	_body.add_child(head)

	if guest:
		_body.add_child(HSeparator.new())
		var note := _label("Đăng nhập để lưu hạng, cấp độ, uy tín và thư từ của bạn.",
				14, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(note)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		for txt in ["Đăng nhập", "Đăng ký"]:
			var b := Button.new()
			b.text = txt
			b.custom_minimum_size = Vector2(150, 42)
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(func() -> void:
				close()
				if game != null:
					game.home_open_account())
			row.add_child(b)
		_body.add_child(row)
		return

	# ---- Danh hiệu / Liên minh rows
	_body.add_child(HSeparator.new())
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	# 15h: earned titles ride the profile payload (a
	# tournament champion gains "Vô địch giải đấu"); the row
	# shows the first one, else the honest empty state.
	var titles: Array = p.get("titles", [])
	var title_text := "Chưa dùng Danh hiệu"
	# 17d: the EQUIPPED display title wins; the first earned
	# title is the fallback label.
	var equipped_title := String(p.get("display_title", ""))
	if equipped_title != "":
		title_text = "Danh hiệu: " + equipped_title
	elif not titles.is_empty():
		title_text = "Danh hiệu: " + String(titles[0])
	var tv := _label(title_text, 16)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(tv)
	# Owner order 2026-11-12: the pencil shortcut is REMOVED —
	# Danh hiệu is changed from the settings hub only.
	_body.add_child(title_row)

	# Liên minh row (17a): the account's real alliance from the
	# live payload; the whole value is a button into the
	# alliance screen (Main closes this profile first).
	var ally_row := HBoxContainer.new()
	ally_row.add_theme_constant_override("separation", 8)
	var al := _label("Liên minh:", 15, MUTED)
	ally_row.add_child(al)
	var aic := GlassIcon.new()
	aic.kind = "emblem"
	aic.custom_minimum_size = Vector2(20, 20)
	aic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ally_row.add_child(aic)
	var ally_btn := Button.new()
	ally_btn.flat = true
	ally_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	ally_btn.add_theme_font_size_override("font_size", 16)
	if Net.alliance_mine.is_empty():
		ally_btn.text = "Chưa có liên minh — bấm để mở"
		ally_btn.add_theme_color_override("font_color", MUTED)
		ally_btn.add_theme_color_override("font_hover_color", PAPER)
	else:
		ally_btn.text = String(Net.alliance_mine.get("name", ""))
		ally_btn.add_theme_color_override("font_color", Color(0.98, 0.8, 0.35))
		ally_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.45))
	ally_btn.pressed.connect(func() -> void:
		if game != null and game.has_method("home_open_alliance"):
			game.home_open_alliance())
	ally_row.add_child(ally_btn)
	_body.add_child(ally_row)

	# ---- rank cards
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	var rank: Dictionary = p.get("rank", {})
	cards.add_child(_rank_card("Hạng hiện tại", true,
			int(rank.get("tier", 0)), bool(rank.get("emperor", false)),
			String(rank.get("short_text", "")), int(p.get("season_stars", 0))))
	var prev: Dictionary = p.get("prev_rank", {})
	if prev.is_empty():
		cards.add_child(_rank_card_empty())
	else:
		cards.add_child(_rank_card("Hạng mùa trước", false,
				int(prev.get("tier", 0)), bool(prev.get("emperor", false)),
				String(prev.get("short_text", "")), int(p.get("prev_season_stars", 0))))
	_body.add_child(cards)

	# ---- stats row
	var wins := int(p.get("wins", 0))
	var matches := int(p.get("matches", 0))
	var rate := "—"
	if matches > 0:
		rate = ("%.1f%%" % (100.0 * float(wins) / float(matches))).replace(".", ",")
	var stats := PanelContainer.new()
	stats.add_theme_stylebox_override("panel",
			_sb(Color(1, 1, 1, 0.045), 10, Color(1, 0.85, 0.4, 0.35), 1))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	stats.add_child(srow)
	var cells := [
		["swords", _fmt_num(matches), "Trận"],
		["trophy", rate, "Tỷ lệ thắng"],
		["emblem", str(int(p.get("credit", 100))), "Uy tín"],
	]
	for i in cells.size():
		if i > 0:
			srow.add_child(VSeparator.new())
		srow.add_child(_stat_cell(cells[i][0], cells[i][1], cells[i][2]))
	_body.add_child(stats)


func _ribbon_strip(text: String, current: bool) -> PanelContainer:
	## The rank cards' ribbon header strip (template v2):
	## a small banner plaque across the card's top — deep
	## red for the current season, bronze-gold for the
	## previous one — with the card's title centred in it.
	var strip := PanelContainer.new()
	var sb := _sb(Color(0.55, 0.09, 0.11, 0.98) if current
			else Color(0.30, 0.23, 0.09, 0.98), 6,
			Color(1, 0.85, 0.4, 0.75), 1)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	strip.add_theme_stylebox_override("panel", sb)
	var l := _label(text, 12, Color(1, 0.92, 0.75) if current
			else Color(0.95, 0.88, 0.62))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.add_child(l)
	return strip


func _rank_card(ribbon: String, current: bool, tier: int, emperor: bool,
		rank_name: String, stars: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := Color(0.14, 0.05, 0.07, 0.95) if current else Color(0.05, 0.07, 0.12, 0.95)
	var rim := Color(0.85, 0.45, 0.25, 0.8) if current else Color(0.55, 0.62, 0.85, 0.55)
	card.add_theme_stylebox_override("panel", _sb(bg, 10, rim, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)
	vb.add_child(_ribbon_strip(ribbon, current))
	var tex := TextureRect.new()
	tex.texture = RankBadge.emblem_texture(tier, emperor)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tex.custom_minimum_size = Vector2(59, 74)
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(tex)
	var nm := _label(rank_name, 17, Color.WHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 5)
	var star := StarIcon.new()
	star.custom_minimum_size = Vector2(16, 16)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(star)
	srow.add_child(_label("×%d" % stars, 16, GOLD))
	vb.add_child(srow)
	return card


func _rank_card_empty() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
			_sb(Color(0.05, 0.07, 0.12, 0.95), 10, Color(0.55, 0.62, 0.85, 0.4), 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)
	vb.add_child(_ribbon_strip("Hạng mùa trước", false))
	var l := _label("Chưa có dữ liệu mùa trước", 15, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(l)
	return card


func _stat_cell(icon_kind: String, value: String, caption: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	# Owner order 2026-11-12: FA icons for the stats row
	# (khanda = the vendored font's sword; it has no "swords").
	var cp := FA_KHANDA
	if icon_kind == "trophy":
		cp = FA_TROPHY
	elif icon_kind == "emblem":
		cp = FA_SHIELD
	center.add_child(_fa(cp, 20, GOLD))
	vb.add_child(center)
	var v := _label(value, 20, Color.WHITE)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(v)
	var c := _label(caption, 12, MUTED)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(c)
	return vb
