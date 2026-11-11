class_name LoadingScreen
extends CanvasLayer
## Empire Age 13r — boot loading screen, after Tín's reference
## (painted village scene, ref 2). The scene is copied as-is; its
## BAKED bottom band (text + bar painted into the picture) is
## fully covered by our own live band: a dark gradient starting
## at 0.80·H — above everything baked — carrying the live status
## line and the live ornate gold bar.
##
## HONEST PROGRESS: the bar is driven by Main's boot sequence,
## one step per real chunk of work (texture preload → world
## build → server connect → session restore). set_progress is
## only ever called when a step has actually completed; the
## screen never animates the number on its own.

const BG_TEX := preload("res://assets/loading_bg.png")

var _band: LoadBand
var _status: Label
var _phase_lbl: Label
var _bar: LoadBar
var _progress: float = 0.0


class LoadBand:
	extends Control
	## Dark translucent gradient. The picture bakes its own text
	## at ~0.83 H and bar at ~0.89 H, so the band starts at
	## 0.75 H and is essentially opaque from ~0.845 H down —
	## nothing baked can ghost through behind the live elements.
	func _draw() -> void:
		var top := size.y * 0.74
		var steps := 28
		for i in range(steps):
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var a := clampf(t0 / 0.28, 0.0, 1.0) * 0.985
			draw_rect(Rect2(0, lerpf(top, size.y, t0), size.x,
					lerpf(top, size.y, t1) - lerpf(top, size.y, t0) + 1.0),
					Color(0.015, 0.02, 0.045, a))


class LoadBar:
	extends Control
	## Ref-2 geometry, MEASURED from Tín's reference (1290×645):
	## the bar spans x 0.191W..0.817W (0.626W wide, centred on
	## 0.504W) and y 0.862H..0.909H — only ~30px tall on a 645px
	## picture, a SLIM hexagon whose pointed chevron ends are
	## part of the frame itself. Frame = double line: a pale
	## bright-gold outer edge (~2px, sampled (246,230,179)) over
	## a dark-bronze inner line (~1.6px, sampled (70,39,0)).
	## Track is near-black blue (sampled ~(21,23,33)). Fill is a
	## smooth VERTICAL gold gradient sampled down a filled
	## column: pale highlight → bright gold → deep amber → a
	## slight lift at the bottom edge. At the fill tip the
	## reference shows a white-hot seam with a real SPARKLE: a
	## 4-point star whose vertical spike spans the full inner
	## height and whose horizontal streak runs back along the
	## fill, over a warm halo ~30px wide — stronger than a plain
	## seam line, but elongated, NOT the v1 bar's round blob.
	##
	## END CAPS (13r follow-up 4b — Tín, on v2: "Chỗ đầu bị
	## thiếu kìa"): zooming the reference's tips shows each end
	## is NOT a bare chevron outline — a solid ornate gold
	## ARROWHEAD CAP sits over the point: a faceted diamond
	## medallion ~0.95·H wide and ~1.5·H TALL (it stands proud
	## of the rails top and bottom), gold frame faces around a
	## dark core, with a small RED GEM diamond at its centre.
	## The nested-hexagon tips of v2 read as thin hollow
	## chevrons next to it, so the caps are drawn on top of the
	## hexagon tips, inside the bar's measured span.
	var value: float = 0.0:
		set(v):
			value = v
			queue_redraw()

	const FRAME_OUT := Color(0.96, 0.90, 0.70)
	const FRAME_IN := Color(0.27, 0.15, 0.00)
	const TRACK := Color(0.08, 0.09, 0.13)
	const GRAD := [
		[0.00, Color(0.98, 0.89, 0.42)],
		[0.22, Color(1.00, 0.95, 0.32)],
		[0.50, Color(0.97, 0.76, 0.18)],
		[0.78, Color(0.95, 0.63, 0.08)],
		[1.00, Color(0.99, 0.76, 0.24)],
	]

	## Hexagon outline inset by d (d = 0 → the outer edge). The
	## chevron tip is tip_len = 0.55·H long; insetting shifts the
	## tip and shoulders by the slant factors derived from the
	## edge angle, so nested outlines stay parallel.
	func _hex(d: float) -> PackedVector2Array:
		var t := size.y * 0.55
		var half := size.y * 0.5
		var l := sqrt(t * t + half * half)
		var tip_k := l / half
		var sh_k := (half * half - t * l + t * t) / (l * half)
		return PackedVector2Array([
			Vector2(tip_k * d, half),
			Vector2(t + sh_k * d, d),
			Vector2(size.x - t - sh_k * d, d),
			Vector2(size.x - tip_k * d, half),
			Vector2(size.x - t - sh_k * d, size.y - d),
			Vector2(t + sh_k * d, size.y - d)])

	## Horizontal extent of the d-inset hexagon at height y.
	func _x_range_at(y: float, d: float) -> Vector2:
		var t := size.y * 0.55
		var half := size.y * 0.5
		var l := sqrt(t * t + half * half)
		var tip_x := (l / half) * d
		var sh_x := t + ((half * half - t * l + t * t) / (l * half)) * d
		var k := 1.0
		if half > d:
			k = clampf(absf(clampf(y, d, size.y - d) - half) / (half - d), 0.0, 1.0)
		var lx := lerpf(tip_x, sh_x, k)
		return Vector2(lx, size.x - lx)

	## Vertical extent of the d-inset hexagon at column x.
	func _y_range_at(x: float, d: float) -> Vector2:
		var t := size.y * 0.55
		var half := size.y * 0.5
		var l := sqrt(t * t + half * half)
		var tip_x := (l / half) * d
		var sh_x := t + ((half * half - t * l + t * t) / (l * half)) * d
		var xx := minf(x, size.x - x)
		if xx <= tip_x:
			return Vector2(half, half)
		if xx >= sh_x:
			return Vector2(d, size.y - d)
		var iy := lerpf(half, d, (xx - tip_x) / maxf(0.001, sh_x - tip_x))
		return Vector2(iy, size.y - iy)

	## One ornate end cap, its outer point AT the bar's tip
	## (tip_x = 0 for the left cap, size.x for the right one).
	## Construction, inside-out as zoomed from the reference:
	## faceted gold diamond (pale top face, deep bottom face)
	## → smaller dark-bronze core diamond → tiny RED GEM
	## diamond at the centre → bright rim. The diamond is
	## ~0.95·H wide and ~1.5·H tall, so it clasps the bar end
	## standing proud of the rails, exactly like the reference.
	func _draw_cap(tip_x: float, dir: float) -> void:
		var half := size.y * 0.5
		var cw := size.y * 0.95
		var ch := size.y * 1.5
		var cx := tip_x + dir * cw * 0.5
		var c := Vector2(cx, half)
		var tip := Vector2(tip_x, half)
		var top := Vector2(cx, half - ch * 0.5)
		var back := Vector2(tip_x + dir * cw, half)
		var bot := Vector2(cx, half + ch * 0.5)
		# Faceted gold body: lighter upper face, deeper lower.
		draw_colored_polygon(PackedVector2Array([tip, top, back]),
				Color(1.00, 0.87, 0.45))
		draw_colored_polygon(PackedVector2Array([tip, back, bot]),
				Color(0.88, 0.60, 0.14))
		# Horizontal ridge through the centre.
		draw_line(tip, back, Color(0.55, 0.33, 0.03, 0.55), 1.0, true)
		# Dark core diamond (the notch the gem sits in).
		var iw := cw * 0.30
		var ih := ch * 0.32
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-iw, 0), c + Vector2(0, -ih),
			c + Vector2(iw, 0), c + Vector2(0, ih)]),
				Color(0.16, 0.09, 0.02))
		# The red gem: small diamond, bright top facet.
		var gw := cw * 0.13
		var gh := ch * 0.15
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-gw, 0), c + Vector2(0, -gh), c + Vector2(gw, 0)]),
				Color(0.98, 0.38, 0.13))
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-gw, 0), c + Vector2(gw, 0), c + Vector2(0, gh)]),
				Color(0.70, 0.15, 0.04))
		# Bright rim around the whole cap.
		var rim := PackedVector2Array([tip, top, back, bot, tip])
		draw_polyline(rim, FRAME_OUT, 1.3, true)

	func _grad_at(t: float) -> Color:
		for i in range(GRAD.size() - 1):
			var a: Array = GRAD[i]
			var b: Array = GRAD[i + 1]
			if t <= float(b[0]):
				var k := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
				return (a[1] as Color).lerp(b[1] as Color, clampf(k, 0.0, 1.0))
		return GRAD[GRAD.size() - 1][1] as Color

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 8.0 or h <= 4.0:
			return
		# Frame: nested hexagons — pale outer line, dark inner
		# line, then the dark track.
		draw_colored_polygon(_hex(0.0), FRAME_OUT)
		draw_colored_polygon(_hex(2.0), FRAME_IN)
		var d_in := 3.6
		var inner := _hex(d_in)
		draw_colored_polygon(inner, TRACK)
		# The fill runs between the inner hexagon's shoulders;
		# the chevron caps keep the frame + dark centre, as in
		# the reference.
		var xs := inner[1].x
		var xe := inner[2].x
		var v := clampf(value, 0.0, 1.0)
		var fill_x := xs + (xe - xs) * v
		if v > 0.0:
			# Fill: horizontal bands carrying the vertical
			# gradient, each clipped to the hexagon (using the
			# band's narrower outer edge so a band can never
			# paint over the frame lines) and to the fill tip.
			var bands := 16
			for i in range(bands):
				var t0 := float(i) / bands
				var t1 := float(i + 1) / bands
				var ya := lerpf(d_in, h - d_in, t0)
				var yb := lerpf(d_in, h - d_in, t1)
				var edge_y := ya if ya < h * 0.5 else yb
				var xr := _x_range_at(edge_y, d_in)
				var lx := maxf(xr.x, xs)
				var rx := minf(xr.y, fill_x)
				if rx > lx:
					draw_rect(Rect2(lx, ya, rx - lx, yb - ya + 0.6),
							_grad_at((t0 + t1) * 0.5))
		if v > 0.005 and v < 0.999:
			# The fill brightens toward its head (the reference
			# fill runs near-white for its last stretch): pale
			# slices of rising alpha over the final ~20px.
			var head_len := 20.0
			var hsteps := 7
			for i in range(hsteps):
				var ha := fill_x - head_len + head_len * float(i) / hsteps
				var hb := fill_x - head_len + head_len * float(i + 1) / hsteps
				if hb <= xs:
					continue
				var a := lerpf(0.04, 0.38, float(i + 1) / hsteps)
				var hyr := _y_range_at((ha + hb) * 0.5, d_in)
				draw_rect(Rect2(maxf(ha, xs), hyr.x, hb - maxf(ha, xs),
						hyr.y - hyr.x), Color(1.0, 0.97, 0.82, a))
			# Warm halo spilling into the track ahead of the
			# tip (~30px, orange, fading out).
			var glow_len := 30.0
			var gsteps := 13
			for i in range(gsteps):
				var ga := fill_x + glow_len * float(i) / gsteps
				if ga >= xe:
					break
				var gb := minf(fill_x + glow_len * float(i + 1) / gsteps, xe)
				var a := 0.34 * pow(1.0 - float(i) / gsteps, 1.5)
				var yr := _y_range_at((ga + gb) * 0.5, d_in)
				draw_rect(Rect2(ga, yr.x, gb - ga, yr.y - yr.x),
						Color(1.0, 0.66, 0.20, a))
			# THE SPARKLE (reference zoom): a 4-point star at
			# the seam — vertical spike spanning the full inner
			# height, horizontal streak running back along the
			# fill and a short way into the track, white-hot
			# core. Elongated lens shapes, never a round blob.
			var syr := _y_range_at(fill_x, d_in)
			var cy := h * 0.5
			# Horizontal streak (pale gold halo pass, then a
			# brighter, thinner core pass).
			for pass_i in range(2):
				var back_len := 44.0 if pass_i == 0 else 34.0
				var fwd_len := 16.0 if pass_i == 0 else 11.0
				var sh := (3.4 if pass_i == 0 else 1.8)
				var scol := Color(1.0, 0.80, 0.30, 0.30) if pass_i == 0 \
						else Color(1.0, 0.96, 0.78, 0.85)
				draw_colored_polygon(PackedVector2Array([
					Vector2(fill_x - back_len, cy),
					Vector2(fill_x, cy - sh),
					Vector2(fill_x + fwd_len, cy),
					Vector2(fill_x, cy + sh)]), scol)
			# Vertical spike: a thin lens from the top inner
			# edge to the bottom inner edge.
			draw_colored_polygon(PackedVector2Array([
				Vector2(fill_x, syr.x - 0.5),
				Vector2(fill_x + 2.6, cy),
				Vector2(fill_x, syr.y + 0.5),
				Vector2(fill_x - 2.6, cy)]),
					Color(1.0, 0.90, 0.55, 0.75))
			# The seam itself: thin near-white line, then the
			# white-hot core diamond where the spikes cross.
			draw_rect(Rect2(fill_x - 1.25, syr.x + 0.5, 2.5, syr.y - syr.x - 1.0),
					Color(1.0, 0.985, 0.80, 0.95))
			draw_colored_polygon(PackedVector2Array([
				Vector2(fill_x - 4.2, cy), Vector2(fill_x, cy - 6.0),
				Vector2(fill_x + 4.2, cy), Vector2(fill_x, cy + 6.0)]),
					Color(1.0, 1.0, 0.96, 0.98))
		# Crisp outer edge.
		var rim := PackedVector2Array(_hex(0.0))
		rim.append(rim[0])
		draw_polyline(rim, FRAME_OUT, 1.2, true)
		# Ornate gold end caps clasping both tips (drawn last,
		# on top of frame and fill — the fill tucks under the
		# right cap at 100%, as in the reference).
		_draw_cap(0.0, 1.0)
		_draw_cap(w, -1.0)


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = BG_TEX
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_band = LoadBand.new()
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 21)
	_status.add_theme_color_override("font_color", Color(0.97, 0.97, 0.99))
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_status.add_theme_constant_override("shadow_offset_x", 2)
	_status.add_theme_constant_override("shadow_offset_y", 2)
	_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status.offset_top = 648.0 * 0.815
	_status.offset_bottom = -648.0 * 0.142
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	# The bar, CENTRED on the screen axis — equal margins to
	# the pixel (the v1 bar sat at 0.197W..0.970W: lopsided,
	# Tín's "lệch"). Width and height are the reference's
	# measured fractions: 0.626W × ~30px, centred at 0.889H.
	_bar = LoadBar.new()
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.offset_left = 1152.0 * 0.187
	_bar.offset_right = -1152.0 * 0.187
	_bar.offset_top = 648.0 * 0.866
	_bar.offset_bottom = -648.0 * 0.0877
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_phase_lbl = Label.new()
	_phase_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_lbl.add_theme_font_size_override("font_size", 14)
	_phase_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_phase_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phase_lbl.offset_top = 648.0 * 0.920
	_phase_lbl.offset_bottom = -648.0 * 0.034
	_phase_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase_lbl)

	set_progress(0.0, "Đang khởi động...")


## p in [0,1] — the share of boot steps COMPLETED so far.
func set_progress(p: float, phase: String = "") -> void:
	_progress = clampf(p, 0.0, 1.0)
	if _bar != null:
		_bar.value = _progress
	if _status != null:
		_status.text = "Đang tải tài nguyên... (%d%%)" % int(round(_progress * 100.0))
	if _phase_lbl != null and phase != "":
		_phase_lbl.text = phase


func progress() -> float:
	return _progress
