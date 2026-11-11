extends Node
## Focused 13v skill-kit test (extracted twin of the (13v)
## section in test_main.gd, which stays the canonical suite).
## Run: godot --headless --path <proj> res://tests/test_skills13v.tscn

var failures := 0


func check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS: ", name)
	else:
		failures += 1
		print("FAIL: ", name, " | ", detail)


func _ready() -> void:
	# ------------------------------------------------ (13v) full skill kits: Chiêu 2 + Ulti
	# Isolated instance; heroes force-spawned per character, the
	# zone/shot sim stepped directly (same pattern as (ad)).
	var gameV = load("res://main.tscn").instantiate()
	add_child(gameV)
	await get_tree().process_frame
	await get_tree().process_frame
	gameV.enemy_ai.waves_enabled = false
	var v_anchor: Vector2i = gameV.world.nearest_walkable(gameV.player_tc.origin_cell + Vector2i(6, 6))
	var v_pos: Vector2 = gameV.world.cell_center(v_anchor)
	# --- Ngân Kỵ 2: Kiếm Khí wave travels the facing line.
	gameV.slot_chars[0] = "ngan_ky"
	var hv1: Unit = gameV._make_unit(0, v_pos, "king")
	hv1.facing = "right"
	var w_in: Unit = gameV._make_unit(1, v_pos + Vector2(100, 0), "militia")
	w_in.max_hp = 1000.0
	w_in.hp = 1000.0
	var w_out: Unit = gameV._make_unit(1, v_pos + Vector2(100, 90), "militia")
	w_out.max_hp = 1000.0
	w_out.hp = 1000.0
	var wok: bool = gameV.cast_hero_skill2(hv1, hv1.global_position)
	for i in range(6):
		gameV._update_skill_shots(0.1)
	check("v1 Kiếm Khí: wave hits enemies on the facing line only, CD 30s, recast refused",
			wok and absf(w_in.hp - 955.0) < 0.01 and absf(w_out.hp - 1000.0) < 0.01
			and absf(hv1.skill2_cd_t - 30.0) < 0.5
			and not gameV.cast_hero_skill2(hv1, hv1.global_position),
			"in=%s out=%s cd=%s" % [w_in.hp, w_out.hp, hv1.skill2_cd_t])
	# --- Ngân Kỵ 3: Vương Kiếm plunge — units + buildings + stun.
	# The building is anchored so its CENTRE is the cast point;
	# the foe stands just off the footprint, inside the radius.
	var vk_p: Vector2 = v_pos + Vector2(150, 10)
	var vk_sz: Vector2i = gameV.get_build_def("barracks").size
	var vk_cell: Vector2i = gameV.world.world_to_cell(vk_p) - vk_sz / 2
	var vk_bld: Building = gameV._spawn_building("barracks", 1, vk_cell, true)
	var vk_bhp := vk_bld.hp
	var vk_tgt: Vector2 = vk_bld.position + Vector2(vk_bld.size) * World.TILE * 0.5
	var vk_foe: Unit = gameV._make_unit(1, vk_tgt + Vector2(58, 0), "militia")
	vk_foe.max_hp = 1000.0
	vk_foe.hp = 1000.0
	check("v2 Vương Kiếm: 120 dmg + 1s stun on units, 250 on buildings, CD 120s",
			gameV.cast_hero_skill3(hv1, vk_tgt)
			and absf(vk_foe.hp - 880.0) < 0.01 and vk_foe.stun_t > 0.9
			and vk_foe.control_locked()
			and absf(vk_bld.hp - (vk_bhp - 250.0)) < 0.01
			and absf(hv1.skill3_cd_t - 120.0) < 0.5,
			"foe=%s stun=%s bld=%s/%s" % [vk_foe.hp, vk_foe.stun_t, vk_bld.hp, vk_bhp])
	gameV.units.erase(hv1)
	hv1.queue_free()
	gameV.skill_shots.clear()
	# --- Lam Bào 2: Thương Băng freezes the FIRST enemy on the path.
	gameV.slot_chars[0] = "lam_bao"
	var hv2: Unit = gameV._make_unit(0, v_pos + Vector2(0, -260), "king")
	hv2.facing = "right"
	var sp_a: Unit = gameV._make_unit(1, hv2.global_position + Vector2(70, 0), "militia")
	sp_a.max_hp = 1000.0
	sp_a.hp = 1000.0
	var sp_b: Unit = gameV._make_unit(1, hv2.global_position + Vector2(135, 0), "militia")
	sp_b.max_hp = 1000.0
	sp_b.hp = 1000.0
	var sok: bool = gameV.cast_hero_skill2(hv2, hv2.global_position)
	for i in range(6):
		gameV._update_skill_shots(0.1)
	check("v3 Thương Băng: both pierced take 35, only the first freezes 1.5s, CD 35s",
			sok and absf(sp_a.hp - 965.0) < 0.01 and absf(sp_b.hp - 965.0) < 0.01
			and sp_a.frozen_t > 1.0 and sp_b.frozen_t <= 0.0
			and sp_a.control_locked() and absf(hv2.skill2_cd_t - 35.0) < 0.5,
			"a=%s frz=%s b=%s frz=%s" % [sp_a.hp, sp_a.frozen_t, sp_b.hp, sp_b.frozen_t])
	sp_a._tick_effects(1.6)
	check("v4 freeze expires: control lock releases",
			sp_a.frozen_t <= 0.0 and not sp_a.control_locked(), "frz=%s" % sp_a.frozen_t)
	# --- Lam Bào 3: Băng Hà chills + DoTs units, freezes buildings.
	# Building centre = the cast point; foe just off the footprint.
	var bh_p: Vector2 = hv2.global_position + Vector2(140, 0)
	var bh_sz: Vector2i = gameV.get_build_def("barracks").size
	var bh_cell: Vector2i = gameV.world.world_to_cell(bh_p) - bh_sz / 2
	var bh_bld: Building = gameV._spawn_building("barracks", 1, bh_cell, true)
	var bh_tgt: Vector2 = bh_bld.position + Vector2(bh_bld.size) * World.TILE * 0.5
	var bh_foe: Unit = gameV._make_unit(1, bh_tgt + Vector2(55, 0), "militia")
	bh_foe.max_hp = 1000.0
	bh_foe.hp = 1000.0
	var bhok: bool = gameV.cast_hero_skill3(hv2, bh_tgt)
	bh_bld.train_types = ["militia"]
	bh_bld.train_queue = 1
	bh_bld.train_timer = 5.0
	gameV._update_skill_zones(0.5)
	bh_bld._process(1.0)
	check("v5 Băng Hà: enemy chilled x0.45 + DoT, building training frozen, CD 130s",
			bhok and bh_foe.chill_t > 0.0 and absf(bh_foe.hp - 995.0) < 0.01
			and absf(bh_foe.eff_speed_mult() - 0.45) < 0.01
			and gameV.building_frozen(bh_bld) and absf(bh_bld.train_timer - 5.0) < 0.01
			and absf(hv2.skill3_cd_t - 130.0) < 0.5,
			"foe=%s chill=%s spd=%s timer=%s" % [bh_foe.hp, bh_foe.chill_t,
					bh_foe.eff_speed_mult(), bh_bld.train_timer])
	gameV.units.erase(hv2)
	hv2.queue_free()
	gameV.skill_zones.clear()
	gameV.skill_shots.clear()
	# --- Kim Hoa 2: Hoa Vũ heals over time + cleanses slows.
	gameV.slot_chars[0] = "kim_hoa"
	var hv3: Unit = gameV._make_unit(0, v_pos + Vector2(0, -520), "king")
	var hr_ally: Unit = gameV._make_unit(0, hv3.global_position + Vector2(150, 0), "militia")
	hr_ally.max_hp = 1000.0
	hr_ally.hp = 500.0
	hr_ally.eff_spd_mult = 0.4
	hr_ally.eff_spd_t = 3.0
	var hrok: bool = gameV.cast_hero_skill2(hv3, hr_ally.global_position)
	gameV._update_skill_zones(0.5)
	check("v6 Hoa Vũ: sub-tick HoT +6 and slow cleansed, zone lives, CD 40s",
			hrok and absf(hr_ally.hp - 506.0) < 0.01 and hr_ally.eff_spd_t <= 0.0
			and gameV.skill_zones.size() == 1 and absf(hv3.skill2_cd_t - 40.0) < 0.5,
			"hp=%s spd_t=%s zones=%d" % [hr_ally.hp, hr_ally.eff_spd_t, gameV.skill_zones.size()])
	gameV._update_skill_zones(6.0)
	check("v7 Hoa Vũ zone expires after its duration",
			gameV.skill_zones.is_empty(), "zones=%d" % gameV.skill_zones.size())
	# --- Kim Hoa 3: Vạn Hoa — +200 heal in 4 tiles + 3s immunity.
	hr_ally.global_position = hv3.global_position + Vector2(100, 0)
	hr_ally.hp = 300.0
	hv3.hp = 400.0
	var vhok: bool = gameV.cast_hero_skill3(hv3, hv3.global_position)
	hr_ally.take_damage(50.0, null)
	check("v8 Vạn Hoa: +200 heal, immunity swallows the next hit, CD 150s",
			vhok and absf(hr_ally.hp - 500.0) < 0.01 and absf(hv3.hp - 600.0) < 0.01
			and hr_ally.immune_t > 2.5 and absf(hv3.skill3_cd_t - 150.0) < 0.5,
			"ally=%s hero=%s imm=%s" % [hr_ally.hp, hv3.hp, hr_ally.immune_t])
	gameV.units.erase(hv3)
	hv3.queue_free()
	# --- Bạch Sa 2: Phán Xét damages + cuts attack 30% for 5s.
	gameV.slot_chars[0] = "bach_sa"
	var hv4: Unit = gameV._make_unit(0, v_pos + Vector2(0, -780), "king")
	var pj_foe: Unit = gameV._make_unit(1, hv4.global_position + Vector2(120, 0), "militia")
	pj_foe.max_hp = 1000.0
	pj_foe.hp = 1000.0
	check("v9 Phán Xét: 55 dmg + attack x0.70 for 5s, CD 40s",
			gameV.cast_hero_skill2(hv4, pj_foe.global_position)
			and absf(pj_foe.hp - 945.0) < 0.01
			and absf(pj_foe.atk_down_mult - 0.70) < 0.01 and pj_foe.atk_down_t > 4.5
			and absf(hv4.skill2_cd_t - 40.0) < 0.5,
			"foe=%s mult=%s t=%s" % [pj_foe.hp, pj_foe.atk_down_mult, pj_foe.atk_down_t])
	# --- Bạch Sa 3: Thiên Màn dome shields allies, buildings immune.
	# Building centre = the cast point; the ally stands inside the
	# dome but OUTSIDE the hero's aura (so the absorb math is the
	# shield's alone, not aura-discounted).
	var dm_p: Vector2 = hv4.global_position + Vector2(110, 0)
	var dm_sz: Vector2i = gameV.get_build_def("barracks").size
	var dm_cell: Vector2i = gameV.world.world_to_cell(dm_p) - dm_sz / 2
	var dm_bld: Building = gameV._spawn_building("barracks", 0, dm_cell, true)
	var dm_bhp := dm_bld.hp
	var dm_c: Vector2 = dm_bld.position + Vector2(dm_bld.size) * World.TILE * 0.5
	var dm_ally: Unit = gameV._make_unit(0, dm_c + Vector2(30, 20), "militia")
	dm_ally.max_hp = 1000.0
	dm_ally.hp = 800.0
	var dmok: bool = gameV.cast_hero_skill3(hv4, dm_c)
	gameV._update_skill_zones(0.5)
	dm_ally.take_damage(50.0, null)
	dm_bld.take_damage(80.0, null)
	check("v10 Thiên Màn: shield 120 absorbs, building takes 0 damage, CD 150s",
			dmok and absf(dm_ally.hp - 800.0) < 0.01 and absf(dm_ally.shield_hp - 70.0) < 0.01
			and absf(dm_bld.hp - dm_bhp) < 0.01 and gameV.building_dome_protected(dm_bld)
			and absf(hv4.skill3_cd_t - 150.0) < 0.5,
			"ally=%s sh=%s bld=%s/%s" % [dm_ally.hp, dm_ally.shield_hp, dm_bld.hp, dm_bhp])
	# --- MP command shape: extended validator routes s=2/3, and
	# rejects a cast claimed for another slot's hero.
	hv4.skill2_cd_t = 0.0
	check("v11 MP skill cmd: s=2 applies for the owner, foreign claim refused",
			gameV._mp_apply_skill_cmd(0, {"u": hv4.net_id, "s": 2,
					"x": pj_foe.global_position.x, "y": pj_foe.global_position.y})
			and hv4.skill2_cd_t > 39.0
			and not gameV._mp_apply_skill_cmd(1, {"u": hv4.net_id, "s": 2}),
			"cd2=%s" % hv4.skill2_cd_t)
	check("v12 targeting matrix: wave + Vạn Hoa instant, the rest ground-targeted",
			not gameV.skill_is_targeted("ngan_ky", 2) and gameV.skill_is_targeted("ngan_ky", 3)
			and gameV.skill_is_targeted("kim_hoa", 2) and not gameV.skill_is_targeted("kim_hoa", 3)
			and gameV.skill_is_targeted("lam_bao", 3) and gameV.skill_is_targeted("bach_sa", 2),
			"")
	remove_child(gameV)
	gameV.queue_free()
	await get_tree().process_frame


	if failures == 0:
		print("ALL PASS")
	else:
		print("FAILED: %d test(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
