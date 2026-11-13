class_name AllyBadge
extends RefCounted

## Empire Age 17e addendum — alliance badge = ICON + COLOUR.
## 17f §1 (owner: "icon liên minh phải in lên lá cờ chứ"):
## the badge now renders as the white icon PRINTED ON A
## WAVING FLAG of the badge colour — a wooden pole with a
## gold finial, cloth drawn as vertical strips with a sine
## wave + per-strip shading folds, the icon centred on the
## cloth with a soft drop shadow so it stays readable on
## bright cloths (yellow/pink). `make(icon, color_idx, px)`
## returns the flag Control: px is its HEIGHT, the width is
## ~1.3× (flag + pole ≈ 4:3). The picker GRID still uses the
## plain tinted icon (icon_texture) — only display surfaces
## and the picker PREVIEW are flags.

const NAMES := {
	1: "Sư Tử", 2: "Rồng", 3: "Phượng Hoàng", 4: "Sói",
	5: "Đầu Lâu", 6: "Kiếm Cánh", 7: "Anh Đào", 8: "Trúc",
	9: "Đinh Ba", 10: "Bánh Răng",
}
const COUNT := 10
const ASPECT := 1.30 # width / height of the flag control

static var _cache: Dictionary = {}


static func icon_id(v: int) -> int:
	return v if v >= 1 and v <= COUNT else 1


static func icon_texture(icon: int) -> Texture2D:
	var id := icon_id(icon)
	if _cache.has(id):
		return _cache[id]
	var t: Texture2D = load("res://assets/alliance_icons/icon_%02d.png" % id)
	_cache[id] = t
	return t


static func color_of(color_idx: int) -> Color:
	return TeamColors.ui_color(clampi(color_idx, 0, 7))


static func icon_name(icon: int) -> String:
	return String(NAMES.get(icon_id(icon), "Sư Tử"))


## The flag badge: height px, width ≈ px × ASPECT.
static func make(icon: int, color_idx: int, px: int) -> Control:
	var f := FlagBadge.new()
	f.set_badge(icon_id(icon), clampi(color_idx, 0, 7))
	f.custom_minimum_size = Vector2(roundf(px * ASPECT), px)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


class FlagBadge:
	extends Control

	## One waving alliance flag (see the file header). Drawn
	## entirely in _draw from (icon, color_idx); set_badge
	## repaints in place (the picker preview uses it).

	var icon: int = 1
	var color_idx: int = 0

	func set_badge(p_icon: int, p_color: int) -> void:
		icon = AllyBadge.icon_id(p_icon)
		color_idx = clampi(p_color, 0, 7)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 8.0 or h < 8.0:
			return
		var base := AllyBadge.color_of(color_idx)
		var x0 := w * 0.075 + clampf(w * 0.045, 2.0, 5.0) * 0.5
		var x1 := w * 0.985
		var y0 := h * 0.13
		var ch := h * 0.60
		var amp := ch * 0.10
		var phase := 0.7
		# Wave grows toward the fly end; the bottom edge gets
		# a touch more travel so the cloth sags like fabric.
		var wave := func(t: float) -> float:
			return sin(phase + t * 5.2) * amp * (0.30 + 0.70 * t)
		# --- soft drop shadow of the whole cloth.
		var shadow_pts := PackedVector2Array()
		for i in 9:
			var tt := float(i) / 8.0
			shadow_pts.append(Vector2(x0 + (x1 - x0) * tt + w * 0.02,
					y0 + wave.call(tt) + h * 0.035))
		for i in range(8, -1, -1):
			var tt := float(i) / 8.0
			shadow_pts.append(Vector2(x0 + (x1 - x0) * tt + w * 0.02,
					y0 + ch + wave.call(tt) * 1.15 + h * 0.035))
		draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.20))
		# --- cloth: 18 strips, fold shading follows the
		# wave's slope with real contrast (never flat).
		var strips := 18
		var sw := (x1 - x0) / strips
		for i in strips:
			var t0 := float(i) / strips
			var t1 := float(i + 1) / strips
			var dy0: float = wave.call(t0)
			var dy1: float = wave.call(t1)
			var slope := cos(phase + (t0 + t1) * 0.5 * 5.2)
			var shade := clampf(0.80 + 0.26 * slope, 0.62, 1.10)
			var col := Color(minf(base.r * shade, 1.0),
					minf(base.g * shade, 1.0), minf(base.b * shade, 1.0))
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0 + sw * i, y0 + dy0),
				Vector2(x0 + sw * (i + 1), y0 + dy1),
				Vector2(x0 + sw * (i + 1), y0 + ch + dy1 * 1.15),
				Vector2(x0 + sw * i, y0 + ch + dy0 * 1.15)]), col)
		# Sheen band across the upper cloth + a deep fold
		# shadow in the lower third, both following the wave.
		for i in strips:
			var t0 := float(i) / strips
			var t1 := float(i + 1) / strips
			var dy0: float = wave.call(t0)
			var dy1: float = wave.call(t1)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0 + sw * i, y0 + dy0 + ch * 0.10),
				Vector2(x0 + sw * (i + 1), y0 + dy1 + ch * 0.10),
				Vector2(x0 + sw * (i + 1), y0 + dy1 + ch * 0.30),
				Vector2(x0 + sw * i, y0 + dy0 + ch * 0.30)]),
					Color(1, 1, 1, 0.10))
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0 + sw * i, y0 + dy0 * 1.15 + ch * 0.78),
				Vector2(x0 + sw * (i + 1), y0 + dy1 * 1.15 + ch * 0.78),
				Vector2(x0 + sw * (i + 1), y0 + ch + dy1 * 1.15),
				Vector2(x0 + sw * i, y0 + ch + dy0 * 1.15)]),
					Color(0, 0, 0, 0.12))
		# --- gold trim along the waving edges + fly end.
		var trim := Color(0.98, 0.80, 0.35, 0.85)
		var trim_w := clampf(h * 0.028, 1.2, 2.4)
		var top_pts := PackedVector2Array()
		var bot_pts := PackedVector2Array()
		for i in 19:
			var tt := float(i) / 18.0
			top_pts.append(Vector2(x0 + (x1 - x0) * tt, y0 + wave.call(tt)))
			bot_pts.append(Vector2(x0 + (x1 - x0) * tt, y0 + ch + wave.call(tt) * 1.15))
		draw_polyline(top_pts, trim, trim_w)
		draw_polyline(bot_pts, trim, trim_w)
		draw_line(Vector2(x1, y0 + wave.call(1.0)),
				Vector2(x1, y0 + ch + wave.call(1.0) * 1.15), trim, trim_w)
		# --- pole over the hoist edge: two-tone wood, gold
		# ball finial with a highlight, small foot.
		var pole_x := w * 0.075
		var pole_w := clampf(w * 0.05, 2.5, 5.5)
		var pole_top := h * 0.10
		draw_rect(Rect2(pole_x - pole_w * 0.5, pole_top, pole_w, h * 0.88),
				Color(0.28, 0.18, 0.09))
		draw_rect(Rect2(pole_x - pole_w * 0.5, pole_top, pole_w * 0.45, h * 0.88),
				Color(0.45, 0.31, 0.16))
		var ball_r := clampf(w * 0.055, 3.0, 6.5)
		draw_circle(Vector2(pole_x, h * 0.075), ball_r, Color(0.98, 0.80, 0.35))
		draw_circle(Vector2(pole_x - ball_r * 0.3, h * 0.075 - ball_r * 0.3),
				ball_r * 0.38, Color(1.0, 0.93, 0.65))
		draw_rect(Rect2(pole_x - w * 0.07, h * 0.965, w * 0.14, maxf(2.0, h * 0.03)),
				Color(0.28, 0.18, 0.09))
		# --- the icon printed on the cloth.
		var share := 0.62 if h > 44.0 else 0.76
		var ih := ch * share
		var iw := ih
		var cx := (x0 + x1) * 0.5
		var cy: float = y0 + ch * 0.5 + float(wave.call(0.5))
		var rect := Rect2(cx - iw * 0.5, cy - ih * 0.5, iw, ih)
		var tex := AllyBadge.icon_texture(icon)
		if tex != null:
			draw_texture_rect(tex, Rect2(rect.position + Vector2(1.2, 1.4), rect.size),
					false, Color(0, 0, 0, 0.30))
			draw_texture_rect(tex, rect, false, Color.WHITE)
