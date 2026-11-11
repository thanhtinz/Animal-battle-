extends Node
## Weapon audit capture: every hero in all 8 facings through the
## LIVE rig render path (real Unit + _king_apply_dir), one row per
## hero, saved as raw frames for offline strip assembly.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path <proj> res://tests/capture_weapon_audit.tscn

var game = null
var spawned: Array = []

const HEROES := ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa",
		"loi_chan", "xich_diem", "phong_linh", "thach_son"]
const DIRS := ["s", "se", "e", "ne", "n", "nw", "w", "sw"]


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

	for hero in HEROES:
		for u in spawned:
			if is_instance_valid(u):
				u.visible = false
				u.position = base + Vector2(-600, -600)
		spawned.clear()
		await get_tree().process_frame
		await get_tree().process_frame
		for i in range(8):
			game.slot_chars[0] = hero
			var u = game._make_unit(0, base + Vector2(i * 64, 0), "king")
			u.king_dir8 = DIRS[i]
			u._king_apply_dir(DIRS[i])
			spawned.append(u)
		game.cam.zoom = Vector2(2.2, 2.2)
		game.cam.focus_on(base + Vector2(224, -6))
		await _wait(0.35)
		await _snap("res://shots/audit_raw2_" + hero + ".png")

	print("CAPTURE WEAPON AUDIT DONE")
	get_tree().quit()
