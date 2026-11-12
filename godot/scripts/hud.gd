class_name HUD
extends CanvasLayer
## Glass in-match HUD (layout follows Tín's reference, frosted-glass style):
## top glass bar (player chip, age badge, 5 resource chips with real gather
## rates, population, match timer, round buttons),
## bottom-left live minimap + 3 side buttons, bottom-right 4 glass action
## buttons (Xây dựng / Huấn luyện / Công nghệ / Khác) with sub-panels, and a
## slim selection chip bottom-center. Large panels try a real screen-blur
## frosted shader; panels keep a translucent navy stylebox underneath, so
## disabling USE_BLUR falls back to plain translucent glass.

const USE_BLUR := true
const GLASS_BG := Color(0.04, 0.07, 0.13, 0.72)
const GLASS_BG_SOFT := Color(0.04, 0.07, 0.13, 0.3)
const BORDER := Color(1, 1, 1, 0.28)
const BORDER_DIM := Color(1, 1, 1, 0.14)
const GOLD := Color(0.85, 0.64, 0.25, 0.95)
const GOLD_DIM := Color(0.85, 0.64, 0.25, 0.55)
const GOLD_TXT := Color(0.96, 0.8, 0.45)
const TXT := Color(0.94, 0.96, 0.99)
const TXT_DIM := Color(0.64, 0.7, 0.8)
const GREEN := Color(0.45, 0.95, 0.5)
const RESOURCE_TYPES: Array = ["food", "wood", "gold", "stone", "iron"]

# 13u: Font Awesome 6 Solid (the genuine fa-solid-900.ttf from
# Tín's AvatarDK project, imported as a real font so HUD glyphs
# render + tint exactly like CSS icons — no painted glyphs).
const FA_FONT_PATH := "res://assets/fonts/fa-solid-900.ttf"
const FA_COMMENTS := 0xF086
const FA_USERS := 0xF0C0
const FA_HANDSHAKE := 0xF2B5
const FA_GEAR := 0xF013
const FA_FLAG := 0xF024
const FA_CROSSHAIRS := 0xF05B
const FA_LAYERS := 0xF5FD
const FA_XMARK := 0xF00D
const FA_SEND := 0xF1D8
const FA_MUSIC := 0xF001
const FA_VOLUME := 0xF028
const FA_SUN := 0xF185
const FA_EYE := 0xF06E
const FA_CHART := 0xE473
const FA_CROWN := 0xF521
const FA_FOOD := 0xF6D7 # drumstick-bite
const FA_WOOD := 0xF1BB # tree
const FA_GOLD := 0xF51E # coins
const FA_STONE := 0xF6FC # mountain
const FA_STAR := 0xF005
const FA_SKULL := 0xF54C
const FA_HAMMER := 0xF6E3
const FA_BOLT := 0xF0E7
const SETTINGS_PATH := "user://hud_settings.cfg"

const BLUR_SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 8.0) = 2.0;
uniform vec4 tint : source_color = vec4(0.05, 0.09, 0.17, 1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;
void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * blur_amount;
	vec4 c = vec4(0.0);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			c += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(float(x), float(y)) * ps);
		}
	}
	c /= 25.0;
	COLOR = vec4(mix(c.rgb, tint.rgb, tint_mix), 1.0);
}
"""

var game = null: # Main (duck-typed)
	set(v):
		game = v
		if minimap != null:
			minimap.game = v

var minimap: Minimap = null
var res_chips: Dictionary = {} # rtype -> {amt: Label, rate: Label}
var open_tab: String = ""

var _blur_mat: ShaderMaterial = null
var _pop_label: Label
var _timer_label: Label
var _msg_label: Label
var _msg_timer := 0.0
var _sel_label: Label
var _subpanel: PanelContainer
var _pages: Dictionary = {}
var _action_panels: Dictionary = {}
var _flag_panel: PanelContainer
var _flag_active := false
var _train_btn: Button
var _militia_btn: Button
var _archer_btn: Button
var _spearman_btn: Button
var _cavalry_btn: Button
var _ram_btn: Button
var _king_btn: Button
var _skill_row: HBoxContainer
var _skill_btns: Array = [] # Array[Button] x1 (16b: ONE skill per hero)
var _skill_icons: Array = [] # Array[TextureRect]
var _skill_sweeps: Array = [] # Array[TextureProgressBar]
var _skill_secs: Array = [] # Array[Label] cooldown seconds
var _skill_for_char := ""
# 15c: skill name labels under the buttons + press-and-hold info.
var _skill_name_labels: Array = [] # Array[Label] x3, under each button
var _skill_hits: Array = [] # Array[Control] input catchers on the buttons
var _skill_press_idx := -1 # button currently pressed (-1 = none)
var _skill_press_msec := 0 # when the current press began
var _skill_hold_fired := false # this press already opened the info card
var _skill_info_card: PanelContainer = null
var _skill_info_icon: TextureRect = null
var _skill_info_title: Label = null
var _skill_info_cd: Label = null
var _skill_info_desc: Label = null
const SKILL_HOLD_MSEC := 400 # press-and-hold threshold for the info card
# 13s action panels: build grid / producer-bound training / AoE tech.
var _build_cards: Dictionary = {} # btype -> {root, click, reason, art, cost_box, cost_done}
var _train_cards: Dictionary = {} # producer btype -> {kind -> card dict}
var _train_boxes: Dictionary = {} # producer btype -> roster GridContainer
var _producer: Building = null # building the training page is bound to
var _train_name: Label
var _train_art: TextureRect
var _queue_strip: HBoxContainer
var _queue_bar: ProgressBar
var _queue_info: Label
var _queue_sig := ""
var _tech_cards: Dictionary = {} # tech id -> {root, click, bar, name, fx, reason, lvl, cost_box, cost_sig}
var _surrender_btn: Button
var _surrender_arm := 0.0 # two-step confirm window for Đầu hàng
var _thumb_cache: Dictionary = {} # unit/ship kind -> Texture2D (or null)
# 13u: FA font + top-left identity + restructured pages + new panels.
var _fa_font: Font = null
var _player_name_label: Label
var _player_avatar: TextureRect
var _avatar_shown_id := ""
var _bright_rect: ColorRect # settings brightness overlay (scene-level)
var _music_vol := 0.8
var _sfx_vol := 1.0
var _brightness := 1.0 # render multiplier 0.5..1.5 (see _apply_brightness)
var _bright_pct := 50.0 # brightness SLIDER value 0..100; 50 = _brightness 1.0x
var _show_names := true
var _set_music_slider: HSlider
var _set_sfx_slider: HSlider
var _set_bright_slider: HSlider
var _set_music_val: Label
var _set_sfx_val: Label
var _set_bright_val: Label
var _set_names_btn: Button
var _set_surrender_btn: Button
var _build_tab := "eco"
var _build_tab_btns: Dictionary = {} # tab id -> Button
var _build_scroll: ScrollContainer
var _train_tab_btns: Dictionary = {} # producer btype -> Button
var _tech_nodes: Dictionary = {} # tech id -> Array of node dicts
var _tech_sel_tid := ""
var _tech_sel_tier := -1
var _tech_detail: Dictionary = {} # detail-strip UI refs
var _players_box: VBoxContainer
var _dip_box: VBoxContainer # 15b diplomacy modal list
var _dip_rows: Dictionary = {} # slot -> row widget refs (built once per match)
var _dip_built_key := ""
var _dip_refresh_msec := 0
var _dip_top_btn: Control = null # top-bar handshake button (diplomacy matches only)
var _players_refresh_msec := 0
var _stats_box: VBoxContainer
var _stats_refresh_msec := 0
var _house_btn: Button
var _barracks_btn: Button
var _mining_btn: Button
var _tower_btn: Button
var _blacksmith_btn: Button
var _lumber_btn: Button
var _storage_btn: Button
var _market_btn: Button
var _dock_btn: Button
var _farm_btn: Button
var _castle_btn: Button
var _wallwood_btn: Button
var _wallstone_btn: Button
var _gatewood_btn: Button
var _gatestone_btn: Button
var _field_btn: Button
var _market_box: VBoxContainer
var _mkt_sell_btns: Dictionary = {} # rtype -> Button
var _mkt_buy_btns: Dictionary = {} # rtype -> Button
var _ship_box: VBoxContainer
var _wagon_box: VBoxContainer # 15g: unload button row for a selected wagon
var _wagon_btn: Button = null
var _ship_btns: Dictionary = {} # ship kind -> Button
var _sel_chip: PanelContainer
var _pause_btn: Button
var _age_badge: TextureRect
var _age_shown: int = 0
var _age_name_label: Label
var _age_name_shown: int = 0
var _age_btn: Button
var _age_bar: ProgressBar
var _age_status: Label
var _age3_btn: Button
var _age3_bar: ProgressBar
var _age3_status: Label
var _age4_btn: Button
var _age4_bar: ProgressBar
var _age4_status: Label
var _end_note: Label
var _end_banner: Label # ranked promotion/demotion banner (stage 4)
var _end_rank: Label # ranked star/MMR movement line (stage 4)
var _rank_result: Dictionary = {}
var _tc_warn_label: Label
var _end_panel: PanelContainer
var _end_title: Label
var _end_time: Label
# 13y result screen pieces (built in _build_end_panel).
var _end_dim: ColorRect
var _end_context: Label # duration · mode · map line
var _end_standings: VBoxContainer
var _end_chart: ScoreChart
var _end_breakdown: VBoxContainer
var _end_replay_btn: Button
# 13y-AOV: MVP spotlight slot above the standings table.
var _end_mvp: VBoxContainer
var _result_replay_pending: bool = false
# P4 stage 2: in-match chat + resync overlay.
# 13w: chat rebuilt as a centred, draggable modal (see _build_chat_panel).
var _chat_panel: PanelContainer
var _chat_dim: ColorRect
var _chat_log: RichTextLabel # transcript store (bbcode); the panel itself renders message rows
var _chat_scroll: ScrollContainer
var _chat_rows: VBoxContainer
var _chat_input: LineEdit
var _chat_scope: String = "match" # relay scope: "match" (all) | "team"
var _chat_all_btn: Button
var _chat_team_btn: Button
var _chat_seg: PanelContainer # segmented channel control (Tất cả / Đội)
var _chat_send_btn: Button
var _chat_chan_label: Label # input-row chip naming the active channel
var _chat_block_seq := 0 # alternating row shading counter
var _chat_last_key := "" # sender|scope|slot of the last block (batching)
var _chat_last_body: VBoxContainer = null # body of the last block
var _chat_dragging := false
var _chat_drag_off := Vector2.ZERO
const CHAT_SIZE := Vector2(560, 452)
const CHAT_MAX_BLOCKS := 60
# 13x: Players / Statistics / Settings rebuilt as CENTRED modals
# in the chat (13w) family — same navy glass card, 2px gold frame,
# dim backdrop — but NOT draggable: only the chat panel drags.
var _modals: Dictionary = {} # tab -> {"dim", "panel", "size"}
const MODAL_TABS: Array = ["players", "stats", "settings", "diplomacy"]
const PLAYERS_SIZE := Vector2(540, 452)
const DIP_SIZE := Vector2(560, 480)
const STATS_SIZE := Vector2(620, 520)
const SETTINGS_SIZE := Vector2(500, 344)
var _sync_overlay: PanelContainer
var _sync_label: Label
var _icon_tex: Dictionary = {} # painted icon name -> Texture2D (or null)
var _map_root: Control = null # boot map-choice overlay (biomes pass)
var _map_cards: Dictionary = {} # biome id -> card PanelContainer
var _map_sel: String = "grassland"
var _layout_chips: Dictionary = {} # layout id -> chip Button
var _layout_sel: String = "plains"
# 15e-ter: refs for the observer-clean gate — the slot-tied
# HUD pieces the spectator screen hides (see _apply_observer_clean).
var _top_bar: PanelContainer
var _identity_chip: PanelContainer
var _res_chip_panels: Array = [] # resource chip panels (RESOURCE_TYPES order)
var _pop_chip: PanelContainer
var _timer_box: HBoxContainer
var _minimap_btns: VBoxContainer
var _action_bar: HBoxContainer
var _set_surrender_div: HSeparator



# ------------------------------------------------------------------ chat (MP)

## In-match chat panel (13w rebuild, researched patterns noted in
## KE-HOACH 13w): a CENTRED modal over a dim backdrop — navy glass
## card, gold 2px frame, blur — that the player can DRAG by its
## header to any position while open (position resets to centre on
## every open). Message list = real rows with alternating shading;
## consecutive messages from one sender batch under a single name
## header (dot + name in the sender's slot colour). Channels are a
## segmented control (Tất cả / Đội) and the input row carries a
## chip naming the active channel + a gold paper-plane send button.
## Chat is pure relay (Net.send_chat) — it never touches the sim.
func _build_chat_panel() -> void:
	# Dim backdrop: fixed full-rect; a tap on it closes the panel.
	_chat_dim = ColorRect.new()
	_chat_dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_chat_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chat_dim.visible = false
	_chat_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_set_chat_open(false))
	add_child(_chat_dim)
	_chat_panel = _panel(16, GOLD, Color(0.03, 0.05, 0.1, 0.94), 2)
	_chat_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_chat_panel.custom_minimum_size = CHAT_SIZE
	_chat_panel.size = CHAT_SIZE
	_add_blur(_chat_panel)
	_chat_panel.visible = false
	add_child(_chat_panel)
	var mc := _pad(14, 12, 14, 12)
	_chat_panel.add_child(mc)
	var vb := _vbox(10)
	mc.add_child(vb)
	# --- header (the drag handle) ---
	var header := _panel(10, BORDER_DIM, Color(1, 1, 1, 0.04))
	header.name = "ChatHeader"
	header.custom_minimum_size = Vector2(0, 46)
	header.gui_input.connect(_on_chat_header_input)
	vb.add_child(header)
	var hmc := _pad(10, 5, 8, 5)
	header.add_child(hmc)
	var head := _hbox(8)
	hmc.add_child(head)
	head.add_child(_fa(FA_COMMENTS, 18, GOLD_TXT))
	head.add_child(_label("Trò chuyện", 16, GOLD_TXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	# Segmented channel control.
	var seg := _panel(9, BORDER_DIM, Color(0.01, 0.02, 0.05, 0.9))
	seg.name = "ChatSeg"
	_chat_seg = seg
	var smc := _pad(2, 2, 2, 2)
	seg.add_child(smc)
	var srow := _hbox(2)
	smc.add_child(srow)
	_chat_all_btn = _chat_seg_button("Tất cả")
	_chat_all_btn.pressed.connect(func() -> void: _set_chat_scope("match"))
	srow.add_child(_chat_all_btn)
	_chat_team_btn = _chat_seg_button("Đội")
	_chat_team_btn.pressed.connect(func() -> void: _set_chat_scope("team"))
	srow.add_child(_chat_team_btn)
	head.add_child(seg)
	var close_btn := _fa_button(FA_XMARK, 8, 32)
	close_btn.btn.pressed.connect(func() -> void: _set_chat_open(false))
	head.add_child(close_btn.panel)
	# --- message rows ---
	_chat_log = RichTextLabel.new() # transcript store only (see add_chat_line)
	_chat_log.bbcode_enabled = true
	_chat_log.visible = false # in-tree but never shown: rows render the chat
	add_child(_chat_log)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chat_scroll.follow_focus = false
	_chat_scroll.add_theme_stylebox_override("panel",
			_sb(BORDER_DIM, Color(0.015, 0.03, 0.07, 0.85), 10))
	vb.add_child(_chat_scroll)
	var rmc := MarginContainer.new()
	rmc.add_theme_constant_override("margin_left", 6)
	rmc.add_theme_constant_override("margin_top", 6)
	rmc.add_theme_constant_override("margin_right", 6)
	rmc.add_theme_constant_override("margin_bottom", 6)
	rmc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rmc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_scroll.add_child(rmc)
	_chat_rows = _vbox(4)
	_chat_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rmc.add_child(_chat_rows)
	# --- input row: channel chip + field + gold send ---
	var irow := _hbox(8)
	vb.add_child(irow)
	var chip := _panel(8, GOLD_DIM, Color(0.85, 0.64, 0.25, 0.14))
	chip.custom_minimum_size = Vector2(64, 38)
	var ccc := CenterContainer.new()
	ccc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_chan_label = _label("Tất cả", 12, GOLD_TXT)
	ccc.add_child(_chat_chan_label)
	chip.add_child(ccc)
	irow.add_child(chip)
	_chat_input = LineEdit.new()
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.custom_minimum_size = Vector2(0, 38)
	_chat_input.max_length = 200
	_chat_input.placeholder_text = "Nhập tin nhắn… (Enter để gửi)"
	_chat_input.add_theme_font_size_override("font_size", 14)
	_chat_input.add_theme_color_override("font_color", TXT)
	_chat_input.add_theme_color_override("font_placeholder_color", TXT_DIM)
	_chat_input.add_theme_stylebox_override("normal",
			_sb(BORDER, Color(0.02, 0.04, 0.09, 0.9), 10))
	_chat_input.add_theme_stylebox_override("focus",
			_sb(GOLD, Color(0.02, 0.04, 0.09, 0.9), 10))
	_chat_input.text_submitted.connect(func(_t: String) -> void: _send_chat_input())
	irow.add_child(_chat_input)
	var send_btn := _fa_button(FA_SEND, 10, 38, Color(0.1, 0.08, 0.02))
	send_btn.panel.add_theme_stylebox_override("panel",
			_sb(GOLD, Color(0.85, 0.64, 0.25, 0.92), 10))
	send_btn.btn.pressed.connect(_send_chat_input)
	_chat_send_btn = send_btn.btn
	irow.add_child(send_btn.panel)
	# The Đội channel exists only when the local player actually
	# has a team-mate in this match (13w fix — see
	# _team_chat_available): 1v1 queues and FFA hide the whole
	# segmented control, chat is Tất cả only.
	_refresh_chat_channels()
	_set_chat_scope("match")
	# 13u: in SP there is nobody to talk to — the panel says so
	# honestly instead of pretending to send.
	if game == null or not game.mp_mode:
		_chat_log.text = "[color=#93a5c4]Trò chuyện chỉ dùng trong trận online. Vào một trận nhiều người chơi để nhắn tin với đối thủ và đồng đội.[/color]\n"
		_add_chat_notice("Trò chuyện chỉ dùng trong trận online. Vào một trận nhiều người chơi để nhắn tin với đối thủ và đồng đội.")
		_chat_input.editable = false
		_chat_input.placeholder_text = "Chỉ dùng trong trận online"
		_chat_send_btn.disabled = true
		seg.visible = false


## One segment of the channel control (13w): flat button restyled
## by _set_chat_scope — gold fill when active, dim text when not.
func _chat_seg_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(74, 30)
	b.add_theme_font_size_override("font_size", 13)
	return b


## Centred open / close for the chat modal (13w). Opening always
## re-centres the panel (a dragged position never persists across
## opens — stated in KE-HOACH 13w) and focuses the input.
func _set_chat_open(on: bool) -> void:
	if _chat_panel == null:
		return
	_chat_panel.visible = on
	if _chat_dim != null:
		_chat_dim.visible = on
	_chat_dragging = false
	if on:
		_refresh_chat_channels()
		_chat_panel.size = CHAT_SIZE
		var vp := _chat_panel.get_viewport_rect().size
		_chat_panel.position = (vp - CHAT_SIZE) * 0.5
		_chat_scroll_bottom()
		if _chat_input != null and _chat_input.editable:
			_chat_input.grab_focus()


## Drag the panel by its header (13w): free movement, clamped so
## at least a grabbable strip of the header always stays on screen.
func _on_chat_header_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_chat_dragging = true
				_chat_drag_off = _chat_panel.global_position - mb.global_position
			else:
				_chat_dragging = false
	elif ev is InputEventMouseMotion and _chat_dragging:
		var mm := ev as InputEventMouseMotion
		var vp := _chat_panel.get_viewport_rect().size
		var target := mm.global_position + _chat_drag_off
		target.x = clampf(target.x, -(CHAT_SIZE.x - 140.0), vp.x - 140.0)
		target.y = clampf(target.y, 0.0, vp.y - 56.0)
		_chat_panel.position = target


## Dim centred notice row (SP honest state, 13w).
func _add_chat_notice(text: String) -> void:
	var l := _label(text, 13, TXT_DIM)
	l.name = "ChatNotice"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_rows.add_child(l)


func _chat_scroll_bottom() -> void:
	if _chat_scroll == null:
		return
	await get_tree().process_frame
	if _chat_scroll == null or not is_inside_tree():
		return
	var bar := _chat_scroll.get_v_scroll_bar()
	if bar != null:
		_chat_scroll.scroll_vertical = int(bar.max_value)


## "Đang đồng bộ lại…" overlay while this client rebuilds from a
## resync snapshot (input is locked on Main's side too).
func _build_sync_overlay() -> void:
	_sync_overlay = _panel(0, BORDER, Color(0.01, 0.02, 0.05, 0.55))
	_sync_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sync_overlay.visible = false
	_sync_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sync_overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sync_overlay.add_child(cc)
	_sync_label = _label("Đang đồng bộ lại…", 26, GOLD_TXT)
	cc.add_child(_sync_label)


func show_sync_overlay(on: bool) -> void:
	if _sync_overlay != null:
		_sync_overlay.visible = on


## Team chat availability (13w fix, Tín: "Sao lại có chat đội ở
## đây"): the Đội channel exists ⟺ the LOCAL player's team has
## at least 2 participants in this match — a real 2v2. A 1v1
## (Đấu Thường / Đấu Hạng queues) gives each player a team of
## one, and so does FFA: there is nobody on "Đội" to talk to.
## (Main.mp_has_allies answers a different, global question —
## whether ANY team repeats — so a lone player on a paired-up
## match's odd team would wrongly get the channel from it.)
func _team_chat_available() -> bool:
	if game == null or not game.mp_mode:
		return false
	# 15b: in a diplomacy match the Đội channel follows CURRENT
	# alliances (the 13w rule restated for stances): the tab
	# exists only while the local player holds at least one
	# ALLY stance, and its membership is that ally set.
	if game.diplomacy_active():
		return not game.dip_allies_of(game.local_slot).is_empty()
	var mine: int = game.team_of_slot(game.local_slot)
	var n := 0
	for s in range(game.slot_count()):
		if game.team_of_slot(s) == mine:
			n += 1
	return n >= 2


## Applies the availability: no team-mate → the whole segmented
## control hides (like the SP state) and a team scope falls back
## to Tất cả. Re-run on every open in case slot state settled
## after the panel was built.
func _refresh_chat_channels() -> void:
	var avail := _team_chat_available()
	if _chat_seg != null:
		_chat_seg.visible = avail
	if _chat_team_btn != null:
		_chat_team_btn.visible = avail
	if not avail and _chat_scope == "team":
		_set_chat_scope("match")


func _set_chat_scope(scope: String) -> void:
	_chat_scope = scope
	_style_chat_seg(_chat_all_btn, scope == "match")
	_style_chat_seg(_chat_team_btn, scope == "team")
	if _chat_chan_label != null:
		_chat_chan_label.text = "Tất cả" if scope == "match" else "Đội"


## Segmented-control styling (13w): the active channel wears a
## gold fill with dark text; the inactive one stays flat and dim.
func _style_chat_seg(b: Button, active: bool) -> void:
	if b == null:
		return
	var e := StyleBoxEmpty.new()
	if active:
		b.add_theme_stylebox_override("normal", _sb(GOLD, Color(0.85, 0.64, 0.25, 0.92), 7))
		b.add_theme_stylebox_override("hover", _sb(GOLD, Color(0.9, 0.7, 0.32, 0.95), 7))
		b.add_theme_stylebox_override("pressed", _sb(GOLD, Color(0.78, 0.58, 0.22, 0.95), 7))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	else:
		b.add_theme_stylebox_override("normal", e)
		b.add_theme_stylebox_override("hover", _sb(BORDER_DIM, Color(1, 1, 1, 0.08), 7))
		b.add_theme_stylebox_override("pressed", _sb(BORDER_DIM, Color(1, 1, 1, 0.12), 7))
		b.add_theme_color_override("font_color", TXT_DIM)
		b.add_theme_color_override("font_hover_color", TXT)


func _send_chat_input() -> void:
	var text := _chat_input.text.strip_edges()
	if text == "":
		return
	_chat_input.clear()
	if _chat_scope == "team" and game != null and game.diplomacy_active():
		Net.send_chat(_chat_scope, text, game.dip_allies_of(game.local_slot))
	else:
		Net.send_chat(_chat_scope, text)
	_chat_input.grab_focus()


func toggle_chat() -> void:
	if _chat_panel == null:
		return
	_set_chat_open(not _chat_panel.visible)


func open_chat() -> void:
	_set_chat_open(true)


func is_chat_open() -> bool:
	return _chat_panel != null and _chat_panel.visible


## Escape user text for the bbcode log (a "[" would otherwise
## be parsed as markup).
func _bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


## One chat line (13w): appended to the bbcode transcript AND
## rendered as a row. The sender's name wears their slot colour
## (TeamColors); team scope gets a dim "(Đội)" tag. Consecutive
## lines from the same sender+scope batch into the open block
## (no repeated name header); blocks alternate a subtle shading.
func add_chat_line(sender_name: String, text: String, scope: String, slot: int = -1, bubble_style: String = "mac_dinh") -> void:
	if _chat_log == null:
		return
	var col := TeamColors.ui_color(slot) if slot >= 0 else TXT
	var head := "[color=%s]%s[/color]" % [col.to_html(), _bb_escape(sender_name)]
	if scope == "team":
		head = "[color=#8fa3c8](Đội) [/color]" + head
	_chat_log.text += head + ": " + _bb_escape(text) + "\n"
	if _chat_rows == null:
		return
	# 17d: lines also wear the sender's equipped bubble style
	# (§7.2B) — the batching key includes it.
	var key := "%s|%s|%d|%s" % [sender_name, scope, slot, bubble_style]
	if key != _chat_last_key or _chat_last_body == null:
		_chat_last_key = key
		_chat_last_body = _new_chat_block(sender_name, scope, col, bubble_style)
	var l := _label(text, 14, TXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_last_body.add_child(l)
	# Circular trim: keep at most CHAT_MAX_BLOCKS blocks.
	while _chat_rows.get_child_count() > CHAT_MAX_BLOCKS:
		var old := _chat_rows.get_child(0)
		_chat_rows.remove_child(old)
		old.queue_free()
	_chat_scroll_bottom()


## A sender block (13w): shaded row — header (slot-colour dot +
## name, "(Đội)" tag for team scope) over a body of message lines.
func _new_chat_block(sender_name: String, scope: String, col: Color, bubble_style: String = "mac_dinh") -> VBoxContainer:
	_chat_block_seq += 1
	var bg := Color(1, 1, 1, 0.05) if _chat_block_seq % 2 == 0 else Color(1, 1, 1, 0.0)
	var border := Color(1, 1, 1, 0)
	var bw := 0
	# 17d: a non-default equipped style re-skins the block
	# (bg + border from the shared ChatBubbles style table).
	if bubble_style != "" and bubble_style != "mac_dinh" and ChatBubbles.STYLES.has(bubble_style):
		var st: Dictionary = ChatBubbles.STYLES[bubble_style]
		bg = st["bg"]
		border = st["border"]
		bw = int(st.get("border_w", 1))
	var block := _panel(8, border, bg, bw)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_rows.add_child(block)
	var bmc := _pad(8, 5, 8, 5)
	bmc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(bmc)
	var bv := _vbox(1)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bmc.add_child(bv)
	var hrow := _hbox(6)
	bv.add_child(hrow)
	var dot := _panel(5, col, col)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(dot)
	var nm := _label(sender_name, 14, col)
	hrow.add_child(nm)
	if scope == "team":
		hrow.add_child(_label("(Đội)", 11, Color(0.56, 0.64, 0.78)))
	var body := _vbox(1)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.add_child(body)
	return body

# ------------------------------------------------------------------ helpers

func _sb(border_col: Color, bg: Color, radius: int, bw: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(1)
	return sb


func _panel(radius: int, border_col: Color, bg: Color, bw: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(border_col, bg, radius, bw))
	return p


func _blur_material() -> ShaderMaterial:
	if _blur_mat == null:
		var sh := Shader.new()
		sh.code = BLUR_SHADER_CODE
		_blur_mat = ShaderMaterial.new()
		_blur_mat.shader = sh
	return _blur_mat


func _add_blur(p: PanelContainer) -> void:
	if not USE_BLUR:
		return
	var cr := ColorRect.new()
	cr.material = _blur_material()
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(cr)


func _pad(l: int, t: int, r: int, b: int) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", l)
	mc.add_theme_constant_override("margin_top", t)
	mc.add_theme_constant_override("margin_right", r)
	mc.add_theme_constant_override("margin_bottom", b)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return mc


func _label(text: String, size: int, col: Color = TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _icon(kind: String, px: int) -> GlassIcon:
	var ic := GlassIcon.new()
	ic.kind = kind
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return ic


## 13u: a Font Awesome glyph as a tintable Label (CSS-icon style).
func _fa(cp: int, px: int, col: Color = TXT) -> Label:
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


## Round/square glass button whose glyph is a Font Awesome icon
## (same {panel, btn} shape as _icon_button).
func _fa_button(cp: int, radius: int, sz: int, col: Color = TXT) -> Dictionary:
	var p := _panel(radius, BORDER, GLASS_BG)
	p.custom_minimum_size = Vector2(sz, sz)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(_fa(cp, int(sz * 0.52), col))
	p.add_child(cc)
	var btn := _click_area(p)
	return {"panel": p, "btn": btn}


## Horizontal-scroll container for the restructured panels: the
## mouse wheel drives it sideways; touch drag scrolls natively.
func _hscroll(height: float) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, height)
	sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = false
	sc.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				sc.scroll_horizontal += 72
				sc.accept_event()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				sc.scroll_horizontal -= 72
				sc.accept_event())
	return sc


## Selectable tab chip (shared by the build/train tab rows).
func _tab_chip(text: String) -> Button:
	var b := _text_button(text)
	b.custom_minimum_size = Vector2(0, 32)
	return b


func _style_tab_chip(b: Button, active: bool) -> void:
	if active:
		b.add_theme_stylebox_override("normal", _sb(GOLD, Color(0.85, 0.64, 0.25, 0.18), 8))
		b.add_theme_color_override("font_color", GOLD_TXT)
	else:
		b.add_theme_stylebox_override("normal", _sb(BORDER_DIM, Color(1, 1, 1, 0.04), 8))
		b.add_theme_color_override("font_color", TXT)


## Painted icon texture (Tín's set, assets/icons/<name>.png); null if absent.
func _icon_texture(icon_name: String) -> Texture2D:
	if _icon_tex.has(icon_name):
		return _icon_tex[icon_name]
	var tex: Texture2D = null
	var path := "res://assets/icons/%s.png" % icon_name
	if ResourceLoader.exists(path):
		tex = load(path)
	_icon_tex[icon_name] = tex
	return tex


## Icon control: painted texture when available (LINEAR-filtered so the
## painted art downscales smoothly), code-drawn GlassIcon as fallback.
func _pic(icon_name: String, px: int) -> Control:
	var tex := _icon_texture(icon_name)
	if tex == null:
		return _icon(icon_name, px)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.custom_minimum_size = Vector2(px, px)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## The header age badge shows the painted shield for the current age.
func refresh_age_badge() -> void:
	if _age_badge == null:
		return
	var a := 1
	if game != null:
		a = clampi(int(game.age), 1, 4)
	if a == _age_shown and _age_badge.texture != null:
		return
	_age_shown = a
	var tex := _icon_texture("age_%d" % a)
	if tex == null:
		tex = _icon_texture("age_1")
	_age_badge.texture = tex


func age_badge_texture() -> Texture2D:
	return _age_badge.texture if _age_badge != null else null


func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _click_area(parent: Control) -> Button:
	var b := Button.new()
	b.text = ""
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var e := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(s, e)
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(b)
	return b


func _text_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TXT_DIM)
	b.add_theme_stylebox_override("normal", _sb(BORDER, Color(1, 1, 1, 0.07), 8))
	b.add_theme_stylebox_override("hover", _sb(BORDER, Color(1, 1, 1, 0.15), 8))
	b.add_theme_stylebox_override("pressed", _sb(GOLD, Color(0.85, 0.64, 0.25, 0.25), 8))
	b.add_theme_stylebox_override("disabled", _sb(BORDER_DIM, Color(1, 1, 1, 0.03), 8))
	return b


func _icon_button(kind: String, radius: int, sz: int) -> Dictionary:
	var p := _panel(radius, BORDER, GLASS_BG)
	p.custom_minimum_size = Vector2(sz, sz)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(_pic(kind, int(sz * 0.55)))
	p.add_child(cc)
	var btn := _click_area(p)
	return {"panel": p, "btn": btn}


# ------------------------------------------------------------------ settings (13u)

## Settings live in user://hud_settings.cfg and are applied by
## the HUD itself: AudioServer bus volumes (Music / SFX buses are
## created at runtime when the project defines none), a
## brightness overlay rect, and the HeroOverlay name gate.
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_music_vol = clampf(float(cfg.get_value("audio", "music", 0.8)), 0.0, 1.0)
		_sfx_vol = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
		_bright_pct = _load_bright_pct(cfg)
		_brightness = 0.5 + _bright_pct / 100.0
		_show_names = bool(cfg.get_value("display", "show_names", true))


## Brightness persistence: the slider is a 0..100 scale and the
## render multiplier is 0.5 + pct/100 (slider 50 = normal 1.0x).
## Files saved by the old build stored the raw multiplier
## (0.5..1.5, i.e. a "50..150 percent" scale) — migrate by
## subtracting 50 from the percent. New saves carry the "pct"
## scale marker so the two scales never get confused.
func _load_bright_pct(cfg: ConfigFile) -> float:
	if String(cfg.get_value("display", "brightness_scale", "")) == "pct":
		return clampf(float(cfg.get_value("display", "brightness", 50.0)), 0.0, 100.0)
	var raw := float(cfg.get_value("display", "brightness", 1.0))
	return clampf(raw * 100.0 - 50.0, 0.0, 100.0)
	_apply_audio()
	_apply_names()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", _music_vol)
	cfg.set_value("audio", "sfx", _sfx_vol)
	cfg.set_value("display", "brightness", _bright_pct)
	cfg.set_value("display", "brightness_scale", "pct")
	cfg.set_value("display", "show_names", _show_names)
	cfg.save(SETTINGS_PATH)


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _apply_audio() -> void:
	for pair in [["Music", _music_vol], ["SFX", _sfx_vol]]:
		var idx := _ensure_bus(String(pair[0]))
		var v := float(pair[1])
		AudioServer.set_bus_mute(idx, v <= 0.001)
		if v > 0.001:
			AudioServer.set_bus_volume_db(idx, linear_to_db(v))


func _apply_names() -> void:
	HeroOverlay.show_names = _show_names


## The brightness layer is the HUD's FIRST child: it tints the
## rendered world (everything the game draws sits in lower
## canvas layers) while every HUD control draws above it.
func _build_brightness_overlay() -> void:
	_bright_rect = ColorRect.new()
	_bright_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bright_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bright_rect)
	_apply_brightness()


func _apply_brightness() -> void:
	if _bright_rect == null:
		return
	var bmat := _bright_rect.material as CanvasItemMaterial
	if bmat == null:
		bmat = CanvasItemMaterial.new()
		_bright_rect.material = bmat
	if _brightness < 1.0:
		bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		_bright_rect.color = Color(0, 0, 0, (1.0 - _brightness) * 0.8)
	else:
		bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_bright_rect.color = Color(1, 1, 1, (_brightness - 1.0) * 0.55)


# ------------------------------------------------------------------ build

func _ready() -> void:
	_load_settings()
	_build_brightness_overlay()
	_build_top_bar()
	_build_message_label()
	_build_minimap()
	_build_action_bar()
	_build_subpanel()
	_build_selection_chip()
	_build_end_panel()
	_build_map_panel()
	_build_info_modals()
	_build_chat_panel()
	_build_sync_overlay()
	_build_skill_button()
	_apply_observer_clean()


## 15e-ter: THE observer predicate — every spectator-clean
## gate in this HUD keys on this one function (Main sets
## observer_mode before the HUD is built, and it never
## changes mid-match).
func _is_observer() -> bool:
	return game != null and game.observer_mode


## 15e-ter (owner clarification: "người xem không hiện panel
## lúc chơi"): an observer's screen is the WORLD plus the
## watcher-personal surfaces only — minimap, spectator bar /
## panel, chat, settings. Every slot-tied gameplay piece is
## hidden here at build time (and kept hidden by the per-frame
## gates in _refresh_skill_button / _refresh_panels /
## _open_tab / _process): the top identity chip, age badge,
## resource / population / timer chips, the diplomacy button,
## the minimap action buttons, the bottom action tabs and
## their subpanel, the selection chip, and the hero skill
## cluster. Hidden controls also take no input, so the UI no
## longer pretends the watcher can play. Player mode never
## enters this function (the predicate is false), so the
## player HUD is untouched byte for byte.
func _apply_observer_clean() -> void:
	if not _is_observer():
		return
	# Top bar: every slot-tied cluster goes; the glass strip
	# shrinks to hug the round buttons that stay.
	if _identity_chip != null:
		_identity_chip.visible = false
	if _age_badge != null:
		_age_badge.visible = false
	if _age_name_label != null:
		_age_name_label.visible = false
	for p in _res_chip_panels:
		(p as Control).visible = false
	if _pop_chip != null:
		_pop_chip.visible = false
	if _timer_box != null:
		_timer_box.visible = false
	if _dip_top_btn != null:
		_dip_top_btn.visible = false
	if _top_bar != null:
		_top_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_top_bar.offset_left = -168
		_top_bar.offset_right = -6
		_top_bar.offset_top = 6
		_top_bar.offset_bottom = 62
	# Minimap action buttons (rally point / centre on own TC /
	# select all villagers) are commands over a seat the
	# watcher does not hold.
	if _minimap_btns != null:
		_minimap_btns.visible = false
	# Bottom gameplay cluster: action tabs + the subpanel
	# they open, the selection readout, the skill cluster.
	if _action_bar != null:
		_action_bar.visible = false
	if _subpanel != null:
		_subpanel.visible = false
	if _sel_chip != null:
		_sel_chip.visible = false
	if _skill_row != null:
		_skill_row.visible = false
	_hide_skill_info()
	# The watcher's own settings panel stays — minus the
	# Surrender action, which belongs to a seat.
	if _set_surrender_btn != null:
		_set_surrender_btn.visible = false
	if _set_surrender_div != null:
		_set_surrender_div.visible = false


## The hero skill buttons (13j → 13v): THREE floating buttons at
## the bottom-right, visible whenever the local player's hero is
## alive — usable whether or not the hero is selected. Each wears
## its approved pixel icon (assets/skill_icons/<char>_<n>.png), a
## radial cooldown sweep (a dark veil that recedes clockwise) and
## a seconds counter; the Ulti button is larger with a gold frame.
## Targeted skills arm Main's ground-targeting flow on tap.
func _build_skill_button() -> void:
	_skill_row = _hbox(8)
	_skill_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# 15c: the row is RAISED (owner order: the cluster sat flush on
	# the action panel) and grew a name label under every button.
	# Geometry (offsets from the bottom-right corner): the action
	# bar's top edge is at -78; this row's bottom is -92, leaving
	# 14 px of daylight under the label. Row height 93 = the one
	# skill button (76) + 2 spacing + a ~15 px name label; the
	# single column is 112 wide so the full skill name fits.
	_skill_row.offset_left = -128
	_skill_row.offset_top = -185
	_skill_row.offset_right = -16
	_skill_row.offset_bottom = -92
	_skill_row.visible = false
	add_child(_skill_row)
	var wimg := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	wimg.fill(Color.WHITE)
	var sweep_tex := ImageTexture.create_from_image(wimg)
	for i in range(1):
		var idx := i + 1
		var big := true # 16b: the one skill gets the gold frame
		var btn := _text_button("")
		btn.custom_minimum_size = Vector2(76, 76) if big else Vector2(58, 58)
		btn.size_flags_vertical = Control.SIZE_SHRINK_END
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.045, 0.09, 0.88)
		sb.set_corner_radius_all(10 if big else 8)
		sb.set_border_width_all(3 if big else 1)
		sb.border_color = GOLD if big else Color(0.45, 0.5, 0.62, 0.9)
		btn.add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate() as StyleBoxFlat
		sbh.bg_color = Color(0.07, 0.09, 0.16, 0.92)
		btn.add_theme_stylebox_override("hover", sbh)
		btn.pressed.connect(func() -> void: _on_skill_pressed(idx))
		# 15c: each button lives in a column with its skill NAME
		# labelled underneath (centred, font shrunk to fit rather
		# than truncated — see _fit_skill_name_label).
		var col := _vbox(2)
		col.custom_minimum_size = Vector2(112 if big else 104, 0)
		col.size_flags_vertical = Control.SIZE_SHRINK_END
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(btn)
		_skill_row.add_child(col)
		var nl := _label("", 12)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.custom_minimum_size = Vector2(112 if big else 104, 0)
		nl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		nl.add_theme_constant_override("shadow_offset_x", 1)
		nl.add_theme_constant_override("shadow_offset_y", 1)
		col.add_child(nl)
		_skill_name_labels.append(nl)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
		_skill_icons.append(icon)
		var sweep := TextureProgressBar.new()
		sweep.min_value = 0
		sweep.max_value = 100
		sweep.value = 0
		sweep.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		sweep.radial_initial_angle = 270.0
		sweep.texture_progress = sweep_tex
		sweep.tint_progress = Color(0.02, 0.03, 0.06, 0.74)
		sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
		sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(sweep)
		_skill_sweeps.append(sweep)
		var secs := _label("", 20 if big else 16, Color(1, 1, 1))
		secs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		secs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		secs.set_anchors_preset(Control.PRESET_FULL_RECT)
		secs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		secs.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		secs.add_theme_constant_override("shadow_offset_x", 1)
		secs.add_theme_constant_override("shadow_offset_y", 1)
		btn.add_child(secs)
		_skill_secs.append(secs)
		# 15c: an input catcher over the whole button face drives
		# the press-and-hold info card. It must be a CHILD of the
		# button: a disabled (cooling-down) Button swallows its own
		# input, but its children still receive gui_input (verified
		# empirically), so holding a cooling-down skill still opens
		# the card. The catcher accepts every left press/release,
		# so the Button's own pressed signal never fires — quick
		# taps are re-issued from _skill_release to preserve the
		# exact tap behaviour.
		var hit := Control.new()
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.add_child(hit)
		_skill_hits.append(hit)
		var cap_i := i
		var cap_hit := hit
		hit.gui_input.connect(func(ev: InputEvent) -> void:
				_on_skill_hit_input(cap_i, cap_hit, ev))
		_skill_btns.append(btn)
	_build_skill_info_card()


func _on_skill_pressed(idx: int) -> void:
	if game == null:
		return
	var hero: Unit = game.local_hero()
	if hero == null:
		return
	var ch: String = game.char_for(hero.owner_id)
	# 16b: exactly ONE skill (idx 1). Ground-targeted skills arm
	# the targeting flow; self-centred ones cast instantly.
	if idx != 1:
		return
	if game.skill_is_targeted(ch, 1):
		game.begin_skill_targeting(1)
	else:
		game.cast_local_skill()


## 15c: press-and-hold on a skill button. A press is timed by
## _update_skill_hold (from _process): crossing SKILL_HOLD_MSEC
## opens the info card and CONSUMES the press — releasing then
## only dismisses the card, never casts. A shorter press is a
## plain tap and re-issues _on_skill_pressed on release, exactly
## the old Button.pressed behaviour. Presentation only: nothing
## here touches the sim.
func _on_skill_hit_input(i: int, hit: Control, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	hit.accept_event()
	if mb.pressed:
		if _skill_info_card != null and _skill_info_card.visible \
				and _skill_press_idx != i:
			_hide_skill_info()
		_skill_press_idx = i
		_skill_press_msec = Time.get_ticks_msec()
		_skill_hold_fired = false
	else:
		_skill_release(i)


func _skill_release(i: int) -> void:
	if _skill_press_idx < 0:
		return
	var idx := _skill_press_idx
	var fired := _skill_hold_fired
	_skill_press_idx = -1
	_skill_hold_fired = false
	if fired:
		_hide_skill_info()
	elif idx == i and _skill_row != null and _skill_row.visible:
		var btn := _skill_btns[idx] as Button
		if btn != null and not btn.disabled:
			_on_skill_pressed(idx + 1)


func _update_skill_hold() -> void:
	if _skill_press_idx < 0:
		return
	# Touch arrives as emulated mouse (project setting), so the
	# mouse state covers both. A release the catcher somehow
	# missed (pointer dragged off mid-press) finalises here.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_skill_release(_skill_press_idx)
		return
	if not _skill_hold_fired \
			and Time.get_ticks_msec() - _skill_press_msec >= SKILL_HOLD_MSEC:
		_skill_hold_fired = true
		_show_skill_info(_skill_press_idx + 1)


## Shrink a skill name label's font until the full name fits its
## column (the owner asked for full names, shrunk — never cut).
func _fit_skill_name_label(i: int) -> void:
	var lbl := _skill_name_labels[i] as Label
	var col_w := 112.0
	var f := lbl.get_theme_default_font()
	var size := 12
	while size > 8 and f.get_string_size(lbl.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > col_w - 2.0:
		size -= 1
	lbl.add_theme_font_size_override("font_size", size)


func _build_skill_info_card() -> void:
	_skill_info_card = _panel(14, GOLD, Color(0.03, 0.05, 0.1, 0.94), 2)
	_skill_info_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skill_info_card.offset_left = -358
	_skill_info_card.offset_right = -16
	# The card floats 12 px above the raised skill row (whose top
	# edge is at -185), right-aligned with the cluster.
	_skill_info_card.offset_bottom = -197
	_skill_info_card.offset_top = -197
	_skill_info_card.visible = false
	_skill_info_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skill_info_card)
	var mc := _pad(12, 10, 12, 10)
	_skill_info_card.add_child(mc)
	var hb := _hbox(10)
	mc.add_child(hb)
	_skill_info_icon = TextureRect.new()
	_skill_info_icon.custom_minimum_size = Vector2(46, 46)
	_skill_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skill_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skill_info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_skill_info_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_skill_info_icon)
	var vb := _vbox(3)
	hb.add_child(vb)
	_skill_info_title = _label("", 16, GOLD_TXT)
	vb.add_child(_skill_info_title)
	_skill_info_cd = _label("", 12, Color(0.75, 0.82, 0.95))
	vb.add_child(_skill_info_cd)
	_skill_info_desc = _label("", 13)
	_skill_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_info_desc.custom_minimum_size = Vector2(262, 0)
	vb.add_child(_skill_info_desc)


func _show_skill_info(idx: int) -> void:
	if game == null or _skill_info_card == null:
		return
	var hero: Unit = game.local_hero()
	if hero == null:
		return
	var ch: String = game.char_for(hero.owner_id)
	var kit := Characters.kit_of(ch)
	_skill_info_title.text = String(kit.get("skill", ""))
	_skill_info_cd.text = "Hồi chiêu: %d giây" % int(round(Stats.hero_cd(ch)))
	_skill_info_desc.text = String(kit.get("skill_desc", ""))
	_skill_info_icon.texture = (_skill_icons[idx - 1] as TextureRect).texture
	_skill_info_card.visible = true
	var h := _skill_info_card.get_combined_minimum_size().y
	_skill_info_card.offset_top = _skill_info_card.offset_bottom - h


func _hide_skill_info() -> void:
	if _skill_info_card != null:
		_skill_info_card.visible = false


## 15c: tapping anywhere that is not a skill button dismisses an
## open skill info card (releasing the held button dismisses it
## too — see _skill_release). Read-only: the event itself is
## never consumed, so world clicks behave exactly as before.
func _input(ev: InputEvent) -> void:
	if _skill_info_card == null or not _skill_info_card.visible:
		return
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for b in _skill_btns:
		if (b as Button).get_global_rect().has_point(mb.position):
			return
	_hide_skill_info()


## Live state of the skill buttons (called from _process).
func _refresh_skill_button() -> void:
	if _skill_row == null or game == null:
		return
	# 15e-ter: this refresh is the one place that re-shows the
	# skill cluster (it keys on the watched slot's hero through
	# local_hero) — an observer never sees it, in any frame.
	if _is_observer():
		_skill_row.visible = false
		_skill_press_idx = -1
		_skill_hold_fired = false
		_hide_skill_info()
		return
	var hero: Unit = game.local_hero()
	_skill_row.visible = hero != null
	if hero == null:
		_skill_for_char = ""
		# 15c: no hero, no hold state and no info card.
		_skill_press_idx = -1
		_skill_hold_fired = false
		_hide_skill_info()
		return
	var ch: String = game.char_for(hero.owner_id)
	if ch != _skill_for_char:
		_skill_for_char = ch
		var kit := Characters.kit_of(ch)
		for i in range(1):
			var tex: Texture2D = load("res://assets/skill_icons/%s_1.png" % ch)
			(_skill_icons[i] as TextureRect).texture = tex
			(_skill_btns[i] as Button).tooltip_text = "%s — %s" % [
					String(kit.get("skill", "")), String(kit.get("skill_desc", ""))]
			# 15c: the name label under the button + the same
			# tooltip on the input catcher (it is what the cursor
			# actually hovers).
			(_skill_name_labels[i] as Label).text = String(kit.get("skill", ""))
			_fit_skill_name_label(i)
			(_skill_hits[i] as Control).tooltip_text = \
					(_skill_btns[i] as Button).tooltip_text
	var cds := [Stats.hero_cd(ch)]
	var lefts := [hero.skill_cd_t]
	for i in range(1):
		var frac := clampf(lefts[i] / cds[i], 0.0, 1.0) if cds[i] > 0.0 else 0.0
		(_skill_sweeps[i] as TextureProgressBar).value = frac * 100.0
		(_skill_btns[i] as Button).disabled = lefts[i] > 0.0
		(_skill_btns[i] as Button).modulate = Color(1.35, 1.2, 0.75) \
				if game.skill_targeting == i + 1 else Color.WHITE
		(_skill_secs[i] as Label).text = "" if lefts[i] <= 0.0 \
				else str(int(ceil(lefts[i])))


## Result screen (13y, Gameplay GDD): a centred modal over a dim
## backdrop — outcome banner + reason, duration · mode · map,
## the ranked movement line (stage 4 wiring, unchanged), the
## final standings sorted by score, a score-over-time chart, a
## per-player category breakdown, and Xem lại / Về sảnh actions.
## Everything below the header scrolls, so the screen renders a
## VARIABLE number of players (2 today; the queue design grows
## to 8) with no fixed row counts. Hidden until Main calls
## show_end_panel. Pausing is Main's job.
func _build_end_panel() -> void:
	_end_dim = ColorRect.new()
	_end_dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_end_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_dim.visible = false
	add_child(_end_dim)
	_end_panel = _panel(16, GOLD, Color(0.03, 0.05, 0.1, 0.94), 2)
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.offset_left = -440
	_end_panel.offset_right = 440
	_end_panel.offset_top = -300
	_end_panel.offset_bottom = 300
	_end_panel.visible = false
	add_child(_end_panel)
	var mc := _pad(20, 14, 20, 14)
	_end_panel.add_child(mc)
	var vb := _vbox(8)
	mc.add_child(vb)
	_end_title = _label("", 32, GOLD_TXT)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_end_title)
	_end_note = _label("", 13, Color(0.85, 0.9, 0.75))
	_end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_end_note)
	_end_context = _label("", 12, TXT_DIM)
	_end_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_end_context)
	_end_banner = _label("", 17, GOLD_TXT)
	_end_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_banner.visible = false
	vb.add_child(_end_banner)
	_end_rank = _label("", 13, TXT)
	_end_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_rank.visible = false
	vb.add_child(_end_rank)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = false
	vb.add_child(sc)
	var body := _vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	# 13y-AOV layout (Liên Quân post-match screen): MVP
	# spotlight first, then the standings as horizontal rows
	# under icon-headed stat columns, the score-over-time chart
	# as its own smaller section below the table, and finally
	# the per-player detail cards.
	_end_mvp = _vbox(0)
	body.add_child(_end_mvp)
	var st_title := _label("Bảng xếp hạng", 14, GOLD_TXT)
	body.add_child(st_title)
	body.add_child(_result_header())
	_end_standings = _vbox(4)
	body.add_child(_end_standings)
	var ch_title := _label("Điểm theo thời gian", 14, GOLD_TXT)
	body.add_child(ch_title)
	var chart_frame := _panel(10, BORDER_DIM, Color(0.015, 0.03, 0.07, 0.85), 1)
	chart_frame.custom_minimum_size = Vector2(0, 110)
	body.add_child(chart_frame)
	_end_chart = ScoreChart.new()
	_end_chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_frame.add_child(_end_chart)
	var bd_title := _label("Chi tiết từng người chơi", 14, GOLD_TXT)
	body.add_child(bd_title)
	_end_breakdown = _vbox(6)
	body.add_child(_end_breakdown)
	var brow := _hbox(10)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(brow)
	_end_replay_btn = _text_button("Xem lại")
	_end_replay_btn.custom_minimum_size = Vector2(150, 40)
	_end_replay_btn.visible = false
	_end_replay_btn.pressed.connect(_on_result_replay_pressed)
	brow.add_child(_end_replay_btn)
	var hb := _text_button("Về sảnh")
	hb.custom_minimum_size = Vector2(150, 40)
	hb.pressed.connect(func() -> void:
		if game != null and game.has_method("return_to_lobby"):
			game.return_to_lobby())
	brow.add_child(hb)
	Net.replay_received.connect(func(rp: Dictionary) -> void:
		if _result_replay_pending:
			_on_result_replay_data(rp))
	Net.replay_failed.connect(func(msg: String) -> void:
		if _result_replay_pending:
			_result_replay_pending = false
			_end_replay_btn.disabled = false
			_end_replay_btn.text = "Xem lại"
			show_message(msg))


## The Xem lại action exists only when the server actually
## recorded THIS match and pushed its replay id (custom rooms);
## called again when the id lands after the screen opened.
func refresh_result_actions() -> void:
	if _end_replay_btn == null:
		return
	_end_replay_btn.visible = game != null and game.mp_mode \
			and String(game.match_replay_id) != ""


func _on_result_replay_pressed() -> void:
	if game == null or _result_replay_pending:
		return
	_result_replay_pending = true
	_end_replay_btn.disabled = true
	_end_replay_btn.text = "Đang tải…"
	Net.fetch_replay(String(game.match_replay_id))


func _on_result_replay_data(rp: Dictionary) -> void:
	_result_replay_pending = false
	if String(rp.get("game_version", "")) != Net.GAME_VERSION:
		_end_replay_btn.disabled = false
		_end_replay_btn.text = "Xem lại"
		show_message("Bản ghi thuộc phiên bản game cũ — hãy xem từ Lịch sử trận đấu")
		return
	Net.begin_replay(rp)


## ------------------------------------------------------------ map choice
## Boot overlay: three biome cards (preview collage from the biome's
## own ground tiles + name + its modifier lines in plain Vietnamese)
## and one "Vào trận" button. Main shows it once per app run, paused;
## confirming calls Main.choose_biome — the same path tests drive.

func _build_map_panel() -> void:
	_map_root = Control.new()
	_map_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_root.visible = false
	add_child(_map_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_root.add_child(cc)
	var panel := _panel(16, GOLD, Color(0.03, 0.05, 0.1, 0.94))
	_add_blur(panel)
	cc.add_child(panel)
	var mc := _pad(20, 16, 20, 16)
	panel.add_child(mc)
	var vb := _vbox(12)
	mc.add_child(vb)
	var title := _label("Chọn bản đồ", 22, GOLD_TXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var row := _hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for id in Biomes.ORDER:
		row.add_child(_build_map_card(id))
	row.add_child(_build_map_card("random"))
	var ltitle := _label("Địa hình", 14, GOLD_TXT)
	ltitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ltitle)
	var lrow := _hbox(8)
	lrow.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(lrow)
	for lid in World.LAYOUTS:
		lrow.add_child(_build_layout_chip(lid))
	lrow.add_child(_build_layout_chip("random"))
	var go := _text_button("Vào trận")
	go.custom_minimum_size = Vector2(170, 40)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(confirm_map_choice)
	vb.add_child(go)
	var mp_btn := _text_button("Chơi mạng")
	mp_btn.custom_minimum_size = Vector2(170, 40)
	mp_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mp_btn.pressed.connect(func() -> void: if game != null: game.open_lobby())
	vb.add_child(mp_btn)
	# 13g: the map panel is the setup view behind the home screen
	# now — Quay lại returns to the painted home lobby.
	var back_btn := _text_button("Quay lại")
	back_btn.custom_minimum_size = Vector2(170, 40)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func() -> void:
		if game != null and game.has_method("return_home_from_setup"):
			game.return_home_from_setup())
	vb.add_child(back_btn)
	_map_sel = game.biome_id if game != null else "grassland"
	_layout_sel = game.layout_id if game != null else "plains"
	_refresh_map_cards()
	_refresh_layout_chips()


func _build_map_card(id: String) -> PanelContainer:
	var def := Biomes.data(id) if id != "random" else {
		"name": "Ngẫu nhiên", "tiles_dir": Biomes.data("grassland")["tiles_dir"],
		"mod_lines": "Khu vực và địa hình được chọn ngẫu nhiên khi vào trận"}
	var card := _panel(12, BORDER_DIM, Color(1, 1, 1, 0.04))
	card.custom_minimum_size = Vector2(198, 0)
	var mc := _pad(10, 10, 10, 10)
	card.add_child(mc)
	var vb := _vbox(6)
	mc.add_child(vb)
	var prev := TextureRect.new()
	prev.texture = _map_preview_texture(id)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	prev.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	prev.custom_minimum_size = Vector2(176, 92)
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(prev)
	var nm := _label(String(def["name"]), 16, GOLD_TXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var mods := _label(String(def["mod_lines"]), 11, TXT_DIM)
	mods.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mods.custom_minimum_size = Vector2(176, 0)
	mods.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(mods)
	var btn := _click_area(card)
	btn.pressed.connect(func() -> void: select_map_card(id))
	_map_cards[id] = card
	return card


## 2x2 collage of the biome's own ground tiles (land / land variant /
## shore / water) as the card's preview swatch.
func _map_preview_texture(id: String) -> Texture2D:
	var dir := String(Biomes.data(id if id != "random" else "grassland")["tiles_dir"])
	var names := ["grass_0", "grass_2", "shore_sand_n", "water_0"]
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for i in range(4):
		var tex: Texture2D = load(dir + names[i] + ".png")
		if tex == null:
			continue
		var t := tex.get_image()
		if t == null:
			continue
		t = t.duplicate()
		t.convert(Image.FORMAT_RGBA8)
		t.resize(48, 48, Image.INTERPOLATE_BILINEAR)
		img.blit_rect(t, Rect2i(0, 0, 48, 48), Vector2i((i % 2) * 48, (i / 2) * 48))
	return ImageTexture.create_from_image(img)


func _refresh_map_cards() -> void:
	for id in _map_cards:
		var card: PanelContainer = _map_cards[id]
		if id == _map_sel:
			card.add_theme_stylebox_override("panel", _sb(GOLD, Color(0.85, 0.64, 0.25, 0.13), 12))
		else:
			card.add_theme_stylebox_override("panel", _sb(BORDER_DIM, Color(1, 1, 1, 0.04), 12))


func select_map_card(id: String) -> void:
	if not (Biomes.is_valid(id) or id == "random"):
		return
	_map_sel = id
	_refresh_map_cards()


## Layout chips: compact selectable row under the biome cards.
func _build_layout_chip(id: String) -> Button:
	var chip := _text_button(String(World.LAYOUT_NAMES[id]))
	chip.custom_minimum_size = Vector2(0, 30)
	chip.pressed.connect(func() -> void: select_layout_chip(id))
	_layout_chips[id] = chip
	return chip


func _refresh_layout_chips() -> void:
	for id in _layout_chips:
		var chip: Button = _layout_chips[id]
		if id == _layout_sel:
			chip.add_theme_stylebox_override("normal", _sb(GOLD, Color(0.85, 0.64, 0.25, 0.16), 8))
		else:
			chip.add_theme_stylebox_override("normal", _sb(BORDER_DIM, Color(1, 1, 1, 0.04), 8))


func select_layout_chip(id: String) -> void:
	if not World.is_valid_layout(id):
		return
	_layout_sel = id
	_refresh_layout_chips()


func layout_selection() -> String:
	return _layout_sel


func confirm_map_choice() -> void:
	if game != null:
		game.choose_map(_map_sel, _layout_sel)


func show_map_panel() -> void:
	if _map_root == null:
		return
	_map_sel = game.biome_id if game != null else "grassland"
	_layout_sel = game.layout_id if game != null else "plains"
	_refresh_map_cards()
	_refresh_layout_chips()
	_map_root.visible = true


func hide_map_panel() -> void:
	if _map_root != null:
		_map_root.visible = false


func map_panel_visible() -> bool:
	return _map_root != null and _map_root.visible


func map_selection() -> String:
	return _map_sel


## 13y: a TRUE team match — some team fields at least two
## players. The only situation where team wording may appear
## (Tín's versus rule: "Kiểu đấu với nhau chứ có phải đội đâu").
func _is_team_match() -> bool:
	if game == null or not game.mp_mode:
		return false
	var counts := {}
	for s in range(game.slot_count()):
		var t: int = game.team_of_slot(s)
		counts[t] = int(counts.get(t, 0)) + 1
		if int(counts[t]) >= 2:
			return true
	return false


## Team labels on the result screen: genuine team matches in
## custom rooms only. Queue matches (Thường / Hạng) are versus
## by design — their queues become 8-player free-for-alls — so
## they never carry team grouping or labels.
func _result_team_labels() -> bool:
	return _is_team_match() and not Net.queued_room


## Player-facing name of one owner (result screen + breakdown).
func _result_name(owner: int) -> String:
	if game.mp_mode:
		if owner < game.slot_names.size() and String(game.slot_names[owner]) != "":
			return String(game.slot_names[owner])
		return "Người chơi %d" % (owner + 1)
	return _resolve_player_name() if owner == 0 else "Máy"


## "12:34 · Đấu thường · Đồng cỏ — Đồng bằng"
func _result_context(mt: int) -> String:
	var mode := "Đấu với máy"
	var biome_id := String(game.chosen_biome)
	var layout_id := String(game.chosen_layout)
	if game.mp_mode:
		if Net.ranked:
			mode = "Đấu hạng"
		elif Net.queued_room:
			mode = "Đấu thường"
		else:
			mode = "Phòng custom"
		biome_id = String(Net.pending_cfg.get("biome", biome_id))
		layout_id = String(Net.pending_cfg.get("layout", layout_id))
	var map := Biomes.display_name(biome_id)
	var lname := String(World.LAYOUT_NAMES.get(layout_id, ""))
	if lname != "":
		map += " — " + lname
	return "%02d:%02d · %s · %s" % [mt / 60, mt % 60, mode, map]


## 13y-AOV standings columns: [FA header glyph, caption, width].
## The header row and every player row share this geometry.
const RESULT_COLS: Array = [
	[FA_STAR, "Điểm", 78],
	[FA_CROSSHAIRS, "Hạ địch", 58],
	[FA_SKULL, "Mất quân", 62],
	[FA_GOLD, "Thu thập", 84],
	[FA_HAMMER, "Phá địch", 62],
	[FA_BOLT, "APM", 54],
]


## Rebuild the standings, chart and breakdown from Main's 13y
## accounting. Count-agnostic: it renders exactly the owners the
## match had, sorted by score (ties keep slot order).
func _refresh_result() -> void:
	var owners: Array = game.result_owners()
	owners.sort_custom(func(a: int, b: int) -> bool:
		var sa: int = game.match_score_of(a)
		var sb: int = game.match_score_of(b)
		if sa != sb:
			return sa > sb
		return a < b)
	for ch in _end_standings.get_children():
		_end_standings.remove_child(ch)
		ch.free()
	var teams := _result_team_labels()
	# AOV MVP spotlight: the top scorer, portrait forward.
	for ch in _end_mvp.get_children():
		_end_mvp.remove_child(ch)
		ch.free()
	if not owners.is_empty():
		_end_mvp.add_child(_result_mvp_card(int(owners[0]), teams))
	for i in range(owners.size()):
		_end_standings.add_child(_result_row(int(owners[i]), i, teams))
	_end_chart.set_data(game.stat_series, owners)
	for ch in _end_breakdown.get_children():
		_end_breakdown.remove_child(ch)
		ch.free()
	var show_iron := false
	for owner in owners:
		if int((game.stat_counters(owner).gathered as Dictionary).get("iron", 0)) > 0:
			show_iron = true
	for owner in owners:
		_end_breakdown.add_child(_result_block(owner, teams, show_iron))


## The standings header: rank + portrait spacers, "Người chơi",
## then one icon-headed cell per RESULT_COLS column (the AOV
## table convention — small glyph + caption over each column).
func _result_header() -> HBoxContainer:
	var row := _hbox(8)
	var rk := _label("#", 11, TXT_DIM)
	rk.custom_minimum_size = Vector2(30, 0)
	rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(rk)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(40, 0)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var nm := _label("Người chơi", 11, TXT_DIM)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	for col in RESULT_COLS:
		var cell := _vbox(0)
		cell.custom_minimum_size = Vector2(int(col[2]), 0)
		var ic := _fa(int(col[0]), 13, GOLD_TXT)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(ic)
		var cap := _label(String(col[1]), 9, TXT_DIM)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(cap)
		row.add_child(cell)
	return row


## Compact gold MVP tag (AOV style) for the spotlight + top row.
func _mvp_tag() -> PanelContainer:
	var tag := _panel(6, GOLD, Color(0.85, 0.62, 0.12, 0.95), 1)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mc := _pad(7, 1, 7, 1)
	tag.add_child(mc)
	var lb := _label("MVP", 11, Color(0.16, 0.10, 0.02))
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mc.add_child(lb)
	return tag


## Hero portrait in a slot-coloured frame (crown glyph when the
## match never drew a character, e.g. SP).
func _result_portrait(owner: int, px: int) -> PanelContainer:
	var frame := _panel(8, TeamColors.ui_color(owner),
			Color(0.02, 0.03, 0.07, 0.9), 1)
	frame.custom_minimum_size = Vector2(px, px)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex := Characters.avatar_for(game.char_for(owner))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
	else:
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(_fa(FA_CROWN, 18, TXT_DIM))
		frame.add_child(cc)
	return frame


## The AOV MVP spotlight: the match's top scorer, portrait large
## and gold-framed, name + MVP tag, score and headline counters.
func _result_mvp_card(owner: int, teams: bool) -> PanelContainer:
	var root := _panel(12, GOLD, Color(0.10, 0.08, 0.03, 0.92), 2)
	var mc := _pad(12, 8, 12, 8)
	root.add_child(mc)
	var row := _hbox(12)
	mc.add_child(row)
	row.add_child(_result_portrait(owner, 64))
	var vb := _vbox(2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vb)
	var nm := _result_name(owner)
	if teams:
		nm = "Đội %d · %s" % [game.team_of_slot(owner) + 1, nm]
	var nrow := _hbox(8)
	var nlb := _label(nm, 18, GOLD_TXT)
	nlb.clip_text = true
	nlb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(nlb)
	nrow.add_child(_mvp_tag())
	vb.add_child(nrow)
	var c: Dictionary = game.stat_counters(owner)
	vb.add_child(_label("Xuất sắc nhất trận · %d điểm" % game.match_score_of(owner),
			13, TXT))
	vb.add_child(_label("Hạ địch %d · Thu thập %d · Phá địch %d" % [
			int(c.kills), int(c.gathered_total), int(c.razed)], 12, TXT_DIM))
	var crown := _fa(FA_CROWN, 30, GOLD_TXT)
	row.add_child(crown)
	return root


## One AOV standings row: placement · hero portrait · name (+MVP
## tag on the top scorer; the local player's row wears the gold
## frame) · the RESULT_COLS stat columns, right-aligned.
func _result_row(owner: int, idx: int, teams: bool) -> PanelContainer:
	var is_local: bool = owner == (game.local_slot if game.mp_mode else 0)
	var is_mvp := idx == 0
	var bg := Color(0.05, 0.08, 0.15, 0.9) if idx % 2 == 0 \
			else Color(0.035, 0.055, 0.11, 0.9)
	var border := BORDER_DIM
	var bw := 1
	if is_local:
		border = GOLD
		bw = 2
	elif is_mvp:
		border = GOLD_DIM
	var root := _panel(10, border, bg, bw)
	var mc := _pad(8, 5, 8, 5)
	root.add_child(mc)
	var row := _hbox(8)
	mc.add_child(row)
	var rk := _label("#%d" % (idx + 1), 14, GOLD_TXT if is_mvp else TXT_DIM)
	rk.custom_minimum_size = Vector2(30, 0)
	rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rk)
	row.add_child(_result_portrait(owner, 40))
	var vb := _vbox(1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vb)
	var nm := _result_name(owner)
	if teams:
		nm = "Đội %d · %s" % [game.team_of_slot(owner) + 1, nm]
	var nrow := _hbox(6)
	var nlb := _label(nm, 14, GOLD_TXT if is_local else TXT)
	nlb.clip_text = true
	nlb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(nlb)
	if is_mvp:
		nrow.add_child(_mvp_tag())
	vb.add_child(nrow)
	vb.add_child(_label(AGE_TXT[clampi(game.owner_age(owner), 1, 4)], 11, TXT_DIM))
	var c: Dictionary = game.stat_counters(owner)
	var apm_txt := "—"
	if game.mp_mode or owner == 0:
		apm_txt = "%d" % int(round(game.apm_of(owner)))
	var vals: Array = ["%d" % game.match_score_of(owner), "%d" % int(c.kills),
			"%d" % int(c.lost), "%d" % int(c.gathered_total),
			"%d" % int(c.razed), apm_txt]
	for i in range(RESULT_COLS.size()):
		var cell := _label(vals[i], 15 if i == 0 else 13,
				GOLD_TXT if i == 0 else TXT)
		cell.custom_minimum_size = Vector2(int(RESULT_COLS[i][2]), 0)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cell)
	return root


## One breakdown card: the four GDD categories for one player.
func _result_block(owner: int, teams: bool, show_iron: bool) -> PanelContainer:
	var is_local: bool = owner == (game.local_slot if game.mp_mode else 0)
	var root := _panel(12, GOLD if is_local else BORDER_DIM,
			Color(0.05, 0.08, 0.15, 0.9), 2 if is_local else 1)
	var mc := _pad(10, 8, 10, 8)
	root.add_child(mc)
	var vb := _vbox(3)
	mc.add_child(vb)
	var nm := _result_name(owner)
	if teams:
		nm = "Đội %d · %s" % [game.team_of_slot(owner) + 1, nm]
	var head := _label("%s — %s — %d điểm" % [nm,
			AGE_TXT[clampi(game.owner_age(owner), 1, 4)],
			game.match_score_of(owner)], 13, GOLD_TXT if is_local else TXT)
	head.clip_text = true
	vb.add_child(head)
	var c: Dictionary = game.stat_counters(owner)
	var gat: Dictionary = c.gathered
	var parts: Array = []
	for r in ["food", "wood", "gold", "stone"]:
		parts.append("%s %d" % [game.res_vn(r).capitalize(), int(gat.get(r, 0))])
	if show_iron:
		parts.append("%s %d" % [game.res_vn("iron").capitalize(), int(gat.get("iron", 0))])
	vb.add_child(_label("Kinh tế — Thu thập %d (%s)" % [
			int(c.gathered_total), " · ".join(parts)], 12))
	var mil := "Quân sự — Huấn luyện %d · Mất %d · Hạ địch %d" % [
			int(c.trained), int(c.lost), int(c.kills)]
	if int(c.hero_kills) > 0:
		mil += " · Nhân vật chính hạ %d" % int(c.hero_kills)
	vb.add_child(_label(mil, 12))
	vb.add_child(_label("Công trình — Đã xây %d · Bị phá %d · Phá địch %d" % [
			int(c.built), int(c.blost), int(c.razed)], 12))
	# APM is counted for humans: MP counts the whole command
	# stream; in SP the AI issues orders outside the command
	# paths, so its APM is honestly not available.
	var apm_txt := "—"
	if game.mp_mode or owner == 0:
		apm_txt = "%d" % int(round(game.apm_of(owner)))
	vb.add_child(_label("Công nghệ — Đã nghiên cứu %d · APM %s" % [
			int(c.researched), apm_txt], 12))
	return root


func show_end_panel(result: String, match_time_sec: float, note: String = "") -> void:
	if _end_panel == null:
		return
	var surrendered: bool = game != null and game.local_surrendered
	if game != null and game.observer_mode:
		# 15a: a live observer has no win/loss — neutral title.
		_end_title.text = "KẾT THÚC"
		_end_title.add_theme_color_override("font_color", Color(1.0, 0.87, 0.45))
	elif surrendered:
		_end_title.text = "ĐẦU HÀNG"
		_end_title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	elif result == "victory":
		_end_title.text = "THẮNG"
		_end_title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	else:
		_end_title.text = "THUA"
		_end_title.add_theme_color_override("font_color", Color(0.98, 0.5, 0.45))
	_end_note.text = note
	_end_note.visible = note != ""
	var mt := int(match_time_sec)
	_end_context.text = _result_context(mt) if game != null else ""
	# Clamp the centred panel inside small viewports.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w := minf(880.0, vp.x - 24.0)
	var h := minf(600.0, vp.y - 24.0)
	_end_panel.offset_left = -w * 0.5
	_end_panel.offset_right = w * 0.5
	_end_panel.offset_top = -h * 0.5
	_end_panel.offset_bottom = h * 0.5
	if game != null:
		_refresh_result()
	_end_dim.visible = true
	_end_panel.visible = true
	_refresh_end_rank()
	refresh_result_actions()


## Ranked ladder movement for this match (pushed by the server
## after the referee's result is banked — may arrive just after
## the panel opens, so this also refreshes a visible panel).
func set_rank_result(info: Dictionary) -> void:
	_rank_result = info
	_refresh_end_rank()


func _refresh_end_rank() -> void:
	if _end_rank == null:
		return
	var has := not _rank_result.is_empty()
	_end_rank.visible = has
	_end_banner.visible = false
	if not has:
		return
	var after: Dictionary = _rank_result.get("after", {})
	var delta := int(_rank_result.get("star_delta", 0))
	var star_txt := "Không đổi sao"
	if delta > 0:
		star_txt = "+%d sao" % delta
		# Name every bonus star the delta is made of (13i): a
		# streak star reads "(chuỗi thắng)", a first-win-of-
		# the-day star "(thưởng ngày)", both joined with " + ".
		var parts: Array = []
		if bool(_rank_result.get("bonus", false)):
			parts.append("chuỗi thắng")
		if bool(_rank_result.get("daily_bonus", false)):
			parts.append("thưởng ngày")
		if not parts.is_empty():
			star_txt += " (" + " + ".join(parts) + ")"
	elif delta < 0:
		star_txt = "%d sao" % delta
	_end_rank.text = "%s · %s · MMR %d" % [star_txt,
			String(after.get("rank_text", "")),
			int(_rank_result.get("mmr_after", 0))]
	if bool(_rank_result.get("promoted", false)):
		_end_banner.text = "Lên hạng %s!" % String(after.get("short_text", ""))
		_end_banner.add_theme_color_override("font_color", GOLD_TXT)
		_end_banner.visible = true
	elif bool(_rank_result.get("demoted", false)):
		_end_banner.text = "Xuống hạng %s" % String(after.get("short_text", ""))
		_end_banner.add_theme_color_override("font_color", Color(0.98, 0.5, 0.45))
		_end_banner.visible = true


## Same call the Công nghệ page button makes (tests drive this path).
func ui_age_up() -> bool:
	if game == null:
		return false
	return game.start_age_up()


func _build_top_bar() -> void:
	_top_bar = _panel(12, BORDER, GLASS_BG_SOFT if USE_BLUR else GLASS_BG)
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = 6
	_top_bar.offset_right = -6
	_top_bar.offset_top = 6
	_top_bar.offset_bottom = 62
	_add_blur(_top_bar)
	add_child(_top_bar)
	var mc := _pad(8, 4, 8, 4)
	_top_bar.add_child(mc)
	var row := _hbox(7)
	mc.add_child(row)

	# Player chip (13u): the account's square avatar + the
	# player-facing name (display name; guests read "Khách").
	_identity_chip = _panel(10, BORDER, GLASS_BG)
	_identity_chip.custom_minimum_size = Vector2(178, 46)
	row.add_child(_identity_chip)
	var cmc := _pad(7, 4, 7, 4)
	_identity_chip.add_child(cmc)
	var ch := _hbox(6)
	cmc.add_child(ch)
	_player_avatar = TextureRect.new()
	_player_avatar.custom_minimum_size = Vector2(36, 36)
	_player_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_player_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_player_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_player_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(_player_avatar)
	var vb := _vbox(1)
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(vb)
	_player_name_label = _label("Khách", 13)
	vb.add_child(_player_name_label)
	_refresh_player_chip()

	# Age badge: painted shield texture for the current age + age name.
	_age_badge = TextureRect.new()
	_age_badge.custom_minimum_size = Vector2(48, 52) # slight overflow vs the 46 px chips: intentional for a shield badge
	_age_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_age_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_age_badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_age_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_age_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_age_badge)
	refresh_age_badge()
	_age_name_label = _label("Thời đại\nHắc ám", 10)
	_age_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_age_name_label)

	# Resource chips with real gather rates. 13u addendum: the
	# whole cluster is the entry point of the in-match statistics
	# panel — every chip carries a full-area tap target.
	for t in RESOURCE_TYPES:
		var rc := _panel(10, BORDER, GLASS_BG)
		rc.custom_minimum_size = Vector2(88, 46)
		row.add_child(rc)
		_res_chip_panels.append(rc)
		var rc_click := _click_area(rc)
		rc_click.pressed.connect(func() -> void: toggle_tab("stats"))
		var rmc := _pad(6, 3, 6, 3)
		rc.add_child(rmc)
		var rh := _hbox(5)
		rmc.add_child(rh)
		rh.add_child(_pic(t, 20))
		var rv := _vbox(0)
		rh.add_child(rv)
		var amt := _label("0", 14)
		var rate := _label("+0/s", 9, TXT_DIM)
		rv.add_child(amt)
		rv.add_child(rate)
		res_chips[t] = {"amt": amt, "rate": rate}

	# Population chip.
	_pop_chip = _panel(10, BORDER, GLASS_BG)
	_pop_chip.custom_minimum_size = Vector2(72, 46)
	row.add_child(_pop_chip)
	var pmc := _pad(6, 3, 6, 3)
	_pop_chip.add_child(pmc)
	var ph := _hbox(5)
	pmc.add_child(ph)
	ph.add_child(_pic("pop", 20))
	_pop_label = _label("0/0", 14)
	_pop_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(_pop_label)

	# Match timer (stopwatch icon + MM:SS).
	_timer_box = _hbox(4)
	_timer_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_timer_box)
	_timer_box.add_child(_pic("timer", 18))
	_timer_label = _label("00:00", 14)
	_timer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timer_box.add_child(_timer_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Round buttons (13u: Font Awesome glyphs): chat opens the
	# chat panel (in SP it shows an honest online-only line),
	# users opens the match players panel, gear opens Settings.
	var chat := _fa_button(FA_COMMENTS, 20, 40)
	chat.btn.pressed.connect(func() -> void: toggle_chat())
	row.add_child(chat.panel)
	var friends := _fa_button(FA_USERS, 20, 40)
	friends.btn.pressed.connect(_on_people_button)
	row.add_child(friends.panel)
	# 15b: the diplomacy button exists only in diplomacy
	# matches (visibility refreshed per frame in _refresh_panels).
	var dip := _fa_button(FA_HANDSHAKE, 20, 40)
	dip.btn.pressed.connect(func() -> void: toggle_tab("diplomacy"))
	row.add_child(dip.panel)
	_dip_top_btn = dip.panel
	_dip_top_btn.visible = false
	var gear := _fa_button(FA_GEAR, 20, 40)
	gear.btn.pressed.connect(func() -> void: toggle_tab("settings"))
	row.add_child(gear.panel)


## The top-right people button: PLAYERS get the players modal;
## an OBSERVER gets the dedicated spectator panel instead
## (15e-bis — owner correction: "lúc xem thì hiện panel xem
## chứ sao hiện lại panel người chơi"). Observer branch only;
## the player path below is exactly the old wiring.
func _on_people_button() -> void:
	if game != null and game.observer_mode and game.spectator != null:
		game.spectator.toggle_panel()
		return
	toggle_tab("players")


## The name the local player is known by: in MP the match slot
## name (the player-facing name they entered with), else the
## account display name (13r — username fallback inside
## Net.display_name), else "Khách" for guests.
func _resolve_player_name() -> String:
	if game != null and game.mp_mode and game.local_slot >= 0 \
			and game.local_slot < game.slot_names.size():
		var sn := String(game.slot_names[game.local_slot])
		if sn != "":
			return sn
	if Net.account_name != "":
		return Net.display_name()
	return "Khách"


## Top-left identity sync: avatar follows the account's pick
## (17d: the anime catalogue — Avatars tracks Net's pushes).
func _refresh_player_chip() -> void:
	if _player_name_label != null:
		var nm := _resolve_player_name()
		if _player_name_label.text != nm:
			_player_name_label.text = nm
	if _player_avatar != null:
		var aid := Avatars.local_avatar()
		if aid != _avatar_shown_id:
			_avatar_shown_id = aid
			_player_avatar.texture = Avatars.texture_for(aid)


func _build_message_label() -> void:
	_msg_label = _label("", 13, Color(1.0, 0.87, 0.5))
	_msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_label.offset_left = -320
	_msg_label.offset_right = 320
	_msg_label.offset_top = 68
	_msg_label.offset_bottom = 92
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_msg_label.add_theme_constant_override("shadow_offset_x", 1)
	_msg_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_msg_label)
	# Persistent warning while the player's Town Center is down but
	# they fight on under the annihilation rules (Main drives it).
	_tc_warn_label = _label("Town Center đã mất — còn Dân và công trình huấn luyện là còn chiến đấu được!",
			13, Color(1.0, 0.45, 0.35))
	_tc_warn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tc_warn_label.offset_left = -400
	_tc_warn_label.offset_right = 400
	_tc_warn_label.offset_top = 94
	_tc_warn_label.offset_bottom = 118
	_tc_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tc_warn_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_tc_warn_label.add_theme_constant_override("shadow_offset_x", 1)
	_tc_warn_label.add_theme_constant_override("shadow_offset_y", 1)
	_tc_warn_label.visible = false
	add_child(_tc_warn_label)


func _build_minimap() -> void:
	var frame := _panel(12, GOLD_DIM, GLASS_BG)
	frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	frame.offset_left = 6
	frame.offset_top = -162
	frame.offset_right = 222
	frame.offset_bottom = -6
	add_child(frame)
	var mc := _pad(7, 7, 7, 7)
	frame.add_child(mc)
	minimap = Minimap.new()
	minimap.game = game
	mc.add_child(minimap)

	# Three functional side buttons.
	_minimap_btns = _vbox(6)
	_minimap_btns.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap_btns.offset_left = 230
	_minimap_btns.offset_top = -144
	_minimap_btns.offset_right = 274
	_minimap_btns.offset_bottom = -6
	add_child(_minimap_btns)
	var flag := _fa_button(FA_FLAG, 10, 42)
	_flag_panel = flag.panel
	flag.btn.pressed.connect(func() -> void:
		if game == null:
			return
		game.rally_setting = not game.rally_setting
		if game.rally_setting:
			show_message("Đặt điểm tập kết: nhấp vào bản đồ"))
	_minimap_btns.add_child(flag.panel)
	var center := _fa_button(FA_CROSSHAIRS, 10, 42)
	center.btn.pressed.connect(func() -> void: if game != null: game.center_on_own_tc())
	_minimap_btns.add_child(center.panel)
	var layers := _fa_button(FA_LAYERS, 10, 42)
	layers.btn.pressed.connect(func() -> void: if game != null: game.select_all_villagers())
	_minimap_btns.add_child(layers.panel)


func _build_action_bar() -> void:
	_action_bar = _hbox(6)
	_action_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_action_bar.offset_left = -384
	_action_bar.offset_right = -6
	_action_bar.offset_top = -78
	_action_bar.offset_bottom = -6
	add_child(_action_bar)
	var defs := [
		["build", "build", "Xây dựng"],
		["train", "train", "Huấn luyện"],
		["tech", "tech", "Công nghệ"],
		["khac", "dots", "Khác"],
	]
	for d in defs:
		var tab: String = d[0]
		var p := _panel(12, GOLD_DIM, GLASS_BG)
		p.custom_minimum_size = Vector2(90, 66)
		var mc := _pad(4, 5, 4, 5)
		p.add_child(mc)
		var vb := _vbox(2)
		mc.add_child(vb)
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(_pic(d[1], 26))
		vb.add_child(cc)
		var lb := _label(d[2], 12)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lb)
		var btn := _click_area(p)
		btn.pressed.connect(func() -> void: toggle_tab(tab))
		_action_panels[tab] = p
		_action_bar.add_child(p)


func _card(icon_kind: String, title: String, sub: String, btn_text: String, dim: bool = false) -> Dictionary:
	var row := _hbox(8)
	# Military cards share the painted crossed-swords icon ("train").
	var ic: Control = _pic("train" if icon_kind == "swords" else icon_kind, 26)
	if dim:
		ic.modulate = Color(1, 1, 1, 0.4)
	row.add_child(ic)
	var vb := _vbox(0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vb)
	vb.add_child(_label(title, 13, TXT_DIM if dim else TXT))
	var sub_lb := _label(sub, 11, TXT_DIM)
	sub_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub_lb)
	var btn := _text_button(btn_text)
	btn.custom_minimum_size = Vector2(92, 34)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(btn)
	return {"row": row, "btn": btn}


## Build-page card whose icon is the building's own tier-1 art (used
## when the painted icon set has no match for the building).
func _card_art(btype: String, title: String, sub: String, btn_text: String) -> Dictionary:
	var row := _hbox(8)
	var tex := Building.tier_texture(btype, 1)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.custom_minimum_size = Vector2(36, 30)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	else:
		row.add_child(_pic("build", 26))
	var vb := _vbox(0)
	row.add_child(vb)
	vb.add_child(_label(title, 13))
	vb.add_child(_label(sub, 11, TXT_DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var btn := _text_button(btn_text)
	btn.custom_minimum_size = Vector2(64, 34)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(btn)
	return {"row": row, "btn": btn}


## Train-page card whose icon is the unit's own first idle frame
## (the new units have no painted icon; their art is the thumbnail).
func _card_unit(kind: String, title: String, sub: String, btn_text: String) -> Dictionary:
	var row := _hbox(8)
	var data := Unit.get_sheet(kind, 0)
	var tex: Texture2D = data.get("tex")
	if tex != null:
		var cell: Vector2i = data.get("cell", Vector2i(82, 82))
		var at := AtlasTexture.new()
		at.atlas = tex
		# Crop to the figure's alpha bbox inside the first frame —
		# wide cells (cavalry/ram) would shrink the figure to a sliver.
		var region := Rect2(0, 0, cell.x, cell.y)
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var frame_img := img.get_region(Rect2i(0, 0, mini(cell.x, img.get_width()), mini(cell.y, img.get_height())))
			var used := frame_img.get_used_rect()
			if used.size.x > 4 and used.size.y > 4:
				region = Rect2(used)
		at.region = region
		var tr := TextureRect.new()
		tr.texture = at
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.custom_minimum_size = Vector2(36, 30)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	else:
		row.add_child(_pic("train", 26))
	var vb := _vbox(0)
	row.add_child(vb)
	vb.add_child(_label(title, 13))
	vb.add_child(_label(sub, 11, TXT_DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var btn := _text_button(btn_text)
	btn.custom_minimum_size = Vector2(64, 34)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(btn)
	return {"row": row, "btn": btn}


func _page(title: String) -> VBoxContainer:
	var vb := _vbox(6)
	vb.add_child(_label(title, 13, GOLD_TXT))
	return vb


func _build_subpanel() -> void:
	_subpanel = _panel(12, BORDER, GLASS_BG_SOFT if USE_BLUR else GLASS_BG)
	_subpanel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_subpanel.offset_left = -570
	_subpanel.offset_right = -6
	_subpanel.offset_top = -356
	_subpanel.offset_bottom = -84
	_add_blur(_subpanel)
	_subpanel.visible = false
	add_child(_subpanel)
	var mc := _pad(10, 8, 10, 8)
	_subpanel.add_child(mc)

	_build_build_page(mc)
	_build_train_page(mc)
	_build_tech_page(mc)
	# 13x: Settings / Players / Statistics are centred modals now
	# (see _build_info_modals) — no longer pages of this subpanel.

	# --- Khác page: pause / restart / multiplayer placeholder.
	var kp := _page("Khác")
	_pause_btn = _text_button("Tạm dừng")
	_pause_btn.pressed.connect(func() -> void:
		if game != null:
			game.set_paused(not game.paused))
	kp.add_child(_pause_btn)
	var restart_btn := _text_button("Chơi lại")
	restart_btn.pressed.connect(func() -> void: if game != null: game.restart_match())
	kp.add_child(restart_btn)
	var mp_btn := _text_button("Nhiều người chơi (P4)")
	mp_btn.disabled = true
	kp.add_child(mp_btn)
	_surrender_btn = _text_button("Đầu hàng")
	_surrender_btn.pressed.connect(_on_surrender_pressed)
	kp.add_child(_surrender_btn)
	mc.add_child(kp)
	_pages["khac"] = kp

	for k in _pages:
		_pages[k].visible = false


## ------------------------------------------------------------------
## 13x modals: Settings / Players / Statistics
## ------------------------------------------------------------------
## Rebuilt from the 13u subpanel pages into CENTRED modals of the
## chat (13w) family — navy glass card, 2px gold frame, screen
## blur, dim backdrop (tap or Esc closes) — per Tín's research-
## backed redesign order. Patterns adopted (see KE-HOACH 13x):
## player identity led by the slot colour with the score large at
## the right edge (AoE2 scoreboard convention); every player's
## rows in the SAME column order, left-aligned, numbers in fixed
## right-aligned columns (scoreboard readability practice); status
## as colour + text label, never colour alone. Unlike chat these
## panels are NOT draggable — they stay centred.

## Builds one centred modal shell and returns its content column
## (below the header). The header is static: FA glyph + gold
## title + close button (no drag handle, by design).
func _make_modal(tab: String, fa_cp: int, title: String, size: Vector2) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_close_panel())
	add_child(dim)
	var panel := _panel(16, GOLD, Color(0.03, 0.05, 0.1, 0.94), 2)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = size
	panel.size = size
	# No _add_blur here: the blur rect would become the panel's
	# visible surface and let the world read through the body
	# (the settings rows sit directly on it). The chat panel gets
	# away with it because its opaque scroll area covers the body;
	# these modals wear the solid navy glass instead.
	panel.visible = false
	add_child(panel)
	_modals[tab] = {"dim": dim, "panel": panel, "size": size}
	var mc := _pad(14, 12, 14, 12)
	panel.add_child(mc)
	var vb := _vbox(10)
	mc.add_child(vb)
	var header := _panel(10, BORDER_DIM, Color(1, 1, 1, 0.04))
	header.custom_minimum_size = Vector2(0, 46)
	vb.add_child(header)
	var hmc := _pad(10, 5, 8, 5)
	header.add_child(hmc)
	var head := _hbox(8)
	hmc.add_child(head)
	head.add_child(_fa(fa_cp, 18, GOLD_TXT))
	head.add_child(_label(title, 16, GOLD_TXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var close_btn := _fa_button(FA_XMARK, 8, 32)
	close_btn.btn.pressed.connect(func() -> void: _close_panel())
	head.add_child(close_btn.panel)
	return vb


## Shows one modal (centred) or hides them all (tab == "").
func _show_modal(tab: String) -> void:
	for t in _modals:
		var m: Dictionary = _modals[t]
		var on: bool = (t == tab)
		(m.panel as Control).visible = on
		(m.dim as Control).visible = on
		if on:
			var p := m.panel as PanelContainer
			var sz: Vector2 = m.size
			p.size = sz
			var vp := p.get_viewport_rect().size
			p.position = (vp - sz) * 0.5


## A scroll area in the chat family's inset style, for the two
## list modals (players / stats).
func _modal_scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = false
	sc.add_theme_stylebox_override("panel",
			_sb(BORDER_DIM, Color(0.015, 0.03, 0.07, 0.85), 10))
	return sc


func _modal_scroll_box(sc: ScrollContainer, sep: int) -> VBoxContainer:
	var rmc := MarginContainer.new()
	rmc.add_theme_constant_override("margin_left", 6)
	rmc.add_theme_constant_override("margin_top", 6)
	rmc.add_theme_constant_override("margin_right", 6)
	rmc.add_theme_constant_override("margin_bottom", 6)
	rmc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rmc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(rmc)
	var box := _vbox(sep)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rmc.add_child(box)
	return box


func _build_info_modals() -> void:
	_build_settings_modal()
	_build_players_modal()
	_build_stats_modal()
	_build_diplomacy_modal()


func _settings_slider(minv: float, maxv: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 28)
	# 13x polish: a slim dark groove with a gold filled portion
	# (the value reads as a gold level, like the chat send key).
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.02, 0.03, 0.06, 0.9)
	track.set_corner_radius_all(4)
	track.content_margin_top = 11
	track.content_margin_bottom = 11
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.64, 0.25, 0.6)
	fill.set_corner_radius_all(4)
	s.add_theme_stylebox_override("grabber_area", fill)
	var fillh := StyleBoxFlat.new()
	fillh.bg_color = Color(0.85, 0.64, 0.25, 0.85)
	fillh.set_corner_radius_all(4)
	s.add_theme_stylebox_override("grabber_area_highlight", fillh)
	return s


## One polished settings row (13x): the FA glyph sits in a small
## gold-tinted chip, then a fixed-width label; the caller appends
## the slider/control and a right-aligned % value.
func _settings_row(cp: int, title: String) -> HBoxContainer:
	var row := _hbox(10)
	var chip := _panel(9, GOLD_DIM, Color(0.85, 0.64, 0.25, 0.13), 1)
	chip.custom_minimum_size = Vector2(36, 36)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(_fa(cp, 16, GOLD_TXT))
	chip.add_child(cc)
	row.add_child(chip)
	var lb := _label(title, 13)
	lb.custom_minimum_size = Vector2(104, 0)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lb)
	return row


## Right-aligned fixed-width % readout for a settings slider.
func _settings_val(text: String) -> Label:
	var lb := _label(text, 12, TXT)
	lb.custom_minimum_size = Vector2(46, 0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lb


## Settings modal (gear): exactly Âm thanh / Ánh sáng / Hiển thị
## tên / Đầu hàng — every control is live-wired (see the
## settings section above) and persisted. 13x presentation:
## polished slider rows (glyph chip · label · slider · % value),
## a pill toggle for names, and the surrender action set apart
## under a divider, full width.
func _build_settings_modal() -> void:
	var vb := _make_modal("settings", FA_GEAR, "Cài đặt", SETTINGS_SIZE)
	var mrow := _settings_row(FA_MUSIC, "Nhạc")
	# All three sliders share ONE 0..100 scale (13x correction):
	# the number shown ALWAYS equals the knob's filled percent
	# of the track. Volumes convert back to 0..1 internally;
	# brightness maps 0..100 onto the 0.5x..1.5x multiplier.
	_set_music_slider = _settings_slider(0.0, 100.0, 1.0, _music_vol * 100.0)
	_set_music_slider.value_changed.connect(func(v: float) -> void:
		_music_vol = v / 100.0
		_set_music_val.text = "%d%%" % int(round(v))
		_apply_audio()
		_save_settings())
	mrow.add_child(_set_music_slider)
	_set_music_val = _settings_val("%d%%" % int(round(_music_vol * 100.0)))
	mrow.add_child(_set_music_val)
	vb.add_child(mrow)
	var srow := _settings_row(FA_VOLUME, "Hiệu ứng")
	_set_sfx_slider = _settings_slider(0.0, 100.0, 1.0, _sfx_vol * 100.0)
	_set_sfx_slider.value_changed.connect(func(v: float) -> void:
		_sfx_vol = v / 100.0
		_set_sfx_val.text = "%d%%" % int(round(v))
		_apply_audio()
		_save_settings())
	srow.add_child(_set_sfx_slider)
	_set_sfx_val = _settings_val("%d%%" % int(round(_sfx_vol * 100.0)))
	srow.add_child(_set_sfx_val)
	vb.add_child(srow)
	var brow := _settings_row(FA_SUN, "Ánh sáng")
	_set_bright_slider = _settings_slider(0.0, 100.0, 1.0, _bright_pct)
	_set_bright_slider.value_changed.connect(func(v: float) -> void:
		_bright_pct = v
		_brightness = 0.5 + v / 100.0
		_set_bright_val.text = "%d%%" % int(round(v))
		_apply_brightness()
		_save_settings())
	brow.add_child(_set_bright_slider)
	_set_bright_val = _settings_val("%d%%" % int(round(_bright_pct)))
	brow.add_child(_set_bright_val)
	vb.add_child(brow)
	var nrow := _settings_row(FA_EYE, "Hiển thị tên")
	_set_names_btn = _text_button("")
	_set_names_btn.custom_minimum_size = Vector2(104, 32)
	_set_names_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_set_names_btn.pressed.connect(func() -> void:
		_show_names = not _show_names
		_apply_names()
		_save_settings()
		_refresh_names_btn())
	var nsp := Control.new()
	nsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nrow.add_child(nsp)
	nrow.add_child(_set_names_btn)
	vb.add_child(nrow)
	_refresh_names_btn()
	_set_surrender_div = HSeparator.new()
	var dl := StyleBoxLine.new()
	dl.color = BORDER_DIM
	dl.thickness = 1
	_set_surrender_div.add_theme_stylebox_override("separator", dl)
	vb.add_child(_set_surrender_div)
	_set_surrender_btn = _text_button("Đầu hàng")
	_set_surrender_btn.custom_minimum_size = Vector2(0, 36)
	_set_surrender_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_surrender_btn.add_theme_color_override("font_color", Color(1.0, 0.62, 0.55))
	_set_surrender_btn.add_theme_stylebox_override("normal",
			_sb(Color(1.0, 0.45, 0.4, 0.4), Color(1.0, 0.4, 0.35, 0.07), 8))
	_set_surrender_btn.add_theme_stylebox_override("hover",
			_sb(Color(1.0, 0.45, 0.4, 0.6), Color(1.0, 0.4, 0.35, 0.14), 8))
	_set_surrender_btn.pressed.connect(_on_surrender_pressed)
	vb.add_child(_set_surrender_btn)


## The names toggle wears its state (13x): gold pill while on,
## dim outline while off — text stays "Đang bật" / "Đang tắt".
func _refresh_names_btn() -> void:
	if _set_names_btn == null:
		return
	_set_names_btn.text = "Đang bật" if _show_names else "Đang tắt"
	if _show_names:
		_set_names_btn.add_theme_stylebox_override("normal",
				_sb(GOLD, Color(0.85, 0.64, 0.25, 0.2), 8))
		_set_names_btn.add_theme_color_override("font_color", GOLD_TXT)
	else:
		_set_names_btn.add_theme_stylebox_override("normal",
				_sb(BORDER_DIM, Color(1, 1, 1, 0.04), 8))
		_set_names_btn.add_theme_color_override("font_color", TXT_DIM)


func _build_players_modal() -> void:
	var vb := _make_modal("players", FA_USERS, "Người chơi", PLAYERS_SIZE)
	var sc := _modal_scroll()
	vb.add_child(sc)
	_players_box = _modal_scroll_box(sc, 6)


## Status pill (13x): the status colour tints a soft fill and
## the border, but the state is always spelled out in text too —
## never colour alone.
func _status_pill(text: String, col: Color) -> PanelContainer:
	var pill := _panel(9, Color(col.r, col.g, col.b, 0.55),
			Color(col.r, col.g, col.b, 0.15), 1)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pmc := _pad(9, 3, 9, 3)
	pill.add_child(pmc)
	var lb := _label(text, 11, col)
	lb.custom_minimum_size = Vector2(76, 0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pmc.add_child(lb)
	return pill


## One player card (13x): a slot-colour band leads (the AoE
## convention — identity is the player's colour), then the
## hero's square portrait: full colour with a gold-tinted frame
## while the hero is on the field, dimmed before that. Name +
## team/hero line in the middle, status pill at the right edge.
## The local player's card wears the gold frame.
func _player_card(col: Color, pname: String, sub: String,
		status: String, status_col: Color, char_id: String,
		hero_alive: bool, is_local: bool, frame_id: String = "") -> PanelContainer:
	var root := _panel(12, GOLD if is_local else BORDER_DIM,
			Color(0.05, 0.08, 0.15, 0.9), 2 if is_local else 1)
	var mc := _pad(10, 8, 10, 8)
	root.add_child(mc)
	var row := _hbox(10)
	mc.add_child(row)
	var band := Panel.new()
	band.custom_minimum_size = Vector2(6, 0)
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = col
	bsb.set_corner_radius_all(3)
	band.add_theme_stylebox_override("panel", bsb)
	row.add_child(band)
	var frame := _panel(8, GOLD_DIM if hero_alive else BORDER_DIM,
			Color(0.02, 0.03, 0.07, 0.9), 1)
	frame.custom_minimum_size = Vector2(46, 46)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tex := Characters.avatar_for(char_id)
	if tex != null:
		# 17d: the hero portrait wears the slot account's
		# equipped frame (shared helper, static at this size).
		var tr := AvatarFrame.new()
		tr.set_content(tex, frame_id, false)
		if not hero_alive:
			tr.modulate = Color(1, 1, 1, 0.45)
		frame.add_child(tr)
	else:
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(_fa(FA_CROWN, 18, TXT_DIM))
		frame.add_child(cc)
	row.add_child(frame)
	var vb := _vbox(1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vb)
	var nm := _label(pname, 14, GOLD_TXT if is_local else TXT)
	nm.clip_text = true
	vb.add_child(nm)
	var sb := _label(sub, 12, TXT_DIM)
	sb.clip_text = true
	vb.add_child(sb)
	row.add_child(_status_pill(status, status_col))
	return root


## Players modal content: one card per player in the MATCH
## (slot colour, player-facing name, team, hero, live status).
## SP lists the player + the bot side. Statuses are the ones the
## sim actually tracks — a surrender eliminates through the same
## path as annihilation (see Main._mp_apply_surrender), so a
## surrendered player truthfully reads "Đã bị loại".
func _refresh_players() -> void:
	if _players_box == null or game == null:
		return
	for ch in _players_box.get_children():
		_players_box.remove_child(ch)
		ch.free()
	if game.mp_mode:
		var n: int = game.slot_count()
		# Versus rule (Tín: "Kiểu đấu với nhau chứ có phải đội
		# đâu"): team wording exists ONLY in a true team match
		# (some team fields 2+ players). A 1v1 reads "Đấu với
		# nhau", a larger all-solo match "Đấu tự do", and the
		# per-player line drops the team prefix entirely.
		var team_match := _is_team_match()
		var sub: String
		if team_match:
			var teams := {}
			for s in range(n):
				teams[game.team_of_slot(s)] = true
			sub = "%d đội · %d người chơi" % [teams.size(), n]
		elif n == 2:
			sub = "Đấu với nhau · %d người chơi" % n
		else:
			sub = "Đấu tự do · %d người chơi" % n
		_players_box.add_child(_label(sub, 12, TXT_DIM))
		for slot in range(n):
			var pname := "Người chơi %d" % (slot + 1)
			if slot < game.slot_names.size() and String(game.slot_names[slot]) != "":
				pname = String(game.slot_names[slot])
			var alive: bool = game.king_alive(slot)
			var hero_txt := "Nhân vật: %s" % str(Characters.kit_of(game.char_for(slot)).get("name", ""))
			hero_txt += " · đang chiến đấu" if alive else " · chưa xuất trận"
			var card_sub := hero_txt
			if team_match:
				card_sub = "Đội %d · %s" % [game.team_of_slot(slot) + 1, hero_txt]
			# 15e: an observer holds no seat — every card shows
			# the player's match score (the same summary figure
			# the result screen computes) and no card is framed
			# as "mine".
			if game.observer_mode:
				card_sub += " · Điểm: %d" % game.match_score_of(slot)
			var status := "Đang chơi"
			var scol := GREEN
			if slot < game.slot_eliminated.size() and game.slot_eliminated[slot]:
				status = "Đã bị loại"
				scol = Color(1.0, 0.55, 0.45)
			elif slot < game.slot_inert.size() and game.slot_inert[slot]:
				status = "Mất kết nối"
				scol = Color(1.0, 0.85, 0.45)
			_players_box.add_child(_player_card(TeamColors.ui_color(slot),
					pname, card_sub, status, scol,
					String(game.char_for(slot)), alive,
					slot == game.local_slot and not game.observer_mode,
					String(game.slot_frames[slot]) if slot < game.slot_frames.size() else ""))
	else:
		# 15f: the local player is labelled by their resolved
		# display name (15d's source), never the "Bạn" placeholder.
		_players_box.add_child(_label("%s đấu với Máy" % _resolve_player_name(), 12, TXT_DIM))
		var pstatus := "Đã bị loại" if game.sp_player_eliminated else "Đang chơi"
		var palive: bool = game.king_alive(0)
		var psub := "%s · Nhân vật: %s" % [_resolve_player_name(),
				str(Characters.kit_of(game.char_for(0)).get("name", ""))]
		psub += " · đang chiến đấu" if palive else " · chưa xuất trận"
		_players_box.add_child(_player_card(TeamColors.ui_color(0),
				_resolve_player_name(), psub,
				pstatus, Color(1.0, 0.55, 0.45) if game.sp_player_eliminated else GREEN,
				String(game.char_for(0)), palive, true,
				String(Net.auth_profile.get("frame_id", ""))))
		var estatus := "Đã bị loại" if game.sp_enemy_eliminated else "Đang chơi"
		var ealive: bool = game.king_alive(1)
		var esub := "Máy · Nhân vật: %s" % str(Characters.kit_of(game.char_for(1)).get("name", ""))
		esub += " · đang chiến đấu" if ealive else " · chưa xuất trận"
		_players_box.add_child(_player_card(TeamColors.ui_color(1),
				"Máy", esub,
				estatus, Color(1.0, 0.55, 0.45) if game.sp_enemy_eliminated else GREEN,
				String(game.char_for(1)), ealive, false))


func _build_diplomacy_modal() -> void:
	var vb := _make_modal("diplomacy", FA_HANDSHAKE, "Ngoại giao", DIP_SIZE)
	var sc := _modal_scroll()
	vb.add_child(sc)
	_dip_box = _modal_scroll_box(sc, 6)


## One diplomacy row per OTHER player (built once per match;
## _dip_update_row then refreshes it in place so the gift
## controls keep the player's half-typed choices): slot-colour
## band, name + stance pill, a status line (invites /
## declaration countdown), stance action buttons, and the
## tribute row (resource + amount + send).
func _dip_make_row(slot: int) -> PanelContainer:
	var root := _panel(12, BORDER_DIM, Color(0.05, 0.08, 0.15, 0.9), 1)
	var mc := _pad(10, 8, 10, 8)
	root.add_child(mc)
	var vb := _vbox(6)
	mc.add_child(vb)
	var head := _hbox(10)
	vb.add_child(head)
	var band := Panel.new()
	band.custom_minimum_size = Vector2(6, 0)
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = TeamColors.ui_color(slot)
	bsb.set_corner_radius_all(3)
	band.add_theme_stylebox_override("panel", bsb)
	head.add_child(band)
	var pname := "Người chơi %d" % (slot + 1)
	if slot < game.slot_names.size() and String(game.slot_names[slot]) != "":
		pname = String(game.slot_names[slot])
	head.add_child(_label(pname, 14, TXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var pill_box := _hbox(0)
	head.add_child(pill_box)
	var sub := _label("", 12, TXT_DIM)
	sub.clip_text = true
	vb.add_child(sub)
	var act := _hbox(8)
	vb.add_child(act)
	var grow := _hbox(8)
	vb.add_child(grow)
	grow.add_child(_label("Tặng:", 12, TXT_DIM))
	var res := OptionButton.new()
	res.focus_mode = Control.FOCUS_NONE
	for rn in ["food", "gỗ", "vàng", "đá"]:
		res.add_item(rn)
	res.custom_minimum_size = Vector2(84, 30)
	res.add_theme_font_size_override("font_size", 12)
	grow.add_child(res)
	var amt := SpinBox.new()
	amt.min_value = 10.0
	amt.max_value = 100000.0
	amt.step = 10.0
	amt.value = 100.0
	amt.custom_minimum_size = Vector2(92, 30)
	amt.add_theme_font_size_override("font_size", 12)
	grow.add_child(amt)
	var gbtn := _text_button("Tặng")
	grow.add_child(gbtn)
	var gnote := _label("", 11, TXT_DIM)
	grow.add_child(gnote)
	gbtn.pressed.connect(func() -> void:
		var types := ["food", "wood", "gold", "stone"]
		game.diplomacy_local_gift(slot, types[res.selected], int(amt.value)))
	_dip_rows[slot] = {"root": root, "sub": sub, "pill_box": pill_box,
			"act": act, "gift_row": grow, "gbtn": gbtn, "gnote": gnote}
	return root


func _dip_act_btn(act: HBoxContainer, text: String, fn: Callable) -> void:
	var b := _text_button(text)
	b.pressed.connect(fn)
	act.add_child(b)


## Diplomacy modal content. Stances, invites, declaration
## windows and tribute cooldowns all read straight from the sim
## (Main's diplomacy tables) — the panel is a pure view.
func _refresh_diplomacy() -> void:
	if _dip_box == null or game == null:
		return
	if not game.diplomacy_active():
		if _dip_built_key != "off":
			_dip_built_key = "off"
			_dip_rows.clear()
			for ch in _dip_box.get_children():
				_dip_box.remove_child(ch)
				ch.free()
			_dip_box.add_child(_label(
					"Trận này không bật ngoại giao.", 12, TXT_DIM))
		return
	var key := "%d:%d" % [game.slot_count(), game.local_slot]
	if key != _dip_built_key:
		_dip_built_key = key
		_dip_rows.clear()
		for ch in _dip_box.get_children():
			_dip_box.remove_child(ch)
			ch.free()
		_dip_box.add_child(_label(
				"Liên minh · trung lập · tặng tài nguyên — chỉ trong trận này.",
				12, TXT_DIM))
		for slot in range(game.slot_count()):
			if slot != game.local_slot:
				_dip_box.add_child(_dip_make_row(slot))
	for slot in _dip_rows.keys():
		_dip_update_row(int(slot))


func _dip_update_row(slot: int) -> void:
	var row: Dictionary = _dip_rows[slot]
	var me: int = game.local_slot
	var elim: bool = slot < game.slot_eliminated.size() \
			and game.slot_eliminated[slot]
	var stance: int = game.stance_of(me, slot)
	# Stance pill.
	var pill_box: HBoxContainer = row["pill_box"]
	for ch in pill_box.get_children():
		pill_box.remove_child(ch)
		ch.free()
	var ptxt: String = game.dip_stance_text(stance)
	var pcol := Color(1.0, 0.55, 0.45)
	if stance == game.DIP_ALLY:
		pcol = GREEN
	elif stance == game.DIP_NEUTRAL:
		pcol = Color(1.0, 0.85, 0.45)
	if elim:
		ptxt = "Đã bị loại"
		pcol = TXT_DIM
	pill_box.add_child(_status_pill(ptxt, pcol))
	# Status line: declaration countdown beats invite notes.
	var sub := ""
	var br: Dictionary = game.dip_break_on(me, slot)
	var out_inv: int = game.dip_invite_from(me, slot)
	var in_inv: int = game.dip_invite_from(slot, me)
	if not br.is_empty():
		sub = "Cắt đứt có hiệu lực sau %d giây" % int(ceil(float(br["t"])))
	elif out_inv >= 0:
		sub = "Đã gửi đề nghị %s — đang chờ trả lời" \
				% game.dip_stance_text(out_inv)
	elif in_inv >= 0:
		sub = "Đang đề nghị %s với bạn" % game.dip_stance_text(in_inv)
	(row["sub"] as Label).text = sub
	# Action buttons for the pair's current state.
	var act: HBoxContainer = row["act"]
	for ch in act.get_children():
		act.remove_child(ch)
		ch.free()
	if not elim and not game.mp_over:
		if in_inv >= 0:
			_dip_act_btn(act, "Chấp nhận",
					func() -> void: game.diplomacy_local_respond(slot, true))
			_dip_act_btn(act, "Từ chối",
					func() -> void: game.diplomacy_local_respond(slot, false))
		elif out_inv >= 0:
			var wait_b := _text_button("Đang chờ…")
			wait_b.disabled = true
			act.add_child(wait_b)
			_dip_act_btn(act, "Hủy",
					func() -> void: game.diplomacy_local_cancel(slot))
		elif br.is_empty():
			if stance == game.DIP_ENEMY:
				_dip_act_btn(act, "Xin trung lập",
						func() -> void: game.diplomacy_local_propose(
								slot, game.DIP_NEUTRAL))
				_dip_act_btn(act, "Xin liên minh",
						func() -> void: game.diplomacy_local_propose(
								slot, game.DIP_ALLY))
			elif stance == game.DIP_NEUTRAL:
				_dip_act_btn(act, "Xin liên minh",
						func() -> void: game.diplomacy_local_propose(
								slot, game.DIP_ALLY))
				_dip_act_btn(act, "Tuyên chiến",
						func() -> void: game.diplomacy_local_break(slot))
			elif stance == game.DIP_ALLY:
				_dip_act_btn(act, "Hạ xuống trung lập",
						func() -> void: game.diplomacy_local_break(slot))
	# Tribute row: allies and neutrals only.
	var gift_row: HBoxContainer = row["gift_row"]
	gift_row.visible = not elim and stance != game.DIP_ENEMY
	var cd := 0.0
	var cdkey := "%d>%d" % [me, slot]
	if game.dip_gift_cd.has(cdkey):
		cd = float(game.dip_gift_cd[cdkey])
	(row["gbtn"] as Button).disabled = cd > 0.0 or game.mp_over
	(row["gnote"] as Label).text = \
			"Hồi chiêu %d giây" % int(ceil(cd)) if cd > 0.0 else ""


func _build_stats_modal() -> void:
	var vb := _make_modal("stats", FA_CHART, "Thống kê", STATS_SIZE)
	var sc := _modal_scroll()
	vb.add_child(sc)
	_stats_box = _modal_scroll_box(sc, 8)


const STAT_RES: Array = ["food", "wood", "gold", "stone"]
const STAT_RES_FA := {"food": FA_FOOD, "wood": FA_WOOD, "gold": FA_GOLD, "stone": FA_STONE}
const AGE_TXT: Array = ["", "Đời I – Hắc ám", "Đời II – Feudal",
	"Đời III – Lâu đài", "Đời IV – Đế quốc"]
const MIL_KINDS: Array = ["militia", "archer", "spearman", "cavalry", "ram"]


func _owner_wallet(owner: int) -> Dictionary:
	if game.mp_mode:
		return game.wallet_of(owner)
	if owner == 0:
		return game.resources
	if game.enemy_ai != null:
		return game.enemy_ai.res
	return {}


func _owner_counts(owner: int) -> Dictionary:
	var vil := 0
	var mil := 0
	for u in game.units:
		if not is_instance_valid(u) or u.is_dead() or u.owner_id != owner:
			continue
		if u.unit_type == "villager":
			vil += 1
		elif MIL_KINDS.has(u.unit_type):
			mil += 1
	var bld := 0
	for b in game.buildings:
		if b.owner_id == owner and b.complete and not b.destroyed:
			bld += 1
	return {"villagers": vil, "military": mil, "buildings": bld}


## Transparent score: gathered/10 + 20 per soldier + 15 per
## standing building + 40 per researched tech tier + 100 while
## the hero lives. (Kept identical for every player.)
func _owner_score(owner: int) -> int:
	var gathered := 0
	for r in RESOURCE_TYPES:
		gathered += game.gathered_of(owner, r)
	var counts := _owner_counts(owner)
	var tiers := 0
	for tid in Stats.TECHS:
		tiers += game.tech_level(owner, tid)
	var score := gathered / 10 + int(counts.military) * 20 \
			+ int(counts.buildings) * 15 + tiers * 40
	if game.king_alive(owner):
		score += 100
	return score


## Statistics modal content: one card per player. Full detail
## for the local player (and for everyone in SP); MP opponents
## show the summary line only — no stockpiles. The score formula
## stays printed under the cards (it is the same transparent
## formula for everyone — see _owner_score).
func _refresh_stats() -> void:
	if _stats_box == null or game == null:
		return
	for ch in _stats_box.get_children():
		_stats_box.remove_child(ch)
		ch.free()
	var owners: Array = range(game.slot_count()) if game.mp_mode else [0, 1]
	for owner in owners:
		var full: bool = (not game.mp_mode) or owner == game.local_slot
		_stats_box.add_child(_stats_block(owner, full))
	var note := _label("Điểm = đã thu thập ÷ 10 + 20 × quân + 15 × công trình + 40 × cấp công nghệ + 100 nếu nhân vật chính còn sống.", 11, TXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_box.add_child(note)


## One statistics card (13x): header = slot chip · name · age,
## with the SCORE large and gold at the right edge (the number
## the panel exists for). Full cards lay the four resources out
## in fixed right-aligned columns — "Hiện có" / "Đã thu thập" —
## in the same order on every card, so players compare at a
## glance. The local player's card wears the gold frame.
func _stats_block(owner: int, full: bool) -> PanelContainer:
	var is_local: bool = owner == (game.local_slot if game.mp_mode else 0)
	var root := _panel(12, GOLD if is_local else BORDER_DIM,
			Color(0.05, 0.08, 0.15, 0.9), 2 if is_local else 1)
	var mc := _pad(10, 8, 10, 8)
	root.add_child(mc)
	var vb := _vbox(4)
	mc.add_child(vb)
	var pname := "Máy"
	if game.mp_mode:
		pname = "Người chơi %d" % (owner + 1)
		if owner < game.slot_names.size() and String(game.slot_names[owner]) != "":
			pname = String(game.slot_names[owner])
	elif owner == 0:
		pname = _resolve_player_name()
	var head := _hbox(8)
	vb.add_child(head)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(14, 14)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var csb := StyleBoxFlat.new()
	csb.bg_color = TeamColors.ui_color(owner)
	csb.set_corner_radius_all(4)
	chip.add_theme_stylebox_override("panel", csb)
	head.add_child(chip)
	var nm := _label(pname, 14, GOLD_TXT if is_local else TXT)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A clipped Label reports a ~1px minimum width, so the name
	# must EXPAND to take the row's slack itself — with a plain
	# spacer sibling it collapses to a sliver (13x debug).
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	head.add_child(nm)
	var age_lb := _label(AGE_TXT[clampi(game.owner_age(owner), 1, 4)], 11, TXT_DIM)
	age_lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(age_lb)
	var score := _owner_score(owner)
	var sc_lb := _label("%d" % score, 17, GOLD_TXT)
	sc_lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sc_lb)
	var sc_unit := _label("điểm", 11, TXT_DIM)
	sc_unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sc_unit)
	var counts := _owner_counts(owner)
	if not full:
		vb.add_child(_label("Dân số %d/%d · Quân %d" % [
				game.owner_pop_current(owner), game.owner_pop_cap(owner),
				int(counts.military)], 11, TXT_DIM))
		return root
	# Column headers over the two number columns.
	var hdr := _hbox(6)
	vb.add_child(hdr)
	var hlead := Control.new()
	hlead.custom_minimum_size = Vector2(84, 0)
	hlead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(hlead)
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(hsp)
	var hc1 := _label("Hiện có", 10, TXT_DIM)
	hc1.custom_minimum_size = Vector2(96, 0)
	hc1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(hc1)
	var hc2 := _label("Đã thu thập", 10, TXT_DIM)
	hc2.custom_minimum_size = Vector2(120, 0)
	hc2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(hc2)
	var wallet := _owner_wallet(owner)
	for r in STAT_RES:
		var rrow := _hbox(6)
		vb.add_child(rrow)
		rrow.add_child(_fa(int(STAT_RES_FA[r]), 14,
				Color(0.98, 0.83, 0.4) if r == "gold" else TXT))
		var rn := _label(game.res_vn(r).capitalize(), 12)
		rn.custom_minimum_size = Vector2(58, 0)
		rrow.add_child(rn)
		var rsp := Control.new()
		rsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rrow.add_child(rsp)
		var cur := _label("%d" % int(wallet.get(r, 0)), 12)
		cur.custom_minimum_size = Vector2(96, 0)
		cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rrow.add_child(cur)
		var gat := _label("%d" % game.gathered_of(owner, r), 12, TXT_DIM)
		gat.custom_minimum_size = Vector2(120, 0)
		gat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rrow.add_child(gat)
	var hero_txt := "chưa xuất trận"
	if game.king_alive(owner):
		hero_txt = str(Characters.kit_of(game.char_for(owner)).get("name", ""))
	vb.add_child(_label("Dân %d · Quân %d · Dân số %d/%d · Công trình %d · Nhân vật chính: %s" % [
			int(counts.villagers), int(counts.military),
			game.owner_pop_current(owner), game.owner_pop_cap(owner),
			int(counts.buildings), hero_txt], 11, TXT_DIM))
	return root


## ------------------------------------------------------------------
## 13s panels: shared card helpers
## ------------------------------------------------------------------

const UNIT_VN := {"villager": "Dân làng", "militia": "Kiếm sĩ",
	"archer": "Cung thủ", "spearman": "Thương binh", "cavalry": "Kỵ binh",
	"ram": "Xe phá thành", "cart": "Xe hàng", "wagon": "Xe chở quân",
	"king": "Nhân vật chính",
	"fishing_boat": "Thuyền cá", "transport": "Thuyền chở quân",
	"war_ship": "Thuyền chiến"}
const SHIP_KINDS: Array = ["fishing_boat", "transport", "war_ship"]


func _gold_bar(w: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(w, 7)
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## (Re)fill a cost row: one painted resource glyph + amount per entry.
func _fill_cost(box: HBoxContainer, cost: Dictionary) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.free()
	for r in ["food", "wood", "gold", "stone", "iron"]:
		if cost.has(r):
			box.add_child(_pic(r, 13))
			var amt := _label(str(int(cost[r])), 11)
			amt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(amt)


## Cropped first-frame sprite for a unit kind (ships: their hull
## texture), cached. Null for the hero (character art, no sheet).
func _thumb_texture(kind: String) -> Texture2D:
	if _thumb_cache.has(kind):
		return _thumb_cache[kind]
	var tex: Texture2D = null
	if SHIP_KINDS.has(kind):
		var path := "res://assets/%s.png" % kind
		if ResourceLoader.exists(path):
			tex = load(path)
	else:
		var data := Unit.get_sheet(kind, 0)
		var sheet: Texture2D = data.get("tex")
		if sheet != null:
			var cell: Vector2i = data.get("cell", Vector2i(82, 82))
			var at := AtlasTexture.new()
			at.atlas = sheet
			var region := Rect2(0, 0, cell.x, cell.y)
			var img := sheet.get_image()
			if img != null and not img.is_empty():
				var frame_img := img.get_region(Rect2i(0, 0,
						mini(cell.x, img.get_width()), mini(cell.y, img.get_height())))
				var used := frame_img.get_used_rect()
				if used.size.x > 4 and used.size.y > 4:
					region = Rect2(used)
			at.region = region
			tex = at
	_thumb_cache[kind] = tex
	return tex


func _art_box(kind: String, w: int, h: int) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(w, h)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := _thumb_texture(kind)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.custom_minimum_size = Vector2(w - 4, h - 4)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(tr)
	else:
		cc.add_child(_pic("helmet" if kind == "king" else "train", 28))
	return cc


func _building_art_box(btype: String, w: int, h: int) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(w, h)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := Building.tier_texture(btype, 1)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.custom_minimum_size = Vector2(w - 4, h - 4)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(tr)
	else:
		cc.add_child(_pic("build", 26))
	return cc


## ------------------------------------------------------------------
## 13s: Build page — grid of every placeable structure
## ------------------------------------------------------------------

## 13u categories for the build tabs: every placeable building
## belongs to exactly one tab.
const BUILD_TABS: Array = [["eco", "Kinh tế"], ["mil", "Quân sự"],
	["def", "Phòng thủ"], ["sea", "Biển"]]
const BUILD_TAB_OF := {
	"house": "eco", "lumber_camp": "eco", "mining_camp": "eco",
	"storage": "eco", "market": "eco", "farm": "eco", "field": "eco",
	"barracks": "mil", "castle": "mil", "blacksmith": "mil",
	"tower": "def", "wallwood": "def", "gatewood": "def",
	"wallstone": "def", "gatestone": "def",
	"dock": "sea"}


func _build_build_page(mc: Container) -> void:
	var bp := _page("Xây dựng — chọn công trình rồi đặt lên bản đồ")
	var tabs := _hbox(6)
	bp.add_child(tabs)
	for t in BUILD_TABS:
		var tid: String = t[0]
		var chip := _tab_chip(t[1])
		chip.pressed.connect(func() -> void: _set_build_tab(tid))
		tabs.add_child(chip)
		_build_tab_btns[tid] = chip
	var defs := [
		["house", "Nhà", "+5 giới hạn dân số"],
		["barracks", "Trại lính", "Huấn luyện mọi loại quân"],
		["lumber_camp", "Trại gỗ", "Điểm nộp Gỗ"],
		["mining_camp", "Mỏ đá", "Điểm nộp Đá và Vàng"],
		["storage", "Kho", "Điểm nộp mọi tài nguyên"],
		["market", "Chợ", "Mua bán tài nguyên"],
		["blacksmith", "Lò rèn", "Nghiên cứu vũ khí, giáp"],
		["tower", "Tháp canh", "Bắn tên phòng thủ"],
		["dock", "Bến cảng", "Đóng thuyền — xây ở bờ nước"],
		["farm", "Nông trại", "Trồng ruộng quanh trại"],
		["field", "Luống ruộng", "Cạnh Nông trại — gặt ra Food"],
		["castle", "Lâu đài", "Đời III — tạo Nhân vật chính"],
		["wallwood", "Tường gỗ", "1 ô — chặn đường đi"],
		["gatewood", "Cổng gỗ", "1 ô — quân nhà qua được"],
		["wallstone", "Tường đá", "1 ô — cứng gấp đôi gỗ"],
		["gatestone", "Cổng đá", "1 ô — quân nhà qua được"],
	]
	_build_scroll = _hscroll(126)
	var row := _hbox(6)
	_build_scroll.add_child(row)
	for d in defs:
		row.add_child(_make_build_card(d[0], d[1], d[2]))
	bp.add_child(_build_scroll)
	mc.add_child(bp)
	_pages["build"] = bp
	_set_build_tab("eco")


func _set_build_tab(tid: String) -> void:
	_build_tab = tid
	for id in _build_tab_btns:
		_style_tab_chip(_build_tab_btns[id], id == tid)
	for btype in _build_cards:
		var c: Dictionary = _build_cards[btype]
		(c.root as Control).visible = \
				String(BUILD_TAB_OF.get(btype, "eco")) == tid
	if _build_scroll != null:
		_build_scroll.scroll_horizontal = 0


func _make_build_card(btype: String, title: String, sub: String) -> PanelContainer:
	var root := _panel(10, BORDER_DIM, Color(0.05, 0.08, 0.15, 0.9))
	root.custom_minimum_size = Vector2(170, 116)
	var mc := _pad(7, 5, 7, 5)
	root.add_child(mc)
	var vb := _vbox(2)
	mc.add_child(vb)
	var art: Control
	if btype == "field":
		art = _art_box("villager", 52, 38)
	else:
		art = _building_art_box(btype, 52, 38)
	vb.add_child(art)
	var nm := _label(title, 13)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var cost_box := _hbox(4)
	cost_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(cost_box)
	var sb := _label(sub, 10, TXT_DIM)
	sb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sb)
	var reason := _label("", 11, Color(0.96, 0.62, 0.45))
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(reason)
	var click := _click_area(root)
	if btype == "field":
		click.pressed.connect(func() -> void: if game != null: game.enter_field_placement())
	else:
		click.pressed.connect(func() -> void: if game != null: game.enter_placement(btype))
	match btype:
		"house": _house_btn = click
		"barracks": _barracks_btn = click
		"mining_camp": _mining_btn = click
		"tower": _tower_btn = click
		"blacksmith": _blacksmith_btn = click
		"lumber_camp": _lumber_btn = click
		"storage": _storage_btn = click
		"market": _market_btn = click
		"dock": _dock_btn = click
		"farm": _farm_btn = click
		"castle": _castle_btn = click
		"wallwood": _wallwood_btn = click
		"wallstone": _wallstone_btn = click
		"gatewood": _gatewood_btn = click
		"gatestone": _gatestone_btn = click
		"field": _field_btn = click
	_build_cards[btype] = {"root": root, "click": click, "reason": reason,
		"art": art, "cost_box": cost_box, "cost_done": false}
	return root


func _cost_of_build(btype: String) -> Dictionary:
	if btype == "field":
		return {"wood": Stats.FIELD_COST_WOOD}
	return game.get_build_def(btype).get("cost", {})


func _first_lacking(cost: Dictionary) -> String:
	for r in cost:
		if int(game.display_resources().get(r, 0)) < int(cost[r]):
			return game.res_vn(r)
	return "tài nguyên"


func _refresh_build_cards() -> void:
	var owner: int = game.local_slot if game.mp_mode else 0
	for btype in _build_cards:
		var c: Dictionary = _build_cards[btype]
		if not bool(c.cost_done):
			_fill_cost(c.cost_box, _cost_of_build(btype))
			c.cost_done = true
		var blocked := ""
		if btype == "field":
			if game.local_farms().is_empty():
				blocked = "Cần Nông trại"
			elif int(game.display_resources().get("wood", 0)) < Stats.FIELD_COST_WOOD:
				blocked = "Thiếu gỗ"
		else:
			var min_age := 3 if btype == "castle" else 1
			if game.owner_age(owner) < min_age:
				blocked = "Cần Đời III"
			elif not game.can_afford(btype):
				blocked = "Thiếu " + _first_lacking(_cost_of_build(btype))
		(c.click as Button).disabled = blocked != ""
		(c.reason as Label).text = blocked
		(c.art as Control).modulate = Color(1, 1, 1, 0.45) if blocked != "" else Color.WHITE


## ------------------------------------------------------------------
## 13s: Training page — bound to the selected production building
## ------------------------------------------------------------------

func _roster_for(btype: String) -> Array:
	match btype:
		"town_center": return ["villager"]
		"barracks": return ["militia", "archer", "spearman", "cavalry", "ram", "wagon"]
		"dock": return ["fishing_boat", "transport", "war_ship"]
		"castle": return ["king"]
		"market": return ["cart"] # 15g: the Market trains the trade cart
	return []


func _build_train_page(mc: Container) -> void:
	var tp := _page("Huấn luyện")
	# 13u: one tab per production building TYPE; a tab only
	# shows while the player owns a completed building of it
	# (refreshed live), and pressing it binds the page to the
	# first such building — the same binding a selection makes.
	var tabs := _hbox(6)
	tp.add_child(tabs)
	for bt in ["town_center", "barracks", "dock", "castle", "market"]:
		var btype: String = bt
		var chip := _tab_chip(str(Stats.BUILDING_VN.get(bt, bt)))
		chip.visible = false
		chip.pressed.connect(func() -> void:
			var b := _first_producer_of(btype)
			if b != null:
				_bind_producer(b)
				_size_subpanel())
		tabs.add_child(chip)
		_train_tab_btns[bt] = chip
	var head := _panel(10, BORDER_DIM, Color(0.05, 0.08, 0.15, 0.9))
	tp.add_child(head)
	var hmc := _pad(8, 5, 8, 5)
	head.add_child(hmc)
	var hr := _hbox(8)
	hmc.add_child(hr)
	_train_art = TextureRect.new()
	_train_art.custom_minimum_size = Vector2(54, 44)
	_train_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_train_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_train_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_train_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hr.add_child(_train_art)
	var hvb := _vbox(1)
	hvb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(hvb)
	_train_name = _label("Town Center", 14, GOLD_TXT)
	hvb.add_child(_train_name)
	hvb.add_child(_label("Tạo quân tại công trình này — điểm tập kết giữ nguyên", 11, TXT_DIM))
	tp.add_child(_label("Hàng chờ — nhấp một ô để huỷ, hoàn tiền đủ", 11, GOLD_TXT))
	_queue_strip = _hbox(5)
	tp.add_child(_queue_strip)
	_queue_bar = _gold_bar(0)
	_queue_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tp.add_child(_queue_bar)
	_queue_info = _label("", 11, TXT_DIM)
	tp.add_child(_queue_info)
	for bt in ["town_center", "barracks", "dock", "castle", "market"]:
		var sc := _hscroll(100)
		sc.visible = false
		var row := _hbox(6)
		sc.add_child(row)
		tp.add_child(sc)
		_train_boxes[bt] = sc
		_train_cards[bt] = {}
		for kind in _roster_for(bt):
			row.add_child(_make_train_card(bt, kind))
	mc.add_child(tp)
	_pages["train"] = tp


## First own, completed production building of a type (the tab
## press target).
func _first_producer_of(btype: String) -> Building:
	if game == null:
		return null
	for b in game.buildings:
		if b.btype == btype and b.complete and not b.destroyed \
				and _is_own_building(b):
			return b
	return null


## Tab visibility + active state for the training page: a tab
## exists only while a completed building of its type stands.
func _refresh_train_tabs() -> void:
	if game == null:
		return
	for bt in _train_tab_btns:
		var chip: Button = _train_tab_btns[bt]
		chip.visible = _first_producer_of(bt) != null
		_style_tab_chip(chip, _producer != null and _producer.btype == bt)


func _make_train_card(btype: String, kind: String) -> PanelContainer:
	var root := _panel(10, BORDER_DIM, Color(0.05, 0.08, 0.15, 0.9))
	root.custom_minimum_size = Vector2(262, 88)
	var mc := _pad(7, 6, 7, 6)
	root.add_child(mc)
	var hr := _hbox(8)
	mc.add_child(hr)
	var art := _art_box(kind, 48, 52)
	hr.add_child(art)
	var vb := _vbox(2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(vb)
	var top := _hbox(6)
	vb.add_child(top)
	top.add_child(_label(str(UNIT_VN.get(kind, kind)), 13))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var time_lb := _label("", 11, TXT_DIM)
	top.add_child(time_lb)
	var cost_box := _hbox(4)
	vb.add_child(cost_box)
	var reason := _label("", 11, Color(0.96, 0.62, 0.45))
	vb.add_child(reason)
	var click := _click_area(root)
	click.pressed.connect(func() -> void:
		if game != null and _producer != null:
			game.train_at(_producer, kind))
	match kind:
		"villager": _train_btn = click
		"militia": _militia_btn = click
		"archer": _archer_btn = click
		"spearman": _spearman_btn = click
		"cavalry": _cavalry_btn = click
		"ram": _ram_btn = click
		"king": _king_btn = click
	_train_cards[btype][kind] = {"root": root, "click": click,
		"reason": reason, "art": art, "cost_box": cost_box,
		"time": time_lb, "cost_done": false}
	return root


func _is_own_building(b: Building) -> bool:
	if game.mp_mode:
		return b.owner_id == game.local_slot
	return b.team == 0


func _default_producer() -> Building:
	if game.mp_mode:
		var tc = game.tc_of(game.local_slot)
		if tc != null:
			return tc
	elif game.player_tc != null:
		return game.player_tc
	for b in game.buildings:
		if b.complete and not b.destroyed and _train_boxes.has(b.btype) \
				and _is_own_building(b):
			return b
	return null


func _bind_producer(b: Building) -> void:
	_producer = b
	_queue_sig = ""
	for bt in _train_boxes:
		(_train_boxes[bt] as Control).visible = b != null and b.btype == bt
	if b == null:
		_train_name.text = "Chưa có công trình tạo quân"
		_train_art.texture = null
		return
	_train_name.text = str(Stats.BUILDING_VN.get(b.btype, b.btype))
	_train_art.texture = Building.tier_texture(b.btype,
			clampi(game.owner_age(b.owner_id), 1, 4))
	if open_tab == "train":
		_size_subpanel()


func _refresh_queue_strip() -> void:
	var sig := ""
	if _producer != null and is_instance_valid(_producer):
		sig = str(_producer.get_instance_id()) + "|" + ",".join(_producer.train_types)
	if sig == _queue_sig:
		return
	_queue_sig = sig
	for ch in _queue_strip.get_children():
		_queue_strip.remove_child(ch)
		ch.free()
	if _producer == null or not is_instance_valid(_producer):
		return
	var types := _producer.train_types
	var shown := mini(types.size(), 8)
	for i in range(shown):
		var idx := i
		var pb: Building = _producer
		var slot := _panel(8, GOLD if i == 0 else BORDER_DIM,
				Color(0.05, 0.08, 0.15, 0.9))
		slot.custom_minimum_size = Vector2(44, 44)
		var tex := _thumb_texture(types[i])
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(tr)
		var btn := _click_area(slot)
		btn.pressed.connect(func() -> void:
			if game != null:
				game.cancel_train_at(pb, idx))
		_queue_strip.add_child(slot)
	if types.size() > shown:
		var more := _label("+%d" % (types.size() - shown), 13, GOLD_TXT)
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_queue_strip.add_child(more)


func _refresh_train_page() -> void:
	_refresh_train_tabs()
	if _producer == null or not is_instance_valid(_producer):
		_queue_info.text = ""
		_queue_bar.visible = false
		return
	_refresh_queue_strip()
	_queue_bar.visible = _producer.train_queue > 0
	_queue_bar.value = _producer.training_fraction() * 100.0
	if _producer.train_queue > 0:
		_queue_info.text = "Đang tạo: %s · %d%% · còn %d trong hàng" % [
				str(UNIT_VN.get(_producer.train_types[0], _producer.train_types[0])),
				int(_producer.training_fraction() * 100.0),
				_producer.train_queue - 1]
	else:
		_queue_info.text = "Hàng chờ trống"
	var bt := _producer.btype
	if not _train_cards.has(bt):
		return
	for kind in _train_cards[bt]:
		var c: Dictionary = _train_cards[bt][kind]
		if not bool(c.cost_done):
			_fill_cost(c.cost_box, game.unit_cost(kind))
			(c.time as Label).text = "%d giây" % int(round(
					game.train_time_for(_producer.owner_id, kind)))
			c.cost_done = true
		var st: Dictionary = game.train_state(_producer, kind)
		var can := bool(st.get("can", false))
		(c.click as Button).disabled = not can
		(c.reason as Label).text = str(st.get("reason", ""))
		(c.art as Control).modulate = Color.WHITE if can else Color(1, 1, 1, 0.45)


## ------------------------------------------------------------------
## 13s: Technology page — AoE II tree, one section per building
## ------------------------------------------------------------------

## 13u: the technology page is a TREE — one group per research
## building (vertical scroll), each tech line a horizontal
## chain of tier nodes joined by connector segments, and one
## shared detail strip under the tree for the tapped node.
func _build_tech_page(mc: Container) -> void:
	var root := _vbox(6)
	root.add_child(_label("Công nghệ — nghiên cứu tại từng công trình", 13, GOLD_TXT))
	var tree := _vbox(10)
	for btype in Stats.TECH_BUILDINGS:
		var head := _hbox(6)
		tree.add_child(head)
		head.add_child(_building_art_box(btype, 36, 30))
		var hl := _label(str(Stats.BUILDING_VN.get(btype, btype)), 13, GOLD_TXT)
		hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hl)
		if btype == "town_center":
			_build_age_cards(tree)
		for tid in Stats.tech_ids_for(btype):
			var chain := _hbox(0)
			tree.add_child(chain)
			var tiers: Array = Stats.tech_def(tid).get("tiers", [])
			for i in range(tiers.size()):
				if i > 0:
					chain.add_child(_chain_link())
				chain.add_child(_make_tech_node(tid, i))
			_tech_cards[tid] = {"line": tid}
	var csc := ScrollContainer.new()
	csc.custom_minimum_size = Vector2(0, 252)
	csc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	csc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	csc.add_child(tree)
	root.add_child(csc)
	_build_tech_detail(root)
	mc.add_child(root)
	_pages["tech"] = root
	# Default selection: the first line's next tier.
	for btype in Stats.TECH_BUILDINGS:
		var ids: Array = Stats.tech_ids_for(btype)
		if not ids.is_empty():
			_tech_sel_tid = String(ids[0])
			_tech_sel_tier = 0
			break


## Gold connector segment between two tree nodes.
func _chain_link() -> Panel:
	var link := Panel.new()
	link.custom_minimum_size = Vector2(14, 4)
	link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	link.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD_DIM
	sb.set_corner_radius_all(2)
	link.add_theme_stylebox_override("panel", sb)
	return link


func _make_tech_node(tid: String, idx: int) -> PanelContainer:
	var root := _panel(9, BORDER_DIM, Color(0.05, 0.08, 0.15, 0.9))
	root.custom_minimum_size = Vector2(142, 94)
	var mc := _pad(7, 5, 7, 5)
	root.add_child(mc)
	var vb := _vbox(2)
	mc.add_child(vb)
	var tier: Dictionary = (Stats.tech_def(tid).get("tiers", []) as Array)[idx]
	var nm := _label(str(tier.get("name", tid)), 11)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(126, 32)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var st := _label("", 10, TXT_DIM)
	vb.add_child(st)
	var bar := _gold_bar(126)
	bar.visible = false
	vb.add_child(bar)
	var click := _click_area(root)
	click.pressed.connect(func() -> void: _select_tech_node(tid, idx))
	if not _tech_nodes.has(tid):
		_tech_nodes[tid] = []
	(_tech_nodes[tid] as Array).append({"root": root, "state": st,
		"bar": bar, "key": ""})
	return root


func _select_tech_node(tid: String, idx: int) -> void:
	_tech_sel_tid = tid
	_tech_sel_tier = idx
	_refresh_tech_cards()


## The detail strip under the tree: full data of the tapped
## node (name, description, 4-resource cost, time, gate) with
## the Nghiên cứu action when the node is the line's next tier.
func _build_tech_detail(parent: Container) -> void:
	var panel := _panel(10, GOLD_DIM, Color(0.05, 0.08, 0.15, 0.92))
	parent.add_child(panel)
	var mc := _pad(9, 6, 9, 6)
	panel.add_child(mc)
	var vb := _vbox(3)
	mc.add_child(vb)
	var title := _label("", 13, GOLD_TXT)
	vb.add_child(title)
	var meta := _label("", 11, TXT_DIM)
	vb.add_child(meta)
	var fx := _label("", 11, TXT)
	fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(fx)
	var row := _hbox(8)
	vb.add_child(row)
	var cost_box := _hbox(4)
	row.add_child(cost_box)
	var time_lb := _label("", 11, TXT_DIM)
	time_lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(time_lb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var btn := _text_button("Nghiên cứu")
	btn.custom_minimum_size = Vector2(118, 30)
	btn.pressed.connect(func() -> void:
		if game != null and _tech_sel_tid != "":
			game.start_research(_tech_sel_tid))
	row.add_child(btn)
	var reason := _label("", 11, Color(0.96, 0.62, 0.45))
	vb.add_child(reason)
	var bar := _gold_bar(0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.visible = false
	vb.add_child(bar)
	_tech_detail = {"title": title, "meta": meta, "fx": fx,
		"cost_box": cost_box, "time": time_lb, "btn": btn,
		"reason": reason, "bar": bar}


## Per-node state for the tree (GDD §10's four states), derived
## from Main.tech_panel_info: {code, text, frac}.
func _tech_node_state(tid: String, idx: int, info: Dictionary) -> Dictionary:
	var lvl := int(info.get("level", 0))
	if idx < lvl:
		return {"code": "done", "text": "Đã xong", "frac": -1.0}
	if idx == lvl:
		var frac := float(info.get("active_frac", -1.0))
		if frac >= 0.0:
			return {"code": "researching", "text": "Đang nghiên cứu", "frac": frac}
		if bool(info.get("can", false)):
			return {"code": "available", "text": "Có thể nghiên cứu", "frac": -1.0}
		return {"code": "locked", "text": str(info.get("reason", "Bị khoá")), "frac": -1.0}
	var tiers: Array = Stats.tech_def(tid).get("tiers", [])
	var need_age := int((tiers[idx] as Dictionary).get("age", 1))
	var owner: int = game.local_slot if game.mp_mode else 0
	var why := "Cần cấp trước"
	if game.owner_age(owner) < need_age:
		why = "Cần Đời %s" % ["", "I", "II", "III", "IV"][need_age]
	return {"code": "locked", "text": why, "frac": -1.0}


func _refresh_tech_cards() -> void:
	if game == null:
		return
	for tid in _tech_nodes:
		var info: Dictionary = game.tech_panel_info(tid)
		var nodes: Array = _tech_nodes[tid]
		for idx in range(nodes.size()):
			var nd: Dictionary = nodes[idx]
			var st := _tech_node_state(tid, idx, info)
			var sel: bool = tid == _tech_sel_tid and idx == _tech_sel_tier
			var key := "%s|%s|%d" % [String(st.code), str(sel),
					int(float(st.frac) * 24.0)]
			var root := nd.root as PanelContainer
			var state_lb := nd.state as Label
			var bar := nd.bar as ProgressBar
			if float(st.frac) >= 0.0:
				bar.visible = true
				bar.value = float(st.frac) * 100.0
			else:
				bar.visible = false
			if key == String(nd.key):
				continue
			nd.key = key
			match String(st.code):
				"done":
					root.add_theme_stylebox_override("panel", _sb(
							Color(0.45, 0.8, 0.45), Color(0.07, 0.13, 0.1, 0.92), 9, 2 if sel else 1))
					state_lb.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
				"researching":
					root.add_theme_stylebox_override("panel", _sb(
							GOLD, Color(0.12, 0.1, 0.05, 0.92), 9, 2 if sel else 1))
					state_lb.add_theme_color_override("font_color", GOLD_TXT)
				"available":
					root.add_theme_stylebox_override("panel", _sb(
							GOLD, Color(0.05, 0.08, 0.15, 0.92), 9, 2 if sel else 1))
					state_lb.add_theme_color_override("font_color", GOLD_TXT)
				_:
					root.add_theme_stylebox_override("panel", _sb(
							GOLD if sel else BORDER_DIM, Color(0.04, 0.05, 0.09, 0.9), 9, 2 if sel else 1))
					state_lb.add_theme_color_override("font_color", TXT_DIM)
			state_lb.text = String(st.text)
	_refresh_tech_detail()


## Detail strip sync for the selected node (see _build_tech_detail).
func _refresh_tech_detail() -> void:
	if _tech_detail.is_empty() or _tech_sel_tid == "" or game == null:
		return
	var tid := _tech_sel_tid
	var def := Stats.tech_def(tid)
	var tiers: Array = def.get("tiers", [])
	if tiers.is_empty():
		return
	var idx := clampi(_tech_sel_tier, 0, tiers.size() - 1)
	var tier: Dictionary = tiers[idx]
	var info: Dictionary = game.tech_panel_info(tid)
	var st := _tech_node_state(tid, idx, info)
	(_tech_detail.title as Label).text = str(tier.get("name", tid))
	var gvn := str(Stats.TECH_GROUP_VN.get(str(def.get("group", "")), ""))
	var bvn := str(Stats.BUILDING_VN.get(str(def.get("building", "")), ""))
	(_tech_detail.meta as Label).text = "%s · %s · Cấp %d/%d · Đời %s" % [
			gvn, bvn, idx + 1, tiers.size(),
			["", "I", "II", "III", "IV"][int(tier.get("age", 1))]]
	(_tech_detail.fx as Label).text = str(tier.get("fx", ""))
	var csig := tid + "|" + str(idx) + "|" + str(tier.get("cost", {}))
	if csig != String(_tech_detail.get("cost_sig", "")):
		_tech_detail["cost_sig"] = csig
		_fill_cost(_tech_detail.cost_box, tier.get("cost", {}))
	(_tech_detail.time as Label).text = "%d giây" % int(tier.get("time", 0))
	var btn := _tech_detail.btn as Button
	var bar := _tech_detail.bar as ProgressBar
	match String(st.code):
		"done":
			btn.disabled = true
			btn.text = "Đã hoàn thành"
			bar.visible = false
			(_tech_detail.reason as Label).text = ""
		"researching":
			btn.disabled = true
			btn.text = "Đang nghiên cứu"
			bar.visible = true
			bar.value = float(st.frac) * 100.0
			(_tech_detail.reason as Label).text = ""
		"available":
			btn.disabled = false
			btn.text = "Nghiên cứu"
			bar.visible = false
			(_tech_detail.reason as Label).text = ""
		_:
			btn.disabled = true
			btn.text = "Chưa mở khoá"
			bar.visible = false
			(_tech_detail.reason as Label).text = String(st.text)


## Age advancement cards (presented at the Town Center section of
## the Công nghệ page; the research itself lives in Main).
func _build_age_cards(cp: VBoxContainer) -> void:
	var age := _card("tech", "Thời đại II – Feudal",
			"500 Food · 60 giây · cần 2 công trình (ngoài Town Center)\nTháp canh bắn mạnh hơn ở đời II", "Nghiên cứu")
	_age_btn = age.btn
	_age_btn.pressed.connect(func() -> void: ui_age_up())
	cp.add_child(age.row)
	_age_status = _label("", 11, TXT_DIM)
	cp.add_child(_age_status)
	_age_bar = ProgressBar.new()
	_age_bar.custom_minimum_size = Vector2(200, 8)
	_age_bar.max_value = 100.0
	_age_bar.show_percentage = false
	_age_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var abg := StyleBoxFlat.new()
	abg.bg_color = Color(0, 0, 0, 0.5)
	abg.set_corner_radius_all(4)
	var afill := StyleBoxFlat.new()
	afill.bg_color = Color(0.85, 0.64, 0.25)
	afill.set_corner_radius_all(4)
	_age_bar.add_theme_stylebox_override("background", abg)
	_age_bar.add_theme_stylebox_override("fill", afill)
	_age_bar.visible = false
	cp.add_child(_age_bar)
	var age3 := _card("tech", "Thời đại III – Castle Age",
			"800 Food · 200 Gold · 90 giây · cần Trại lính + Lò rèn hoặc Chợ\nMở Lâu đài (Castle) + Xe phá thành (Ram)", "Nghiên cứu")
	_age3_btn = age3.btn
	_age3_btn.pressed.connect(func() -> void: ui_age_up3())
	cp.add_child(age3.row)
	_age3_status = _label("", 11, TXT_DIM)
	cp.add_child(_age3_status)
	_age3_bar = ProgressBar.new()
	_age3_bar.custom_minimum_size = Vector2(200, 8)
	_age3_bar.max_value = 100.0
	_age3_bar.show_percentage = false
	_age3_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_age3_bar.add_theme_stylebox_override("background", abg)
	_age3_bar.add_theme_stylebox_override("fill", afill)
	_age3_bar.visible = false
	cp.add_child(_age3_bar)
	var age4 := _card("tech", "Thời đại IV – Imperial (Đế quốc)",
			"1000 Food · 350 Gold · 120 giây · cần Lâu đài + Lò rèn hoặc Chợ\nTháp canh + Lâu đài bắn mạnh hơn · Xe phá thành mạnh hơn · Huấn luyện nhanh hơn 20%", "Nghiên cứu")
	_age4_btn = age4.btn
	_age4_btn.pressed.connect(func() -> void: ui_age_up4())
	cp.add_child(age4.row)
	_age4_status = _label("", 11, TXT_DIM)
	cp.add_child(_age4_status)
	_age4_bar = ProgressBar.new()
	_age4_bar.custom_minimum_size = Vector2(200, 8)
	_age4_bar.max_value = 100.0
	_age4_bar.show_percentage = false
	_age4_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_age4_bar.add_theme_stylebox_override("background", abg)
	_age4_bar.add_theme_stylebox_override("fill", afill)
	_age4_bar.visible = false
	cp.add_child(_age4_bar)


## ------------------------------------------------------------------
## 13s: per-frame panel sync (called from _process)
## ------------------------------------------------------------------

var _sel_seen: Building = null


func _refresh_panels() -> void:
	# The training page follows the selection: a NEW selection of
	# an own, completed production building binds the page to it
	# and opens it (one panel area, replacing any other tab).
	var selb = game.selected_building
	if selb != _sel_seen:
		_sel_seen = selb
		if selb != null and selb.complete and not selb.destroyed \
				and _train_boxes.has(selb.btype) and _is_own_building(selb):
			if _producer != selb:
				_bind_producer(selb)
			if open_tab != "train":
				_open_tab("train")
	if _producer == null or not is_instance_valid(_producer) or _producer.destroyed:
		_bind_producer(_default_producer())
	if open_tab == "build":
		_refresh_build_cards()
	elif open_tab == "train":
		_refresh_train_page()
	elif open_tab == "tech":
		_refresh_tech_cards()
	elif open_tab == "players":
		if Time.get_ticks_msec() - _players_refresh_msec > 400:
			_players_refresh_msec = Time.get_ticks_msec()
			_refresh_players()
	elif open_tab == "diplomacy":
		if Time.get_ticks_msec() - _dip_refresh_msec > 400:
			_dip_refresh_msec = Time.get_ticks_msec()
			_refresh_diplomacy()
	elif open_tab == "stats":
		if Time.get_ticks_msec() - _stats_refresh_msec > 250:
			_stats_refresh_msec = Time.get_ticks_msec()
			_refresh_stats()
	# 15b per-frame diplomacy upkeep (independent of the open tab).
	# 15e-ter: never for an observer — a diplomacy MATCH can be
	# active under a watcher who holds no seat in it.
	if _dip_top_btn != null:
		_dip_top_btn.visible = game != null and game.diplomacy_active() \
				and not _is_observer()
	if game != null and game.diplomacy_active() and is_chat_open():
		# Alliances move while the chat is open; the Đội tab
		# follows them without waiting for a reopen.
		if Time.get_ticks_msec() - _dip_refresh_msec > 400:
			_refresh_chat_channels()


func _size_subpanel() -> void:
	if open_tab == "" or not _pages.has(open_tab):
		return
	var need: float = _pages[open_tab].get_combined_minimum_size().y + 18.0
	var h: float = clampf(need, 178.0, 470.0)
	_subpanel.offset_top = -84.0 - h
	_subpanel.offset_bottom = -84.0



func _build_selection_chip() -> void:
	var chip := _panel(10, BORDER, GLASS_BG)
	chip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	chip.offset_left = -175
	chip.offset_right = 175
	chip.offset_top = -40
	chip.offset_bottom = -8
	_sel_chip = chip
	add_child(chip)
	var mc := _pad(10, 4, 10, 4)
	chip.add_child(mc)
	var vb := _vbox(4)
	mc.add_child(vb)
	_sel_label = _label("", 12)
	_sel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_sel_label)
	# Market exchange rows (visible only while a completed Market is
	# selected): sell 100 of a resource for gold / buy 100 back.
	_market_box = _vbox(4)
	_market_box.visible = false
	vb.add_child(_market_box)
	var srow := _hbox(6)
	_market_box.add_child(srow)
	var brow := _hbox(6)
	_market_box.add_child(brow)
	for t in ["food", "wood", "stone"]:
		var rt: String = t
		var sb := _text_button("Bán 100 " + rt.capitalize())
		sb.add_theme_font_size_override("font_size", 11)
		sb.custom_minimum_size = Vector2(104, 30)
		sb.pressed.connect(func() -> void: _market_trade(true, rt))
		srow.add_child(sb)
		_mkt_sell_btns[rt] = sb
		var bb := _text_button("Mua 100 " + rt.capitalize())
		bb.add_theme_font_size_override("font_size", 11)
		bb.custom_minimum_size = Vector2(104, 30)
		bb.pressed.connect(func() -> void: _market_trade(false, rt))
		brow.add_child(bb)
		_mkt_buy_btns[rt] = bb
	# Dock shipyard row (visible only while a completed own Dock is
	# selected): one train button per hull, costs on the label.
	_ship_box = _vbox(4)
	_ship_box.visible = false
	vb.add_child(_ship_box)
	var ship_row := _hbox(6)
	_ship_box.add_child(ship_row)
	var ship_defs := [["fishing_boat", "Thuyền cá · 75 Gỗ"],
			["transport", "Thuyền chở · 125 Gỗ"],
			["war_ship", "Thuyền chiến · 150 Gỗ + 50 Vàng"]]
	for sd in ship_defs:
		var kind: String = sd[0]
		var btn := _text_button(sd[1])
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(104, 30)
		btn.pressed.connect(func() -> void: if game != null: game.train_ship(kind))
		ship_row.add_child(btn)
		_ship_btns[kind] = btn
	# 15g wagon row (visible only while exactly one own loaded
	# Wagon is selected): unload everyone where the wagon stands.
	_wagon_box = _vbox(4)
	_wagon_box.visible = false
	vb.add_child(_wagon_box)
	var wagon_row := _hbox(6)
	_wagon_box.add_child(wagon_row)
	_wagon_btn = _text_button("Dỡ quân tại chỗ")
	_wagon_btn.add_theme_font_size_override("font_size", 11)
	_wagon_btn.custom_minimum_size = Vector2(130, 30)
	_wagon_btn.pressed.connect(func() -> void:
		if game != null:
			game.issue_selected_wagon_unload())
	wagon_row.add_child(_wagon_btn)


## One Market exchange button press: run the trade on Main, then a
## small gold glint over the selected Market.
func _market_trade(sell: bool, rtype: String) -> void:
	if game == null or game.selected_building == null:
		return
	var ok: bool = game.market_sell(rtype) if sell else game.market_buy(rtype)
	if ok and game.vfx != null:
		var b = game.selected_building
		var top: Vector2 = b.position + Vector2(b.size) * World.TILE * Vector2(0.5, 0.0)
		game.vfx.glint(top + Vector2(0, -10), Color(1.0, 0.85, 0.35, 0.95), 12.0, 0.5)


# ------------------------------------------------------------------ public API

func show_message(text: String) -> void:
	_msg_label.text = text
	_msg_timer = 3.0


## Same call the Huấn luyện sub-panel button makes (tests drive this path).
func ui_train_villager() -> bool:
	if game == null:
		return false
	return game.train_villager()


func ui_train_militia() -> bool:
	if game == null:
		return false
	return game.train_militia()


func ui_train_archer() -> bool:
	if game == null:
		return false
	return game.train_archer()


func ui_train_spearman() -> bool:
	if game == null:
		return false
	return game.train_spearman()


func ui_train_cavalry() -> bool:
	if game == null:
		return false
	return game.train_cavalry()


func ui_train_ram() -> bool:
	if game == null:
		return false
	return game.train_ram()


func ui_train_king() -> bool:
	if game == null:
		return false
	return game.train_king()


## Same call the Công nghệ page Age-III button makes.
func ui_age_up3() -> bool:
	if game == null:
		return false
	return game.start_age_up3()


## Same call the Công nghệ page Age-IV button makes.
func ui_age_up4() -> bool:
	if game == null:
		return false
	return game.start_age_up4()


func toggle_tab(tab: String) -> void:
	if open_tab == tab:
		_close_panel()
	else:
		_open_tab(tab)


## Force a tab open (selection of a production building routes
## here so its training page appears without a second click).
func _open_tab(tab: String) -> void:
	# 15e-ter: for an observer the only openable tab is their
	# own settings; every gameplay tab (action pages AND the
	# players / stats / diplomacy modals) refuses here, at the
	# single funnel — this also disarms the selection-driven
	# auto-open of the training page in _refresh_panels.
	if _is_observer() and tab != "settings":
		return
	open_tab = tab
	_players_refresh_msec = 0
	_stats_refresh_msec = 0
	if MODAL_TABS.has(tab):
		# 13x: Players / Statistics / Settings open as CENTRED
		# modals over a dim backdrop instead of subpanel pages.
		# (Not draggable — they stay centred; only chat drags.)
		_subpanel.visible = false
		for k in _pages:
			_pages[k].visible = false
		_show_modal(tab)
		if tab == "players":
			_refresh_players()
		elif tab == "stats":
			_refresh_stats()
		elif tab == "diplomacy":
			_refresh_diplomacy()
		_refresh_tab_highlights()
		return
	_show_modal("")
	for k in _pages:
		_pages[k].visible = (k == tab)
	# Size the panel to its page (bottom edge pinned above the action
	# bar) so tall pages grow upward instead of overlapping the buttons.
	var need: float = _pages[tab].get_combined_minimum_size().y + 18.0
	var h: float = clampf(need, 178.0, 470.0) # cap: grid/scroll pages scroll
	_subpanel.offset_top = -84.0 - h
	_subpanel.offset_bottom = -84.0
	_subpanel.visible = true
	_refresh_tab_highlights()


func _close_panel() -> void:
	open_tab = ""
	_subpanel.visible = false
	_show_modal("")
	_refresh_tab_highlights()


## Đầu hàng (Khác page): two-step confirm — the first press arms
## the button for 4 s, the second actually surrenders.
## Both surrender buttons (Khác page + Settings page) share the
## armed state, so their labels must move together.
func _set_surrender_text(t: String) -> void:
	if _surrender_btn != null:
		_surrender_btn.text = t
	if _set_surrender_btn != null:
		_set_surrender_btn.text = t


func _on_surrender_pressed() -> void:
	if game == null:
		return
	if _surrender_arm > 0.0:
		_surrender_arm = 0.0
		_set_surrender_text("Đầu hàng")
		game.surrender()
	else:
		_surrender_arm = 4.0
		_set_surrender_text("Chắc chắn đầu hàng? Nhấn lần nữa")


## Esc handling in Main asks this first: an open action panel
## (or the chat panel) closes before the selection is cleared.
func close_panel_if_open() -> bool:
	# 15e-bis: an open spectator panel closes first (observer
	# branch only — players never have a spectator controller).
	if game != null and game.observer_mode and game.spectator != null \
			and game.spectator.close_panel_if_open():
		return true
	if _chat_panel != null and _chat_panel.visible:
		_set_chat_open(false)
		return true
	if open_tab == "":
		return false
	_close_panel()
	return true


func _refresh_tab_highlights() -> void:
	for t in _action_panels:
		var p: PanelContainer = _action_panels[t]
		if t == open_tab:
			p.add_theme_stylebox_override("panel", _sb(GOLD, Color(0.1, 0.13, 0.2, 0.85), 12, 2))
		else:
			p.add_theme_stylebox_override("panel", _sb(GOLD_DIM, GLASS_BG, 12, 1))


# ------------------------------------------------------------------ per-frame sync

func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg_label.text = ""
	refresh_age_badge()
	if game == null:
		return

	# Top bar: amounts + real trailing-60 s gather rates.
	for t in RESOURCE_TYPES:
		var chip: Dictionary = res_chips[t]
		chip.amt.text = str(int(game.display_resources().get(t, 0)))
		var r: float = game.gather_rate(t)
		chip.rate.text = "+%d/s" % int(round(r))
		chip.rate.add_theme_color_override("font_color", GREEN if r > 0.0 else TXT_DIM)
	_pop_label.text = "%d/%d" % [game.pop_current(), game.pop_cap()]
	var mt := int(game.match_time)
	_timer_label.text = "%02d:%02d" % [mt / 60, mt % 60]

	# Rally flag button highlight.
	if game.rally_setting != _flag_active:
		_flag_active = game.rally_setting
		if _flag_active:
			_flag_panel.add_theme_stylebox_override("panel", _sb(GOLD, Color(0.12, 0.14, 0.2, 0.9), 10, 2))
		else:
			_flag_panel.add_theme_stylebox_override("panel", _sb(BORDER, GLASS_BG, 10, 1))

	# Sub-panel live states (13s: build grid / training / tech).
	_refresh_skill_button()
	_update_skill_hold() # 15c: press-and-hold threshold on skill buttons
	_refresh_player_chip()
	if _surrender_arm > 0.0:
		_surrender_arm -= delta
		if _surrender_arm <= 0.0:
			_set_surrender_text("Đầu hàng")
	_refresh_panels()
	_pause_btn.text = "Tiếp tục" if game.paused else "Tạm dừng"

	# Age name next to the badge follows Main.age.
	if _age_name_label != null and game.age != _age_name_shown:
		_age_name_shown = game.age
		var names := {1: "Thời đại\nHắc ám", 2: "Thời đại\nFeudal", 3: "Thời đại\nLâu đài", 4: "Thời đại\nĐế quốc"}
		_age_name_label.text = names.get(game.age, "Thời đại\nHắc ám")

	# Feudal research card: live states.
	if _age_btn != null:
		if game.age >= 2:
			_age_btn.disabled = true
			_age_btn.text = "Đã lên đời"
			_age_status.text = "Đang ở Thời đại II — Feudal"
			_age_bar.visible = false
		elif game.age_researching:
			_age_btn.disabled = true
			_age_btn.text = "Đang nghiên cứu"
			_age_status.text = "Nghiên cứu Feudal: %d%%" % int(game.age_fraction() * 100.0)
			_age_bar.visible = true
			_age_bar.value = game.age_fraction() * 100.0
		else:
			_age_btn.disabled = not game.can_age_up()
			_age_btn.text = "Nghiên cứu"
			var have: int = game.completed_non_tc_buildings(0)
			if have < Stats.AGE_UP_MIN_BUILDINGS:
				_age_status.text = "Cần %d công trình (hiện có %d) + %d Food" % [Stats.AGE_UP_MIN_BUILDINGS, have, int(Stats.AGE_UP_COST.food)]
			else:
				_age_status.text = "Đủ điều kiện: %d Food (hiện có %d)" % [int(Stats.AGE_UP_COST.food), int(game.display_resources().get("food", 0))]
			_age_bar.visible = false

	# Castle Age research card: live states.
	if _age3_btn != null:
		if game.age >= 3:
			_age3_btn.disabled = true
			_age3_btn.text = "Đã lên đời"
			_age3_status.text = "Đang ở Thời đại III — Castle Age"
			_age3_bar.visible = false
		elif game.age_researching and game.age_target == 3:
			_age3_btn.disabled = true
			_age3_btn.text = "Đang nghiên cứu"
			_age3_status.text = "Nghiên cứu Castle Age: %d%%" % int(game.age_fraction() * 100.0)
			_age3_bar.visible = true
			_age3_bar.value = game.age_fraction() * 100.0
		elif game.age < 2:
			_age3_btn.disabled = true
			_age3_btn.text = "Nghiên cứu"
			_age3_status.text = "Cần lên Thời đại II — Feudal trước"
			_age3_bar.visible = false
		else:
			_age3_btn.disabled = not game.can_age_up3()
			_age3_btn.text = "Nghiên cứu"
			_age3_status.text = "Cần Trại lính + (Lò rèn/Chợ), %d Food + %d Gold" % [int(Stats.AGE3_UP_COST.food), int(Stats.AGE3_UP_COST.gold)]
			_age3_bar.visible = false

	# Imperial research card: live states.
	if _age4_btn != null:
		if game.age >= 4:
			_age4_btn.disabled = true
			_age4_btn.text = "Đã lên đời"
			_age4_status.text = "Đang ở Thời đại IV — Imperial"
			_age4_bar.visible = false
		elif game.age_researching and game.age_target == 4:
			_age4_btn.disabled = true
			_age4_btn.text = "Đang nghiên cứu"
			_age4_status.text = "Nghiên cứu Imperial: %d%%" % int(game.age_fraction() * 100.0)
			_age4_bar.visible = true
			_age4_bar.value = game.age_fraction() * 100.0
		elif game.age < 3:
			_age4_btn.disabled = true
			_age4_btn.text = "Nghiên cứu"
			_age4_status.text = "Cần lên Thời đại III — Castle Age trước"
			_age4_bar.visible = false
		else:
			_age4_btn.disabled = not game.can_age_up4()
			_age4_btn.text = "Nghiên cứu"
			_age4_status.text = "Cần Lâu đài + (Lò rèn/Chợ), %d Food + %d Gold" % [int(Stats.AGE4_UP_COST.food), int(Stats.AGE4_UP_COST.gold)]
			_age4_bar.visible = false

	# TC-down warning state (annihilation rules): persistent while
	# the player's Town Center is gone but they fight on.
	# 15e-ter: it reports the WATCHED slot's state to an observer
	# as if it were theirs — never shown while spectating.
	if _tc_warn_label != null:
		_tc_warn_label.visible = game.own_tc_down_fighting_on() \
				and not _is_observer()

	# Market exchange box: only while a completed Market is selected;
	# the selection chip grows upward to fit the two button rows.
	var sel_b = game.selected_building
	var show_mkt: bool = sel_b != null and sel_b.btype == "market" and sel_b.complete
	var show_ship: bool = sel_b != null and sel_b.btype == "dock" and sel_b.complete and sel_b.team == 0
	# 15g: the unload row rides the chip while one own Wagon
	# (loaded or not — the label explains the empty case) is the
	# whole selection; the button itself needs passengers.
	var show_wagon: bool = game.selection.size() == 1 \
			and game.selection[0].unit_type == "wagon" \
			and game.is_local_owner(game.selection[0].owner_id)
	if _market_box.visible != show_mkt:
		_market_box.visible = show_mkt
	if _ship_box.visible != show_ship:
		_ship_box.visible = show_ship
	if _wagon_box.visible != show_wagon:
		_wagon_box.visible = show_wagon
	if show_wagon:
		_wagon_btn.disabled = game.selection[0].cargo.is_empty()
	_sel_chip.offset_top = -112.0 if show_mkt else (-78.0 if (show_ship or show_wagon) else -40.0)
	if show_mkt:
		for t in _mkt_sell_btns:
			_mkt_sell_btns[t].disabled = not game.market_can_sell(t)
			_mkt_buy_btns[t].disabled = not game.market_can_buy(t)
	if show_ship:
		for k in _ship_btns:
			_ship_btns[k].disabled = not game.can_train_ship(k)

	# Selection chip (the single selection readout).
	if game.rally_setting:
		_sel_label.text = "Đặt điểm tập kết — nhấp vào bản đồ"
	elif game.placing_field:
		_sel_label.text = "Đang đặt luống ruộng — nhấp ô trống cạnh Farm, Esc để xong"
	elif game.placing_type != "":
		_sel_label.text = "Đang đặt: %s — nhấp ô xanh để xây, Esc/huỷ để hoàn tiền" % game.get_build_def(game.placing_type).name
	elif game.selected_building != null:
		var sb = game.selected_building
		if sb.btype == "town_center":
			if sb.team == 0 and game.age_researching:
				_sel_label.text = "Town Center · đang nghiên cứu lên đời: %d%%" % int(game.age_fraction() * 100.0)
			else:
				_sel_label.text = "Town Center · hàng chờ huấn luyện: %d" % sb.train_queue
		elif sb.btype == "market" and sb.complete:
			_sel_label.text = "Market (Chợ) · Bán 100 → +%d Vàng · Mua 100 → −%d Vàng" % [
					game.market_sell_gold(game.local_slot), game.market_buy_gold(game.local_slot)]
		elif sb.btype == "dock" and sb.complete:
			_sel_label.text = "Bến thuyền · hàng chờ đóng: %d" % sb.train_queue
		elif sb.complete:
			_sel_label.text = sb.display_name
		else:
			_sel_label.text = "%s · đang xây %d%%" % [sb.display_name, int(sb.progress * 100.0)]
	elif game.selected_ship != null:
		var ss = game.selected_ship
		if ss.ship_type == "transport":
			_sel_label.text = "Thuyền chở quân · chở %d/%d quân · HP %d/%d" % [
					ss.cargo.size(), Ship.TRANSPORT_CAP, int(ss.hp), int(ss.max_hp)]
		elif ss.ship_type == "fishing_boat":
			_sel_label.text = "Thuyền cá · đang chở %d/%d Food · HP %d/%d" % [
					ss.carry_amount, Ship.CARRY_CAP, int(ss.hp), int(ss.max_hp)]
		else:
			_sel_label.text = "Thuyền chiến · HP %d/%d" % [int(ss.hp), int(ss.max_hp)]
	elif game.selection.size() > 0:
		# 15g single-vehicle readouts: the wagon's manifest and
		# the cart's route, in the chip's one-line style.
		if game.selection.size() == 1 and game.selection[0].unit_type == "wagon":
			var w1 = game.selection[0]
			if w1.cargo.is_empty():
				_sel_label.text = "Xe chở quân · đang trống (0/%d) · HP %d/%d — chọn quân rồi nhấp phải vào xe để lên" % [
						Unit.WAGON_CAP, int(w1.hp), int(w1.max_hp)]
			else:
				var cnames: Array = []
				for cu in w1.cargo:
					cnames.append(str(UNIT_VN.get(cu.unit_type, cu.unit_type)))
				_sel_label.text = "Xe chở quân · chở %d/%d: %s · HP %d/%d" % [
						w1.cargo.size(), Unit.WAGON_CAP, ", ".join(cnames),
						int(w1.hp), int(w1.max_hp)]
		elif game.selection.size() == 1 and game.selection[0].unit_type == "cart":
			var c1 = game.selection[0]
			if c1.trade_target != null and is_instance_valid(c1.trade_target):
				var tname := "Chợ nhà" if c1.trade_target.owner_id == c1.owner_id \
						else "Chợ của %s" % game._player_display_name(c1.trade_target.owner_id)
				_sel_label.text = "Xe hàng · tuyến tới %s · +%d Vàng/chuyến · HP %d/%d" % [
						tname, c1.trade_gold, int(c1.hp), int(c1.max_hp)]
			else:
				_sel_label.text = "Xe hàng · chưa có tuyến — nhấp phải vào một Chợ để đặt tuyến · HP %d/%d" % [
						int(c1.hp), int(c1.max_hp)]
		else:
			var sel_counts := {}
			for u in game.selection:
				sel_counts[u.unit_type] = int(sel_counts.get(u.unit_type, 0)) + 1
			var parts: Array = []
			var names := {"villager": "Dân", "militia": "Militia", "archer": "Archer",
				"spearman": "Spearman", "cavalry": "Cavalry", "ram": "Ram",
				"cart": "Xe hàng", "wagon": "Xe chở quân"}
			for k in ["villager", "militia", "archer", "spearman", "cavalry", "ram", "cart", "wagon"]:
				if sel_counts.has(k):
					parts.append("%s ×%d" % [names[k], sel_counts[k]])
			_sel_label.text = " · ".join(parts)
	else:
		_sel_label.text = "Chưa chọn — nhấp hoặc kéo để chọn dân"
