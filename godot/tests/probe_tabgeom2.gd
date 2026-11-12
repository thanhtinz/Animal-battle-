extends Node
## Probe 2 (17c): build the alliance tab buttons through the
## REAL AllianceScreen helpers and print their geometry.

func _ready() -> void:
	var scr = load("res://scripts/alliance_screen.gd").new()
	add_child(scr)
	await get_tree().process_frame
	for t in ["Thành viên", "Yêu cầu", "Nhiệm vụ", "Hoạt động"]:
		var b: Button = scr._tab_btn("members" if t == "Thành viên" else "quests", t)
		add_child(b)
		await get_tree().process_frame
		var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
		print("PROBE2 '", t, "' minsize=", b.get_combined_minimum_size(),
			" sb_min=", sb.get_minimum_size(),
			" cm L", sb.content_margin_left, " R", sb.content_margin_right,
			" T", sb.content_margin_top, " B", sb.content_margin_bottom)
		var f := b.get_theme_font("font")
		print("PROBE2   font str size=", f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14),
			" fontname=", f.get_font_name() if f.has_method("get_font_name") else "?")
	get_tree().quit()
