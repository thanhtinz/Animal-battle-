extends Node
## Focused 14c test: the four new heroes (Lôi Chấn / Xích Diệm /
## Phong Linh / Thạch Sơn) — roster of 8, auras, all 12 skills,
## the stone wall's pathing + expiry, cyclone determinism.
## Run: godot --headless --path <proj> res://tests/test_heroes14c.tscn
##
## Pattern follows test_skills13v.gd: one isolated main.tscn
## instance, the MATCH hero reused as the test hero (auras read
## hero_of_team, so the spawned king must be the real one),
## slot_chars switched per section, the zone/wall sim stepped
## directly. The enemy match hero is parked as ngan_ky far away
## so its aura never leaks into a measurement.

var failures := 0


func check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS: ", name)
	else:
		failures += 1
		print("FAIL: ", name, " | ", detail)


func _foe(game, pos: Vector2, hp: float = 1000.0) -> Unit:
	var u: Unit = game._make_unit(1, pos, "militia")
	u.max_hp = hp
	u.hp = hp
	return u


func _ally(game, pos: Vector2, hp: float = 1000.0) -> Unit:
	var u: Unit = game._make_unit(0, pos, "militia")
	u.max_hp = hp
	u.hp = hp
	return u


func _reset_hero(game, hero: Unit, pos: Vector2) -> void:
	hero.global_position = pos
	hero.hp = hero.max_hp
	hero.skill_cd_t = 0.0
	hero.skill2_cd_t = 0.0
	hero.skill3_cd_t = 0.0
	hero.eff_spd_mult = 1.0
	hero.eff_spd_t = 0.0
	hero.eff_dmg_mult = 1.0
	hero.eff_dmg_t = 0.0
	game.skill_zones.clear()
	game.skill_shots.clear()
	game.projectiles.clear()


func _ready() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	# ------------------------------------------------ roster of 8
	var seen := {}
	var rng := RandomNumberGenerator.new()
	for s in range(400):
		rng.seed = s * 7919 + 13
		seen[game.draw_character(rng)] = true
	check("pool of 8: every hero reachable by the draw, none outside",
			seen.size() == 8, "seen=%s" % [seen.keys()])
	game.enemy_ai.waves_enabled = false
	# No king exists at SP boot (heroes are Castle-trained), and
	# the aura helpers read hero_of_team — so retire any stray
	# king and force-spawn THE test hero, like the (ad) section:
	# he is then the only team-0 king, and team 1 has none (its
	# aura lookups all come back false).
	for u in game.units.duplicate():
		if u.unit_type == "king":
			game.units.erase(u)
			u.queue_free()
	var anchor: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(6, 6))
	var base: Vector2 = game.world.cell_center(anchor)
	var hero: Unit = game._make_unit(0, base, "king")
	hero.facing = "right"

	# ------------------------------------------------ Lôi Chấn
	game.slot_chars[0] = "loi_chan"
	_reset_hero(game, hero, base)
	# Aura: allied military attack speed x1.12; enemies unaffected.
	var lc_ally := _ally(game, base + Vector2(48, 40))
	var lc_foe_far := _foe(game, base + Vector2(48, -200))
	check("loi aura: ally atk speed x1.12, enemy at range unaffected",
			absf(lc_ally.eff_atkspd_mult() - 1.12) < 0.01
			and absf(lc_foe_far.eff_atkspd_mult() - 1.0) < 0.01,
			"ally=%s foe=%s" % [lc_ally.eff_atkspd_mult(), lc_foe_far.eff_atkspd_mult()])
	# C1 Lôi Độn: dash 5 tiles, 40 landing dmg, +20% speed 4 s.
	var lc_land := _foe(game, base + Vector2(160, 0))
	var dash_ok: bool = game.cast_hero_skill(hero, base + Vector2(160, 0))
	check("loi C1: dash lands on the point, 40 dmg, speed buff, CD 50",
			dash_ok and hero.global_position.distance_to(base + Vector2(160, 0)) < 24.0
			and absf(lc_land.hp - 960.0) < 0.01
			and absf(hero.eff_spd_mult - 1.2) < 0.01 and hero.eff_spd_t > 3.5
			and absf(hero.skill_cd_t - 50.0) < 0.5,
			"pos=%s foe=%s buff=%s/%s cd=%s" % [hero.global_position, lc_land.hp,
					hero.eff_spd_mult, hero.eff_spd_t, hero.skill_cd_t])
	# C2 chain lightning: 55 then 3 bounces of 30.
	_reset_hero(game, hero, base)
	var chain: Array = []
	for i in range(4):
		chain.append(_foe(game, base + Vector2(96 + i * 48, 64)))
	var chain_ok: bool = game.cast_hero_skill2(hero, chain[0].global_position)
	check("loi C2: chain 55 + 3 bounces x30, CD 35",
			chain_ok and absf(chain[0].hp - 945.0) < 0.01
			and absf(chain[1].hp - 970.0) < 0.01 and absf(chain[2].hp - 970.0) < 0.01
			and absf(chain[3].hp - 970.0) < 0.01
			and absf(hero.skill2_cd_t - 35.0) < 0.5,
			"hps=%s,%s,%s,%s" % [chain[0].hp, chain[1].hp, chain[2].hp, chain[3].hp])
	# C3 storm zone: slow every sub-tick, 45 dmg + 22.5 building
	# every 1 s.
	_reset_hero(game, hero, base)
	var st_foe := _foe(game, base + Vector2(64, -64))
	var st_bld: Building = game._spawn_building("house", 1,
			game.world.world_to_cell(base + Vector2(-64, -64)), true)
	var st_bhp := st_bld.hp
	var storm_ok: bool = game.cast_hero_skill3(hero, base + Vector2(0, -64))
	game._update_skill_zones(0.5)
	var slow_after_1: float = st_foe.eff_spd_mult
	game._update_skill_zones(0.5)
	check("loi C3: storm slows x0.80, strikes 45/s, buildings 50%, CD 130",
			storm_ok and absf(slow_after_1 - 0.8) < 0.01
			and absf(st_foe.hp - 955.0) < 0.01
			and absf(st_bld.hp - (st_bhp - 22.5)) < 0.01
			and absf(hero.skill3_cd_t - 130.0) < 0.5,
			"slow=%s foe=%s bld=%s/%s" % [slow_after_1, st_foe.hp, st_bld.hp, st_bhp])
	game.skill_zones.clear()

	# ------------------------------------------------ Xích Diệm
	game.slot_chars[0] = "xich_diem"
	_reset_hero(game, hero, base)
	# Aura burn: an ally's hit sets the target burning (3/0.5s x2s).
	var xd_ally := _ally(game, base + Vector2(40, 30))
	var xd_foe := _foe(game, base + Vector2(120, 30))
	xd_ally.attack_target = xd_foe
	xd_ally.strike()
	var burn_set: bool = xd_foe.burn_t > 1.9 and xd_foe.burn_ticks == 4
	var hp_after_hit := xd_foe.hp
	for i in range(4):
		xd_foe._tick_effects(0.5)
	check("xich aura: ally hit applies burn, 4 ticks x3 = 12 over 2s",
			burn_set and absf(xd_foe.hp - (hp_after_hit - 12.0)) < 0.01
			and xd_foe.burn_t <= 0.0,
			"burn_t set=%s hp %s -> %s" % [burn_set, hp_after_hit, xd_foe.hp])
	# C1 Hỏa Ấn: explodes after 2 s for 70 in r1.5; refuses out of range.
	_reset_hero(game, hero, base)
	var mk_foe := _foe(game, base + Vector2(128, 0))
	var mk_by := _foe(game, base + Vector2(160, 0))
	var mk_ally := _ally(game, base + Vector2(144, 20))
	var mark_ok: bool = game.cast_hero_skill(hero, mk_foe.global_position)
	mk_foe._tick_effects(1.0)
	var quiet: bool = absf(mk_foe.hp - 1000.0) < 0.01
	mk_foe._tick_effects(1.0)
	check("xich C1: mark quiet at 1s, explodes 70 r1.5 at 2s, allies safe, CD 60",
			mark_ok and quiet and absf(mk_foe.hp - 930.0) < 0.01
			and absf(mk_by.hp - 930.0) < 0.01 and absf(mk_ally.hp - 1000.0) < 0.01
			and absf(hero.skill_cd_t - 60.0) < 0.5,
			"foe=%s by=%s ally=%s" % [mk_foe.hp, mk_by.hp, mk_ally.hp])
	hero.skill_cd_t = 0.0
	check("xich C1: cast beyond 6 tiles refused, no cooldown spent",
			not game.cast_hero_skill(hero, base + Vector2(900, 0))
			and hero.skill_cd_t <= 0.0, "cd=%s" % hero.skill_cd_t)
	# Mark detonates on death too.
	var mk2_foe := _foe(game, base + Vector2(96, 80))
	var mk2_by := _foe(game, base + Vector2(120, 80))
	game.cast_hero_skill(hero, mk2_foe.global_position)
	mk2_foe.take_damage(99999.0, null)
	check("xich C1: mark detonates when the bearer dies",
			mk2_foe.state == "dead" and absf(mk2_by.hp - 930.0) < 0.01,
			"by=%s" % mk2_by.hp)
	# C2 cone: front 120 degrees burns, behind is safe.
	_reset_hero(game, hero, base)
	hero.facing = "right"
	var cn_front := _foe(game, base + Vector2(64, 0))
	var cn_diag := _foe(game, base + Vector2(56, 56))
	var cn_back := _foe(game, base + Vector2(-64, 0))
	var cone_ok: bool = game.cast_hero_skill2(hero, hero.global_position)
	check("xich C2: cone hits front + diagonal (50 + burn), spares the back, CD 35",
			cone_ok and absf(cn_front.hp - 950.0) < 0.01 and cn_front.burn_ticks == 6
			and absf(cn_diag.hp - 950.0) < 0.01
			and absf(cn_back.hp - 1000.0) < 0.01
			and absf(hero.skill2_cd_t - 35.0) < 0.5,
			"f=%s d=%s b=%s" % [cn_front.hp, cn_diag.hp, cn_back.hp])
	# C3 phoenix: 130 units / 150 buildings + burning ground.
	_reset_hero(game, hero, base)
	var ph_foe := _foe(game, base + Vector2(200, -200))
	var ph_sz: Vector2i = game.get_build_def("barracks").size
	var ph_cell: Vector2i = game.world.world_to_cell(ph_foe.global_position) - ph_sz / 2
	var ph_bld: Building = game._spawn_building("barracks", 1, ph_cell, true)
	var ph_bc: Vector2 = ph_bld.position + Vector2(ph_bld.size) * World.TILE * 0.5
	ph_foe.global_position = ph_bc + Vector2(58, 0)
	var ph_bhp := ph_bld.hp
	_reset_hero(game, hero, ph_bc + Vector2(-80, 30))
	var ph_ok: bool = game.cast_hero_skill3(hero, ph_bc)
	game._update_skill_zones(0.5)
	check("xich C3: 130 on units, 150 on buildings, ground burns 12/0.5s, CD 140",
			ph_ok and absf(ph_foe.hp - (1000.0 - 130.0 - 12.0)) < 0.01
			and absf(ph_bld.hp - (ph_bhp - 150.0)) < 0.01
			and absf(hero.skill3_cd_t - 140.0) < 0.5,
			"foe=%s bld=%s/%s" % [ph_foe.hp, ph_bld.hp, ph_bhp])
	game.skill_zones.clear()

	# ------------------------------------------------ Phong Linh
	game.slot_chars[0] = "phong_linh"
	_reset_hero(game, hero, base)
	# Ranged basic attack: bow range 160, arrow flies and lands.
	var rg_foe := _foe(game, base + Vector2(128, 0))
	var rg_dmg := Stats.damage("king", rg_foe, 1)
	hero.attack_target = rg_foe
	hero.strike()
	for i in range(8):
		game._update_projectiles(0.1)
	check("phong basic: bow range 160 (vs 44 melee), arrow deals full damage at 4 tiles",
			absf(hero.attack_range() - 160.0) < 0.01
			and absf(rg_foe.hp - (1000.0 - rg_dmg)) < 0.01,
			"range=%s foe=%s dmg=%s" % [hero.attack_range(), rg_foe.hp, rg_dmg])
	# Aura: +12% move speed for allies AND herself.
	var pl_ally := _ally(game, base + Vector2(40, 60))
	check("phong aura: ally + hero move speed x1.12",
			absf(game.hero_speed_factor(pl_ally) - 1.12) < 0.01
			and absf(game.hero_speed_factor(hero) - 1.12) < 0.01,
			"ally=%s hero=%s" % [game.hero_speed_factor(pl_ally),
					game.hero_speed_factor(hero)])
	# C1 snipe: only the chosen target, a blocker in between is fine.
	_reset_hero(game, hero, base)
	var sn_block := _foe(game, base + Vector2(64, 120))
	var sn_tgt := _foe(game, base + Vector2(192, 120))
	var sn_ok: bool = game.cast_hero_skill(hero, sn_tgt.global_position)
	check("phong C1: snipe hits only the target for 75, blocker untouched, CD 45",
			sn_ok and absf(sn_tgt.hp - 925.0) < 0.01
			and absf(sn_block.hp - 1000.0) < 0.01
			and absf(hero.skill_cd_t - 45.0) < 0.5,
			"tgt=%s blk=%s" % [sn_tgt.hp, sn_block.hp])
	# C2 arrow rain: 3 waves of 20 over 3 s, then the zone is gone.
	_reset_hero(game, hero, base)
	var ar_foe := _foe(game, base + Vector2(48, -120))
	var ar_ok: bool = game.cast_hero_skill2(hero, ar_foe.global_position)
	for i in range(6):
		game._update_skill_zones(0.5)
	check("phong C2: arrow rain 3 waves x20 = 60, zone expires, CD 30",
			ar_ok and absf(ar_foe.hp - 940.0) < 0.01 and game.skill_zones.is_empty()
			and absf(hero.skill2_cd_t - 30.0) < 0.5,
			"foe=%s zones=%d" % [ar_foe.hp, game.skill_zones.size()])
	# C3 cyclone: pull is a fixed 16 px per sub-tick — run the
	# same setup twice and demand identical displacement.
	_reset_hero(game, hero, base)
	var cy_centre := base + Vector2(0, 140)
	var cy_foe := _foe(game, cy_centre + Vector2(96, 0))
	var cy_ok: bool = game.cast_hero_skill3(hero, cy_centre)
	var dists_a: Array = []
	for i in range(4):
		game._update_skill_zones(0.5)
		dists_a.append(cy_foe.global_position.distance_to(cy_centre))
	var cy_hp_a := cy_foe.hp
	var cy_atk: float = cy_foe.atk_down_mult
	game.skill_zones.clear()
	cy_foe.global_position = cy_centre + Vector2(96, 0)
	cy_foe.hp = 1000.0
	hero.skill3_cd_t = 0.0
	game.cast_hero_skill3(hero, cy_centre)
	var dists_b: Array = []
	for i in range(4):
		game._update_skill_zones(0.5)
		dists_b.append(cy_foe.global_position.distance_to(cy_centre))
	check("phong C3: cyclone pulls 16px/sub-tick deterministically, 15 dmg + atk x0.70",
			cy_ok and dists_a == dists_b
			and absf(dists_a[0] - 80.0) < 0.01 and absf(dists_a[3] - 32.0) < 0.01
			and absf(cy_hp_a - (1000.0 - 60.0)) < 0.01 and absf(cy_atk - 0.7) < 0.01
			and absf(hero.skill3_cd_t - 120.0) < 0.5,
			"a=%s b=%s hp=%s" % [dists_a, dists_b, cy_hp_a])
	game.skill_zones.clear()

	# ------------------------------------------------ Thạch Sơn
	game.slot_chars[0] = "thach_son"
	_reset_hero(game, hero, base)
	# Aura armour: flat -3 per hit, minimum 1 through.
	var ts_ally := _ally(game, base + Vector2(40, -40))
	var ts_src := _foe(game, base + Vector2(300, -40))
	ts_ally.take_damage(10.0, ts_src)
	var after_10 := ts_ally.hp
	ts_ally.take_damage(2.0, ts_src)
	check("thach aura: hits reduced by flat 3, minimum 1 gets through",
			absf(after_10 - 993.0) < 0.01 and absf(ts_ally.hp - 992.0) < 0.01,
			"hp=%s" % ts_ally.hp)
	# C1 leap slam: lands on the point, 40 dmg r2, knockback + slow.
	# The foe stands on a scanned-clear cell with a clear cell to
	# its east, so the 1-tile knockback lane is open on any layout.
	var lp_cell := Vector2i(-1, -1)
	var lp_bc: Vector2i = game.world.world_to_cell(base)
	for dx in range(-4, 7):
		for dy in range(-4, 5):
			var cand := lp_bc + Vector2i(dx, dy)
			if game._skill_wall_cell_ok(cand) and game._skill_wall_cell_ok(cand + Vector2i(1, 0)) \
					and game._skill_wall_cell_ok(cand + Vector2i(-3, 0)):
				lp_cell = cand
				break
		if lp_cell.x >= 0:
			break
	_reset_hero(game, hero, game.world.cell_center(lp_cell + Vector2i(-3, 0)))
	hero.facing = "right"
	var lp_tgt: Vector2 = game.world.cell_center(lp_cell)
	var lp_foe := _foe(game, lp_tgt)
	var lp_ok: bool = game.cast_hero_skill(hero, lp_tgt)
	check("thach C1: leap lands, 40 dmg, knockback 1 tile + 30% slow 2s, CD 55",
			lp_cell.x >= 0 and lp_ok
			and hero.global_position.distance_to(lp_tgt) < 24.0
			and absf(lp_foe.hp - 960.0) < 0.01
			and absf(lp_foe.global_position.x - (lp_tgt.x + World.TILE)) < 1.0
			and absf(lp_foe.eff_spd_mult - 0.7) < 0.01 and lp_foe.eff_spd_t > 1.5
			and absf(hero.skill_cd_t - 55.0) < 0.5,
			"foe=%s foepos=%s slow=%s" % [lp_foe.hp, lp_foe.global_position,
					lp_foe.eff_spd_mult])
	# C2 stone wall: find a clear 3-cell vertical run near base.
	_reset_hero(game, hero, base)
	hero.facing = "right"
	var wall_centre := Vector2i(-1, -1)
	var bc: Vector2i = game.world.world_to_cell(base)
	for dx in range(-4, 7):
		for dy in range(-4, 5):
			var cand := bc + Vector2i(dx, dy)
			if game._skill_wall_cell_ok(cand) and game._skill_wall_cell_ok(cand + Vector2i(0, -1)) \
					and game._skill_wall_cell_ok(cand + Vector2i(0, 1)):
				wall_centre = cand
				break
		if wall_centre.x >= 0:
			break
	var stand_foe := _foe(game, game.world.cell_center(wall_centre))
	var razed0: int = int(game._stat_rec(0).get("razed", 0))
	var blost1: int = int(game._stat_rec(1).get("blost", 0))
	_reset_hero(game, hero, game.world.cell_center(wall_centre + Vector2i(-2, 0)))
	hero.facing = "right"
	var wall_ok: bool = game.cast_hero_skill2(hero, game.world.cell_center(wall_centre))
	var walls: Array = game.buildings.filter(func(b): return b.btype == "skillwall")
	var wpath: Array = game.world.get_path_cells(wall_centre + Vector2i(-2, 0),
			wall_centre + Vector2i(2, 0), 0)
	var through: bool = wpath.has(wall_centre) or wpath.has(wall_centre + Vector2i(0, -1)) \
			or wpath.has(wall_centre + Vector2i(0, 1))
	check("thach C2: 3 wall cells raised solid, unit pushed off, path detours, CD 40",
			wall_centre.x >= 0 and wall_ok and walls.size() == 3
			and game.world.is_solid(wall_centre)
			and game.world.world_to_cell(stand_foe.global_position) != wall_centre
			and not wpath.is_empty() and not through
			and absf(hero.skill2_cd_t - 40.0) < 0.5,
			"cells=%d path=%d through=%s" % [walls.size(), wpath.size(), through])
	game._update_skill_walls(12.5)
	check("thach C2: wall expires after 12s — cells freed, no raze/loss credit",
			game.buildings.filter(func(b): return b.btype == "skillwall").is_empty()
			and not game.world.is_solid(wall_centre) and game.skill_wall_timers.is_empty()
			and int(game._stat_rec(0).get("razed", 0)) == razed0
			and int(game._stat_rec(1).get("blost", 0)) == blost1,
			"timers=%s" % [game.skill_wall_timers])
	# C3 quake: 90 units / 300 buildings + 40% slow 3 s.
	_reset_hero(game, hero, base)
	var qk_foe := _foe(game, base + Vector2(220, 160))
	var qk_sz: Vector2i = game.get_build_def("barracks").size
	var qk_cell: Vector2i = game.world.world_to_cell(qk_foe.global_position) - qk_sz / 2
	var qk_bld: Building = game._spawn_building("barracks", 1, qk_cell, true)
	var qk_bc: Vector2 = qk_bld.position + Vector2(qk_bld.size) * World.TILE * 0.5
	qk_foe.global_position = qk_bc + Vector2(58, 0)
	var qk_bhp := qk_bld.hp
	_reset_hero(game, hero, qk_bc + Vector2(-80, 30))
	var qk_ok: bool = game.cast_hero_skill3(hero, qk_bc)
	check("thach C3: quake 90 on units, 300 on buildings, slow x0.60 3s, CD 150",
			qk_ok and absf(qk_foe.hp - 910.0) < 0.01
			and absf(qk_bld.hp - (qk_bhp - 300.0)) < 0.01
			and absf(qk_foe.eff_spd_mult - 0.6) < 0.01 and qk_foe.eff_spd_t > 2.5
			and absf(hero.skill3_cd_t - 150.0) < 0.5,
			"foe=%s bld=%s/%s" % [qk_foe.hp, qk_bld.hp, qk_bhp])

	# ------------------------------------------------ plumbing
	game.slot_chars[0] = "loi_chan"
	_reset_hero(game, hero, base)
	var mp_foe := _foe(game, base + Vector2(160, -120))
	var mp_t: bool = game._mp_apply_skill_cmd(0, {"u": hero.net_id, "s": 1,
			"x": mp_foe.global_position.x, "y": mp_foe.global_position.y})
	hero.skill_cd_t = 0.0
	var mp_u: bool = game._mp_apply_skill_cmd(0, {"u": hero.net_id, "s": 1})
	check("MP skill cmd s=1: with a target it dashes there, without one it still casts",
			mp_t and mp_u and hero.skill_cd_t > 49.0, "cd=%s" % hero.skill_cd_t)
	check("targeting matrix: new Chiêu 1 all targeted, xich cone instant, all Ultis targeted",
			game.skill_is_targeted("loi_chan", 1) and game.skill_is_targeted("loi_chan", 2)
			and game.skill_is_targeted("loi_chan", 3) and game.skill_is_targeted("xich_diem", 1)
			and not game.skill_is_targeted("xich_diem", 2)
			and game.skill_is_targeted("xich_diem", 3)
			and game.skill_is_targeted("phong_linh", 1) and game.skill_is_targeted("phong_linh", 2)
			and game.skill_is_targeted("phong_linh", 3)
			and game.skill_is_targeted("thach_son", 1) and game.skill_is_targeted("thach_son", 2)
			and game.skill_is_targeted("thach_son", 3), "")
	remove_child(game)
	game.queue_free()
	await get_tree().process_frame


	if failures == 0:
		print("ALL PASS")
	else:
		print("FAILED: %d test(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
