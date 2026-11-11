extends Node
## Glyph-level proof sheet for the ping-meter correction:
## the real GlassIcon "signal_meter" drawn at all three
## bands (0 bad / 1 medium / 2 good), big, over a sky-blue
## backdrop with the same offset black silhouette the home
## build puts behind the glyph. Band 2 must read as the
## WHOLE glyph green (dot + arcs) — "xanh là toàn bộ
## xanh". Live-band captures live in capture_ping_v2.sh;
## this sheet exists because this sandbox's localhost
## samples floor around ~110 ms, so a live sub-100 ms
## sample may never occur during a capture window.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.45, 0.78)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	for i in range(3):
		var cx := 213.0 + float(i) * 427.0
		var sh := GlassIcon.new()
		sh.kind = "signal_meter"
		sh.signal_band = i
		sh.size = Vector2(192, 192)
		sh.position = Vector2(cx - 96.0 + 5.0, 269.0)
		sh.modulate = Color(0, 0, 0, 0.4)
		add_child(sh)
		var ic := GlassIcon.new()
		ic.kind = "signal_meter"
		ic.signal_band = i
		ic.size = Vector2(192, 192)
		ic.position = Vector2(cx - 96.0, 264.0)
		add_child(ic)
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/empire_age_home_ping_v2_bands.png")
	print("CAPTURE SAVED res://shots/empire_age_home_ping_v2_bands.png")
	get_tree().quit()
