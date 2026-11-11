class_name Ship
extends Node2D
## Empire Age — a naval unit trained at the Dock. Ships live ONLY on
## water cells: they path on the World's water A* grid (the inverse
## of the land grid), so they can never enter land — and in the Snow
## biome every water cell is frozen, so the grid has no navigable
## cell at all and ships cannot launch.
##
## Kinds (single side view + horizontal flip, like the Battering Ram):
##   fishing_boat — gathers Food at fish spots, hauls 20/trip back
##                  to a Dock (a water villager; see _fish_tick).
##   transport    — carries up to 5 land units; cargo is hidden and
##                  invulnerable while aboard, and DIES with the ship.
##   war_ship     — floating archer: flat-damage arrows at 5 tiles,
##                  can hit shore targets and other ships.
##
## Art: self-drawn in the game's family (gen/ sources); each slot's
## hulls come from its team-color set (TeamColors.ship_dir — red for
## slot 0, blue/green/yellow recolors for slots 1/2/3). Movement
## adds a gentle bob + wake ripples.

const TARGET_LEN := {"fishing_boat": 74.0, "transport": 106.0, "war_ship": 110.0}
const CARRY_CAP := 20
const GATHER_TIME := 1.6
const TRANSPORT_CAP := 5
const ARRIVE_DIST := 7.0

var ship_type: String = "fishing_boat"
var team: int = 0
var owner_id: int = 0 # player slot owning this ship (P4 MP; == team in SP)
var net_id: int = 0 # stable id for lockstep commands (P4 MP)
var game = null # Main (duck-typed)
var world: World = null

var max_hp: float = 60.0
var hp: float = 60.0
var state: String = "idle" # idle|move|to_fish|fishing|to_dock|to_attack|attack|dead
var selected: bool = false
var path: Array = [] # Vector2 waypoints
var attack_target = null
var fish_spot: FishSpot = null
var home_dock: Building = null
var carry_amount: int = 0
var cargo: Array = [] # boarded Units (transport only)

var _spr: Sprite2D = null
var _disp_len: float = 74.0
var _atk_cd := 0.0
var _gather_t := 0.0
var _repath_t := 0.0
var _scan_t := 0.0
var _wake_t := 0.0
var _bob_t := 0.0
var _death_t := 0.0
var _sink := 0.0 # 13o: accumulated sink depth while dying (the old
	# per-frame += was overwritten by the bob assignment each frame,
	# so sinking never actually accumulated)


func _ready() -> void:
	z_index = 15
	max_hp = Stats.ship_stat(ship_type, "hp")
	hp = max_hp
	var base := TeamColors.ship_dir(owner_id)
	var p := base + ship_type + ".png"
	_spr = Sprite2D.new()
	if ResourceLoader.exists(p):
		_spr.texture = load(p)
		_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var tw := float(_spr.texture.get_width())
		_disp_len = float(TARGET_LEN.get(ship_type, 74.0))
		var s := _disp_len / tw
		_spr.scale = Vector2(s, s)
		# Anchor: hull waterline sits on the node origin.
		_spr.offset = Vector2(0, -float(_spr.texture.get_height()) * 0.30)
	add_child(_spr)
	_bob_t = randf() * TAU


func cell() -> Vector2i:
	return world.world_to_cell(global_position)


func is_dead() -> bool:
	return state == "dead"


func speed() -> float:
	return Stats.ship_stat(ship_type, "speed")


# ---------------------------------------------------------------- orders

func _set_water_path(dest_cell: Vector2i) -> bool:
	var cells: Array = world.get_water_path_cells(cell(), dest_cell)
	path = world.cells_to_points(cells)
	# Drop the first point when it is the cell we already occupy.
	if path.size() > 1 and global_position.distance_to(path[0]) < 12.0:
		path.pop_front()
	return not path.is_empty()


func order_move_cell(dest_cell: Vector2i) -> void:
	if state == "dead":
		return
	attack_target = null
	fish_spot = null
	if _set_water_path(dest_cell):
		state = "move"
	else:
		state = "idle"


func order_fish(spot: FishSpot) -> void:
	if state == "dead" or spot == null:
		return
	attack_target = null
	fish_spot = spot
	if _set_water_path(spot.cell):
		state = "to_fish"
	elif cell() == spot.cell:
		state = "fishing"
	else:
		state = "idle"


func order_attack(t) -> void:
	if state == "dead" or t == null or not is_instance_valid(t):
		return
	fish_spot = null
	attack_target = t
	state = "to_attack"
	_repath_t = 0.0
	_repath_attack()


## Transport: take a land unit aboard. The caller (Main) checks the
## shore/range rules; here we only enforce capacity and ownership.
## A boarded unit leaves the land roster entirely: hidden, frozen
## and invulnerable until it disembarks (or the ship sinks).
func board_unit(u: Unit) -> bool:
	if ship_type != "transport" or state == "dead" or cargo.size() >= TRANSPORT_CAP:
		return false
	if u == null or not is_instance_valid(u) or u.team != team or u.is_dead():
		return false
	cargo.append(u)
	u.visible = false
	u.state = "idle"
	u.path.clear()
	u.attack_target = null
	u.target_node = null
	u.target_site = null
	if game != null:
		game.units.erase(u)
		game.selection.erase(u)
		u.selected = false
	return true


## Transport: put every passenger ashore on walkable cells around
## `land_cell`. Returns how many units disembarked (0 = stayed loaded).
func unload_all(land_cell: Vector2i) -> int:
	if ship_type != "transport" or cargo.is_empty():
		return 0
	var spots: Array = []
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = land_cell + Vector2i(dx, dy)
				if world.in_bounds(c) and not world.is_solid(c) and not spots.has(c):
					spots.append(c)
		if spots.size() >= cargo.size():
			break
	var n := 0
	for u in cargo:
		if n >= spots.size():
			break
		if u == null or not is_instance_valid(u):
			continue
		u.global_position = world.cell_center(spots[n])
		u.visible = true
		if game != null and not game.units.has(u):
			game.units.append(u)
		u.state = "idle"
		n += 1
	cargo = cargo.slice(n)
	return n


# ---------------------------------------------------------------- combat

func _target_gone() -> bool:
	var t = attack_target
	if t == null or not is_instance_valid(t):
		return true
	if t is Building:
		return t.destroyed
	if t.has_method("is_dead"):
		return t.is_dead()
	return false


func _dist_to_target() -> float:
	var t = attack_target
	if t is Building:
		var rect := Rect2(t.position, Vector2(t.size) * World.TILE)
		var cx := clampf(global_position.x, rect.position.x, rect.position.x + rect.size.x)
		var cy := clampf(global_position.y, rect.position.y, rect.position.y + rect.size.y)
		return global_position.distance_to(Vector2(cx, cy))
	return global_position.distance_to(t.global_position)


func _repath_attack() -> void:
	if _target_gone():
		return
	var tc: Vector2i
	if attack_target is Building:
		# Sail to the navigable cell nearest the building's shore.
		var best := Vector2i(-1, -1)
		var bd := INF
		for c in world.water_adjacent_to(attack_target.cells()):
			var d := global_position.distance_squared_to(world.cell_center(c))
			if d < bd:
				bd = d
				best = c
		if best.x < 0:
			path.clear()
			return
		tc = best
	else:
		tc = attack_target.cell()
	_set_water_path(tc)


func strike() -> void:
	if _target_gone():
		return
	if game != null and game.has_method("fire_arrow"):
		game.fire_arrow(global_position + Vector2(0, -34), attack_target,
				Stats.ship_stat(ship_type, "atk"), self)


func take_damage(amount: float, _attacker = null) -> void:
	if state == "dead":
		return
	hp -= amount
	if game != null and game.vfx != null:
		game.vfx.hit_spark(global_position + Vector2(0, -18),
				TeamColors.vfx_palette(owner_id))
	if hp <= 0.0:
		hp = 0.0
		die()
	queue_redraw()


func die() -> void:
	if state == "dead":
		return
	state = "dead"
	_death_t = 1.5
	path.clear()
	attack_target = null
	# Cargo dies with the ship (stated rule, see README): boarded
	# units are out of game.units, so free them outright.
	for u in cargo:
		if u != null and is_instance_valid(u):
			u.queue_free()
	cargo.clear()
	if game != null and game.vfx != null:
		game.vfx.death_smoke(global_position, TeamColors.vfx_palette(owner_id))
	queue_redraw()


# ---------------------------------------------------------------- fishing

func _return_to_dock() -> void:
	var dock: Building = null
	if home_dock != null and is_instance_valid(home_dock) and home_dock.complete \
			and not home_dock.destroyed and home_dock.team == team:
		dock = home_dock
	elif game != null and game.has_method("nearest_dock"):
		dock = game.nearest_dock(team, global_position)
	if dock == null:
		state = "idle"
		return
	home_dock = dock
	var adj := world.water_adjacent_to(dock.cells())
	if adj.is_empty():
		state = "idle"
		return
	var best: Vector2i = adj[0]
	var bd := INF
	for c in adj:
		var d := global_position.distance_squared_to(world.cell_center(c))
		if d < bd:
			bd = d
			best = c
	if _set_water_path(best):
		state = "to_dock"
	else:
		state = "idle"


func _deposit() -> void:
	if carry_amount > 0 and game != null:
		var delivered: int = game.delivered_amount(carry_amount, "food")
		game.credit_owner(owner_id, "food", delivered)
		if game.has_method("on_deposit_effect"):
			game.on_deposit_effect(team, "food", global_position)
		carry_amount = 0
	# Loop back to the same spot while it lasts, else the next one.
	if fish_spot != null and is_instance_valid(fish_spot) and fish_spot.amount > 0:
		order_fish(fish_spot)
		return
	var next: FishSpot = world.nearest_fish_spot(global_position)
	if next != null:
		order_fish(next)
	else:
		state = "idle"


func _fish_tick(delta: float) -> void:
	_gather_t -= delta
	if _gather_t > 0.0:
		return
	_gather_t = GATHER_TIME
	if fish_spot == null or not is_instance_valid(fish_spot) or fish_spot.amount <= 0:
		if carry_amount > 0:
			_return_to_dock()
		else:
			state = "idle"
		return
	var want: int = mini(5, mini(fish_spot.amount, CARRY_CAP - carry_amount))
	carry_amount += fish_spot.take(want)
	if game != null and game.vfx != null:
		game.vfx.ripple(global_position + Vector2(10, 2), Color(0.85, 0.95, 1.0, 0.5), 16.0, 1.0)
	if carry_amount >= CARRY_CAP or fish_spot.amount <= 0:
		_return_to_dock()


# ---------------------------------------------------------------- update

func _follow_path(delta: float) -> bool:
	if path.is_empty():
		return true
	var target: Vector2 = path[0]
	var to := target - global_position
	if to.length() <= ARRIVE_DIST:
		path.pop_front()
		return path.is_empty()
	var dir := to / to.length()
	global_position += dir * speed() * delta
	if _spr != null and absf(dir.x) > 0.15:
		_spr.flip_h = dir.x < 0.0
	_wake_t -= delta
	if _wake_t <= 0.0:
		_wake_t = 0.34
		if game != null and game.vfx != null:
			game.vfx.ripple(global_position + Vector2(0, 4),
					Color(0.85, 0.95, 1.0, 0.35), 13.0, 1.1)
	return false


func _acquire_target() -> void:
	# War ships auto-engage hostiles inside sight: enemy ships first,
	# then enemy units standing near the shore.
	if game == null:
		return
	var sight := Stats.ship_stat(ship_type, "sight") * World.TILE
	var best = null
	var bd := sight
	for s in game.ships:
		if not game.auto_engage_allowed(owner_id, s.owner_id) or s.is_dead():
			continue
		var d := global_position.distance_to(s.global_position)
		if d < bd:
			bd = d
			best = s
	if best != null:
		attack_target = best
		state = "to_attack"
		return
	for u in game.units:
		if not game.auto_engage_allowed(owner_id, u.owner_id) or u.is_dead():
			continue
		var d := global_position.distance_to(u.global_position)
		if d < bd:
			bd = d
			best = u
	if best != null:
		attack_target = best
		state = "to_attack"


func _process(delta: float) -> void:
	if game != null and game.paused:
		return
	_bob_t += delta
	if _spr != null:
		# 13o: bob + a gentle roll around the waterline (stronger
		# under way); the sails are baked into the hull art, so the
		# roll is what sells the wind. Presentation only.
		var moving := state in ["move", "to_fish", "to_dock", "to_attack"]
		var amp := 0.030 if moving else 0.016
		if state == "dead":
			amp *= clampf(1.0 - _sink / 16.0, 0.25, 1.0)
		_spr.rotation = sin(_bob_t * 1.25 + 0.8) * amp + _sink * 0.006
		_spr.position.y = sin(_bob_t * 1.7) * 1.6 + _sink
	if state == "dead":
		_death_t -= delta
		_sink += delta * 7.0 # sinking (accumulates now — see _sink)
		modulate.a = clampf(_death_t / 1.5, 0.0, 1.0)
		if _death_t <= 0.0:
			if game != null and game.has_method("on_ship_dead"):
				game.on_ship_dead(self)
			queue_free()
		return
	# P4 MP: a disconnected player's ships freeze in place.
	if game != null and game.get("mp_mode") == true and game.slot_inert[owner_id]:
		return
	match state:
		"move":
			if _follow_path(delta):
				state = "idle"
		"to_fish":
			if _follow_path(delta):
				state = "fishing" if fish_spot != null and is_instance_valid(fish_spot) else "idle"
				_gather_t = 0.3
		"fishing":
			_fish_tick(delta)
		"to_dock":
			if _follow_path(delta):
				_deposit()
		"to_attack", "attack":
			if _target_gone():
				attack_target = null
				state = "idle"
			elif _dist_to_target() <= Stats.ship_stat(ship_type, "range") + 4.0:
				state = "attack"
				_atk_cd -= delta
				if _atk_cd <= 0.0:
					strike()
					_atk_cd = Stats.ship_stat(ship_type, "cooldown")
			else:
				state = "to_attack"
				_repath_t -= delta
				if _repath_t <= 0.0:
					_repath_t = 0.4
					_repath_attack()
				_follow_path(delta)
		"idle":
			if ship_type == "war_ship":
				_scan_t -= delta
				if _scan_t <= 0.0:
					_scan_t = 0.4
					_acquire_target()
	if hp < max_hp:
		queue_redraw()


func _draw() -> void:
	if selected and state != "dead":
		draw_arc(Vector2(0, 2), _disp_len * 0.36, 0, TAU, 28, TeamColors.ui_color(owner_id), 2.0)
	# A small pile of fish on deck while the hold has any catch.
	if ship_type == "fishing_boat" and carry_amount > 0 and state != "dead":
		draw_circle(Vector2(-8, -14), 3.0, Color(0.8, 0.88, 0.95))
		draw_circle(Vector2(-3, -15), 2.4, Color(0.7, 0.8, 0.9))
	if hp < max_hp and state != "dead":
		var frac := clampf(hp / max_hp, 0.0, 1.0)
		var bcol := TeamColors.ui_color(owner_id)
		var bw := clampf(_disp_len * 0.5, 34.0, 52.0)
		draw_rect(Rect2(-bw * 0.5, -46, bw, 4.5), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(-bw * 0.5, -46, bw * frac, 4.5), bcol)
