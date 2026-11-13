extends Node
## TOUR capture: Chat hub "Hệ thống" tab (17e). Store seeded
## by tests/capture_tour_system.sh — HubShotA holds real mail
## letters; the tab renders the system feed + mailbox rows.
## Needs the relay on Net.DEFAULT_URL still running.

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	Net.connect_to_server(Net.DEFAULT_URL)
	var waited := 0.0
	while not Net.connected and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	if Net.connected:
		Net.login_account("HubShotA", "secret1")
	waited = 0.0
	while Net.account_name == "" and waited < 25.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	# The mailbox is pull-based: ask for it like the real UI does.
	Net.request_mail()
	waited = 0.0
	while Net.mail_rows.is_empty() and waited < 8.0:
		await get_tree().create_timer(0.5, true).timeout
		waited += 0.5
	await get_tree().create_timer(0.8, true).timeout
	game.open_chat_hub_shot("system")
	await get_tree().create_timer(1.4, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_chathub_system_tour_v1.png")
	print("TOUR CHATHUB SYSTEM CAPTURE SAVED size=", img.get_size(),
		" mail_rows=", Net.mail_rows.size(),
		" system_feed=", Net.system_feed.size())
	get_tree().quit()
