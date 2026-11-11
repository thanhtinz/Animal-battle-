extends Node
## Mode-choice panel capture (13i follow-up): boots the game,
## logs in as the harness's seeded account DIRECTLY through
## Net (the Net auto-driver only arms on its shot flags, and
## its home-shot flow would quit the tree before the panel
## opens — so this scene drives the login itself), waits for
## the home to fill, opens the BẮT ĐẦU mode-choice panel and
## photographs it. Needs the seeded relay from
## capture_home_v6.sh running on 127.0.0.1:8765:
## xvfb-run -a -s "-screen 0 1280x800x24" godot --path <proj> \
##   --resolution 1280x720 res://tests/capture_mode_panel.tscn
##
## NOTE: every timer here passes process_always=true — once
## the home screen opens, Main pauses the tree, and a plain
## SceneTreeTimer never fires again (the first version of
## this harness hung forever on exactly that).

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	Net.connect_to_server(Net.DEFAULT_URL)
	var waited := 0.0
	while not Net.connected and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	if Net.connected:
		# The seeded account already exists, so login (register
		# would be rejected as a duplicate — the auto-driver
		# falls back the same way).
		Net.login_account("HiepSi", "secret1")
	waited = 0.0
	while Net.account_name == "" and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	await get_tree().create_timer(1.5, true).timeout
	if game.home != null:
		game.home.refresh()
		game.home._open_mode_panel()
	await get_tree().create_timer(0.7, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_mode_panel_v1.png")
	print("MODE PANEL CAPTURE SAVED size=", img.get_size())
	get_tree().quit()
