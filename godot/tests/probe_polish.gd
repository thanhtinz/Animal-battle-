extends Node
## Numeric probe for the visual-polish pass (headless, no capture):
##   godot --headless --path . res://tests/probe_polish.tscn
## Prints cloud display widths (must be <= ~320 world px) and the
## dirt-blob decals' scale ranges (must be non-uniform, 0.7–1.6 tiles
## per axis => scale factor vs the 128 px blob texture).

func _ready() -> void:
	var ms = load("res://scripts/main.gd")
	ms.chosen_biome = "grassland"
	ms.chosen_layout = "plains"
	ms.map_choice_done = true
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var worst_cloud := 0.0
	for pair in game.world.clouds:
		var cs: Sprite2D = pair["cloud"]
		worst_cloud = maxf(worst_cloud, cs.texture.get_width() * cs.scale.x)
	print("PROBE cloud_max_display_w=", snappedf(worst_cloud, 0.1))
	var blobs := 0
	var sx_min := 99.0
	var sx_max := 0.0
	var sy_min := 99.0
	var sy_max := 0.0
	var nonuniform := 0
	for d in game.world.ground_decals:
		var s := d as Sprite2D
		if s.texture != null and s.texture.get_width() == 128:
			blobs += 1
			# Display width in tiles = tex_px * scale / TILE.
			var tx := 128.0 * s.scale.x / 32.0
			var ty := 128.0 * s.scale.y / 32.0
			sx_min = minf(sx_min, tx)
			sx_max = maxf(sx_max, tx)
			sy_min = minf(sy_min, ty)
			sy_max = maxf(sy_max, ty)
			if absf(s.scale.x - s.scale.y) > 0.01:
				nonuniform += 1
	print("PROBE dirt_blobs=", blobs, " nonuniform=", nonuniform,
			" tiles_x=[", snappedf(sx_min, 0.01), ",", snappedf(sx_max, 0.01), "]",
			" tiles_y=[", snappedf(sy_min, 0.01), ",", snappedf(sy_max, 0.01), "]")
	var by_width := {}
	for d in game.world.ground_decals:
		var s := d as Sprite2D
		if s.texture != null:
			var w := s.texture.get_width()
			by_width[w] = int(by_width.get(w, 0)) + 1
	print("PROBE decals_by_tex_width=", by_width)
	print("PROBE total_decals=", game.world.ground_decals.size())
	get_tree().quit()
