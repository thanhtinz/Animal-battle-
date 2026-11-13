class_name ChatHub
extends CanvasLayer

## Empire Age 17e — the CHAT HUB: ONE panel for every
## out-of-match chat surface (the owner's order: "Toàn bộ
## liên quan tới chat sẽ ở đây, trừ chat trong màn game" —
## in-match chat stays in the match, untouched). PageShell
## dialect, four tabs:
##
##   Hệ thống  — read-only feed of REAL events: server system
##               pushes, ranked results, alliance notices,
##               and the account mailbox (letters carry the
##               megaphone-grant paper trail).
##   Thế giới  — the world channel: every online account.
##   Liên minh — the 17a/17b alliance chat ([TAG], champion
##               suffix, bubble-style colours, server-kept
##               history) living here now.
##   Chat riêng — 1:1 DMs: conversation list (friends +
##               recent partners), server-stored per-pair
##               history, unread badges.
##
## Every text tab shares one input bar: [hold-to-talk voice]
## [Loa xN megaphone] [emoticon picker] [field] [Gửi].
## Emoticons are DRAWN assets (scripts/emotes.gd); sending
## inserts a token the server validates. Voice notes are
## live-relayed WAVs (never stored server-side).

const GOLD := Color(1.0, 0.85, 0.4)
const GOLD_TXT := Color(0.98, 0.8, 0.35)
const PAPER := Color(0.92, 0.9, 0.84)
const MUTED := Color(0.62, 0.66, 0.75)
const DIM := Color(0.45, 0.48, 0.58)
const RED := Color(0.98, 0.5, 0.45)
const CARD_BG := Color(0.05, 0.07, 0.13)
const PANEL_LINE := Color(0.30, 0.34, 0.46)
const FIELD_BG := Color(0.04, 0.05, 0.10)
const BTN_BG := Color(0.13, 0.16, 0.24)
# Owner order 2026-11-12: voice + megaphone are ICON buttons.
const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"
const FA_MIC := 0xF130
const FA_BULLHORN := 0xF0A1

const TABS := ["system", "world", "alliance", "dm"]
const TAB_NAMES := {
	"system": "Hệ thống", "world": "Thế giới",
	"alliance": "Liên minh", "dm": "Chat riêng",
}

var game = null # Main (duck-typed)

var _body: VBoxContainer
var _status: Label
var _tab := "world"
var _dm_peer := ""
var _picker_open := false
var _loa_mode := false
var _sig := ""
var _status_msg := ""
var _status_bad := false
var _edit: LineEdit = null
var _draft := ""
var _poll := 0.0
var _rec: VoiceRec = null
var _player: AudioStreamPlayer = null
var _recording := false
var _fa_font: Font = null
var _mic_btn: Button = null


func setup(g) -> void:
	game = g


func _ready() -> void:
	layer = 55 # above profile/alliance (50), below settings (56)
	visible = false
	# Owner order 2026-11-12: AOV-style floating panel, NOT
	# full-screen — dim backdrop, panel ~60% wide on the left,
	# the lobby stays visible on the right.
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.04, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.anchor_right = 0.60
	board.offset_left = 24
	board.offset_right = -14
	board.offset_top = 24
	board.offset_bottom = -56
	var bs := PageShell.bg_style()
	bs.set_corner_radius_all(10)
	bs.border_color = Color(1, 0.85, 0.4, 0.55)
	bs.set_border_width_all(2)
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bs.content_margin_top = 14
	bs.content_margin_bottom = 14
	board.add_theme_stylebox_override("panel", bs)
	add_child(board)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	board.add_child(outer)
	var hrow := HBoxContainer.new()
	hrow.add_child(_label("Chat", 20, Color(1.0, 0.85, 0.4)))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(hsp)
	var xbtn := Button.new()
	xbtn.text = "X"
	xbtn.custom_minimum_size = Vector2(36, 36)
	xbtn.focus_mode = Control.FOCUS_NONE
	xbtn.add_theme_color_override("font_color", Color.WHITE)
	xbtn.add_theme_stylebox_override("normal",
			_sb(Color(0.72, 0.16, 0.14), 8, Color(0, 0, 0, 0), 0))
	xbtn.add_theme_stylebox_override("hover",
			_sb(Color(0.82, 0.22, 0.18), 8, Color(0, 0, 0, 0), 0))
	xbtn.add_theme_stylebox_override("pressed",
			_sb(Color(0.60, 0.12, 0.11), 8, Color(0, 0, 0, 0), 0))
	xbtn.pressed.connect(func() -> void: close())
	hrow.add_child(xbtn)
	outer.add_child(hrow)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_body)
	_status = _label("", 13, Color(1.0, 0.75, 0.6))
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.anchor_right = 0.60
	_status.offset_top = -48
	_status.offset_bottom = -26
	_status.offset_left = 40
	_status.offset_right = -30
	add_child(_status)
	_rec = VoiceRec.new()
	add_child(_rec)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	Net.chat_line_received.connect(func(_m: Dictionary) -> void:
		if visible: _render())
	Net.voice_line_received.connect(func(_m: Dictionary, _w: PackedByteArray) -> void:
		if visible: _render())
	Net.dm_list_received.connect(func(_rows: Array) -> void:
		if visible: _render())
	Net.dm_thread_received.connect(func(_p: String, _rows: Array) -> void:
		if visible: _render())
	Net.dm_line_received.connect(func(_p: String, _mine: bool) -> void:
		if visible: _render())
	Net.system_feed_changed.connect(func() -> void:
		if visible: _render())
	Net.megaphones_changed.connect(func(_n: int) -> void:
		if visible: _render())
	Net.mail_received.connect(func(_rows: Array, _unread: int) -> void:
		if visible: _render())
	Net.alliance_home_received.connect(func(_mine: Dictionary, _inv: Array) -> void:
		if visible: _render())
	Net.lobby_error.connect(func(msg: String) -> void:
		if visible:
			_set_status(msg, true)
			_sig = "" # force the status into the next render
			_render())


func open(tab: String = "world") -> void:
	_tab = tab if TABS.has(tab) else "world"
	if _tab == "dm":
		Net.dm_request_list()
	visible = true
	_sig = ""
	_render()


func close() -> void:
	visible = false
	if _recording:
		_rec.stop_recording()
		_recording = false


func shot_open_picker() -> void:
	open("world")
	_picker_open = true
	_sig = ""
	_render()


func shot_open_thread(peer: String) -> void:
	open("dm")
	_dm_peer = peer
	_sig = ""
	_render()


func _process(delta: float) -> void:
	if not visible:
		return
	if _recording:
		if _rec.auto_stopped():
			_finish_recording()
		elif _mic_btn != null:
			_mic_btn.add_theme_color_override("font_color",
					Color(1.0, 0.52, 0.45))
	_poll += delta
	if _poll >= 0.6:
		_poll = 0.0
		_render()


# ------------------------------------------------------------ shell

func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


func _btn_sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := _sb(bg, radius, border, bw)
	s.content_margin_left = 1
	s.content_margin_right = 1
	s.content_margin_top = 0
	s.content_margin_bottom = 2
	return s


func _label(text: String, fsize: int, col: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label_wrap(text: String, fsize: int, col: Color = PAPER) -> Label:
	var l := _label(text, fsize, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A Font Awesome glyph as a tintable Label (same pattern as
## the other screens' _fa helpers).
func _fa(cp: int, px: int, col: Color = PAPER) -> Label:
	if _fa_font == null:
		_fa_font = load(FA_FONT_PATH)
	var l := Label.new()
	l.text = String.chr(cp)
	l.add_theme_font_override("font", _fa_font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(px + 6, px + 6)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Icon + count toggle chip (the megaphone): a styled panel
## with an FA glyph and a small count label, flat Button on top.
func _loa_chip() -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(78, 38)
	if _loa_mode:
		holder.add_theme_stylebox_override("panel",
				_btn_sb(Color(0.98, 0.8, 0.35), 8))
	else:
		holder.add_theme_stylebox_override("panel",
				_btn_sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(hb)
	var ink := Color(0.1, 0.08, 0.02) if _loa_mode else PAPER
	hb.add_child(_fa(FA_BULLHORN, 15, ink))
	var cnt := _label("x%d" % Net.megaphone_count, 13, ink)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(cnt)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = "Loa thông báo"
	btn.pressed.connect(func() -> void:
		_loa_mode = not _loa_mode
		_sig = ""
		_render())
	holder.add_child(btn)
	return holder


func _button(text: String, primary := false, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 38)
	b.add_theme_font_size_override("font_size", 14)
	if primary:
		b.add_theme_stylebox_override("normal", _btn_sb(Color(0.98, 0.8, 0.35), 8))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(1.0, 0.86, 0.45), 8))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.88, 0.7, 0.28), 8))
		b.add_theme_stylebox_override("disabled", _btn_sb(Color(0.35, 0.33, 0.28), 8))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_disabled_color", Color(0.6, 0.58, 0.52))
	else:
		b.add_theme_stylebox_override("normal", _btn_sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(0.18, 0.22, 0.32), 8, Color(1, 0.85, 0.4, 0.6), 1))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(0.09, 0.11, 0.19), 8, Color(1, 0.85, 0.4, 0.35), 1))
		b.add_theme_color_override("font_color", PAPER)
		b.add_theme_color_override("font_hover_color", PAPER)
	return b


func _card() -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", _sb(CARD_BG, 10, PANEL_LINE, 1))
	return c


func _set_status(msg: String, bad: bool) -> void:
	_status_msg = msg
	_status_bad = bad
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color",
			Color(1.0, 0.62, 0.55) if bad else Color(0.75, 0.95, 0.7))


func _tab_btn(id: String) -> Button:
	var text := String(TAB_NAMES[id])
	if id == "dm" and Net.dm_total_unread() > 0:
		text += " (%d)" % Net.dm_total_unread()
	var b := _button(text)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _tab == id:
		var edge := Color(0.72, 0.52, 0.15)
		b.add_theme_stylebox_override("normal", _btn_sb(Color(0.98, 0.8, 0.35), 8, edge, 1))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(1.0, 0.86, 0.45), 8, edge, 1))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	b.pressed.connect(func() -> void:
		_tab = id
		_picker_open = false
		_loa_mode = false
		if id == "dm":
			_dm_peer = ""
			Net.dm_request_list()
		_sig = ""
		_render())
	return b


# ------------------------------------------------------------ render

func _render() -> void:
	if _body == null or not visible:
		return
	if _edit != null and is_instance_valid(_edit):
		_draft = _edit.text
	var last_world := ""
	if not Net.world_chat_lines.is_empty():
		last_world = String(Net.world_chat_lines[Net.world_chat_lines.size() - 1].get("text", ""))
	var sig := JSON.stringify([_tab, _dm_peer, _picker_open, _loa_mode,
		Net.world_chat_lines.size(), last_world,
		Net.alliance_chat_lines.size(), Net.dm_convs,
		(Net.dm_threads.get(_dm_peer, []) as Array).size(),
		Net.system_feed.size(), Net.mail_rows.size(),
		Net.megaphone_count, Net.account_name,
		String(Net.alliance_mine.get("name", "")), Net.friends_rows.size(),
		Net.dm_total_unread()])
	if sig == _sig:
		return
	_sig = sig
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_edit = null
	_mic_btn = null
	if _status != null:
		_status.text = _status_msg
	if Net.account_name == "":
		_body.add_child(_label_wrap(
			"Đăng nhập để dùng Chat — kênh thế giới, liên minh và chat riêng chỉ dành cho tài khoản.", 15, MUTED))
		return
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for id in TABS:
		tabs.add_child(_tab_btn(id))
	_body.add_child(tabs)
	match _tab:
		"system":
			_build_system()
		"world":
			_build_lines(Net.world_chat_lines, "world")
		"alliance":
			_build_alliance()
		"dm":
			_build_dm()


func _scroll_box() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return sc


func _scroll_to_bottom(sc: ScrollContainer) -> void:
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _line_row(line: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bubble := String(line.get("bubble", "mac_dinh"))
	var st: Dictionary = ChatBubbles.STYLES.get(bubble, ChatBubbles.STYLES["mac_dinh"])
	var name := Net._decor_name(String(line.get("name", "?")),
		String(line.get("tag", "")), bool(line.get("champ", false)))
	var nl := _label(name + ":", 14, Color(st["text"]))
	nl.custom_minimum_size = Vector2(150, 0)
	nl.clip_text = true
	row.add_child(nl)
	if bool(line.get("voice", false)):
		row.add_child(_voice_cell(line))
		return row
	var body := Emotes.make_rich(String(line.get("text", "")), 14, PAPER)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return row


func _voice_cell(line: Dictionary) -> Control:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 8)
	var play := _button("Nghe", false, 64)
	play.custom_minimum_size = Vector2(64, 32)
	var data: PackedByteArray = line.get("data", PackedByteArray())
	play.pressed.connect(func() -> void:
		var stream := VoiceRec.make_stream(data)
		if stream != null:
			_player.stream = stream
			_player.play())
	cell.add_child(play)
	var dur := float(line.get("dur", 0.0))
	if dur <= 0.0 and not data.is_empty():
		dur = float(VoiceRec.wav_info(data).get("dur", 0.0))
	cell.add_child(_label("Tin nhắn thoại • %d giây" % int(ceil(dur)), 13, MUTED))
	return cell


func _build_lines(lines: Array, channel: String) -> void:
	var card := _card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := _scroll_box()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	card.add_child(sc)
	if lines.is_empty():
		vb.add_child(_label_wrap("Chưa có tin nhắn nào.", 14, MUTED))
	for line in lines:
		vb.add_child(_line_row(line))
	_body.add_child(card)
	_scroll_to_bottom(sc)
	if _picker_open:
		_body.add_child(_picker_panel())
	_body.add_child(_input_bar(channel))


func _build_alliance() -> void:
	if Net.alliance_mine.is_empty():
		var card := _card()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 10)
		card.add_child(vb)
		vb.add_child(_label_wrap(
			"Bạn chưa thuộc liên minh nào — kênh Liên minh sẽ mở khi bạn gia nhập một liên minh.", 15, MUTED))
		var go := _button("Mở trang Liên minh", true, 200)
		go.pressed.connect(func() -> void:
			if game != null and game.has_method("home_open_alliance"):
				game.home_open_alliance())
		vb.add_child(go)
		_body.add_child(card)
		return
	_build_lines(Net.alliance_chat_lines, "alliance")


func _build_system() -> void:
	var card := _card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := _scroll_box()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	card.add_child(sc)
	_body.add_child(card)
	var any := false
	for e in Net.system_feed:
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_label("[Hệ thống]", 14, RED))
		row.add_child(_label_wrap(String(e.get("text", "")), 14, PAPER))
		vb.add_child(row)
	for l in Net.mail_rows:
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_label("[Thư]", 14, GOLD_TXT))
		var txt := String(l.get("title", ""))
		var body := String(l.get("body", ""))
		if body != "":
			txt += " — " + body
		row.add_child(_label_wrap(txt, 14, PAPER if bool(l.get("read", false)) else Color(1, 1, 1)))
		vb.add_child(row)
	if not any:
		vb.add_child(_label_wrap(
			"Chưa có thông báo nào. Kết quả trận, thư và thông báo của máy chủ sẽ hiện ở đây.", 14, MUTED))
	_scroll_to_bottom(sc)


# ------------------------------------------------------------ DM tab

func _build_dm() -> void:
	if _dm_peer == "":
		_build_dm_list()
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var back := _button("‹ Danh sách", false, 110)
	back.pressed.connect(func() -> void:
		_dm_peer = ""
		Net.dm_request_list()
		_sig = ""
		_render())
	head.add_child(back)
	head.add_child(_label(_dm_name(_dm_peer), 16, GOLD_TXT))
	_body.add_child(head)
	_build_lines(Net.dm_threads.get(_dm_peer, []), "dm")


func _dm_name(user: String) -> String:
	for r in Net.dm_convs:
		if String(r.get("user", "")) == user:
			return String(r.get("name", user))
	for f in Net.friends_rows:
		if String(f.get("user", "")) == user:
			return String(f.get("name", user))
	return user


func _build_dm_list() -> void:
	var card := _card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := _scroll_box()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	card.add_child(sc)
	_body.add_child(card)
	var seen := {}
	for r in Net.dm_convs:
		var user := String(r.get("user", ""))
		if user == "":
			continue
		seen[user] = true
		vb.add_child(_dm_row(user, String(r.get("name", user)),
			String(r.get("last_text", "")), int(r.get("unread", 0))))
	# Friends without a thread yet: one tap starts one.
	var fresh := false
	for f in Net.friends_rows:
		var user := String(f.get("user", ""))
		if user == "" or seen.has(user):
			continue
		if not fresh:
			fresh = true
			vb.add_child(_label("Bạn bè — chạm để bắt đầu trò chuyện", 13, GOLD_TXT))
		vb.add_child(_dm_row(user, String(f.get("name", user)), "", 0))
	if vb.get_child_count() == 0:
		vb.add_child(_label_wrap(
			"Chưa có cuộc trò chuyện nào. Kết bạn ở trang Bạn bè rồi quay lại đây để nhắn riêng.", 14, MUTED))


func _dm_row(user: String, disp: String, last: String, unread: int) -> Control:
	var b := Button.new()
	b.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_stylebox_override("normal", _btn_sb(BTN_BG, 8, Color(1, 0.85, 0.4, 0.25), 1))
	b.add_theme_stylebox_override("hover", _btn_sb(Color(0.18, 0.22, 0.32), 8, Color(1, 0.85, 0.4, 0.55), 1))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", PAPER)
	var text := disp
	if last != "":
		text += "   —   " + Emotes.strip_tokens(last)
	if unread > 0:
		text += "   •   %d tin chưa đọc" % unread
	b.text = text
	b.pressed.connect(func() -> void:
		_dm_peer = user
		Net.dm_open(user)
		_sig = ""
		_render())
	return b


# ------------------------------------------------------------ input

func _input_bar(channel: String) -> Control:
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	if _loa_mode:
		bar.add_child(_label_wrap(
			"Chế độ Loa thông báo: nội dung sẽ chạy chữ trên cùng màn hình của MỌI người chơi đang trực tuyến. Gửi tốn 1 Loa (đang có x%d)." % Net.megaphone_count,
			13, GOLD_TXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# Hold-to-talk voice (owner order: icon, not a text button).
	var mic := _button("", false, 48)
	if _fa_font == null:
		_fa_font = load(FA_FONT_PATH)
	mic.add_theme_font_override("font", _fa_font)
	mic.add_theme_font_size_override("font_size", 16)
	mic.text = String.chr(FA_MIC)
	mic.tooltip_text = "Giữ để ghi âm"
	mic.toggle_mode = false
	mic.button_down.connect(func() -> void: _start_recording(channel, mic))
	mic.button_up.connect(func() -> void:
		if _recording:
			_finish_recording())
	row.add_child(mic)
	_mic_btn = mic
	# Megaphone toggle (owner order: icon + count chip).
	row.add_child(_loa_chip())
	# Emoticon picker toggle (the button IS one of the set).
	var pick := TextureButton.new()
	pick.texture_normal = Emotes.texture("vui")
	pick.ignore_texture_size = true
	pick.custom_minimum_size = Vector2(38, 38)
	pick.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	pick.tooltip_text = "Biểu cảm"
	pick.pressed.connect(func() -> void:
		_picker_open = not _picker_open
		_sig = ""
		_render())
	row.add_child(pick)
	# Text field.
	var edit := LineEdit.new()
	edit.placeholder_text = "Nhập tin nhắn…"
	edit.text = _draft
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 38)
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_stylebox_override("normal", _sb(FIELD_BG, 8, PANEL_LINE, 1))
	edit.add_theme_stylebox_override("focus", _sb(FIELD_BG, 8, GOLD, 1))
	edit.max_length = 200
	edit.text_submitted.connect(func(_t: String) -> void: _send_current(channel))
	row.add_child(edit)
	_edit = edit
	var send := _button("Gửi Loa" if _loa_mode else "Gửi", true, 76)
	send.pressed.connect(func() -> void: _send_current(channel))
	row.add_child(send)
	bar.add_child(row)
	return bar


func _picker_panel() -> Control:
	var card := _card()
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for id in Emotes.IDS:
		var tb := TextureButton.new()
		tb.texture_normal = Emotes.texture(id)
		tb.custom_minimum_size = Vector2(40, 40)
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.tooltip_text = id
		var eid := id
		tb.pressed.connect(func() -> void:
			if _edit != null and is_instance_valid(_edit):
				_edit.insert_text_at_caret(Emotes.token_of(eid) + " ")
				_edit.grab_focus()
			_picker_open = false
			_sig = ""
			_render())
		grid.add_child(tb)
	return card


func _send_current(channel: String) -> void:
	if _edit == null or not is_instance_valid(_edit):
		return
	var text := _edit.text.strip_edges()
	if text == "":
		return
	if _loa_mode:
		Net.use_megaphone(text)
		_loa_mode = false
	else:
		match channel:
			"world":
				Net.world_chat(text)
			"alliance":
				Net.alliance_chat(text)
			"dm":
				if _dm_peer != "":
					Net.dm_send(_dm_peer, text)
	_edit.text = ""
	_draft = ""
	_sig = ""
	_render()


# ------------------------------------------------------------ voice

func _start_recording(channel: String, btn: Button) -> void:
	if _recording:
		return
	_recording = true
	_mic_btn = btn
	btn.add_theme_color_override("font_color", Color(1.0, 0.52, 0.45))
	_set_status("Đang ghi âm — thả nút mic để gửi.", false)
	_rec.start_recording()
	# Remember the target on the button for the finish step.
	btn.set_meta("channel", channel)


func _finish_recording() -> void:
	_recording = false
	var channel := "world"
	if _mic_btn != null and is_instance_valid(_mic_btn):
		channel = String(_mic_btn.get_meta("channel", "world"))
		_mic_btn.add_theme_color_override("font_color", PAPER)
	var take: Dictionary = _rec.stop_recording()
	var wav: PackedByteArray = take.get("wav", PackedByteArray())
	var dur := float(take.get("dur", 0.0))
	if wav.is_empty() or dur < 0.4:
		_set_status("Ghi âm quá ngắn hoặc không có mic — giữ nút lâu hơn một chút.", true)
		return
	match channel:
		"world":
			Net.world_voice(wav, dur)
		"alliance":
			Net.alliance_voice(wav, dur)
		"dm":
			if _dm_peer != "":
				Net.dm_voice(_dm_peer, wav, dur)
