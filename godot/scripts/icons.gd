class_name GlassIcon
extends Control
## Code-drawn HUD icons (no emoji, no textures). Drawn in a 24x24 logical
## space and scaled to the control's size. Set `kind` before adding to tree.
## Dim an icon by setting `modulate` on this control (parents do that).

var kind: String = "dots":
	set(v):
		kind = v
		queue_redraw()

## Ping band for kind "signal_meter" (the glyph IS the meter):
## 0 = bad — base dot red, arcs grey; 1 = medium — base dot
## yellow, arcs grey; 2 = good — the WHOLE glyph green.
var signal_band: int = 0:
	set(v):
		signal_band = v
		queue_redraw()

const LIGHT := Color(0.93, 0.95, 0.98)
const GOLD := Color(0.92, 0.72, 0.3)
const GOLD_LIGHT := Color(0.98, 0.83, 0.4)
const STEEL := Color(0.8, 0.85, 0.92)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _p(x: float, y: float) -> Vector2:
	return Vector2(x * size.x / 24.0, y * size.y / 24.0)


func _w(f: float) -> float:
	return f * minf(size.x, size.y) / 24.0


func _poly(pts: Array, col: Color) -> void:
	var packed := PackedVector2Array()
	for pt in pts:
		packed.append(_p(pt.x, pt.y))
	draw_colored_polygon(packed, col)


func _line(pts: Array, col: Color, width: float, closed: bool = false) -> void:
	var packed := PackedVector2Array()
	for pt in pts:
		packed.append(_p(pt.x, pt.y))
	if closed and packed.size() > 2:
		packed.append(packed[0])
	draw_polyline(packed, col, _w(width))


func _circ(x: float, y: float, r: float, col: Color) -> void:
	draw_circle(_p(x, y), r * minf(size.x, size.y) / 24.0, col)


func _arc(x: float, y: float, r: float, col: Color, width: float) -> void:
	draw_arc(_p(x, y), r * minf(size.x, size.y) / 24.0, 0, TAU, 24, col, _w(width))


func _arc_span(x: float, y: float, r: float, a0: float, a1: float, col: Color, width: float) -> void:
	draw_arc(_p(x, y), r * minf(size.x, size.y) / 24.0, a0, a1, 20, col, _w(width))


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	match kind:
		"emblem":
			_poly([Vector2(12, 2.5), Vector2(19, 4.8), Vector2(19, 11.5), Vector2(12, 21.5), Vector2(5, 11.5), Vector2(5, 4.8)], Color(0.16, 0.3, 0.62))
			_line([Vector2(12, 2.5), Vector2(19, 4.8), Vector2(19, 11.5), Vector2(12, 21.5), Vector2(5, 11.5), Vector2(5, 4.8)], GOLD_LIGHT, 1.4, true)
			_poly([Vector2(12, 6.8), Vector2(15.6, 11), Vector2(12, 17.2), Vector2(8.4, 11)], GOLD)
		"food": # drumstick
			_circ(10.5, 10, 5.6, Color(0.74, 0.38, 0.2))
			_circ(13.5, 6.8, 4.0, Color(0.8, 0.44, 0.24))
			_line([Vector2(14.5, 14.5), Vector2(18.6, 18.6)], Color(0.94, 0.9, 0.8), 2.6)
			_circ(19.6, 17.2, 1.9, Color(0.94, 0.9, 0.8))
			_circ(17.2, 19.6, 1.9, Color(0.94, 0.9, 0.8))
		"wood": # log
			draw_rect(Rect2(_p(6.5, 7), _p(19, 17) - _p(6.5, 7)), Color(0.48, 0.33, 0.17))
			_line([Vector2(8, 10), Vector2(18.5, 10)], Color(0.4, 0.26, 0.12), 1.4)
			_circ(6.5, 12, 5.0, Color(0.8, 0.62, 0.38))
			_arc(6.5, 12, 3.1, Color(0.55, 0.38, 0.18), 1.3)
			_circ(6.5, 12, 1.2, Color(0.55, 0.38, 0.18))
		"gold": # ingots
			_poly([Vector2(3.5, 15), Vector2(10.5, 15), Vector2(9.2, 19.5), Vector2(4.8, 19.5)], GOLD)
			_poly([Vector2(13.5, 15), Vector2(20.5, 15), Vector2(19.2, 19.5), Vector2(14.8, 19.5)], GOLD)
			_poly([Vector2(8.5, 8.5), Vector2(15.5, 8.5), Vector2(14.2, 13), Vector2(9.8, 13)], GOLD_LIGHT)
		"stone": # rocks
			_poly([Vector2(3.5, 18.5), Vector2(5.5, 10.5), Vector2(11.5, 7), Vector2(17.5, 10.5), Vector2(19.5, 18.5)], Color(0.62, 0.63, 0.66))
			_line([Vector2(5.5, 10.5), Vector2(10, 13), Vector2(15, 11)], Color(0.78, 0.79, 0.82), 1.3)
			_poly([Vector2(14.5, 19.5), Vector2(16.5, 14), Vector2(21, 15.5), Vector2(21.5, 19.5)], Color(0.52, 0.53, 0.57))
		"iron": # steel ingot
			_poly([Vector2(7.5, 6.5), Vector2(16.5, 6.5), Vector2(19.5, 10.5), Vector2(4.5, 10.5)], Color(0.68, 0.75, 0.85))
			_poly([Vector2(4.5, 10.5), Vector2(19.5, 10.5), Vector2(17, 17.5), Vector2(7, 17.5)], Color(0.5, 0.58, 0.7))
			_line([Vector2(7.5, 13.8), Vector2(17, 13.8)], Color(0.72, 0.79, 0.9), 1.4)
		"pop": # two people
			_circ(9, 8.6, 3.3, LIGHT)
			_poly(_arc_pts(9, 17.5, 4.8, PI, TAU), LIGHT)
			_circ(16.8, 10.2, 2.7, Color(0.7, 0.76, 0.85))
			_poly(_arc_pts(16.8, 18.2, 4.0, PI, TAU), Color(0.7, 0.76, 0.85))
		"person": # single bust (13r: form fields)
			_circ(12, 8.2, 3.9, LIGHT)
			_poly(_arc_pts(12, 19.8, 6.4, PI, TAU), LIGHT)
		"lock": # padlock (13r: password field)
			draw_rect(Rect2(_p(5.4, 10.6), _p(18.6, 20.2) - _p(5.4, 10.6)), LIGHT)
			_arc_span(12, 10.8, 4.4, PI, TAU, LIGHT, 2.4)
			_circ(12, 14.6, 1.8, Color(0.16, 0.19, 0.28))
			_line([Vector2(12, 15.6), Vector2(12, 17.8)], Color(0.16, 0.19, 0.28), 1.8)
		"eye": # open eye (13r: password visibility toggle)
			_line([Vector2(3.8, 12), Vector2(6.6, 8.2), Vector2(17.4, 8.2), Vector2(20.2, 12), Vector2(17.4, 15.8), Vector2(6.6, 15.8)], LIGHT, 1.6, true)
			_circ(12, 12, 3.1, LIGHT)
			_circ(12, 12, 1.5, Color(0.16, 0.19, 0.28))
		"eye_off": # eye with a slash (13r)
			_line([Vector2(3.8, 12), Vector2(6.6, 8.2), Vector2(17.4, 8.2), Vector2(20.2, 12), Vector2(17.4, 15.8), Vector2(6.6, 15.8)], Color(0.62, 0.66, 0.74), 1.6, true)
			_circ(12, 12, 3.1, Color(0.62, 0.66, 0.74))
			_line([Vector2(5, 19.5), Vector2(19, 4.5)], Color(1, 0.45, 0.4), 2.2)
		"check": # tick (13r: remember-me box)
			_line([Vector2(4.6, 12.8), Vector2(9.8, 17.8), Vector2(19.4, 6.4)], GOLD_LIGHT, 3.0)
		"swords": # crossed swords
			_line([Vector2(6, 18.5), Vector2(16.8, 7.7)], STEEL, 2.2)
			_line([Vector2(6.2, 13.8), Vector2(10.2, 17.8)], GOLD, 2.2)
			_line([Vector2(18, 18.5), Vector2(7.2, 7.7)], STEEL, 2.2)
			_line([Vector2(17.8, 13.8), Vector2(13.8, 17.8)], GOLD, 2.2)
			_circ(5.4, 19.1, 1.5, GOLD_LIGHT)
			_circ(18.6, 19.1, 1.5, GOLD_LIGHT)
		"chat": # speech bubble
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.9, 0.93, 0.97)
			sb.set_corner_radius_all(int(_w(5)))
			draw_style_box(sb, Rect2(_p(3.5, 4.5), _p(20.5, 16.5) - _p(3.5, 4.5)))
			_poly([Vector2(7, 16.5), Vector2(11, 16.5), Vector2(7.5, 20.5)], Color(0.9, 0.93, 0.97))
			_circ(8, 10.5, 1.4, Color(0.25, 0.3, 0.4))
			_circ(12, 10.5, 1.4, Color(0.25, 0.3, 0.4))
			_circ(16, 10.5, 1.4, Color(0.25, 0.3, 0.4))
		"friends":
			_circ(8.6, 9.4, 3.6, LIGHT)
			_poly(_arc_pts(8.6, 18.6, 5.2, PI, TAU), LIGHT)
			_circ(17.2, 9.4, 3.6, Color(0.62, 0.68, 0.78))
			_poly(_arc_pts(17.2, 18.6, 5.2, PI, TAU), Color(0.62, 0.68, 0.78))
		"gear":
			for i in range(8):
				var a := float(i) * TAU / 8.0
				var d := Vector2(cos(a), sin(a))
				_line([Vector2(12, 12) + d * 4.6, Vector2(12, 12) + d * 8.6], LIGHT, 3.0)
			_arc(12, 12, 5.6, LIGHT, 2.8)
			_circ(12, 12, 2.1, LIGHT)
		"flag":
			_line([Vector2(8, 3.5), Vector2(8, 20.5)], Color(0.9, 0.85, 0.75), 2.0)
			_poly([Vector2(8, 3.8), Vector2(17.5, 6.4), Vector2(8, 9.4)], Color(0.4, 0.6, 1.0))
			_circ(8, 20.8, 1.6, GOLD)
		"crosshair":
			_arc(12, 12, 6.8, LIGHT, 1.9)
			_line([Vector2(12, 1.8), Vector2(12, 5)], LIGHT, 2.0)
			_line([Vector2(12, 19), Vector2(12, 22.2)], LIGHT, 2.0)
			_line([Vector2(1.8, 12), Vector2(5, 12)], LIGHT, 2.0)
			_line([Vector2(19, 12), Vector2(22.2, 12)], LIGHT, 2.0)
			_circ(12, 12, 1.5, Color(1.0, 0.55, 0.4))
		"target": # target rings pierced by an arrow (home: Đấu thường)
			_arc(10.5, 13.5, 7.0, GOLD_LIGHT, 2.0)
			_arc(10.5, 13.5, 3.4, GOLD, 1.8)
			_circ(10.5, 13.5, 1.3, Color(1.0, 0.55, 0.4))
			_line([Vector2(13.2, 10.8), Vector2(20.6, 3.4)], STEEL, 2.2)
			_line([Vector2(20.8, 3.2), Vector2(16.9, 3.4)], GOLD_LIGHT, 2.0)
			_line([Vector2(20.8, 3.2), Vector2(20.6, 7.1)], GOLD_LIGHT, 2.0)
			_line([Vector2(13.4, 10.6), Vector2(10.9, 7.2)], GOLD, 1.8)
		"gift": # present with lid, ribbon and bow (home: thưởng ngày)
			draw_rect(Rect2(_p(5, 10.8), _p(19, 20.5) - _p(5, 10.8)), Color(0.78, 0.27, 0.32))
			draw_rect(Rect2(_p(3.8, 7.8), _p(20.2, 10.8) - _p(3.8, 7.8)), Color(0.88, 0.35, 0.4))
			draw_rect(Rect2(_p(10.9, 7.8), _p(13.1, 20.5) - _p(10.9, 7.8)), GOLD)
			_circ(9.1, 5.7, 2.2, GOLD_LIGHT)
			_circ(14.9, 5.7, 2.2, GOLD_LIGHT)
			_circ(12, 6.9, 1.3, GOLD)
		"layers":
			_line([Vector2(12, 3.5), Vector2(20, 7.8), Vector2(12, 12.1), Vector2(4, 7.8)], GOLD_LIGHT, 1.8, true)
			_line([Vector2(4.5, 12.4), Vector2(12, 16.4), Vector2(19.5, 12.4)], LIGHT, 1.8)
			_line([Vector2(4.5, 16.9), Vector2(12, 20.9), Vector2(19.5, 16.9)], LIGHT, 1.8)
		"house":
			_poly([Vector2(3.5, 11), Vector2(12, 3.8), Vector2(20.5, 11)], Color(0.75, 0.42, 0.22))
			draw_rect(Rect2(_p(6, 11), _p(18, 19.5) - _p(6, 11)), Color(0.88, 0.78, 0.6))
			draw_rect(Rect2(_p(10.4, 14.5), _p(13.6, 19.5) - _p(10.4, 14.5)), Color(0.35, 0.22, 0.12))
		"train": # sword + shield
			_line([Vector2(6.5, 17.5), Vector2(15.5, 8.5)], STEEL, 2.2)
			_line([Vector2(6.8, 12.8), Vector2(10.8, 16.8)], GOLD, 2.0)
			_poly([Vector2(13.5, 12.5), Vector2(19.5, 12.5), Vector2(19.5, 16.5), Vector2(16.5, 20.5), Vector2(13.5, 16.5)], Color(0.2, 0.38, 0.75))
			_line([Vector2(13.5, 12.5), Vector2(19.5, 12.5), Vector2(19.5, 16.5), Vector2(16.5, 20.5), Vector2(13.5, 16.5)], GOLD_LIGHT, 1.2, true)
		"tech": # flask
			draw_rect(Rect2(_p(10.3, 3.5), _p(13.7, 9) - _p(10.3, 3.5)), LIGHT)
			_line([Vector2(9.2, 9), Vector2(14.8, 9), Vector2(19.3, 19.3), Vector2(4.7, 19.3)], LIGHT, 1.8, true)
			_poly([Vector2(7.6, 14.8), Vector2(16.4, 14.8), Vector2(18.6, 19.3), Vector2(5.4, 19.3)], Color(0.35, 0.8, 0.85, 0.85))
		"trophy": # cup with handles + stem (home nav: Thành Tích)
			_poly([Vector2(7, 3.5), Vector2(17, 3.5), Vector2(17, 9), Vector2(12, 12.5), Vector2(7, 9)], GOLD)
			_poly(_arc_pts(6.2, 6.8, 3.4, PI * 0.5, PI * 1.5), GOLD)
			_poly(_arc_pts(17.8, 6.8, 3.4, -PI * 0.5, PI * 0.5), GOLD)
			_line([Vector2(12, 12.5), Vector2(12, 16.5)], GOLD, 2.4)
			draw_rect(Rect2(_p(8.4, 17.6), _p(15.6, 20.2) - _p(8.4, 17.6)), GOLD_LIGHT)
			_poly([Vector2(9.6, 5.4), Vector2(14.4, 5.4), Vector2(14, 8.6), Vector2(10, 8.6)], GOLD_LIGHT)
		"helmet": # crested knight helmet inside a laurel (Đấu Hạng)
			_poly(_arc_pts(12, 11.5, 6.4, PI, TAU), Color(0.42, 0.48, 0.62))
			draw_rect(Rect2(_p(5.6, 11.5), _p(18.4, 13.4) - _p(5.6, 11.5)), Color(0.42, 0.48, 0.62))
			_poly([Vector2(10.6, 5.2), Vector2(13.4, 5.2), Vector2(13, 2.6), Vector2(11, 2.6)], Color(0.85, 0.3, 0.25))
			_line([Vector2(8.6, 13.4), Vector2(8.6, 16.8)], Color(0.13, 0.15, 0.22), 1.7)
			_line([Vector2(12, 13.4), Vector2(12, 16.8)], Color(0.13, 0.15, 0.22), 1.7)
			_line([Vector2(15.4, 13.4), Vector2(15.4, 16.8)], Color(0.13, 0.15, 0.22), 1.7)
			for sgn: float in [-1.0, 1.0]:
				for i in range(3):
					var a := (0.72 - float(i) * 0.34) * PI
					var cx: float = 12.0 + sgn * sin(a) * 9.6
					var cy: float = 13.5 + cos(a) * 8.6 - 1.5
					_circ(cx, cy, 1.45, GOLD)
			_line([Vector2(12, 20.8), Vector2(12, 18.6)], GOLD, 1.6)
		"scroll": # rolled parchment (home nav: Lịch Sử)
			draw_rect(Rect2(_p(6.4, 6), _p(17.6, 18) - _p(6.4, 6)), Color(0.9, 0.8, 0.58))
			_circ(6.4, 6, 2.5, Color(0.78, 0.64, 0.4))
			_circ(6.4, 18, 2.5, Color(0.78, 0.64, 0.4))
			_circ(17.6, 6, 2.5, Color(0.78, 0.64, 0.4))
			_circ(17.6, 18, 2.5, Color(0.78, 0.64, 0.4))
			draw_rect(Rect2(_p(3.9, 3.5), _p(8.9, 8.5) - _p(3.9, 3.5)), Color(0.68, 0.5, 0.26))
			draw_rect(Rect2(_p(15.1, 15.5), _p(20.1, 20.5) - _p(15.1, 15.5)), Color(0.68, 0.5, 0.26))
			_line([Vector2(9.6, 10), Vector2(15.2, 10)], Color(0.6, 0.47, 0.28), 1.5)
			_line([Vector2(9.6, 13.2), Vector2(15.2, 13.2)], Color(0.6, 0.47, 0.28), 1.5)
			_poly([Vector2(13.4, 15.8), Vector2(15.8, 15.8), Vector2(14.6, 18.2)], Color(0.8, 0.3, 0.25))
		"chart": # rising bars (home nav: BXH)
			draw_rect(Rect2(_p(4.4, 13), _p(7.6, 19.6) - _p(4.4, 13)), GOLD)
			draw_rect(Rect2(_p(10.4, 9.4), _p(13.6, 19.6) - _p(10.4, 9.4)), GOLD_LIGHT)
			draw_rect(Rect2(_p(16.4, 5.4), _p(19.6, 19.6) - _p(16.4, 5.4)), GOLD)
			_line([Vector2(3.4, 20.4), Vector2(20.6, 20.4)], LIGHT, 1.7)
		"book": # open book (home nav: Hướng Dẫn)
			_poly([Vector2(12, 6.8), Vector2(6.4, 4.6), Vector2(3.6, 5.6), Vector2(3.6, 18.4), Vector2(6.4, 17.4), Vector2(12, 19.4)], Color(0.93, 0.9, 0.8))
			_poly([Vector2(12, 6.8), Vector2(17.6, 4.6), Vector2(20.4, 5.6), Vector2(20.4, 18.4), Vector2(17.6, 17.4), Vector2(12, 19.4)], Color(0.85, 0.81, 0.7))
			_poly([Vector2(3.6, 5.6), Vector2(6.4, 4.6), Vector2(12, 6.8), Vector2(12, 19.4), Vector2(6.4, 17.4), Vector2(3.6, 18.4)], Color(0.55, 0.36, 0.18))
			_poly([Vector2(20.4, 5.6), Vector2(17.6, 4.6), Vector2(12, 6.8), Vector2(12, 19.4), Vector2(17.6, 17.4), Vector2(20.4, 18.4)], Color(0.45, 0.28, 0.13))
			_line([Vector2(6.2, 8.8), Vector2(10, 10.2)], Color(0.5, 0.42, 0.3), 1.2)
			_line([Vector2(6.2, 12.2), Vector2(10, 13.6)], Color(0.5, 0.42, 0.3), 1.2)
			_line([Vector2(14, 10.2), Vector2(17.8, 8.8)], Color(0.5, 0.42, 0.3), 1.2)
			_line([Vector2(14, 13.6), Vector2(17.8, 12.2)], Color(0.5, 0.42, 0.3), 1.2)
		"mail": # envelope (home top bar: Thư)
			draw_rect(Rect2(_p(3.2, 6), _p(20.8, 18.4) - _p(3.2, 6)), Color(0.93, 0.9, 0.82))
			_poly([Vector2(3.2, 6.4), Vector2(20.8, 6.4), Vector2(12, 13.6)], Color(0.8, 0.74, 0.6))
			_line([Vector2(3.6, 18), Vector2(10.4, 11.8)], Color(0.66, 0.6, 0.46), 1.5)
			_line([Vector2(20.4, 18), Vector2(13.6, 11.8)], Color(0.66, 0.6, 0.46), 1.5)
		"signal": # wifi arcs + dot (ping readout)
			_arc_span(12, 17.5, 9.6, PI * 1.22, PI * 1.78, GOLD_LIGHT, 2.2)
			_arc_span(12, 17.5, 6.4, PI * 1.25, PI * 1.75, GOLD_LIGHT, 2.2)
			_arc_span(12, 17.5, 3.4, PI * 1.28, PI * 1.72, GOLD_LIGHT, 2.2)
			_circ(12, 17.8, 1.7, GOLD_LIGHT)
		"signal_meter": # wifi fan + base dot — Tín's correction:
			# the dot is the fan's BASE point, below the arcs
			# (not above them); the glyph itself is the ping
			# meter — bad: red dot + grey arcs, medium: yellow
			# dot + grey arcs, good: dot AND arcs all green.
			var dot_col := Color(1, 0.4, 0.35) if signal_band == 0 else \
					(Color(1, 0.85, 0.4) if signal_band == 1 else Color(0.45, 0.95, 0.5))
			var arc_col := Color(0.45, 0.95, 0.5) if signal_band == 2 else Color(0.62, 0.66, 0.74)
			_arc_span(12, 17.5, 9.6, PI * 1.22, PI * 1.78, arc_col, 2.2)
			_arc_span(12, 17.5, 6.4, PI * 1.25, PI * 1.75, arc_col, 2.2)
			_arc_span(12, 17.5, 3.4, PI * 1.28, PI * 1.72, arc_col, 2.2)
			_circ(12, 17.8, 1.7, dot_col)
		"dots":
			_circ(5, 12, 2.3, LIGHT)
			_circ(12, 12, 2.3, LIGHT)
			_circ(19, 12, 2.3, LIGHT)
		"back": # bold gold return arrow (board headers)
			_poly([Vector2(12.6, 3.6), Vector2(4.6, 12), Vector2(12.6, 20.4),
					Vector2(16.1, 20.4), Vector2(9.6, 12), Vector2(16.1, 3.6)], GOLD)
			_line([Vector2(12.5, 12), Vector2(20.4, 12)], GOLD, 3.2)
		"list": # details: three ruled lines with bullet dots
			_circ(5.4, 6.4, 1.7, GOLD_LIGHT)
			_circ(5.4, 12, 1.7, GOLD_LIGHT)
			_circ(5.4, 17.6, 1.7, GOLD_LIGHT)
			_line([Vector2(9.4, 6.4), Vector2(20.2, 6.4)], LIGHT, 2.0)
			_line([Vector2(9.4, 12), Vector2(20.2, 12)], LIGHT, 2.0)
			_line([Vector2(9.4, 17.6), Vector2(20.2, 17.6)], LIGHT, 2.0)
		"play": # triangle in a ring (replay button / resume)
			_arc(12, 12, 8.6, GOLD, 2.0)
			_poly([Vector2(9.6, 7.6), Vector2(17.2, 12), Vector2(9.6, 16.4)], GOLD_LIGHT)
		"pause": # two bars in a ring
			_arc(12, 12, 8.6, GOLD, 2.0)
			draw_rect(Rect2(_p(8.8, 7.8), _p(11.2, 16.2) - _p(8.8, 7.8)), GOLD_LIGHT)
			draw_rect(Rect2(_p(12.8, 7.8), _p(15.2, 16.2) - _p(12.8, 7.8)), GOLD_LIGHT)
		"chev_left":
			_line([Vector2(15.5, 5.5), Vector2(8.5, 12), Vector2(15.5, 18.5)], LIGHT, 2.6)
		"chev_right":
			_line([Vector2(8.5, 5.5), Vector2(15.5, 12), Vector2(8.5, 18.5)], LIGHT, 2.6)
		"heart": # filled heart (13m: bạn thân flag, set) — flat
			# single-colour glyph; parents modulate gold.
			_poly(_heart_pts(), LIGHT)
		"heart_o": # outline heart (13m: bạn thân flag, unset)
			_line(_heart_pts(), LIGHT, 1.9, true)
		"trash": # bin with lid (13m: remove friend) — flat glyph
			draw_rect(Rect2(_p(9.8, 3.2), _p(14.2, 5.2) - _p(9.8, 3.2)), LIGHT)
			_line([Vector2(4.2, 6.2), Vector2(19.8, 6.2)], LIGHT, 2.2)
			_line([Vector2(6.4, 8.6), Vector2(17.6, 8.6), Vector2(16.4, 20.2), Vector2(7.6, 20.2)], LIGHT, 2.0, true)
			_line([Vector2(10.2, 11), Vector2(10.2, 17.4)], LIGHT, 1.8)
			_line([Vector2(13.8, 11), Vector2(13.8, 17.4)], LIGHT, 1.8)
		"plus": # add (13m: rail add button / Tìm bạn)
			_line([Vector2(12, 5), Vector2(12, 19)], LIGHT, 2.8)
			_line([Vector2(5, 12), Vector2(19, 12)], LIGHT, 2.8)
		"search": # magnifier (13m: Tìm bạn box)
			_arc(10.4, 10.4, 5.8, LIGHT, 2.1)
			_line([Vector2(14.9, 14.9), Vector2(20.2, 20.2)], LIGHT, 2.6)
		"chev_down":
			_line([Vector2(6.5, 8.5), Vector2(12, 14.5), Vector2(17.5, 8.5)], LIGHT, 2.4)
		"chev_up":
			_line([Vector2(6.5, 15.5), Vector2(12, 9.5), Vector2(17.5, 15.5)], LIGHT, 2.4)


## Parametric heart outline in logical 24x24 space (13m).
func _heart_pts() -> Array:
	var pts: Array = []
	var n := 26
	for i in range(n):
		var t := TAU * float(i) / float(n)
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(12.0 + x * 0.60, 11.8 - y * 0.60))
	return pts


func _arc_pts(cx: float, cy: float, r: float, a0: float, a1: float) -> Array:
	var pts: Array = []
	var n := 10
	for i in range(n + 1):
		var a := a0 + (a1 - a0) * float(i) / float(n)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return pts
