extends Node
## 15e-ter staged capture: the observer screen WITH the
## dedicated spectator panel open — the panel (Spectator-owned)
## over a world whose player gameplay HUD is fully gated off
## (no top chips, no action bar, no skill cluster, no selection
## chip; minimap + spectator bar only). Staged locally on the
## SP boot (slot arrays shaped like the suite's spectator
## section) because the live-MP harness's windowed runs kept
## being SIGKILLed by sandbox memory pressure on 2026-11-11;
## the gate itself is production-shaped: observer_mode is set
## and HUD._apply_observer_clean() runs exactly as Main's boot
## applies it for a real observer (there it runs inside
## HUD._ready, before the first frame).
##   xvfb-run -a -s "-screen 0 1400x1000x24" godot --path <proj> \
##     --resolution 1152x864 res://tests/capture_spectator_clean_panel.tscn

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
	# Slot shape of a watched 2-player match (suite's staging).
	game.slot_teams = [0, 1]
	game.slot_names = ["ChuMot", "NguoiHai"]
	game.slot_eliminated = [false, false]
	# A hero for the followed slot so follow + rows have life.
	var tc1 = game.tc_of(1)
	if tc1 != null:
		var c: Vector2 = tc1.position + Vector2(tc1.size) * World.TILE * 0.5
		game._make_unit(1, c + Vector2(140, 60), "king")
	# Become an observer and apply the boot gate.
	game.observer_mode = true
	game.hud._apply_observer_clean()
	var spec = Spectator.new()
	spec.game = game
	game.add_child(spec)
	game.spectator = spec
	spec.set_follow(1)
	await _wait(0.8)
	spec.set_panel_open(true)
	await _wait(0.8)
	await _snap("res://shots/empire_age_spectator_clean_panel_v1.png")
	print("CAPTURE SPECTATOR CLEAN PANEL DONE")
	get_tree().quit()
