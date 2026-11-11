extends Node
## 14c-fix4-ter match capture: Xích Diệm facing NORTH (back view) in a
## live match — her fan must NOT render at all in back views (owner: "Quay sau lưng bỏ quạt luôn").
## A villager stands beside her as the size ruler.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_fanfix_match.tscn

var game = null


func _snap(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("CAPTURE SAVED ", path, " size=", img.get_size())


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _ready() -> void:
	Net.auto = {"mp-name": "Tin"}
	game = load("res://main.tscn").instantiate()
	add_child(game)
	var guard := 0
	while game.home == null and guard < 1800:
		await get_tree().process_frame
		guard += 1
	await _wait(0.6)

	game.home_quick_match()
	for i in range(6):
		await get_tree().process_frame
	game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = true
	if game.world.sky_layer != null:
		game.world.sky_layer.visible = false
	var anchor: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(7, 7))
	var base: Vector2 = game.world.cell_center(anchor)

	game.slot_chars[0] = "xich_diem"
	var u = game._make_unit(0, base, "king")
	u.king_dir8 = "n"
	u._king_apply_dir("n")
	game._make_unit(0, base + Vector2(46, 6), "villager")
	game.cam.zoom = Vector2(2.4, 2.4)
	game.cam.focus_on(base + Vector2(20, -4))
	await _wait(0.4)
	await _snap("res://shots/empire_age_xichdiem_fan_match_v3.png")

	print("CAPTURE FANFIX MATCH DONE")
	get_tree().quit()
