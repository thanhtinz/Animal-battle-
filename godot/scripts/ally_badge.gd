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
		# --- pole: dark wood + gold finial + a small foot.
		var pole_x := w * 0.075
		var pole_w := clampf(w * 0.045, 2.0, 5.0)
		var pole_top := h * 0.10
		draw_rect(Rect2(pole_x - pole_w * 0.5, pole_top, pole_w, h * 0.88),
				Color(0.30, 0.20, 0.10))
		draw_rect(Rect2(pole_x - pole_w * 0.5, pole_top, pole_w * 0.45, h * 0.88),
				Color(0.42, 0.29, 0.15))
		draw_circle(Vector2(pole_x, h * 0.075), clampf(w * 0.05, 2.5, 6.0),
				Color(0.98, 0.80, 0.35))
		draw_rect(Rect2(pole_x - w * 0.07, h * 0.965, w * 0.14, maxf(2.0, h * 0.03)),
				Color(0.30, 0.20, 0.10))
		# --- cloth: vertical strips on a sine wave, each
		# strip shaded by the wave's slope so the cloth reads
		# as folded fabric, never a flat rectangle.
		var x0 := pole_x + pole_w * 0.5
		var x1 := w * 0.985
		var y0 := h * 0.13
		var ch := h * 0.60
		var amp := ch * 0.055
		var strips := 14
		var sw := (x1 - x0) / strips
		var phase := 0.7
		var wave := func(t: float) -> float:
			return sin(phase + t * 4.6) * amp * (0.35 + 0.65 * t)
		for i in strips:
			var t0 := float(i) / strips
			var t1 := float(i + 1) / strips
			var dy0: float = wave.call(t0)
			var dy1: float = wave.call(t1)
			var shade := 0.86 + 0.14 * cos(phase + (t0 + t1) * 0.5 * 4.6)
			var col := Color(base.r * shade, base.g * shade, base.b * shade)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0 + sw * i, y0 + dy0),
				Vector2(x0 + sw * (i + 1), y0 + dy1),
				Vector2(x0 + sw * (i + 1), y0 + ch + dy1 * 1.12),
				Vector2(x0 + sw * i, y0 + ch + dy0 * 1.12)]), col)
		# A darker fold line a third across the cloth.
		var fx := x0 + (x1 - x0) * 0.36
		var fdy: float = wave.call(0.36)
		draw_line(Vector2(fx, y0 + fdy + 1.0),
				Vector2(fx, y0 + ch + fdy * 1.12 - 1.0),
				Color(0, 0, 0, 0.16), clampf(w * 0.03, 1.5, 3.5))
		# Cloth outline (top/bottom follow the wave coarsely).
		var edge := Color(0, 0, 0, 0.22)
		draw_line(Vector2(x0, y0 + wave.call(0.0)), Vector2(x1, y0 + wave.call(1.0)), edge, 1.2)
		draw_line(Vector2(x0, y0 + ch + wave.call(0.0) * 1.12),
				Vector2(x1, y0 + ch + wave.call(1.0) * 1.12), edge, 1.2)
		# --- the icon printed on the cloth: soft shadow pass
		# then the white glyph. Small flags give the glyph a
		# bigger share of the cloth so it survives at 30px.
		var share := 0.62 if h > 44.0 else 0.76
		var ih := ch * share
		var iw := ih # icons are square silhouettes
		var cx := (x0 + x1) * 0.5
		var cy: float = y0 + ch * 0.5 + float(wave.call(0.5))
		var rect := Rect2(cx - iw * 0.5, cy - ih * 0.5, iw, ih)
		var tex := AllyBadge.icon_texture(icon)
		if tex != null:
			draw_texture_rect(tex, Rect2(rect.position + Vector2(1.2, 1.4), rect.size),
					false, Color(0, 0, 0, 0.30))
			draw_texture_rect(tex, rect, false, Color.WHITE)
