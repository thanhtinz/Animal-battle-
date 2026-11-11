extends Node2D
## Contact sheet for the self-drawn pass: every NEW sprite at exact
## in-game scale over grass, flanked by accepted family references
## (Town Center tier 3, Villager, Militia) for the style judgement.
## Run under Xvfb like the other capture scenes.

const TILE := 32.0


func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)


## Draw a building texture bottom-anchored at (cx, ground_y), at
## ART_SCALE x its footprint width — exactly Building.art_rect math.
func _building(tex: Texture2D, cx: float, ground_y: float, footprint_tiles: float, name: String) -> void:
	if tex == null:
		return
	var w := footprint_tiles * TILE * Building.ART_SCALE
	var h := w * float(tex.get_height()) / float(tex.get_width())
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.centered = false
	s.position = Vector2(cx - w * 0.5, ground_y - h)
	s.scale = Vector2(w, h) / Vector2(tex.get_size())
	add_child(s)
	_label(name, Vector2(cx - w * 0.5, ground_y + 4.0))


## Draw a unit sheet's first idle (down) frame, feet on ground_y, at
## the game's DISPLAY_SCALE — exactly Unit sprite math.
func _unit(sheet_path: String, frames_path: String, cx: float, ground_y: float, name: String) -> void:
	if not ResourceLoader.exists(sheet_path) or not FileAccess.file_exists(frames_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	var cell := Vector2i(int(parsed.get("cell_w", 82)), int(parsed.get("cell_h", 82)))
	var baseline := int(parsed.get("baseline", 78))
	var at := AtlasTexture.new()
	at.atlas = load(sheet_path)
	at.region = Rect2(0, 0, cell.x, cell.y)
	var s := Sprite2D.new()
	s.texture = at
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.centered = false
	var sc := 0.68
	s.scale = Vector2(sc, sc)
	s.position = Vector2(cx - cell.x * sc * 0.5, ground_y - baseline * sc)
	add_child(s)
	_label(name, Vector2(cx - 30.0, ground_y + 4.0))


func _ready() -> void:
	# Grass backdrop: the seamless in-game tile, repeated.
	var grass := _tex("res://assets/tiles_seamless/grass_1.png")
	if grass != null:
		for y in range(0, 648, 32):
			for x in range(0, 1152, 32):
				var s := Sprite2D.new()
				s.texture = grass
				s.centered = false
				s.position = Vector2(x, y)
				s.scale = Vector2(TILE, TILE) / Vector2(grass.get_size())
				add_child(s)

	# Row A — big buildings (ground line y=300).
	_building(_tex("res://assets/buildings/towncenter_t3.png"), 150, 300, 3, "TownCenter t3 (REF)")
	_building(_tex("res://assets/buildings/farm_t3.png"), 400, 300, 3, "Farm t3 (NEW)")
	_building(_tex("res://assets/buildings/castle_t3.png"), 640, 300, 4, "Castle t3 (NEW)")
	_building(_tex("res://assets/buildings/farm_t1.png"), 880, 300, 3, "Farm t1 (NEW)")
	_building(_tex("res://assets/buildings/castle_t1.png"), 1060, 300, 4, "Castle t1 (NEW)")

	# Row B — wall pieces at 1-tile footprint scale + field stages (y=430).
	var pieces := [
		["wallwood", "WallWood"], ["wallwood_corner", "Corner"], ["gatewood", "GateWood"],
		["wallstone", "WallStone"], ["wallstone_corner", "Corner"], ["gatestone", "GateStone"],
	]
	var px := 90.0
	for p in pieces:
		_building(_tex("res://assets/buildings/%s.png" % p[0]), px, 430, 1, p[1])
		px += 105.0
	var fx := 760.0
	for i in range(1, 5):
		var t := _tex("res://assets/fields/field_s%d.png" % i)
		if t != null:
			var s := Sprite2D.new()
			s.texture = t
			s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			s.centered = false
			s.position = Vector2(fx, 430 - TILE)
			s.scale = Vector2(TILE, TILE) / Vector2(t.get_size())
			add_child(s)
			_label("Field s%d" % i, Vector2(fx - 6, 434))
		fx += 95.0

	# Row C — units at game scale (ground line y=600).
	_unit("res://assets/villager.png", "res://assets/villager_frames.json", 110, 600, "Villager (REF)")
	_unit("res://assets/militia.png", "res://assets/militia_frames.json", 260, 600, "Militia (REF)")
	_unit("res://assets/spearman.png", "res://assets/spearman_frames.json", 420, 600, "Spearman (NEW)")
	_unit("res://assets/cavalry.png", "res://assets/cavalry_frames.json", 620, 600, "Cavalry (NEW)")
	_unit("res://assets/ram.png", "res://assets/ram_frames.json", 880, 600, "Ram (NEW)")

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_newart_contact_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_newart_contact_v1.png size=", img.get_size())
	get_tree().quit()
