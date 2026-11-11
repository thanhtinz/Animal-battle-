class_name PageShell
extends RefCounted

## Shared page shell (13q) — Tín's unification order for the
## three info pages (Hồ sơ / Bạn bè / Bảng xếp hạng): "Màu
## background phải đồng nhất. Header sẽ là nút quay lại xong
## kế bên là title trang phải match với nhau." This file is
## the ONE place that defines both invariants:
##
## BACKGROUND — every info page is the same solid deep-navy
## colour (BG), full-screen edge-to-edge, fully opaque: no
## home art, no per-page gradient or tint. The colour is the
## friends board's long-standing solid navy, the one true
## solid page background the three pages already had.
##
## HEADER — every info page carries the identical header:
## the gold back pill at (11, 11) — the profile screen's
## long-standing back button, geometry and look copied
## verbatim — with the page title label immediately to its
## right, same size/colour, vertically centred on the
## button. Page content starts below CONTENT_TOP (67 = 11 +
## 44 button + 12 gap, the profile panel's existing inset).
## Page-specific header extras (the friends search box) hang
## off the header's right end and never touch this block.

const BG := Color(0.02, 0.035, 0.085, 1.0)

const TITLE_COLOR := Color(0.98, 0.8, 0.35)
const TITLE_SIZE := 27
const BACK_POS := Vector2(11, 11)
const BACK_SIZE := Vector2(92, 44)
const TITLE_POS := Vector2(115, 11) # 11 + 92 + 12 gap
const CONTENT_TOP := 67.0


## The shared page background as a flat stylebox (radius 0).
static func bg_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG
	s.set_corner_radius_all(0)
	return s


## The shared back button: the profile screen's gold pill,
## verbatim — a 92×44 gold-brown pill at (11, 11), the back
## glyph centred in it, a flat Button taking the clicks.
static func back_button(on_back: Callable) -> PanelContainer:
	var back := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.22, 0.05, 0.95)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(1, 0.85, 0.4, 0.8)
	sb.set_border_width_all(2)
	back.add_theme_stylebox_override("panel", sb)
	back.position = BACK_POS
	back.custom_minimum_size = BACK_SIZE
	back.size = BACK_SIZE
	var bic := GlassIcon.new()
	bic.kind = "back"
	bic.custom_minimum_size = Vector2(26, 26)
	bic.size = Vector2(26, 26)
	bic.position = Vector2(33, 9)
	bic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(bic)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = "Quay lại"
	if on_back.is_valid():
		btn.pressed.connect(on_back)
	back.add_child(btn)
	return back


## The shared page title: same size and colour on every
## page, in a 44-tall strip level with the back button so
## the text's vertical centre IS the button's centre (y=33).
static func title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", TITLE_SIZE)
	l.add_theme_color_override("font_color", TITLE_COLOR)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = TITLE_POS
	l.size = Vector2(600, BACK_SIZE.y)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The full shared header as an overlay: add it to the
## page's root AFTER the page background so it draws on top.
## Returns the overlay so a page can hang right-end extras
## (search boxes) off it.
static func header(title_text: String, on_back: Callable) -> Control:
	var h := Control.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(back_button(on_back))
	h.add_child(title_label(title_text))
	return h
