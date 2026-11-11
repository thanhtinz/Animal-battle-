extends Control
## Verification sheet for Tín's rank emblem textures (sliced by
## gen/rank_emblems_build.py, wired into RankBadge): all 8 emblems
## LARGE on the game's dark navy, tier names underneath, plus two
## rows of the REAL RankBadge controls at production sizes — full
## badges (emblem + star row) and mini badges (leaderboard rows) —
## so legibility is judged at the sizes the game actually uses.
## Run under Xvfb like the other capture scenes.

const NAMES := ["Tân Binh", "Chiến Binh", "Kỵ Sĩ", "Nam Tước",
		"Bá Tước", "Hầu Tước", "Công Tước", "Hoàng Đế"]


func _label(text: String, pos: Vector2, size_px: int = 15) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color(0.92, 0.93, 0.97))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.17)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Row A — the 8 emblem textures, large.
	var ew := 150.0
	var eh := ew / RankBadge.EMBLEM_ASPECT
	var gap := (1152.0 - 8.0 * ew) / 9.0
	for i in 8:
		var tr := TextureRect.new()
		tr.texture = RankBadge.emblem_texture(i)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(gap + i * (ew + gap), 30)
		tr.size = Vector2(ew, eh)
		add_child(tr)
		_label(NAMES[i], Vector2(gap + i * (ew + gap) + 8, 30 + eh + 8), 16)

	# Row B — real RankBadge controls, full size (2 stars filled).
	_label("RankBadge thường (BXH lớn / sảnh / Thành Tích):", Vector2(24, 300), 15)
	for i in 8:
		var b := RankBadge.new()
		b.setup(i, 2, 3, i == 7)
		b.position = Vector2(24 + i * 140, 330)
		add_child(b)

	# Row C — real RankBadge controls, mini size (leaderboard rows).
	_label("RankBadge mini (dòng BXH / bạn bè):", Vector2(24, 400), 15)
	for i in 8:
		var b := RankBadge.new()
		b.setup(i, 0, 3, i == 7, true)
		b.position = Vector2(24 + i * 60, 430)
		add_child(b)

	# Row D — the mini badge at lobby-row height next to a name, as
	# it actually appears (19x22 box over a glass row strip).
	_label("Ghép thử trong dòng:", Vector2(24, 500), 15)
	var strip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.24, 0.9)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	strip.add_theme_stylebox_override("panel", sb)
	strip.position = Vector2(24, 528)
	strip.size = Vector2(330, 34)
	add_child(strip)
	var mb := RankBadge.new()
	mb.setup(7, 0, 3, true, true)
	mb.position = Vector2(36, 534)
	add_child(mb)
	_label("HoangDe · Hoàng Đế · MMR 2.130", Vector2(64, 536), 15)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_rank_emblems_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_rank_emblems_v1.png size=", img.get_size())
	get_tree().quit()
