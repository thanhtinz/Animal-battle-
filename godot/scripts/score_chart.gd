class_name ScoreChart
extends Control

## 13y: score-over-time line chart for the result screen.
## Data comes from Main.stat_series — one sample every 30
## game-seconds: {t, rows: {owner: {score, pop, mil}}}. One
## polyline per owner in the owner's slot colour (TeamColors),
## count-agnostic: it draws however many owners the match had
## (2 now; the queue design grows to 8). Presentation only.

var series: Array = [] # Main.stat_series (shared reference, read-only here)
var owners: Array = [] # owner ids to draw, in standings order


func set_data(p_series: Array, p_owners: Array) -> void:
	series = p_series
	owners = p_owners
	queue_redraw()


func _max_score() -> float:
	var m := 1.0
	for s in series:
		var rows: Dictionary = s.get("rows", {})
		for o in owners:
			if rows.has(o):
				m = maxf(m, float((rows[o] as Dictionary).get("score", 0)))
	return m


func _max_t() -> float:
	if series.is_empty():
		return 1.0
	return maxf(float((series[series.size() - 1] as Dictionary).get("t", 0.0)), 1.0)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 40.0 or rect.size.y < 40.0:
		return
	# Plot area: room for the max-score label at top and the
	# time axis at the bottom.
	var plot := Rect2(Vector2(6, 14), rect.size - Vector2(12, 30))
	# Faint horizontal gridlines (quarters of the max score).
	for i in range(5):
		var y := plot.position.y + plot.size.y * float(i) / 4.0
		draw_line(Vector2(plot.position.x, y),
				Vector2(plot.position.x + plot.size.x, y),
				Color(1, 1, 1, 0.07), 1.0)
	var font := ThemeDB.fallback_font
	var max_s := _max_score()
	var max_t := _max_t()
	draw_string(font, Vector2(plot.position.x, 10), "%d" % int(max_s),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.8, 0.9, 0.8))
	draw_string(font, Vector2(plot.position.x + plot.size.x - 30, size.y - 4),
			"%02d:%02d" % [int(max_t) / 60, int(max_t) % 60],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.8, 0.9, 0.8))
	if series.size() < 2:
		draw_string(font, plot.position + Vector2(6, 16),
				"Chưa đủ dữ liệu biểu đồ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.75, 0.8, 0.9, 0.7))
		return
	for o in owners:
		var col := TeamColors.ui_color(int(o))
		var pts := PackedVector2Array()
		for s in series:
			var rows: Dictionary = s.get("rows", {})
			if not rows.has(o):
				continue
			var t := float(s.get("t", 0.0))
			var sc := float((rows[o] as Dictionary).get("score", 0))
			pts.append(Vector2(
					plot.position.x + plot.size.x * t / max_t,
					plot.position.y + plot.size.y * (1.0 - sc / max_s)))
		if pts.size() >= 2:
			draw_polyline(pts, col, 2.0, true)
		if not pts.is_empty():
			draw_circle(pts[pts.size() - 1], 3.0, col)
