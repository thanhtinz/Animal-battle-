extends Node
## Idle-friend presence helper for the 13m friends captures:
## boots the game, logs in as CongTuoc1 and simply stays
## online, so the capturing client (HiepSi) sees one friend
## live with a presence dot. The harness kills this process
## when the captures are done; it never quits on its own.

func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(1.2).timeout
	Net.connect_to_server("ws://127.0.0.1:8765/ws")
	await get_tree().create_timer(1.2).timeout
	Net.login_account("CongTuoc1", "secret1")
	print("IDLE FRIEND LOGIN SENT")
