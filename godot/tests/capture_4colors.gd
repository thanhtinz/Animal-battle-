extends Node
## Team-colors capture (Tín's rule: 4 slots = 4 colours, ONE sprite
## set): xvfb-run -a -s "-screen 0 1152x648x24" godot --path <proj> res://tests/capture_4colors.tscn
## Four columns, one per SLOT (0 Đỏ / 1 Xanh dương / 2 Xanh lá /
## 3 Vàng): a House behind (tier art flags/roofs in slot colours)
## and Villager + Militia + Archer in front, all wearing the SAME
## base sprites recoloured per slot. Every unit is slightly damaged
## so the HP bars show their slot colours; each column's Militia is
## selected so its selection ring shows too. A King sprite in each
## slot's colours stands at the front of each column (asset only —
## the King is not gameplay yet). All units are team 0 so nobody
## fights during the shot; only owner_id (the colour key) differs.

var game = null
var w = null


func find_spot(size: Vector2i, near: Vector2i) -> Vector2i:
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := near + Vector2i(dx, dy)
				if cand.x >= 0 and cand.y >= 0 and w.can_place(cand, size):
					return cand
	return Vector2i(-1, -1)


func _ready() -> void:
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.choose_map(game.biome_id, game.layout_id) # close map panel, unpause
	await get_tree().process_frame
	w = game.world
	# Presentation-only staging: lift the fog so all four columns
	# read in one frame, and hide the drifting clouds.
	for i in range(game.fog.state.size()):
		game.fog.state[i] = 2
	if w.sky_layer != null:
		w.sky_layer.visible = false
	if game.enemy_ai != null:
		game.enemy_ai.set("waves_enabled", false)
	var tc_o: Vector2i = game.player_tc.origin_cell

	# Park the starting villagers south-west, off-stage.
	for u in game.units:
		if u.team == 0 and u.unit_type == "villager":
			u.global_position = w.cell_center(w.nearest_walkable(tc_o + Vector2i(-5, 9)))
			u.state = "idle"
			u.path.clear()

	var kinds := ["villager", "militia", "archer"]
	var row_y: int = tc_o.y - 8
	# The player base hugs the map's west edge: stage the columns
	# EAST of the TC so all four fit inside the camera's clamp.
	var col_x0: int = tc_o.x - 1
	var first_pos := Vector2.ZERO
	var last_pos := Vector2.ZERO
	for slot in range(4):
		var cx: int = col_x0 + slot * 6
		var h_spot := find_spot(Vector2i(2, 2), Vector2i(cx, row_y - 5))
		if h_spot.x >= 0:
			game._spawn_building("house", 0, h_spot, true, slot)
		for i in range(kinds.size()):
			var cell: Vector2i = w.nearest_walkable(Vector2i(cx + i * 2, row_y))
			var u: Unit = game._make_unit(0, w.cell_center(cell), kinds[i], slot)
			u.state = "idle"
			u.path.clear()
			u.hp = u.max_hp * 0.65 # HP bar visible, in the slot colour
			if kinds[i] == "militia":
				u.selected = true # selection ring in the slot colour
			if slot == 0 and i == 0:
				first_pos = u.global_position
			if slot == 3 and i == kinds.size() - 1:
				last_pos = u.global_position
		# King of this slot's colours, front and centre of the column.
		var king := Sprite2D.new()
		king.texture = load(TeamColors.king_path(slot))
		king.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var ks := 44.0 / float(king.texture.get_height())
		king.scale = Vector2(ks, ks)
		king.centered = true
		king.position = w.cell_center(Vector2i(cx + 2, row_y + 3)) + Vector2(0, -14)
		king.z_index = 40
		add_child(king)

	await get_tree().process_frame
	await get_tree().process_frame

	var mid := (first_pos + last_pos) * 0.5
	game.cam.zoom = Vector2(0.85, 0.85) # zoom first: focus_on clamps by view size
	game.cam.focus_on(mid + Vector2(0, 10))
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_4colors_v1.png")
	print("CAPTURE SAVED res://shots/empire_age_4colors_v1.png size=", img.get_size())
	get_tree().quit()
