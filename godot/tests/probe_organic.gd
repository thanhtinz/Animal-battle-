extends Node
## Diagnosis probe for the organic-water pass (headless):
##   godot --headless --path . res://tests/probe_organic.tscn
## Plains: where are the ponds/fish spots, and is the spot nearest
## to (1800,300) on the lake's water body?
## Valley: which corridor cells are blocked, and by what?

func _ready() -> void:
	# --- plains ---
	var wp := World.new()
	wp.layout_id = "plains"
	add_child(wp)
	wp.generate(12345)
	print("PLAINS ponds:")
	for pond in wp.features.ponds:
		print("  pond cells=", pond.size(), " first=", pond[0] if not pond.is_empty() else Vector2i(-1, -1))
	print("PLAINS lake cells=", wp.features.lake.size())
	# Water components (4-connected) with their fish spots.
	var seen: Dictionary = {}
	var comp_id := 0
	var spot_comp: Dictionary = {}
	for start in wp.water.keys():
		if seen.has(start):
			continue
		var comp: Array = []
		var stack: Array = [start]
		seen[start] = comp_id
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if wp.water.has(n) and not seen.has(n):
					seen[n] = comp_id
					stack.append(n)
		print("  comp ", comp_id, " size=", comp.size(), " sample=", comp[0])
		comp_id += 1
	for fs in wp.fish_spots:
		spot_comp[fs.cell] = seen.get(fs.cell, -1)
		print("  fish spot cell=", fs.cell, " comp=", spot_comp[fs.cell])
	var far := wp.nearest_fish_spot(Vector2(1800, 300))
	print("  nearest spot to (1800,300): ", far.cell if far else Vector2i(-1, -1),
			" comp=", spot_comp.get(far.cell, -1) if far else -1)
	var lake_comp: int = seen.get(wp.features.lake[0], -1)
	print("  lake comp=", lake_comp)
	if far:
		print("  water path lake->far_spot cells=",
				wp.get_water_path_cells(wp.features.lake[0], far.cell).size())
	remove_child(wp)
	wp.queue_free()
	# --- valley ---
	var wv := World.new()
	wv.layout_id = "valley"
	add_child(wv)
	wv.generate(12345)
	print("VALLEY path base->base = ", wv.get_path_cells(wv.player_base, wv.enemy_base).size())
	print("VALLEY path base->centre(31,32) = ", wv.get_path_cells(wv.player_base, Vector2i(30, 32)).size())
	print("VALLEY path centre->enemy = ", wv.get_path_cells(Vector2i(30, 32), wv.enemy_base).size())
	# Dump non-water solids inside the corridor rect.
	var blocked: Array = []
	for y in range(23, 42):
		for x in range(27, 37):
			var c := Vector2i(x, y)
			if wv.is_solid(c) and not wv.water.has(c):
				blocked.append(c)
	print("VALLEY corridor non-water solids: ", blocked.size())
	for c in blocked:
		var what := "?"
		for nd in wv.nodes:
			if nd.cell == c:
				what = "node:" + nd.rtype
		print("   ", c, " ", what)
	remove_child(wv)
	wv.queue_free()
	get_tree().quit()
