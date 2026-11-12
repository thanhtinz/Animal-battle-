extends Node
## Focused 16b test: the medieval roster (Hiệp Sĩ Hoàng Gia /
## Chiến Binh Cuồng Nộ / Cung Thủ Tinh Anh / Pháp Sư Cung Đình /
## Thánh Kỵ Sĩ / Kỵ Sĩ Long / Sát Thủ Bóng Đêm / Nhà Thám Hiểm)
## — pool of 8, per-hero aura measured in the sim, the ONE
## skill's effect, the unified 75 s cooldown, the targeting
## matrix and the MP command shape.
## Run: godot --headless --path <proj> res://tests/test_heroes16b.tscn
##
## Pattern follows test_heroes14c.gd (retired with the old
## roster): one isolated main.tscn instance, the match hero
## reused as the test hero (auras read hero_of_team), slot_chars
## switched per section, the zone/flurry sim stepped directly.
## Twin of the (16b) section in test_main.gd, which stays the
## canonical suite.

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
	hero.shield_hp = 0.0
	hero.shield_t = 0.0
	hero.flurry_left = 0
	hero.flurry_t = 0.0
	hero.flurry_cursor = -1
	hero.eff_spd_mult = 1.0
	hero.eff_spd_t = 0.0
	hero.eff_dmg_mult = 1.0
	hero.eff_dmg_t = 0.0
	game.skill_zones.clear()
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
	# Pin slot 1's character: foe kings in the assassin phase
	# must not bring a mitigation/armour aura of their own.
	game.slot_chars[1] = "mage"
	# No king exists at SP boot (heroes are Castle-trained), and
	# the aura helpers read hero_of_team — so retire any stray
	# king and force-spawn THE test hero: he is then the only
	# team-0 king (team 1 has none until the assassin phase).
	for u in game.units.duplicate():
		if u.unit_type == "king":
			game.units.erase(u)
			u.queue_free()
	var anchor: Vector2i = game.world.nearest_walkable(
			game.player_tc.origin_cell + Vector2i(6, 6))
	var base: Vector2 = game.world.cell_center(anchor)
	var w_hero: Unit = game._make_unit(0, base, "king")
	w_hero.facing = "right"

	# ------------------------------------------------ Knight
	game.slot_chars[0] = "knight"
	_reset_hero(game, w_hero, base)
	# Aura Hộ Vệ: covered allies take x0.92 damage.
	var kn_ally := _ally(game, base + Vector2(48, 40))
	kn_ally.take_damage(100.0, null)
	check("knight aura: ally takes x0.92 damage inside 3 tiles",
			absf(kn_ally.hp - 908.0) < 0.01
			and game.hero_aura_covers(kn_ally, "knight", true),
			"ally=%s" % kn_ally.hp)
	# Skill Khiên Sư Tử: 250 shield (the x0.92 aura eats into the
	# absorb), military foes taunted, villagers not, CD 75.
	var kn_foe := _foe(game, base + Vector2(64, -40))
	var kn_vil: Unit = game._make_unit(1, base + Vector2(30, 70), "villager")
	var kn_ok: bool = game.cast_hero_skill(w_hero)
	w_hero.take_damage(100.0, null)
	check("knight skill: 250 shield absorbs, military taunted, CD 75",
			kn_ok and absf(w_hero.shield_hp - 158.0) < 0.01
			and absf(w_hero.hp - w_hero.max_hp) < 0.01
			and kn_foe.taunt_id == w_hero.net_id and kn_foe.taunt_t > 3.5
			and kn_foe._taunt_hero() == w_hero
			and kn_vil.taunt_t <= 0.0
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"shield=%s hp=%s taunt=%s cd=%s" % [w_hero.shield_hp, w_hero.hp,
					kn_foe.taunt_t, w_hero.skill_cd_t])

	# ------------------------------------------------ Berserker
	var b_base := base + Vector2(0, 260)
	game.slot_chars[0] = "berserker"
	_reset_hero(game, w_hero, b_base)
	# Aura Cuồng Chiến: allied military attack speed x1.10.
	var bk_ally := _ally(game, b_base + Vector2(48, 40))
	check("berserker aura: ally attack speed x1.10",
			absf(bk_ally.eff_atkspd_mult() - 1.10) < 0.01,
			"ally=%s" % bk_ally.eff_atkspd_mult())
	# Skill Rìu Xoáy: 110 to every enemy within 2 tiles only.
	var bk_f1 := _foe(game, b_base + Vector2(50, 0))
	var bk_f2 := _foe(game, b_base + Vector2(-40, 30))
	var bk_far := _foe(game, b_base + Vector2(110, 0))
	var bk_ok: bool = game.cast_hero_skill(w_hero)
	check("berserker skill: whirlwind 110 in 2 tiles, outside safe, CD 75",
			bk_ok and absf(bk_f1.hp - 890.0) < 0.01
			and absf(bk_f2.hp - 890.0) < 0.01
			and absf(bk_far.hp - 1000.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"f1=%s f2=%s far=%s" % [bk_f1.hp, bk_f2.hp, bk_far.hp])

	# ------------------------------------------------ Archer
	var a_base := base + Vector2(300, 260)
	game.slot_chars[0] = "archer"
	_reset_hero(game, w_hero, a_base)
	# Ranged frame: bow range 160, arrows fly.
	check("archer frame: attack range 160 (ranged kit)",
			absf(w_hero.attack_range() - 160.0) < 0.01,
			"range=%s" % w_hero.attack_range())
	# Aura Tiễn Thủ: allied military damage x1.08 (strike ratio).
	var ar_a1 := _ally(game, a_base + Vector2(40, 30))
	var ar_a2 := _ally(game, a_base + Vector2(400, 30))
	var ar_t1 := _foe(game, a_base + Vector2(70, 30))
	var ar_t2 := _foe(game, a_base + Vector2(430, 30))
	ar_a1.attack_target = ar_t1
	ar_a2.attack_target = ar_t2
	ar_a1.strike()
	ar_a2.strike()
	var ar_d1 := 1000.0 - ar_t1.hp
	var ar_d2 := 1000.0 - ar_t2.hp
	check("archer aura: covered ally strikes x1.08, far ally x1.0",
			ar_d2 > 0.0 and absf(ar_d1 - ar_d2 * 1.08) < 0.01,
			"near=%s far=%s" % [ar_d1, ar_d2])
	# Skill Mưa Tên: zone at the point, 3 waves x40, then gone.
	_reset_hero(game, w_hero, a_base)
	var ar_foe := _foe(game, a_base + Vector2(120, -60))
	var ar_ok: bool = game.cast_hero_skill(w_hero, ar_foe.global_position)
	for i in range(4):
		game._update_skill_zones(0.5)
	check("archer skill: arrow rain 3 waves x40 = 120, zone expires, CD 75",
			ar_ok and absf(ar_foe.hp - 880.0) < 0.01
			and game.skill_zones.is_empty()
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"foe=%s zones=%d" % [ar_foe.hp, game.skill_zones.size()])
	# Cast range clamps at 8 tiles.
	w_hero.skill_cd_t = 0.0
	game.cast_hero_skill(w_hero, a_base + Vector2(400, 0))
	check("archer skill: cast point clamps to 8 tiles",
			game.skill_zones.size() == 1
			and (game.skill_zones[0]["pos"] as Vector2).distance_to(a_base) <= 8.0 * World.TILE + 1.0,
			"zones=%d" % game.skill_zones.size())
	game.skill_zones.clear()

	# ------------------------------------------------ Mage
	var m_base := base + Vector2(-300, 260)
	game.slot_chars[0] = "mage"
	_reset_hero(game, w_hero, m_base)
	# Aura Ma Lực Hồi Lưu: +1.2 HP/s regen for covered allies.
	var mg_ally := _ally(game, m_base + Vector2(40, 30))
	mg_ally.hp = 500.0
	mg_ally._tick_effects(1.05)
	check("mage aura: covered ally regenerates +1.2 HP per second",
			absf(mg_ally.hp - 501.2) < 0.01, "hp=%s" % mg_ally.hp)
	# Skill Thiên Thạch: 120 in 2.5 tiles at the point.
	_reset_hero(game, w_hero, m_base)
	var mg_f1 := _foe(game, m_base + Vector2(150, 0))
	var mg_f2 := _foe(game, m_base + Vector2(190, 20))
	var mg_far := _foe(game, m_base + Vector2(150, 120))
	var mg_ok: bool = game.cast_hero_skill(w_hero, m_base + Vector2(160, 0))
	check("mage skill: meteor 120 in 2.5 tiles, outside safe, CD 75",
			mg_ok and absf(mg_f1.hp - 880.0) < 0.01
			and absf(mg_f2.hp - 880.0) < 0.01
			and absf(mg_far.hp - 1000.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"f1=%s f2=%s far=%s" % [mg_f1.hp, mg_f2.hp, mg_far.hp])

	# ------------------------------------------------ Paladin
	var p_base := base + Vector2(300, -260)
	game.slot_chars[0] = "paladin"
	_reset_hero(game, w_hero, p_base)
	# Aura Thánh Giáp: flat -3 per hit, at least 1 through.
	var pa_ally := _ally(game, p_base + Vector2(40, -40))
	pa_ally.take_damage(10.0, null)
	var pa_after10 := pa_ally.hp
	pa_ally.take_damage(2.0, null)
	check("paladin aura: hits reduced by flat 3, minimum 1 gets through",
			absf(pa_after10 - 993.0) < 0.01 and absf(pa_ally.hp - 992.0) < 0.01,
			"hp=%s" % pa_ally.hp)
	# Skill Thánh Quang: +160 heal in 3 tiles + cleanse.
	_reset_hero(game, w_hero, p_base)
	var pa_wound := _ally(game, p_base + Vector2(50, 20))
	pa_wound.hp = 30.0
	pa_wound.stun_t = 3.0
	w_hero.hp = 400.0
	var pa_foe := _foe(game, p_base + Vector2(60, -20))
	pa_foe.hp = 30.0
	var pa_ok: bool = game.cast_hero_skill(w_hero)
	check("paladin skill: heal 160 + cleanse allies, enemies unhealed, CD 75",
			pa_ok and absf(pa_wound.hp - 190.0) < 0.01
			and pa_wound.stun_t <= 0.0
			and absf(w_hero.hp - 560.0) < 0.01
			and absf(pa_foe.hp - 30.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"ally=%s hero=%s foe=%s" % [pa_wound.hp, w_hero.hp, pa_foe.hp])

	# ------------------------------------------------ Dragoon
	var d_base := base + Vector2(-300, -260)
	game.slot_chars[0] = "dragoon"
	_reset_hero(game, w_hero, d_base)
	w_hero.facing = "right"
	# Aura Long Hành: +10% move speed, allies and himself.
	var dr_ally := _ally(game, d_base + Vector2(40, 40))
	check("dragoon aura: ally + hero move speed x1.10",
			absf(game.hero_speed_factor(dr_ally) - 1.10) < 0.01
			and absf(game.hero_speed_factor(w_hero) - 1.10) < 0.01,
			"ally=%s hero=%s" % [game.hero_speed_factor(dr_ally),
					game.hero_speed_factor(w_hero)])
	# Skill Long Thương: dash to the point, 120 along the path.
	var dr_on := _foe(game, d_base + Vector2(80, 0))
	var dr_off := _foe(game, d_base + Vector2(80, 70))
	var dr_ok: bool = game.cast_hero_skill(w_hero, d_base + Vector2(160, 0))
	check("dragoon skill: dash lands, 120 on the path, off-path safe, CD 75",
			dr_ok and w_hero.global_position.distance_to(d_base + Vector2(160, 0)) < 24.0
			and absf(dr_on.hp - 880.0) < 0.01
			and absf(dr_off.hp - 1000.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"pos=%s on=%s off=%s" % [w_hero.global_position, dr_on.hp, dr_off.hp])
	# The dash clamps at 5 tiles.
	_reset_hero(game, w_hero, d_base)
	game.cast_hero_skill(w_hero, d_base + Vector2(300, 0))
	check("dragoon skill: dash clamps to 5 tiles",
			w_hero.global_position.distance_to(d_base) <= 5.0 * World.TILE + 24.0,
			"dist=%s" % w_hero.global_position.distance_to(d_base))

	# ------------------------------------------------ Assassin
	var s_base := base + Vector2(0, -420)
	game.slot_chars[0] = "assassin"
	_reset_hero(game, w_hero, s_base)
	# Aura Truy Sát: allied military deal x1.10 to enemy heroes.
	var as_a1 := _ally(game, s_base + Vector2(40, 30))
	var as_a2 := _ally(game, s_base + Vector2(400, 30))
	var as_k1: Unit = game._make_unit(1, s_base + Vector2(70, 30), "king")
	var as_k2: Unit = game._make_unit(1, s_base + Vector2(430, 30), "king")
	as_k1.hp = 10000.0
	as_k1.max_hp = 10000.0
	as_k2.hp = 10000.0
	as_k2.max_hp = 10000.0
	as_a1.attack_target = as_k1
	as_a2.attack_target = as_k2
	as_a1.strike()
	as_a2.strike()
	var as_d1 := 10000.0 - as_k1.hp
	var as_d2 := 10000.0 - as_k2.hp
	check("assassin aura: covered ally strikes x1.10 vs enemy heroes",
			as_d2 > 0.0 and absf(as_d1 - as_d2 * 1.10) < 0.01,
			"near=%s far=%s" % [as_d1, as_d2])
	# Skill Ám Sát: refuses beyond 6 tiles; blinks behind + 160.
	_reset_hero(game, w_hero, s_base)
	check("assassin skill: target beyond 6 tiles refused, no cooldown spent",
			not game.cast_hero_skill(w_hero, s_base + Vector2(224, 0))
			and w_hero.skill_cd_t <= 0.0, "cd=%s" % w_hero.skill_cd_t)
	var as_victim: Unit = game._make_unit(1, s_base + Vector2(150, 0), "king")
	var as_ok: bool = game.cast_hero_skill(w_hero, as_victim.global_position)
	check("assassin skill: blink behind the victim, 160 burst, CD 75",
			as_ok and absf(as_victim.hp - 490.0) < 0.01
			and w_hero.global_position.distance_to(as_victim.global_position) < 40.0
			and w_hero.global_position.x > as_victim.global_position.x
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"victim=%s herox=%s vx=%s" % [as_victim.hp,
					w_hero.global_position.x, as_victim.global_position.x])

	# ------------------------------------------------ Ranger
	var r_base := base + Vector2(420, 0)
	game.slot_chars[0] = "ranger"
	_reset_hero(game, w_hero, r_base)
	# Aura Viễn Thị: +1 sight for covered allies (fog reads it).
	var rg_ally := _ally(game, r_base + Vector2(40, 30))
	check("ranger aura: covers allies, kit grants +1 sight",
			game.hero_aura_covers(rg_ally, "ranger", true)
			and int(Stats.HERO_KITS["ranger"]["aura_sight"]) == 1,
			"covers=%s" % game.hero_aura_covers(rg_ally, "ranger", true))
	# Skill Kiếm Vũ: 5 slashes x32 round-robin over 3 foes.
	var rg_f1 := _foe(game, r_base + Vector2(40, 0))
	var rg_f2 := _foe(game, r_base + Vector2(-30, 40))
	var rg_f3 := _foe(game, r_base + Vector2(0, -50))
	var rg_ok: bool = game.cast_hero_skill(w_hero)
	for i in range(5):
		game._update_hero_flurries(0.21)
	check("ranger skill: 5 slashes x32 spread round-robin, CD 75",
			rg_ok and absf(rg_f1.hp - 936.0) < 0.01
			and absf(rg_f2.hp - 936.0) < 0.01
			and absf(rg_f3.hp - 968.0) < 0.01
			and w_hero.flurry_left == 0
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not game.cast_hero_skill(w_hero),
			"f=%s,%s,%s left=%s" % [rg_f1.hp, rg_f2.hp, rg_f3.hp, w_hero.flurry_left])

	# ------------------------------------------------ plumbing
	check("targeting matrix: rain/meteor/dash/blink targeted, the rest instant",
			game.skill_is_targeted("archer", 1) and game.skill_is_targeted("mage", 1)
			and game.skill_is_targeted("dragoon", 1) and game.skill_is_targeted("assassin", 1)
			and not game.skill_is_targeted("knight", 1)
			and not game.skill_is_targeted("berserker", 1)
			and not game.skill_is_targeted("paladin", 1)
			and not game.skill_is_targeted("ranger", 1)
			and not game.skill_is_targeted("archer", 2)
			and not game.skill_is_targeted("mage", 3), "")
	game.slot_chars[0] = "dragoon"
	_reset_hero(game, w_hero, base)
	w_hero.facing = "right"
	var mp_foe := _foe(game, base + Vector2(160, -120))
	var mp_t: bool = game._mp_apply_skill_cmd(0, {"u": w_hero.net_id, "s": 1,
			"x": mp_foe.global_position.x, "y": mp_foe.global_position.y})
	w_hero.skill_cd_t = 0.0
	var mp_u: bool = game._mp_apply_skill_cmd(0, {"u": w_hero.net_id, "s": 1})
	var mp_bad: bool = game._mp_apply_skill_cmd(0, {"u": w_hero.net_id, "s": 2,
			"x": mp_foe.global_position.x, "y": mp_foe.global_position.y})
	check("MP skill cmd: s=1 targeted + untargeted apply, s=2 rejected (one skill only)",
			mp_t and mp_u and not mp_bad and w_hero.skill_cd_t > 74.0,
			"cd=%s" % w_hero.skill_cd_t)

	remove_child(game)
	game.queue_free()
	await get_tree().process_frame
	if failures == 0:
		print("ALL PASS")
	else:
		print("FAILED: %d test(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
