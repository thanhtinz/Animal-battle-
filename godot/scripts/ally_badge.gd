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
const ASPECT := 1.02 # the banner hangs portrait; box stays ~square

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
		var cx := w * 0.5
		# --- cloth geometry: a hanging pennant banner —
		# straight sides, then diagonals to a bottom point,
		# top edge sagging slightly between its loops.
		var hw := w * 0.335
		var y_t := h * 0.155
		var y_b := h * 0.985
		var y_s := y_t + (y_b - y_t) * 0.70
		var sag := h * 0.028
		var centroid := Vector2(cx, y_t + (y_b - y_t) * 0.45)
		var cloth_pts := PackedVector2Array([
			Vector2(cx - hw, y_t), Vector2(cx, y_t + sag),
			Vector2(cx + hw, y_t), Vector2(cx + hw, y_s),
			Vector2(cx, y_b), Vector2(cx - hw, y_s)])
		# --- gold trim: the same pennant pushed outward.
		var trim := clampf(w * 0.05, 2.0, 6.0)
		var trim_pts := PackedVector2Array()
		for p in cloth_pts:
			var d := p - centroid
			trim_pts.append(p + d.normalized() * trim)
		draw_colored_polygon(trim_pts, Color(0.80, 0.58, 0.16))
		# --- cloth: vertical strips clipped to the pennant,
		# shaded as soft folds, darkening toward the point.
		var strips := 14
		for i in strips:
			var t0 := float(i) / strips
			var t1 := float(i + 1) / strips
			var xa := cx - hw + 2.0 * hw * t0
			var xb := cx - hw + 2.0 * hw * t1
			var top_a := y_t + sag * (1.0 - absf(t0 * 2.0 - 1.0))
			var top_b := y_t + sag * (1.0 - absf(t1 * 2.0 - 1.0))
			var bot_a := y_s + (y_b - y_s) * (1.0 - absf(t0 * 2.0 - 1.0))
			var bot_b := y_s + (y_b - y_s) * (1.0 - absf(t1 * 2.0 - 1.0))
			var shade := clampf(0.85 + 0.19 * cos(t0 * 5.5 + 0.6), 0.68, 1.06)
			var col := Color(minf(base.r * shade, 1.0),
					minf(base.g * shade, 1.0), minf(base.b * shade, 1.0))
			draw_colored_polygon(PackedVector2Array([
				Vector2(xa, top_a), Vector2(xb, top_b),
				Vector2(xb, bot_b), Vector2(xa, bot_a)]), col)
		# Soft sheen across the upper cloth.
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - hw, y_t + sag * 0.4),
			Vector2(cx + hw * 0.2, y_t + sag),
			Vector2(cx + hw * 0.2, y_t + (y_s - y_t) * 0.52),
			Vector2(cx - hw, y_t + (y_s - y_t) * 0.34)]),
				Color(1, 1, 1, 0.08))
		# Light-gold inner line along the trim's inner edge.
		var edge := cloth_pts
		edge.append(cloth_pts[0])
		draw_polyline(edge, Color(1.0, 0.86, 0.48, 0.8), 1.2)
		# --- hanging loops over the bar.
		var loop_w := hw * 0.30
		var bar_y := h * 0.085
		for sgn in [-1.0, 1.0]:
			var lx: float = cx + sgn * hw * 0.82
			var lcol := Color(base.r * 0.78, base.g * 0.78, base.b * 0.78)
			draw_rect(Rect2(lx - loop_w * 0.5, bar_y - h * 0.012,
					loop_w, y_t - bar_y + h * 0.03), lcol)
			draw_line(Vector2(lx - loop_w * 0.5, y_t + h * 0.018),
					Vector2(lx + loop_w * 0.5, y_t + h * 0.018),
					Color(0, 0, 0, 0.25), 1.2)
		# --- the gold crossbar + diamond finials.
		var bar_h := clampf(h * 0.07, 3.0, 8.0)
		var bar_x0 := w * 0.045
		var bar_x1 := w * 0.955
		draw_rect(Rect2(bar_x0, bar_y - bar_h * 0.5, bar_x1 - bar_x0, bar_h * 0.38),
				Color(1.0, 0.87, 0.45))
		draw_rect(Rect2(bar_x0, bar_y - bar_h * 0.12, bar_x1 - bar_x0, bar_h * 0.40),
				Color(0.85, 0.62, 0.18))
		draw_rect(Rect2(bar_x0, bar_y + bar_h * 0.28, bar_x1 - bar_x0, bar_h * 0.24),
				Color(0.55, 0.38, 0.08))
		for sgn in [-1.0, 1.0]:
			var fx := bar_x0 if sgn < 0.0 else bar_x1
			var fd := clampf(w * 0.085, 4.0, 11.0)
			var dir: float = sgn
			draw_colored_polygon(PackedVector2Array([
				Vector2(fx, bar_y - fd * 0.62),
				Vector2(fx + dir * fd, bar_y),
				Vector2(fx, bar_y + fd * 0.10)]), Color(1.0, 0.85, 0.42))
			draw_colored_polygon(PackedVector2Array([
				Vector2(fx, bar_y + fd * 0.10),
				Vector2(fx + dir * fd, bar_y),
				Vector2(fx, bar_y + fd * 0.62)]), Color(0.62, 0.44, 0.10))
		# --- the icon printed BLACK on the cloth (owner:
		# the icons are black; the colour is the flag's).
		var share := 0.60 if h > 44.0 else 0.70
		var iw := 2.0 * hw * share
		var icy := y_t + (y_s - y_t) * 0.44
		var rect := Rect2(cx - iw * 0.5, icy - iw * 0.5, iw, iw)
		var tex := AllyBadge.icon_texture(icon)
		if tex != null:
			draw_texture_rect(tex, Rect2(rect.position + Vector2(0.8, 1.1), rect.size),
					false, Color(1, 1, 1, 0.16))
			draw_texture_rect(tex, rect, false, Color(0.05, 0.05, 0.07))
