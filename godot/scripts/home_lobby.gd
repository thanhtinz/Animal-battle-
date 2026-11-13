class_name HomeLobby
extends CanvasLayer

## Home Lobby (P4 stage 5 / KE-HOACH 13g) — the painted boot
## screen modelled on Tín's reference: full-bleed Roman coastal
## panorama, profile chip top-left (the portrait in its
## square gold frame, with the account name and "Lv.N" on
## two lines beside it — Tín's follow-up after 13l; the
## full rank line still lives in the profile it opens),
## top-right utility row (Bạn bè / Thư /
## Cài Đặt / ping), a rotating season banner on the right, and
## ONE bottom row over the art (13i + follow-ups): NO band
## background — Tín's painted nav buttons (Thành Tích / Lịch
## Sử Trận / Bảng Xếp Hạng / Bạn Bè — the old Hướng Dẫn cell
## is gone; its panel currently has no entry point) sit
## directly on the panorama, evenly spaced in equal cells,
## and his painted BẮT ĐẦU button is pinned at the row's far
## right. BẮT ĐẦU opens the mode-choice panel (Đấu Thường →
## the NORMAL online queue, Đấu Hạng → ranked queue, Custom →
## the room flow, Minigame → placeholder; 13t); the season banner
## still goes to the ranked queue directly. The compact rank
## display floats just ABOVE the row, centred over BẮT ĐẦU.
## (The server's daily first-win bonus still exists and the
## end-of-match panel still reports it; its old home-screen
## display line was removed on Tín's order.)
## Everything here is REAL: friends and mail are server features
## (Store-backed), history is the server's ranked match record,
## the ping readout is a live app-level ping/pong against the
## relay. The world stays paused behind this screen; picking a
## mode hands off to the setup view (map panel) or the
## multiplayer lobby exactly as before.

const RankBadge := preload("res://scripts/rank_badge.gd")

const GOLD := Color(0.98, 0.8, 0.35)
const GOLD_DEEP := Color(0.85, 0.6, 0.16)
const GOLD_LIGHT := Color(0.98, 0.83, 0.4)
const INK := Color(0.05, 0.06, 0.1)
const PAPER := Color(0.96, 0.94, 0.88)

var game = null

var _root: Control
var _ping_label: Label
var _ping_icon: GlassIcon
var _ping_icon_shadow: GlassIcon
var _mail_badge: Dictionary = {}
var _chat_badge: Dictionary = {} # DM unread badge (on the chat ticker since 2026-11-12)
var _ticker_name: Label
var _ticker_text: RichTextLabel
var _ticker_channel := "world"
var _banner_idx: int = 0
var _banner_title: Label
var _banner_sub: Label
var _banner_art: TextureRect
var _dots: Array = []
var _tick: Timer
var _banner_clock: float = 0.0

# Match-entry cluster (13i).
var _cluster_rank: ClusterRank
var _chip_av: AvatarFrame # profile chip portrait (13l addendum 3; 17d frame helper)
var _chip: Control # top-left cluster: avatar + name/Lv lines
var _chip_name: Label
var _chip_lv: Label
var _chip_text_bg: Panel
var _chip_box: VBoxContainer
var _mode_dim: ColorRect
var _mode_panel: Control

# Painted button art supplied by Tín (sliced by
# gen/nav_buttons_build.py + gen/start_button_build.py).
const NAV_TEX_PROFILE := preload("res://assets/nav_buttons/nav_profile.png")
const NAV_TEX_HISTORY := preload("res://assets/nav_buttons/nav_history.png")
const NAV_TEX_LEADERBOARD := preload("res://assets/nav_buttons/nav_leaderboard.png")
const NAV_TEX_FRIENDS := preload("res://assets/nav_buttons/nav_friends.png")
const START_TEX := preload("res://assets/nav_buttons/start_button.png")
const MODE_FRAME_TEX := preload("res://assets/nav_buttons/mode_frame.png")
# Bottom row footprint (13i follow-ups): the row keeps the
# v6 band's 131px height and its 14px side / 8px top-bottom
# margins so every element keeps its v6 baseline — only the
# band's dark background is gone (the row is a transparent
# Control now, the buttons sit on the art).
const BAND_H := 131.0
const NAV_BTN_H := 104.0
const START_BTN_H := 90.0
# Mode-choice badges (Tín's painted emblems, gen/mode_badges_build.py).
const MODE_TEX_NORMAL := preload("res://assets/nav_buttons/mode_normal.png")
const MODE_TEX_RANKED := preload("res://assets/nav_buttons/mode_ranked.png")
const MODE_TEX_CUSTOM := preload("res://assets/nav_buttons/mode_custom.png")
const MODE_TEX_MINIGAME := preload("res://assets/nav_buttons/mode_minigame.png")
# All four mode entries are painted badges of one height; the panel
# widened (680 -> 800) so two badge rows fit the glass. Tín later
# ordered the caption lines under the badges removed ("Bỏ mấy dòng
# ghi chú đi") — the badges carry their names on their ribbons, so
# the panel now holds just the 2x2 badge grid under the title.
const MODE_BADGE_H := 126.0

var _popup: PanelContainer
var _popup_title: Label
var _popup_body: VBoxContainer
var _popup_kind: String = ""
var _popup_status: Label
var _mail_mark_sent: bool = false

# History panel (full-screen, reference-styled).
var _hist_root: Control
var _hist_rows_box: VBoxContainer
var _hist_pages_box: HBoxContainer
var _hist_filter: int = 0 # 0 all, 1 ranked, 2 custom
var _hist_page: int = 0
var _hist_detail: PanelContainer
var _hist_detail_body: VBoxContainer

# Right rail (13m + follow-ups): a SHORT compact group on
# the home's right edge — glyph chips row, close-friend
# portraits, and a "<" arrow chip at the column's bottom
# (the old "+" chip's slot; the separate mid-height
# floating arrow was removed on Tín's word) — hugging its
# content in the upper-right (the banner moved left).
var _rail_box: VBoxContainer
var _rail_bg: PanelContainer
var _rail_close_box: VBoxContainer
var _rail_arrow: Control

# Friends panel (13m redesign, full-screen like Lịch Sử):
# left menu Bạn bè / Bạn thân / Tìm bạn, framed-avatar rows
# with Lv badge, Online / last-seen status, heart (bạn thân)
# and trash glyph actions.
var _fr_root: Control
var _fr_tab: String = "all" # all | close | find
var _fr_list: VBoxContainer
var _fr_scroll: ScrollContainer
var _fr_find_box: VBoxContainer
var _fr_find_edit: LineEdit
var _fr_status: Label
var _fr_search_edit: LineEdit
var _fr_menu: Dictionary = {} # tab -> Button
var _fr_content: HBoxContainer
var _fr_guest_box: VBoxContainer
var _fr_confirm: Control
var _fr_confirm_text: Label
var _fr_pending_remove: String = ""
var _fr_last_add: String = ""

const HIST_BIOMES := {"grassland": "Đồng cỏ", "desert": "Sa mạc", "snow": "Tuyết"}
const HIST_LAYOUTS := {"plains": "Đồng bằng", "hills": "Đồi núi", "lakes": "Sông hồ",
		"coast": "Ven biển", "valley": "Thung lũng", "random": "Ngẫu nhiên"}
const HIST_TEAM_COLORS := [Color(0.85, 0.25, 0.2), Color(0.25, 0.45, 0.95),
		Color(0.3, 0.75, 0.3), Color(0.95, 0.8, 0.2)]


class LaurelBranch:
	extends Control
	var flip: bool = false
	var col: Color = Color(0.98, 0.8, 0.35)

	# One laurel branch hugging the side of the control: leaves
	# sweep from top, around the side, to the bottom (mirrored
	# when flip). Two branches together read as a wreath.
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.44
		var a0 := -1.85 if not flip else PI - 1.25
		var a1 := 1.25 if not flip else PI + 1.85
		draw_arc(c, r, a0, a1, 18, Color(col, 0.55), 1.4)
		for i in range(7):
			var t := float(i) / 6.0
			var a := lerpf(a0, a1, t)
			var p := c + Vector2(cos(a), sin(a)) * r
			draw_circle(p, 2.8 + sin(t * PI) * 1.7, col)


class MapChip:
	extends Control
	var biome: String = "grassland"

	func _draw() -> void:
		var top := Color(0.45, 0.72, 0.3)
		var left := Color(0.32, 0.55, 0.2)
		var right := Color(0.38, 0.63, 0.25)
		match biome:
			"desert":
				top = Color(0.9, 0.76, 0.45)
				left = Color(0.72, 0.58, 0.32)
				right = Color(0.8, 0.66, 0.38)
			"snow":
				top = Color(0.92, 0.95, 0.99)
				left = Color(0.7, 0.78, 0.88)
				right = Color(0.8, 0.86, 0.94)
		var cx := size.x * 0.5
		var cy := size.y * 0.42
		var w := size.x * 0.46
		var h := size.y * 0.3
		var d := size.y * 0.16
		draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - h),
				Vector2(cx + w, cy), Vector2(cx, cy + h), Vector2(cx - w, cy)]), top)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - w, cy),
				Vector2(cx, cy + h), Vector2(cx, cy + h + d), Vector2(cx - w, cy + d)]), left)
		draw_colored_polygon(PackedVector2Array([Vector2(cx + w, cy),
				Vector2(cx, cy + h), Vector2(cx, cy + h + d), Vector2(cx + w, cy + d)]), right)
		# A river squiggle + two tree dots for life.
		draw_polyline(PackedVector2Array([Vector2(cx - w * 0.5, cy + h * 0.2),
				Vector2(cx - w * 0.1, cy - h * 0.15), Vector2(cx + w * 0.3, cy + h * 0.25),
				Vector2(cx + w * 0.62, cy - h * 0.1)]), Color(0.3, 0.55, 0.9), 2.2)
		draw_circle(Vector2(cx - w * 0.35, cy - h * 0.3), 2.6, left.darkened(0.25))
		draw_circle(Vector2(cx + w * 0.45, cy + h * 0.42), 2.6, left.darkened(0.25))


## The rank display over the START button (13i), arranged
## the way Tín's crop shows it: the tier EMBLEM stands at
## the left, as tall as the two text rows beside it put
## together (Tín: "cho icon rank bự ra bằng 2 hàng đó
## luôn"); the right column carries the rank NAME on top
## and, BELOW it, a row of DIAMOND pips (rotated squares —
## filled gold = earned, empty = dark with a gold rim;
## total = the division's star cap).
## The whole group sits on a dark glass pill so name and
## pips stay legible over the art (the v4 legibility fix,
## kept). Công Tước / Hoàng Đế carry unbounded stars: the
## pip row is hidden and the name line itself reads
## "Công Tước · N sao". Guests get a grey emblem +
## "Chưa xếp hạng" + an all-empty pip row. The control
## sizes itself to its content via custom_minimum_size so
## the pill hugs the group.
class ClusterRank:
	extends Control
	const PAD_X := 10.0
	const PAD_T := 6.0
	const PAD_B := 6.0
	const ROW_H := 34.0 # name row height in the right column
	const GAP_ROW := 4.0 # between the name row and the pips
	const PIP_R := 7.5 # diamond half-size
	const PIP_STEP := 24.0
	const PIP_ROW_H := 17.0
	# The right column's full height (name + gap + pips);
	# the emblem is drawn exactly this tall so it spans both
	# rows. The pill keeps this height in every variant —
	# with no pips the name simply centres in the column.
	const COL_H := ROW_H + GAP_ROW + PIP_ROW_H
	var tier: int = 0
	var stars: int = 0
	var star_cap: int = 3
	var emperor: bool = false
	var guest: bool = true
	var _name_label: Label
	var _backing: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(260, _content_height())
		# Glass backing (navy, radius 14, gold hairline).
		_backing = StyleBoxFlat.new()
		_backing.bg_color = Color(0.03, 0.04, 0.08, 0.66)
		_backing.set_corner_radius_all(14)
		_backing.border_color = Color(1, 0.85, 0.4, 0.35)
		_backing.set_border_width_all(1)
		_name_label = Label.new()
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_label.position = Vector2(_name_x(), PAD_T)
		_name_label.size = Vector2(420, ROW_H)
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name_label.add_theme_font_size_override("font_size", 19)
		_name_label.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
		_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_name_label.add_theme_constant_override("shadow_offset_x", 2)
		_name_label.add_theme_constant_override("shadow_offset_y", 2)
		add_child(_name_label)

	# The name starts right of the emblem (emblem at PAD_X,
	# COL_H tall, its width from rank_badge.gd's aspect).
	func _name_x() -> float:
		return PAD_X + COL_H * RankBadge.EMBLEM_ASPECT + 8.0

	func _name_width() -> float:
		var font := _name_label.get_theme_font("font")
		return font.get_string_size(_name_label.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19).x

	# The pip row runs under the NAME (as in Tín's crop), its
	# first pip centred on the name's first letter.
	func _pips_x() -> float:
		return _name_x() + PIP_R

	func _pips_y() -> float:
		return PAD_T + ROW_H + GAP_ROW + PIP_ROW_H * 0.5

	func _content_width() -> float:
		var w := _name_x() + _name_width() + PAD_X
		if star_cap > 0:
			w = maxf(w, _pips_x() + float(star_cap - 1) * PIP_STEP
					+ PIP_R + PAD_X)
		return w

	func _content_height() -> float:
		# The emblem spans the full two-row column in every
		# variant, so the pill's height never changes.
		return PAD_T + COL_H + PAD_B

	func set_state(p_tier: int, p_stars: int, p_cap: int, p_emperor: bool,
			p_guest: bool, p_name: String) -> void:
		tier = p_tier
		stars = p_stars
		star_cap = p_cap
		emperor = p_emperor
		guest = p_guest
		_name_label.text = p_name
		# With pips the name sits in the column's top row;
		# without them it centres against the full-height
		# emblem.
		_name_label.position = Vector2(_name_x(), PAD_T
				+ (0.0 if star_cap > 0 else (COL_H - ROW_H) * 0.5))
		custom_minimum_size = Vector2(_content_width(), _content_height())
		queue_redraw()

	# A diamond pip: a square rotated 45 degrees.
	func _pip_points(c: Vector2, r: float) -> PackedVector2Array:
		return PackedVector2Array([c + Vector2(0, -r),
				c + Vector2(r, 0), c + Vector2(0, r),
				c + Vector2(-r, 0)])

	func _draw() -> void:
		# Backing pill behind the whole group, hugging the
		# content (long names like "Công Tước · N sao" widen
		# it via custom_minimum_size).
		draw_style_box(_backing,
				Rect2(0, 0, maxf(size.x, _content_width()), size.y))
		# The tier emblem itself: rank_badge.gd's painted texture
		# (Tín's emblem sheet), aspect preserved, greyed for
		# guests. This replaced the procedurally drawn shield
		# when the emblem pass landed.
		var tex := RankBadge.emblem_texture(tier, emperor)
		var eh := COL_H
		var ew := eh * RankBadge.EMBLEM_ASPECT
		var tint := Color(0.5, 0.52, 0.58, 0.9) if guest else Color.WHITE
		draw_texture_rect(tex,
				Rect2(Vector2(PAD_X, PAD_T), Vector2(ew, eh)),
				false, tint)
		# The division's diamond pips under the name: every pip
		# drop-shadowed and rimmed so filled gold and empty
		# dark both stay crisp.
		if star_cap > 0:
			for i in range(star_cap):
				var sc := Vector2(_pips_x() + float(i) * PIP_STEP, _pips_y())
				var sp := _pip_points(sc, PIP_R)
				draw_colored_polygon(
						_pip_points(sc + Vector2(1.5, 2), PIP_R),
						Color(0, 0, 0, 0.4))
				var sloop := PackedVector2Array(sp)
				sloop.append(sp[0])
				if (not guest) and i < stars:
					draw_colored_polygon(sp, Color(1, 0.82, 0.3))
					draw_polyline(sloop, Color(0.45, 0.3, 0.05, 0.9), 1.3)
				else:
					draw_colored_polygon(sp, Color(0.06, 0.06, 0.1, 0.85))
					draw_polyline(sloop, Color(0.95, 0.75, 0.35, 0.9), 1.4)


class AvatarRing:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_arc(c, r, 0, TAU, 40, Color(0.25, 0.16, 0.05), 7.0)
		draw_arc(c, r, 0, TAU, 40, Color(0.99, 0.82, 0.38), 3.5)


func setup(p_game) -> void:
	game = p_game
	layer = 40
	_build()
	visible = false
	Net.auth_ok.connect(func(_t, _p) -> void: refresh())
	# 17d: cosmetics equips / renames refresh the chip + rows.
	Net.profile_updated.connect(func(_p) -> void: refresh())
	Net.avatar_changed.connect(func(_a) -> void: refresh())
	Net.display_name_changed.connect(func(_n) -> void: refresh())
	Net.auth_out.connect(func() -> void: refresh())
	Net.rank_result_received.connect(func(_info: Dictionary) -> void: refresh())
	Net.mail_received.connect(func(_rows, unread) -> void:
		_set_mail_badge(unread)
		if _popup_kind == "mail":
			_refill_popup()
			if unread > 0 and not _mail_mark_sent:
				_mail_mark_sent = true
				Net.mark_mail_read(0))
	# 17e: the Chat button's badge tracks unread DMs live.
	Net.dm_list_received.connect(func(_rows) -> void:
		_set_chat_badge(Net.dm_total_unread()))
	Net.dm_line_received.connect(func(_p, mine) -> void:
		if not mine:
			_set_chat_badge(Net.dm_total_unread()))
	Net.dm_thread_received.connect(func(_p, _rows) -> void:
		_set_chat_badge(Net.dm_total_unread()))
	# Chat ticker (owner, 2026-11-12): the latest world /
	# alliance / DM line shows on the ticker bar.
	Net.chat_received.connect(func(scope: String, _slot: int, sender: String, text: String, _tag: String, _bub: String) -> void:
		if scope == "world" or scope == "alliance":
			_ticker_show(scope, sender, text))
	Net.dm_line_received.connect(func(peer: String, mine: bool) -> void:
		if not mine:
			var lines: Array = Net.dm_threads.get(peer, [])
			if not lines.is_empty():
				var l: Dictionary = lines[lines.size() - 1]
				_ticker_show("dm", String(l.get("name", peer)),
						String(l.get("text", ""))))
	Net.friends_received.connect(func(_rows) -> void:
		_rebuild_rail()
		if _fr_root != null and _fr_root.visible:
			_refill_friends_panel()
		elif _popup_kind == "friends":
			_refill_popup())
	Net.friend_error.connect(func(msg) -> void:
		if _fr_root != null and _fr_root.visible and _fr_status != null:
			_fr_status.text = msg
		elif _popup_kind == "friends" and _popup_status != null:
			_popup_status.text = msg)
	Net.history_received.connect(func(_rows) -> void:
		if _hist_root != null and _hist_root.visible:
			_rebuild_history())
	Net.connection_closed.connect(func() -> void: refresh())
	Net.replay_received.connect(func(rp: Dictionary) -> void:
		_on_replay_data(rp))
	Net.replay_failed.connect(func(msg: String) -> void:
		_replay_msg("Không xem được", msg, {}))


func _font() -> Font:
	return ThemeDB.fallback_font


## 13r flow-check hook: the name the home chip currently shows.
func chip_name_text() -> String:
	return _chip_name.text if _chip_name != null else ""


func _sb(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _label(text: String, size: int, color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Full-bleed painted panorama.
	var bg := TextureRect.new()
	bg.texture = load("res://assets/home_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_build_chip()
	_build_top_right()
	_build_banner()
	_build_bracket_button()
	_build_chat_ticker()
	_build_rail()
	_build_bottom_band()
	_build_popup()
	_build_history_panel()
	_build_friends_panel()

	_tick = Timer.new()
	_tick.wait_time = 0.5
	_tick.autostart = true
	_tick.timeout.connect(_on_tick)
	add_child(_tick)


func _build_chip() -> void:
	# The top-left corner used to be avatar + full profile
	# card; Tín cut it to the portrait alone (13i) in a
	# SQUARE gold frame ("cho khung hình vuông", matching
	# the supplied character portraits' framed style). His
	# latest order adds back exactly TWO text lines beside
	# the portrait — account name on top, "Lv.N" below —
	# nothing else: no card, no bar (the rank line and
	# everything else still live in the profile screen this
	# cluster opens, 13l). The portrait comes from the
	# character resolver (13l addendum 3): the account's
	# chosen avatar_id — Ngân Kỵ by default — never the
	# retired king crop; refresh() re-applies the portrait
	# and both lines when the account/avatar moves.
	var chip := Control.new()
	chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chip.position = Vector2(10, 10)
	chip.custom_minimum_size = Vector2(76, 76)
	chip.size = Vector2(76, 76)
	_root.add_child(chip)
	_chip = chip

	var frame := PanelContainer.new()
	frame.position = Vector2.ZERO
	frame.custom_minimum_size = Vector2(76, 76)
	frame.size = Vector2(76, 76)
	frame.add_theme_stylebox_override("panel",
			_sb(Color(0.10, 0.08, 0.05), 4, GOLD, 3))
	chip.add_child(frame)
	# 17d: the chip portrait is composed by the shared
	# AvatarFrame helper (account avatar + equipped frame).
	var av := AvatarFrame.new()
	av.custom_minimum_size = Vector2(68, 68)
	av.size = Vector2(68, 68)
	av.position = Vector2(4, 4)
	av.set_content(Avatars.texture_for(Avatars.local_avatar()),
			String(Net.auth_profile.get("frame_id", "")), true)
	chip.add_child(av)
	_chip_av = av

	# The two lines (name / level) right of the portrait.
	# Legibility over the bright panorama is mandatory:
	# strong outline + soft shadow on the glyphs AND a
	# subtle dark backing behind the text block ONLY —
	# deliberately not a card: no border, nothing around
	# the avatar itself. Geometry is fitted in
	# _layout_chip() once the texts are known.
	_chip_text_bg = Panel.new()
	_chip_text_bg.add_theme_stylebox_override("panel",
			_sb(Color(0.02, 0.03, 0.07, 0.45), 10))
	_chip_text_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(_chip_text_bg)
	_chip_box = VBoxContainer.new()
	_chip_box.add_theme_constant_override("separation", 1)
	_chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(_chip_box)
	_chip_name = _chip_line("Khách", 20, Color.WHITE)
	_chip_box.add_child(_chip_name)
	_chip_lv = _chip_line("Chưa đăng nhập", 15, GOLD_LIGHT)
	_chip_box.add_child(_chip_lv)
	_layout_chip()

	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.tooltip_text = "Hồ sơ"
	tap.pressed.connect(func() -> void: if game != null: game.home_open_profile())
	chip.add_child(tap)


## One line of the chip's name/Lv pair: bright text with a
## dark outline and a soft drop shadow, so it stays crisp
## over the painted sky/foliage behind the corner.
func _chip_line(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Fit the text block (and the cluster's tap area) to the
## current name/level strings: block vertically centred on
## the 76px portrait, backing hugging the two lines only.
func _layout_chip() -> void:
	if _chip_name == null or _chip_box == null:
		return
	var bw := maxf(_chip_name.get_combined_minimum_size().x,
			_chip_lv.get_combined_minimum_size().x)
	var bh := _chip_name.get_combined_minimum_size().y + 1.0 \
			+ _chip_lv.get_combined_minimum_size().y
	_chip_box.position = Vector2(86, (76.0 - bh) * 0.5)
	_chip_box.size = Vector2(bw, bh)
	_chip_text_bg.position = _chip_box.position - Vector2(9, 6)
	_chip_text_bg.size = Vector2(bw + 18, bh + 12)
	_chip.size = Vector2(86 + bw + 20, 76)


## One circular glass icon button; returns {btn, badge_setter}.
## With bare=true the glass disc is GONE (Tín's "icon css"
## order): the flat glyph floats on its own, kept readable
## by a dark silhouette of itself offset behind it as a
## soft drop shadow. The holder (and its tap target) keeps
## the full sz footprint either way.
## A hand-drawn disc for the round icon buttons. The old
## StyleBoxFlat disc (corner radius = half the size) left
## a visible vertical seam through the middle of every
## chip (owner catch 2026-11-12: "sao có dấu | trong
## nút"); a plain draw_circle + draw_arc has no seam.
class _Disc:
	extends Control
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r - 0.5, Color(0.03, 0.04, 0.08, 0.6))
		draw_arc(c, r - 1.0, 0, TAU, 48, Color(1, 0.85, 0.4, 0.4), 1.0, true)


func _icon_button(icon_kind: String, tip: String, sz := 48.0, bare := false) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(sz, sz)
	if not bare:
		var disc := _Disc.new()
		disc.set_anchors_preset(Control.PRESET_FULL_RECT)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(disc)
	var isz := sz * 0.5625
	var ipos := Vector2((sz - isz) * 0.5, (sz - isz) * 0.5)
	if bare:
		var sh := GlassIcon.new()
		sh.kind = icon_kind
		sh.custom_minimum_size = Vector2(isz, isz)
		sh.size = Vector2(isz, isz)
		sh.position = ipos + Vector2(1.5, 2)
		sh.modulate = Color(0, 0, 0, 0.4)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(sh)
	var ic := GlassIcon.new()
	ic.kind = icon_kind
	ic.custom_minimum_size = Vector2(isz, isz)
	ic.size = Vector2(isz, isz)
	ic.position = ipos
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = tip
	holder.add_child(btn)
	# Unread badge (hidden until set > 0).
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", _sb(Color(0.85, 0.2, 0.15), 9))
	bp.custom_minimum_size = Vector2(19, 19)
	bp.size = Vector2(19, 19)
	# Framed: on the disc's rim. Bare: on the glyph's own
	# top-right corner (the badge is not a frame — it
	# stays in both variants).
	bp.position = Vector2((sz + isz) * 0.5 - 9, (sz - isz) * 0.5 - 9) \
			if bare else Vector2(sz - 17.0, -3)
	bp.visible = false
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := _label("", 11, Color.WHITE)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_child(bl)
	holder.add_child(bp)
	return {"holder": holder, "btn": btn, "badge": bp, "badge_label": bl}


func _set_badge(d: Dictionary, n: int) -> void:
	var bp: PanelContainer = d.get("badge")
	var bl: Label = d.get("badge_label")
	if bp == null:
		return
	bp.visible = n > 0
	bl.text = str(mini(n, 99))


func _set_mail_badge(n: int) -> void:
	_set_badge(_mail_badge, n)


func _set_chat_badge(n: int) -> void:
	if not _chat_badge.is_empty():
		_set_badge(_chat_badge, n)


func _build_chat_ticker() -> void:
	# Owner order 2026-11-12 (his reference crop): chat is
	# NOT opened from an icon — this slim bar in the
	# bottom-left corner shows the LATEST chat message, one at a
	# time; tapping the bar opens the chat panel at that
	# message's channel.
	var bar := PanelContainer.new()
	# Owner order 2026-11-12: the ticker moves to the
	# BOTTOM-LEFT corner of the lobby.
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# Owner: raise the bar so its centre is level with the
	# BẮT ĐẦU button's centre (band top + 8 + 45 from the
	# bottom edge = 78; bar is 38 tall → top at −97).
	bar.position = Vector2(10, -97)
	bar.custom_minimum_size = Vector2(436, 38)
	bar.size = Vector2(436, 38)
	var bsb := _sb(Color(0.02, 0.03, 0.07, 0.88), 8, Color(1, 0.85, 0.4, 0.55), 1)
	bsb.content_margin_left = 10
	bsb.content_margin_right = 10
	bsb.content_margin_top = 4
	bsb.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", bsb)
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	var ic := GlassIcon.new()
	ic.kind = "chat"
	ic.custom_minimum_size = Vector2(22, 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	_ticker_name = _label("Chat", 13, Color(1, 0.85, 0.4))
	_ticker_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ticker_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_ticker_name)
	var clip := Control.new()
	clip.clip_contents = true
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(clip)
	_ticker_text = Emotes.make_rich("", 15, PAPER)
	_ticker_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ticker_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clip.add_child(_ticker_text)
	# Unread-DM badge riding the bar's top-right corner
	# (same dict shape _set_badge consumes).
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", _sb(Color(0.85, 0.2, 0.15), 9))
	bp.custom_minimum_size = Vector2(19, 19)
	bp.size = Vector2(19, 19)
	bp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bp.position = Vector2(10 + 436 - 9, -97 - 10)
	bp.visible = false
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := _label("", 11, Color.WHITE)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_child(bl)
	_root.add_child(bp)
	_chat_badge = {"badge": bp, "badge_label": bl}
	_set_chat_badge(Net.dm_total_unread())
	# Tap overlay (added last → on top of the row).
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.tooltip_text = "Chat"
	bar.add_child(tap)
	tap.pressed.connect(func() -> void:
		if game != null and game.has_method("home_open_chat_hub"):
			game.home_open_chat_hub(_ticker_channel))


func _ticker_show(channel: String, sender: String, text: String) -> void:
	if _ticker_name == null:
		return
	_ticker_channel = channel
	var nm := sender
	if nm.length() > 16:
		nm = nm.left(16) + "…"
	_ticker_name.text = nm + ":"
	var clip := _ticker_text.get_parent()
	_ticker_text.queue_free()
	_ticker_text = Emotes.make_rich(text, 15, PAPER)
	_ticker_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ticker_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clip.add_child(_ticker_text)


func _build_top_right() -> void:
	# Tín (13l addendum): the friends icon left this row —
	# Thư · Cài đặt · Ping remain. (The friends panel itself
	# stays in code, dormant like the other removed entries.)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Owner order 2026-11-12: NO chat icon button here any
	# more — chat lives in the ticker bar under the season
	# banner (latest message shows there; tap opens the hub).
	row.position = Vector2(-244, 12)
	row.custom_minimum_size = Vector2(232, 48)
	row.add_theme_constant_override("separation", 10)
	_root.add_child(row)

	# Tín's frameless order ("thay thành icon css và bỏ
	# khung"): mail + gear are BARE glyphs now — no glass
	# disc, just the flat icon and its shadow silhouette.
	# The unread badge still rides the envelope glyph.
	_mail_badge = _icon_button("mail", "Thư", 48.0, true)
	_mail_badge["btn"].pressed.connect(func() -> void: _open_popup("mail"))
	row.add_child(_mail_badge["holder"])
	var gear := _icon_button("gear", "Cài đặt", 48.0, true)
	gear["btn"].pressed.connect(func() -> void: _open_popup("settings"))
	row.add_child(gear["holder"])

	# Ping readout: the pill is gone too (same order). What
	# remains, bare over the art: the WiFi glyph + the live
	# ms text (or "—" offline), both shadowed to stay
	# readable. Tín's correction (from his reference crop,
	# pixel-checked): there is NO separate status dot above
	# the arcs — the dot is the fan's BASE point, part of
	# the glyph below the arcs, and the glyph itself is the
	# meter: bad (> 200 ms / no pong / offline) = red base
	# dot + grey arcs; medium (100–200 ms) = yellow base
	# dot + grey arcs; good (< 100 ms) = the ENTIRE glyph
	# green, dot and arcs ("xanh là toàn bộ xanh"). Band is
	# set in _on_tick via GlassIcon.signal_band.
	var ph := HBoxContainer.new()
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	ph.custom_minimum_size = Vector2(96, 48)
	ph.add_theme_constant_override("separation", 5)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sic_holder := Control.new()
	sic_holder.custom_minimum_size = Vector2(24, 24)
	# Tín: "Ping cân bằng cái số của nó đang bị chênh" —
	# the glyph holder must NOT fill the 48px row (the
	# glyph then rides at the row's top while the number
	# sits on the centre line). Shrink-centre BOTH parts
	# so the glyph and the ms text share the row's one
	# optical line, level with the mail/gear glyphs.
	sic_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sic_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sic_sh := GlassIcon.new()
	sic_sh.kind = "signal_meter"
	sic_sh.custom_minimum_size = Vector2(24, 24)
	sic_sh.size = Vector2(24, 24)
	sic_sh.position = Vector2(1.5, 2)
	sic_sh.modulate = Color(0, 0, 0, 0.4)
	sic_sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sic_holder.add_child(sic_sh)
	_ping_icon_shadow = sic_sh
	var sic := GlassIcon.new()
	sic.kind = "signal_meter"
	sic.custom_minimum_size = Vector2(24, 24)
	sic.size = Vector2(24, 24)
	sic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sic_holder.add_child(sic)
	_ping_icon = sic
	ph.add_child(sic_holder)
	_ping_label = _label("—", 16, Color(0.85, 0.88, 0.95))
	_ping_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ping_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_ping_label.add_theme_constant_override("outline_size", 5)
	_ping_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_ping_label.add_theme_constant_override("shadow_offset_x", 1)
	_ping_label.add_theme_constant_override("shadow_offset_y", 2)
	ph.add_child(_ping_label)
	row.add_child(ph)


func _season_num() -> int:
	var rank: Dictionary = Net.auth_profile.get("rank", {})
	var s := int(rank.get("season", 0))
	return s if s > 0 else 1


func _build_banner() -> void:
	# 13m: the season carousel moved to the LEFT side, under
	# the avatar — the right edge now belongs to the rail
	# (Bạn bè / BXH chips + close-friend portraits). Same
	# card, same slides, same dots, same behaviour.
	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(10, 100)
	card.custom_minimum_size = Vector2(436, 116)
	card.size = Vector2(436, 116)
	card.add_theme_stylebox_override("panel",
			_sb(Color(0.02, 0.03, 0.07, 0.88), 8, Color(1, 0.85, 0.4, 0.55), 1))
	_root.add_child(card)
	_banner_art = TextureRect.new()
	_banner_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_banner_art.anchor_left = 1.0
	_banner_art.anchor_right = 1.0
	_banner_art.anchor_top = 0.0
	_banner_art.anchor_bottom = 1.0
	_banner_art.offset_left = -158
	_banner_art.offset_right = -4
	_banner_art.offset_top = 4
	_banner_art.offset_bottom = -4
	_banner_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_banner_art)
	_banner_title = _label("", 21, Color(1, 0.85, 0.4))
	_banner_title.position = Vector2(16, 14)
	card.add_child(_banner_title)
	_banner_sub = _label("", 17, Color.WHITE)
	_banner_sub.position = Vector2(16, 48)
	card.add_child(_banner_sub)
	var hint := _label("Chạm để vào", 13, Color(1, 1, 1, 0.6))
	hint.position = Vector2(16, 82)
	card.add_child(hint)
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(_on_banner_tap)
	card.add_child(tap)
	# Carousel dots under the card (tappable).
	for i in range(2):
		var d := Button.new()
		d.custom_minimum_size = Vector2(15, 15)
		d.set_anchors_preset(Control.PRESET_TOP_LEFT)
		d.position = Vector2(10 + 196 + i * 24, 224)
		d.pressed.connect(func() -> void: _show_banner(i))
		_root.add_child(d)
		_dots.append(d)
	_show_banner(0)


## Owner order 2026-11-12: the Đại chiến bracket board
## gets a prominent HORIZONTAL button directly under the
## season banner (this replaces the earlier spec idea of a
## carousel slide as the board's lobby entry). Gold, full
## banner width; opens the war board screen.
func _build_bracket_button() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bar.position = Vector2(10, 248)
	bar.custom_minimum_size = Vector2(436, 42)
	bar.size = Vector2(436, 42)
	var bsb := _sb(Color(0.93, 0.72, 0.22), 9, Color(1, 0.88, 0.5, 0.9), 1)
	bsb.content_margin_left = 14
	bsb.content_margin_right = 14
	bsb.content_margin_top = 0
	bsb.content_margin_bottom = 2
	bar.add_theme_stylebox_override("panel", bsb)
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	var ic := GlassIcon.new()
	ic.kind = "trophy"
	ic.custom_minimum_size = Vector2(24, 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate = Color(0.16, 0.11, 0.03)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var t := _label("XEM BẢNG ĐẤU", 16, Color(0.16, 0.11, 0.03))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var sub := _label("Đại chiến liên minh", 12, Color(0.16, 0.11, 0.03, 0.75))
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sub)
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.tooltip_text = "Bảng đấu Đại chiến liên minh"
	bar.add_child(tap)
	tap.pressed.connect(func() -> void:
		if game != null and game.has_method("home_open_war_board"):
			game.home_open_war_board())


func _show_banner(i: int) -> void:
	_banner_idx = i
	_banner_clock = 0.0
	if i == 0:
		_banner_title.text = "MÙA GIẢI MỚI"
		_banner_sub.text = "Đấu Hạng · Mùa %d" % _season_num()
		_banner_art.texture = load("res://assets/home_banner_soldiers.png")
	else:
		_banner_title.text = "PHÒNG THƯỜNG"
		_banner_sub.text = "Lập phòng đấu cùng bạn"
		_banner_art.texture = load("res://assets/home_banner_rooms.png")
	for j in range(_dots.size()):
		var d: Button = _dots[j]
		var col := Color(0.98, 0.8, 0.35) if j == i else Color(1, 1, 1, 0.4)
		d.add_theme_stylebox_override("normal", _sb(col, 8))
		d.add_theme_stylebox_override("hover", _sb(col, 8))
		d.add_theme_stylebox_override("pressed", _sb(col, 8))


func _on_banner_tap() -> void:
	if game == null:
		return
	if _banner_idx == 0:
		game.home_open_ranked()
	else:
		game.home_open_rooms()


## The right-edge RAIL (13m, per Tín's reference; follow-up
## 2 restyle): a SHORT, COMPACT group hanging in the
## upper-right where the season banner used to be — it hugs
## its content and ends well above the rank pill / BẮT ĐẦU
## (Tín: "chỉ hiện 1 đoạn thôi chứ sao kéo hẳn xuống chạm
## nút bắt đầu rồi" — the v1 full-height strip and the "+"
## pinned at the screen bottom were both wrong). Contents,
## top to bottom: a row of two flat GLYPH icon chips — Bạn
## bè (people) and BXH (chart), drawn glyphs on dark glass
## like the rest of the home chrome (Tín: "icon css", not
## painted art); the CLOSE-FRIENDS mini list ("bạn thân"
## portraits in square gold frames, online first, max 4 —
## the stack simply runs down the column); and one chip
## at the column's bottom. Follow-up 3 (Tín: "cái mũi tên
## phải đưa kế bên ô đó và là mũi tên trái rồi chỗ đó là
## avatar mà"): the old in-column ">" chevron was removed —
## its slot belongs to the portrait stack — and a
## LEFT-pointing "<" arrow chip sat BESIDE the column,
## attached to its left edge at mid-height, outside the
## backing; tapping it opens the friends panel. LATEST
## (Tín: "bỏ dấu cộng đưa dấu mũi tên vào đó đi"): the
## bottom chip was a "+" (find-friend) — it is GONE, and
## the "<" arrow moved INTO that bottom slot; the floating
## beside-column arrow is removed, leaving exactly one
## arrow, in the column, opening the friends panel.
## Later in
## follow-up 3 the follow-up 2 FEATURED CARD (the player's
## own character under the chips) was REMOVED again on
## Tín's word ("Cái lam bào kia là gì vậy xoá đi chỗ bạn
## bè ấy") — the column is friends-only again.
## The translucent backing wraps ONLY this group (5px pad).
## Follow-up 5 (Tín: "Cột đó chiều ngang vẫn bự"): the
## column is SLIM — it hugs ONE portrait: RAIL_W fits a
## 56px portrait with 1px to spare, the two top chips
## shrink to 27px each (27+4+27 = RAIL_W), the bottom
## arrow chip matches them, and the backing totals RAIL_W + 10 = 68px.
## Guests see the chips and an empty friends segment;
## every friends tap routes them to the account flow
## instead.
const RAIL_W := 58.0

func _build_rail() -> void:
	_rail_bg = PanelContainer.new()
	_rail_bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rail_bg.position = Vector2(-(RAIL_W + 10.0), 76)
	_rail_bg.add_theme_stylebox_override("panel",
			_sb(Color(0.02, 0.03, 0.07, 0.5), 12, Color(1, 0.85, 0.4, 0.3), 1))
	_rail_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rail_bg)

	var rail := VBoxContainer.new()
	rail.name = "RightRail"
	rail.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rail.position = Vector2(-(RAIL_W + 5.0), 81)
	rail.custom_minimum_size = Vector2(RAIL_W, 0)
	rail.alignment = BoxContainer.ALIGNMENT_BEGIN
	rail.add_theme_constant_override("separation", 6)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rail)
	_rail_box = rail

	# Owner order 2026-11-12 (his reference rail): the top
	# pair carries NO round frames and sits OUTSIDE the
	# vertical strip, above it — bare glyphs on the sky.
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Straddling the strip's top edge (strip starts at 76):
	# clear of the ping row above, visibly OUTSIDE the
	# frame's enclosed area.
	top.position = Vector2(-(RAIL_W + 5.0), 58)
	top.custom_minimum_size = Vector2(RAIL_W, 0)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	var friends_btn := _icon_button("friends", "Bạn bè", 30.0, true)
	friends_btn["btn"].pressed.connect(func() -> void: _rail_open_friends("all"))
	top.add_child(friends_btn["holder"])
	var chart_btn := _icon_button("chart", "Bảng xếp hạng", 30.0, true)
	chart_btn["btn"].pressed.connect(func() -> void:
		if game != null:
			game.home_open_leaderboard())
	top.add_child(chart_btn["holder"])
	# 15h: tournament entry — the trophy chip sits on its own
	# row under the BXH / Bạn bè pair (the pair exactly fills
	# the 58px rail; the mode panel is full, and the rail is
	# where the other meta screens live). Guests route to the
	# account flow like the friends chip does.
	var trophy_btn := _icon_button("trophy", "Giải đấu", 27.0)
	trophy_btn["btn"].pressed.connect(func() -> void:
		if Net.account_name == "":
			if game != null:
				game.home_open_account()
		elif game != null:
			game.home_open_tournament())
	rail.add_child(_rail_centered(trophy_btn["holder"]))

	_rail_close_box = VBoxContainer.new()
	_rail_close_box.add_theme_constant_override("separation", 6)
	_rail_close_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(_rail_close_box)

	# Tín's latest word on the column's bottom slot: the "+"
	# chip is GONE — the "<" arrow lives there now (it used to
	# float beside the column at mid-height; that separate
	# chip is removed, so there is exactly ONE arrow, in the
	# column, where "+" used to be). Same 27px chip family as
	# the top pair; tapping it opens the friends panel.
	var arr := _icon_button("chev_left", "Mở danh sách bạn bè", 27.0)
	arr["btn"].pressed.connect(func() -> void: _rail_open_friends("all"))
	_rail_arrow = arr["holder"]
	rail.add_child(_rail_centered(_rail_arrow))
	_rebuild_rail()


## Shrink-wrap the rail group: the VBox and its backing hug
## the content height exactly (no full-height strip), so
## the group ends wherever its last element ends.
func _fit_rail() -> void:
	if _rail_box == null:
		return
	var h := _rail_box.get_combined_minimum_size().y
	_rail_box.size = Vector2(RAIL_W, h)
	if _rail_bg != null:
		_rail_bg.size = Vector2(RAIL_W + 10.0, h + 10.0)


func _rail_centered(child: Control) -> CenterContainer:
	var cell := CenterContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(child)
	return cell


## Rail entry point for every friends affordance: guests go
## to the account flow (the rail shows them icons only),
## accounts open the friends panel on the requested tab.
func _rail_open_friends(tab: String) -> void:
	if Net.account_name == "":
		if game != null:
			game.home_open_account()
		return
	open_friends_panel(tab)


## (Re)build the rail's close-friend portraits from the
## cached friends rows: flagged "bạn thân" only, online
## first (then most-recently-seen), at most 4. Portraits
## are the friends' chosen avatar art in square gold
## frames, with a green presence dot; a tap opens the
## friends panel on the Bạn bè tab.
func _rebuild_rail() -> void:
	if _rail_close_box == null:
		return
	for c in _rail_close_box.get_children():
		_rail_close_box.remove_child(c)
		c.queue_free()
	if Net.account_name == "":
		_fit_rail()
		return
	var close_rows: Array = []
	for r in Net.friends_rows:
		if bool(r.get("close", false)):
			close_rows.append(r)
	close_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ao := bool(a.get("online", false))
		var bo := bool(b.get("online", false))
		if ao != bo:
			return ao
		return int(a.get("last_online", 0)) > int(b.get("last_online", 0)))
	for i in range(mini(4, close_rows.size())):
		var r: Dictionary = close_rows[i]
		var cell := CenterContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(_rail_portrait(r))
		_rail_close_box.add_child(cell)
	# Owner order 2026-11-12 (his reference rail): while a
	# friend slot is still free, the "+" add chip closes
	# the friend column — with no close friends at all it
	# is the only thing above the arrow.
	if close_rows.size() < 4:
		var plus := _icon_button("plus", "Thêm bạn", 27.0)
		plus["btn"].pressed.connect(func() -> void: _rail_open_friends("all"))
		_rail_close_box.add_child(_rail_centered(plus["holder"]))
	_fit_rail()


func _rail_portrait(r: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(56, 56)
	holder.size = Vector2(56, 56)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel",
			_sb(Color(0.10, 0.08, 0.05), 4, GOLD, 2))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var av := AvatarFrame.new()
	av.custom_minimum_size = Vector2(50, 50)
	av.size = Vector2(50, 50)
	av.position = Vector2(3, 3)
	av.set_content(Avatars.texture_for_user(String(r.get("avatar_id", "")),
			String(r.get("user", ""))), String(r.get("frame_id", "")), false)
	holder.add_child(av)
	if bool(r.get("online", false)):
		var dot := PanelContainer.new()
		# _sb's shared content margins (10px sides) would
		# inflate this tiny panel's minimum size to a 20x12
		# pill; zero them so the dot stays a true 12px circle.
		var dot_sb := _sb(Color(0.35, 0.9, 0.45), 6)
		dot_sb.set_content_margin_all(0)
		dot.add_theme_stylebox_override("panel", dot_sb)
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size = Vector2(12, 12)
		dot.position = Vector2(42, 42)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(dot)
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.tooltip_text = String(r.get("display_name", String(r.get("user", ""))))
	tap.pressed.connect(func() -> void: _rail_open_friends("all"))
	holder.add_child(tap)
	return holder


## The bottom row (13i follow-ups): a TRANSPARENT Control —
## Tín ordered the black band background removed, so the
## painted buttons sit directly on the panorama. The row
## keeps the v6 band's footprint (BAND_H tall, 14px side
## margins, 8px top/bottom) so every element keeps its v6
## baseline. Tín then (13l addendum) removed the Thành
## Tích / Lịch Sử Trận / Bạn Bè entry points, and (13m
## follow-up 2, addendum 3) the last painted nav button —
## BẢNG XẾP HẠNG — too: BXH moved to the right rail, so
## the row's left side is empty panorama. The painted BẮT
## ĐẦU button stays pinned at the row's far right, at the
## same top position it held inside the old band. (The achievements / history /
## friends panels stay in code — dormant, with no home
## entry point, exactly like the guide panel whose button
## was never supplied.) The rank display floats just above
## the row, centred over BẮT ĐẦU (see _build_rank_pill).
## BẮT ĐẦU opens the mode-choice panel (see
## _build_mode_panel). The old daily bonus line under
## BẮT ĐẦU is gone from Home (the server feature itself
## stays — see the file header).
func _build_bottom_band() -> void:
	var bar := Control.new()
	bar.name = "BottomBand"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAND_H
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.name = "BottomRow"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.offset_top = 8
	row.offset_bottom = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	# -- The bottom-left is CLEAN now (13m follow-up 2,
	# addendum 3): Tín removed the last painted nav button
	# (BẢNG XẾP HẠNG) — the leaderboard lives on the right
	# rail's chart chip. Only the spacer remains here,
	# pushing BẮT ĐẦU to the far right; the left bottom
	# shows the panorama art only. (_on_nav's "leaderboard"
	# branch and NAV_TEX_LEADERBOARD stay in code, dormant.)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# -- BẮT ĐẦU pinned at the far right → the mode-choice
	# panel (Đấu Thường / Đấu Hạng). SHRINK_BEGIN keeps the
	# top position it had inside the old band's entry block.
	var start := TextureButton.new()
	start.name = "StartBtn"
	start.texture_normal = START_TEX
	start.ignore_texture_size = true
	start.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	start.focus_mode = Control.FOCUS_NONE
	var s_aspect := float(START_TEX.get_width()) / float(START_TEX.get_height())
	start.custom_minimum_size = Vector2(START_BTN_H * s_aspect, START_BTN_H)
	start.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_press_fx(start)
	start.pressed.connect(func() -> void: _open_mode_panel())
	row.add_child(start)

	_build_rank_pill()
	_build_mode_panel()


## One of Tín's painted nav buttons: a texture button with
## the label baked into the art, sized by the band height
## with its aspect preserved.
func _make_nav_button(tex: Texture2D, kind: String) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.focus_mode = Control.FOCUS_NONE
	var aspect := float(tex.get_width()) / float(tex.get_height())
	b.custom_minimum_size = Vector2(NAV_BTN_H * aspect, NAV_BTN_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_press_fx(b)
	b.pressed.connect(func() -> void: _on_nav(kind))
	return b


## Shared press feedback for the painted texture buttons:
## slight scale + darken around the centre pivot.
func _press_fx(b: BaseButton) -> void:
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(0.94, 0.94)
		b.modulate = Color(0.82, 0.82, 0.88))
	b.button_up.connect(func() -> void:
		b.scale = Vector2.ONE
		b.modulate = Color.WHITE)


## The rank display, floating just above the bottom row,
## centred over BẮT ĐẦU (Tín: the band was too tall with the
## rank row stacked inside it). Same compact glass pill as
## before; DISPLAY-ONLY since the 13l addendum (its tap
## used to open Thành Tích, whose entry points Tín removed).
func _build_rank_pill() -> void:
	_cluster_rank = ClusterRank.new()
	_cluster_rank.name = "ClusterRank"
	_cluster_rank.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cluster_rank.set_state(0, 0, 3, false, true, "Chưa xếp hạng")
	_cluster_rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cluster_rank)
	_layout_rank_pill()


## Position the floating rank pill: horizontally centred
## over BẮT ĐẦU (pinned at the row's far right, its right
## edge at the row's 14px right margin), bottom edge 8px
## above the row's top edge.
func _layout_rank_pill() -> void:
	if _cluster_rank == null:
		return
	var ms := _cluster_rank.get_combined_minimum_size()
	var s_aspect := float(START_TEX.get_width()) / float(START_TEX.get_height())
	var cx := 14.0 + START_BTN_H * s_aspect * 0.5
	_cluster_rank.offset_left = -cx - ms.x * 0.5
	_cluster_rank.offset_right = -cx + ms.x * 0.5
	_cluster_rank.offset_top = -(BAND_H + 8.0) - ms.y
	_cluster_rank.offset_bottom = -(BAND_H + 8.0)


## The mode-choice panel BẮT ĐẦU opens: Tín's painted gold
## frame (gen/panel_frame_build.py) shown at its natural
## aspect — never nine-sliced, so the corner and gem
## ornaments stay true. Title, the choices and the
## close affordance sit INSIDE the frame's navy glass
## (measured glass span ~x .06-.95 / y .16-.81; the centre
## gems' tips reach ~.20 at the top and ~.82 at the bottom,
## so the content box keeps clear of them): the main choices
## are Tín's painted emblem badges (Đấu Thường = blue crossed-
## swords shield → the NORMAL online queue, Đấu Hạng = red-gold
## winged-crown shield → the ranked queue), each with its
## one-line subtitle under it. BELOW them (13t, Tín's order)
## sit Custom (→ the custom room flow) and Minigame (→ an
## honest "sắp ra mắt" placeholder) — painted heraldic badges
## in the same style as the top pair since Tín's follow-up
## ("vẽ button Custom, Minigame như style của đấu thường,
## đấu hạng"): emerald fortress for Custom, purple trophy +
## dice for Minigame (gen/mode_badges_extra_build.py). All
## four badges share MODE_BADGE_H and the panel widened to
## 800 so both badge rows fit the glass.
## Closes on choice, on the X, or on a backdrop tap.
func _build_mode_panel() -> void:
	_mode_dim = ColorRect.new()
	_mode_dim.name = "ModeDim"
	_mode_dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_mode_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mode_dim.visible = false
	_mode_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_mode_panel())
	_root.add_child(_mode_dim)
	_mode_panel = Control.new()
	_mode_panel.name = "ModePanel"
	_mode_panel.set_anchors_preset(Control.PRESET_CENTER)
	var pw := 800.0
	var ph := pw * float(MODE_FRAME_TEX.get_height()) \
			/ float(MODE_FRAME_TEX.get_width())
	_mode_panel.position = Vector2(-pw * 0.5, -ph * 0.5)
	_mode_panel.size = Vector2(pw, ph)
	_mode_panel.visible = false
	_root.add_child(_mode_panel)
	var frame := TextureRect.new()
	frame.texture = MODE_FRAME_TEX
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_panel.add_child(frame)
	# Content box inside the glass, as fractions of the panel.
	var inner := VBoxContainer.new()
	inner.anchor_left = 0.085
	inner.anchor_right = 0.915
	inner.anchor_top = 0.195
	inner.anchor_bottom = 0.80
	inner.add_theme_constant_override("separation", 12)
	_mode_panel.add_child(inner)
	var title := _label("CHỌN CHẾ ĐỘ", 21, Color(1, 0.87, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)
	inner.add_child(title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 24)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(cards)
	cards.add_child(_make_mode_choice(true))
	cards.add_child(_make_mode_choice(false))
	# 13t: the two lower entries — Custom and Minigame.
	var extras := HBoxContainer.new()
	extras.add_theme_constant_override("separation", 24)
	inner.add_child(extras)
	extras.add_child(_make_mode_extra("custom"))
	extras.add_child(_make_mode_extra("minigame"))
	# The standard close affordance, at the glass's top-right.
	var x := Button.new()
	x.text = "X"
	x.anchor_left = 0.915
	x.anchor_right = 0.915
	x.anchor_top = 0.185
	x.anchor_bottom = 0.185
	x.offset_left = -38
	x.offset_right = 0
	x.offset_top = 0
	x.offset_bottom = 34
	x.add_theme_font_size_override("font_size", 16)
	x.add_theme_color_override("font_color", Color.WHITE)
	x.add_theme_stylebox_override("normal", _sb(Color(0.75, 0.2, 0.15), 9))
	x.add_theme_stylebox_override("hover", _sb(Color(0.85, 0.28, 0.2), 9))
	x.pressed.connect(_close_mode_panel)
	_mode_panel.add_child(x)
## One of the mode panel's two choices: Tín's painted emblem
## badge (sliced by gen/mode_badges_build.py — the mode name
## is baked into its ribbon) as a texture button at the
## largest size the glass fits. No caption under the badge —
## Tín ordered those note lines removed; the ribbon says it.
func _make_mode_choice(normal_mode: bool) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override("separation", 4)
	var tex: Texture2D = MODE_TEX_NORMAL if normal_mode else MODE_TEX_RANKED
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.focus_mode = Control.FOCUS_NONE
	var aspect := float(tex.get_width()) / float(tex.get_height())
	b.custom_minimum_size = Vector2(MODE_BADGE_H * aspect, MODE_BADGE_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_press_fx(b)
	if normal_mode:
		b.pressed.connect(func() -> void:
			_close_mode_panel()
			if game != null:
				game.home_open_normal())
	else:
		b.pressed.connect(func() -> void:
			_close_mode_panel()
			if game != null:
				game.home_open_ranked())
	cell.add_child(b)
	return cell


## One of the mode panel's two lower entries (13t): Custom or
## Minigame — since Tín's follow-up, a painted heraldic badge
## in the SAME style as the top pair (emerald fortress badge
## for Custom, purple trophy-and-dice badge for Minigame; the
## mode name is baked into each ribbon, sliced by
## gen/mode_badges_extra_build.py), structured exactly like
## _make_mode_choice's cells so the two rows align. Custom
## opens the custom room flow (create/join by code — bot play
## lives there now); Minigame opens the honest placeholder
## popup.
func _make_mode_extra(kind: String) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override("separation", 4)
	var tex: Texture2D = MODE_TEX_CUSTOM if kind == "custom" \
			else MODE_TEX_MINIGAME
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.focus_mode = Control.FOCUS_NONE
	var aspect := float(tex.get_width()) / float(tex.get_height())
	b.custom_minimum_size = Vector2(MODE_BADGE_H * aspect, MODE_BADGE_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_press_fx(b)
	if kind == "custom":
		b.pressed.connect(func() -> void:
			_close_mode_panel()
			if game != null:
				game.home_open_rooms())
	else:
		b.pressed.connect(func() -> void:
			_close_mode_panel()
			_open_popup("minigame"))
	cell.add_child(b)
	return cell


func _open_mode_panel() -> void:
	if _mode_dim != null:
		_mode_dim.visible = true
	if _mode_panel != null:
		_mode_panel.visible = true


func _close_mode_panel() -> void:
	if _mode_panel != null:
		_mode_panel.visible = false
	if _mode_dim != null:
		_mode_dim.visible = false


func _on_nav(kind: String) -> void:
	match kind:
		"leaderboard":
			if game != null:
				game.home_open_leaderboard()
		"history":
			_open_history_panel()
		_:
			_open_popup(kind)


func _on_tick() -> void:
	if not visible:
		return
	# Ping glyph band (Tín's correction): the glyph is the
	# meter — 2 good (< 100 ms, whole glyph green), 1
	# medium (100–200 ms, yellow base dot, grey arcs), 0
	# bad (> 200 ms, no pong yet, or disconnected: red
	# base dot, grey arcs).
	var band := 0
	if Net.connected and Net.ping_ms >= 0:
		band = 2 if Net.ping_ms < 100 else \
				(1 if Net.ping_ms <= 200 else 0)
	if _ping_icon != null:
		_ping_icon.signal_band = band
	if _ping_icon_shadow != null:
		_ping_icon_shadow.signal_band = band
	# Ping readout (text colour matches the band).
	if Net.connected and Net.ping_ms >= 0:
		_ping_label.text = "%d ms" % Net.ping_ms
		_ping_label.add_theme_color_override("font_color",
				Color(0.55, 0.95, 0.6) if Net.ping_ms < 100
				else (Color(1, 0.85, 0.45) if Net.ping_ms <= 200 else Color(1, 0.55, 0.45)))
	elif Net.connected:
		_ping_label.text = "..."
		_ping_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	else:
		_ping_label.text = "—"
		_ping_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	# Banner auto-rotate every ~6 s.
	_banner_clock += 0.5
	if _banner_clock >= 6.0:
		_show_banner((_banner_idx + 1) % 2)


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	_close_mode_panel()
	_close_popup()
	_close_friends_panel()


func refresh() -> void:
	if _root == null:
		return
	var guest := Net.account_name == ""
	# Profile chip follows the account's chosen avatar (13l
	# addendum 3; Net syncs the server value into the local
	# pick on auth, guests keep their local/default pick).
	if _chip_av != null:
		_chip_av.set_content(Avatars.texture_for(Avatars.local_avatar()),
				String(Net.auth_profile.get("frame_id", "")), true)
	# Name + level lines beside the portrait (13l level
	# from the auth payload; guests read Khách / chưa vào).
	if _chip_name != null:
		if guest:
			_chip_name.text = "Khách"
			_chip_lv.text = "Chưa đăng nhập"
		else:
			_chip_name.text = Net.display_name()
			_chip_lv.text = "Lv.%d" % int(Net.auth_profile.get("level", 1))
		_layout_chip()
	_set_mail_badge(Net.mail_unread)
	# Season-dependent labels track the server's current season.
	_show_banner(_banner_idx)
	# Entry cluster (13i): the big rank display.
	if _cluster_rank != null:
		if guest:
			_cluster_rank.set_state(0, 0, 3, false, true, "Chưa xếp hạng")
		else:
			var rk: Dictionary = Net.auth_profile.get("rank", {})
			var rcap := int(rk.get("star_cap", 3))
			_cluster_rank.set_state(int(rk.get("tier", 0)),
					int(rk.get("stars", 0)), rcap,
					bool(rk.get("emperor", false)), false,
					String(rk.get("short_text", "Tân Binh III")) if rcap > 0
					else String(rk.get("rank_text", "")))
		_layout_rank_pill()
	# Rail (13m): keep the close-friend portraits current.
	if not guest:
		Net.request_friends()
	_rebuild_rail()


# ------------------------------------------------------------ popups
## One shared glass popup; its body is rebuilt per kind. All data
## comes from Net (server-backed): profile payload, history,
## friends, mail. Guests get a login prompt where the feature is
## account-only.

func _build_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "PopupDim"
	dim.color = Color(0.01, 0.015, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	_root.add_child(dim)
	_popup = PanelContainer.new()
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.position = Vector2(-290, -250)
	_popup.custom_minimum_size = Vector2(580, 500)
	_popup.size = Vector2(580, 500)
	_popup.add_theme_stylebox_override("panel",
			_sb(Color(0.03, 0.045, 0.09, 0.97), 14, Color(1, 0.85, 0.4, 0.5), 1))
	_popup.visible = false
	_root.add_child(_popup)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_popup.add_child(vb)
	var head := HBoxContainer.new()
	_popup_title = _label("", 22, Color(1, 0.87, 0.45))
	head.add_child(_popup_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var x := Button.new()
	x.text = "X"
	x.custom_minimum_size = Vector2(38, 34)
	x.add_theme_font_size_override("font_size", 16)
	x.add_theme_color_override("font_color", Color.WHITE)
	x.add_theme_stylebox_override("normal", _sb(Color(0.75, 0.2, 0.15), 9))
	x.add_theme_stylebox_override("hover", _sb(Color(0.85, 0.28, 0.2), 9))
	x.pressed.connect(_close_popup)
	head.add_child(x)
	vb.add_child(head)
	_popup_status = _label("", 14, Color(1, 0.75, 0.5))
	_popup_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_popup_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_popup_body = VBoxContainer.new()
	_popup_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_popup_body.add_theme_constant_override("separation", 7)
	scroll.add_child(_popup_body)


func _open_popup(kind: String) -> void:
	_popup_kind = kind
	_mail_mark_sent = false
	_popup.visible = true
	_root.get_node("PopupDim").visible = true
	_popup_status.text = ""
	match kind:
		"profile":
			_popup_title.text = "Thành Tích"
		"friends":
			_popup_title.text = "Bạn Bè"
			if Net.account_name != "":
				Net.request_friends()
		"mail":
			_popup_title.text = "Thư"
			if Net.account_name != "":
				Net.request_mail()
		"guide":
			_popup_title.text = "Hướng Dẫn"
		"settings":
			_popup_title.text = "Cài Đặt"
		"minigame":
			_popup_title.text = "Minigame"
	_refill_popup()


func _close_popup() -> void:
	_popup_kind = ""
	if _popup != null:
		_popup.visible = false
	var dim := _root.get_node_or_null("PopupDim")
	if dim != null:
		dim.visible = false


func _refill_popup() -> void:
	if _popup == null or not _popup.visible or _popup_body == null:
		return
	for c in _popup_body.get_children():
		_popup_body.remove_child(c)
		c.queue_free()
	match _popup_kind:
		"profile":
			_fill_profile(_popup_body)
		"friends":
			_fill_friends(_popup_body)
		"mail":
			_fill_mail(_popup_body)
		"guide":
			_fill_guide(_popup_body)
		"settings":
			_fill_settings(_popup_body)
		"minigame":
			_fill_minigame(_popup_body)


## Minigame placeholder (13t): the mode panel has the entry,
## but no minigame system exists yet — say so honestly instead
## of inventing one.
func _fill_minigame(body: VBoxContainer) -> void:
	var l := _label("Minigame — sắp ra mắt.", 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)


func _guest_prompt(body: VBoxContainer, what: String) -> void:
	var l := _label("%s là tính năng theo tài khoản. Đăng nhập để sử dụng." % what, 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	var b := Button.new()
	b.text = "Đăng nhập / Đăng ký"
	b.custom_minimum_size = Vector2(220, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func() -> void:
		_close_popup()
		if game != null:
			game.home_open_account())
	body.add_child(b)


func _fmt_date(unix: int) -> String:
	if unix <= 0:
		return ""
	var s := Time.get_datetime_string_from_unix_time(unix)
	return s.substr(0, 10) + " " + s.substr(11, 5)


func _fmt_num(n: int) -> String:
	# Vietnamese thousand separators: 3268 -> "3.268".
	var neg := n < 0
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if neg else "") + digits + out


func _fill_profile(body: VBoxContainer) -> void:
	if Net.account_name == "":
		_guest_prompt(body, "Thành tích")
		return
	var p := Net.auth_profile
	var rank: Dictionary = p.get("rank", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var badge := RankBadge.new()
	badge.setup(int(rank.get("tier", 0)), int(rank.get("stars", 0)),
			int(rank.get("star_cap", 3)), bool(rank.get("emperor", false)), false)
	row.add_child(badge)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	var nm := _label(Net.display_name(), 24, Color.WHITE)
	vb.add_child(nm)
	vb.add_child(_label(String(rank.get("rank_text", "")), 18, Color(1, 0.9, 0.6)))
	vb.add_child(_label("Mùa %d" % _season_num(), 14, Color(0.8, 0.83, 0.9)))
	row.add_child(vb)
	body.add_child(row)
	var wins := int(p.get("wins", 0))
	var losses := int(p.get("losses", 0))
	var matches := int(p.get("matches", 0))
	var rate := 0.0
	if matches > 0:
		rate = 100.0 * float(wins) / float(matches)
	body.add_child(_label("MMR (điểm ghép trận): %s" % _fmt_num(int(p.get("mmr", 1000))), 17))
	body.add_child(_label("Thắng %d · Thua %d · Tổng %d trận · Tỉ lệ thắng %.0f%%"
			% [wins, losses, matches, rate], 17))
	body.add_child(_label("Đỉnh mùa này: %s" % String(rank.get("peak_text", "")), 17))
	var prev := String(rank.get("prev_season_text", ""))
	if prev != "":
		body.add_child(_label(prev, 15, Color(0.8, 0.83, 0.9)))


func _fill_friends(body: VBoxContainer) -> void:
	if Net.account_name == "":
		_guest_prompt(body, "Bạn bè")
		return
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	var edit := LineEdit.new()
	edit.placeholder_text = "Tên tài khoản bạn bè…"
	edit.custom_minimum_size = Vector2(300, 38)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 16)
	add_row.add_child(edit)
	var add_btn := Button.new()
	add_btn.text = "Thêm bạn"
	add_btn.custom_minimum_size = Vector2(110, 38)
	add_btn.add_theme_font_size_override("font_size", 16)
	add_btn.pressed.connect(func() -> void:
		var u := edit.text.strip_edges()
		if u != "":
			_popup_status.text = ""
			Net.add_friend(u)
			edit.text = "")
	add_row.add_child(add_btn)
	body.add_child(add_row)
	if Net.friends_rows.is_empty():
		body.add_child(_label("Chưa có bạn bè. Thêm bạn bằng tên tài khoản để xem hạng và trạng thái online của họ.", 15))
		return
	for f in Net.friends_rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var badge := RankBadge.new()
		badge.setup(int(f.get("rank_tier", 0)), 0, 3, bool(f.get("emperor", false)), true)
		row.add_child(badge)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_child(_label(Net.ally_disp(String(f.get("display_name", String(f.get("user", "?")))),
				String(f.get("ally_tag", ""))), 17, Color.WHITE))
		mid.add_child(_label(String(f.get("rank_text", "")), 13, Color(0.8, 0.83, 0.9)))
		row.add_child(mid)
		var online := bool(f.get("online", false))
		var dot := PanelContainer.new()
		dot.add_theme_stylebox_override("panel",
				_sb(Color(0.4, 0.9, 0.45) if online else Color(0.45, 0.47, 0.55), 6))
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		row.add_child(_label("Đang online" if online else "Ngoại tuyến", 14,
				Color(0.6, 0.95, 0.65) if online else Color(0.65, 0.68, 0.78)))
		var rm := Button.new()
		rm.text = "Xoá"
		rm.custom_minimum_size = Vector2(58, 32)
		rm.add_theme_font_size_override("font_size", 14)
		var uname := String(f.get("user", ""))
		rm.pressed.connect(func() -> void: Net.remove_friend(uname))
		row.add_child(rm)
		body.add_child(row)


func _fill_mail(body: VBoxContainer) -> void:
	if Net.account_name == "":
		_guest_prompt(body, "Thư")
		return
	if Net.mail_rows.is_empty():
		body.add_child(_label("Hộp thư trống.", 16))
		return
	for l in Net.mail_rows:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel",
				_sb(Color(1, 1, 1, 0.05) if bool(l.get("read", true)) else Color(1, 0.85, 0.4, 0.12), 8))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		var head := HBoxContainer.new()
		var t := _label(String(l.get("title", "")), 17,
				Color.WHITE if bool(l.get("read", true)) else Color(1, 0.9, 0.55))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		head.add_child(_label(_fmt_date(int(l.get("at", 0))), 13, Color(0.7, 0.73, 0.82)))
		vb.add_child(head)
		var b := _label(String(l.get("body", "")), 15, Color(0.9, 0.9, 0.88))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(b)
		box.add_child(vb)
		body.add_child(box)


func _fill_guide(body: VBoxContainer) -> void:
	var sections := [
		["Điều khiển", "Chuột trái: chọn quân / kéo khung chọn nhiều quân. Chuột phải: ra lệnh di chuyển, tấn công, thu thập. Camera: WASD / phím mũi tên, kéo chuột giữa, cuộn chuột để zoom."],
		["Kinh tế", "Dân làng (Villager) chặt gỗ, hái quả/đào vàng/đá rồi mang về Town Center. Xây nhà để tăng giới hạn dân số. Huấn luyện mọi loại lính tại Trại lính (Barracks) — mở khoá dần theo thời đại."],
		["Thời đại", "Nghiên cứu lên đời tại Town Center: I Nguyên thuỷ → II Phong kiến → III Lâu đài → IV Đế quốc. Lên đời mở khoá công trình và quân mạnh hơn (Castle cần để lên đời IV)."],
		["Thắng / thua", "Phá Town Center của địch VÀ quét sạch chúng (hết dân làng hoặc hết nơi huấn luyện lính) là thắng. Mất Town Center và bị quét sạch là thua."],
		["Màu đội", "Mỗi người chơi một màu riêng — Đỏ, Xanh dương, Xanh lá, Vàng — nhuộm lên vải, khiên, cờ và chấm bản đồ nhỏ. Quân các phe dùng chung hình dạng, chỉ khác màu."],
		["Hạng & mùa giải", "Đấu Hạng 1v1: thắng +1 sao (thắng liên tiếp từ 3 trận được +1 sao thưởng), đủ sao thì thăng đoàn/hạng: Tân Binh → Chiến Binh → Kỵ Sĩ → Nam Tước → Bá Tước → Hầu Tước → Công Tước → Hoàng Đế (top 50 Công Tước). Mỗi mùa 90 ngày; hết mùa hạng được đặt lại mềm và lưu đỉnh mùa."],
	]
	for s in sections:
		body.add_child(_label(s[0], 18, Color(1, 0.87, 0.45)))
		var t := _label(s[1], 15, Color(0.92, 0.92, 0.9))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(t)


func _fill_settings(body: VBoxContainer) -> void:
	var st := "Đã kết nối máy chủ" if Net.connected else "Chưa kết nối"
	if Net.connected and Net.ping_ms >= 0:
		st += " · ping %d ms" % Net.ping_ms
	body.add_child(_label("Trạng thái: " + st, 16))
	body.add_child(_label("Địa chỉ máy chủ (WebSocket):", 15, Color(0.85, 0.87, 0.92)))
	var edit := LineEdit.new()
	edit.text = Net.DEFAULT_URL
	edit.custom_minimum_size = Vector2(0, 38)
	edit.add_theme_font_size_override("font_size", 15)
	body.add_child(edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var save := Button.new()
	save.text = "Lưu địa chỉ"
	save.custom_minimum_size = Vector2(140, 38)
	save.add_theme_font_size_override("font_size", 15)
	save.pressed.connect(func() -> void:
		if game != null and game.has_method("home_set_server"):
			game.home_set_server(edit.text)
		_popup_status.text = "Đã lưu. Địa chỉ áp dụng cho Chơi mạng / Đấu Hạng.")
	row.add_child(save)
	if Net.connected:
		var disc := Button.new()
		disc.text = "Ngắt kết nối"
		disc.custom_minimum_size = Vector2(140, 38)
		disc.add_theme_font_size_override("font_size", 15)
		disc.pressed.connect(func() -> void:
			Net.disconnect_from_server()
			_refill_popup())
		row.add_child(disc)
	body.add_child(row)
	var note := _label("Âm thanh, nhạc và tạm dừng trận nằm ở menu “Khác” trong trận đấu.", 14, Color(0.75, 0.78, 0.86))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)


# ------------------------------------------------------------ history panel
## Full-screen match history in the reference's language: dark
## blue glass over the dimmed home art, gold back arrow + title,
## a mode filter, reference-style row cards (mode + relative time
## | result | map chip | player chips | replay slot + details),
## and real pagination (5 rows per page). Ranked rows come from
## the server history; custom rows from the device-local log
## (LocalHistory). The round slot left of the details button is
## RESERVED for replay (13h) — intentionally left empty here.

const HIST_PAGE_SIZE := 5


func _build_history_panel() -> void:
	_hist_root = Control.new()
	_hist_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hist_root.visible = false
	_root.add_child(_hist_root)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/home_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hist_root.add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hist_root.add_child(dim)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 26
	board.offset_top = 14
	board.offset_right = -26
	board.offset_bottom = -14
	board.add_theme_stylebox_override("panel",
			_sb(Color(0.02, 0.035, 0.085, 0.94), 12, Color(1, 0.85, 0.4, 0.3), 1))
	_hist_root.add_child(board)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	board.add_child(vb)
	# Header: gold back arrow + title + mode filter.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.custom_minimum_size = Vector2(52, 46)
	back.add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0.25), 8))
	back.add_theme_stylebox_override("hover", _sb(Color(1, 0.85, 0.4, 0.2), 8))
	var bic := GlassIcon.new()
	bic.kind = "back"
	bic.custom_minimum_size = Vector2(30, 30)
	bic.size = Vector2(30, 30)
	bic.position = Vector2(11, 8)
	bic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(bic)
	back.pressed.connect(func() -> void: _hist_root.visible = false)
	head.add_child(back)
	var title := _label("Lịch Sử Trận", 30, Color(1, 0.87, 0.45))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var filter := OptionButton.new()
	filter.add_item("Tất cả chế độ", 0)
	filter.add_item("Đấu Hạng", 1)
	filter.add_item("Đấu Thường", 2)
	filter.custom_minimum_size = Vector2(210, 42)
	filter.add_theme_font_size_override("font_size", 16)
	filter.add_theme_stylebox_override("normal",
			_sb(Color(0.05, 0.07, 0.14, 0.95), 8, Color(1, 0.85, 0.4, 0.4), 1))
	filter.item_selected.connect(func(idx: int) -> void:
		_hist_filter = idx
		_hist_page = 0
		_rebuild_history())
	head.add_child(filter)
	vb.add_child(head)
	_hist_rows_box = VBoxContainer.new()
	_hist_rows_box.add_theme_constant_override("separation", 9)
	_hist_rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_hist_rows_box)
	_hist_pages_box = HBoxContainer.new()
	_hist_pages_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hist_pages_box.add_theme_constant_override("separation", 6)
	vb.add_child(_hist_pages_box)
	_build_history_detail()


func _build_history_detail() -> void:
	_hist_detail = PanelContainer.new()
	_hist_detail.set_anchors_preset(Control.PRESET_CENTER)
	_hist_detail.position = Vector2(-250, -190)
	_hist_detail.custom_minimum_size = Vector2(500, 380)
	_hist_detail.size = Vector2(500, 380)
	_hist_detail.add_theme_stylebox_override("panel",
			_sb(Color(0.03, 0.045, 0.09, 0.98), 12, Color(1, 0.85, 0.4, 0.55), 1))
	_hist_detail.visible = false
	_hist_root.add_child(_hist_detail)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	_hist_detail.add_child(vb)
	var head := HBoxContainer.new()
	var dt := _label("Chi Tiết Trận", 21, Color(1, 0.87, 0.45))
	dt.name = "DetailTitle"
	head.add_child(dt)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := Button.new()
	x.text = "X"
	x.custom_minimum_size = Vector2(36, 32)
	x.add_theme_color_override("font_color", Color.WHITE)
	x.add_theme_stylebox_override("normal", _sb(Color(0.75, 0.2, 0.15), 8))
	x.add_theme_stylebox_override("hover", _sb(Color(0.85, 0.28, 0.2), 8))
	x.pressed.connect(func() -> void: _hist_detail.visible = false)
	head.add_child(x)
	vb.add_child(head)
	_hist_detail_body = VBoxContainer.new()
	_hist_detail_body.add_theme_constant_override("separation", 5)
	vb.add_child(_hist_detail_body)


func _open_history_panel() -> void:
	_hist_page = 0
	_hist_root.visible = true
	if Net.account_name != "":
		Net.request_history()
	_rebuild_history()


## Capture-harness entry (tests/capture_history.sh).
func open_history_for_shot() -> void:
	_open_history_panel()


# ------------------------------------------------------------ friends panel (13m)
## The redesigned Bạn bè screen (Tín's Liên Quân reference):
## the shared info-page shell (PageShell, 13q — same solid
## navy background and back-pill + title header as Hồ sơ /
## Bảng xếp hạng), a Tìm bạn box at the header's right end, a left
## menu (Bạn bè / Bạn thân / Tìm bạn) and rows with a gold-
## framed avatar portrait, an Lv badge, the name, an Online /
## last-seen status line and two flat glyph actions — heart
## (bạn thân toggle) and trash (remove, with confirm). All
## chrome icons are the game's drawn glyph set (Tín: "icon
## css"), never painted art. Deliberately NO chat icon: the
## mail system is server-to-player only, so there is no
## player-to-player channel to open. No gift/coin icons
## either — those systems do not exist.

const FR_ONLINE := Color(0.45, 0.95, 0.55)
const FR_MUTED := Color(0.62, 0.66, 0.75)


func _build_friends_panel() -> void:
	_fr_root = Control.new()
	_fr_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fr_root.visible = false
	_root.add_child(_fr_root)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/home_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fr_root.add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fr_root.add_child(dim)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Full-bleed (Tín, 13m follow-up): the board covers the
	# ENTIRE viewport edge-to-edge — opaque navy, square
	# corners, no home art margin around it. The bg/dim
	# layers above stay only as a backdrop while it fades in.
	board.add_theme_stylebox_override("panel",
			_sb(PageShell.BG, 0))
	_fr_root.add_child(board)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	# Content starts below the shared header (13q):
	# PageShell.CONTENT_TOP, same as the profile panel.
	margin.add_theme_constant_override("margin_top", int(PageShell.CONTENT_TOP))
	margin.add_theme_constant_override("margin_bottom", 14)
	board.add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	margin.add_child(root_box)

	# -- Header: the shared page header (PageShell, 13q) —
	# identical back pill + title to Hồ sơ / Bảng xếp
	# hạng, overlaid on the board. The Tìm bạn box hangs
	# off the header's right end; it never touches the
	# shared back+title block.
	var hdr := PageShell.header("Bạn bè",
			func() -> void: _close_friends_panel())
	_fr_root.add_child(hdr)
	_fr_search_edit = LineEdit.new()
	_fr_search_edit.placeholder_text = "Tìm bạn — nhập tên tài khoản…"
	_fr_search_edit.custom_minimum_size = Vector2(330, 44)
	_fr_search_edit.add_theme_font_size_override("font_size", 16)
	_fr_search_edit.anchor_left = 1.0
	_fr_search_edit.anchor_right = 1.0
	_fr_search_edit.offset_left = -408
	_fr_search_edit.offset_right = -78
	_fr_search_edit.offset_top = 11
	_fr_search_edit.offset_bottom = 55
	_fr_search_edit.text_submitted.connect(func(_t: String) -> void: _fr_submit_add(_fr_search_edit))
	hdr.add_child(_fr_search_edit)
	var search := _icon_button("search", "Tìm bạn")
	search["btn"].pressed.connect(func() -> void: _fr_submit_add(_fr_search_edit))
	var sholder: Control = search["holder"]
	sholder.anchor_left = 1.0
	sholder.anchor_right = 1.0
	sholder.offset_left = -59
	sholder.offset_right = -11
	sholder.offset_top = 9
	sholder.offset_bottom = 57
	hdr.add_child(sholder)

	_fr_status = _label("", 15, GOLD_LIGHT)
	root_box.add_child(_fr_status)

	# -- Guest state: a login prompt instead of the lists.
	_fr_guest_box = VBoxContainer.new()
	_fr_guest_box.add_theme_constant_override("separation", 12)
	_fr_guest_box.visible = false
	root_box.add_child(_fr_guest_box)
	var gl := _label("Đăng nhập để dùng Bạn bè — thêm bạn, ghim bạn thân lên sảnh và xem ai đang online.", 16, PAPER)
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fr_guest_box.add_child(gl)
	var gbtn := Button.new()
	gbtn.text = "Đăng nhập / Đăng ký"
	gbtn.custom_minimum_size = Vector2(220, 44)
	gbtn.add_theme_font_size_override("font_size", 16)
	gbtn.add_theme_stylebox_override("normal", _sb(Color(0.85, 0.6, 0.16), 8))
	gbtn.add_theme_stylebox_override("hover", _sb(Color(0.95, 0.7, 0.22), 8))
	gbtn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
	gbtn.pressed.connect(func() -> void:
		_close_friends_panel()
		if game != null:
			game.home_open_account())
	_fr_guest_box.add_child(gbtn)

	# -- Content: left menu + side (list or find form).
	_fr_content = HBoxContainer.new()
	_fr_content.add_theme_constant_override("separation", 12)
	_fr_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(_fr_content)
	var menu := VBoxContainer.new()
	menu.custom_minimum_size = Vector2(176, 0)
	menu.add_theme_constant_override("separation", 8)
	_fr_content.add_child(menu)
	for tab_def in [["all", "Bạn bè"], ["close", "Bạn thân"], ["find", "Tìm bạn"]]:
		var b := Button.new()
		b.text = String(tab_def[1])
		b.custom_minimum_size = Vector2(176, 46)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func() -> void: _fr_set_tab(String(tab_def[0])))
		menu.add_child(b)
		_fr_menu[String(tab_def[0])] = b
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	_fr_content.add_child(side)
	_fr_scroll = ScrollContainer.new()
	_fr_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fr_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_fr_scroll)
	_fr_list = VBoxContainer.new()
	_fr_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fr_list.add_theme_constant_override("separation", 8)
	_fr_scroll.add_child(_fr_list)
	_fr_find_box = VBoxContainer.new()
	_fr_find_box.add_theme_constant_override("separation", 10)
	_fr_find_box.visible = false
	side.add_child(_fr_find_box)
	var fh := _label("Thêm bạn bằng tên tài khoản", 19, GOLD_LIGHT)
	_fr_find_box.add_child(fh)
	var fdesc := _label("Nhập đúng tên tài khoản của người chơi — họ sẽ xuất hiện trong danh sách Bạn bè ngay khi thêm thành công.", 14, FR_MUTED)
	fdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fr_find_box.add_child(fdesc)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	_fr_find_box.add_child(frow)
	_fr_find_edit = LineEdit.new()
	_fr_find_edit.placeholder_text = "Tên tài khoản…"
	_fr_find_edit.custom_minimum_size = Vector2(0, 46)
	_fr_find_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fr_find_edit.add_theme_font_size_override("font_size", 16)
	_fr_find_edit.text_submitted.connect(func(_t: String) -> void: _fr_submit_add(_fr_find_edit))
	frow.add_child(_fr_find_edit)
	var add_btn := Button.new()
	add_btn.text = "Thêm bạn"
	add_btn.custom_minimum_size = Vector2(130, 46)
	add_btn.add_theme_font_size_override("font_size", 16)
	add_btn.add_theme_stylebox_override("normal", _sb(Color(0.85, 0.6, 0.16), 8))
	add_btn.add_theme_stylebox_override("hover", _sb(Color(0.95, 0.7, 0.22), 8))
	add_btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
	add_btn.pressed.connect(func() -> void: _fr_submit_add(_fr_find_edit))
	frow.add_child(add_btn)

	# -- Remove-friend confirm (dim + centred card).
	_fr_confirm = Control.new()
	_fr_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fr_confirm.visible = false
	_fr_root.add_child(_fr_confirm)
	var cdim := ColorRect.new()
	cdim.color = Color(0.005, 0.01, 0.03, 0.6)
	cdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fr_confirm.add_child(cdim)
	var ccent := CenterContainer.new()
	ccent.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fr_confirm.add_child(ccent)
	var ccard := PanelContainer.new()
	ccard.custom_minimum_size = Vector2(430, 0)
	ccard.add_theme_stylebox_override("panel",
			_sb(Color(0.03, 0.045, 0.10, 0.98), 12, Color(1, 0.85, 0.4, 0.6), 1))
	ccent.add_child(ccard)
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 18)
	cm.add_theme_constant_override("margin_right", 18)
	cm.add_theme_constant_override("margin_top", 14)
	cm.add_theme_constant_override("margin_bottom", 14)
	ccard.add_child(cm)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 12)
	cm.add_child(cbox)
	_fr_confirm_text = _label("", 17, PAPER)
	_fr_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cbox.add_child(_fr_confirm_text)
	var cbtns := HBoxContainer.new()
	cbtns.add_theme_constant_override("separation", 10)
	cbox.add_child(cbtns)
	var del_btn := Button.new()
	del_btn.text = "Xoá bạn"
	del_btn.custom_minimum_size = Vector2(130, 42)
	del_btn.add_theme_font_size_override("font_size", 16)
	del_btn.add_theme_stylebox_override("normal", _sb(Color(0.75, 0.25, 0.2), 8))
	del_btn.add_theme_stylebox_override("hover", _sb(Color(0.85, 0.32, 0.26), 8))
	del_btn.add_theme_color_override("font_color", Color.WHITE)
	del_btn.pressed.connect(func() -> void:
		var who := _fr_pending_remove
		_fr_confirm.visible = false
		_fr_pending_remove = ""
		if who != "":
			Net.remove_friend(who)
			_fr_status.text = "Đã xoá %s khỏi danh sách bạn bè." % who)
	cbtns.add_child(del_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Huỷ"
	cancel_btn.custom_minimum_size = Vector2(110, 42)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.add_theme_stylebox_override("normal", _sb(Color(1, 1, 1, 0.1), 8))
	cancel_btn.add_theme_color_override("font_color", PAPER)
	cancel_btn.pressed.connect(func() -> void:
		_fr_confirm.visible = false
		_fr_pending_remove = "")
	cbtns.add_child(cancel_btn)


func open_friends_panel(tab: String = "all") -> void:
	_fr_tab = tab if ["all", "close", "find"].has(tab) else "all"
	_fr_status.text = ""
	_fr_root.visible = true
	if Net.account_name != "":
		Net.request_friends()
	_refill_friends_panel()
	if _fr_tab == "find" and _fr_find_edit != null:
		_fr_find_edit.grab_focus()


## Capture-harness entry (tests/capture_friends.sh).
func open_friends_for_shot(tab: String = "all") -> void:
	open_friends_panel(tab)


func _close_friends_panel() -> void:
	if _fr_root != null:
		_fr_root.visible = false
	if _fr_confirm != null:
		_fr_confirm.visible = false
	_fr_pending_remove = ""


func _fr_set_tab(tab: String) -> void:
	_fr_tab = tab
	_fr_status.text = ""
	_refill_friends_panel()
	if tab == "find" and _fr_find_edit != null:
		_fr_find_edit.grab_focus()


## Add-by-username, shared by the header Tìm bạn box and the
## Tìm bạn tab form: the server answers with a fresh list (or
## a friend_error, surfaced in the status line verbatim).
func _fr_submit_add(edit: LineEdit) -> void:
	var name := edit.text.strip_edges()
	if name == "":
		return
	edit.text = ""
	_fr_status.text = ""
	_fr_last_add = name
	Net.add_friend(name)


func _fr_sorted_rows() -> Array:
	var rows: Array = Net.friends_rows.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ao := bool(a.get("online", false))
		var bo := bool(b.get("online", false))
		if ao != bo:
			return ao
		var al := int(a.get("last_online", 0))
		var bl := int(b.get("last_online", 0))
		if al != bl:
			return al > bl
		return String(a.get("user", "")) < String(b.get("user", "")))
	return rows


func _refill_friends_panel() -> void:
	if _fr_root == null or _fr_list == null:
		return
	# A successful add while standing on Tìm bạn: land on the
	# list so the new friend is visible.
	if _fr_tab == "find" and _fr_last_add != "":
		for r in Net.friends_rows:
			if String(r.get("user", "")) == _fr_last_add:
				_fr_tab = "all"
				_fr_status.text = "Đã thêm %s vào danh sách bạn bè." % _fr_last_add
				break
		_fr_last_add = ""
	var guest := Net.account_name == ""
	_fr_guest_box.visible = guest
	_fr_content.visible = not guest
	if guest:
		return
	for key in _fr_menu:
		var b: Button = _fr_menu[key]
		if key == _fr_tab:
			b.add_theme_stylebox_override("normal", _sb(Color(0.55, 0.38, 0.1, 0.95), 8))
			b.add_theme_color_override("font_color", GOLD_LIGHT)
		else:
			b.add_theme_stylebox_override("normal", _sb(Color(1, 1, 1, 0.06), 8))
			b.add_theme_color_override("font_color", PAPER)
	_fr_scroll.visible = _fr_tab != "find"
	_fr_find_box.visible = _fr_tab == "find"
	if _fr_tab == "find":
		return
	for c in _fr_list.get_children():
		_fr_list.remove_child(c)
		c.queue_free()
	var rows := _fr_sorted_rows()
	if _fr_tab == "close":
		rows = rows.filter(func(r: Dictionary) -> bool: return bool(r.get("close", false)))
	if rows.is_empty():
		var empty := _label(
				"Chưa có bạn bè nào.\nMở tab Tìm bạn để thêm bạn bằng tên tài khoản."
				if _fr_tab == "all" else
				"Chưa có bạn thân nào.\nBấm biểu tượng trái tim ở một người bạn để ghim họ lên thanh bên phải ở sảnh.",
				15, FR_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fr_list.add_child(empty)
		return
	for r in rows:
		_fr_list.add_child(_friend_row(r))


func _friend_row(f: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel",
			_sb(Color(1, 1, 1, 0.05), 10, Color(1, 0.85, 0.4, 0.18), 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	h.add_child(_friend_avatar_block(f))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 2)
	h.add_child(mid)
	var uname := String(f.get("user", ""))
	var name_l := _label(Net.ally_disp(String(f.get("display_name", uname)),
			String(f.get("ally_tag", ""))), 17, PAPER)
	mid.add_child(name_l)
	var status_l: Label
	if bool(f.get("online", false)):
		status_l = _label("Online", 14, FR_ONLINE)
	else:
		var lo := int(f.get("last_online", 0))
		if lo > 0:
			status_l = _label("Online gần đây · " + _rel_time(lo), 14, FR_MUTED)
		else:
			status_l = _label("Chưa rõ lần cuối online", 14, FR_MUTED)
	mid.add_child(status_l)
	var rank_text := String(f.get("rank_text", ""))
	if bool(f.get("close", false)):
		rank_text += "  ·  Bạn thân"
	mid.add_child(_label(rank_text, 13, FR_MUTED))
	# Glyph actions: heart toggles bạn thân (filled gold when
	# set, outline when not); trash removes (with confirm).
	var is_close := bool(f.get("close", false))
	var heart := _icon_button("heart" if is_close else "heart_o",
			"Bỏ bạn thân" if is_close else "Đánh dấu bạn thân")
	var hic: GlassIcon = heart["holder"].get_child(1)
	hic.modulate = Color(1.0, 0.78, 0.3) if is_close else Color(0.75, 0.78, 0.85)
	heart["btn"].pressed.connect(func() -> void:
		Net.set_close_friend(uname, not is_close))
	heart["holder"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(heart["holder"])
	var trash := _icon_button("trash", "Xoá bạn")
	var tic: GlassIcon = trash["holder"].get_child(1)
	tic.modulate = Color(1.0, 0.62, 0.55)
	trash["btn"].pressed.connect(func() -> void:
		_fr_pending_remove = uname
		_fr_confirm_text.text = "Xoá %s khỏi danh sách bạn bè?" % String(f.get("display_name", uname))
		_fr_confirm.visible = true)
	trash["holder"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(trash["holder"])
	return row


## Framed portrait + Lv badge (+ presence dot), like the
## reference rows: the friend's chosen avatar art in a
## square gold frame, "Lv.N" pill overlapping the frame's
## bottom edge.
func _friend_avatar_block(f: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(64, 68)
	holder.size = Vector2(64, 68)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(64, 64)
	frame.size = Vector2(64, 64)
	frame.add_theme_stylebox_override("panel",
			_sb(Color(0.10, 0.08, 0.05), 4, GOLD, 2))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var av := AvatarFrame.new()
	av.custom_minimum_size = Vector2(58, 58)
	av.size = Vector2(58, 58)
	av.position = Vector2(3, 3)
	av.set_content(Avatars.texture_for_user(String(f.get("avatar_id", "")),
			String(f.get("user", ""))), String(f.get("frame_id", "")), false)
	holder.add_child(av)
	if bool(f.get("online", false)):
		var dot := PanelContainer.new()
		dot.add_theme_stylebox_override("panel", _sb(Color(0.35, 0.9, 0.45), 6))
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size = Vector2(12, 12)
		dot.position = Vector2(50, 2)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(dot)
	var lv := PanelContainer.new()
	lv.add_theme_stylebox_override("panel",
			_sb(Color(0.05, 0.05, 0.09, 0.95), 6, Color(1, 0.85, 0.4, 0.5), 1))
	lv.custom_minimum_size = Vector2(44, 17)
	lv.size = Vector2(44, 17)
	lv.position = Vector2(10, 51)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ll := _label("Lv.%d" % int(f.get("level", 1)), 11, GOLD_LIGHT)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.set_anchors_preset(Control.PRESET_FULL_RECT)
	ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(ll)
	holder.add_child(lv)
	return holder


func _hist_entries() -> Array:
	var out: Array = []
	for r in Net.history_rows:
		var players: Array = [{"name": Net.display_name(), "team": 0},
				{"name": String(r.get("opponent", "?")), "team": 1}]
		out.append({
			"ranked": true, "won": bool(r.get("won", false)),
			"at": int(r.get("at", 0)),
			"biome": String(r.get("biome", "")), "layout": String(r.get("layout", "")),
			"star_delta": int(r.get("star_delta", 0)),
			"star_bonus": bool(r.get("star_bonus", false)),
			"daily_bonus": bool(r.get("daily_bonus", false)),
			"rank_from": String(r.get("rank_from", "")),
			"rank_to": String(r.get("rank_to", "")),
			"duration_ticks": int(r.get("duration_ticks", 0)),
			"players": players, "replay_id": String(r.get("replay_id", "")),
		})
	for e in LocalHistory.entries():
		out.append({
			"ranked": false, "won": bool(e.get("won", false)),
			"at": int(e.get("at", 0)),
			"biome": String(e.get("biome", "grassland")),
			"layout": String(e.get("layout", "plains")),
			"star_delta": 0, "star_bonus": false, "daily_bonus": false,
			"rank_from": "", "rank_to": "",
			"duration_ticks": int(e.get("duration_ticks", 0)),
			"players": e.get("players", []),
			"replay_id": String(e.get("replay_id", "")),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["at"]) > int(b["at"]))
	if _hist_filter == 1:
		out = out.filter(func(e: Dictionary) -> bool: return bool(e["ranked"]))
	elif _hist_filter == 2:
		out = out.filter(func(e: Dictionary) -> bool: return not bool(e["ranked"]))
	return out


func _rel_time(at: int) -> String:
	var diff := int(Time.get_unix_time_from_system()) - at
	if diff < 60:
		return "Vừa xong"
	if diff < 3600:
		return "%d phút trước" % maxi(1, diff / 60)
	if diff < 86400:
		return "%d giờ trước" % (diff / 3600)
	if diff < 172800:
		return "Hôm qua"
	if diff < 7 * 86400:
		return "%d ngày trước" % (diff / 86400)
	return _fmt_date(at)


func _rebuild_history() -> void:
	if _hist_rows_box == null:
		return
	for c in _hist_rows_box.get_children():
		_hist_rows_box.remove_child(c)
		c.queue_free()
	for c in _hist_pages_box.get_children():
		_hist_pages_box.remove_child(c)
		c.queue_free()
	var entries := _hist_entries()
	if entries.is_empty():
		var msg := "Chưa có trận nào trong lịch sử."
		if Net.account_name == "" and _hist_filter != 2:
			msg = "Đăng nhập để xem lịch sử Đấu Hạng; trận Đấu Thường trên máy này sẽ hiện tại đây."
		var l := _label(msg, 17)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hist_rows_box.add_child(l)
		return
	var pages := int(ceil(float(entries.size()) / float(HIST_PAGE_SIZE)))
	_hist_page = clampi(_hist_page, 0, pages - 1)
	var from := _hist_page * HIST_PAGE_SIZE
	var to := mini(entries.size(), from + HIST_PAGE_SIZE)
	for i in range(from, to):
		_hist_rows_box.add_child(_hist_row_card(entries[i]))
	# Pagination: ‹ 1 2 3 … › (windowed when many pages).
	var prev := _page_btn("‹", _hist_page > 0)
	prev.pressed.connect(func() -> void:
		_hist_page -= 1
		_rebuild_history())
	_hist_pages_box.add_child(prev)
	var nums: Array = []
	if pages <= 7:
		for i in range(pages):
			nums.append(i)
	else:
		var keep := {}
		for i in [0, 1, _hist_page - 1, _hist_page, _hist_page + 1, pages - 2, pages - 1]:
			if i >= 0 and i < pages:
				keep[i] = true
		var last := -1
		for i in range(pages):
			if keep.has(i):
				if last >= 0 and i - last > 1:
					nums.append(-1) # ellipsis
				nums.append(i)
				last = i
	for n in nums:
		if n == -1:
			var dots := _label("…", 17, Color(0.75, 0.78, 0.86))
			dots.custom_minimum_size = Vector2(22, 38)
			dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_hist_pages_box.add_child(dots)
		else:
			var b := _page_btn(str(n + 1), true, n == _hist_page)
			var target: int = n
			b.pressed.connect(func() -> void:
				_hist_page = target
				_rebuild_history())
			_hist_pages_box.add_child(b)
	var next := _page_btn("›", _hist_page < pages - 1)
	next.pressed.connect(func() -> void:
		_hist_page += 1
		_rebuild_history())
	_hist_pages_box.add_child(next)


func _page_btn(text: String, enabled: bool, active: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(40, 38)
	b.add_theme_font_size_override("font_size", 17)
	b.disabled = not enabled
	if active:
		b.add_theme_color_override("font_color", Color(0.15, 0.1, 0.02))
		b.add_theme_stylebox_override("normal", _sb(Color(0.98, 0.8, 0.35), 7))
		b.add_theme_stylebox_override("hover", _sb(Color(0.98, 0.8, 0.35), 7))
	else:
		b.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
		b.add_theme_stylebox_override("normal",
				_sb(Color(0.05, 0.07, 0.14, 0.9), 7, Color(1, 1, 1, 0.18), 1))
		b.add_theme_stylebox_override("hover",
				_sb(Color(0.1, 0.13, 0.24, 0.95), 7, Color(1, 0.85, 0.4, 0.5), 1))
	return b


func _hist_row_card(e: Dictionary) -> PanelContainer:
	var won := bool(e["won"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 92)
	if won:
		card.add_theme_stylebox_override("panel",
				_sb(Color(0.09, 0.075, 0.03, 0.97), 10, Color(1, 0.8, 0.3, 0.95), 2))
	else:
		card.add_theme_stylebox_override("panel",
				_sb(Color(0.028, 0.04, 0.085, 0.97), 10, Color(1, 1, 1, 0.14), 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	# --- mode cell: swords (+ laurel when ranked) + name + time
	var mode_cell := HBoxContainer.new()
	mode_cell.custom_minimum_size = Vector2(216, 0)
	mode_cell.add_theme_constant_override("separation", 8)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(52, 52)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var swords := GlassIcon.new()
	swords.kind = "swords"
	swords.custom_minimum_size = Vector2(36, 36)
	swords.size = Vector2(36, 36)
	swords.position = Vector2(8, 8)
	swords.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(swords)
	if bool(e["ranked"]):
		var laurel := LaurelBranch.new()
		laurel.set_anchors_preset(Control.PRESET_FULL_RECT)
		laurel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(laurel)
		var laurel2 := LaurelBranch.new()
		laurel2.flip = true
		laurel2.set_anchors_preset(Control.PRESET_FULL_RECT)
		laurel2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(laurel2)
	mode_cell.add_child(icon_box)
	var mode_texts := VBoxContainer.new()
	mode_texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_texts.add_theme_constant_override("separation", 2)
	mode_texts.add_child(_label("Đấu Hạng" if bool(e["ranked"]) else "Đấu Thường",
			19, Color.WHITE))
	mode_texts.add_child(_label(_rel_time(int(e["at"])), 14, Color(0.72, 0.76, 0.86)))
	mode_cell.add_child(mode_texts)
	row.add_child(mode_cell)
	# --- result cell
	var result_cell := VBoxContainer.new()
	result_cell.custom_minimum_size = Vector2(238, 0)
	result_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	result_cell.add_theme_constant_override("separation", 2)
	if won:
		var win_row := HBoxContainer.new()
		win_row.alignment = BoxContainer.ALIGNMENT_CENTER
		win_row.add_theme_constant_override("separation", 2)
		var lb1 := LaurelBranch.new()
		lb1.custom_minimum_size = Vector2(34, 40)
		win_row.add_child(lb1)
		win_row.add_child(_label("Chiến Thắng", 23, Color(1, 0.85, 0.4)))
		var lb2 := LaurelBranch.new()
		lb2.flip = true
		lb2.custom_minimum_size = Vector2(34, 40)
		win_row.add_child(lb2)
		result_cell.add_child(win_row)
	else:
		var banner := PanelContainer.new()
		banner.add_theme_stylebox_override("panel",
				_sb(Color(0.3, 0.05, 0.06, 0.85), 6, Color(0.9, 0.3, 0.25, 0.6), 1))
		banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var bl := _label("Thất Bại", 21, Color(1, 0.5, 0.42))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.add_child(bl)
		result_cell.add_child(banner)
	if bool(e["ranked"]):
		var sd := int(e["star_delta"])
		var sd_txt := ""
		if sd > 0:
			sd_txt = "+%d sao" % sd
			# Label the delta from the server's composition
			# flags (13i); records banked before flags existed
			# fall back to the old streak reading.
			var parts: Array = []
			if bool(e.get("star_bonus", false)):
				parts.append("chuỗi thắng")
			if bool(e.get("daily_bonus", false)):
				parts.append("thưởng ngày")
			if parts.is_empty() and sd >= 2:
				parts.append("chuỗi thắng")
			if not parts.is_empty():
				sd_txt += " (" + " + ".join(parts) + ")"
		elif sd < 0:
			sd_txt = "%d sao" % sd
		else:
			sd_txt = "Không đổi sao"
		var sdl := _label(sd_txt, 14, Color(1, 0.9, 0.6))
		sdl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		result_cell.add_child(sdl)
	row.add_child(result_cell)
	# --- map cell
	var map_cell := HBoxContainer.new()
	map_cell.custom_minimum_size = Vector2(224, 0)
	map_cell.add_theme_constant_override("separation", 8)
	var chip := MapChip.new()
	chip.biome = String(e["biome"]) if String(e["biome"]) != "" else "grassland"
	chip.custom_minimum_size = Vector2(64, 52)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	map_cell.add_child(chip)
	var map_name := "—"
	if String(e["biome"]) != "":
		map_name = "%s · %s" % [HIST_BIOMES.get(String(e["biome"]), String(e["biome"])),
				HIST_LAYOUTS.get(String(e["layout"]), String(e["layout"]))]
	var ml := _label(map_name, 15, Color(0.93, 0.93, 0.9))
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.custom_minimum_size = Vector2(146, 0)
	map_cell.add_child(ml)
	row.add_child(map_cell)
	# --- players cell
	var players_cell := VBoxContainer.new()
	players_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	players_cell.add_theme_constant_override("separation", 2)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 7)
	var players: Array = e["players"]
	for i in range(mini(4, players.size())):
		var p: Dictionary = players[i]
		chips.add_child(_player_chip(String(p.get("name", "?")),
				int(p.get("team", 0))))
	players_cell.add_child(chips)
	if bool(e["ranked"]) and String(e["rank_to"]) != "":
		players_cell.add_child(_label("Hạng sau trận: %s" % String(e["rank_to"]),
				12, Color(1, 0.9, 0.6)))
	row.add_child(players_cell)
	# --- replay button (13h): gold when a recording exists,
	# greyed with an explanatory tooltip when it does not.
	var rid := String(e["replay_id"])
	var play := Button.new()
	play.custom_minimum_size = Vector2(48, 48)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if rid != "":
		play.add_theme_stylebox_override("normal",
				_sb(Color(0.85, 0.64, 0.25, 0.25), 24, Color(1, 0.82, 0.35, 0.9), 2))
		play.add_theme_stylebox_override("hover",
				_sb(Color(0.85, 0.64, 0.25, 0.45), 24, Color(1, 0.82, 0.35), 1))
		play.tooltip_text = "Xem lại trận đấu"
		play.pressed.connect(func() -> void: _on_replay_pressed(rid))
	else:
		play.disabled = true
		play.modulate = Color(1, 1, 1, 0.35)
		play.add_theme_stylebox_override("disabled",
				_sb(Color(0, 0, 0, 0.25), 24, Color(1, 1, 1, 0.2), 1))
		play.tooltip_text = "Không có bản ghi lại"
	var pic := GlassIcon.new()
	pic.kind = "play"
	pic.custom_minimum_size = Vector2(26, 26)
	pic.size = Vector2(26, 26)
	pic.position = Vector2(11, 11)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play.add_child(pic)
	row.add_child(play)
	# --- details button
	var det := Button.new()
	det.custom_minimum_size = Vector2(48, 48)
	det.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	det.add_theme_stylebox_override("normal",
			_sb(Color(0, 0, 0, 0.25), 9, Color(1, 1, 1, 0.35), 1))
	det.add_theme_stylebox_override("hover",
			_sb(Color(1, 0.85, 0.4, 0.18), 9, Color(1, 0.85, 0.4, 0.6), 1))
	var dic := GlassIcon.new()
	dic.kind = "list"
	dic.custom_minimum_size = Vector2(26, 26)
	dic.size = Vector2(26, 26)
	dic.position = Vector2(11, 11)
	dic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	det.add_child(dic)
	var entry := e
	det.pressed.connect(func() -> void: _show_history_detail(entry))
	row.add_child(det)
	return card


func _player_chip(pname: String, team: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(52, 62)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
			_sb(Color(0, 0, 0, 0.3), 5, Color(1, 0.85, 0.4, 0.65), 1))
	frame.custom_minimum_size = Vector2(46, 46)
	frame.size = Vector2(46, 46)
	frame.position = Vector2(3, 0)
	box.add_child(frame)
	var av := TextureRect.new()
	av.texture = load("res://assets/king_avatar.png")
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.custom_minimum_size = Vector2(42, 42)
	av.size = Vector2(42, 42)
	av.position = Vector2(5, 2)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(av)
	var strip := ColorRect.new()
	strip.color = HIST_TEAM_COLORS[clampi(team, 0, 3)]
	strip.custom_minimum_size = Vector2(46, 4)
	strip.size = Vector2(46, 4)
	strip.position = Vector2(3, 42)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(strip)
	var nm := _label(pname, 10, Color(0.9, 0.9, 0.88))
	nm.custom_minimum_size = Vector2(52, 14)
	nm.size = Vector2(52, 14)
	nm.position = Vector2(0, 48)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(nm)
	return box


var _replay_pending: Dictionary = {}


func _on_replay_pressed(rid: String) -> void:
	if not Net.connected:
		_replay_msg("Chưa kết nối",
				"Chưa kết nối máy chủ. Hãy mở Đấu Hạng hoặc Phòng thường một lần để kết nối rồi quay lại.", {})
		return
	_replay_msg("Đang tải…", "Đang tải bản ghi lại của trận đấu…", {})
	Net.fetch_replay(rid)


func _on_replay_data(rp: Dictionary) -> void:
	if String(rp.get("game_version", "")) != Net.GAME_VERSION:
		_replay_pending = rp
		_replay_msg("Bản ghi phiên bản cũ",
				"Replay thuộc phiên bản game cũ, có thể không chính xác. Bạn vẫn muốn xem?", rp)
		return
	_start_replay(rp)


func _start_replay(rp: Dictionary) -> void:
	_hist_detail.visible = false
	if game != null and game.has_method("start_replay"):
		game.start_replay(rp)


## Small message/confirm card over the history panel.
func _replay_msg(title: String, body: String, rp: Dictionary) -> void:
	for c in _hist_detail_body.get_children():
		_hist_detail_body.remove_child(c)
		c.queue_free()
	var t := _hist_detail.get_node_or_null("DetailTitle") as Label
	if t != null:
		t.text = title
	_hist_detail_body.add_child(_label(body, 15))
	if not rp.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var watch := Button.new()
		watch.text = "Xem vẫn"
		watch.custom_minimum_size = Vector2(110, 38)
		watch.add_theme_font_size_override("font_size", 15)
		watch.pressed.connect(func() -> void: _start_replay(rp))
		row.add_child(watch)
		var cancel := Button.new()
		cancel.text = "Huỷ"
		cancel.custom_minimum_size = Vector2(90, 38)
		cancel.add_theme_font_size_override("font_size", 15)
		cancel.pressed.connect(func() -> void: _hist_detail.visible = false)
		row.add_child(cancel)
		_hist_detail_body.add_child(row)
	_hist_detail.visible = true


func _show_history_detail(e: Dictionary) -> void:
	var dt := _hist_detail.get_node_or_null("DetailTitle") as Label
	if dt != null:
		dt.text = "Chi Tiết Trận"
	for c in _hist_detail_body.get_children():
		_hist_detail_body.remove_child(c)
		c.queue_free()
	var b := _hist_detail_body
	b.add_child(_label("Kết quả: %s" % ("Chiến Thắng" if bool(e["won"]) else "Thất Bại"),
			17, Color(1, 0.87, 0.45) if bool(e["won"]) else Color(1, 0.55, 0.48)))
	b.add_child(_label("Chế độ: %s" % ("Đấu Hạng" if bool(e["ranked"]) else "Đấu Thường"), 15))
	b.add_child(_label("Thời gian: %s" % _fmt_date(int(e["at"])), 15))
	var ticks := int(e["duration_ticks"])
	if ticks > 0:
		var secs := ticks / 10
		b.add_child(_label("Thời lượng: %d:%02d" % [secs / 60, secs % 60], 15))
	if String(e["biome"]) != "":
		b.add_child(_label("Bản đồ: %s · %s" % [
				HIST_BIOMES.get(String(e["biome"]), String(e["biome"])),
				HIST_LAYOUTS.get(String(e["layout"]), String(e["layout"]))], 15))
	if bool(e["ranked"]):
		b.add_child(_label("Hạng: %s → %s" % [String(e["rank_from"]),
				String(e["rank_to"])], 15))
	b.add_child(_label("Người chơi:", 15, Color(1, 0.87, 0.45)))
	var team_names := ["Đỏ", "Xanh dương", "Xanh lá", "Vàng"]
	var seen_teams: Dictionary = {}
	for p in e["players"]:
		var t := int(p.get("team", 0))
		if not seen_teams.has(t):
			seen_teams[t] = seen_teams.size()
	for p in e["players"]:
		var t := int(p.get("team", 0))
		b.add_child(_label("· %s — đội %s" % [String(p.get("name", "?")),
				team_names[clampi(t, 0, 3)]], 15))
	_hist_detail.visible = true
