extends Node
## Probe: ink widths of every _small_btn label at 12pt in the
## project's default font, vs the buttons' current widths
## (stylebox content margins L/R = 1 + border 1 per side).

func _ready() -> void:
	var b := Button.new()
	add_child(b)
	await get_tree().process_frame
	var f := b.get_theme_font("font")
	for t in ["Đuổi", "Chi tiết", "Lên Phó", "Hạ Phó", "Chuyển quyền",
			"Đã chắc? Bấm lại", "Mời", "Đã ở liên minh", "Đóng"]:
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		print("PROBE txt '", t, "' ink=", snappedf(w, 0.1),
			" btn_now=", snappedf(w + 4.0, 0.1),
			" btn_pad8=", snappedf(w + 18.0, 0.1))
	print("PROBE DONE")
	get_tree().quit()
