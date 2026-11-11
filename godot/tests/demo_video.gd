extends Node
## Demo-video driver (13r follow-up): plays the REAL game from a
## cold boot exactly as a first-time player would, so an Xvfb +
## ffmpeg x11grab recording (tests/record_demo.sh) can capture
## the whole first-run flow:
##   boot loading -> login -> register tab -> typed credentials
##   -> name panel (dice + confirm) -> home lobby (display name
##   in the chip) -> BẮT ĐẦU -> Đấu Thường -> map setup -> SP
##   match vs the bot AI: villagers gather, a House and a
##   Barracks go up, villagers + a Militia train, the Militia
##   marches out. Every step goes through the same buttons /
##   handlers / order APIs the shipped UI uses.
##
## Needs the fresh-store relay from record_demo.sh on
## 127.0.0.1:8765 and an isolated XDG profile (no saved session,
## so the boot lands on the login form).
##
## NOTE: every timer passes process_always=true — the home
## screen pauses the tree, and plain timers would never fire.

const USER := "ChienBinh01"
const PASS := "secret1"

var game = null
var _t0 := 0
var _cam_target := Vector2.INF
var _cam_follow = null
var _assign_flip := false
var _militia_queued := 0


func dlog(msg: String) -> void:
	var dt := float(Time.get_ticks_msec() - _t0) / 1000.0
	print("DEMOLOG [+%6.1fs] %s" % [dt, msg])


func wait_s(sec: float) -> void:
	# process_always (home pauses the tree) + ignore_time_scale
	# (the choreography is timed in REAL seconds).
	await get_tree().create_timer(sec, true, false, true).timeout


## Poll `cond` every 0.2 s (real time) until true or timeout.
func wait_until(cond: Callable, timeout: float, what: String) -> bool:
	var waited := 0.0
	while waited < timeout:
		if cond.call():
			return true
		await get_tree().create_timer(0.2, true).timeout
		waited += 0.2
	if cond.call():
		return true
	dlog("TIMEOUT waiting for: " + what)
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	dlog("driver start")
	game = load("res://main.tscn").instantiate()
	add_child(game)
	_run()


func _process(delta: float) -> void:
	if game == null or game.cam == null:
		return
	var tgt := _cam_target
	if _cam_follow != null and is_instance_valid(_cam_follow):
		tgt = _cam_follow.global_position
	if tgt != Vector2.INF:
		var c = game.cam
		c.position = c.position.lerp(tgt, 1.0 - exp(-2.0 * delta))


# ------------------------------------------------------------ helpers

## Type into a LineEdit character by character, like a player.
func type_into(edit: LineEdit, text: String) -> void:
	edit.grab_focus()
	for i in range(1, text.length() + 1):
		edit.text = text.left(i)
		edit.caret_column = edit.text.length()
		await wait_s(0.075)


func find_buttons(root: Node, acc: Array, skip: Node = null) -> void:
	if root == skip:
		return
	if root is BaseButton:
		acc.append(root)
	for ch in root.get_children():
		find_buttons(ch, acc, skip)


func find_spot(size: Vector2i, near: Vector2i) -> Vector2i:
	for r in range(0, 18):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := near + Vector2i(dx, dy)
				if game.world.can_place(cand, size):
					return cand
	return Vector2i(-1, -1)


func player_units_of(kind: String) -> Array:
	var out: Array = []
	for u in game.units:
		if u.team == 0 and u.unit_type == kind and not u.is_dead():
			out.append(u)
	return out


# ------------------------------------------------------------ flow

func _run() -> void:
	# -- 1. boot -> loading -> login ------------------------------
	if not await wait_until(func() -> bool: return game.entry_state() == "login",
			40.0, "login screen"):
		_finish()
		return
	dlog("login screen up")
	await wait_s(1.1)

	# -- 2. register tab + typed credentials ----------------------
	var login = game._login_screen
	if login == null:
		dlog("FAIL no login screen ref")
		_finish()
		return
	login._tab_register.emit_signal("pressed")
	dlog("register tab pressed")
	await wait_s(0.7)
	await type_into(login._user_edit, USER)
	await type_into(login._pass_edit, PASS)
	await type_into(login._pass2_edit, PASS)
	dlog("credentials typed")
	await wait_s(0.5)
	login._submit_btn.emit_signal("pressed")
	dlog("register submitted")

	# -- 3. name panel: dice + confirm ----------------------------
	if not await wait_until(func() -> bool: return game.entry_state() == "name",
			25.0, "name panel"):
		_finish()
		return
	dlog("name panel up")
	await wait_s(1.0)
	var np = game._name_panel
	var dice_btn: BaseButton = null
	var confirm_btn: BaseButton = null
	for ch in np._panel.get_children():
		if ch is BaseButton and ch.has_meta("fr"):
			var fr: Rect2 = ch.get_meta("fr")
			if fr == NamePanel.DICE_FR:
				dice_btn = ch
			elif fr == NamePanel.BUTTON_FR:
				confirm_btn = ch
	if dice_btn != null:
		dice_btn.emit_signal("pressed")
	else:
		np.roll_dice()
	dlog("dice pressed, name=" + String(np._edit.text))
	await wait_s(1.4)
	if confirm_btn != null:
		confirm_btn.emit_signal("pressed")
	else:
		np.confirm()
	dlog("name confirmed")

	# -- 4. home lobby ---------------------------------------------
	if not await wait_until(func() -> bool: return game.entry_state() == "home",
			25.0, "home lobby"):
		_finish()
		return
	dlog("home up, chip name=" + String(game.entry_home_name_text()))
	await wait_s(1.8)

	# BẮT ĐẦU (the real TextureButton in the bottom band).
	var home = game.home
	var cands: Array = []
	find_buttons(home._root, cands, home._mode_panel)
	var start_btn: BaseButton = null
	for b in cands:
		if b is TextureButton and b.size.x >= 120.0:
			if start_btn == null or b.global_position.y > start_btn.global_position.y:
				start_btn = b
	if start_btn != null:
		start_btn.emit_signal("pressed")
		dlog("BẮT ĐẦU pressed (button)")
	else:
		home._open_mode_panel()
		dlog("BẮT ĐẦU fallback: _open_mode_panel()")
	await wait_s(1.0)

	# Đấu Thường (first TextureButton inside the mode panel).
	var modes: Array = []
	find_buttons(home._mode_panel, modes)
	if modes.size() >= 1:
		modes[0].emit_signal("pressed")
		dlog("Đấu Thường pressed")
	else:
		game.open_setup()
		dlog("Đấu Thường fallback: open_setup()")
	await wait_s(1.3)

	# Map setup -> start (the panel's own confirm handler).
	game.hud.confirm_map_choice()
	dlog("map confirmed")
	if not await wait_until(func() -> bool: return game.match_time > 0.3,
			15.0, "match running"):
		_finish()
		return
	dlog("match running, resources=" + str(game.resources))

	await _play_match()
	_finish()


func _finish() -> void:
	dlog("driver done")
	await wait_s(0.6)
	get_tree().quit()


# ------------------------------------------------------------ match

func _place(btype: String, size: Vector2i) -> bool:
	var cell := find_spot(size, game.player_tc.origin_cell)
	if cell.x < 0:
		dlog("no spot for " + btype)
		return false
	game.enter_placement(btype)
	var ok: bool = game.confirm_placement(cell)
	dlog("placed %s at %s -> %s" % [btype, str(cell), str(ok)])
	return ok


func _building(btype: String):
	for b in game.buildings:
		if b.owner_id == 0 and b.btype == btype and not b.destroyed:
			return b
	return null


func _housekeep() -> void:
	# Idle villagers (fresh spawns, finished builders) get work:
	# alternate wood / food, exactly like a player's right-clicks.
	for u in game.units:
		if u.team != 0 or u.unit_type != "villager" or u.is_dead():
			continue
		if u.state == "idle" and u.target_site == null and u.target_node == null:
			_assign_flip = not _assign_flip
			var kind := "wood" if _assign_flip else "food"
			var node = game.world.nearest_node_of_type(u.global_position, kind)
			if node != null:
				u.order_gather(node)
				dlog("villager -> gather " + kind)
	# Militia as soon as the Barracks stands (a pair, no more).
	var barr = _building("barracks")
	if barr != null and barr.complete \
			and player_units_of("militia").size() + _militia_queued < 2:
		if game.train_militia():
			_militia_queued += 1
			dlog("militia training queued")


func _play_match() -> void:
	var tc = game.player_tc
	_cam_target = tc.global_position
	# Economy openers: House + Barracks sites, one villager.
	_place("house", Vector2i(2, 2))
	_place("barracks", Vector2i(3, 3))
	if game.train_villager():
		dlog("villager training queued")
	_housekeep()

	var t := 0.0
	var trained_second := false
	var militia = null
	var marched := false
	while t < 54.0:
		await wait_s(1.0)
		t += 1.0
		_housekeep()
		if t >= 18.0 and not trained_second:
			trained_second = true
			if game.train_villager():
				dlog("second villager queued")
		# Camera beats.
		if t == 8.0:
			var woods := player_units_of("villager")
			for u in woods:
				if u.target_node != null and u.target_node.rtype == "wood":
					_cam_follow = u
					dlog("camera follows woodcutter")
					break
		if t == 20.0:
			_cam_follow = null
			_cam_target = tc.global_position
			dlog("camera back to base")
		# Militia march (the whole squad, once it exists).
		var mil := player_units_of("militia")
		if militia == null and not mil.is_empty():
			militia = mil[0]
			dlog("militia trained x%d" % mil.size())
		if militia != null and not marched and t >= 26.0:
			marched = true
			game.select_unit_at(militia.global_position, 26.0)
			var centre := Vector2(World.MAP_W, World.MAP_H) * World.TILE * 0.36
			game.order_move(mil, centre)
			_cam_follow = militia
			dlog("militia marching to " + str(centre))
		if t == 44.0:
			_cam_follow = null
			_cam_target = tc.global_position
			dlog("camera returns to base")
	dlog("match segment end: match_time=%.0f res=%s pop=%d/%d" % [
		game.match_time, str(game.resources), game.pop_current(), game.pop_cap()])
