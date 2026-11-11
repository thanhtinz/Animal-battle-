class_name EnemyAI
extends Node
## Empire Age P3 — the enemy commander (team 1, deep blue faction).
##
## Honest economy: the AI keeps its OWN resource ledger. It only
## gains when one of its villagers actually deposits a load at an
## enemy drop-off (Main.credit_resource routes team-1 deposits here),
## and it pays the same unit costs as the player when it queues
## training at its Town Center / Barracks.
##
## Behaviour:
##   * Economy — idle villagers are assigned to gather nodes near
##     the enemy base (wood/food/gold rotation), up to a villager cap.
##   * Production — TC trains villagers to the cap; the Barracks
##     trains a Militia/Archer mix up to a cap that grows per wave.
##   * Defence — idle military engages player units that come within
##     DEFEND_RADIUS of the enemy Town Center (their own guard-anchor
##     auto-engage helps too).
##   * Waves — every WAVE_INTERVAL after FIRST_WAVE_DELAY it sends
##     2, 3, 4, ... military units at the player's Town Center.
##     When wave 2 launches, the AI ages up to Feudal; wave 4, to
##     the Castle Age (both on the wave schedule, as before). Wave 6
##     arms IMPERIAL (Age IV) — but unlike II/III the AI must BUY it
##     from its own ledger (Stats.AGE4_UP_COST) and research it over
##     AGE4_UP_TIME like the player; if it cannot afford it yet, it
##     buys the moment its economy can (see _age4_tick).
##   * TC down (annihilation rules): waves stop, no new age-ups,
##     villager production stops with the TC — but the Barracks
##     keeps turning out military with what the side has left, and
##     standing forces keep fighting via their own auto-engage.
##
## Test hooks: all timers/caps are plain vars — the suite shortens
## first_wave_delay / wave_interval and reads waves_launched,
## last_wave_size, deposits and res directly.

var game = null # Main (duck-typed)

var res: Dictionary = {"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0}
var deposits: int = 0 # villager drop-offs credited (honesty counter)

var villager_cap: int = 6
var military_cap_base: int = 4
var military_cap_max: int = 12

var waves_enabled: bool = true
var first_wave_delay: float = 240.0
var wave_interval: float = 210.0
var next_wave_time: float = -1.0 # armed from match_time on first tick
var waves_launched: int = 0
var last_wave_size: int = 0

## Imperial (Age IV) purchase state: armed by wave 6, bought from
## the ledger when affordable, researched over AGE4_UP_TIME.
var age4_pending: bool = false
var age4_researching: bool = false
var age4_timer: float = 0.0

const DEFEND_RADIUS := 320.0 # 10 tiles around the enemy TC

var _assign_t := 0.0
var _prod_t := 0.0
var _def_t := 0.0
var _navy_t := 0.0
var navy_ships_wanted: int = 2 # scripted navy size on water layouts
var _pref_cycle := 0
var _mil_toggle := 0


func credit(rtype: String, amount: int) -> void:
	res[rtype] = int(res.get(rtype, 0)) + amount
	deposits += 1


func _process(delta: float) -> void:
	if game == null or game.paused or game.match_over != "":
		return
	if next_wave_time < 0.0:
		next_wave_time = game.match_time + first_wave_delay
	_assign_t -= delta
	if _assign_t <= 0.0:
		_assign_t = 0.6
		_assign_economy()
	_prod_t -= delta
	if _prod_t <= 0.0:
		_prod_t = 1.0
		_production()
	_def_t -= delta
	if _def_t <= 0.0:
		_def_t = 0.3
		_defend()
	_navy_t -= delta
	if _navy_t <= 0.0:
		_navy_t = 1.2
		_navy()
	_age4_tick(delta)
	# Waves stop once the AI's own Town Center is down (it fights on
	# with what it has; see the annihilation rules in Main).
	if waves_enabled and not game.enemy_tc_destroyed \
			and game.match_time >= next_wave_time:
		launch_wave()


# ---------------------------------------------------------------- helpers

func _team_units(team: int, kind: String = "") -> Array:
	var out: Array = []
	for u in game.units:
		if u.team == team and not u.is_dead() and (kind == "" or u.unit_type == kind):
			out.append(u)
	return out


func _can_afford(costs: Dictionary) -> bool:
	for r in costs:
		if int(res.get(r, 0)) < int(costs[r]):
			return false
	return true


func _pay(costs: Dictionary) -> void:
	for r in costs:
		res[r] = int(res[r]) - int(costs[r])


func _pop_room() -> bool:
	return game.team_pop_current(1) + game.team_queued(1) < game.team_pop_cap(1)


# ---------------------------------------------------------------- economy

func _assign_economy() -> void:
	var prefs := ["wood", "food", "wood", "gold", "stone"]
	for u in _team_units(1, "villager"):
		if u.state != "idle" or u.carry_amount > 0:
			continue
		var rt: String = prefs[_pref_cycle % prefs.size()]
		_pref_cycle += 1
		var node: ResourceNode = game.world.nearest_node_of_type(u.global_position, rt)
		if node == null:
			node = game.world.nearest_node_of_type(u.global_position, "wood")
		if node != null:
			u.order_gather(node)


# ---------------------------------------------------------------- production

## The Imperial King: once the AI has BOUGHT Age IV (see
## _age4_tick) it crowns a King like the player must — from its
## own ledger, at a Castle, one alive at a time. It holds no
## Castle in its starting stronghold, so on reaching Imperial it
## first commissions one (full Castle cost from the ledger,
## raised complete beside the TC like the rest of its stronghold)
## and only then pays the King's muster. A side whose TC has
## fallen never starts either (annihilation rules).
func _king_production() -> void:
	if int(game.team_age.get(1, 1)) < 4 or game.enemy_tc_destroyed:
		return
	var castle = game.get_team_castle(1)
	if castle == null:
		var cdef: Dictionary = game.BUILD_DEFS["castle"]
		if not _can_afford(cdef["cost"]):
			return
		var spot := Vector2i(-1, -1)
		var tc = game.enemy_tc
		if tc == null or not is_instance_valid(tc) or tc.destroyed:
			return
		for r in range(4, 12):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var cand: Vector2i = tc.origin_cell + Vector2i(dx, dy)
					if game.world.can_place(cand, cdef["size"]):
						spot = cand
						break
				if spot.x >= 0:
					break
			if spot.x >= 0:
				break
		if spot.x < 0:
			return
		_pay(cdef["cost"])
		game._spawn_building("castle", 1, spot, true)
		return
	if not castle.complete or castle.train_queue > 0:
		return
	if game.king_alive(1) or game.king_queued(1):
		return
	if not _can_afford(game.UNIT_COSTS["king"]) or not _pop_room():
		return
	_pay(game.UNIT_COSTS["king"])
	castle.start_training("king")


## The AI hero's active skill: a simple deterministic trigger on
## the production cadence — cast when the skill would bite:
## Ngân Kỵ charges when an enemy is close enough to fight, Kim
## Hoa heals when a nearby ally (or she) is missing real HP, Lam
## Bào freezes enemies in Băng Phong range, Bạch Sa raises her
## barrier when enemies press in. Cooldown gating is the cast's.
func _hero_skill_tick() -> void:
	var hero: Unit = game.hero_of_team(1)
	if hero == null or hero.skill_cd_t > 0.0:
		return
	var ch: String = game.char_for(hero.owner_id)
	var kit: Dictionary = Stats.HERO_KITS.get(ch, {})
	if kit.is_empty():
		return
	var r := Stats.AURA_RANGE_TILES * World.TILE
	var cast := false
	# 14c: cast point for the targeted Chiêu 1 (sentinel = none;
	# the original four ignore it entirely).
	var target := Vector2(-99999.0, -99999.0)
	match ch:
		"ngan_ky":
			for u in game.units:
				if is_instance_valid(u) and u.team == 0 and not u.is_dead() \
						and u.global_position.distance_to(hero.global_position) <= r * 0.7:
					cast = true
					break
		"kim_hoa":
			for u in game.units:
				if is_instance_valid(u) and u.team == 1 and not u.is_dead() \
						and u.hp <= u.max_hp - 40.0 \
						and u.global_position.distance_to(hero.global_position) <= r:
					cast = true
					break
		"lam_bao":
			var sr := float(kit["skill_range"]) * World.TILE
			for u in game.units:
				if is_instance_valid(u) and u.team == 0 and not u.is_dead() \
						and u.global_position.distance_to(hero.global_position) <= sr:
					cast = true
					break
		"bach_sa":
			for u in game.units:
				if is_instance_valid(u) and u.team == 0 and not u.is_dead() \
						and u.global_position.distance_to(hero.global_position) <= r:
					cast = true
					break
		# 14c: the new heroes' Chiêu 1 are targeted — the AI aims
		# at the nearest enemy inside the skill's own range.
		"loi_chan", "xich_diem", "phong_linh", "thach_son":
			var key: String = {"loi_chan": "dash_tiles", "xich_diem": "mark_range_tiles",
					"phong_linh": "snipe_range_tiles", "thach_son": "leap_tiles"}[ch]
			var sr2 := float(kit[key]) * World.TILE
			var foe: Unit = null
			for u in game.units:
				if is_instance_valid(u) and u.team == 0 and not u.is_dead() \
						and u.global_position.distance_to(hero.global_position) <= sr2:
					if foe == null or u.net_id < foe.net_id:
						foe = u
			if foe != null:
				cast = true
				target = foe.global_position
	if cast:
		game.cast_hero_skill(hero, target)


func _production() -> void:
	_king_production()
	_hero_skill_tick()
	var tc = game.enemy_tc
	var tc_alive: bool = tc != null and is_instance_valid(tc) and not tc.destroyed
	# Villagers first, up to the cap (impossible without the TC).
	if tc_alive and _team_units(1, "villager").size() < villager_cap and tc.train_queue == 0 \
			and _can_afford(game.UNIT_COSTS["villager"]) and _pop_room():
		_pay(game.UNIT_COSTS["villager"])
		tc.start_training("villager")
	# Military mix at the Barracks, up to the (wave-scaled) cap.
	var barr = game.get_team_barracks(1)
	if barr == null or not barr.complete or barr.train_queue > 0:
		return
	var cap := mini(military_cap_base + waves_launched * 2, military_cap_max)
	var mil := 0
	for u in _team_units(1):
		if u.is_military():
			mil += 1
	if mil + barr.train_queue >= cap:
		return
	var kind := "militia" if _mil_toggle % 2 == 0 else "archer"
	# From Feudal on, every fourth trainee is cavalry (shock wing).
	if int(game.team_age.get(1, 1)) >= 2 and _mil_toggle % 4 == 3:
		kind = "cavalry"
	if not _can_afford(game.UNIT_COSTS[kind]):
		kind = "archer" if kind == "militia" else "militia"
		if not _can_afford(game.UNIT_COSTS[kind]):
			return
	if not _pop_room():
		return
	_mil_toggle += 1
	_pay(game.UNIT_COSTS[kind])
	barr.start_training(kind)


# ---------------------------------------------------------------- defence

# ---------------------------------------------------------------- navy (scripted, small)
## On water-heavy layouts (Quần đảo / Bờ biển) only, and only once
## the third wave is due (waves_launched >= 2): keep up to
## `navy_ships_wanted` War Ships training at the enemy Dock and send
## idle ones patrolling toward the player's shore, where their own
## auto-engage takes over. Land layouts skip the navy entirely.

func _navy() -> void:
	if game.world == null:
		return
	var lay: String = game.world.resolved_layout
	if lay != "islands" and lay != "coast":
		return
	if waves_launched < 2:
		return
	_navy_patrol()
	var dock = game.get_team_dock(1)
	if dock == null or dock.train_queue > 0:
		return
	var mine := 0
	for s in game.ships:
		if s.team == 1 and s.ship_type == "war_ship" and not s.is_dead():
			mine += 1
	if mine >= navy_ships_wanted:
		return
	var costs: Dictionary = game.SHIP_COSTS["war_ship"]
	if not _can_afford(costs):
		return
	_pay(costs)
	dock.start_training("war_ship")


func _navy_patrol() -> void:
	var tc = game.player_tc
	if tc == null or not is_instance_valid(tc) or tc.destroyed:
		return
	for s in game.ships:
		if s.team == 1 and s.ship_type == "war_ship" and not s.is_dead() and s.state == "idle":
			var dest: Vector2i = game.world.nearest_navigable(
					game.world.world_to_cell(tc.global_position), 16)
			if dest.x >= 0:
				s.order_move_cell(dest)

func _defend() -> void:
	var tc = game.enemy_tc
	if tc == null or not is_instance_valid(tc) or tc.destroyed:
		return
	var centre: Vector2 = tc.position + Vector2(tc.size) * World.TILE * 0.5
	# Nearest player unit threatening the base.
	var threat = null
	var bd := DEFEND_RADIUS
	for u in game.units:
		if u.team != 0 or u.is_dead():
			continue
		var d := centre.distance_to(u.global_position)
		if d < bd:
			bd = d
			threat = u
	if threat == null:
		return
	for u in _team_units(1):
		if u.is_military() and u.state == "idle":
			u.order_attack(threat)


# ---------------------------------------------------------------- waves

func launch_wave() -> void:
	waves_launched += 1
	next_wave_time = game.match_time + wave_interval
	var want := waves_launched + 1 # wave sizes grow 2, 3, 4, ...
	var idle_mil: Array = []
	for u in _team_units(1):
		if u.is_military() and u.state == "idle":
			idle_mil.append(u)
	last_wave_size = mini(want, idle_mil.size())
	var tc = game.player_tc
	if tc != null and is_instance_valid(tc) and not tc.destroyed:
		for i in range(last_wave_size):
			idle_mil[i].order_attack(tc)
	if waves_launched == 2:
		# The AI ages up to Feudal as its second wave marches.
		game.set_team_age(1, 2)
	if waves_launched == 4:
		# ...and to the Castle Age as its fourth wave marches.
		game.set_team_age(1, 3)
	if waves_launched == 6:
		# Imperial is ARMED here but must be bought from the ledger
		# (see _age4_tick) — the AI pays like the player for Age IV.
		age4_pending = true


## Imperial purchase + research: once wave 6 has launched and the
## AI is in Age III, the moment its ledger covers AGE4_UP_COST it
## pays and researches over AGE4_UP_TIME, then ages up. A side
## whose TC has fallen never starts (or finishes) the research.
func _age4_tick(delta: float) -> void:
	if int(game.team_age.get(1, 1)) >= 4:
		age4_pending = false
		age4_researching = false
		return
	if game.enemy_tc_destroyed:
		age4_pending = false
		age4_researching = false
		return
	if age4_researching:
		age4_timer -= delta
		if age4_timer <= 0.0:
			age4_researching = false
			age4_pending = false
			game.set_team_age(1, 4)
		return
	if age4_pending and int(game.team_age.get(1, 1)) == 3 \
			and _can_afford(Stats.AGE4_UP_COST):
		_pay(Stats.AGE4_UP_COST)
		age4_researching = true
		age4_timer = Stats.AGE4_UP_TIME
