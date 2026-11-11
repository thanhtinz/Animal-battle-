class_name Spectator
extends CanvasLayer
## 15e spectator controller — created by Main ONLY for observer
## matches (custom rooms). Presentation-only: it reads the sim
## (units, buildings, camera) and moves the CAMERA; it never
## writes sim state, never sends commands, and stays out of the
## checksum entirely.
##
## Camera modes (mutually exclusive):
##   FREE   — the observer drives the camera as in 15a.
##   FOLLOW — the camera tracks one slot: their hero if alive,
##            else their Town Center, else their largest army
##            cluster. Any manual camera input (drag / keys /
##            wheel / pinch — RTSCamera.manual_input) drops the
##            mode back to FREE.
##   AUTO   — the camera periodically glides to the most recent
##            significant action the client already observes:
##            hero skill casts (Main._skill_cast_fx hook),
##            building destructions (Main.on_building_destroyed
##            hook) and live battle clusters polled from unit
##            states. After 20 s of quiet it slowly tours the
##            alive players' bases.
##
## The bar (bottom centre) shows the current mode, one chip per
## slot for follow, and the stream badge: "Trực tiếp" or the
## room's anti-cheat delay "Trễ Ns" (Net.cfg_obs_delay — the
## buffering itself is server-side, see hub.go).

const MODE_FREE := 0
const MODE_FOLLOW := 1
const MODE_AUTO := 2

const GOLD := Color(0.98, 0.80, 0.45)
const TXT := Color(0.92, 0.93, 0.96)
const TXT_DIM := Color(0.62, 0.66, 0.74)

var game = null # Main (set before add_child)

var mode: int = MODE_FREE
var follow_slot: int = -1

var _events: Array = [] # {pos, at (msec), w, why}
var _last_action_ms: int = 0
var _last_jump_ms: int = 0
var _eval_acc: float = 0.0
var _tour_idx: int = 0
var _tour_next_ms: int = 0
var _glide_from := Vector2.ZERO
var _glide_to := Vector2.ZERO
var _glide_t: float = 1.0 # >= 1: not gliding
var _auto_target := Vector2.ZERO
var _has_auto_target: bool = false

var _panel: PanelContainer
var panel_ui = null # SpectatorPanel (15e-bis; untyped on purpose)
var _mode_label: Label
var _badge_label: Label
var _free_btn: Button
var _auto_btn: Button
var _chips: Array = [] # per-slot follow Buttons


func _ready() -> void:
	_build_bar()
	# 15e-bis: the observer's dedicated panel (opened from
	# HUD's people button in observer mode — never the players
	# panel). Built after the bar so it layers above it.
	panel_ui = SpectatorPanel.new()
	panel_ui.spec = self
	panel_ui.game = game
	add_child(panel_ui)
	if game != null and game.cam != null:
		game.cam.manual_input.connect(_on_manual_input)
	_refresh_bar()


func _process(delta: float) -> void:
	if game == null or game.cam == null or game.mp_over:
		return
	# Auto-camera glide (smoothstep over ~0.9 s).
	if _glide_t < 1.0:
		_glide_t = minf(1.0, _glide_t + delta / 0.9)
		var s := _glide_t * _glide_t * (3.0 - 2.0 * _glide_t)
		game.cam.focus_on(_glide_from.lerp(_glide_to, s))
	if mode == MODE_FOLLOW and follow_slot >= 0:
		var tp = follow_target_pos(follow_slot)
		if tp != null:
			var k := 1.0 - exp(-8.0 * delta)
			game.cam.focus_on(game.cam.position.lerp(tp, k))
	elif mode == MODE_AUTO:
		_eval_acc += delta
		if _eval_acc >= 1.0:
			_eval_acc = 0.0
			_auto_evaluate()
	_refresh_badge()


# ------------------------------------------------------------ modes

func set_free() -> void:
	var changed := mode != MODE_FREE
	mode = MODE_FREE
	follow_slot = -1
	_glide_t = 1.0
	if changed:
		print("MPLOG spec mode=free")
	_refresh_bar()


func set_follow(slot: int) -> void:
	mode = MODE_FOLLOW
	follow_slot = slot
	_glide_t = 1.0
	print("MPLOG spec mode=follow slot=", slot,
			" name=", _slot_name(slot))
	_refresh_bar()


func set_auto() -> void:
	mode = MODE_AUTO
	follow_slot = -1
	_last_action_ms = Time.get_ticks_msec()
	print("MPLOG spec mode=auto")
	_refresh_bar()


# ------------------------------------------------------------ panel (15e-bis)

## The dedicated spectator panel shares this controller's
## state (mode / follow_slot / badge) with the bar; opening it
## refreshes its content from that single source.
func set_panel_open(on: bool) -> void:
	if panel_ui == null or panel_is_open() == on:
		return
	panel_ui.visible = on
	if on:
		panel_ui.refresh()
		print("MPLOG spec panel open")
	else:
		print("MPLOG spec panel closed")


func toggle_panel() -> void:
	set_panel_open(not panel_is_open())


func panel_is_open() -> bool:
	return panel_ui != null and panel_ui.visible


## Esc path (HUD.close_panel_if_open asks this first for an
## observer): reports whether it consumed the key.
func close_panel_if_open() -> bool:
	if panel_is_open():
		set_panel_open(false)
		return true
	return false


## Any manual camera input breaks follow/auto back to free.
func _on_manual_input() -> void:
	if mode != MODE_FREE or _glide_t < 1.0:
		set_free()


func mode_name() -> String:
	return ["free", "follow", "auto"][mode]


# ------------------------------------------------------------ targets

func _slot_name(slot: int) -> String:
	if game != null and slot >= 0 and slot < game.slot_names.size():
		var n := String(game.slot_names[slot])
		if n != "":
			return n
	return "P%d" % (slot + 1)


func hero_of(owner: int):
	if game == null:
		return null
	for u in game.units:
		if int(u.owner_id) == owner and u.unit_type == "king" \
				and not u.is_dead():
			return u
	return null


## The follow chain: hero -> Town Center -> largest army
## cluster -> null (camera stays put).
func follow_target_pos(slot: int) -> Variant:
	if game == null:
		return null
	var h = hero_of(slot)
	if h != null:
		return h.global_position
	var tc = game.tc_of(slot)
	if tc != null and not tc.destroyed:
		return tc.position + Vector2(tc.size) * World.TILE * 0.5
	var pts: Array = []
	for u in game.units:
		if int(u.owner_id) == slot and u.is_military() \
				and not u.is_dead() and not u.garrisoned:
			pts.append(u.global_position)
	var c := largest_cluster(pts, World.TILE * 3.0)
	if c.is_empty():
		return null
	return c["pos"]


## Grid-bucket clustering: returns {"pos": centroid, "count": n}
## of the fullest bucket, or {} for no points. Static + pure so
## the SP suite can pin it directly.
static func largest_cluster(points: Array, cell: float) -> Dictionary:
	if points.is_empty():
		return {}
	var buckets := {}
	for p in points:
		var key := Vector2i(floori(float(p.x) / cell), floori(float(p.y) / cell))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(p)
	var best: Array = []
	for key in buckets:
		if buckets[key].size() > best.size():
			best = buckets[key]
	if best.is_empty():
		return {}
	var c := Vector2.ZERO
	for p in best:
		c += p
	return {"pos": c / float(best.size()), "count": best.size()}


## Live battle clusters: units currently attacking something.
## Only the largest cluster is returned (the biggest fight is
## the one worth watching).
func battle_clusters() -> Array:
	if game == null:
		return []
	var pts: Array = []
	for u in game.units:
		if u.is_dead():
			continue
		if (u.state == "attack" or u.state == "to_attack") \
				and u.attack_target != null and is_instance_valid(u.attack_target):
			pts.append(u.global_position)
	var c := largest_cluster(pts, World.TILE * 3.0)
	return [] if c.is_empty() else [c]


# ------------------------------------------------------------ auto-camera

## Event hooks called by Main's presentation paths.
func note_cast(pos: Vector2, at_ms: int = -1) -> void:
	_events.append({"pos": pos, "at": _stamp(at_ms), "w": 30.0, "why": "cast"})


func note_building_down(pos: Vector2, is_tc: bool, at_ms: int = -1) -> void:
	_events.append({"pos": pos, "at": _stamp(at_ms),
			"w": 55.0 if is_tc else 40.0, "why": "building"})


func _stamp(at_ms: int) -> int:
	return at_ms if at_ms >= 0 else Time.get_ticks_msec()


## Pick the best current auto-camera candidate: {"pos", "why"}
## or {} when nothing is happening. Fresh events decay over
## ~15 s; a live battle of >= 3 attackers scores by size.
func _auto_pick(now: int) -> Dictionary:
	var best := {}
	var best_score := 0.0
	var keep: Array = []
	for e in _events:
		var age := float(now - int(e["at"])) / 1000.0
		if age > 15.0:
			continue
		keep.append(e)
		var score := float(e["w"]) * (1.0 - age / 20.0)
		if score > best_score:
			best_score = score
			best = {"pos": e["pos"], "why": String(e["why"])}
	_events = keep
	for c in battle_clusters():
		var n := int(c["count"])
		if n >= 3 and 6.0 * float(n) > best_score:
			best_score = 6.0 * float(n)
			best = {"pos": c["pos"], "why": "battle"}
	return best


func _auto_evaluate() -> void:
	var now := Time.get_ticks_msec()
	var pick := _auto_pick(now)
	if not pick.is_empty():
		_last_action_ms = now
		var pos: Vector2 = pick["pos"]
		if (not _has_auto_target or pos.distance_to(_auto_target) > 48.0) \
				and now - _last_jump_ms >= 3500:
			_jump_to(pos, String(pick["why"]), now)
		return
	# Quiet for a while: slowly tour the alive players' bases.
	if now - _last_action_ms > 20000 and now >= _tour_next_ms:
		_tour_next_ms = now + 8000
		var alive: Array = []
		for s in range(game.slot_count()):
			if not game.slot_eliminated[s]:
				var tc = game.tc_of(s)
				if tc != null and not tc.destroyed:
					alive.append(s)
		if alive.is_empty():
			return
		_tour_idx = (_tour_idx + 1) % alive.size()
		var ts: int = alive[_tour_idx]
		var tc2 = game.tc_of(ts)
		_jump_to(tc2.position + Vector2(tc2.size) * World.TILE * 0.5,
				"tour", now)


func _jump_to(pos: Vector2, why: String, now: int) -> void:
	_glide_from = game.cam.position
	_glide_to = pos
	_glide_t = 0.0
	_auto_target = pos
	_has_auto_target = true
	_last_jump_ms = now
	print("MPLOG spec auto jump to=", pos, " why=", why)


# ------------------------------------------------------------ bar UI

func _sb(bg: Color, radius: int, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


func _bar_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_stylebox_override("normal",
			_sb(Color(1, 1, 1, 0.07), 6, Color(1, 1, 1, 0.16), 1))
	b.add_theme_stylebox_override("hover",
			_sb(Color(1, 1, 1, 0.14), 6, Color(1, 1, 1, 0.3), 1))
	b.add_theme_stylebox_override("pressed",
			_sb(Color(1, 1, 1, 0.2), 6, GOLD, 1))
	return b


func _build_bar() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -340
	_panel.offset_right = 340
	_panel.offset_top = -100
	_panel.offset_bottom = -60
	_panel.add_theme_stylebox_override("panel",
			_sb(Color(0.05, 0.08, 0.15, 0.92), 10, GOLD, 1))
	add_child(_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(hb)
	var title := Label.new()
	title.text = "Người xem"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", GOLD)
	hb.add_child(title)
	_free_btn = _bar_button("Tự do")
	_free_btn.pressed.connect(set_free)
	hb.add_child(_free_btn)
	_auto_btn = _bar_button("Tự động")
	_auto_btn.pressed.connect(set_auto)
	hb.add_child(_auto_btn)
	if game != null:
		for s in range(game.slot_count()):
			var chip := _bar_button(_slot_name(s))
			var slot := s
			chip.pressed.connect(func() -> void: set_follow(slot))
			hb.add_child(chip)
			_chips.append(chip)
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 13)
	_mode_label.add_theme_color_override("font_color", TXT)
	hb.add_child(_mode_label)
	_badge_label = Label.new()
	_badge_label.add_theme_font_size_override("font_size", 13)
	hb.add_child(_badge_label)


func _badge_text() -> String:
	return "Trễ %d giây" % Net.cfg_obs_delay if Net.cfg_obs_delay > 0 else "Trực tiếp"


func _refresh_badge() -> void:
	if _badge_label == null:
		return
	var t := _badge_text()
	if _badge_label.text != t:
		_badge_label.text = t
		_badge_label.add_theme_color_override("font_color",
				Color(1.0, 0.62, 0.35) if Net.cfg_obs_delay > 0
				else Color(0.45, 0.95, 0.55))


func _refresh_bar() -> void:
	if _mode_label == null:
		return
	_refresh_badge()
	match mode:
		MODE_FOLLOW:
			_mode_label.text = "Theo dõi: %s" % _slot_name(follow_slot)
		MODE_AUTO:
			_mode_label.text = "Camera tự động"
		_:
			_mode_label.text = "Camera tự do"
	_free_btn.add_theme_color_override("font_color",
			GOLD if mode == MODE_FREE else TXT)
	_auto_btn.add_theme_color_override("font_color",
			GOLD if mode == MODE_AUTO else TXT)
	for i in range(_chips.size()):
		_chips[i].add_theme_color_override("font_color",
				GOLD if mode == MODE_FOLLOW and follow_slot == i
				else TeamColors.ui_color(i))


## State snapshot for the auto driver (smoke) and debugging.
func debug_state() -> Dictionary:
	var target = null
	if mode == MODE_FOLLOW and follow_slot >= 0:
		target = follow_target_pos(follow_slot)
	elif mode == MODE_AUTO and _has_auto_target:
		target = _auto_target
	return {"mode": mode_name(), "slot": follow_slot,
			"cam": game.cam.position if game != null and game.cam != null else Vector2.ZERO,
			"target": target}
