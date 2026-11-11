extends Node
## Captures the water VFX under Xvfb:
## xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_vfx_water.tscn
## Frames the lake (same framing as capture_terrain), lets the ambient
## water emitters run a few seconds (shore foam breathing, surface
## shimmer), then fires a small staged volley through the real VFX API
## (ripples + glints at lake cells) and shoots mid-expansion so the
## rings are unmistakably in frame.

var game = null


func _ready() -> void:
	Engine.time_scale = 1.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	# Same framing as the terrain shot: ~768x432 world px on the lake.
	game.cam.zoom = Vector2(1.5, 1.5)
	game.cam.focus_on(Vector2(1072, 976))
	# Let foam + shimmer run.
	await get_tree().create_timer(3.2).timeout
	# Staged volley through the real API: ripples at spread lake cells.
	var w = game.world
	var spots: Array = []
	for c in w.water:
		if absi(c.x - 33) <= 3 and absi(c.y - 30) <= 2:
			spots.append(c)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	if spots.size() >= 3:
		var picks: Array = [spots[0], spots[spots.size() / 2], spots[spots.size() - 1]]
		for c in picks:
			game.vfx.ripple(w.cell_center(c), VFX.RIPPLE_COLOR, 30.0, 1.8)
		for i in range(5):
			var c2: Vector2i = picks[i % picks.size()]
			game.vfx.glint(w.cell_center(c2) + Vector2(6 - i * 3, -4 + i * 2),
					VFX.SHIMMER_COLOR, 11.0, 1.0)
	print("CAPTURE water live effects before volley-settle: ", game.vfx.live_count())
	await get_tree().create_timer(0.45).timeout
	print("CAPTURE water live effects at shot: ", game.vfx.live_count())
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_vfx_water.png")
	print("CAPTURE SAVED res://shots/empire_age_vfx_water.png size=", img.get_size())
	get_tree().quit()
