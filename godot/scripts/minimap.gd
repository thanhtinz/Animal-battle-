class_name Minimap
extends Control
## Live-drawn minimap: simplified terrain (grass shades + lake), resource
## clusters as coloured dots, buildings as team-colour squares, units as
## dots, and a white rectangle for the camera viewport.
## Click / drag moves the camera. `click_at()` is the same code path the
## GUI input uses (also driven by the headless tests).

var game = null # Main (duck-typed)

## 15g alert pings (presentation only): expanding rings at a
## world position, decaying over ~2.4 s. Fed by Main's ambush
## alerts; never sim state.
var pings: Array = [] # [{pos: Vector2, t: float}]


## Mark a world position for the local player's attention.
func ping_at(wpos: Vector2) -> void:
	pings.append({"pos": wpos, "t": 2.4})
	if pings.size() > 6:
		pings.pop_front()

var _accum := 0.0
var _ground_tex: Texture2D = null # minimap-sized copy of the baked ground
var _ground_img: Image = null


## Builds (once) the minimap ground texture by sampling the world's
## baked ground image down, so minimap colours match the real map.
func _ensure_ground_tex(w) -> void:
	if _ground_tex != null or w == null or w.baked_image == null:
		return
	_ground_img = w.baked_image.duplicate() as Image
	_ground_img.resize(128, 128, Image.INTERPOLATE_BILINEAR)
	_ground_tex = ImageTexture.create_from_image(_ground_img)


## Terrain colour the minimap paints at a cell (from the baked
## ground), or TRANSPARENT before the bake exists.
func ground_color_at(c: Vector2i) -> Color:
	if _ground_img == null:
		return Color.TRANSPARENT
	return _ground_img.get_pixel(clampi(c.x * 2, 0, 127), clampi(c.y * 2, 0, 127))


func _ready() -> void:
	custom_minimum_size = Vector2(200, 140)
	mouse_filter = MOUSE_FILTER_STOP


func world_pixels() -> Vector2:
	return Vector2(World.MAP_W, World.MAP_H) * World.TILE


func local_to_world(p: Vector2) -> Vector2:
	var ws := world_pixels()
	return Vector2(
			clampf(p.x / maxf(size.x, 1.0), 0.0, 1.0) * ws.x,
			clampf(p.y / maxf(size.y, 1.0), 0.0, 1.0) * ws.y)


func click_at(local: Vector2) -> void:
	if game == null or game.cam == null:
		return
	game.cam.focus_on(local_to_world(local))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			click_at(mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			click_at(mm.position)


## The entity-layer colour _draw would paint at a world cell, or
## TRANSPARENT when nothing entity-like is drawn there. Mirrors the
## _draw building/unit passes exactly (own team only) so tests can
## assert the minimap privacy rule without a renderer.
func marker_color_at(c: Vector2i) -> Color:
	if game == null:
		return Color.TRANSPARENT
	var vt: int = game.view_team()
	for b in game.buildings:
		if b.team != vt:
			continue
		if c.x >= b.origin_cell.x and c.x < b.origin_cell.x + b.size.x \
				and c.y >= b.origin_cell.y and c.y < b.origin_cell.y + b.size.y:
			return TeamColors.minimap_color(b.owner_id, "building")
	for u in game.units:
		if u.team != vt:
			continue
		if game.world != null and game.world.world_to_cell(u.global_position) == c:
			return TeamColors.minimap_color(u.owner_id, "unit")
	if game.get("ships") != null:
		for s in game.ships:
			if s.team != vt:
				continue
			if game.world != null and game.world.world_to_cell(s.global_position) == c:
				return TeamColors.minimap_color(s.owner_id, "ship")
	return Color.TRANSPARENT


func _process(delta: float) -> void:
	_accum += delta
	if not pings.is_empty():
		var kept: Array = []
		for p in pings:
			p["t"] = float(p["t"]) - delta
			if float(p["t"]) > 0.0:
				kept.append(p)
		pings = kept
	if _accum >= 0.2:
		_accum = 0.0
		queue_redraw()


func _cell_rect(c: Vector2i) -> Rect2:
	var sx := size.x / World.MAP_W
	var sy := size.y / World.MAP_H
	return Rect2(float(c.x) * sx, float(c.y) * sy, sx + 0.6, sy + 0.6)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.06, 0.04))
	if game == null or game.world == null:
		return
	var w = game.world
	# Terrain comes from the world's baked ground texture (sampled
	# down once), so the minimap shows the same soft shores and base
	# tones as the real map. Fallback: flat biome colours per cell.
	_ensure_ground_tex(w)
	if _ground_tex != null:
		draw_texture_rect(_ground_tex, Rect2(Vector2.ZERO, size), false)
	else:
		var bdef: Dictionary = w.biome()
		var base_a: Color = bdef["minimap_land_a"]
		var base_b: Color = bdef["minimap_land_b"]
		var water_col: Color = bdef["minimap_water"]
		for y in range(World.MAP_H):
			for x in range(World.MAP_W):
				var c := Vector2i(x, y)
				var r := _cell_rect(c)
				if w.water.has(c):
					draw_rect(r, water_col)
				else:
					draw_rect(r, base_a.lerp(base_b, w.tile_shade[y * World.MAP_W + x]))
	# Fog of War (P3): unexplored cells go black, explored ones dim.
	# (Fog no longer gates entity markers — the privacy rule below
	# removes other teams from the minimap entirely.)
	var fog = game.fog
	if fog != null:
		for y in range(World.MAP_H):
			for x in range(World.MAP_W):
				var c := Vector2i(x, y)
				var s: int = fog.cell_state(c)
				if s == 0:
					draw_rect(_cell_rect(c), Color(0.01, 0.01, 0.02, 1.0))
				elif s == 1:
					draw_rect(_cell_rect(c), Color(0.01, 0.01, 0.03, 0.45))
	# Resource clusters as dots.
	for n in w.nodes:
		if fog != null and not fog.is_explored_cell(n.cell):
			continue
		var col := Color(0.16, 0.4, 0.14)
		if n.rtype == "gold":
			col = Color(0.98, 0.8, 0.25)
		elif n.rtype == "stone":
			col = Color(0.75, 0.76, 0.79)
		elif n.rtype == "food":
			col = Color(0.95, 0.4, 0.4)
		var r := _cell_rect(n.cell)
		draw_rect(Rect2(r.position + r.size * 0.25, r.size * 0.55), col)
	# Buildings as squares — PLAYER'S OWN ONLY. Privacy rule (Tín):
	# the minimap must NEVER render another team's information, not
	# even scouted/"last seen" buildings. Other teams simply do not
	# exist on this map; _draw skips them unconditionally.
	for b in game.buildings:
		if b.team != game.view_team():
			continue
		var col := TeamColors.minimap_color(b.owner_id, "building")
		var r := _cell_rect(b.origin_cell)
		var sz := Vector2(float(b.size.x) * size.x / World.MAP_W, float(b.size.y) * size.y / World.MAP_H)
		draw_rect(Rect2(r.position, sz), col)
		draw_rect(Rect2(r.position, sz), Color(1, 1, 1, 0.55), false, 1.0)
	# Units as dots — own team only, same rule.
	for u in game.units:
		if u.team != game.view_team():
			continue
		var col := TeamColors.minimap_color(u.owner_id, "unit")
		var p: Vector2 = u.global_position / world_pixels() * size
		draw_rect(Rect2(p - Vector2(1.4, 1.4), Vector2(2.8, 2.8)), col)
	# Own ships as slightly larger dots — same privacy rule, and the
	# owner's slot colour like everything else on this map.
	if game.get("ships") != null:
		for s in game.ships:
			if s.team != game.view_team():
				continue
			var p2: Vector2 = s.global_position / world_pixels() * size
			draw_rect(Rect2(p2 - Vector2(1.8, 1.8), Vector2(3.6, 3.6)),
					TeamColors.minimap_color(s.owner_id, "ship"))
	# Camera viewport rectangle.
	var cam: Camera2D = game.cam
	if cam != null:
		var view_world: Vector2 = get_viewport_rect().size / cam.zoom.x
		var tl: Vector2 = (cam.position - view_world * 0.5) / world_pixels() * size
		var br: Vector2 = (cam.position + view_world * 0.5) / world_pixels() * size
		draw_rect(Rect2(tl, br - tl), Color(1, 1, 1, 0.9), false, 1.4)
	# 15g alert pings on top of everything: a ring that expands
	# and fades over its 2.4 s life.
	for p in pings:
		var lp: Vector2 = (p["pos"] as Vector2) / world_pixels() * size
		var life := clampf(float(p["t"]) / 2.4, 0.0, 1.0)
		var rad := 3.0 + (1.0 - life) * 9.0
		draw_arc(lp, rad, 0, TAU, 24, Color(1.0, 0.35, 0.25, life), 1.8)
		draw_circle(lp, 1.8, Color(1.0, 0.35, 0.25, life))
