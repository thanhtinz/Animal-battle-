extends Node
## Numeric probe for the water-contrast fix (headless):
##   godot --headless --path . res://tests/probe_water_contrast.tscn
## For each biome: generate a plains world, sample the BAKED ground
## image at deep-water cell centres vs land cells adjacent to water,
## and print mean luminance + HSV saturation for both sets plus the
## two acceptance ratios (lum difference >= 25% of land lum, OR
## water saturation >= 2x land saturation).

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _sat(c: Color) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	return 0.0 if mx <= 0.0001 else (mx - mn) / mx


func _measure(biome_id: String) -> void:
	var w := World.new()
	w.biome_id = biome_id
	add_child(w)
	w.generate(777)
	var img: Image = w.baked_image
	var bs := float(World.BAKE_PX) / float(World.MAP_W * World.TILE) # bake px per world px
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var w_lum := 0.0
	var w_sat := 0.0
	var w_n := 0
	var l_lum := 0.0
	var l_sat := 0.0
	var l_n := 0
	for c in w.water:
		var deep := true
		for d in dirs:
			if not w.water.has(c + d):
				deep = false
				break
		if deep:
			var p := img.get_pixel((c.x * World.TILE + World.TILE / 2) * bs,
					(c.y * World.TILE + World.TILE / 2) * bs)
			w_lum += _lum(p)
			w_sat += _sat(p)
			w_n += 1
	for y in range(World.MAP_H):
		for x in range(World.MAP_W):
			var c := Vector2i(x, y)
			if w.water.has(c):
				continue
			var adj := false
			for d in dirs:
				if w.water.has(c + d):
					adj = true
					break
			if adj:
				var p := img.get_pixel((c.x * World.TILE + World.TILE / 2) * bs,
						(c.y * World.TILE + World.TILE / 2) * bs)
				l_lum += _lum(p)
				l_sat += _sat(p)
				l_n += 1
	if w_n == 0 or l_n == 0:
		print("PROBE ", biome_id, " NO SAMPLES water=", w_n, " land=", l_n)
		return
	w_lum /= w_n
	w_sat /= w_n
	l_lum /= l_n
	l_sat /= l_n
	var lum_diff := absf(w_lum - l_lum) / maxf(l_lum, 0.0001)
	var sat_ratio := w_sat / maxf(l_sat, 0.0001)
	var ok := lum_diff >= 0.25 or sat_ratio >= 2.0
	print("PROBE ", biome_id,
			" water_lum=", snappedf(w_lum, 0.001), " water_sat=", snappedf(w_sat, 0.001),
			" land_lum=", snappedf(l_lum, 0.001), " land_sat=", snappedf(l_sat, 0.001),
			" lum_diff=", snappedf(lum_diff * 100.0, 0.1), "%",
			" sat_ratio=", snappedf(sat_ratio, 0.01), "x",
			" samples_w=", w_n, " samples_l=", l_n,
			" VERDICT=", "PASS" if ok else "FAIL")


func _ready() -> void:
	for b in ["grassland", "desert", "snow"]:
		_measure(b)
	get_tree().quit()
