class_name FallsLayer
extends Node2D
## Animated waterfall strips over the World's falls cells: slices of
## the active biome's water texture scroll downward (built from the
## water tiles themselves, so the falls always match the map's water),
## with a rock backing at each column head and a foam line at the base.
## Foam ripples + mist at the base come from VFX (falls_foam_points).

var world: World = null
var _phase := 0.0


func _process(dt: float) -> void:
	if world == null or world.falls_cells.is_empty():
		return
	_phase += dt
	queue_redraw()


func _draw() -> void:
	if world == null or world.falls_cells.is_empty():
		return
	var tex: Texture2D = world.ground_tex.get("water_2", null)
	if tex == null:
		tex = world.ground_tex.get("water_0", null)
	if tex == null:
		return
	var step := int(_phase * 44.0) % 48
	for c in world.falls_cells:
		var p := Vector2(c) * World.TILE
		# Rock backing where a falls column starts (no falls above/left).
		if not world.falls_cells.has(c + Vector2i(0, -1)) \
				and not world.falls_cells.has(c + Vector2i(-1, 0)) \
				and not world.cliff_tex.is_empty():
			draw_texture_rect(world.cliff_tex[0],
					Rect2(p + Vector2(0, -12), Vector2(World.TILE, World.TILE + 12)), false)
		# Scrolling water: 2 horizontal slices whose source rows cycle.
		for s in range(2):
			var src_y := (s * 16 + step) % 64
			if src_y > 48:
				src_y = 48
			draw_texture_rect_region(tex,
					Rect2(p + Vector2(3, s * 16), Vector2(World.TILE - 6, 16)),
					Rect2(4, src_y, World.TILE - 8, 16))
		# Foam line where the column ends.
		if not world.falls_cells.has(c + Vector2i(0, 1)) \
				and not world.falls_cells.has(c + Vector2i(1, 0)):
			draw_rect(Rect2(p + Vector2(3, World.TILE - 6), Vector2(World.TILE - 6, 5)),
					Color(1, 1, 1, 0.55))
