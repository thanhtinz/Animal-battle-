extends Node
## Probe: build ONE chat line through the REAL ChatHub
## _line_row and dump every Label's geometry.

func _dump(n: Node, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	if n is Label:
		var l := n as Label
		print("PROBE", pad, "LABEL '", l.text, "' pos=", l.global_position,
			" size=", l.size, " visible=", l.visible)
	for c in n.get_children():
		_dump(c, depth + 1)


func _ready() -> void:
	var hub = load("res://scripts/chat_hub.gd").new()
	add_child(hub)
	var line := {"name": "HubShotA", "text": "Chao ca nha", "tag": "HA17",
		"title": "Vo dich", "user": "hubshota", "ts": 1762000000,
		"avatar_id": "art_01", "frame_id": "", "bubble": "mac_dinh",
		"id": "w1", "reactions": {}}
	var cell: Control = hub._line_row(line, "world")
	cell.position = Vector2(40, 140)
	cell.size = Vector2(660, 60)
	add_child(cell)
	await get_tree().process_frame
	await get_tree().process_frame
	_dump(cell, 0)
	get_tree().quit()
