extends Node
## 16a verification capture: the eight NEW medieval heroes rendered
## from their live rig data (hero_rig.json entries + part/weapon
## textures) for the dirs s / ne / n / nw. The heroes are not
## registered in Characters until stage 2, so Unit._setup_king_sprite
## cannot spawn them yet; this harness replicates Unit._rig_build_dir
## 1:1 (same base anchor, pivot/offset/scale/z compose, weapon rest
## pose) at 2x the game's 0.49 display scale for a readable strip.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_medieval8.tscn

const HEROES := ["knight", "berserker", "archer", "mage",
		"paladin", "dragoon", "assassin", "ranger"]
const DIRS := ["s", "ne", "n", "nw"]
const DS := 0.49 # the roster's true in-game display scale
const CELL := Vector2(140, 150)
const ORIGIN := Vector2(75, 140) # feet point of cell (0,0)


func _build_rig(hero: String, dir8: String, feet: Vector2) -> void:
	var dd := HeroRig.dir_data(hero, dir8)
	var canvas: Array = dd.get("canvas", [64, 92])
	var base := feet + Vector2(-float(canvas[0]) * DS * 0.5, -float(canvas[1]) * DS)
	var root := Node2D.new()
	add_child(root)
	var parts: Dictionary = dd.get("parts", {})
	for key in parts:
		var pd: Dictionary = parts[key]
		var s := Sprite2D.new()
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.texture = HeroRig.tex(String(pd.get("tex", "")))
		if s.texture == null:
			continue
		var pv: Array = pd.get("pivot", [0, 0])
		var pivot := Vector2(float(pv[0]), float(pv[1]))
		s.position = base + pivot * DS
		s.offset = -pivot
		s.scale = Vector2.ONE * DS
		s.z_index = int(pd.get("z", 2))
		root.add_child(s)
	var wp: Dictionary = dd.get("weapon", {})
	if not wp.is_empty():
		var ws := Sprite2D.new()
		ws.centered = false
		ws.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ws.texture = HeroRig.tex(String(HeroRig.char_data(hero)
				.get("weapon", {}).get("tex", "")))
		if ws.texture != null:
			var wscale := float(HeroRig.char_data(hero)
					.get("weapon", {}).get("wscale", 1.0))
			ws.scale = Vector2.ONE * DS * wscale
			ws.z_index = int(wp.get("z", 6))
			var grip_a: Array = HeroRig.char_data(hero) \
					.get("weapon", {}).get("grip", [0, 0])
			var hand_a: Array = wp.get("hand", [0, 0])
			ws.position = base + Vector2(float(hand_a[0]),
					float(hand_a[1])) * DS
			ws.offset = -Vector2(float(grip_a[0]), float(grip_a[1]))
			ws.rotation = deg_to_rad(float(wp.get("rest", 0.0)))
			root.add_child(ws)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(1, 0, 1)
	bg.size = Vector2(1152, 648)
	add_child(bg)
	for r in range(DIRS.size()):
		for c in range(HEROES.size()):
			var feet := ORIGIN + Vector2(c * CELL.x, r * CELL.y)
			_build_rig(HEROES[c], DIRS[r], feet)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/medieval8_raw.png")
	print("CAPTURE SAVED res://shots/medieval8_raw.png size=", img.get_size())
	get_tree().quit()
