class_name RankBadge
extends Control
## Seasonal-rank badge (P4 stage 4): Tín's painted winged-shield
## emblem (one texture per tier, sliced from his emblem sheet by
## gen/rank_emblems_build.py) plus a row of drawn star polygons for
## the division's stars. The emblem replaces the old procedurally
## tinted shield; the public API (setup / tier_color) is unchanged
## so every consumer — lobby rank panel + queue, leaderboard rows,
## home profile chip, Thành Tích — upgraded at once.
##
## Tier colour language (server ladder order, rank.go) — kept for
## text accents and star colours only:
## Tân Binh leather brown · Chiến Binh iron grey · Kỵ Sĩ steel
## silver-blue · Nam Tước bronze-green · Bá Tước purple · Hầu
## Tước deep crimson · Công Tước gold · Hoàng Đế radiant red-gold.

const TIER_COLORS: Array[Color] = [
	Color(0.55, 0.38, 0.22), # 0 Tân Binh
	Color(0.52, 0.54, 0.58), # 1 Chiến Binh
	Color(0.62, 0.72, 0.86), # 2 Kỵ Sĩ
	Color(0.36, 0.62, 0.46), # 3 Nam Tước
	Color(0.62, 0.42, 0.87), # 4 Bá Tước
	Color(0.68, 0.16, 0.26), # 5 Hầu Tước
	Color(0.96, 0.76, 0.26), # 6 Công Tước
	Color(1.00, 0.46, 0.16), # 7 Hoàng Đế
]
const RIM := Color(0.30, 0.22, 0.10)
const STAR_ON := Color(1.0, 0.82, 0.30)
const STAR_OFF := Color(1, 1, 1, 0.16)

## Emblem textures, ladder order. Hoàng Đế (the computed top-50
## status) maps to tier 7, the most ornate emblem.
const EMBLEMS: Array[Texture2D] = [
	preload("res://assets/rank_emblems/tier_0.png"),
	preload("res://assets/rank_emblems/tier_1.png"),
	preload("res://assets/rank_emblems/tier_2.png"),
	preload("res://assets/rank_emblems/tier_3.png"),
	preload("res://assets/rank_emblems/tier_4.png"),
	preload("res://assets/rank_emblems/tier_5.png"),
	preload("res://assets/rank_emblems/tier_6.png"),
	preload("res://assets/rank_emblems/tier_7.png"),
]
## All emblems share one canvas, so the aspect is uniform.
const EMBLEM_ASPECT := 174.0 / 219.0

var tier: int = 0
var stars: int = 0
var star_cap: int = 3 # 0 = unbounded (Công Tước: one star glyph, count lives in the text)
var emperor: bool = false
var mini: bool = false # emblem only, for leaderboard rows

static func tier_color(p_tier: int, p_emperor: bool = false) -> Color:
	if p_emperor:
		return TIER_COLORS[7]
	return TIER_COLORS[clampi(p_tier, 0, 6)]


static func emblem_texture(p_tier: int, p_emperor: bool = false) -> Texture2D:
	if p_emperor:
		return EMBLEMS[7]
	return EMBLEMS[clampi(p_tier, 0, 7)]


func setup(p_tier: int, p_stars: int, p_cap: int, p_emperor: bool = false, p_mini: bool = false) -> void:
	tier = p_tier
	stars = p_stars
	star_cap = p_cap
	emperor = p_emperor
	mini = p_mini
	if mini:
		custom_minimum_size = Vector2(19, 22)
	else:
		var n := star_cap if star_cap > 0 else 1
		custom_minimum_size = Vector2(27 + 5 + n * 12, 33)
	queue_redraw()


func _star_count() -> int:
	return star_cap if star_cap > 0 else 1


func _filled() -> int:
	return stars if star_cap > 0 else 1


func _draw() -> void:
	var tex := emblem_texture(tier, emperor)
	if mini:
		# Fit the emblem into the mini box, aspect preserved,
		# centred — row badges stay the same visual height.
		var box := Vector2(19, 22)
		var h := box.y
		var w := h * EMBLEM_ASPECT
		if w > box.x:
			w = box.x
			h = w / EMBLEM_ASPECT
		draw_texture_rect(tex,
				Rect2(Vector2((box.x - w) * 0.5, (box.y - h) * 0.5),
						Vector2(w, h)), false)
		return
	# Full badge: emblem at the left (the old shield's slot),
	# star row to its right, layout unchanged.
	var eh := 33.0
	var ew := eh * EMBLEM_ASPECT
	draw_texture_rect(tex, Rect2(Vector2(0.5, 0), Vector2(ew, eh)), false)
	var n := _star_count()
	var filled := _filled()
	for i in n:
		var sc := Vector2(32 + 6 + i * 12, 16.5)
		draw_colored_polygon(_star_points(sc, 5.2),
				STAR_ON if i < filled else STAR_OFF)


func _star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + i * PI / 5.0
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	return pts
