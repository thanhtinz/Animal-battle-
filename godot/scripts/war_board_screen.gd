class_name WarBoardScreen
extends CanvasLayer

## War board screen — the public face of the Đại chiến
## liên minh (alliance war) bracket. Owner order
## 2026-11-12: the lobby entry is a prominent horizontal
## gold button under the season banner ("XEM BẢNG ĐẤU"),
## replacing the spec's earlier carousel-slide idea.
##
## The monthly tournament itself is Phase 2 of
## DAI-CHIEN-LIEN-MINH-SPEC.md (registration, roster lock,
## referee-run rounds); until it runs, this screen shows
## the honest off-season state: the format, the monthly
## schedule and an empty board area. When Phase 2 lands,
## the bracket renders here from the server payload and
## the alliance screen's war tab shows the same board.

const GOLD := Color(0.98, 0.8, 0.35)
const PAPER := Color(0.96, 0.94, 0.88)
const MUTED := Color(0.72, 0.76, 0.86)

var game = null

var _root: Control
var _box: VBoxContainer


func setup(p_game) -> void:
	game = p_game
	layer = 50 # above home (40), below the MP lobby (60)
	_build()
	visible = false


func open() -> void:
	visible = true
	_render()


func close() -> void:
	visible = false


func _on_back() -> void:
	close()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bs := PageShell.bg_style()
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bs.content_margin_top = PageShell.CONTENT_TOP
	bs.content_margin_bottom = 16
	board.add_theme_stylebox_override("panel", bs)
	_root.add_child(board)
	var scroll := ScrollContainer.new()
	board.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	_root.add_child(PageShell.header("Bảng đấu",
			Callable(self, "_on_back")))


func _render() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var intro := _label("Đại chiến liên minh — hai liên minh đấu 8 vs 8 trên một bản đồ, Đỏ vs Xanh, phá Citadel để thắng.", 14, PAPER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(intro)
	_box.add_child(_card("Lịch giải hằng tháng",
			"Mở đăng ký ngày 1 · Khoá danh sách ngày 4 · Các vòng đấu tối thứ Bảy 20:00 · Chung kết thứ Bảy cuối tháng."))
	var empty := _label("Hiện chưa có bảng đấu nào đang diễn ra.", 15, MUTED)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_box.add_child(empty)
	var note := _label("Bảng đấu của giải tháng sẽ hiện tại đây khi giải mở.", 13, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(note)


func _card(title: String, body: String) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.13, 1.0)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(1, 0.85, 0.4, 0.35)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	vb.add_child(_label(title, 14, GOLD))
	var b := _label(body, 13, PAPER)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(b)
	return card


func _label(text: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
