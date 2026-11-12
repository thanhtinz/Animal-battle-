extends Node
## Headless functional tests for the Empire Age P2 prototype.
## Run: godot --headless --path <proj> res://tests/test_main.tscn
## Prints PASS/FAIL per test and a final ALL PASS line.

var failures := 0
var game = null


func check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS: ", name)
	else:
		failures += 1
		print("FAIL: ", name, " | ", detail)


func wait_until(cond: Callable, timeout_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func player_units() -> Array:
	var out: Array = []
	for u in game.units:
		if u.team == 0:
			out.append(u)
	return out


func stop_all_units() -> void:
	for u in player_units():
		u.state = "idle"
		u.path.clear()
		u.target_node = null
		u.target_site = null


## First origin (ring scan out from `near`) where a `size` footprint fits.
func find_spot(size: Vector2i, near: Vector2i) -> Vector2i:
	for r in range(0, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := near + Vector2i(dx, dy)
				if game.world.can_place(cand, size):
					return cand
	return Vector2i(-1, -1)


## (h, s, v) of a colour, each in 0..1 (test-local, no engine HSV).
func hsv_of(c: Color) -> Vector3:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var d := mx - mn
	var h := 0.0
	if d > 0.0001:
		if mx == c.r:
			h = fmod((c.g - c.b) / d, 6.0)
		elif mx == c.g:
			h = (c.b - c.r) / d + 2.0
		else:
			h = (c.r - c.g) / d + 4.0
		h /= 6.0
		if h < 0.0:
			h += 1.0
	var s := 0.0 if mx <= 0.0001 else d / mx
	return Vector3(h, s, mx)


## Palette-survey a coloured set against the canonical slot-0 art:
## every pixel in the red hue band must land inside the slot's hue
## family; every warm neutral (skin/hair/wood) and every other
## opaque pixel must be PIXEL-IDENTICAL — the "same sprites, only
## the faction parts change colour" rule, measured. Returns
## [ok, detail]. `stride` subsamples big sheets.
func palette_survey(path0: String, pathN: String, slot: int, stride: int) -> Array:
	# Survey the RAW asset files, not the imported textures: the
	# importer's fix_alpha_border bleeds colours across alpha edges
	# (identically for every set, but it would pollute exact counts).
	var img0 := Image.load_from_file(path0)
	var imgN := Image.load_from_file(pathN)
	if img0 == null or imgN == null or img0.is_empty() or imgN.is_empty():
		return [false, "raw image load failed"]
	img0.convert(Image.FORMAT_RGBA8)
	imgN.convert(Image.FORMAT_RGBA8)
	if img0.get_size() != imgN.get_size():
		return [false, "size mismatch %s vs %s" % [img0.get_size(), imgN.get_size()]]
	var fam := Vector2(0.52, 0.70) # slot 1 blue
	if slot == 2:
		fam = Vector2(0.24, 0.48) # green
	elif slot == 3:
		fam = Vector2(0.09, 0.21) # yellow/amber
	var band := 0
	var band_ok := 0
	var neutral := 0
	var neutral_ok := 0
	var other := 0
	var other_ok := 0
	for y in range(0, img0.get_height(), stride):
		for x in range(0, img0.get_width(), stride):
			var c0 := img0.get_pixel(x, y)
			if c0.a < 0.9:
				continue
			var cn := imgN.get_pixel(x, y)
			var hsv := hsv_of(c0)
			# Guard zone: the generator cut its band in float64; this
			# survey computes in float32, so pixels within a hair of
			# the band edges / saturation floor are unclassifiable
			# and exempt from every bucket.
			if minf(absf(hsv.x - 0.045), absf(hsv.x - 0.955)) < 0.004 \
					or absf(hsv.y - 0.28) < 0.02:
				continue
			if hsv.y >= 0.28 and (hsv.x <= 0.045 or hsv.x >= 0.955) and hsv.z < 0.03:
				# Near-black quantization dust (e.g. RGB (7,1,1)): at
				# value < 3% there are not enough bits to hold a hue —
				# it must simply stay as dark in the recoloured set
				# (brightest channel no higher than the source's).
				band += 1
				if maxi(maxi(cn.r8, cn.g8), cn.b8) <= maxi(maxi(c0.r8, c0.g8), c0.b8) + 1 \
						and cn.a8 == c0.a8:
					band_ok += 1
			elif hsv.y >= 0.28 and (hsv.x <= 0.045 or hsv.x >= 0.955):
				band += 1
				var hn := hsv_of(cn).x
				if hn >= fam.x and hn <= fam.y:
					band_ok += 1
			elif hsv.x >= 0.03 and hsv.x <= 0.13 and hsv.y >= 0.15 \
					and hsv.y <= 0.65 and hsv.z >= 0.55:
				neutral += 1
				if cn == c0:
					neutral_ok += 1
			else:
				other += 1
				if cn == c0:
					other_ok += 1
	var ok := band > 100 and band_ok == band and neutral > 20 \
			and neutral_ok == neutral and other_ok == other
	return [ok, "band %d/%d neutral %d/%d other %d/%d"
			% [band_ok, band, neutral_ok, neutral, other_ok, other]]



func w_foe(game, pos: Vector2, hp: float = 1000.0) -> Unit:
	var u: Unit = game._make_unit(1, pos, "militia")
	u.max_hp = hp
	u.hp = hp
	return u


func w_ally(game, pos: Vector2, hp: float = 1000.0) -> Unit:
	var u: Unit = game._make_unit(0, pos, "militia")
	u.max_hp = hp
	u.hp = hp
	return u


func w_reset_hero(game, w_hero: Unit, pos: Vector2) -> void:
	w_hero.global_position = pos
	w_hero.hp = w_hero.max_hp
	w_hero.skill_cd_t = 0.0
	w_hero.shield_hp = 0.0
	w_hero.shield_t = 0.0
	w_hero.flurry_left = 0
	w_hero.flurry_t = 0.0
	w_hero.flurry_cursor = -1
	w_hero.eff_spd_mult = 1.0
	w_hero.eff_spd_t = 0.0
	w_hero.eff_dmg_mult = 1.0
	w_hero.eff_dmg_t = 0.0
	game.skill_zones.clear()
	game.projectiles.clear()


## (15b) Diplomacy — the stance sim on a staged 3-slot FFA
## instance: invite/accept/decline, tribute rules, the 30 s
## declaration window, targeting gates, checksum + snapshot
## coverage, the Đội chat rule and the shared allied victory.
func _section_diplomacy15b() -> void:
	var gd = load("res://main.tscn").instantiate()
	add_child(gd)
	await get_tree().process_frame
	await get_tree().process_frame
	gd.enemy_ai.waves_enabled = false
	gd.mp_mode = true
	gd.slot_teams = [0, 1, 2]
	gd.slot_names = ["A", "B", "C"]
	gd.slot_eliminated = [false, false, false]
	gd.mp_wallets = [
		{"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0},
		{"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0},
		{"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0}]
	# The full per-slot state _mp_setup_slots would build — the
	# checksum and the snapshot read all of it (ages/techs/rally).
	gd.mp_ages = [
		{"age": 1, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0},
		{"age": 1, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0},
		{"age": 1, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0}]
	gd.mp_techs = [{"levels": {}, "active": {}},
		{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	gd.mp_rally = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	gd.slot_tc_down = [false, false, false]
	gd.slot_inert = [false, false, false]
	gd.slot_chars = ["knight", "archer", "mage"]
	gd.slot_skins = ["", "", ""]
	gd.team_age = {0: 1, 1: 1, 2: 1}
	# dp0: arming rules — the flag arms diplomacy only in an FFA
	# shape; a shared team (fixed 2v2-style setup) keeps it inert,
	# and without the flag nothing arms at all.
	gd.mp_config = {"diplomacy": true}
	gd._dip_setup()
	check("dp0 diplomacy arms in an FFA custom shape", gd.diplomacy_active())
	gd.slot_teams = [0, 0, 1]
	gd._dip_setup()
	check("dp0 fixed teams take precedence (diplomacy inert)",
			not gd.diplomacy_active())
	gd.slot_teams = [0, 1, 2]
	gd.mp_config = {}
	gd._dip_setup()
	check("dp0 no room flag, no diplomacy", not gd.diplomacy_active())
	gd.mp_config = {"diplomacy": true}
	gd._dip_setup()
	check("dp0 default stance is enemy",
			gd.stance_of(0, 1) == gd.DIP_ENEMY and not gd.owners_allied(0, 1)
			and gd.attack_allowed(0, 1) and gd.auto_engage_allowed(0, 1)
			and not gd.dip_vision_shared(0, 1))
	# dp1: propose -> accept lands the ALLY stance + predicates.
	var ok1: bool = gd._mp_apply_command(0,
			{"kind": "dip_propose", "to": 1, "stance": 2})
	check("dp1 propose applies", ok1 and gd.dip_invite_from(0, 1) == 2)
	var ok2: bool = gd._mp_apply_command(1,
			{"kind": "dip_respond", "to": 0, "accept": true})
	check("dp1 accept allies the pair",
			ok2 and gd.stance_of(0, 1) == gd.DIP_ALLY
			and gd.owners_allied(0, 1) and gd.dip_vision_shared(0, 1)
			and not gd.attack_allowed(0, 1) and not gd.attack_allowed(1, 0)
			and not gd.auto_engage_allowed(0, 1)
			and gd.dip_invite_from(0, 1) == -1)
	# dp5a: while allied, acquisition finds no hostile and the
	# ordered-target lookup refuses the ally.
	var ua = gd._make_unit(0, gd.world.cell_center(Vector2i(30, 30)),
			"militia", 0)
	var ub = gd._make_unit(1, gd.world.cell_center(Vector2i(30, 31)),
			"militia", 1)
	ua.guard_pos = ua.global_position
	check("dp5a allied: no auto target, no ordered target",
			ua._nearest_hostile_unit(600.0) == null
			and ua._acquire_near_guard() == null
			and gd.enemy_unit_at(ub.global_position, 24.0, 0, 0) == null)
	# dp2: a declined proposal changes nothing.
	gd._mp_apply_command(0, {"kind": "dip_propose", "to": 2, "stance": 1})
	var okd: bool = gd._mp_apply_command(2,
			{"kind": "dip_respond", "to": 0, "accept": false})
	check("dp2 decline clears the invite, stance stays enemy",
			okd and gd.dip_invite_from(0, 2) == -1
			and gd.stance_of(0, 2) == gd.DIP_ENEMY)
	# dp3: tribute — exact transfer, cooldown, balance, stance.
	var okg: bool = gd._mp_apply_command(0,
			{"kind": "dip_gift", "to": 1, "rtype": "wood", "amt": 100})
	check("dp3 gift of 100 wood lands exactly",
			okg and int(gd.mp_wallets[0]["wood"]) == 100
			and int(gd.mp_wallets[1]["wood"]) == 300)
	check("dp3 cooldown blocks an instant second gift",
			not gd._mp_apply_command(0,
					{"kind": "dip_gift", "to": 1, "rtype": "wood", "amt": 10}))
	check("dp3 no tribute to an enemy",
			not gd._mp_apply_command(0,
					{"kind": "dip_gift", "to": 2, "rtype": "wood", "amt": 10}))
	gd._update_diplomacy(31.0)
	check("dp3 over-balance gift refused, smaller one lands",
			not gd._mp_apply_command(0,
					{"kind": "dip_gift", "to": 1, "rtype": "gold", "amt": 500})
			and gd._mp_apply_command(0,
					{"kind": "dip_gift", "to": 1, "rtype": "wood", "amt": 50})
			and int(gd.mp_wallets[0]["wood"]) == 50
			and int(gd.mp_wallets[1]["wood"]) == 350)
	# dp4: the declaration window — vision ends at once, the
	# stance (and attack protection) holds until maturity.
	var okb: bool = gd._mp_apply_command(0, {"kind": "dip_break", "to": 1})
	check("dp4 declaration: vision ends now, stance holds",
			okb and not gd.dip_break_on(0, 1).is_empty()
			and gd.stance_of(0, 1) == gd.DIP_ALLY
			and not gd.dip_vision_shared(0, 1)
			and not gd.attack_allowed(0, 1) and not gd.attack_allowed(1, 0))
	gd._update_diplomacy(30.5)
	check("dp4 matured: neutral — ordered attacks ok, no auto-engage",
			gd.stance_of(0, 1) == gd.DIP_NEUTRAL
			and gd.attack_allowed(0, 1)
			and not gd.auto_engage_allowed(0, 1))
	var okb2: bool = gd._mp_apply_command(1, {"kind": "dip_break", "to": 0})
	check("dp4 second declaration binds only the breaker",
			okb2 and not gd.attack_allowed(1, 0) and gd.attack_allowed(0, 1))
	gd._update_diplomacy(30.5)
	check("dp4 matured to enemy: auto-engage back on",
			gd.stance_of(0, 1) == gd.DIP_ENEMY
			and gd.auto_engage_allowed(0, 1))
	# dp5b: enemies again — acquisition and ordered lookup bite.
	check("dp5b enemy: auto target and ordered target resolve",
			ua._nearest_hostile_unit(600.0) != null
			and gd.enemy_unit_at(ub.global_position, 24.0, 0, 0) == ub)
	# dp7: the checksum moves when a stance lands.
	var h1: int = gd._mp_state_hash()
	gd._mp_apply_command(0, {"kind": "dip_propose", "to": 2, "stance": 2})
	gd._mp_apply_command(2, {"kind": "dip_respond", "to": 0, "accept": true})
	check("dp7 stance change moves the checksum",
			gd.stance_of(0, 2) == gd.DIP_ALLY and gd._mp_state_hash() != h1)
	# dp9: the Đội chat rule follows current alliances.
	gd.local_slot = 0
	check("dp9 team chat available with a live ally",
			gd.hud._team_chat_available())
	# dp8: snapshot round-trip of the diplomacy tables.
	gd.dip_gift_cd["0>1"] = 12.0
	var snap: Dictionary = gd._mp_snapshot_state()
	gd.dip_stance.erase("0:2")
	gd.dip_gift_cd.clear()
	check("dp8 snapshot carries the tables; restore rebuilds them",
			snap.has("dip") and gd.stance_of(0, 2) == gd.DIP_ENEMY)
	gd._dip_restore(snap)
	check("dp8 restore: stance + cooldown back",
			gd.stance_of(0, 2) == gd.DIP_ALLY
			and float(gd.dip_gift_cd.get("0>1", 0.0)) == 12.0)
	gd.dip_stance.erase("0:2")
	check("dp9 team chat gone when the last ally falls",
			not gd.hud._team_chat_available())
	gd.dip_stance["0:2"] = gd.DIP_ALLY
	# dp6: with slot 1 eliminated, the two survivors are mutually
	# allied — the match ends as a shared victory.
	gd.slot_eliminated[1] = true
	gd._mp_check_winner()
	check("dp6 allied victory ends the match for both survivors",
			gd.mp_over and gd.dip_winners == [0, 2],
			"winners=%s" % [gd.dip_winners])
	remove_child(gd)
	gd.queue_free()
	await get_tree().process_frame


## (16b) The medieval roster — twin of tests/test_heroes16b.gd
## (kept as its own function so its locals cannot collide with
## the shared _ready scope). Every hero: aura measurable in the
## sim, the ONE skill's effect, and the unified 75 s cooldown.
func _section_heroes16b() -> void:
	var gameW = load("res://main.tscn").instantiate()
	add_child(gameW)
	await get_tree().process_frame
	await get_tree().process_frame
	# ------------------------------------------------ roster of 8
	var seen := {}
	var rng := RandomNumberGenerator.new()
	for s in range(400):
		rng.seed = s * 7919 + 13
		seen[gameW.draw_character(rng)] = true
	check("(16b) pool of 8: every hero reachable by the draw, none outside",
			seen.size() == 8, "seen=%s" % [seen.keys()])
	gameW.enemy_ai.waves_enabled = false
	# Pin slot 1's character: foe kings in the assassin phase
	# must not bring a mitigation/armour aura of their own.
	gameW.slot_chars[1] = "mage"
	# No king exists at SP boot (heroes are Castle-trained), and
	# the aura helpers read hero_of_team — so retire any stray
	# king and force-spawn THE test hero: he is then the only
	# team-0 king (team 1 has none until the assassin phase).
	for u in gameW.units.duplicate():
		if u.unit_type == "king":
			gameW.units.erase(u)
			u.queue_free()
	var anchor: Vector2i = gameW.world.nearest_walkable(
			gameW.player_tc.origin_cell + Vector2i(6, 6))
	var base: Vector2 = gameW.world.cell_center(anchor)
	var w_hero: Unit = gameW._make_unit(0, base, "king")
	w_hero.facing = "right"

	# ------------------------------------------------ Knight
	gameW.slot_chars[0] = "knight"
	w_reset_hero(gameW, w_hero, base)
	# Aura Hộ Vệ: covered allies take x0.92 damage.
	var kn_ally := w_ally(gameW, base + Vector2(48, 40))
	kn_ally.take_damage(100.0, null)
	check("(16b) knight aura: ally takes x0.92 damage inside 3 tiles",
			absf(kn_ally.hp - 908.0) < 0.01
			and gameW.hero_aura_covers(kn_ally, "knight", true),
			"ally=%s" % kn_ally.hp)
	# Skill Khiên Sư Tử: 250 shield (the x0.92 aura eats into the
	# absorb), military foes taunted, villagers not, CD 75.
	var kn_foe := w_foe(gameW, base + Vector2(64, -40))
	var kn_vil: Unit = gameW._make_unit(1, base + Vector2(30, 70), "villager")
	var kn_ok: bool = gameW.cast_hero_skill(w_hero)
	w_hero.take_damage(100.0, null)
	check("(16b) knight skill: 250 shield absorbs, military taunted, CD 75",
			kn_ok and absf(w_hero.shield_hp - 158.0) < 0.01
			and absf(w_hero.hp - w_hero.max_hp) < 0.01
			and kn_foe.taunt_id == w_hero.net_id and kn_foe.taunt_t > 3.5
			and kn_foe._taunt_hero() == w_hero
			and kn_vil.taunt_t <= 0.0
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"shield=%s hp=%s taunt=%s cd=%s" % [w_hero.shield_hp, w_hero.hp,
					kn_foe.taunt_t, w_hero.skill_cd_t])

	# ------------------------------------------------ Berserker
	var b_base := base + Vector2(0, 260)
	gameW.slot_chars[0] = "berserker"
	w_reset_hero(gameW, w_hero, b_base)
	# Aura Cuồng Chiến: allied military attack speed x1.10.
	var bk_ally := w_ally(gameW, b_base + Vector2(48, 40))
	check("(16b) berserker aura: ally attack speed x1.10",
			absf(bk_ally.eff_atkspd_mult() - 1.10) < 0.01,
			"ally=%s" % bk_ally.eff_atkspd_mult())
	# Skill Rìu Xoáy: 110 to every enemy within 2 tiles only.
	var bk_f1 := w_foe(gameW, b_base + Vector2(50, 0))
	var bk_f2 := w_foe(gameW, b_base + Vector2(-40, 30))
	var bk_far := w_foe(gameW, b_base + Vector2(110, 0))
	var bk_ok: bool = gameW.cast_hero_skill(w_hero)
	check("(16b) berserker skill: whirlwind 110 in 2 tiles, outside safe, CD 75",
			bk_ok and absf(bk_f1.hp - 890.0) < 0.01
			and absf(bk_f2.hp - 890.0) < 0.01
			and absf(bk_far.hp - 1000.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"f1=%s f2=%s far=%s" % [bk_f1.hp, bk_f2.hp, bk_far.hp])

	# ------------------------------------------------ Archer
	var a_base := base + Vector2(300, 260)
	gameW.slot_chars[0] = "archer"
	w_reset_hero(gameW, w_hero, a_base)
	# Ranged frame: bow range 160, arrows fly.
	check("(16b) archer frame: attack range 160 (ranged kit)",
			absf(w_hero.attack_range() - 160.0) < 0.01,
			"range=%s" % w_hero.attack_range())
	# Aura Tiễn Thủ: allied military damage x1.08 (strike ratio).
	var ar_a1 := w_ally(gameW, a_base + Vector2(40, 30))
	var ar_a2 := w_ally(gameW, a_base + Vector2(400, 30))
	var ar_t1 := w_foe(gameW, a_base + Vector2(70, 30))
	var ar_t2 := w_foe(gameW, a_base + Vector2(430, 30))
	ar_a1.attack_target = ar_t1
	ar_a2.attack_target = ar_t2
	ar_a1.strike()
	ar_a2.strike()
	var ar_d1 := 1000.0 - ar_t1.hp
	var ar_d2 := 1000.0 - ar_t2.hp
	check("(16b) archer aura: covered ally strikes x1.08, far ally x1.0",
			ar_d2 > 0.0 and absf(ar_d1 - ar_d2 * 1.08) < 0.01,
			"near=%s far=%s" % [ar_d1, ar_d2])
	# Skill Mưa Tên: zone at the point, 3 waves x40, then gone.
	w_reset_hero(gameW, w_hero, a_base)
	var ar_foe := w_foe(gameW, a_base + Vector2(120, -60))
	var ar_ok: bool = gameW.cast_hero_skill(w_hero, ar_foe.global_position)
	for i in range(4):
		gameW._update_skill_zones(0.5)
	check("(16b) archer skill: arrow rain 3 waves x40 = 120, zone expires, CD 75",
			ar_ok and absf(ar_foe.hp - 880.0) < 0.01
			and gameW.skill_zones.is_empty()
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"foe=%s zones=%d" % [ar_foe.hp, gameW.skill_zones.size()])
	# Cast range clamps at 8 tiles.
	w_hero.skill_cd_t = 0.0
	gameW.cast_hero_skill(w_hero, a_base + Vector2(400, 0))
	check("(16b) archer skill: cast point clamps to 8 tiles",
			gameW.skill_zones.size() == 1
			and (gameW.skill_zones[0]["pos"] as Vector2).distance_to(a_base) <= 8.0 * World.TILE + 1.0,
			"zones=%d" % gameW.skill_zones.size())
	gameW.skill_zones.clear()

	# ------------------------------------------------ Mage
	var m_base := base + Vector2(-300, 260)
	gameW.slot_chars[0] = "mage"
	w_reset_hero(gameW, w_hero, m_base)
	# Aura Ma Lực Hồi Lưu: +1.2 HP/s regen for covered allies.
	var mg_ally := w_ally(gameW, m_base + Vector2(40, 30))
	mg_ally.hp = 500.0
	mg_ally._tick_effects(1.05)
	check("(16b) mage aura: covered ally regenerates +1.2 HP per second",
			absf(mg_ally.hp - 501.2) < 0.01, "hp=%s" % mg_ally.hp)
	# Skill Thiên Thạch: 120 in 2.5 tiles at the point.
	w_reset_hero(gameW, w_hero, m_base)
	var mg_f1 := w_foe(gameW, m_base + Vector2(150, 0))
	var mg_f2 := w_foe(gameW, m_base + Vector2(190, 20))
	var mg_far := w_foe(gameW, m_base + Vector2(150, 120))
	var mg_ok: bool = gameW.cast_hero_skill(w_hero, m_base + Vector2(160, 0))
	check("(16b) mage skill: meteor 120 in 2.5 tiles, outside safe, CD 75",
			mg_ok and absf(mg_f1.hp - 880.0) < 0.01
			and absf(mg_f2.hp - 880.0) < 0.01
			and absf(mg_far.hp - 1000.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"f1=%s f2=%s far=%s" % [mg_f1.hp, mg_f2.hp, mg_far.hp])

	# ------------------------------------------------ Paladin
	var p_base := base + Vector2(300, -260)
	gameW.slot_chars[0] = "paladin"
	w_reset_hero(gameW, w_hero, p_base)
	# Aura Thánh Giáp: flat -3 per hit, at least 1 through.
	var pa_ally := w_ally(gameW, p_base + Vector2(40, -40))
	pa_ally.take_damage(10.0, null)
	var pa_after10 := pa_ally.hp
	pa_ally.take_damage(2.0, null)
	check("(16b) paladin aura: hits reduced by flat 3, minimum 1 gets through",
			absf(pa_after10 - 993.0) < 0.01 and absf(pa_ally.hp - 992.0) < 0.01,
			"hp=%s" % pa_ally.hp)
	# Skill Thánh Quang: +160 heal in 3 tiles + cleanse.
	w_reset_hero(gameW, w_hero, p_base)
	var pa_wound := w_ally(gameW, p_base + Vector2(50, 20))
	pa_wound.hp = 30.0
	pa_wound.stun_t = 3.0
	w_hero.hp = 400.0
	var pa_foe := w_foe(gameW, p_base + Vector2(60, -20))
	pa_foe.hp = 30.0
	var pa_ok: bool = gameW.cast_hero_skill(w_hero)
	check("(16b) paladin skill: heal 160 + cleanse allies, enemies unhealed, CD 75",
			pa_ok and absf(pa_wound.hp - 190.0) < 0.01
			and pa_wound.stun_t <= 0.0
			and absf(w_hero.hp - 560.0) < 0.01
			and absf(pa_foe.hp - 30.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"ally=%s hero=%s foe=%s" % [pa_wound.hp, w_hero.hp, pa_foe.hp])

	# ------------------------------------------------ Dragoon
	var d_base := base + Vector2(-300, -260)
	gameW.slot_chars[0] = "dragoon"
	w_reset_hero(gameW, w_hero, d_base)
	w_hero.facing = "right"
	# Aura Long Hành: +10% move speed, allies and himself.
	var dr_ally := w_ally(gameW, d_base + Vector2(40, 40))
	check("(16b) dragoon aura: ally + hero move speed x1.10",
			absf(gameW.hero_speed_factor(dr_ally) - 1.10) < 0.01
			and absf(gameW.hero_speed_factor(w_hero) - 1.10) < 0.01,
			"ally=%s hero=%s" % [gameW.hero_speed_factor(dr_ally),
					gameW.hero_speed_factor(w_hero)])
	# Skill Long Thương: dash to the point, 120 along the path.
	var dr_on := w_foe(gameW, d_base + Vector2(80, 0))
	var dr_off := w_foe(gameW, d_base + Vector2(80, 70))
	var dr_ok: bool = gameW.cast_hero_skill(w_hero, d_base + Vector2(160, 0))
	check("(16b) dragoon skill: dash lands, 120 on the path, off-path safe, CD 75",
			dr_ok and w_hero.global_position.distance_to(d_base + Vector2(160, 0)) < 24.0
			and absf(dr_on.hp - 880.0) < 0.01
			and absf(dr_off.hp - 1000.0) < 0.01
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"pos=%s on=%s off=%s" % [w_hero.global_position, dr_on.hp, dr_off.hp])
	# The dash clamps at 5 tiles.
	w_reset_hero(gameW, w_hero, d_base)
	gameW.cast_hero_skill(w_hero, d_base + Vector2(300, 0))
	check("(16b) dragoon skill: dash clamps to 5 tiles",
			w_hero.global_position.distance_to(d_base) <= 5.0 * World.TILE + 24.0,
			"dist=%s" % w_hero.global_position.distance_to(d_base))

	# ------------------------------------------------ Assassin
	var s_base := base + Vector2(0, -420)
	gameW.slot_chars[0] = "assassin"
	w_reset_hero(gameW, w_hero, s_base)
	# Aura Truy Sát: allied military deal x1.10 to enemy heroes.
	var as_a1 := w_ally(gameW, s_base + Vector2(40, 30))
	var as_a2 := w_ally(gameW, s_base + Vector2(400, 30))
	var as_k1: Unit = gameW._make_unit(1, s_base + Vector2(70, 30), "king")
	var as_k2: Unit = gameW._make_unit(1, s_base + Vector2(430, 30), "king")
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
	check("(16b) assassin aura: covered ally strikes x1.10 vs enemy heroes",
			as_d2 > 0.0 and absf(as_d1 - as_d2 * 1.10) < 0.01,
			"near=%s far=%s" % [as_d1, as_d2])
	# Skill Ám Sát: refuses beyond 6 tiles; blinks behind + 160.
	w_reset_hero(gameW, w_hero, s_base)
	check("(16b) assassin skill: target beyond 6 tiles refused, no cooldown spent",
			not gameW.cast_hero_skill(w_hero, s_base + Vector2(224, 0))
			and w_hero.skill_cd_t <= 0.0, "cd=%s" % w_hero.skill_cd_t)
	var as_victim: Unit = gameW._make_unit(1, s_base + Vector2(150, 0), "king")
	var as_ok: bool = gameW.cast_hero_skill(w_hero, as_victim.global_position)
	check("(16b) assassin skill: blink behind the victim, 160 burst, CD 75",
			as_ok and absf(as_victim.hp - 490.0) < 0.01
			and w_hero.global_position.distance_to(as_victim.global_position) < 40.0
			and w_hero.global_position.x > as_victim.global_position.x
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"victim=%s herox=%s vx=%s" % [as_victim.hp,
					w_hero.global_position.x, as_victim.global_position.x])

	# ------------------------------------------------ Ranger
	var r_base := base + Vector2(420, 0)
	gameW.slot_chars[0] = "ranger"
	w_reset_hero(gameW, w_hero, r_base)
	# Aura Viễn Thị: +1 sight for covered allies (fog reads it).
	var rg_ally := w_ally(gameW, r_base + Vector2(40, 30))
	check("(16b) ranger aura: covers allies, kit grants +1 sight",
			gameW.hero_aura_covers(rg_ally, "ranger", true)
			and int(Stats.HERO_KITS["ranger"]["aura_sight"]) == 1,
			"covers=%s" % gameW.hero_aura_covers(rg_ally, "ranger", true))
	# Skill Kiếm Vũ: 5 slashes x32 round-robin over 3 foes.
	var rg_f1 := w_foe(gameW, r_base + Vector2(40, 0))
	var rg_f2 := w_foe(gameW, r_base + Vector2(-30, 40))
	var rg_f3 := w_foe(gameW, r_base + Vector2(0, -50))
	var rg_ok: bool = gameW.cast_hero_skill(w_hero)
	for i in range(5):
		gameW._update_hero_flurries(0.21)
	check("(16b) ranger skill: 5 slashes x32 spread round-robin, CD 75",
			rg_ok and absf(rg_f1.hp - 936.0) < 0.01
			and absf(rg_f2.hp - 936.0) < 0.01
			and absf(rg_f3.hp - 968.0) < 0.01
			and w_hero.flurry_left == 0
			and absf(w_hero.skill_cd_t - 75.0) < 0.5
			and not gameW.cast_hero_skill(w_hero),
			"f=%s,%s,%s left=%s" % [rg_f1.hp, rg_f2.hp, rg_f3.hp, w_hero.flurry_left])

	# ------------------------------------------------ plumbing
	check("(16b) targeting matrix: rain/meteor/dash/blink targeted, the rest instant",
			gameW.skill_is_targeted("archer", 1) and gameW.skill_is_targeted("mage", 1)
			and gameW.skill_is_targeted("dragoon", 1) and gameW.skill_is_targeted("assassin", 1)
			and not gameW.skill_is_targeted("knight", 1)
			and not gameW.skill_is_targeted("berserker", 1)
			and not gameW.skill_is_targeted("paladin", 1)
			and not gameW.skill_is_targeted("ranger", 1)
			and not gameW.skill_is_targeted("archer", 2)
			and not gameW.skill_is_targeted("mage", 3), "")
	gameW.slot_chars[0] = "dragoon"
	w_reset_hero(gameW, w_hero, base)
	w_hero.facing = "right"
	var mp_foe := w_foe(gameW, base + Vector2(160, -120))
	var mp_t: bool = gameW._mp_apply_skill_cmd(0, {"u": w_hero.net_id, "s": 1,
			"x": mp_foe.global_position.x, "y": mp_foe.global_position.y})
	w_hero.skill_cd_t = 0.0
	var mp_u: bool = gameW._mp_apply_skill_cmd(0, {"u": w_hero.net_id, "s": 1})
	var mp_bad: bool = gameW._mp_apply_skill_cmd(0, {"u": w_hero.net_id, "s": 2,
			"x": mp_foe.global_position.x, "y": mp_foe.global_position.y})
	check("(16b) MP skill cmd: s=1 targeted + untargeted apply, s=2 rejected (one skill only)",
			mp_t and mp_u and not mp_bad and w_hero.skill_cd_t > 74.0,
			"cd=%s" % w_hero.skill_cd_t)
	remove_child(gameW)
	gameW.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	Engine.time_scale = 20.0
	game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	# P3 harness guard: the legacy sections predate the enemy AI's
	# attack waves — keep them deterministic; section (t) re-enables.
	game.enemy_ai.waves_enabled = false
	# Same guard for wild beasts (ships + beasts pass): parked until
	# section (x) wakes them, so legacy gather/combat routes stay
	# deterministic.
	for bst in game.world.beasts:
		bst.dormant = true

	# ------------------------------------------------ (a) boot + map
	check("a1 world + astar built", game.world != null and game.world.astar != null)
	check("a2 obstacles on grid", game.world.solid.size() > 50, "solid=%d" % game.world.solid.size())
	check("a3 resource nodes exist", game.world.nodes.size() > 20, "nodes=%d" % game.world.nodes.size())
	var a4_villagers := 0
	var a4_scout := false
	for u0 in player_units():
		if u0.unit_type == "villager":
			a4_villagers += 1
		if u0.unit_type == "cavalry":
			a4_scout = true
	check("a4 three starting villagers + 1 scout cavalry (flow doc)",
			a4_villagers == 3 and a4_scout and player_units().size() == 4,
			"villagers=%d scout=%s units=%d" % [a4_villagers, a4_scout, player_units().size()])
	check("a5 starting resources", game.resources.food == 200 and game.resources.wood == 200 and game.resources.gold == 100,
			str(game.resources))
	check("a6 population 4/5 (3 villagers + scout)", game.pop_current() == 4 and game.pop_cap() == 5,
			"%d/%d" % [game.pop_current(), game.pop_cap()])
	check("a7 enemy base exists", game.enemy_tc != null and game.enemy_tc.team == 1)
	# Terrain tileset: textures load and cells resolve to real tiles.
	check("a8 ground tile textures loaded", game.world.ground_textures_loaded(),
			"tiles=%d" % game.world.ground_tex.size())
	var saw_grass := false
	var saw_water := false
	var saw_shore := false
	for yy in range(World.MAP_H):
		for xx in range(World.MAP_W):
			var key: String = game.world.ground_tile_key(Vector2i(xx, yy))
			if key.begins_with("grass"):
				saw_grass = true
			elif key.begins_with("shore"):
				saw_shore = true
			elif key.begins_with("water"):
				saw_water = true
	check("a9 ground keys cover grass + open water + shore", saw_grass and saw_water and saw_shore)
	# Baked ground: the whole map is ONE composed texture (single
	# base variant per surface) with soft accent decals on top —
	# no per-tile variant drawing remains to form a quilt.
	check("a10 ground is baked into one texture + decals",
			game.world.baked_ground != null
			and game.world.baked_ground.get_width() == World.BAKE_PX
			and game.world.baked_ground.get_height() == World.BAKE_PX
			and game.world.ground_decals.size() > 40,
			"decals=%d" % game.world.ground_decals.size())
	# No quilt: sampled inland cell centres stay near the base grass
	# tone (the old variant tiles swapped whole cells to other tones).
	var btex: Texture2D = game.world.ground_tex.get("grass_0")
	var bimg := btex.get_image()
	bimg.convert(Image.FORMAT_RGBA8)
	var bacc := Color(0, 0, 0)
	var bn := 0
	for yy in range(bimg.get_height()):
		for xx in range(bimg.get_width()):
			var bp := bimg.get_pixel(xx, yy)
			if bp.a > 0.8:
				bacc += bp
				bn += 1
	var bavg := bacc / float(maxi(1, bn))
	var worst := 0.0
	for yy in range(0, World.MAP_H, 3):
		for xx in range(0, World.MAP_W, 3):
			var c := Vector2i(xx, yy)
			if game.world.water.has(c):
				continue
			var rim := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if game.world.water.has(c + d):
					rim = true
			if rim:
				continue # the shore rim is intentionally sandy
			var col: Color = game.world.baked_color_at(c)
			worst = maxf(worst, absf(col.r - bavg.r) + absf(col.g - bavg.g) + absf(col.b - bavg.b))
	check("a11 baked land shows no variant quilt patches", worst < 0.6,
			"worst=%.2f" % worst)

	# ------------------------------------------------ (b) selection
	var box := Rect2(Vector2(80, 1620), Vector2(420, 330))
	game.apply_box_selection(box)
	check("b1 box select finds 3 villagers + the scout", game.selection.size() == 4, "sel=%d" % game.selection.size())
	var u0: Unit = player_units()[0]
	var ok_single: bool = game.select_unit_at(u0.global_position)
	check("b2 click select finds 1", ok_single and game.selection.size() == 1, "sel=%d" % game.selection.size())
	game.select_all_of_type(u0)
	check("b3 double-click select-all-of-type finds 3", game.selection.size() == 3, "sel=%d" % game.selection.size())
	game.clear_selection()
	check("b4 clear selection", game.selection.is_empty())

	# ------------------------------------------------ (c) move order avoids obstacle
	var w = game.world
	var tree_cell := Vector2i(-1, -1)
	for n in w.nodes:
		if n.rtype == "wood":
			tree_cell = n.cell
			break
	check("c0 found a tree cell", tree_cell.x >= 0)
	var from_c: Vector2i = w.nearest_walkable(tree_cell + Vector2i(-3, 0))
	var to_c: Vector2i = w.nearest_walkable(tree_cell + Vector2i(3, 0))
	var um: Unit = player_units()[0]
	um.global_position = w.cell_center(from_c)
	um.state = "idle"
	um.path.clear()
	um.order_move_cell(to_c)
	check("c1 path produced", um.path_cells.size() > 1, "cells=%d" % um.path_cells.size())
	var path_clean := true
	for c in um.path_cells:
		if w.is_solid(c):
			path_clean = false
	check("c2 path avoids all solid tiles (incl. tree)", path_clean and not um.path_cells.has(tree_cell))
	var dest: Vector2 = w.cell_center(to_c)
	var arrived: bool = await wait_until(func() -> bool: return um.global_position.distance_to(dest) < 42.0, 30000)
	check("c3 unit reached destination area", arrived, "pos=%s dest=%s" % [str(um.global_position), str(dest)])

	# ------------------------------------------------ (d) gather cycle deposits +10 wood
	var wood0: int = game.resources.wood
	var node: ResourceNode = w.nearest_node_of_type(game.player_tc.global_position, "wood")
	check("d0 tree node near TC", node != null)
	var ug: Unit = player_units()[1]
	ug.order_gather(node)
	var deposited: bool = await wait_until(func() -> bool: return game.resources.wood > wood0, 40000)
	check("d1 gather cycle increased wood", deposited, "wood=%d start=%d" % [game.resources.wood, wood0])
	check("d2 deposit was exactly +10", game.resources.wood == wood0 + 10,
			"wood=%d start=%d" % [game.resources.wood, wood0])

	# ------------------------------------------------ (e) training
	stop_all_units()
	var food0: int = game.resources.food
	var pop0: int = game.pop_current()
	var trained: bool = game.train_villager()
	check("e1 train order accepted", trained)
	check("e2 50 food deducted", game.resources.food == food0 - 50, "food=%d" % game.resources.food)
	var spawned: bool = await wait_until(func() -> bool: return game.pop_current() == pop0 + 1, 40000)
	check("e3 new villager spawned", spawned, "pop=%d" % game.pop_current())

	# ------------------------------------------------ (f) placement: deduct, refund, build, pop cap
	stop_all_units()
	var wood1: int = game.resources.wood
	game.enter_placement("barracks")
	check("f1 enter placement deducts 100 wood", game.resources.wood == wood1 - 100,
			"wood=%d start=%d" % [game.resources.wood, wood1])
	game.cancel_placement()
	check("f2 cancel refunds 100 wood", game.resources.wood == wood1, "wood=%d" % game.resources.wood)

	game.enter_placement("house")
	check("f3 enter house placement deducts 30 wood", game.resources.wood == wood1 - 30,
			"wood=%d" % game.resources.wood)
	var place_cell := Vector2i(-1, -1)
	for dy in range(-9, 10):
		for dx in range(-9, 10):
			var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
			if w.can_place(cand, Vector2i(2, 2)):
				place_cell = cand
				break
		if place_cell.x >= 0:
			break
	check("f4 free spot found", place_cell.x >= 0)
	var placed: bool = game.confirm_placement(place_cell)
	check("f5 placement confirmed", placed)
	var cap0: int = game.pop_cap()
	var house = null
	for b in game.buildings:
		if b.btype == "house":
			house = b
	check("f6 house site exists, unfinished", house != null and not house.complete)
	var built: bool = await wait_until(func() -> bool: return house != null and house.complete, 60000)
	check("f7 house construction finished", built)
	check("f8 pop cap raised by +5", game.pop_cap() == cap0 + 5, "cap=%d was=%d" % [game.pop_cap(), cap0])

	# ------------------------------------------------ (g) barracks construction
	stop_all_units()
	game.enter_placement("barracks")
	var bcell := Vector2i(-1, -1)
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
			if w.can_place(cand, game.get_build_def("barracks").size):
				bcell = cand
				break
		if bcell.x >= 0:
			break
	check("g1 free barracks spot found", bcell.x >= 0)
	var placed_b: bool = game.confirm_placement(bcell)
	check("g2 barracks placement confirmed", placed_b)
	var barr = null
	for b in game.buildings:
		if b.btype == "barracks":
			barr = b
	var bbuilt: bool = await wait_until(func() -> bool: return barr != null and barr.complete, 60000)
	check("g3 barracks construction finished", bbuilt)
	check("g4 completed barracks is the training building", game.training_building("militia") == barr)
	check("g5 quest system removed (13s addendum)", not game.has_method("quest_states")
			and not game.hud.has_method("quest_states")
			and not game.has_method("objectives_fraction"))
	check("g6 completed barracks shows camp sprite", barr != null and barr.art_sprite != null
			and barr.art_sprite.texture != null and barr.art_sprite.visible,
			"sprite=%s" % str(barr.art_sprite if barr != null else null))

	# ------------------------------------------------ (h) training via the HUD path
	stop_all_units()
	var food_h: int = game.resources.food
	var q0: int = game.player_tc.train_queue
	var ok_h: bool = game.hud.ui_train_villager()
	check("h1 HUD train accepted", ok_h)
	check("h2 HUD train deducted 50 food", game.resources.food == food_h - 50,
			"food=%d start=%d" % [game.resources.food, food_h])
	check("h3 HUD train queued at TC", game.player_tc.train_queue == q0 + 1,
			"queue=%d was=%d" % [game.player_tc.train_queue, q0])

	# ------------------------------------------------ (i) minimap click moves camera
	check("i1 minimap exists", game.hud.minimap != null)
	var cam_before: Vector2 = game.cam.position
	var mm = game.hud.minimap
	mm.click_at(Vector2(mm.size.x - 6.0, 6.0))
	check("i2 minimap click moved camera", game.cam.position != cam_before,
			"cam=%s was=%s" % [str(game.cam.position), str(cam_before)])
	check("i3 camera moved toward enemy corner",
			game.cam.position.x > cam_before.x and game.cam.position.y < cam_before.y,
			"cam=%s was=%s" % [str(game.cam.position), str(cam_before)])

	# ------------------------------------------------ (j) match timer advances
	var t0: float = game.match_time
	var adv: bool = await wait_until(func() -> bool: return game.match_time > t0 + 0.2, 5000)
	check("j1 match timer advances", adv, "t=%f was=%f" % [game.match_time, t0])

	# ------------------------------------------------ (k) iron in state + 5 HUD chips
	check("k1 iron present in game state", game.resources.has("iron"))
	check("k2 HUD shows 5 resource chips", game.hud.res_chips.size() == 5 and game.hud.res_chips.has("iron"),
			"chips=%d" % game.hud.res_chips.size())

	# ------------------------------------------------ (l) villager sprite sheet
	Engine.time_scale = 5.0
	stop_all_units()
	var us: Unit = player_units()[0]
	check("l1 sprite node created from sheet", us.spr != null and us._atlas != null and us._atlas.atlas != null)
	check("l2 idle has 16 frames", us.sheet_anim_count("idle") == 16,
			"idle=%d" % us.sheet_anim_count("idle"))
	check("l3 walk has 16 frames", us.sheet_anim_count("walk") == 16,
			"walk=%d" % us.sheet_anim_count("walk"))
	check("l4 work has >= 8 frames", us.sheet_anim_count("work") >= 8,
			"work=%d" % us.sheet_anim_count("work"))
	# Direction mapping: walk east -> Right frames, walk north -> Up frames.
	var start_c: Vector2i = w.nearest_walkable(game.player_tc.origin_cell + Vector2i(-2, 9))
	var east_c: Vector2i = w.nearest_walkable(start_c + Vector2i(9, 0))
	us.global_position = w.cell_center(start_c)
	us.state = "idle"
	us.path.clear()
	us.order_move_cell(east_c)
	var saw_right: bool = await wait_until(func() -> bool: return us.anim_name == "walk_right", 20000)
	check("l5 moving right uses Right frames", saw_right, "anim=%s" % us.anim_name)
	var uu: Unit = player_units()[1]
	uu.global_position = w.cell_center(start_c)
	uu.state = "idle"
	uu.path.clear()
	uu.order_move_cell(w.nearest_walkable(start_c + Vector2i(0, -7)))
	var saw_up: bool = await wait_until(func() -> bool: return uu.anim_name == "walk_up", 20000)
	check("l6 moving up uses Up frames", saw_up, "anim=%s" % uu.anim_name)
	# Gathering -> Work animation.
	stop_all_units()
	var uw: Unit = player_units()[2]
	var wnode: ResourceNode = w.nearest_node_of_type(uw.global_position, "wood")
	uw.order_gather(wnode)
	var saw_work: bool = await wait_until(func() -> bool: return uw.anim_name == "work", 40000)
	check("l7 gathering uses Work animation", saw_work,
			"anim=%s state=%s" % [uw.anim_name, uw.state])

	# ------------------------------------------------ (m) berry bushes deposit +10 food
	Engine.time_scale = 20.0
	stop_all_units()
	var food_nodes := 0
	for n in w.nodes:
		if n.rtype == "food":
			food_nodes += 1
	check("m1 berry-bush (food) nodes exist", food_nodes >= 4, "food=%d" % food_nodes)
	var fnode: ResourceNode = w.nearest_node_of_type(game.player_tc.global_position, "food")
	check("m2 food node reachable from TC", fnode != null)
	var uf: Unit = player_units()[0]
	var food_start: int = game.resources.food
	uf.order_gather(fnode)
	var saw_harvest: bool = await wait_until(func() -> bool: return uf.anim_name == "harvest", 40000)
	check("m3 gathering food uses Harvest animation", saw_harvest, "anim=%s" % uf.anim_name)
	var food_deposited: bool = await wait_until(func() -> bool: return game.resources.food > food_start, 60000)
	check("m4 gather cycle increased food", food_deposited,
			"food=%d start=%d" % [game.resources.food, food_start])
	check("m5 deposit was exactly +10 food", game.resources.food == food_start + 10,
			"food=%d start=%d" % [game.resources.food, food_start])
	stop_all_units()

	# ------------------------------------------------ (n) militia training at the barracks
	game.resources.food += 500
	game.resources.gold += 500
	game.resources.wood += 500
	var pop_n: int = game.pop_current()
	var food_n: int = game.resources.food
	var gold_n: int = game.resources.gold
	var ok_mil: bool = game.hud.ui_train_militia()
	check("n1 HUD militia train accepted (barracks complete)", ok_mil)
	check("n2 militia cost 60 food + 20 gold deducted",
			game.resources.food == food_n - 60 and game.resources.gold == gold_n - 20,
			"food=%d gold=%d" % [game.resources.food, game.resources.gold])
	var mil_spawned: bool = await wait_until(func() -> bool: return game.pop_current() == pop_n + 1, 60000)
	check("n3 militia spawned", mil_spawned, "pop=%d" % game.pop_current())
	var mil: Unit = null
	for u in game.units:
		if u.team == 0 and u.unit_type == "militia":
			mil = u
	check("n4 militia unit exists with sprite sheet", mil != null and mil.spr != null)
	check("n5 militia attack frames ready for P3", mil != null and mil.sheet_anim_count("attack") >= 16,
			"attack=%d" % (mil.sheet_anim_count("attack") if mil != null else -1))
	if mil != null:
		var mil_from: Vector2 = mil.global_position
		var mil_dest: Vector2i = w.nearest_walkable(w.world_to_cell(mil_from) + Vector2i(4, 0))
		mil.order_move_cell(mil_dest)
		var mil_moved: bool = await wait_until(func() -> bool: return mil.global_position.distance_to(mil_from) > 30.0, 30000)
		check("n6 militia moves on order", mil_moved, "pos=%s from=%s" % [str(mil.global_position), str(mil_from)])

	# ------------------------------------------------ (o) archer training at the barracks
	var pop_o: int = game.pop_current()
	var wood_o: int = game.resources.wood
	var gold_o: int = game.resources.gold
	var ok_arc: bool = game.hud.ui_train_archer()
	check("o1 HUD archer train accepted", ok_arc)
	check("o2 archer cost 50 wood + 40 gold deducted",
			game.resources.wood == wood_o - 50 and game.resources.gold == gold_o - 40,
			"wood=%d gold=%d" % [game.resources.wood, game.resources.gold])
	var arc_spawned: bool = await wait_until(func() -> bool: return game.pop_current() == pop_o + 1, 60000)
	check("o3 archer spawned", arc_spawned, "pop=%d" % game.pop_current())
	var arc: Unit = null
	for u in game.units:
		if u.team == 0 and u.unit_type == "archer":
			arc = u
	check("o4 archer unit exists with sprite sheet", arc != null and arc.spr != null)
	check("o5 archer attack (shoot) frames ready for P3", arc != null and arc.sheet_anim_count("attack") >= 16,
			"attack=%d" % (arc.sheet_anim_count("attack") if arc != null else -1))
	check("o6 arrow projectile sprite extracted", FileAccess.file_exists("res://assets/arrow.png"))
	if arc != null:
		var arc_from: Vector2 = arc.global_position
		var arc_dest: Vector2i = w.nearest_walkable(w.world_to_cell(arc_from) + Vector2i(-4, 0))
		arc.order_move_cell(arc_dest)
		var arc_moved: bool = await wait_until(func() -> bool: return arc.global_position.distance_to(arc_from) > 30.0, 30000)
		check("o7 archer moves on order", arc_moved, "pos=%s from=%s" % [str(arc.global_position), str(arc_from)])

	# ------------------------------------------------ (p) building tier art, scale, mining drop-off
	stop_all_units()
	game.resources.wood += 2000
	game.resources.stone += 2000
	# p-cost: the tower's two-resource price is deducted / refunded as a whole.
	var wood_t: int = game.resources.wood
	var stone_t: int = game.resources.stone
	game.enter_placement("tower")
	check("p1 tower placement deducts 50 wood + 100 stone",
			game.resources.wood == wood_t - 50 and game.resources.stone == stone_t - 100,
			"wood=%d stone=%d" % [game.resources.wood, game.resources.stone])
	game.cancel_placement()
	check("p2 tower cancel refunds both resources",
			game.resources.wood == wood_t and game.resources.stone == stone_t,
			"wood=%d stone=%d" % [game.resources.wood, game.resources.stone])

	# p-art: every building type completes showing its tier-1 sprite.
	var placed_by_type := {}
	for btype in ["town_center", "house", "barracks", "mining_camp", "tower", "blacksmith"]:
		var defsz: Vector2i = game.get_build_def(btype).size
		var spot := Vector2i(-1, -1)
		for dy in range(-26, 27):
			for dx in range(-26, 27):
				var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
				if w.can_place(cand, defsz):
					spot = cand
					break
			if spot.x >= 0:
				break
		var nb = null
		if spot.x >= 0:
			nb = game._spawn_building(btype, 0, spot, true)
		placed_by_type[btype] = nb
		var texpath := ""
		if nb != null and nb.art_sprite != null and nb.art_sprite.texture != null:
			texpath = nb.art_sprite.texture.resource_path
		check("p3 %s completes with tier-1 art sprite" % btype,
				nb != null and nb.art_sprite != null and nb.art_sprite.visible
				and texpath.ends_with("_t1.png"),
				"spot=%s tex=%s" % [str(spot), texpath])

	# p-scale: barracks art is ~1.5x its footprint and bottom-anchored;
	# the name label clears the top of the drawn art.
	var pb = placed_by_type.get("barracks")
	check("p4 barracks available for scale checks", pb != null and pb.art_sprite != null)
	if pb != null and pb.art_sprite != null:
		var disp: Vector2 = Vector2(pb.art_sprite.texture.get_size()) * pb.art_sprite.scale
		var fp := Vector2(pb.size) * World.TILE
		check("p5 barracks art width is 1.5x footprint",
				absf(disp.x - fp.x * Building.ART_SCALE) < 2.0,
				"disp.x=%.1f want=%.1f" % [disp.x, fp.x * Building.ART_SCALE])
		var art_r: Rect2 = pb.art_display_rect()
		check("p6 barracks art bottom flush with footprint bottom",
				absf(art_r.position.y + art_r.size.y - fp.y) < 1.5,
				"bottom=%.1f fp=%.1f" % [art_r.position.y + art_r.size.y, fp.y])
		# Label glyphs are top-aligned in their rect: the text line
		# (~18 px from the rect top) must clear the art's top edge.
		check("p7 barracks label text line sits at/above art top",
				pb._label.position.y + 18.0 <= art_r.position.y + 1.5,
				"label_line_bottom=%.1f art_top=%.1f" % [pb._label.position.y + 18.0, art_r.position.y])

	# p-drop: drop-off routing — mining camp takes stone/gold, TC keeps the rest.
	var camp = placed_by_type.get("mining_camp")
	check("p8 mining camp routes stone drop-off when nearest",
			camp != null and game.get_dropoff_for(0, "stone", camp.position) == camp)
	check("p9 mining camp routes gold drop-off when nearest",
			camp != null and game.get_dropoff_for(0, "gold", camp.position) == camp)
	check("p10 wood still routes to the Town Center",
			camp != null and game.get_dropoff_for(0, "wood", camp.position) == game.player_tc)

	# p-loop: full gather cycle — a villager hauls stone to a camp placed
	# beside a stone cluster instead of walking back to the Town Center.
	var loop_camp = null
	var loop_node: ResourceNode = null
	for n in w.nodes:
		if n.rtype != "stone":
			continue
		for dy in range(-7, 8):
			for dx in range(-7, 8):
				var cand2: Vector2i = n.cell + Vector2i(dx, dy)
				if w.can_place(cand2, Vector2i(3, 3)):
					loop_camp = game._spawn_building("mining_camp", 0, cand2, true)
					loop_node = n
					break
			if loop_camp != null:
				break
		if loop_camp != null:
			break
	check("p11 mining camp staged beside a stone node", loop_camp != null and loop_node != null)
	if loop_camp != null and loop_node != null:
		var uv: Unit = player_units()[0]
		uv.global_position = w.cell_center(w.nearest_walkable(loop_node.cell + Vector2i(2, 2)))
		uv.state = "idle"
		uv.path.clear()
		var stone0: int = game.resources.stone
		uv.order_gather(loop_node)
		var returning: bool = await wait_until(
				func() -> bool: return uv.state == "return" and uv.carry_type == "stone", 60000)
		check("p12 villager returns carrying stone", returning, "state=%s" % uv.state)
		if returning:
			var last_cell: Vector2i = uv.path_cells[uv.path_cells.size() - 1]
			check("p13 return path heads to the mining camp, not the TC",
					w.adjacent_walkable(loop_camp.cells()).has(last_cell),
					"last=%s" % str(last_cell))
		var stone_dep: bool = await wait_until(
				func() -> bool: return game.resources.stone >= stone0 + 10, 60000)
		check("p14 stone deposited (+10)", stone_dep,
				"stone=%d start=%d" % [game.resources.stone, stone0])
		stop_all_units()

	# ------------------------------------------------ (q) painted HUD icons
	var icon_names := ["food", "wood", "gold", "stone", "iron", "pop", "timer",
			"chat", "friends", "gear", "build", "train", "tech",
			"age_1", "age_2", "age_3", "age_4"]
	var missing: Array = []
	for n in icon_names:
		if load("res://assets/icons/%s.png" % n) as Texture2D == null:
			missing.append(n)
	check("q1 all 17 painted icon textures load", missing.is_empty(), str(missing))
	check("q2 age badge shows age_1 at age 1",
			game.hud.age_badge_texture() != null
			and game.hud.age_badge_texture().resource_path.ends_with("age_1.png"),
			str(game.hud.age_badge_texture()))
	game.age = 3
	await get_tree().process_frame
	await get_tree().process_frame
	check("q3 age badge follows Main.age (age_3)",
			game.hud.age_badge_texture() != null
			and game.hud.age_badge_texture().resource_path.ends_with("age_3.png"),
			str(game.hud.age_badge_texture()))
	game.age = 1
	await get_tree().process_frame

	# ------------------------------------------------ (r) VFX layer
	check("r1 vfx layer exists on Main", game.vfx != null and game.vfx is VFX)
	# Water ambience: foam/glints/ripples spawn on the lake map by themselves.
	var water_fx: bool = await wait_until(func() -> bool: return game.vfx.live_count() >= 5, 15000)
	check("r2 water emitters produce live effects", water_fx,
			"live=%d" % game.vfx.live_count())
	# Cap: flood the layer with bursts — the live count must never
	# exceed MAX_LIVE (oldest effects get recycled).
	game.vfx.ambient_enabled = false
	var drained0: bool = await wait_until(func() -> bool: return game.vfx.live_count() == 0, 30000)
	check("r3 effects drain to zero (self-freeing)", drained0, "live=%d" % game.vfx.live_count())
	for i in range(40):
		game.vfx.burst(Vector2(500, 500), [Color(1, 0.8, 0.3)], 8)
	check("r4 live effects capped at MAX_LIVE", game.vfx.live_count() <= VFX.MAX_LIVE
			and game.vfx.live_count() > 200,
			"live=%d cap=%d" % [game.vfx.live_count(), VFX.MAX_LIVE])
	# Combat-ready entry points: spawn, then free themselves cleanly.
	var drained1: bool = await wait_until(func() -> bool: return game.vfx.live_count() == 0, 30000)
	check("r5 burst flood drains too", drained1, "live=%d" % game.vfx.live_count())
	game.vfx.hit_spark(Vector2(600, 600), "player")
	var after_hit: int = game.vfx.live_count()
	check("r6 hit_spark spawns effects (player palette)", after_hit > 0, "live=%d" % after_hit)
	game.vfx.death_smoke(Vector2(640, 600), "enemy")
	check("r7 death_smoke spawns more effects (enemy palette)",
			game.vfx.live_count() > after_hit, "live=%d" % game.vfx.live_count())
	var drained2: bool = await wait_until(func() -> bool: return game.vfx.live_count() == 0, 30000)
	check("r8 combat effects free themselves cleanly", drained2, "live=%d" % game.vfx.live_count())
	game.vfx.ambient_enabled = true

	# ------------------------------------------------ (s) new buildings: lumber / storage / market / dock
	Engine.time_scale = 20.0
	stop_all_units()
	game.resources.wood += 5000
	game.resources.stone += 1000
	var find_spot := func(size: Vector2i, max_r: int) -> Vector2i:
		for dy in range(-max_r, max_r + 1):
			for dx in range(-max_r, max_r + 1):
				var cand: Vector2i = game.player_tc.origin_cell + Vector2i(dx, dy)
				if w.can_place(cand, size):
					return cand
		return Vector2i(-1, -1)
	var find_shore := func(size: Vector2i) -> Vector2i:
		for yy in range(0, World.MAP_H - size.y + 1):
			for xx in range(0, World.MAP_W - size.x + 1):
				var cand := Vector2i(xx, yy)
				if w.can_place(cand, size) and game.is_shore_spot(cand, size):
					return cand
		return Vector2i(-1, -1)
	var find_b := func(btype: String):
		for b in game.buildings:
			if b.btype == btype and b.team == 0:
				return b
		return null

	# s-sprites: all 16 new tier textures load.
	var missing16: Array = []
	for fam in ["lumbercamp", "storage", "market", "dock"]:
		for t in range(1, 5):
			if load("res://assets/buildings/%s_t%d.png" % [fam, t]) as Texture2D == null:
				missing16.append("%s_t%d" % [fam, t])
	check("s1 all 16 new building sprites load", missing16.is_empty(), str(missing16))

	# s-age: a building spawned at age 3 shows its tier-3 art.
	game.age = 3
	var spot_a3: Vector2i = find_spot.call(game.get_build_def("market").size, 30)
	var mkt3 = null
	if spot_a3.x >= 0:
		mkt3 = game._spawn_building("market", 0, spot_a3, true)
	game.age = 1
	await get_tree().process_frame
	check("s2 market spawned at age 3 shows tier-3 art",
			mkt3 != null and mkt3.art_sprite != null and mkt3.art_sprite.texture != null
			and mkt3.art_sprite.texture.resource_path.ends_with("_t3.png"),
			"tex=%s" % (str(mkt3.art_sprite.texture.resource_path) if mkt3 != null and mkt3.art_sprite != null and mkt3.art_sprite.texture != null else "none"))

	# s-flow: each new building goes through the normal placement flow
	# (deduct on enter -> confirm -> construction completes with art).
	var wood_s: int = game.resources.wood
	game.enter_placement("lumber_camp")
	check("s3 lumber placement deducts 100 wood", game.resources.wood == wood_s - 100,
			"wood=%d start=%d" % [game.resources.wood, wood_s])
	var spot_l: Vector2i = find_spot.call(game.get_build_def("lumber_camp").size, 30)
	check("s3 lumber placement confirmed", spot_l.x >= 0 and game.confirm_placement(spot_l),
			"spot=%s" % str(spot_l))
	var lumber_b = find_b.call("lumber_camp")
	var lumber_done: bool = await wait_until(func() -> bool: return lumber_b != null and lumber_b.complete, 90000)
	check("s3 lumber camp completes with tier-1 art",
			lumber_done and lumber_b.art_sprite != null and lumber_b.art_sprite.texture != null
			and lumber_b.art_sprite.texture.resource_path.ends_with("lumbercamp_t1.png"))

	wood_s = game.resources.wood
	game.enter_placement("storage")
	var spot_st: Vector2i = find_spot.call(game.get_build_def("storage").size, 30)
	check("s4 storage deducts 100 wood + confirms",
			game.resources.wood == wood_s - 100 and spot_st.x >= 0 and game.confirm_placement(spot_st),
			"wood=%d spot=%s" % [game.resources.wood, str(spot_st)])
	var storage_b = find_b.call("storage")
	var storage_done: bool = await wait_until(func() -> bool: return storage_b != null and storage_b.complete, 90000)
	check("s4 storage completes with tier-1 art",
			storage_done and storage_b.art_sprite != null and storage_b.art_sprite.texture != null
			and storage_b.art_sprite.texture.resource_path.ends_with("storage_t1.png"))

	wood_s = game.resources.wood
	game.enter_placement("market")
	var spot_mk: Vector2i = find_spot.call(game.get_build_def("market").size, 30)
	check("s5 market deducts 150 wood + confirms",
			game.resources.wood == wood_s - 150 and spot_mk.x >= 0 and game.confirm_placement(spot_mk),
			"wood=%d spot=%s" % [game.resources.wood, str(spot_mk)])
	var market_b = null
	for b in game.buildings:
		if b.btype == "market" and b.origin_cell == spot_mk:
			market_b = b
	var market_done: bool = await wait_until(func() -> bool: return market_b != null and market_b.complete, 90000)
	check("s5 market completes with tier-1 art",
			market_done and market_b.art_sprite != null and market_b.art_sprite.texture != null
			and market_b.art_sprite.texture.resource_path.ends_with("market_t1.png"))

	# s-routing: drop-off competition for the new camps.
	check("s6 wood routes to the lumber camp when nearest",
			lumber_b != null and game.get_dropoff_for(0, "wood", lumber_b.position) == lumber_b)
	check("s6 stone routes to storage when it is nearest",
			storage_b != null and game.get_dropoff_for(0, "stone", storage_b.position) == storage_b)
	check("s6 food routes to storage when it is nearest",
			storage_b != null and game.get_dropoff_for(0, "food", storage_b.position) == storage_b)
	check("s6 gold does NOT route to the lumber camp",
			lumber_b != null and game.get_dropoff_for(0, "gold", lumber_b.position) != lumber_b)

	# s-loop: full gather cycle — a villager hauls wood to a lumber camp
	# placed beside a forest instead of walking back to the Town Center.
	var loop_lumber = null
	var loop_wnode: ResourceNode = null
	for n in w.nodes:
		if n.rtype != "wood":
			continue
		# The tree must be gatherable: some adjacent cell reachable
		# from the player base (dense forest can pocket a tree off).
		var reach_adj: Array = []
		for adj_c2 in w.adjacent_walkable([n.cell]):
			if not w.get_path_cells(w.player_base, adj_c2).is_empty():
				reach_adj.append(adj_c2)
		if reach_adj.is_empty():
			continue
		# Closest valid spot to this tree (the camp must be the
		# villager's nearest drop-off for the loop below to use it)
		# whose footprint does NOT seal the tree: at least one
		# reachable adjacent cell must stay outside the footprint.
		var best_spot := Vector2i(-1, -1)
		var best_d := 1 << 30
		for dy in range(-7, 8):
			for dx in range(-7, 8):
				var dd0: int = maxi(absi(dx), absi(dy))
				if dd0 < 2:
					continue
				var cand3: Vector2i = n.cell + Vector2i(dx, dy)
				if not w.can_place(cand3, Vector2i(3, 3)):
					continue
				var seals := true
				for ra in reach_adj:
					if not (ra.x >= cand3.x and ra.x < cand3.x + 3
							and ra.y >= cand3.y and ra.y < cand3.y + 3):
						seals = false
						break
				if not seals and dd0 < best_d:
					best_d = dd0
					best_spot = cand3
		if best_spot.x >= 0:
			loop_lumber = game._spawn_building("lumber_camp", 0, best_spot, true)
			loop_wnode = n
			break
	check("s7 lumber camp staged beside a tree node", loop_lumber != null and loop_wnode != null)
	if loop_lumber != null and loop_wnode != null:
		var uw2: Unit = player_units()[0]
		# Stand on a node-adjacent cell that the TC can actually reach
		# (dense forest can enclose single walkable pockets; a walking
		# unit could never be inside one, so don't teleport into one).
		var stand_cell: Vector2i = w.nearest_walkable(loop_wnode.cell + Vector2i(2, 2))
		for adj_c in w.adjacent_walkable([loop_wnode.cell]):
			if not w.get_path_cells(game.world.player_base, adj_c).is_empty():
				stand_cell = adj_c
				break
		uw2.global_position = w.cell_center(stand_cell)
		uw2.state = "idle"
		uw2.path.clear()
		var wood_loop0: int = game.resources.wood
		uw2.order_gather(loop_wnode)
		var wreturning: bool = await wait_until(
				func() -> bool: return uw2.state == "return" and uw2.carry_type == "wood", 60000)
		check("s7 villager returns carrying wood", wreturning, "state=%s" % uw2.state)
		if wreturning:
			var last_wcell: Vector2i = uw2.path_cells[uw2.path_cells.size() - 1]
			check("s7 return path heads to the lumber camp, not the TC",
					w.adjacent_walkable(loop_lumber.cells()).has(last_wcell),
					"last=%s" % str(last_wcell))
		var wood_dep: bool = await wait_until(
				func() -> bool: return game.resources.wood >= wood_loop0 + 10, 60000)
		check("s7 wood deposited at the lumber camp (+10)", wood_dep,
				"wood=%d start=%d" % [game.resources.wood, wood_loop0])
		stop_all_units()

	# s-market: exchange math + insufficient-funds guards.
	game.resources.food = 150
	game.resources.gold = 0
	var sell_ok: bool = game.market_sell("food")
	check("s8 sell 100 food -> +40 gold", sell_ok and game.resources.food == 50 and game.resources.gold == 40,
			"food=%d gold=%d" % [game.resources.food, game.resources.gold])
	var sell_again: bool = game.market_sell("food")
	check("s8 sell blocked when under 100 of the resource",
			not sell_again and game.resources.food == 50 and game.resources.gold == 40,
			"food=%d gold=%d" % [game.resources.food, game.resources.gold])
	game.resources.gold = 100
	var wood_buy0: int = game.resources.wood
	var buy_ok: bool = game.market_buy("wood")
	check("s8 buy 100 wood -> -60 gold", buy_ok and game.resources.gold == 40
			and game.resources.wood == wood_buy0 + 100,
			"gold=%d wood=%d start=%d" % [game.resources.gold, game.resources.wood, wood_buy0])
	var buy_again: bool = game.market_buy("stone")
	check("s8 buy blocked when gold under 60",
			not buy_again and game.resources.gold == 40,
			"gold=%d" % game.resources.gold)

	# s-dock: shoreline-only placement, through the normal flow.
	var dock_size: Vector2i = game.get_build_def("dock").size
	var shore_spot: Vector2i = find_shore.call(dock_size)
	check("s9 a shoreline spot exists by the lake", shore_spot.x >= 0)
	var inland_spot: Vector2i = find_spot.call(dock_size, 20)
	check("s9 inland spot is not a shore spot",
			inland_spot.x >= 0 and not game.is_shore_spot(inland_spot, dock_size),
			"spot=%s" % str(inland_spot))
	check("s9 placement_valid_at rejects dock inland, accepts at shore",
			inland_spot.x >= 0 and shore_spot.x >= 0
			and not game.placement_valid_at(inland_spot, "dock")
			and game.placement_valid_at(shore_spot, "dock"))
	wood_s = game.resources.wood
	game.enter_placement("dock")
	check("s9 dock placement deducts 150 wood", game.resources.wood == wood_s - 150,
			"wood=%d start=%d" % [game.resources.wood, wood_s])
	var inland_ok: bool = game.confirm_placement(inland_spot)
	check("s9 dock confirm inland is rejected (still placing)",
			not inland_ok and game.placing_type == "dock")
	var shore_ok: bool = game.confirm_placement(shore_spot)
	check("s9 dock confirm at the shore succeeds", shore_ok)
	var dock_b = find_b.call("dock")
	var dock_done: bool = await wait_until(func() -> bool: return dock_b != null and dock_b.complete, 90000)
	check("s9 dock completes with tier-1 art",
			dock_done and dock_b.art_sprite != null and dock_b.art_sprite.texture != null
			and dock_b.art_sprite.texture.resource_path.ends_with("dock_t1.png"))
	stop_all_units()

	# s-hud: the Build page carries the 4 new cards + market trade buttons.
	check("s10 build page has lumber/storage/market/dock buttons",
			game.hud._lumber_btn != null and game.hud._storage_btn != null
			and game.hud._market_btn != null and game.hud._dock_btn != null)
	check("s10 market trade buttons exist (3 sell + 3 buy)",
			game.hud._mkt_sell_btns.size() == 3 and game.hud._mkt_buy_btns.size() == 3,
			"sell=%d buy=%d" % [game.hud._mkt_sell_btns.size(), game.hud._mkt_buy_btns.size()])

	# ------------------------------------------------ (t) P3: combat, enemy faction + AI, age-up, fog, win/lose
	Engine.time_scale = 20.0
	stop_all_units()
	game.resources.food += 2000
	game.resources.wood += 2000
	game.resources.gold += 2000
	game.resources.stone += 2000
	# Clear the legacy sections' military so tower attribution below is clean.
	for u in game.units.duplicate():
		if u.team == 0 and u.is_military():
			u.take_damage(99999.0)
	await get_tree().process_frame
	await get_tree().process_frame

	# t0: the enemy stronghold is fully built (barracks + 2 houses + tower).
	var ebarr = game.get_team_barracks(1)
	var ehouse_n := 0
	var etower = null
	for b in game.buildings:
		if b.team == 1 and b.btype == "house":
			ehouse_n += 1
		if b.team == 1 and b.btype == "tower":
			etower = b
	check("t0 enemy base has barracks + 2 houses + watch tower",
			ebarr != null and ehouse_n >= 2 and etower != null,
			"ebarr=%s houses=%d etower=%s" % [str(ebarr), ehouse_n, str(etower)])

	# t1: enemy art — blue tier art on buildings, blue sheets on units.
	check("t1 enemy TC wears the blue tier art",
			game.enemy_tc.art_sprite != null and game.enemy_tc.art_sprite.texture != null
			and game.enemy_tc.art_sprite.texture.resource_path.contains("enemy"),
			"tex=%s" % (str(game.enemy_tc.art_sprite.texture.resource_path) if game.enemy_tc.art_sprite != null and game.enemy_tc.art_sprite.texture != null else "none"))
	check("t1 enemy barracks wears the blue tier art",
			ebarr != null and ebarr.art_sprite != null and ebarr.art_sprite.texture != null
			and ebarr.art_sprite.texture.resource_path.contains("enemy"))
	var eu0: Unit = null
	for u in game.units:
		if u.team == 1:
			eu0 = u
			break
	check("t1 enemy units load the blue sheet",
			eu0 != null and eu0._data.get("tex") != null
			and eu0._data.tex.resource_path.contains("enemy"),
			"tex=%s" % (str(eu0._data.tex.resource_path) if eu0 != null and eu0._data.get("tex") != null else "none"))

	# t2: melee combat — a player Militia hunts down an enemy villager.
	var arena: Vector2i = w.nearest_walkable(game.player_tc.origin_cell + Vector2i(10, -6))
	var mil2: Unit = game._make_unit(0, w.cell_center(arena), "militia")
	var evic: Unit = game._make_unit(1, w.cell_center(w.nearest_walkable(arena + Vector2i(2, 0))), "villager")
	var evic_hp0: float = evic.hp
	mil2.order_attack(evic)
	var evic_hurt: bool = await wait_until(
			func() -> bool: return not is_instance_valid(evic) or evic.hp < evic_hp0, 30000)
	check("t2 militia attack damages the enemy villager", evic_hurt)
	# Flee pass: a hurt villager no longer stands there to be killed —
	# it bolts for its own Town Center and garrisons inside.
	var evic_fled: bool = await wait_until(
			func() -> bool: return not is_instance_valid(evic) or evic.state == "flee" or evic.state == "garrison", 30000)
	check("t2 the hurt villager flees instead of fighting on", evic_fled,
			"state=%s" % (evic.state if is_instance_valid(evic) else "gone"))
	if is_instance_valid(evic):
		evic.take_damage(99999.0)
	var evic_gone: bool = await wait_until(
			func() -> bool: return not is_instance_valid(evic), 90000)
	check("t2 villager death flow removes it", evic_gone)
	if is_instance_valid(mil2):
		mil2.take_damage(99999.0)

	# t3/t4: the counter table + the archer's projectile.
	var arc2: Unit = game._make_unit(0, w.cell_center(arena), "archer")
	var emil: Unit = game._make_unit(1, w.cell_center(w.nearest_walkable(arena + Vector2i(4, 0))), "militia")
	var vil0: Unit = player_units()[0]
	check("t4 militia strikes archer-class at x1.5",
			absf(Stats.damage("militia", arc2) - 12.0) < 0.01,
			"dmg=%f" % Stats.damage("militia", arc2))
	check("t4 archer strikes villager-class at x1.25",
			absf(Stats.damage("archer", vil0) - 7.5) < 0.01,
			"dmg=%f" % Stats.damage("archer", vil0))
	check("t4 archer damage vs buildings is halved, militia full",
			absf(Stats.damage("archer", game.player_tc) - 3.0) < 0.01
			and absf(Stats.damage("militia", game.player_tc) - 8.0) < 0.01,
			"arc=%f mil=%f" % [Stats.damage("archer", game.player_tc), Stats.damage("militia", game.player_tc)])
	var emil_hp0: float = emil.hp
	arc2.order_attack(emil)
	var shot_fired: bool = await wait_until(
			func() -> bool: return game.projectiles.size() > 0 or not is_instance_valid(emil) or emil.hp < emil_hp0, 20000)
	check("t3 archer looses a visible arrow projectile", shot_fired,
			"proj=%d" % game.projectiles.size())
	var arrow_hit: bool = await wait_until(
			func() -> bool: return not is_instance_valid(emil) or emil.hp < emil_hp0, 30000)
	check("t3 the arrow lands and damages at range", arrow_hit,
			"hp=%f was=%f" % [(emil.hp if is_instance_valid(emil) else -1.0), emil_hp0])
	if is_instance_valid(emil):
		emil.take_damage(99999.0)
	if is_instance_valid(arc2):
		arc2.take_damage(99999.0)

	# t5: a Watch Tower fires on an enemy in range (attributed by projectile owner).
	var tw_spot := Vector2i(-1, -1)
	for dy in range(-4, 9):
		for dx in range(-4, 13):
			var cand: Vector2i = arena + Vector2i(dx, dy)
			if w.can_place(cand, Vector2i(2, 2)):
				tw_spot = cand
				break
		if tw_spot.x >= 0:
			break
	var tw = null
	if tw_spot.x >= 0:
		tw = game._spawn_building("tower", 0, tw_spot, true)
	check("t5 tower staged", tw != null, "spot=%s" % str(tw_spot))
	var ev2: Unit = game._make_unit(1, w.cell_center(w.nearest_walkable(tw_spot + Vector2i(4, 1))), "villager")
	var ev2_hp0: float = ev2.hp
	var tower_shot: bool = await wait_until(
			func() -> bool: return game.projectiles.any(func(p) -> bool: return p.get("attacker") == tw), 30000)
	check("t5 watch tower looses arrows at enemies in range", tower_shot and tw != null)
	var tower_hit: bool = await wait_until(
			func() -> bool: return not is_instance_valid(ev2) or ev2.hp < ev2_hp0, 30000)
	check("t5 tower arrows damage the enemy", tower_hit)
	if is_instance_valid(ev2):
		ev2.take_damage(99999.0)

	# t6: AI economy (its own ledger fills via real deposits) + production.
	var dep0: int = game.enemy_ai.deposits
	var econ: bool = await wait_until(
			func() -> bool: return game.enemy_ai.deposits > dep0, 90000)
	check("t6 enemy villagers gather + deposit into the AI ledger", econ,
			"dep=%d was=%d" % [game.enemy_ai.deposits, dep0])
	# Clear standing-army leftovers from the combat sections so the
	# production caps don't mask the ledger -> queue path under test.
	for lu in game.units.duplicate():
		if lu.team == 1 and lu.is_military():
			lu.take_damage(99999.0)
	await get_tree().process_frame
	game.enemy_ai.res.food += 500
	game.enemy_ai.res.wood += 500
	game.enemy_ai.res.gold += 500
	game.enemy_ai._production()
	check("t6 AI queues training (villagers or military) from its ledger",
			game.enemy_tc.train_queue > 0 or (ebarr != null and ebarr.train_queue > 0),
			"tc_q=%d barr_q=%d" % [game.enemy_tc.train_queue, (ebarr.train_queue if ebarr != null else -1)])

	# t7: attack waves — re-enabled with the AI's own grown army.
	for i in range(3):
		game._make_unit(1, w.cell_center(w.nearest_walkable(game.enemy_tc.origin_cell + Vector2i(5 + i, 2))), "militia")
	game.enemy_ai.waves_enabled = true
	var waves0: int = game.enemy_ai.waves_launched
	var waved: bool = await wait_until(
			func() -> bool: return game.enemy_ai.waves_launched > waves0, 30000)
	check("t7 AI launches an attack wave of 2+ units",
			waved and game.enemy_ai.last_wave_size >= 2,
			"waves=%d size=%d" % [game.enemy_ai.waves_launched, game.enemy_ai.last_wave_size])
	var any_targeting := false
	for u in game.units:
		if u.team == 1 and u.attack_target == game.player_tc:
			any_targeting = true
	check("t7 wave units march on the player Town Center", any_targeting)
	game.enemy_ai.waves_enabled = false
	for u in game.units.duplicate():
		if u.team == 1 and u.is_military():
			u.take_damage(99999.0)

	# t8: Feudal age-up — guards, research, tier + badge swap, tower buff.
	game.resources.food = 0
	check("t8 age-up blocked without 500 food",
			not game.can_age_up() and not game.start_age_up())
	game.resources.food = 1000
	check("t8 age-up available with food + 2 buildings", game.can_age_up())
	var age_ok: bool = game.start_age_up()
	check("t8 research starts and deducts 500 food",
			age_ok and game.resources.food == 500 and game.age_researching and game.age == 1,
			"food=%d researching=%s age=%d" % [game.resources.food, str(game.age_researching), game.age])
	game.age_timer = 0.05
	var aged: bool = await wait_until(func() -> bool: return game.age == 2, 20000)
	check("t8 research completes into Feudal (age II)", aged)
	var barr1 = game.get_barracks()
	check("t8 player buildings swap to tier-2 art",
			barr1 != null and barr1.tier == 2 and barr1.art_sprite != null
			and barr1.art_sprite.texture != null
			and barr1.art_sprite.texture.resource_path.ends_with("_t2.png"),
			"tier=%s" % (str(barr1.tier) if barr1 != null else "none"))
	var badge2: bool = await wait_until(
			func() -> bool: return (game.hud.age_badge_texture() != null
			and game.hud.age_badge_texture().resource_path.ends_with("age_2.png")), 10000)
	check("t8 HUD badge swaps to the Feudal badge", badge2)
	check("t8 Feudal towers hit harder", Stats.tower_atk(2) > Stats.tower_atk(1),
			"t1=%f t2=%f" % [Stats.tower_atk(1), Stats.tower_atk(2)])

	# t9: Fog of War states + entity visibility.
	check("t9 fog grid covers the map",
			game.fog != null and game.fog.state.size() == World.MAP_W * World.MAP_H)
	check("t9 the player base is visible",
			game.fog.is_visible_cell(game.player_tc.origin_cell + Vector2i(1, 1)))
	var far_cell: Vector2i = game.enemy_tc.origin_cell + Vector2i(1, 1)
	check("t9 the enemy base starts unexplored + hidden",
			not game.fog.is_explored_cell(far_cell) and not game.enemy_tc.visible)
	var scout: Unit = player_units()[0]
	scout.global_position = w.cell_center(w.nearest_walkable(game.enemy_tc.origin_cell + Vector2i(-2, 1)))
	game.fog.update_fog()
	check("t9 scouting reveals the enemy base",
			game.fog.is_visible_cell(far_cell) and game.enemy_tc.visible)
	var ev9: Unit = game._make_unit(1, w.cell_center(w.nearest_walkable(game.enemy_tc.origin_cell + Vector2i(0, 4))), "villager")
	game.fog.update_fog()
	check("t9 an enemy unit on a visible tile is shown", ev9.visible)
	scout.global_position = w.cell_center(game.player_tc.origin_cell + Vector2i(1, 4))
	game.fog.update_fog()
	check("t9 enemy unit hides again unscouted; tile stays explored",
			not ev9.visible and game.fog.cell_state(far_cell) == 1,
			"state=%d" % game.fog.cell_state(far_cell))
	ev9.take_damage(99999.0)

	# ---------------------------------------------------------------
	# u-series: self-drawn pass (farm/fields, walls/gates, castle,
	# Age III, spearman/cavalry/ram). Style gate record: every piece
	# below shipped only after passing the contact-sheet gate (see
	# README "New assets"); the wall set passed with a flatness note.
	# ---------------------------------------------------------------
	for p in ["farm_t1", "farm_t2", "farm_t3", "farm_t4", "castle_t1", "castle_t2",
			"castle_t3", "castle_t4", "wallwood", "wallwood_corner", "gatewood",
			"wallstone", "wallstone_corner", "gatestone"]:
		check("u0 asset buildings/%s.png exists" % p,
				ResourceLoader.exists("res://assets/buildings/%s.png" % p))
	for s in range(1, 5):
		check("u0 asset fields/field_s%d.png exists" % s,
				ResourceLoader.exists("res://assets/fields/field_s%d.png" % s))
	for kind in ["spearman", "cavalry", "ram"]:
		check("u0 %s sheet + frames load (both teams)" % kind,
				not Unit.get_sheet(kind, 0).is_empty() and not Unit.get_sheet(kind, 1).is_empty())
	check("u0 farm/castle tier art resolves", Building.tier_texture("farm", 3) != null
			and Building.tier_texture("castle", 3) != null)
	check("u0 wall corner variant resolves", Building.wall_texture("wallstone", "corner") != null)
	check("u0 HUD has the new cards", game.hud._spearman_btn != null and game.hud._cavalry_btn != null
			and game.hud._ram_btn != null and game.hud._farm_btn != null and game.hud._castle_btn != null
			and game.hud._age3_btn != null and game.hud.has_method("ui_age_up3"))

	# Counters incl. the new classes (pure stat math on live units).
	var u_sp = game._make_unit(0, Vector2(300, 300), "spearman")
	var u_cav_e = game._make_unit(1, Vector2(340, 300), "cavalry")
	var u_arc = game._make_unit(0, Vector2(380, 300), "archer")
	var u_ram = game._make_unit(0, Vector2(420, 300), "ram")
	check("u1 spearman x2 vs cavalry", is_equal_approx(Stats.damage("spearman", u_cav_e), 14.0),
			"dmg=%s" % Stats.damage("spearman", u_cav_e))
	check("u1 archer x1.25 vs spearman", is_equal_approx(Stats.damage("archer", u_sp), 7.5))
	check("u1 cavalry x1.5 vs archer", is_equal_approx(Stats.damage("cavalry", u_arc), 13.5))
	check("u1 ram x6 vs buildings", is_equal_approx(Stats.damage("ram", game.player_tc), 24.0))
	check("u1 ram x0.1 vs units", is_equal_approx(Stats.damage("ram", u_sp), 0.4))
	check("u1 arrows x0.25 vs ram", is_equal_approx(Stats.damage("archer", u_ram), 1.5))
	check("u1 cavalry speed is 1.6x villager", is_equal_approx(
			Stats.unit_stat("cavalry", "speed") / Stats.unit_stat("villager", "speed"), 1.6))

	# Training + age locks at the single Barracks.
	game.resources["food"] = 5000
	game.resources["wood"] = 5000
	game.resources["gold"] = 5000
	game.resources["stone"] = 5000
	var barr_spot := find_spot(Vector2i(3, 3), Vector2i(16, 50))
	var my_barr = game._spawn_building("barracks", 0, barr_spot, true)
	game.set_team_age(0, 1)
	check("u2 spearman trains in Age I", game.train_spearman())
	check("u2 cavalry locked in Age I", not game.train_cavalry())
	game.set_team_age(0, 2)
	check("u2 cavalry trains in Feudal", game.train_cavalry())
	check("u2 ram locked in Feudal", not game.train_ram())
	var got_cav: bool = await wait_until(func() -> bool:
		for u in game.units:
			if u.team == 0 and u.unit_type == "cavalry":
				return true
		return false, 15000)
	check("u2 cavalry actually spawns from the Barracks", got_cav)

	# Age III research flow (Barracks + Blacksmith present).
	var smith = game._spawn_building("blacksmith", 0, find_spot(Vector2i(3, 3), Vector2i(22, 50)), true)
	check("u3 Age III research can start", game.start_age_up3())
	game.age_timer = 0.01
	game._process(0.05)
	check("u3 Age III reached, buildings swap to tier 3", game.age == 3 and my_barr.tier == 3,
			"age=%d tier=%d" % [game.age, my_barr.tier])
	check("u3 ram trains in Age III", game.train_ram())
	var got_ram: bool = await wait_until(func() -> bool:
		for u in game.units:
			if u.team == 0 and u.unit_type == "ram":
				return true
		return false, 15000)
	check("u3 ram actually spawns", got_ram)

	# Castle: buildable in Age III and fires like a super-tower.
	game.enter_placement("castle")
	var castle_spot := find_spot(Vector2i(4, 4), Vector2i(26, 46))
	check("u4 castle placement confirms", game.confirm_placement(castle_spot))
	var castle: Building = null
	for b in game.buildings:
		if b.btype == "castle" and b.team == 0:
			castle = b
	check("u4 castle exists with 1600 HP", castle != null and is_equal_approx(castle.max_hp, 1600.0))
	castle.complete = true
	castle.progress = 1.0
	if castle.art_sprite != null:
		castle.art_sprite.visible = true
	var dummy = game._make_unit(1, castle.position + Vector2(120, 64), "militia")
	game.projectiles.clear()
	game._update_towers(1.3)
	check("u4 castle fires arrows at enemies in range", game.projectiles.size() > 0,
			"proj=%d" % game.projectiles.size())
	dummy.take_damage(99999.0)

	# Farm + fields: place a plot, tend it through growth to a harvest.
	var farm = game._spawn_building("farm", 0, find_spot(Vector2i(3, 3), Vector2i(14, 44)), true)
	game.placing_field = true
	var field_cell := Vector2i(-1, -1)
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cand: Vector2i = farm.origin_cell + Vector2i(1, 1) + Vector2i(dx, dy)
				if field_cell.x < 0 and game.field_valid_at(cand):
					field_cell = cand
	check("u5 field plot places near the Farm", field_cell.x >= 0 and game.confirm_field_placement(field_cell))
	game.placing_field = false
	var plot: FieldPlot = game.field_at_cell(field_cell)
	check("u5 plot registered to the farm", plot != null and plot.farm == farm and game.fields.size() > 0)
	var tender: Unit = player_units()[0]
	# Stand the tender beside the plot first (wherever earlier
	# sections left it, the order's path must not depend on that).
	tender.global_position = game.world.cell_center(field_cell + Vector2i(1, 0))
	tender.state = "idle"
	tender.path.clear()
	tender.order_field(plot)
	check("u5 villager takes the field order", tender.state == "to_field" and tender.target_field == plot)
	tender.global_position = game.world.cell_center(field_cell + Vector2i(1, 0))
	tender._on_arrive()
	var food_u5: int = game.resources.food
	for i in range(4):
		tender._process(2.1)
	# The harvest yields FIELD_YIELD food: either still on the
	# tender's back or already deposited if a drop-off was in reach
	# of the manually driven ticks.
	check("u5 tend loop grows then harvests (carry 10 food, plot regrows)",
			plot.stage == 1 and plot.harvests_left == Stats.FIELD_HARVESTS - 1
			and (tender.carry_amount == Stats.FIELD_YIELD
					or game.resources.food >= food_u5 + Stats.FIELD_YIELD),
			"carry=%d stage=%d left=%d" % [tender.carry_amount, plot.stage, plot.harvests_left])
	plot.advance()
	plot.advance()
	plot.on_harvested()
	plot.advance()
	plot.advance()
	plot.on_harvested()
	check("u5 exhausted plot lies bare after %d harvests" % Stats.FIELD_HARVESTS,
			plot.stage == 0 and plot.harvests_left == 0, "stage=%d left=%d" % [plot.stage, plot.harvests_left])
	plot.advance()
	check("u5 re-tilling a bare plot restarts it", plot.stage == 1 and plot.harvests_left == Stats.FIELD_HARVESTS)
	tender.state = "idle"
	tender.target_field = null

	# Walls block A* for everyone; a gate passes only its owner.
	var line_x := -1
	var line_y := -1
	for x in range(24, 44):
		for y0 in range(16, 48):
			var clear := true
			for k in range(9):
				if game.world.is_solid(Vector2i(x, y0 + k)):
					clear = false
			if clear and not game.world.is_solid(Vector2i(x - 2, y0 + 4)) and not game.world.is_solid(Vector2i(x + 2, y0 + 4)):
				line_x = x
				line_y = y0
				break
		if line_x >= 0:
			break
	check("u6 found an open corridor for the wall line", line_x >= 0, "x=%d y=%d" % [line_x, line_y])
	var w_from := Vector2i(line_x - 2, line_y + 4)
	var w_to := Vector2i(line_x + 2, line_y + 4)
	var gap_cell := Vector2i(line_x, line_y + 4)
	# A finite wall in open ground can always be walked AROUND — the
	# real assertions are about crossing the wall column itself.
	var crosses := func(p: Array) -> bool:
		for c in p:
			if c.x == line_x and c.y >= line_y and c.y <= line_y + 8:
				return true
		return false
	check("u6 open ground paths across", crosses.call(game.world.get_path_cells(w_from, w_to, 0)))
	var wall_segs: Array = []
	for k in range(9):
		if k == 4:
			continue
		wall_segs.append(game._spawn_building("wallwood", 0, Vector2i(line_x, line_y + k), true))
	check("u6 wall line still paths through the gap",
			game.world.get_path_cells(w_from, w_to, 0).has(gap_cell))
	wall_segs.append(game._spawn_building("wallwood", 0, Vector2i(line_x, line_y + 4), true))
	check("u6 sealed wall blocks crossing for BOTH teams (detour only)",
			not crosses.call(game.world.get_path_cells(w_from, w_to, 0))
			and not crosses.call(game.world.get_path_cells(w_from, w_to, 1))
			and not game.world.get_path_cells(w_from, w_to, 0).is_empty())
	var mid_seg: Building = wall_segs[wall_segs.size() - 1]
	mid_seg.take_damage(99999.0)
	await get_tree().process_frame
	var gate = game._spawn_building("gatewood", 0, Vector2i(line_x, line_y + 4), true)
	check("u6 gate passes the OWNER team only",
			game.world.get_path_cells(w_from, w_to, 0).has(gap_cell)
			and not game.world.get_path_cells(w_from, w_to, 1).has(gap_cell))
	gate.take_damage(99999.0)
	await get_tree().process_frame
	check("u6 destroyed gate reopens its cell to everyone",
			game.world.get_path_cells(w_from, w_to, 0).has(gap_cell)
			and game.world.get_path_cells(w_from, w_to, 1).has(gap_cell))
	for s in wall_segs:
		if is_instance_valid(s) and not s.destroyed:
			s.take_damage(99999.0)
	await get_tree().process_frame
	check("u6 walls removed cleanly (crossing restored)",
			crosses.call(game.world.get_path_cells(w_from, w_to, 0)))

	# Enemy AI: ages to III on wave 4 and fields cavalry from Feudal.
	game.enemy_ai.waves_launched = 3
	game.enemy_ai.launch_wave()
	check("u7 AI reaches Age III on its 4th wave", int(game.team_age.get(1, 1)) == 3,
			"age=%d" % int(game.team_age.get(1, 1)))
	game.enemy_ai.credit("food", 3000)
	game.enemy_ai.credit("gold", 3000)
	game.enemy_ai.credit("wood", 3000)
	var ai_barr = game.get_team_barracks(1)
	var ai_cav := false
	for i in range(16):
		game.enemy_ai._production()
		if ai_barr != null and ai_barr.train_queue > 0:
			ai_barr._process(6.0)
		if game.enemy_tc != null and game.enemy_tc.train_queue > 0:
			game.enemy_tc._process(6.0)
		for u in game.units:
			if u.team == 1 and u.unit_type == "cavalry":
				ai_cav = true
		if ai_cav:
			break
	check("u7 AI fields cavalry in later production", ai_cav)

	# t10: annihilation — the enemy TC falling no longer ends the
	# match while the enemy keeps living villagers AND its Barracks.
	game.enemy_tc.take_damage(99999.0)
	check("t10 enemy TC down but the side fights on (villagers + Barracks remain)",
			game.match_over == "" and game.enemy_tc_destroyed and not game.hud._end_panel.visible,
			"over=%s" % game.match_over)
	# Finish the annihilation: kill every enemy unit, then the trainer.
	for u in game.units.duplicate():
		if u.team == 1:
			u.take_damage(99999.0)
	var ebarr_down = game.get_team_barracks(1)
	if ebarr_down != null:
		ebarr_down.take_damage(99999.0)
	var swept: bool = await wait_until(func() -> bool: return game.match_over == "victory", 30000)
	check("t10 annihilation (no villagers, no Barracks) wins the match", swept,
			"over=%s" % game.match_over)
	check("t10 victory panel shows with the quét sạch note, simulation pauses, enemy side eliminated",
			game.hud._end_panel.visible and game.paused and game._enemy_side_eliminated()
			and game.hud._end_note.text.contains("quét sạch"),
			"note=%s" % game.hud._end_note.text)

	# t11: defeat — on a fresh instance so the main one stays won.
	var game2 = load("res://main.tscn").instantiate()
	add_child(game2)
	await get_tree().process_frame
	await get_tree().process_frame
	game2.enemy_ai.waves_enabled = false
	game2.player_tc.take_damage(99999.0)
	check("t11 losing the player TC ends in defeat",
			game2.match_over == "defeat" and game2.hud._end_panel.visible,
			"over=%s" % game2.match_over)
	remove_child(game2)
	game2.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ unit display ruler (scale pass)
	# Every type's sprite must carry its per-type display scale, and the
	# rendered idle body sizes must land on the ruler: the armoured
	# infantry share H = 34.3 world px (±5%; the whole ruler came down
	# by a uniform 0.72 factor so infantry stand about as tall as a
	# House door). The Villager has its own smaller band — about
	# 0.95 * the Militia's height (±1.5 px) and a front width no wider
	# than the Militia's — so the civilian reads as the smallest person
	# on the field. Cavalry ~1.30*H tall and ~1.3 tiles long, Ram ~2.2
	# tiles long and no taller than 1.5*H.
	var ruler_h := 34.3
	var militia_h := Unit.rendered_body_height("militia")
	var ruler_pos: Vector2 = game.player_tc.position + Vector2(0, 260)
	for kind in ["villager", "militia", "archer", "spearman", "cavalry", "ram"]:
		var ru: Unit = game._make_unit(0, ruler_pos, kind)
		check("v-%s sprite uses its display scale" % kind,
				ru.spr != null and absf(ru.disp_scale - Unit.display_scale_for(kind)) < 0.001
				and absf(ru.spr.scale.y - ru.disp_scale) < 0.001,
				"scale=%s want=%s" % [ru.disp_scale, Unit.display_scale_for(kind)])
		var bh := Unit.rendered_body_height(kind)
		if kind == "villager":
			check("v-villager rendered body height in its own smaller band",
					bh >= militia_h * 0.95 - 1.5 and bh <= militia_h * 0.95 + 1.5,
					"h=%.1f target=%.1f" % [bh, militia_h * 0.95])
			check("v-villager rendered front width no wider than militia",
					Unit.rendered_front_width("villager") <= Unit.rendered_front_width("militia") + 0.01,
					"w=%.1f mw=%.1f" % [Unit.rendered_front_width("villager"),
							Unit.rendered_front_width("militia")])
		elif kind in ["militia", "archer", "spearman"]:
			check("v-%s rendered body height on the infantry ruler" % kind,
					bh >= ruler_h * 0.95 and bh <= ruler_h * 1.05, "h=%.1f" % bh)
		elif kind == "cavalry":
			check("v-cavalry rendered height ~1.30*H",
					bh >= ruler_h * 1.17 and bh <= ruler_h * 1.43, "h=%.1f" % bh)
			var cl := Unit.rendered_side_length(kind)
			check("v-cavalry rendered length ~1.3 tiles",
					cl >= 38.4 and cl <= 51.2, "len=%.1f" % cl)
		elif kind == "ram":
			var rl := Unit.rendered_side_length(kind)
			check("v-ram rendered length ~2.2 tiles",
					rl >= 66.0 and rl <= 78.0, "len=%.1f" % rl)
			check("v-ram rendered height under 1.5*H",
					Unit.rendered_full_height(kind) <= ruler_h * 1.5 + 2.0,
					"h=%.1f" % Unit.rendered_full_height(kind))
		game.units.erase(ru)
		ru.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (u) biomes + modifiers + panel
	# Modifier table values per biome (Grassland = identity baseline).
	check("u1 grassland modifiers are identity",
			Biomes.mod("grassland", "move") == 1.0 and Biomes.mod("grassland", "yield_gold") == 1.0
			and Biomes.mod("grassland", "field_growth") == 1.0 and Biomes.mod("grassland", "cavalry_move") == 1.0)
	check("u2 desert modifiers",
			Biomes.mod("desert", "move") == 0.95 and Biomes.mod("desert", "yield_wood") == 0.8
			and Biomes.mod("desert", "yield_gold") == 1.3 and Biomes.mod("desert", "yield_stone") == 1.2
			and Biomes.mod("desert", "field_growth") == 0.7 and Biomes.mod("desert", "field_yield") == 0.8
			and Biomes.mod("desert", "cavalry_move") == 1.1)
	check("u3 snow modifiers",
			Biomes.mod("snow", "move") == 0.9 and Biomes.mod("snow", "cavalry_move") == 0.85
			and Biomes.mod("snow", "yield_wood") == 1.3 and Biomes.mod("snow", "yield_food") == 0.9
			and Biomes.mod("snow", "field_growth") == 0.6 and Biomes.mod("snow", "yield_gold") == 1.0)
	# Delivered amounts follow the active biome (pure functions of it).
	check("u4 grassland delivery is identity", game.delivered_amount(10, "gold") == 10)
	game.biome_id = "desert"
	check("u5 desert gold deposit delivers x1.3", game.delivered_amount(10, "gold") == 13,
			"got=%d" % game.delivered_amount(10, "gold"))
	check("u6 desert wood deposit delivers x0.8", game.delivered_amount(10, "wood") == 8)
	game.biome_id = "snow"
	check("u7 snow field interval longer than grassland",
			game.field_interval() > Unit.TEND_TIME, "iv=%.2f" % game.field_interval())
	check("u8 snow cavalry slower than grassland cavalry",
			game.move_mult_for("cavalry") < 1.0 and game.move_mult_for("villager") == 0.9)
	game.biome_id = "grassland"
	# Unit effective speed: same villager type, snow instance slower.
	var spd_pos: Vector2 = game.world.cell_center(game.world.nearest_walkable(Vector2i(20, 50)))
	var uv_g: Unit = game._make_unit(0, spd_pos, "villager")
	game.biome_id = "snow"
	var uv_s: Unit = game._make_unit(0, spd_pos, "villager")
	game.biome_id = "grassland"
	check("u9 villager speed differs snow vs grassland",
			uv_s.speed < uv_g.speed and absf(uv_s.speed - uv_g.speed * 0.9) < 0.6,
			"g=%.1f s=%.1f" % [uv_g.speed, uv_s.speed])
	for uv in [uv_g, uv_s]:
		game.units.erase(uv)
		uv.queue_free()
	await get_tree().process_frame
	# Biome asset files exist + load for every biome.
	for bid in Biomes.ORDER:
		var dir := String(Biomes.data(bid)["tiles_dir"])
		check("u10 %s tile set loads" % bid,
				load(dir + "grass_0.png") != null and load(dir + "water_0.png") != null
				and load(dir + "shore_sand_n.png") != null)
		var skin := String(Biomes.data(bid)["node_skin"])
		check("u11 %s node skins resolve" % bid,
				ResourceNode.tex_for("wood", 0, skin) != null
				and ResourceNode.tex_for("food", 0, skin) != null
				and ResourceNode.tex_for("stone", 0, skin) != null)
	# Per-biome world contract on standalone worlds (plains layout).
	var near_base := func(w, base: Vector2i, rtype: String) -> int:
		var n := 0
		for nd in w.nodes:
			if nd.rtype == rtype and Vector2(nd.cell - base).length() <= 19.0:
				n += 1
		return n
	for bid in Biomes.ORDER:
		var wb := World.new()
		wb.biome_id = bid
		add_child(wb)
		wb.generate(12345)
		check("u12 %s bases placeable (clearings)" % bid,
				wb.can_place(wb.player_base - Vector2i(1, 1), Vector2i(3, 3))
				and wb.can_place(wb.enemy_base - Vector2i(1, 1), Vector2i(3, 3)))
		check("u13 %s starting resources near both TCs" % bid,
				near_base.call(wb, wb.player_base, "wood") >= 3 and near_base.call(wb, wb.enemy_base, "wood") >= 3
				and near_base.call(wb, wb.player_base, "food") >= 2 and near_base.call(wb, wb.enemy_base, "food") >= 2
				and near_base.call(wb, wb.player_base, "gold") >= 1 and near_base.call(wb, wb.enemy_base, "gold") >= 1
				and near_base.call(wb, wb.player_base, "stone") >= 1 and near_base.call(wb, wb.enemy_base, "stone") >= 1,
				"pw=%d ew=%d pf=%d ef=%d" % [near_base.call(wb, wb.player_base, "wood"),
						near_base.call(wb, wb.enemy_base, "wood"),
						near_base.call(wb, wb.player_base, "food"),
						near_base.call(wb, wb.enemy_base, "food")])
		check("u14 %s land path base-to-base" % bid,
				wb.get_path_cells(wb.player_base, wb.enemy_base).size() > 0)
		# Determinism: a second world with the same seed matches exactly.
		var wb2 := World.new()
		wb2.biome_id = bid
		add_child(wb2)
		wb2.generate(12345)
		var sig := func(w) -> String:
			var parts: Array = []
			for nd in w.nodes:
				parts.append("%d,%d,%s" % [nd.cell.x, nd.cell.y, nd.rtype])
			parts.sort()
			return str(w.water.size()) + "|" + ",".join(parts)
		check("u15 %s same-seed determinism" % bid, sig.call(wb) == sig.call(wb2))
		remove_child(wb)
		wb.queue_free()
		remove_child(wb2)
		wb2.queue_free()
		await get_tree().process_frame
	# Panel setter path: cards + layout chips -> statics -> fresh world.
	game.hud.select_map_card("desert")
	check("u16 panel card selection", game.hud.map_selection() == "desert")
	game.hud.select_layout_chip("river")
	check("u17 panel layout chip selection", game.hud.layout_selection() == "river")
	game.hud.confirm_map_choice()
	var ms = load("res://scripts/main.gd")
	check("u18 confirm writes Main statics",
			ms.chosen_biome == "desert" and ms.chosen_layout == "river")
	var game3 = load("res://main.tscn").instantiate()
	add_child(game3)
	await get_tree().process_frame
	await get_tree().process_frame
	game3.enemy_ai.waves_enabled = false
	check("u19 chosen biome+layout flow into world gen",
			game3.biome_id == "desert" and game3.world.biome_id == "desert"
			and game3.world.resolved_layout == "river",
			"b=%s l=%s" % [game3.biome_id, game3.world.resolved_layout])
	remove_child(game3)
	game3.queue_free()
	ms.chosen_biome = "grassland"
	ms.chosen_layout = "plains"
	await get_tree().process_frame

	# ------------------------------------------------ (w) layouts + water features + minimap privacy
	var mk_world := func(layout: String) -> World:
		var wl := World.new()
		wl.layout_id = layout
		add_child(wl)
		wl.generate(12345)
		return wl
	var drop_world := func(wl: World) -> void:
		remove_child(wl)
		wl.queue_free()
	# plains: lake + 2 ponds + waterfall.
	var wp = mk_world.call("plains")
	check("w1 plains has lake + 2 ponds + waterfall",
			wp.features.lake.size() > 40 and wp.features.ponds.size() >= 2
			and wp.features.waterfalls.size() >= 1,
			"lake=%d ponds=%d wf=%d" % [wp.features.lake.size(), wp.features.ponds.size(),
					wp.features.waterfalls.size()])
	check("w2 waterfall + cliff cells are non-walkable",
			not wp.falls_cells.is_empty() and wp.is_solid(wp.falls_cells[0])
			and not wp.cliff_cells.is_empty() and wp.is_solid(wp.cliff_cells[0])
			and wp.falls_foam_points().size() >= 1)
	drop_world.call(wp)
	# river: band + 2 crossings + waterfall + ponds + path.
	var wr = mk_world.call("river")
	var crossings_open := true
	for cx in [19, 20, 43, 44]:
		if wr.water.has(Vector2i(cx, 31)):
			crossings_open = false
	check("w3 river band + falls + ponds + open crossings",
			wr.features.river.size() > 100 and wr.features.waterfalls.size() >= 1
			and wr.features.ponds.size() >= 2 and crossings_open,
			"river=%d wf=%d ponds=%d" % [wr.features.river.size(),
					wr.features.waterfalls.size(), wr.features.ponds.size()])
	check("w4 river layout keeps land path", wr.get_path_cells(wr.player_base, wr.enemy_base).size() > 0)
	drop_world.call(wr)
	# islands: sea everywhere, bases on SEPARATE landmasses with shore.
	var wi = mk_world.call("islands")
	var seen: Dictionary = {}
	var stack: Array = [wi.player_base]
	seen[wi.player_base] = true
	while not stack.is_empty():
		var cc: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nn: Vector2i = cc + d
			if wi.in_bounds(nn) and not seen.has(nn) and not wi.is_solid(nn):
				seen[nn] = true
				stack.append(nn)
	var shore_near := func(w, base: Vector2i) -> bool:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if w.water.has(base + Vector2i(dx, dy)):
					return true
		return false
	check("w5 islands: sea + separate landmasses + shoreline + pond",
			wi.water.size() > 1800 and not seen.has(wi.enemy_base)
			and shore_near.call(wi, wi.player_base) and shore_near.call(wi, wi.enemy_base)
			and wi.features.ponds.size() >= 1,
			"water=%d sep=%s" % [wi.water.size(), str(not seen.has(wi.enemy_base))])
	drop_world.call(wi)
	# valley: river + waterfall + pond, path squeezed through the gap.
	var wv = mk_world.call("valley")
	var vpath: Array = wv.get_path_cells(wv.player_base, wv.enemy_base)
	var squeezed := vpath.size() > 0
	for pc2 in vpath:
		if ((pc2.y >= 25 and pc2.y <= 27) or (pc2.y >= 37 and pc2.y <= 39)) \
				and (pc2.x < 27 or pc2.x > 36):
			squeezed = false
	check("w6 valley: features + single chokepoint path",
			wv.features.river.size() > 30 and wv.features.waterfalls.size() >= 1
			and wv.features.ponds.size() >= 1 and squeezed,
			"river=%d path=%d" % [wv.features.river.size(), vpath.size()])
	drop_world.call(wv)
	# arena: symmetric ponds + corner mini-lakes + rich centre ring.
	var wa = mk_world.call("arena")
	var ring := 0
	for nd in wa.nodes:
		if (nd.rtype == "gold" or nd.rtype == "stone") \
				and Vector2(nd.cell - Vector2i(32, 32)).length() <= 8.0:
			ring += 1
	var corner_water := func(w, ctr: Vector2i) -> bool:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if w.water.has(ctr + Vector2i(dx, dy)):
					return true
		return false
	check("w7 arena: ponds + corner lakes + centre ring",
			wa.features.ponds.size() >= 2 and corner_water.call(wa, Vector2i(7, 7))
			and corner_water.call(wa, Vector2i(56, 56)) and ring >= 8,
			"ponds=%d ring=%d" % [wa.features.ponds.size(), ring])
	drop_world.call(wa)
	# coast: sea edge depth + lake + river + inland bases + land path.
	var wc = mk_world.call("coast")
	var sea_col := true
	for yy in range(54, 64):
		if not wc.water.has(Vector2i(32, yy)):
			sea_col = false
	check("w8 coast: sea depth + lake + river + path along coast",
			sea_col and wc.features.lake.size() > 30 and wc.features.river.size() > 20
			and wc.get_path_cells(wc.player_base, wc.enemy_base).size() > 0,
			"lake=%d river=%d" % [wc.features.lake.size(), wc.features.river.size()])
	drop_world.call(wc)
	# random resolves to a real layout.
	var wran = mk_world.call("random")
	check("w9 random layout resolves", World.LAYOUTS.has(wran.resolved_layout),
			"resolved=%s" % wran.resolved_layout)
	drop_world.call(wran)
	await get_tree().process_frame
	# Minimap privacy (fresh instance — the main one's enemy TC was
	# destroyed in section t): fog fully lifted + enemy scouted
	# (visible flags forced on) — the minimap entity layer must still
	# paint NOTHING for the enemy, and the player colour for our TC.
	var game4 = load("res://main.tscn").instantiate()
	add_child(game4)
	await get_tree().process_frame
	await get_tree().process_frame
	game4.enemy_ai.waves_enabled = false
	for i in range(game4.fog.state.size()):
		game4.fog.state[i] = 2
	game4.enemy_tc.visible = true
	var mm_priv = game4.hud.minimap
	check("w10 minimap shows NO enemy info at enemy TC",
			mm_priv.marker_color_at(game4.world.enemy_base) == Color.TRANSPARENT)
	check("w11 minimap shows player colour at player TC",
			mm_priv.marker_color_at(game4.world.player_base)
			== TeamColors.minimap_color(0, "building"))
	var ev_cell := Vector2i(-1, -1)
	for eu in game4.units:
		if eu.team == 1:
			ev_cell = game4.world.world_to_cell(eu.global_position)
			break
	check("w12 minimap shows NO enemy unit markers",
			ev_cell.x >= 0 and mm_priv.marker_color_at(ev_cell) == Color.TRANSPARENT)
	remove_child(game4)
	game4.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (x) ships + wild beasts
	# Section (t) ended this match (victory -> paused): reopen it,
	# keep the AI's waves off, and wake the beasts the harness parked.
	game.match_over = ""
	game.set_paused(false)
	game.enemy_ai.waves_enabled = false
	for bst in game.world.beasts:
		bst.dormant = false
	# Fish spots: sizable water bodies carry them, on water cells.
	check("x1 fish spots exist on the plains lake",
			game.world.fish_spots.size() >= 2,
			"spots=%d" % game.world.fish_spots.size())
	var spot_ok := true
	for fs in game.world.fish_spots:
		if not game.world.water.has(fs.cell) or fs.amount <= 0:
			spot_ok = false
	check("x2 every fish spot sits on water with food", spot_ok)
	# Beasts: the grassland distribution + territory rule.
	var n_wolf := 0
	var n_bear := 0
	var n_boar := 0
	var anchors_ok := true
	for bst in game.world.beasts:
		match bst.species:
			"wolf": n_wolf += 1
			"bear": n_bear += 1
			"boar": n_boar += 1
		var ac: Vector2i = game.world.world_to_cell(bst.anchor)
		if Vector2(ac - game.world.player_base).length() <= 10.0 \
				or Vector2(ac - game.world.enemy_base).length() <= 10.0:
			anchors_ok = false
	check("x3 grassland beasts: wolf packs + 2 bears + 3 boars",
			n_wolf >= 6 and n_bear == 2 and n_boar == 3,
			"wolf=%d bear=%d boar=%d" % [n_wolf, n_bear, n_boar])
	check("x4 beast territories stay out of base clearings", anchors_ok)
	# A test dock on the big lake's shore (section (s)'s dock may sit
	# on a pond too small for fish spots; the lake always has them).
	var dock_x: Building = null
	for r in range(0, 12):
		if dock_x != null:
			break
		for dy in range(-r, r + 1):
			if dock_x != null:
				break
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = Vector2i(33, 30) + Vector2i(dx, dy)
				if game.placement_valid_at(cand, "dock"):
					dock_x = game._spawn_building("dock", 0, cand, true)
					break
	check("x5 a completed player dock exists on the lake", dock_x != null)
	game.resources.wood = 600
	game.resources.gold = 300
	game.selected_building = dock_x
	var wood_x := int(game.resources.wood)
	check("x6 can_train_ship + HUD has 3 ship buttons",
			game.can_train_ship("fishing_boat") and game.hud._ship_btns.size() == 3)
	check("x7 training a fishing boat deducts 75 wood",
			game.train_ship("fishing_boat") and int(game.resources.wood) == wood_x - 75)
	var got_boat: bool = await wait_until(func() -> bool:
		for s in game.ships:
			if s.team == 0 and s.ship_type == "fishing_boat":
				return true
		return false, 60000)
	var fboat: Ship = null
	for s in game.ships:
		if s.team == 0 and s.ship_type == "fishing_boat":
			fboat = s
	check("x8 fishing boat spawns on a water cell",
			got_boat and fboat != null and game.world.water.has(fboat.cell()))
	# Water grid: a water path never touches land, and an order onto
	# land still leaves the hull on water. The far spot must sit on
	# the boat's OWN water body (a hull cannot sail between
	# disconnected ponds): flood the boat's body, then take the
	# farthest spot inside it.
	var boat_body: Dictionary = {}
	var bb_stack: Array = [fboat.cell()]
	boat_body[fboat.cell()] = true
	while not bb_stack.is_empty():
		var bb_c: Vector2i = bb_stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var bb_n: Vector2i = bb_c + d
			if game.world.water.has(bb_n) and not boat_body.has(bb_n):
				boat_body[bb_n] = true
				bb_stack.append(bb_n)
	var far_spot: FishSpot = null
	var far_d := -1.0
	for fs2 in game.world.fish_spots:
		if boat_body.has(fs2.cell):
			var dd := Vector2(fs2.cell - fboat.cell()).length()
			if dd > far_d:
				far_d = dd
				far_spot = fs2
	var wpath: Array = game.world.get_water_path_cells(fboat.cell(), far_spot.cell)
	var wpath_ok := not wpath.is_empty()
	for wcell in wpath:
		if not game.world.navigable(wcell):
			wpath_ok = false
	check("x9 water A* path stays on navigable water", wpath_ok,
			"cells=%d" % wpath.size())
	fboat.order_move_cell(game.world.player_base)
	var settled: bool = await wait_until(func() -> bool: return fboat.state == "idle", 60000)
	check("x10 ship ordered onto land still ends on water",
			settled and game.world.water.has(fboat.cell()),
			"cell=%s" % str(fboat.cell()))
	# Fishing loop: order onto the nearest REACHABLE spot (same water
	# body as the dock), then Food must increase AND the spot drain.
	var food_x := int(game.resources.food)
	var home_spot: FishSpot = null
	var spots_by_dist: Array = game.world.fish_spots.duplicate()
	spots_by_dist.sort_custom(func(a: FishSpot, b: FishSpot) -> bool:
		return fboat.global_position.distance_squared_to(a.global_position) \
				< fboat.global_position.distance_squared_to(b.global_position))
	for cand_spot in spots_by_dist:
		if not game.world.get_water_path_cells(fboat.cell(), cand_spot.cell).is_empty():
			home_spot = cand_spot
			break
	fboat.home_dock = dock_x
	fboat.order_fish(home_spot)
	var fished: bool = await wait_until(func() -> bool:
		return int(game.resources.food) > food_x, 150000)
	check("x11 fishing loop deposits +Food at the dock", fished,
			"food %d -> %d" % [food_x, int(game.resources.food)])
	check("x11b the worked fish spot actually drained",
			home_spot != null and home_spot.amount < home_spot.max_amount,
			"amount=%d" % (home_spot.amount if home_spot != null else -1))
	# War ship sinks a fishing boat through the projectile system.
	game.train_ship("war_ship")
	var got_war: bool = await wait_until(func() -> bool:
		for s in game.ships:
			if s.team == 0 and s.ship_type == "war_ship":
				return true
		return false, 60000)
	var wship: Ship = null
	for s in game.ships:
		if s.team == 0 and s.ship_type == "war_ship":
			wship = s
	var prey := Ship.new()
	prey.ship_type = "fishing_boat"
	prey.team = 1
	prey.game = game
	prey.world = game.world
	var prey_cell: Vector2i = game.world.nearest_navigable(wship.cell() + Vector2i(3, 0), 6)
	prey.position = game.world.cell_center(prey_cell)
	game.add_child(prey)
	game.ships.append(prey)
	wship.order_attack(prey)
	var sunk: bool = await wait_until(func() -> bool:
		return not is_instance_valid(prey) or prey.is_dead(), 90000)
	check("x12 war ship sinks a fishing boat via projectiles", got_war and sunk)
	# Minimap privacy covers ships too.
	var eship := Ship.new()
	eship.ship_type = "transport"
	eship.team = 1
	eship.game = game
	eship.world = game.world
	eship.position = game.world.cell_center(game.world.nearest_navigable(Vector2i(33, 30), 4))
	game.add_child(eship)
	game.ships.append(eship)
	var mm_x = game.hud.minimap
	check("x13 minimap shows NO marker at an enemy ship",
			mm_x.marker_color_at(eship.cell()) == Color.TRANSPARENT)
	check("x14 minimap shows own-ship colour at own war ship",
			mm_x.marker_color_at(wship.cell()) == TeamColors.minimap_color(0, "ship"),
			"got=%s" % str(mm_x.marker_color_at(wship.cell())))
	game.ships.erase(eship)
	eship.queue_free()
	# Transport round-trip: board at the shore, sail, unload ashore.
	game.train_ship("transport")
	var got_tr: bool = await wait_until(func() -> bool:
		for s in game.ships:
			if s.team == 0 and s.ship_type == "transport":
				return true
		return false, 60000)
	var tship: Ship = null
	for s in game.ships:
		if s.team == 0 and s.ship_type == "transport":
			tship = s
	var shore_land: Vector2i = game.world.nearest_walkable(tship.cell(), 4)
	var m1: Unit = game._make_unit(0, game.world.cell_center(shore_land), "militia")
	var m2: Unit = game._make_unit(0, game.world.cell_center(shore_land), "militia")
	game.board_units([m1, m2], tship)
	check("x15 transport boards 2 units (hidden + out of roster)",
			got_tr and tship.cargo.size() == 2 and not game.units.has(m1)
			and not m1.visible and not game.units.has(m2),
			"cargo=%d" % (tship.cargo.size() if tship != null else -1))
	var unloaded: int = tship.unload_all(shore_land)
	check("x16 unload round-trip restores both units ashore",
			unloaded == 2 and tship.cargo.is_empty() and game.units.has(m1)
			and game.units.has(m2) and m1.visible
			and not game.world.is_solid(m1.cell()))
	# Cargo dies with the ship.
	game.board_units([m1], tship)
	var cargo_aboard: bool = tship.cargo.size() == 1 and not game.units.has(m1)
	tship.take_damage(9999.0, null)
	var ship_gone: bool = await wait_until(func() -> bool:
		return not is_instance_valid(tship), 60000)
	check("x17 sinking the transport kills its cargo",
			cargo_aboard and ship_gone and not is_instance_valid(m1))
	# Beasts: a wolf aggros and kills a villager that wanders in.
	var wolf: Beast = null
	for bst in game.world.beasts:
		if bst.species == "wolf":
			wolf = bst
			break
	wolf.global_position = wolf.anchor # hunt starts inside the leash
	# Flee pass: an UNORDERED villager now runs from the wolf, so the
	# stated balance (Stats: a villager that stands and fights loses
	# to a wolf) is exercised with an explicit attack order — the
	# flee grace window keeps it in the fight.
	var victim: Unit = game._make_unit(0, wolf.anchor + Vector2(56, 0), "villager")
	victim.order_attack(wolf)
	var wolf_kill: bool = await wait_until(func() -> bool:
		return not is_instance_valid(victim) or victim.is_dead(), 120000)
	check("x18 wolf kills a villager that stands and fights it", wolf_kill)
	# Boar: ignores an untouched passerby, retaliates when damaged,
	# and its death drops a 100-Food carcass a villager can gather.
	var boar: Beast = null
	for bst in game.world.beasts:
		if bst.species == "boar":
			boar = bst
			break
	var passer: Unit = game._make_unit(0, boar.global_position + Vector2(40, 0), "villager")
	passer.state = "idle"
	await get_tree().create_timer(1.2).timeout
	check("x19 boar ignores an untouched passerby",
			boar.target == null and boar.state == "wander" and not passer.is_dead())
	var hunter: Unit = game._make_unit(0, boar.global_position + Vector2(30, 0), "villager")
	boar.take_damage(5.0, hunter)
	check("x20 boar retaliates when damaged",
			boar.state == "chase" and boar.target == hunter)
	game.units.erase(passer)
	passer.queue_free()
	var boar_cell: Vector2i = boar.cell()
	boar.take_damage(9999.0, hunter)
	var carcass: ResourceNode = game.node_at_cell(boar_cell)
	check("x21 dead boar leaves a 100-food carcass node",
			carcass != null and carcass.rtype == "meat" and carcass.amount == 100,
			"node=%s" % str(carcass))
	hunter.order_gather(carcass)
	var got_meat: bool = await wait_until(func() -> bool:
		return hunter.carry_type == "food" and hunter.carry_amount > 0, 90000)
	check("x22 villager-class unit gathers food from the carcass", got_meat,
			"carry=%s/%d" % [hunter.carry_type, hunter.carry_amount])
	# Base keep-out: a beast dragged next to the player base drops
	# its hunt and returns to its territory.
	var wolf2: Beast = null
	for bst in game.world.beasts:
		if bst.species == "wolf" and bst != wolf:
			wolf2 = bst
			break
	var saved_pos: Vector2 = wolf2.global_position
	var near_base_cell: Vector2i = game.world.nearest_walkable(
			game.world.player_base + Vector2i(7, 0), 4)
	wolf2.global_position = game.world.cell_center(near_base_cell)
	var dummy_x: Unit = game._make_unit(0, wolf2.global_position + Vector2(30, 0), "villager")
	wolf2.target = dummy_x
	wolf2.state = "chase"
	var dropped: bool = await wait_until(func() -> bool:
		return wolf2.state == "return" or wolf2.target == null, 30000)
	check("x23 beast abandons a hunt inside the base clearing", dropped,
			"state=%s" % wolf2.state)
	wolf2.global_position = saved_pos
	wolf2.state = "wander"
	game.units.erase(dummy_x)
	dummy_x.queue_free()
	# Snow: frozen water is not navigable — no water path exists.
	var ms_snow = load("res://scripts/main.gd")
	ms_snow.chosen_biome = "snow"
	ms_snow.chosen_layout = "plains"
	ms_snow.map_choice_done = true
	var game5 = load("res://main.tscn").instantiate()
	add_child(game5)
	await get_tree().process_frame
	await get_tree().process_frame
	game5.enemy_ai.waves_enabled = false
	var nav_count := 0
	for yy in range(World.MAP_H):
		for xx in range(World.MAP_W):
			if game5.world.navigable(Vector2i(xx, yy)):
				nav_count += 1
	var ice_path: Array = game5.world.get_water_path_cells(Vector2i(30, 30), Vector2i(36, 30))
	check("x24 snow water is frozen: zero navigable cells, no water path",
			game5.world.water.size() > 0 and nav_count == 0 and ice_path.is_empty(),
			"water=%d nav=%d" % [game5.world.water.size(), nav_count])
	remove_child(game5)
	game5.queue_free()
	await get_tree().process_frame
	# AI navy: on Quần đảo the enemy fields a War Ship by wave 3.
	var ms_isl = load("res://scripts/main.gd")
	ms_isl.chosen_biome = "grassland"
	ms_isl.chosen_layout = "islands"
	ms_isl.map_choice_done = true
	var game6 = load("res://main.tscn").instantiate()
	add_child(game6)
	await get_tree().process_frame
	await get_tree().process_frame
	game6.enemy_ai.waves_enabled = false
	check("x25 islands: enemy base includes a dock",
			game6.get_team_dock(1) != null)
	game6.enemy_ai.res.wood = 900
	game6.enemy_ai.res.gold = 400
	game6.enemy_ai.waves_launched = 2
	var navy_up: bool = await wait_until(func() -> bool:
		for s in game6.ships:
			if s.team == 1 and s.ship_type == "war_ship" and not s.is_dead():
				return true
		return false, 120000)
	check("x26 AI fields a war ship on islands by wave 3", navy_up,
			"ships=%d" % game6.ships.size())
	remove_child(game6)
	game6.queue_free()
	await get_tree().process_frame
	var ms_back = load("res://scripts/main.gd")
	ms_back.chosen_biome = "grassland"
	ms_back.chosen_layout = "plains"

	# ------------------------------------------------ (y) visible clouds
	# Grassland sky: CLOUD_COUNT pairs on the sky layer, each cloud a
	# real sprite from Tín's pack with its shadow riding at the offset.
	check("y1 grassland spawns the named cloud count",
			game.world.clouds.size() == int(World.CLOUD_COUNT["grassland"])
			and game.world.sky_layer != null,
			"clouds=%d" % game.world.clouds.size())
	var pair0: Dictionary = game.world.clouds[0]
	var cl0: Sprite2D = pair0["cloud"]
	var sh0: Sprite2D = pair0["shadow"]
	check("y2 cloud texture comes from the sent cloud pack",
			cl0.texture != null
			and cl0.texture.resource_path.begins_with("res://assets/env/cloud_"),
			"tex=%s" % (cl0.texture.resource_path if cl0.texture != null else "none"))
	check("y3 shadow tracks its cloud at the sun offset",
			sh0.position == cl0.position + World.CLOUD_SHADOW_OFFSET)
	var cx0: float = cl0.position.x
	await get_tree().create_timer(1.2).timeout
	check("y4 clouds drift on the wind (position delta > 0)",
			cl0.position.x > cx0, "dx=%.1f" % (cl0.position.x - cx0))
	# Modal rule: the sky layer hides while a full-screen panel is up.
	game.world.set_sky_active(false)
	check("y5 sky hides while a modal panel is open",
			not game.world.sky_active and not game.world.sky_layer.visible
			and not cl0.is_visible_in_tree())
	game.world.set_sky_active(true)
	check("y6 sky returns when the modal closes",
			game.world.sky_active and game.world.sky_layer.visible)
	# Snow sky: denser count from the same constants (bare world —
	# generate() is self-contained once biome_id is set).
	var w_snow := World.new()
	w_snow.biome_id = "snow"
	add_child(w_snow)
	w_snow.generate(777)
	check("y7 snow sky uses the denser named count",
			w_snow.clouds.size() == int(World.CLOUD_COUNT["snow"]),
			"clouds=%d" % w_snow.clouds.size())
	remove_child(w_snow)
	w_snow.queue_free()
	await get_tree().process_frame
	# Minimap terrain is sampled from the baked ground: its texture
	# builds from the bake and a lake cell reads as water-blue.
	var mm2 = game.hud.minimap
	mm2._ensure_ground_tex(game.world)
	var mm_col: Color = mm2.ground_color_at(Vector2i(33, 30))
	check("y8 minimap terrain comes from the baked ground",
			mm2._ground_tex != null and mm_col.b > mm_col.r,
			"col=%s" % str(mm_col))

	# ------------------------------------------------ (z) dry-base placement guard
	# No scatter placement (tree / rock / bush / node / decor, any
	# biome or layout) may stand on water-toned baked ground: the
	# bake feathers water ~0.38 tile onto shore cells, which put
	# oasis palms IN the lake (Tín's catch). World._enforce_dry_
	# placements runs inside generate(); this asserts its invariant
	# on the shipped worlds via the same sampling it uses.
	var z_combos: Array = [
			["grassland", "plains", 12345], ["desert", "plains", 12345],
			["desert", "coast", 777], ["snow", "plains", 777],
			["snow", "coast", 12345], ["grassland", "islands", 777]]
	var zi := 0
	for combo in z_combos:
		zi += 1
		var wz := World.new()
		wz.biome_id = String(combo[0])
		wz.layout_id = String(combo[1])
		add_child(wz)
		wz.generate(int(combo[2]))
		var wet := 0
		for n in wz.nodes:
			if not wz.placement_base_dry(n.cell):
				wet += 1
		for d in wz.decors:
			if not wz.placement_base_dry(d.cell):
				wet += 1
		check("z%d dry bases: %s/%s seed %d" % [zi, String(combo[0]), String(combo[1]), int(combo[2])],
				wet == 0, "wet=%d of %d placements" % [wet, wz.nodes.size() + wz.decors.size()])
		remove_child(wz)
		wz.queue_free()
		await get_tree().process_frame

	# ------------------------------------------------ (aa) Age IV + flee + annihilation
	# Imperial research on the main instance (Age III from section u,
	# Castle + Blacksmith standing): wallet topped up first.
	game.resources["food"] = 1500
	game.resources["gold"] = 600
	var food_before4: int = int(game.resources["food"])
	var gold_before4: int = int(game.resources["gold"])
	check("aa1 Age IV available at Age III with Castle + Blacksmith",
			game.can_age_up4(), "age=%d" % game.age)
	check("aa2 Age IV research starts", game.start_age_up4())
	check("aa3 Age IV deducted 1000 Food + 350 Gold",
			int(game.resources["food"]) == food_before4 - 1000
			and int(game.resources["gold"]) == gold_before4 - 350,
			"food=%d gold=%d" % [int(game.resources["food"]), int(game.resources["gold"])])
	game.age_timer = 0.05
	var age4_done: bool = await wait_until(func() -> bool: return game.age >= 4, 20000)
	check("aa4 research completes into Age IV (Imperial)", age4_done)
	var tc_tex := ""
	if game.player_tc != null and game.player_tc.art_sprite != null and game.player_tc.art_sprite.texture != null:
		tc_tex = game.player_tc.art_sprite.texture.resource_path
	check("aa5 player buildings wear tier-4 art at Age IV",
			tc_tex.ends_with("_t4.png"), tc_tex)
	check("aa6 tower/castle damage steps at Age IV",
			Stats.tower_atk(3) == 14.0 and Stats.tower_atk(4) == 18.0
			and Stats.castle_atk(3) == 16.0 and Stats.castle_atk(4) == 20.0)
	check("aa7 Ram gains its Imperial step vs buildings",
			Stats.damage("ram", game.player_tc, 3) == 24.0
			and Stats.damage("ram", game.player_tc, 4) == 28.0,
			"iii=%s iv=%s" % [Stats.damage("ram", game.player_tc, 3), Stats.damage("ram", game.player_tc, 4)])
	var barr4 = game.get_team_barracks(0)
	if barr4 != null:
		barr4.start_training("militia")
	check("aa8 Imperial logistics cuts the Barracks training timer by 20%",
			barr4 != null and barr4.train_queue == 1 and barr4.train_timer <= 4.05 and barr4.train_timer > 3.5
			and game.train_time_mult(0) == Stats.IMPERIAL_TRAIN_TIME_MULT,
			"timer=%s" % (barr4.train_timer if barr4 != null else -1.0))

	# Flee cycle on a fresh instance (also carries the Age-IV gate).
	var gameF = load("res://main.tscn").instantiate()
	add_child(gameF)
	await get_tree().process_frame
	await get_tree().process_frame
	gameF.enemy_ai.waves_enabled = false
	check("aa9 Age IV is gated in the Dark Age (wrong age, no Castle)",
			not gameF.can_age_up4())
	var fv: Unit = null
	for u6 in gameF.units:
		if u6.team == 0 and u6.unit_type == "villager":
			fv = u6
			break
	var node6: ResourceNode = null
	for n6 in gameF.world.nodes:
		if n6.rtype == "wood":
			node6 = n6
			break
	fv.order_gather(node6)
	fv.carry_type = "wood"
	fv.carry_amount = 10
	var wood6: int = int(gameF.resources["wood"])
	var wolf6 = gameF.world._add_beast("wolf", "wolf", gameF.world.world_to_cell(fv.global_position))
	fv.take_damage(6.0, wolf6)
	check("aa10 a wolf hit puts the villager in flee state",
			fv.state == "flee", "state=%s" % fv.state)
	var garr: bool = await wait_until(func() -> bool: return fv.state == "garrison", 60000)
	check("aa11 fleeing villager reaches the TC and garrisons (hidden, untargetable)",
			garr and not fv.visible and not fv.is_targetable(),
			"state=%s vis=%s" % [fv.state, fv.visible])
	check("aa12 the carried wood is deposited on garrison entry",
			int(gameF.resources["wood"]) == wood6 + 10,
			"wood=%d want=%d" % [int(gameF.resources["wood"]), wood6 + 10])
	# Danger gone: the villager pops back out — and STAYS IDLE.
	# The match-start flow doc forbids automatic villager control:
	# no auto-resume of the interrupted task (player re-orders).
	wolf6.take_damage(99999.0)
	var back6: bool = await wait_until(func() -> bool: return fv.state != "garrison" and fv.visible, 60000)
	check("aa13 the villager re-emerges once it is safe", back6, "state=%s" % fv.state)
	check("aa14 no auto-resume: it waits idle with no task",
			fv.state == "idle" and fv.target_node == null and fv.target_field == null,
			"state=%s node=%s" % [fv.state, fv.target_node])
	# An explicitly ordered villager does NOT flee (grace window).
	var fv2: Unit = null
	for u6b in gameF.units:
		if u6b.team == 0 and u6b.unit_type == "villager" and u6b != fv:
			fv2 = u6b
			break
	var wolf6b = gameF.world._add_beast("wolf", "wolf", gameF.world.world_to_cell(fv2.global_position) + Vector2i(6, 0))
	fv2.order_attack(wolf6b)
	fv2.take_damage(6.0, wolf6b)
	check("aa15 an ordered-attack villager does NOT flee",
			fv2.state != "flee" and fv2.state != "garrison" and fv2.no_flee_timer > 0.0,
			"state=%s grace=%s" % [fv2.state, fv2.no_flee_timer])
	remove_child(gameF)
	gameF.queue_free()
	await get_tree().process_frame

	# AI Imperial on a fresh instance: wave 6 arms the purchase, the
	# AI pays from its own ledger and researches (no free age-up).
	var gameAI = load("res://main.tscn").instantiate()
	add_child(gameAI)
	await get_tree().process_frame
	await get_tree().process_frame
	gameAI.enemy_ai.waves_enabled = false
	gameAI.set_team_age(1, 3)
	gameAI.enemy_ai.waves_launched = 5
	gameAI.enemy_ai.launch_wave()
	check("aa16 wave 6 arms the AI's Imperial purchase",
			gameAI.enemy_ai.age4_pending and int(gameAI.team_age.get(1, 1)) == 3)
	gameAI.enemy_ai.res["food"] = 1200
	gameAI.enemy_ai.res["gold"] = 500
	var ai_paid: bool = await wait_until(func() -> bool: return gameAI.enemy_ai.age4_researching, 20000)
	check("aa17 AI pays the Imperial cost from its own ledger",
			ai_paid and int(gameAI.enemy_ai.res["gold"]) == 150
			and int(gameAI.enemy_ai.res["food"]) <= 200 and int(gameAI.enemy_ai.res["food"]) >= 50,
			"food=%d gold=%d" % [int(gameAI.enemy_ai.res["food"]), int(gameAI.enemy_ai.res["gold"])])
	gameAI.enemy_ai.age4_timer = 0.05
	var ai_age4: bool = await wait_until(func() -> bool: return int(gameAI.team_age.get(1, 1)) >= 4, 20000)
	check("aa18 AI completes Imperial research into Age IV", ai_age4)
	remove_child(gameAI)
	gameAI.queue_free()
	await get_tree().process_frame

	# Annihilation on the player's side (fresh instance): TC down
	# with villagers + a Barracks = fights on; trainer gone = defeat.
	var gameA = load("res://main.tscn").instantiate()
	add_child(gameA)
	await get_tree().process_frame
	await get_tree().process_frame
	gameA.enemy_ai.waves_enabled = false
	var barr8 = gameA._spawn_building("barracks", 0,
			gameA.world.nearest_walkable(gameA.world.player_base + Vector2i(7, 0)), true)
	gameA.player_tc.take_damage(99999.0)
	check("aa19 player TC down + villagers + Barracks = match continues, warning on",
			gameA.match_over == "" and gameA.player_tc_destroyed and gameA.own_tc_down_fighting_on(),
			"over=%s" % gameA.match_over)
	barr8.take_damage(99999.0)
	check("aa20 losing the last trainer too = defeat (annihilation)",
			gameA.match_over == "defeat", "over=%s" % gameA.match_over)
	remove_child(gameA)
	gameA.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (ab) team colours: 8 slots, one sprite set
	# Colour table sanity: named slots, distinct identity hues —
	# slots 0-3 keep the original four families; 13z adds Tím /
	# Cam / Xanh ngọc / Hồng for the 8-player queues.
	var ui_fams := true
	var c0 := TeamColors.ui_color(0)
	var c1 := TeamColors.ui_color(1)
	var c2 := TeamColors.ui_color(2)
	var c3 := TeamColors.ui_color(3)
	ui_fams = ui_fams and c0.r > c0.g and c0.r > c0.b # red
	ui_fams = ui_fams and c1.b > c1.r and c1.b > c1.g # blue
	ui_fams = ui_fams and c2.g > c2.r and c2.g > c2.b # green
	ui_fams = ui_fams and c3.r > c3.g and c3.g > c3.b # yellow
	var c4 := TeamColors.ui_color(4)
	var c5 := TeamColors.ui_color(5)
	var c6 := TeamColors.ui_color(6)
	var c7 := TeamColors.ui_color(7)
	ui_fams = ui_fams and c4.b > c4.g and c4.r > c4.g # purple (blue+red over green)
	ui_fams = ui_fams and c5.r > c5.g and c5.g > c5.b # orange
	ui_fams = ui_fams and c6.g > c6.r and c6.b > c6.r # teal (green+blue over red)
	ui_fams = ui_fams and c7.r > c7.g and c7.b > c7.g # pink
	check("ab1 slot UI colours match the approved 8-colour table",
			ui_fams and TeamColors.color_name(2) == "Xanh lá"
			and TeamColors.color_name(4) == "Tím"
			and TeamColors.color_name(5) == "Cam"
			and TeamColors.color_name(6) == "Xanh ngọc"
			and TeamColors.color_name(7) == "Hồng"
			and TeamColors.SLOT_COUNT == 8)
	# Sheet routing by OWNER slot (not faction team).
	check("ab2 sheets route by slot: 0 canonical, 1 enemy, 2 team2, 3 team3",
			String(Unit.get_sheet("militia", 0).tex.resource_path) == "res://assets/militia.png"
			and String(Unit.get_sheet("militia", 1).tex.resource_path).contains("enemy")
			and String(Unit.get_sheet("militia", 2).tex.resource_path).contains("team2")
			and String(Unit.get_sheet("militia", 3).tex.resource_path).contains("team3"))
	# Pixel truth on the militia sheet for the two NEW colours (and
	# the regenerated blue set): band -> family, everything else
	# pixel-identical (skin/hair/armour/weapons untouched).
	var sv1 := palette_survey("res://assets/militia.png",
			TeamColors.unit_sheet(1, "militia")[0], 1, 2)
	check("ab3 blue militia: red band -> blue family, rest identical",
			bool(sv1[0]), String(sv1[1]))
	var sv2 := palette_survey("res://assets/militia.png",
			TeamColors.unit_sheet(2, "militia")[0], 2, 2)
	check("ab4 green militia: red band -> green family, skin identical",
			bool(sv2[0]), String(sv2[1]))
	var sv3 := palette_survey("res://assets/militia.png",
			TeamColors.unit_sheet(3, "militia")[0], 3, 2)
	check("ab5 yellow militia: red band -> yellow family, skin identical",
			bool(sv3[0]), String(sv3[1]))
	# Live units pick their slot's sheet at spawn.
	var ab_cell: Vector2i = game.world.nearest_walkable(game.world.player_base + Vector2i(-4, 6))
	var u_g: Unit = game._make_unit(0, game.world.cell_center(ab_cell), "militia", 2)
	var u_y: Unit = game._make_unit(0, game.world.cell_center(ab_cell + Vector2i(2, 0)), "villager", 3)
	check("ab6 spawned slot-2/slot-3 units wear green/yellow sheets",
			String(u_g._data.tex.resource_path).contains("team2")
			and String(u_y._data.tex.resource_path).contains("team3"),
			"%s | %s" % [u_g._data.tex.resource_path, u_y._data.tex.resource_path])
	# Buildings: a slot-2 house shows the green tier art, a slot-3
	# tower the yellow one; minimap paints the slot-2 house in the
	# slot-2 building colour.
	var h_spot := find_spot(Vector2i(2, 2), game.player_tc.origin_cell + Vector2i(-7, 5))
	var house2: Building = null
	if h_spot.x >= 0:
		house2 = game._spawn_building("house", 0, h_spot, true, 2)
	check("ab7 slot-2 house uses green tier art (and not slot 0/3)",
			house2 != null
			and house2.current_texture() == Building.tier_texture("house", house2.tier, 2)
			and house2.current_texture() != Building.tier_texture("house", house2.tier, 0)
			and house2.current_texture() != Building.tier_texture("house", house2.tier, 3),
			"spot=%s" % str(h_spot))
	check("ab8 minimap paints the slot-2 house in slot-2 colour",
			house2 != null and game.hud.minimap.marker_color_at(
					house2.origin_cell + Vector2i(1, 1))
					== TeamColors.minimap_color(2, "building"),
			"got=%s" % str(game.hud.minimap.marker_color_at(
					house2.origin_cell + Vector2i(1, 1))) if house2 != null else "no house")
	# Ships + King exist in all four colours.
	var sets_ok := true
	for s in range(4):
		for k in ["fishing_boat", "transport", "war_ship"]:
			if not ResourceLoader.exists(TeamColors.ship_dir(s) + k + ".png"):
				sets_ok = false
		if not ResourceLoader.exists(TeamColors.king_path(s)):
			sets_ok = false
	check("ab9 ship hulls + King asset exist in all 4 slot colours", sets_ok)
	var kv2 := palette_survey("res://assets/king.png", TeamColors.king_path(2), 2, 1)
	var kv3 := palette_survey("res://assets/king.png", TeamColors.king_path(3), 3, 1)
	check("ab10 king cape+shield recolour to green/yellow, face identical",
			bool(kv2[0]) and bool(kv3[0]),
			"g:%s y:%s" % [String(kv2[1]), String(kv3[1])])

	# ------------------------------------------------ (ac) characters: roster, draw, hero
	# Registry (16b model): the 8 medieval mains with kits + 3
	# cosmetic-only premium skins (dormant, unbound from the
	# roster). Old-roster ids normalise to the default. No "goc",
	# no selectable king.
	check("ac1 registry: 8 medieval mains with names, 3 dormant skins, no kits on skins",
			Characters.CHAR_IDS == ["knight", "berserker", "archer", "mage",
					"paladin", "dragoon", "assassin", "ranger"]
			and Characters.char_name("knight") == "Hiệp Sĩ Hoàng Gia"
			and Characters.char_name("berserker") == "Chiến Binh Cuồng Nộ"
			and Characters.char_name("archer") == "Cung Thủ Tinh Anh"
			and Characters.char_name("mage") == "Pháp Sư Cung Đình"
			and Characters.char_name("paladin") == "Thánh Kỵ Sĩ"
			and Characters.char_name("dragoon") == "Kỵ Sĩ Long"
			and Characters.char_name("assassin") == "Sát Thủ Bóng Đêm"
			and Characters.char_name("ranger") == "Nhà Thám Hiểm"
			and Characters.SKIN_IDS == ["vo_hiep", "bach_y", "tu_y"]
			and Characters.skin_name("vo_hiep") == "Võ Hiệp"
			and Characters.DEFAULT_CHAR == "knight"
			and Characters.normalize_char("goc") == "knight"
			and Characters.normalize_char("vo_hiep") == "knight"
			and Characters.normalize_char("ngan_ky") == "knight"
			and Characters.normalize_char("skin_la") == "knight"
			and Characters.normalize_skin("tu_y") == "tu_y"
			and Characters.normalize_skin("knight") == ""
			and String(Characters.kit_of("knight").get("aura", "")) == "Hộ Vệ"
			and String(Characters.kit_of("knight").get("skill", "")) == "Khiên Sư Tử"
			and String(Characters.kit_of("berserker").get("skill", "")) == "Rìu Xoáy Cuồng Nộ"
			and String(Characters.kit_of("archer").get("skill", "")) == "Mưa Tên"
			and String(Characters.kit_of("mage").get("skill", "")) == "Thiên Thạch Ma Thuật"
			and String(Characters.kit_of("paladin").get("skill", "")) == "Thánh Quang Hồi Phục"
			and String(Characters.kit_of("dragoon").get("aura", "")) == "Long Hành"
			and String(Characters.kit_of("dragoon").get("skill", "")) == "Long Thương Xuyên Tâm"
			and String(Characters.kit_of("assassin").get("skill", "")) == "Ám Sát"
			and String(Characters.kit_of("ranger").get("skill", "")) == "Kiếm Vũ Lữ Hành")
	# Assets: ONE canonical colour set per appearance — 8
	# directions for all 11 ids, framed portraits for the mains,
	# and NO team-variant files for characters at all.
	var ac_assets := true
	for app_id in ["knight", "berserker", "archer", "mage", "paladin",
			"dragoon", "assassin", "ranger", "vo_hiep", "bach_y", "tu_y"]:
		for d in Characters.DIRS8:
			if not ResourceLoader.exists("res://assets/king_" + app_id + "_" + d + ".png"):
				ac_assets = false
			if Characters.texture_for(app_id, d) == null:
				ac_assets = false
		if ResourceLoader.exists("res://assets/enemy/king_" + app_id + "_s.png") \
				or ResourceLoader.exists("res://assets/team2/king_" + app_id + "_s.png"):
			ac_assets = false
	for cid in Characters.CHAR_IDS:
		if Characters.avatar_for(cid) == null:
			ac_assets = false
	check("ac2 all 11 appearances load 8 canonical directions; portraits exist; no team variants", ac_assets)
	# Pack-sprite format (16b): every hero's south pose is the
	# standard hero height with binary alpha (the builder's
	# crisp standard; back-view weapon removal is audited by
	# tools/build_owner_pack_sprites.py + its grass strip).
	var ac_fmt := true
	for cid in Characters.CHAR_IDS:
		var pimg := Image.load_from_file("res://assets/king_%s_s.png" % cid)
		if pimg == null or pimg.is_empty() or pimg.get_height() != 92:
			ac_fmt = false
			continue
		pimg.convert(Image.FORMAT_RGBA8)
		for yy in range(pimg.get_height()):
			for xx in range(pimg.get_width()):
				var pa := pimg.get_pixel(xx, yy).a
				if pa > 0.01 and pa < 0.99:
					ac_fmt = false
	check("ac3 pack sprites: height 92 + binary alpha for all 8 heroes", ac_fmt)
	# Avatar pick persists locally, free among the mains only.
	Characters.set_local_avatar("archer")
	var ac_persist := Characters.local_avatar() == "archer"
	Characters.set_local_avatar("vo_hiep")
	ac_persist = ac_persist and Characters.local_avatar() == "knight"
	Characters.set_local_avatar("knight")
	check("ac4 avatar pick persists; skins/unknown fall back to the default portrait", ac_persist)
	# Cosmetic skins are dormant: nobody owns any, activation is
	# refused, and the active slot stays empty.
	var ac_locked := Characters.local_active_skin() == ""
	for sid in Characters.SKIN_IDS:
		ac_locked = ac_locked and not Characters.try_set_active_skin(sid) \
				and not Characters.owns_skin(sid)
	check("ac5 premium skins locked: activation refused, active skin empty", ac_locked)
	# The draw: SP assigns from the mains only; over 200 draws
	# every main appears and no skin ever does.
	var draw_rng := RandomNumberGenerator.new()
	draw_rng.seed = 777
	var drawn := {}
	for di in range(200):
		drawn[game.draw_character(draw_rng)] = true
	var ac_draw := drawn.size() == 8
	for cid in Characters.CHAR_IDS:
		ac_draw = ac_draw and drawn.has(cid)
	check("ac6 character draw covers exactly the 8 mains over 200 draws", ac_draw,
			"drawn=%s" % str(drawn.keys()))
	check("ac7 this match's slots hold main characters",
			Characters.CHAR_IDS.has(game.char_for(0)) and Characters.CHAR_IDS.has(game.char_for(1)),
			"p=%s ai=%s" % [game.char_for(0), game.char_for(1)])
	# Facing maths: 45-degree sectors, screen coords (y down).
	check("ac8 dir8_of maps the 8 compass vectors",
			Unit.dir8_of(Vector2(1, 0)) == "e" and Unit.dir8_of(Vector2(0, 1)) == "s"
			and Unit.dir8_of(Vector2(-1, 0)) == "w" and Unit.dir8_of(Vector2(0, -1)) == "n"
			and Unit.dir8_of(Vector2(1, 1)) == "se" and Unit.dir8_of(Vector2(-1, -1)) == "nw"
			and Unit.dir8_of(Vector2(1, -1)) == "ne" and Unit.dir8_of(Vector2(-1, 1)) == "sw")
	# Gating on the main game (Age IV + Castle from aa/u sections).
	for hi in range(2):
		var h_spot2 := find_spot(Vector2i(2, 2), game.player_tc.origin_cell + Vector2i(-9 + hi * 3, 8))
		if h_spot2.x >= 0:
			game._spawn_building("house", 0, h_spot2, true)
	game.resources["food"] = 3000
	game.resources["gold"] = 1500
	check("ac9 hero trainable at Age IV with a Castle standing",
			game.get_team_castle(0) != null and game.age >= 4 and game.can_train_unit("king"),
			"age=%d castle=%s" % [game.age, str(game.get_team_castle(0) != null)])
	game.age = 3
	var ac_gate3: bool = not game.can_train_unit("king")
	game.age = 4
	check("ac10 hero locked below Age IV", ac_gate3 and game.can_train_unit("king"))

	# Full lifecycle on an isolated instance.
	var gameK = load("res://main.tscn").instantiate()
	add_child(gameK)
	await get_tree().process_frame
	await get_tree().process_frame
	gameK.enemy_ai.waves_enabled = false
	gameK.slot_chars[0] = "knight"
	gameK.age = 4
	gameK.resources["food"] = 2000
	gameK.resources["gold"] = 1000
	check("ac11 no Castle -> no hero, even at Age IV with funds",
			gameK.get_team_castle(0) == null and not gameK.can_train_unit("king"))
	var k_spot := find_spot(Vector2i(4, 4), gameK.player_tc.origin_cell + Vector2i(-3, -6))
	var k_castle: Building = gameK._spawn_building("castle", 0, k_spot, true)
	var kh_spot := find_spot(Vector2i(2, 2), gameK.player_tc.origin_cell + Vector2i(4, 4))
	if kh_spot.x >= 0:
		gameK._spawn_building("house", 0, kh_spot, true) # pop room for hero + aura pair
	check("ac12 Castle raised -> hero trainable", k_castle != null and gameK.can_train_unit("king"))
	var kf0: int = int(gameK.resources["food"])
	var kg0: int = int(gameK.resources["gold"])
	check("ac13 train_king musters at the Castle", gameK.train_king())
	check("ac14 hero costs 500 Food + 300 Gold",
			int(gameK.resources["food"]) == kf0 - 500 and int(gameK.resources["gold"]) == kg0 - 300,
			"food=%d gold=%d" % [int(gameK.resources["food"]), int(gameK.resources["gold"])])
	check("ac15 hero train time is the long 60s x Imperial 0.8 = 48s",
			k_castle.train_types == ["king"] and k_castle.train_timer > 47.0
			and k_castle.train_timer < 49.0, "timer=%s" % k_castle.train_timer)
	check("ac16 second muster refused while the first is queued",
			gameK.king_queued(0) and not gameK.can_train_unit("king") and not gameK.train_king())
	k_castle.train_timer = 0.05
	var k_spawned: bool = await wait_until(func() -> bool: return gameK.king_alive(0), 15000)
	check("ac17 the hero takes the field from the Castle queue", k_spawned)
	var the_king: Unit = null
	for u in gameK.units:
		if u.unit_type == "king" and u.owner_id == 0:
			the_king = u
	check("ac18 hero wears the DRAWN character (knight), full hero stats",
			the_king != null and the_king.hp == 650.0 and the_king.spr != null
			and String(the_king.spr.texture.resource_path).contains("king_knight_"),
			"tex=%s" % (String(the_king.spr.texture.resource_path) if the_king != null and the_king.spr != null else "none"))
	if the_king != null:
		the_king._king_apply_dir("e")
		var tex_e := String(the_king.spr.texture.resource_path)
		the_king._king_apply_dir("n")
		check("ac19 8-dir facing swaps the hero sprite",
				tex_e.contains("king_knight_e") and String(the_king.spr.texture.resource_path).contains("king_knight_n"),
				"e=%s n=%s" % [tex_e, String(the_king.spr.texture.resource_path)])
		the_king._king_apply_dir("s")
	check("ac20 resync serialises the hero as a normal unit record",
			the_king != null and String(gameK._mp_unit_record(the_king).get("type", "")) == "king"
			and int(gameK._mp_unit_record(the_king).get("owner", -1)) == 0)
	# The Archer's aura (Tiễn Thủ): measured through real
	# strikes — the drawn character is read live from the slot,
	# so the standing hero fights as the Archer for this check.
	gameK.slot_chars[0] = "archer"
	if the_king != null:
		var base_cell: Vector2i = gameK.world.world_to_cell(the_king.global_position)
		var m_near: Unit = gameK._make_unit(0, gameK.world.cell_center(
				gameK.world.nearest_walkable(base_cell + Vector2i(2, 0))), "militia")
		var m_far: Unit = gameK._make_unit(0, gameK.world.cell_center(
				gameK.world.nearest_walkable(base_cell + Vector2i(9, 0))), "militia")
		var foe1: Unit = gameK._make_unit(1, m_near.global_position + Vector2(30, 0), "militia")
		var foe2: Unit = gameK._make_unit(1, m_far.global_position + Vector2(30, 0), "militia")
		foe1.hp = 10000.0
		foe2.hp = 10000.0
		m_near.attack_target = foe1
		m_far.attack_target = foe2
		m_near.strike()
		m_far.strike()
		var d_near := 10000.0 - foe1.hp
		var d_far := 10000.0 - foe2.hp
		check("ac21 Tiễn Thủ aura: +8% damage inside 3 tiles, none outside",
				d_far > 0.0 and absf(d_near - d_far * 1.08) < 0.01
				and gameK.hero_aura_covers(m_near, "archer") and not gameK.hero_aura_covers(m_far, "archer")
				and gameK.aura_active_for(the_king),
				"near=%s far=%s" % [d_near, d_far])
		gameK.slot_chars[0] = "knight" # melee frame for the strike check
		var foe3: Unit = gameK._make_unit(1, the_king.global_position + Vector2(30, 0), "militia")
		foe3.hp = 10000.0
		the_king.attack_target = foe3
		the_king.strike()
		check("ac22 the hero does not buff his own strikes (shared frame atk, no kit rescale for the Knight)",
				absf((10000.0 - foe3.hp) - Stats.damage("king", foe3, 4)) < 0.01,
				"dmg=%s base=%s" % [10000.0 - foe3.hp, Stats.damage("king", foe3, 4)])
	# Death frees the muster: a new hero may be trained.
	if the_king != null:
		the_king.take_damage(100000.0)
	await get_tree().process_frame
	gameK.resources["food"] = 2000
	gameK.resources["gold"] = 1000
	check("ac23 after the hero falls, a successor may be mustered",
			not gameK.king_alive(0) and gameK.can_train_unit("king") and gameK.train_king())
	# A SKINNED hero keeps the DRAWN character's kit: force the
	# dormant slot (as a future owner would have it) — the Mage
	# drawn, Võ Hiệp worn: sprite is the skin, aura is the Mage's.
	gameK.slot_chars[0] = "mage"
	gameK.slot_skins[0] = "vo_hiep"
	var skinned: Unit = gameK._make_unit(0, gameK.world.cell_center(
			gameK.world.nearest_walkable(gameK.player_tc.origin_cell + Vector2i(3, 3))), "king")
	var sk_tex := String(skinned.spr.texture.resource_path) if skinned.spr != null else ""
	var sk_ally: Unit = gameK._make_unit(0, skinned.global_position + Vector2(40, 0), "militia")
	check("ac24 skin changes appearance only: vo_hiep sprite, mage regen aura",
			sk_tex.contains("king_vo_hiep_") and gameK.appearance_for(0) == "vo_hiep"
			and gameK.char_for(0) == "mage"
			and gameK.hero_aura_covers(sk_ally, "mage", true),
			"tex=%s" % sk_tex)
	gameK.slot_skins[0] = ""
	remove_child(gameK)
	gameK.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (ad) hero kits: auras + actives
	# Isolated instance; heroes are force-spawned per character.
	var gameS = load("res://main.tscn").instantiate()
	add_child(gameS)
	await get_tree().process_frame
	await get_tree().process_frame
	gameS.enemy_ai.waves_enabled = false
	var s_anchor: Vector2i = gameS.world.nearest_walkable(gameS.player_tc.origin_cell + Vector2i(6, 6))
	var s_pos: Vector2 = gameS.world.cell_center(s_anchor)
	# --- Knight: Khiên Sư Tử shield + cooldown gating.
	gameS.slot_chars[0] = "knight"
	var h_knight: Unit = gameS._make_unit(0, s_pos, "king")
	check("ad1 Khiên Sư Tử: 250 shield for 6s, CD 75s, recast refused",
			gameS.cast_hero_skill(h_knight) and absf(h_knight.shield_hp - 250.0) < 0.01
			and h_knight.shield_t > 5.5 and absf(h_knight.skill_cd_t - 75.0) < 0.5
			and not gameS.cast_hero_skill(h_knight),
			"shield=%s t=%s cd=%s" % [h_knight.shield_hp, h_knight.shield_t, h_knight.skill_cd_t])
	# hero_of_team resolves ONE hero per team (the first living) —
	# retire each phase's hero so the next phase's aura is his.
	gameS.units.erase(h_knight)
	h_knight.queue_free()
	# --- Paladin: Thánh Giáp aura + Thánh Quang heal/cleanse.
	gameS.slot_chars[0] = "paladin"
	var h_pal: Unit = gameS._make_unit(0, s_pos + Vector2(260, 0), "king")
	var ally_pal: Unit = gameS._make_unit(0, h_pal.global_position + Vector2(40, 0), "militia")
	ally_pal.max_hp = 1000.0 # test-only bulk: heal amounts must not clamp
	ally_pal.hp = 1000.0
	ally_pal.take_damage(100.0)
	var ad2_lost := 1000.0 - ally_pal.hp
	ally_pal.hp = 30.0
	ally_pal.stun_t = 3.0
	h_pal.hp = 400.0
	check("ad2 Thánh Giáp aura: a covered ally's hit is reduced by flat 3",
			absf(ad2_lost - 97.0) < 0.01, "lost=%s" % ad2_lost)
	check("ad3 Thánh Quang Hồi Phục: +160 HP in radius + cleanse (hero incl.), CD 75s",
			gameS.cast_hero_skill(h_pal) and absf(ally_pal.hp - 190.0) < 0.01
			and ally_pal.stun_t <= 0.0
			and absf(h_pal.hp - 560.0) < 0.01 and absf(h_pal.skill_cd_t - 75.0) < 0.5,
			"ally=%s hero=%s" % [ally_pal.hp, h_pal.hp])
	gameS.units.erase(h_pal)
	h_pal.queue_free()
	# --- Mage: Ma Lực Hồi Lưu regen aura + Thiên Thạch.
	gameS.slot_chars[0] = "mage"
	var h_mage: Unit = gameS._make_unit(0, s_pos + Vector2(520, 0), "king")
	var ally_mage: Unit = gameS._make_unit(0, h_mage.global_position + Vector2(40, 0), "militia")
	ally_mage.max_hp = 1000.0
	ally_mage.hp = 30.0
	ally_mage._tick_effects(1.05)
	check("ad4 mage aura Ma Lực Hồi Lưu: +1.2 HP/s to covered allies",
			absf(ally_mage.hp - 31.2) < 0.01, "hp=%s" % ally_mage.hp)
	var foe_mage: Unit = gameS._make_unit(1, h_mage.global_position + Vector2(120, 0), "militia")
	foe_mage.max_hp = 1000.0
	foe_mage.hp = 1000.0
	var foe_mage_far: Unit = gameS._make_unit(1, h_mage.global_position + Vector2(120, 130), "militia")
	foe_mage_far.max_hp = 1000.0
	foe_mage_far.hp = 1000.0
	check("ad5 Thiên Thạch Ma Thuật: 120 dmg in 2.5 tiles at the point, CD 75s",
			gameS.cast_hero_skill(h_mage, foe_mage.global_position)
			and absf(foe_mage.hp - 880.0) < 0.01
			and absf(foe_mage_far.hp - 1000.0) < 0.01
			and absf(h_mage.skill_cd_t - 75.0) < 0.5,
			"near=%s far=%s" % [foe_mage.hp, foe_mage_far.hp])
	gameS.units.erase(h_mage)
	h_mage.queue_free()
	# --- Dragoon aura + Assassin skill (single-skill spot checks;
	# the full per-hero matrix lives in the (16b) section).
	gameS.slot_chars[0] = "dragoon"
	var h_drag: Unit = gameS._make_unit(0, s_pos + Vector2(780, 0), "king")
	var ally_drag: Unit = gameS._make_unit(0, h_drag.global_position + Vector2(40, 0), "militia")
	check("ad6 Long Hành aura: covered allies move x1.10",
			absf(gameS.hero_speed_factor(ally_drag) - 1.10) < 0.01,
			"factor=%s" % gameS.hero_speed_factor(ally_drag))
	gameS.units.erase(h_drag)
	h_drag.queue_free()
	gameS.slot_chars[0] = "assassin"
	gameS.slot_chars[1] = "mage" # the foe king brings no defensive aura of his own
	var h_ass: Unit = gameS._make_unit(0, s_pos + Vector2(1040, 0), "king")
	var foe_king: Unit = gameS._make_unit(1, h_ass.global_position + Vector2(150, 0), "king")
	check("ad7 Ám Sát: blink behind the enemy hero, 160 burst, CD 75s",
			gameS.cast_hero_skill(h_ass, foe_king.global_position)
			and absf(foe_king.hp - 490.0) < 0.01
			and h_ass.global_position.distance_to(foe_king.global_position) < 40.0
			and absf(h_ass.skill_cd_t - 75.0) < 0.5,
			"foe=%s dist=%s" % [foe_king.hp,
					h_ass.global_position.distance_to(foe_king.global_position)])
	gameS.units.erase(h_ass)
	h_ass.queue_free()
	gameS.units.erase(foe_king)
	foe_king.queue_free()
	# --- MP validator: the skill command is gated like a sim rule.
	gameS.slot_chars[0] = "knight"
	var h_val: Unit = gameS._make_unit(0, s_pos + Vector2(1300, 0), "king")
	check("ad8 _mp_apply_skill rejects unknown units and wrong owners",
			not gameS._mp_apply_skill(0, 999999)
			and not gameS._mp_apply_skill(1, h_val.net_id))
	var ad8_cast: bool = gameS._mp_apply_skill(0, h_val.net_id)
	check("ad9 _mp_apply_skill casts off cooldown, then refuses on cooldown",
			ad8_cast and not gameS._mp_apply_skill(0, h_val.net_id))
	h_val.take_damage(100000.0)
	h_val.skill_cd_t = 0.0
	check("ad10 _mp_apply_skill refuses a dead hero",
			not gameS._mp_apply_skill(0, h_val.net_id))
	# --- The AI casts its hero's ONE skill when the trigger bites.
	gameS.slot_chars[1] = "knight"
	var h_ai: Unit = gameS._make_unit(1, s_pos + Vector2(1100, 0), "king")
	var _bait: Unit = gameS._make_unit(0, h_ai.global_position + Vector2(45, 0), "militia")
	gameS.enemy_ai._hero_skill_tick()
	check("ad11 AI hero casts Khiên Sư Tử with an enemy in reach",
			h_ai.skill_cd_t > 70.0, "cd=%s" % h_ai.skill_cd_t)
	# ------------------------------------------------ (ae) 13o animation coverage
	# Presentation-only life from the 13o pass — hurt rows, idle
	# breathing, the Ram's thrust, crop/tree sway, the flag shader,
	# beast breathing. Everything asserted is render state; the
	# sim never reads any of it.
	var ae_anchor: Vector2 = s_pos + Vector2(-520, -320)
	var ae_mil: Unit = gameS._make_unit(0, ae_anchor, "militia")
	ae_mil.take_damage(5.0)
	var ae_flash: bool = await wait_until(
			func() -> bool: return ae_mil.spr.modulate.r > 1.05, 2000)
	check("ae1 hurt flash fires on damage", ae_flash,
			"mod=%s" % ae_mil.spr.modulate)
	var ae_hurt: bool = await wait_until(
			func() -> bool: return ae_mil.anim_name.begins_with("hurt"), 3000)
	check("ae2 militia plays its hurt row after a hit", ae_hurt,
			"anim=%s" % ae_mil.anim_name)
	var ae_back: bool = await wait_until(
			func() -> bool: return ae_mil.anim_name.begins_with("idle"), 4000)
	check("ae3 hurt flinch ends and idle resumes", ae_back,
			"anim=%s" % ae_mil.anim_name)
	# The Spearman's idle row is ONE frame per direction: the
	# breathing layer must move the sprite anyway.
	var ae_spr: Unit = gameS._make_unit(0, ae_anchor + Vector2(60, 10), "spearman")
	var ae_y0: float = ae_spr.spr.position.y
	var ae_breathe := false
	var ae_t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - ae_t0 < 2500:
		await get_tree().process_frame
		if absf(ae_spr.spr.position.y - ae_y0) > 0.35:
			ae_breathe = true
			break
	check("ae4 spearman idle breathes (single-frame idle row)", ae_breathe)
	# The Ram's sheet is one repeated image: the attack-state
	# thrust cycle is its only attack motion — measure travel.
	var ae_cell: Vector2i = gameS.world.world_to_cell(ae_anchor)
	var ae_tower_cell := Vector2i(-1, -1)
	for r in range(0, 10):
		if ae_tower_cell.x >= 0:
			break
		for dy in range(-r, r + 1):
			if ae_tower_cell.x >= 0:
				break
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = ae_cell + Vector2i(9, 0) + Vector2i(dx, dy)
				if gameS.world.can_place(cand, Vector2i(2, 2)):
					ae_tower_cell = cand
					break
	# The battering target is a HOUSE, not a tower: a Watch Tower
	# shoots back and can kill the ram mid-measurement (a freed ram
	# then breaks the sampling below — seen on a throttled run).
	var ae_tower: Building = gameS._spawn_building("house", 1, ae_tower_cell, true)
	var ae_ram: Unit = gameS._make_unit(0,
			gameS.world.cell_center(ae_tower_cell + Vector2i(-4, 0)), "ram")
	ae_ram.order_attack(ae_tower)
	var ae_atk: bool = await wait_until(
			func() -> bool: return is_instance_valid(ae_ram) \
					and ae_ram.state == "attack", 30000)
	var ae_travel := 0.0
	if ae_atk and is_instance_valid(ae_ram):
		var pmin: Vector2 = ae_ram.spr.position
		var pmax: Vector2 = ae_ram.spr.position
		var ae_t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - ae_t1 < 1800 and is_instance_valid(ae_ram):
			await get_tree().process_frame
			if not is_instance_valid(ae_ram):
				break
			pmin = Vector2(minf(pmin.x, ae_ram.spr.position.x),
					minf(pmin.y, ae_ram.spr.position.y))
			pmax = Vector2(maxf(pmax.x, ae_ram.spr.position.x),
					maxf(pmax.y, ae_ram.spr.position.y))
		ae_travel = (pmax - pmin).length()
	check("ae5 ram thrusts while battering (single-image sheet)",
			ae_atk and ae_travel > 3.0,
			"state=%s travel=%.1f" % [
					ae_ram.state if is_instance_valid(ae_ram) else "freed",
					ae_travel])
	# Crop sway on a ripe field plot.
	var ae_field := FieldPlot.new()
	ae_field.cell = ae_cell + Vector2i(2, 4)
	ae_field.stage = 3
	gameS.add_child(ae_field)
	var ae_sway := false
	var ae_t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - ae_t2 < 2500:
		await get_tree().process_frame
		if absf(ae_field._spr.skew) > 0.012:
			ae_sway = true
			break
	check("ae6 ripe field crops sway", ae_sway)
	# Tree sway + beast breathing in the sandbox world.
	var ae_node: ResourceNode = null
	for n in gameS.world.nodes:
		if n.rtype == "wood":
			ae_node = n
			break
	var ae_tree := false
	if ae_node != null:
		var r0: float = ae_node._sway_rot
		var ae_t3 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - ae_t3 < 3000:
			await get_tree().process_frame
			if absf(ae_node._sway_rot - r0) > 0.008:
				ae_tree = true
				break
	check("ae7 trees sway in the wind", ae_tree and ae_node != null)
	var ae_beast := false
	if not gameS.world.beasts.is_empty():
		var bst = gameS.world.beasts[0]
		if bst._spr != null:
			var sc0: float = bst._spr.scale.y
			var ae_t4 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - ae_t4 < 3000:
				await get_tree().process_frame
				if bst._spr != null and absf(bst._spr.scale.y - sc0) > 0.0015:
					ae_beast = true
					break
	check("ae8 beasts breathe at idle", ae_beast,
			"beasts=%d" % gameS.world.beasts.size())
	# The flag-wave material rides the player's Town Center art.
	check("ae9 town center flag carries the wave shader",
			gameS.player_tc != null and gameS.player_tc.art_sprite != null
			and gameS.player_tc.art_sprite.material is ShaderMaterial)

	remove_child(gameS)
	gameS.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (af) 13n hero rig
	# ------------------------------------------------ (af) hero presentation: the flat-sprite path
	# 16b: the medieval roster renders through the 13j procedural
	# single-sprite path (owner-pack poses) — the cutout limb rig
	# is DEREGISTERED for every hero (hero_rig.json "chars" is
	# empty; the old rig data stays on disk, dormant). Everything
	# asserted is render state; the sim never reads any of it.
	var gameR = load("res://main.tscn").instantiate()
	add_child(gameR)
	await get_tree().process_frame
	await get_tree().process_frame
	gameR.enemy_ai.waves_enabled = false
	var r_anchor: Vector2i = gameR.world.nearest_walkable(gameR.player_tc.origin_cell + Vector2i(6, 6))
	var r_pos: Vector2 = gameR.world.cell_center(r_anchor)
	# af1: no rig for any of the new heroes (nor for the skins).
	var af_rig_ok := true
	for cid in Characters.CHAR_IDS:
		af_rig_ok = af_rig_ok and not HeroRig.has_rig(cid)
	check("af1 rig deregistered: all 8 medieval heroes use the flat path",
			af_rig_ok and not HeroRig.has_rig("vo_hiep")
			and not HeroRig.has_rig("bach_y") and not HeroRig.has_rig("tu_y"))
	# af2: every direction of every hero loads from the owner
	# packs at the standard format (height 92, binary alpha —
	# the weapon-free back views are audited by the pack builder
	# and its grass strip, see tools/build_owner_pack_sprites.py).
	var af_fmt := true
	var af_detail := ""
	for cid in Characters.CHAR_IDS:
		for d8 in Characters.DIRS8:
			var img := Image.load_from_file("res://assets/king_%s_%s.png" % [cid, d8])
			if img == null or img.is_empty() or img.get_height() != 92:
				af_fmt = false
				af_detail = "%s/%s missing or wrong height" % [cid, d8]
				continue
			img.convert(Image.FORMAT_RGBA8)
			for yy in range(img.get_height()):
				for xx in range(img.get_width()):
					var a := img.get_pixel(xx, yy).a
					if a > 0.01 and a < 0.99:
						af_fmt = false
						af_detail = "%s/%s semi-transparent pixel" % [cid, d8]
	check("af2 all 64 pack sprites load: height 92, binary alpha", af_fmt, af_detail)
	# af3: heroes build the flat path (no rig, sprite visible,
	# texture from their own pack).
	var af_heroes: Array = []
	for i in range(Characters.CHAR_IDS.size()):
		gameR.slot_chars[0] = Characters.CHAR_IDS[i]
		var h: Unit = gameR._make_unit(0, r_pos + Vector2(70 * i, 0), "king")
		af_heroes.append(h)
	var af_built := true
	for i in range(af_heroes.size()):
		var h: Unit = af_heroes[i]
		af_built = af_built and not h._rig_active and h.spr != null and h.spr.visible \
				and String(h.spr.texture.resource_path).contains(
						"king_%s_" % Characters.CHAR_IDS[i])
	check("af3 heroes render flat: own pack sprite, no rig", af_built)
	# af4: walk motion — the procedural bob lifts the sprite and
	# the body leans into the travel direction.
	var hw: Unit = af_heroes[0]
	hw.state = "move"
	hw.path = [hw.global_position + Vector2(96, 0)]
	hw._king_phase = PI * 0.5
	hw._king_tick(0.016)
	var af_bob: float = hw.spr.position.y - hw._king_base_pos.y
	var af_lean: float = hw.spr.rotation
	check("af4 walk bob + lean on the flat path",
			af_bob < -1.0 and absf(af_lean) > 0.02,
			"bob=%s lean=%s" % [af_bob, af_lean])
	# af5: idle breathing — the sprite rises and falls and the
	# squash breathes with it.
	hw.state = "idle"
	hw.path = []
	hw._king_t = 0.0
	hw._king_tick(0.016)
	var af_y0: float = hw.spr.position.y
	var af_sq0: float = hw.spr.scale.y
	hw._king_t = PI / 2.2 * 0.5
	hw._king_tick(0.016)
	check("af5 idle breathing moves the sprite",
			absf(hw.spr.position.y - af_y0) > 0.3 or absf(hw.spr.scale.y - af_sq0) > 0.001,
			"y %s -> %s" % [af_y0, hw.spr.position.y])
	# af6: hurt flash brightens the sprite.
	hw.take_damage(5.0, null)
	hw._king_tick(0.016)
	check("af6 hurt flash fires on the hero sprite",
			hw.spr.modulate.r > 1.05, "mod=%s" % hw.spr.modulate)
	# af7: a SKINNED hero keeps the same flat path (dormant skin).
	gameR.slot_chars[0] = "mage"
	gameR.slot_skins[0] = "vo_hiep"
	var hskin: Unit = gameR._make_unit(0, r_pos + Vector2(0, 90), "king")
	check("af7 skinned hero: no rig, single sprite visible (flat path)",
			hskin != null and not hskin._rig_active and hskin.spr != null
			and hskin.spr.visible,
			"rig=%s" % (hskin._rig_active if hskin != null else "null"))
	gameR.slot_skins[0] = ""
	# af8: 8-dir facing swaps the flat texture (back views come
	# from the pack's weapon-free back rotations).
	var hb: Unit = af_heroes[1]
	hb._king_apply_dir("s")
	var af8_s := String(hb.spr.texture.resource_path)
	hb._king_apply_dir("n")
	check("af8 facing swaps textures: s -> n (back rotation)",
			af8_s.ends_with("_s.png")
			and String(hb.spr.texture.resource_path).ends_with("_n.png"),
			"s=%s n=%s" % [af8_s, String(hb.spr.texture.resource_path)])
	remove_child(gameR)
	gameR.queue_free()
	await get_tree().process_frame
	# ------------------------------------------------ (13s) action panels + GDD technologies + queue cancel + scout/surrender
	var gameT = load("res://main.tscn").instantiate()
	add_child(gameT)
	await get_tree().process_frame
	await get_tree().process_frame
	gameT.enemy_ai.waves_enabled = false
	for bst in gameT.world.beasts:
		bst.dormant = true
	gameT.resources.food = 5000
	gameT.resources.wood = 5000
	gameT.resources.gold = 5000
	gameT.resources.stone = 5000
	gameT.set_team_age(0, 4)
	# Research is gated by the hosting building (GDD section 9).
	var chk0: Dictionary = gameT.research_check(0, "melee")
	check("s1 melee line locked without a Barracks", not bool(chk0.get("ok", true))
			and str(chk0.get("reason", "")).begins_with("Cần Trại lính"), str(chk0))
	# Place Blacksmith / Barracks / Lumber Camp instantly (capture pattern).
	var placed_s := {}
	for bt in ["blacksmith", "barracks", "lumber_camp"]:
		var bsize: Vector2i = gameT.get_build_def(bt).size
		var cell := Vector2i(-1, -1)
		for r in range(0, 16):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var cand: Vector2i = gameT.player_tc.origin_cell + Vector2i(dx, dy)
					if gameT.world.can_place(cand, bsize):
						cell = cand
						break
				if cell.x >= 0:
					break
			if cell.x >= 0:
				break
		gameT.enter_placement(bt)
		if cell.x >= 0 and gameT.confirm_placement(cell):
			for b in gameT.buildings:
				if b.btype == bt and b.team == 0:
					b.progress = 1.0
					b.complete = true
					if b.art_sprite != null:
						b.art_sprite.visible = true
					gameT.on_building_complete(b)
					placed_s[bt] = b
	check("s2 three research/production buildings placed", placed_s.size() == 3,
			"placed=%s" % str(placed_s.keys()))
	# Two houses: headroom so the queue tests are not pop-blocked
	# (the section force-spawns several units past the TC's cap).
	for hi in range(2):
		var hsize: Vector2i = gameT.get_build_def("house").size
		var hcell := Vector2i(-1, -1)
		for r in range(0, 16):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var hcand: Vector2i = gameT.player_tc.origin_cell + Vector2i(dx, dy)
					if gameT.world.can_place(hcand, hsize):
						hcell = hcand
						break
				if hcell.x >= 0:
					break
			if hcell.x >= 0:
				break
		gameT.enter_placement("house")
		if hcell.x >= 0 and gameT.confirm_placement(hcell):
			for b in gameT.buildings:
				if b.btype == "house" and b.team == 0 and not b.complete:
					b.progress = 1.0
					b.complete = true
					gameT.on_building_complete(b)
	# Melee tier 1 (Toolworking): cost deducted, completes, +1 attack.
	var food_s: int = gameT.resources.food
	check("s3 start_research(melee) accepted", gameT.start_research("melee"))
	check("s3 melee cost deducted (150 food)", gameT.resources.food == food_s - 150,
			"food=%d was=%d" % [gameT.resources.food, food_s])
	var forged: bool = await wait_until(func() -> bool: return gameT.tech_level(0, "melee") == 1, 30000)
	check("s4 melee tier 1 completes", forged)
	check("s4 melee attack bonus is +1", is_equal_approx(gameT.tech_atk_bonus(0, "militia"), 1.0))
	var u_mil = gameT._make_unit(0, Vector2(300, 300), "militia")
	var u_sp_e = gameT._make_unit(1, Vector2(340, 300), "spearman")
	u_mil.attack_target = u_sp_e
	var hp_e: float = u_sp_e.hp
	u_mil.strike()
	var expect_hit := Stats.damage("militia", u_sp_e, gameT.owner_age(0)) + 1.0
	check("s5 strike applies the melee bonus", is_equal_approx(hp_e - u_sp_e.hp, expect_hit),
			"dealt=%s expect=%s" % [hp_e - u_sp_e.hp, expect_hit])
	# Infantry armour tier 1 (Leather Armor): our infantry takes 1 less per hit.
	check("s6 start_research(inf_armor) accepted", gameT.start_research("inf_armor"))
	var mailed: bool = await wait_until(func() -> bool: return gameT.tech_level(0, "inf_armor") == 1, 30000)
	check("s6 infantry armour tier 1 completes", mailed)
	var u_sp_o = gameT._make_unit(0, Vector2(380, 300), "spearman")
	var u_mil_e = gameT._make_unit(1, Vector2(420, 300), "militia")
	u_mil_e.attack_target = u_sp_o
	var hp_o: float = u_sp_o.hp
	u_mil_e.strike()
	var expect_taken := Stats.damage("militia", u_sp_o, gameT.owner_age(1)) - 1.0
	check("s7 armour subtracts 1 per hit", is_equal_approx(hp_o - u_sp_o.hp, expect_taken),
			"taken=%s expect=%s" % [hp_o - u_sp_o.hp, expect_taken])
	# Economy lane: the wood line multiplies what a deposit delivers.
	gameT.tech_levels["wood"] = 2
	var expect_wood := int(round(10.0 * gameT.yield_mult("wood", false) * 1.4))
	check("s8 wood line +40% at tier 2", gameT.delivered_amount(10, "wood", false, 0) == expect_wood,
			"got=%d expect=%d" % [gameT.delivered_amount(10, "wood", false, 0), expect_wood])
	check("s8 ownerless delivery gets no tech", gameT.delivered_amount(10, "wood", false, -1)
			== int(round(10.0 * gameT.yield_mult("wood", false))))
	# Queue cancel at a specific building: full refund, timer resets.
	var barr_s: Building = placed_s.get("barracks")
	var food_q: int = gameT.resources.food
	var gold_q: int = gameT.resources.gold
	check("s9 train_at queues two militia", gameT.train_at(barr_s, "militia")
			and gameT.train_at(barr_s, "militia") and barr_s.train_types.size() == 2)
	check("s9 cancel queued entry refunds fully", gameT.cancel_train_at(barr_s, 1)
			and barr_s.train_types.size() == 1 and gameT.resources.food == food_q - 60
			and gameT.resources.gold == gold_q - 20,
			"food=%d gold=%d" % [gameT.resources.food, gameT.resources.gold])
	check("s9 cancel front entry empties queue", gameT.cancel_train_at(barr_s, 0)
			and barr_s.train_queue == 0 and gameT.resources.food == food_q
			and gameT.resources.gold == gold_q)
	# Nobility (Castle): cavalry mustered after it spawn with +20 HP.
	gameT.tech_levels["nobility"] = 1
	var u_cav = gameT._make_unit(0, Vector2(460, 300), "cavalry")
	check("s10 nobility cavalry spawn with +20 HP",
			is_equal_approx(u_cav.max_hp, Stats.unit_stat("cavalry", "hp") + 20.0),
			"max_hp=%s" % u_cav.max_hp)
	# Coinage (Market): exchange rates improve for the researching owner.
	check("s11 base market rates are 40/60", gameT.market_sell_gold(0) == 40
			and gameT.market_buy_gold(0) == 60,
			"%d/%d" % [gameT.market_sell_gold(0), gameT.market_buy_gold(0)])
	gameT.tech_levels["coinage"] = 1
	check("s11 coinage improves rates to 50/50", gameT.market_sell_gold(0) == 50
			and gameT.market_buy_gold(0) == 50,
			"%d/%d" % [gameT.market_sell_gold(0), gameT.market_buy_gold(0)])
	# HUD: the three designed panels exist and bind to a selection.
	gameT.hud.toggle_tab("build")
	check("s12 build panel has all 16 cards", gameT.hud.open_tab == "build"
			and gameT.hud._build_cards.size() == 16,
			"cards=%d" % gameT.hud._build_cards.size())
	gameT.hud.toggle_tab("tech")
	check("s12 tech panel has all 18 GDD lines", gameT.hud.open_tab == "tech"
			and gameT.hud._tech_cards.size() == 18,
			"lines=%d" % gameT.hud._tech_cards.size())
	gameT.selected_building = barr_s
	await get_tree().process_frame
	await get_tree().process_frame
	check("s13 selecting the Barracks opens its training page",
			gameT.hud.open_tab == "train" and gameT.hud._producer == barr_s
			and gameT.hud._train_cards["barracks"].size() == 6, # 15g: + Wagon
			"tab=%s" % gameT.hud.open_tab)
	check("s13 Esc-close hook consumes once", gameT.hud.close_panel_if_open()
			and not gameT.hud.close_panel_if_open())
	# Surrender (flow doc): an SP surrender ends the match as defeat.
	gameT.surrender()
	check("s14 SP surrender ends the match as a defeat", gameT.match_over == "defeat",
			"over=%s" % gameT.match_over)
	remove_child(gameT)
	gameT.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (13u) HUD rework: FA icons, scroll+tabs, tech tree, new pages, stats
	var gameU = load("res://main.tscn").instantiate()
	add_child(gameU)
	await get_tree().process_frame
	await get_tree().process_frame
	gameU.enemy_ai.waves_enabled = false
	check("u1 FA font vendored and loaded", gameU.hud._fa_font != null)
	check("u1 top-left falls back to the guest name signed out",
			gameU.hud._resolve_player_name() == "Khách",
			gameU.hud._resolve_player_name())
	gameU.hud.toggle_tab("build")
	var vis := 0
	for bt in gameU.hud._build_cards:
		var bc: Dictionary = gameU.hud._build_cards[bt]
		if (bc.root as Control).visible:
			vis += 1
	check("u2 build panel defaults to the Kinh tế tab (7 cards)",
			gameU.hud.open_tab == "build" and vis == 7, "vis=%d" % vis)
	gameU.hud._set_build_tab("mil")
	vis = 0
	for bt in gameU.hud._build_cards:
		var bc2: Dictionary = gameU.hud._build_cards[bt]
		if (bc2.root as Control).visible:
			vis += 1
	check("u2 Quân sự tab shows its 3 cards", vis == 3, "vis=%d" % vis)
	var nodes := 0
	for tid in gameU.hud._tech_nodes:
		nodes += (gameU.hud._tech_nodes[tid] as Array).size()
	check("u3 tech tree renders all 35 tier nodes in 18 lines",
			nodes == 35 and gameU.hud._tech_cards.size() == 18,
			"nodes=%d lines=%d" % [nodes, gameU.hud._tech_cards.size()])
	gameU.hud.toggle_tab("settings")
	check("u4 settings page opens", gameU.hud.open_tab == "settings")
	gameU.hud._music_vol = 0.5
	gameU.hud._apply_audio()
	var mbi := AudioServer.get_bus_index("Music")
	check("u4 music slider drives the Music bus", mbi >= 0
			and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(mbi)), 0.5),
			"bus=%d" % mbi)
	gameU.hud._show_names = false
	gameU.hud._apply_names()
	check("u4 names toggle reaches the hero overlay", not HeroOverlay.show_names)
	gameU.hud._show_names = true
	gameU.hud._apply_names()
	gameU.hud._brightness = 0.6
	gameU.hud._apply_brightness()
	check("u4 brightness layer actually darkens",
			gameU.hud._bright_rect != null and gameU.hud._bright_rect.color.a > 0.2,
			"a=%s" % (gameU.hud._bright_rect.color.a if gameU.hud._bright_rect != null else -1))
	gameU.hud._brightness = 1.0
	gameU.hud._apply_brightness()
	gameU.hud.toggle_tab("players")
	gameU.hud._refresh_players()
	check("u5 players page lists both SP sides",
			gameU.hud._players_box.get_child_count() == 3,
			"rows=%d" % gameU.hud._players_box.get_child_count())
	gameU.credit_owner(0, "food", 250)
	check("u6 gathered totals count real deposits",
			gameU.gathered_of(0, "food") >= 250,
			"g=%d" % gameU.gathered_of(0, "food"))
	gameU.hud.toggle_tab("stats")
	gameU.hud._refresh_stats()
	check("u6 stats builds a block per SP side",
			gameU.hud._stats_box.get_child_count() >= 3,
			"blocks=%d" % gameU.hud._stats_box.get_child_count())
	gameU.hud.add_chat_line("Bạn", "xin chào", "match", 0)
	check("u7 chat line appended with slot colour",
			"xin chào" in gameU.hud._chat_log.text)
	check("u7 SP chat input stays honestly disabled",
			not gameU.hud._chat_input.editable)
	# ------------------------------------------------ (13w fix) Đội channel only for a real team
	# Staged slot state on the same instance (the capture-harness
	# pattern): availability follows the LOCAL player's team size.
	gameU.mp_mode = true
	gameU.local_slot = 0
	gameU.slot_teams = [0, 1] # 1v1 queue match: a team of one each
	gameU.hud._refresh_chat_channels()
	check("cw1 1v1 chat has no Đội channel (whole segmented control hidden)",
			not gameU.hud._chat_seg.visible and not gameU.hud._chat_team_btn.visible)
	gameU.slot_teams = [0, 1, 2] # FFA: everyone alone
	gameU.hud._refresh_chat_channels()
	check("cw2 FFA chat has no Đội channel",
			not gameU.hud._chat_seg.visible)
	gameU.slot_teams = [0, 0, 1, 1] # 2v2: the local team has a mate
	gameU.hud._refresh_chat_channels()
	check("cw3 2v2 chat shows the Đội channel",
			gameU.hud._chat_seg.visible and gameU.hud._chat_team_btn.visible)
	gameU.slot_teams = [0, 0, 1] # paired team + one lone player
	gameU.local_slot = 2
	gameU.hud._refresh_chat_channels()
	check("cw4 the lone-team player gets no Đội channel",
			not gameU.hud._chat_seg.visible)
	gameU.local_slot = 0
	gameU.hud._refresh_chat_channels()
	check("cw5 the paired team keeps the Đội channel",
			gameU.hud._chat_seg.visible)
	remove_child(gameU)
	gameU.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (16b) skill sim plumbing: snapshot + checksum
	# The new skill state (shield pool + lifetime, taunt, Kiếm Vũ
	# flurry, the arrow-rain zone) must ride the resync snapshot
	# and the lockstep checksum exactly like the old kits' state
	# did. Isolated instance with the MP scaffolding the snapshot
	# path reads (the tr13 pattern).
	var gameV = load("res://main.tscn").instantiate()
	add_child(gameV)
	await get_tree().process_frame
	await get_tree().process_frame
	gameV.enemy_ai.waves_enabled = false
	gameV.mp_mode = true
	gameV.slot_teams = [0, 1]
	gameV.slot_names = ["A", "B"]
	gameV.slot_eliminated = [false, false]
	gameV.mp_wallets = [
		{"food": 500, "wood": 500, "gold": 300, "stone": 0, "iron": 0},
		{"food": 500, "wood": 500, "gold": 300, "stone": 0, "iron": 0}]
	gameV.mp_ages = [
		{"age": 4, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0},
		{"age": 4, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0}]
	gameV.mp_techs = [{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	gameV.mp_rally = [Vector2.ZERO, Vector2.ZERO]
	gameV.slot_tc_down = [false, false]
	gameV.slot_inert = [false, false]
	gameV.slot_chars = ["knight", "mage"]
	gameV.slot_skins = ["", ""]
	gameV.team_age = {0: 4, 1: 4}
	gameV.paused = true
	var v_anchor: Vector2i = gameV.world.nearest_walkable(gameV.player_tc.origin_cell + Vector2i(6, 6))
	var v_pos: Vector2 = gameV.world.cell_center(v_anchor)
	# --- v1: shield + taunt survive a snapshot round-trip.
	var hv1: Unit = gameV._make_unit(0, v_pos, "king")
	var vf1: Unit = gameV._make_unit(1, v_pos + Vector2(60, 0), "militia")
	gameV.cast_hero_skill(hv1)
	var v_hash0: int = gameV._mp_state_hash()
	var snap1: Dictionary = gameV._mp_snapshot_state()
	hv1.shield_hp = 0.0
	hv1.shield_t = 0.0
	hv1.skill_cd_t = 0.0
	vf1.taunt_t = 0.0
	vf1.taunt_id = -1
	gameV._mp_apply_snapshot(0, snap1)
	Engine.time_scale = 20.0 # the snapshot path parks the clock
	var rv1: Unit = gameV.unit_of_net_id(hv1.net_id)
	var rvf1: Unit = gameV.unit_of_net_id(vf1.net_id)
	check("v1 snapshot restores shield pool, taunt and cooldown; hash identical",
			rv1 != null and absf(rv1.shield_hp - 250.0) < 0.01
			and rv1.shield_t > 5.5 and absf(rv1.skill_cd_t - 75.0) < 0.5
			and rvf1 != null and rvf1.taunt_id == hv1.net_id and rvf1.taunt_t > 3.5
			and gameV._mp_state_hash() == v_hash0,
			"shield=%s taunt=%s hash %d vs %d" % [
					rv1.shield_hp if rv1 != null else -1.0,
					rvf1.taunt_t if rvf1 != null else -1.0,
					gameV._mp_state_hash(), v_hash0])
	# --- v2: the arrow-rain zone round-trips and keeps raining.
	gameV.slot_chars[0] = "archer"
	var hv2: Unit = gameV._make_unit(0, v_pos + Vector2(0, 200), "king")
	var vf2: Unit = gameV._make_unit(1, hv2.global_position + Vector2(100, 0), "militia")
	vf2.max_hp = 1000.0
	vf2.hp = 1000.0
	gameV.cast_hero_skill(hv2, vf2.global_position)
	var snap2: Dictionary = gameV._mp_snapshot_state()
	gameV.skill_zones.clear()
	gameV._mp_apply_snapshot(0, snap2)
	Engine.time_scale = 20.0
	var rvf2: Unit = gameV.unit_of_net_id(vf2.net_id)
	gameV._update_skill_zones(0.5)
	check("v2 snapshot restores the arrow rain; the first wave lands after resync",
			gameV.skill_zones.size() == 1 and rvf2 != null
			and absf(rvf2.hp - 960.0) < 0.01,
			"zones=%d foe=%s" % [gameV.skill_zones.size(),
					rvf2.hp if rvf2 != null else -1.0])
	gameV.skill_zones.clear()
	# --- v3: the Kiếm Vũ flurry is checksum state.
	gameV.slot_chars[0] = "ranger"
	var hv3: Unit = gameV._make_unit(0, v_pos + Vector2(0, 400), "king")
	var vf3: Unit = gameV._make_unit(1, hv3.global_position + Vector2(40, 0), "militia")
	vf3.max_hp = 1000.0
	vf3.hp = 1000.0
	var v_hash_pre: int = gameV._mp_state_hash()
	gameV.cast_hero_skill(hv3)
	var v_hash_cast: int = gameV._mp_state_hash()
	for i in range(5):
		gameV._update_hero_flurries(0.21)
	check("v3 flurry state moves the checksum; 5 slashes land on the lone foe",
			v_hash_cast != v_hash_pre and absf(vf3.hp - 840.0) < 0.01
			and hv3.flurry_left == 0,
			"foe=%s left=%s" % [vf3.hp, hv3.flurry_left])
	# --- v4: MP command shape — exactly one skill exists now.
	gameV.slot_chars[0] = "knight"
	var hv4: Unit = gameV._make_unit(0, v_pos + Vector2(0, 600), "king")
	check("v4 MP skill cmd: s=2 refused, foreign slot refused, s=1 applies",
			not gameV._mp_apply_skill_cmd(0, {"u": hv4.net_id, "s": 2})
			and not gameV._mp_apply_skill_cmd(1, {"u": hv4.net_id, "s": 1})
			and gameV._mp_apply_skill_cmd(0, {"u": hv4.net_id, "s": 1})
			and absf(hv4.skill_cd_t - 75.0) < 0.5,
			"cd=%s" % hv4.skill_cd_t)
	remove_child(gameV)
	gameV.queue_free()
	await get_tree().process_frame
	# ------------------------------------------------ (13y) match counters, APM, sampling, result screen
	# Isolated SP instance; counters are presentation-layer, so
	# the checks drive the same hooks real play uses (train
	# completion, construction completion, deaths, research).
	var gameY = load("res://main.tscn").instantiate()
	add_child(gameY)
	await get_tree().process_frame
	await get_tree().process_frame
	gameY.enemy_ai.waves_enabled = false
	var y_anchor: Vector2i = gameY.world.nearest_walkable(gameY.player_tc.origin_cell + Vector2i(6, 6))
	var y_pos: Vector2 = gameY.world.cell_center(y_anchor)
	var tc0: Building = null
	for b in gameY.buildings:
		if b.owner_id == 0:
			tc0 = b
			break
	# y1: a train completion counts as trained (spawn_unit is
	# the train-completion exit; it returns void, so the check
	# reads the counter, and the attacker below is a direct unit).
	var tr0: int = gameY.stat_counters(0).trained
	gameY.spawn_unit(tc0, "militia")
	var y_mil: Unit = gameY._make_unit(0, y_pos + Vector2(-30, 0), "militia")
	check("y1 train completion bumps trained",
			gameY.stat_counters(0).trained == tr0 + 1,
			"trained=%d base=%d" % [gameY.stat_counters(0).trained, tr0])
	# y2: a construction completion counts as built.
	var bu0: int = gameY.stat_counters(0).built
	var y_house: Building = gameY._spawn_building("house", 0,
			gameY.world.nearest_walkable(gameY.player_tc.origin_cell + Vector2i(-5, 3)), false)
	y_house.add_progress(9999.0)
	check("y2 construction completion bumps built", y_house.complete
			and gameY.stat_counters(0).built == bu0 + 1,
			"built=%d base=%d" % [gameY.stat_counters(0).built, bu0])
	# y3: a credited kill bumps the victim's lost + killer's kills.
	var lo1: int = gameY.stat_counters(1).lost
	var ki0: int = gameY.stat_counters(0).kills
	var y_vic: Unit = gameY._make_unit(1, y_pos + Vector2(30, 0), "militia")
	y_vic.take_damage(99999.0, y_mil)
	var y3cond: Callable = func() -> bool:
		return gameY.stat_counters(1).lost == lo1 + 1 \
				and gameY.stat_counters(0).kills == ki0 + 1
	var y3ok: bool = await wait_until(y3cond, 30000)
	check("y3 kill credits lost + kills", y3ok,
			"lost=%d/%d kills=%d/%d" % [gameY.stat_counters(1).lost, lo1,
					gameY.stat_counters(0).kills, ki0])
	# y4: a hero (king) as the killer also bumps hero_kills.
	var y_king: Unit = gameY._make_unit(0, y_pos + Vector2(-60, 0), "king")
	var y_vic2: Unit = gameY._make_unit(1, y_pos + Vector2(-30, 0), "militia")
	y_vic2.take_damage(99999.0, y_king)
	var y4ok: bool = await wait_until(
			func() -> bool: return gameY.stat_counters(0).hero_kills == 1, 30000)
	check("y4 hero kill credited", y4ok,
			"hero_kills=%d" % gameY.stat_counters(0).hero_kills)
	# y5: razing credits the last hitter; an unattributed fall
	# credits nobody (but still counts as the owner's loss).
	var rz0: int = gameY.stat_counters(0).razed
	var bl1: int = gameY.stat_counters(1).blost
	var y_ehouse: Building = gameY._spawn_building("house", 1,
			gameY.world.nearest_walkable(gameY.world.world_to_cell(y_pos) + Vector2i(4, 2)), false)
	y_ehouse.add_progress(9999.0)
	y_ehouse.take_damage(999999.0, y_mil)
	check("y5 raze credits last hitter + owner loss", y_ehouse.destroyed
			and gameY.stat_counters(0).razed == rz0 + 1
			and gameY.stat_counters(1).blost == bl1 + 1,
			"razed=%d/%d blost=%d/%d" % [gameY.stat_counters(0).razed, rz0,
					gameY.stat_counters(1).blost, bl1])
	var y_ehouse2: Building = gameY._spawn_building("house", 1,
			gameY.world.nearest_walkable(gameY.world.world_to_cell(y_pos) + Vector2i(-4, 3)), false)
	y_ehouse2.add_progress(9999.0)
	y_ehouse2.take_damage(999999.0)
	check("y5 unattributed fall credits no raze", y_ehouse2.destroyed
			and gameY.stat_counters(0).razed == rz0 + 1
			and gameY.stat_counters(1).blost == bl1 + 2,
			"razed=%d blost=%d" % [gameY.stat_counters(0).razed,
					gameY.stat_counters(1).blost])
	# y6: a research completion bumps researched. The food line
	# lives at the Storage and its first tier needs Age II.
	gameY.resources.food = 99999
	gameY.resources.wood = 99999
	gameY.resources.gold = 99999
	gameY.resources.stone = 99999
	gameY.set_team_age(0, 2)
	var y_store: Building = gameY._spawn_building("storage", 0,
			gameY.world.nearest_walkable(gameY.player_tc.origin_cell + Vector2i(5, -3)), false)
	y_store.add_progress(9999.0)
	check("y6 research starts at the Storage", gameY.start_research("food"))
	gameY._update_techs(9999.0)
	check("y6 research completion bumps researched",
			gameY.stat_counters(0).researched == 1 and gameY.tech_level(0, "food") == 1,
			"researched=%d" % gameY.stat_counters(0).researched)
	# y7: SP APM counts the local player's issued commands only.
	var ac0: int = gameY.stat_counters(0).actions
	gameY.selection = [y_mil]
	gameY.issue_order(y_pos)
	check("y7 train_at counts one action", gameY.train_at(tc0, "villager")
			and gameY.stat_counters(0).actions == ac0 + 2,
			"actions=%d base=%d" % [gameY.stat_counters(0).actions, ac0])
	gameY.match_time = 120.0
	check("y7 APM = actions per minute", absf(gameY.apm_of(0)
			- float(gameY.stat_counters(0).actions) / 2.0) < 0.05,
			"apm=%s" % gameY.apm_of(0))
	# y8: sampling appends full rows; the score Main samples is
	# the very score the HUD statistics use.
	var sn0: int = gameY.stat_series.size()
	gameY._sample_stats()
	check("y8 sampling appends a full row", gameY.stat_series.size() == sn0 + 1
			and (gameY.stat_series[sn0].rows as Dictionary).has(0)
			and (gameY.stat_series[sn0].rows as Dictionary).has(1)
			and ((gameY.stat_series[sn0].rows[0] as Dictionary).has("score")
			and (gameY.stat_series[sn0].rows[0] as Dictionary).has("pop")
			and (gameY.stat_series[sn0].rows[0] as Dictionary).has("mil")),
			"series=%d" % gameY.stat_series.size())
	check("y8 Main score == HUD score", gameY.match_score_of(0) == gameY.hud._owner_score(0)
			and gameY.match_score_of(1) == gameY.hud._owner_score(1),
			"main=%d/%d hud=%d/%d" % [gameY.match_score_of(0), gameY.match_score_of(1),
					gameY.hud._owner_score(0), gameY.hud._owner_score(1)])
	# y9: the result screen builds — victory, standings, chart,
	# breakdown; Xem lại hidden (SP matches have no replay).
	gameY.end_match("victory", "Thắng bằng quét sạch (annihilation)")
	await get_tree().process_frame
	check("y9 result screen shows THẮNG with full content",
			gameY.hud._end_panel.visible and gameY.hud._end_title.text == "THẮNG"
			and gameY.hud._end_note.text.contains("quét sạch")
			and gameY.hud._end_standings.get_child_count() == 2
			and gameY.hud._end_breakdown.get_child_count() == 2
			and gameY.hud._end_chart.owners.size() == 2
			and gameY.hud._end_chart.series.size() >= 1
			and not gameY.hud._end_replay_btn.visible,
			"title=%s rows=%d chart=%d/%d" % [gameY.hud._end_title.text,
					gameY.hud._end_standings.get_child_count(),
					gameY.hud._end_chart.owners.size(), gameY.hud._end_chart.series.size()])
	remove_child(gameY)
	gameY.queue_free()
	await get_tree().process_frame
	# y10: surrender gets its own banner.
	var gameZ = load("res://main.tscn").instantiate()
	add_child(gameZ)
	await get_tree().process_frame
	await get_tree().process_frame
	gameZ.surrender()
	await get_tree().process_frame
	check("y10 surrender shows ĐẦU HÀNG", gameZ.local_surrendered
			and gameZ.hud._end_panel.visible and gameZ.hud._end_title.text == "ĐẦU HÀNG",
			"title=%s" % gameZ.hud._end_title.text)
	remove_child(gameZ)
	gameZ.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (13x corrections) versus labels + sliders
	# Stage MP slot state on an isolated instance (same pattern
	# as the cw chat checks) and read the Players panel text.
	var gameW = load("res://main.tscn").instantiate()
	add_child(gameW)
	await get_tree().process_frame
	await get_tree().process_frame
	gameW.mp_mode = true
	gameW.local_slot = 0
	gameW.slot_tc_down = [false, false, false, false]
	gameW.mp_rally = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	gameW.mp_techs = [{"levels": {}, "active": {}}, {"levels": {}, "active": {}},
			{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	gameW.mp_wallets = [{"food": 800, "wood": 800, "gold": 800, "stone": 800},
			{"food": 800, "wood": 800, "gold": 800, "stone": 800},
			{"food": 800, "wood": 800, "gold": 800, "stone": 800},
			{"food": 800, "wood": 800, "gold": 800, "stone": 800}]
	gameW.mp_ages = [{"age": 1}, {"age": 1}, {"age": 1}, {"age": 1}]
	# Iterative label-text collector (a self-capturing recursive
	# lambda captures the variable while it is still null).
	var collect_text: Callable = func(root: Node) -> String:
		var s := ""
		var walk: Array = [root]
		while not walk.is_empty():
			var nd: Node = walk.pop_back()
			if nd is Label:
				s += (nd as Label).text + "|"
			for ch in nd.get_children():
				walk.append(ch)
		return s
	gameW.slot_teams = [0, 1]
	gameW.slot_names = ["An", "Bình"]
	gameW.slot_chars = ["knight", "archer"]
	gameW.slot_eliminated = [false, false]
	gameW.slot_inert = [false, false]
	gameW.hud._refresh_players()
	var vy1: String = collect_text.call(gameW.hud._players_box)
	check("vy1 1v1 panel: versus wording, no team labels",
			vy1.contains("Đấu với nhau") and not vy1.contains("Đội"), vy1)
	gameW.slot_teams = [0, 0, 1, 1]
	gameW.slot_names = ["An", "Bình", "Chi", "Dũng"]
	gameW.slot_chars = ["knight", "archer", "mage", "paladin"]
	gameW.slot_eliminated = [false, false, false, false]
	gameW.slot_inert = [false, false, false, false]
	gameW.hud._refresh_players()
	var vy2: String = collect_text.call(gameW.hud._players_box)
	check("vy2 true 2v2 keeps team wording",
			vy2.contains("2 đội") and vy2.contains("Đội 1"), vy2)
	gameW.slot_teams = [0, 1, 2]
	gameW.slot_names = ["An", "Bình", "Chi"]
	gameW.slot_chars = ["knight", "archer", "mage"]
	gameW.slot_eliminated = [false, false, false]
	gameW.slot_inert = [false, false, false]
	gameW.hud._refresh_players()
	var vy3: String = collect_text.call(gameW.hud._players_box)
	check("vy3 FFA panel: free-for-all wording, no team labels",
			vy3.contains("Đấu tự do") and not vy3.contains("Đội"), vy3)
	# The result screen follows the same versus rule.
	gameW.hud.show_end_panel("victory", 300.0, "Thắng")
	await get_tree().process_frame
	var vy4: String = collect_text.call(gameW.hud._end_standings) \
			+ collect_text.call(gameW.hud._end_breakdown)
	check("vy4 result screen: no team labels in a versus match",
			vy4.contains("An") and not vy4.contains("Đội"), vy4)
	remove_child(gameW)
	gameW.queue_free()
	await get_tree().process_frame
	# Sliders: one 0..100 scale; the number always equals the
	# knob's filled percent. Brightness maps onto 0.5x..1.5x.
	var gameSL = load("res://main.tscn").instantiate()
	add_child(gameSL)
	await get_tree().process_frame
	await get_tree().process_frame
	var hudS = gameSL.hud
	check("st1 all three sliders are 0..100",
			hudS._set_music_slider.min_value == 0.0 and hudS._set_music_slider.max_value == 100.0
			and hudS._set_sfx_slider.min_value == 0.0 and hudS._set_sfx_slider.max_value == 100.0
			and hudS._set_bright_slider.min_value == 0.0 and hudS._set_bright_slider.max_value == 100.0,
			"music=%s..%s bright=%s..%s" % [hudS._set_music_slider.min_value,
					hudS._set_music_slider.max_value, hudS._set_bright_slider.min_value,
					hudS._set_bright_slider.max_value])
	hudS._set_bright_slider.value = 50.0
	check("st2 brightness 50 = normal 1.0x, label matches knob",
			hudS._bright_pct == 50.0 and absf(hudS._brightness - 1.0) < 0.001
			and hudS._set_bright_val.text == "50%",
			"pct=%s mult=%s label=%s" % [hudS._bright_pct, hudS._brightness,
					hudS._set_bright_val.text])
	hudS._set_bright_slider.value = 100.0
	check("st3 brightness 100 = 1.5x, label matches knob",
			absf(hudS._brightness - 1.5) < 0.001 and hudS._set_bright_val.text == "100%",
			"mult=%s label=%s" % [hudS._brightness, hudS._set_bright_val.text])
	hudS._set_music_slider.value = 25.0
	check("st4 volume slider 25 drives 0.25 internally, label 25%",
			absf(hudS._music_vol - 0.25) < 0.001 and hudS._set_music_val.text == "25%",
			"vol=%s label=%s" % [hudS._music_vol, hudS._set_music_val.text])
	# Legacy migration: an old-format file (raw multiplier, no
	# scale marker) loads as pct = multiplier*100 - 50.
	var legacy := ConfigFile.new()
	legacy.set_value("display", "brightness", 1.5)
	legacy.save("user://hud_settings.cfg")
	hudS._load_settings()
	var mig_hi: bool = hudS._bright_pct == 100.0 and absf(hudS._brightness - 1.5) < 0.001
	legacy.set_value("display", "brightness", 0.5)
	legacy.save("user://hud_settings.cfg")
	hudS._load_settings()
	check("st5 legacy brightness migrates by subtracting 50",
			mig_hi and hudS._bright_pct == 0.0 and absf(hudS._brightness - 0.5) < 0.001,
			"pct=%s mult=%s" % [hudS._bright_pct, hudS._brightness])
	# Restore a sane saved state for later runs.
	hudS._bright_pct = 50.0
	hudS._brightness = 1.0
	hudS._music_vol = 0.8
	hudS._sfx_vol = 1.0
	hudS._save_settings()
	remove_child(gameSL)
	gameSL.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ 13z: 8 slots
	# z1: the colour table seats eight distinct factions and
	# every recoloured asset set is on disk.
	var z_colours_ok := TeamColors.SLOT_COUNT == 8 and TeamColors.NAMES.size() == 8
	var z_seen := {}
	for i in range(TeamColors.SLOT_COUNT):
		var zc := TeamColors.ui_color(i)
		var zkey := "%s,%s,%s" % [zc.r, zc.g, zc.b]
		if z_seen.has(zkey):
			z_colours_ok = false
		z_seen[zkey] = true
		for p in [TeamColors.unit_sheet(i, "villager")[0],
				TeamColors.building_path(i, "towncenter_t1"),
				TeamColors.ship_dir(i) + "war_ship.png",
				TeamColors.king_path(i)]:
			if not ResourceLoader.exists(p):
				z_colours_ok = false
	check("z1 eight slot colours, recoloured sets on disk", z_colours_ok)

	# z2/z3: an 8-base plains world — eight placeable TC spots,
	# each with all four starting resources within reach.
	var w8 := World.new()
	w8.biome_id = "grassland"
	w8.layout_id = "plains"
	w8.base_count = 8
	add_child(w8)
	w8.generate(12345)
	var z_spawn_ok := w8.base_centres.size() == 8
	var z_res_ok := true
	for bc in w8.base_centres:
		if not w8.can_place(bc - Vector2i(1, 1), Vector2i(3, 3)):
			z_spawn_ok = false
		for rt in ["wood", "food", "gold", "stone"]:
			if near_base.call(w8, bc, rt) < 1:
				z_res_ok = false
	check("z2 eight plains bases placeable", z_spawn_ok,
			"centres=%d" % w8.base_centres.size())
	check("z3 every 8p base has wood/food/gold/stone near", z_res_ok)
	remove_child(w8)
	w8.queue_free()
	await get_tree().process_frame

	# z4: FFA placements from the elimination record — survivor
	# first, then latest fall first; two slots that fell on the
	# same tick order by match score (slot 6 out-gathered slot 4).
	var gameZ8 = load("res://main.tscn").instantiate()
	add_child(gameZ8)
	await get_tree().process_frame
	await get_tree().process_frame
	gameZ8.enemy_ai.waves_enabled = false
	gameZ8.mp_mode = true
	gameZ8.slot_teams = [0, 1, 2, 3, 4, 5, 6, 7]
	gameZ8.slot_names = ["A", "B", "C", "D", "E", "F", "G", "H"]
	gameZ8.slot_eliminated = [false, true, true, true, true, true, true, true]
	gameZ8.mp_elim_order = [3, 1, 4, 6, 2, 5, 7]
	gameZ8.mp_elim_tick = {3: 100, 1: 150, 4: 200, 6: 200, 2: 260, 5: 300, 7: 340}
	gameZ8.credit_owner(6, "food", 2000)
	gameZ8.credit_owner(4, "food", 500)
	var zp: Array = gameZ8._mp_placements()
	check("z4 placements: survivor, latest fall, same-tick score break",
			zp == [0, 7, 5, 2, 6, 4, 1, 3], "got %s" % [zp])
	remove_child(gameZ8)
	gameZ8.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ 14a: replay controls
	# rp1: timeline markers derive from the recording alone —
	# age-up + hero-train commands out of the log, eliminations
	# out of the events sidecar, and the final tick; ordinary
	# commands and non-hero training produce NO marker.
	var gameRp = load("res://main.tscn").instantiate()
	add_child(gameRp)
	await get_tree().process_frame
	await get_tree().process_frame
	# 14b: rp3/rp4 exercise match-scoped state (per-team fog
	# tracking, the slot-indexed elim sidecar) — give the instance
	# the 2-slot FFA context a real replay would have, or
	# slot_count() is 0 and both checks read empty/observer state.
	gameRp.slot_teams = [0, 1]
	gameRp._replay_cmds = [
		{"from": 0, "tick": 100, "cmd": {"kind": "age_up", "to": 2}},
		{"from": 1, "tick": 150, "cmd": {"kind": "order"}},
		{"from": 1, "tick": 200, "cmd": {"kind": "train", "unit": "king", "b": 3}},
		{"from": 0, "tick": 300, "cmd": {"kind": "train", "unit": "militia", "b": 1}},
	]
	gameRp._replay_final_tick = 600
	var saved_replay_data: Dictionary = Net.replay_data
	Net.replay_data = {"events": [{"tick": 450, "kind": "elim", "slot": 2}]}
	var rp_markers: Array = gameRp.build_replay_markers()
	Net.replay_data = saved_replay_data
	var rp_kinds: Array = []
	for m in rp_markers:
		rp_kinds.append(str(m["kind"]))
	check("rp1 markers: age/hero/elim/end only, tick-ordered",
			rp_kinds == ["age", "hero", "elim", "end"]
			and int(rp_markers[0]["tick"]) == 100
			and int(rp_markers[0]["to"]) == 2
			and int(rp_markers[1]["slot"]) == 1
			and int(rp_markers[2]["slot"]) == 2,
			"got %s" % [rp_markers])
	# rp2: the GDD speed set cycles 1->2->4->8->0.5->1 and the
	# label is truthful at the fractional and top steps.
	gameRp.replay_set_speed(1.0)
	var rp_seq: Array = []
	for i in range(5):
		gameRp.replay_cycle_speed()
		rp_seq.append(gameRp.replay_speed())
	check("rp2 speed cycle 1,2,4,8,0.5,1",
			rp_seq == [2.0, 4.0, 8.0, 0.5, 1.0], "got %s" % [rp_seq])
	gameRp.replay_set_speed(0.5)
	var rp_txt_half: String = gameRp.replay_speed_text()
	gameRp.replay_set_speed(8.0)
	check("rp2 speed labels", rp_txt_half == "0.5×"
			and gameRp.replay_speed_text() == "8×",
			"%s / %s" % [rp_txt_half, gameRp.replay_speed_text()])
	# rp3: follow player — the view switches to a slot's own fog:
	# its base is visible to it, the far enemy base is unexplored;
	# full vision restores everything.
	gameRp.fog.track_teams = true
	gameRp.fog.update_fog()
	var rp_my_tc: Vector2i = Vector2i(-1, -1)
	var rp_foe_tc: Vector2i = Vector2i(-1, -1)
	for b in gameRp.buildings:
		if b.btype == "town_center" and not b.destroyed:
			if b.team == gameRp.team_of_slot(0):
				rp_my_tc = b.origin_cell + Vector2i(1, 1)
			elif b.team == gameRp.team_of_slot(1):
				rp_foe_tc = b.origin_cell + Vector2i(1, 1)
	gameRp.replay_set_follow(1)
	check("rp3 follow foe: own base seen, far base unseen",
			rp_foe_tc.x >= 0 and rp_my_tc.x >= 0
			and gameRp.fog.view_team_now() == gameRp.team_of_slot(1)
			and gameRp.fog.cell_state(rp_foe_tc) == 2
			and gameRp.fog.cell_state(rp_my_tc) == 0,
			"foe=%d mine=%d" % [gameRp.fog.cell_state(rp_foe_tc),
					gameRp.fog.cell_state(rp_my_tc)])
	gameRp.replay_set_follow(-1)
	check("rp3 full vision restores the whole map",
			gameRp.fog.view_team_now() == -1
			and gameRp.fog.cell_state(rp_my_tc) == 2)
	# rp4: the sidecar array the reporters send — slot-indexed,
	# survivors -1.
	gameRp.mp_elim_tick = {1: 450}
	check("rp4 elim ticks slot-indexed", gameRp._mp_elim_ticks() == [-1, 450],
			"got %s" % [gameRp._mp_elim_ticks()])
	remove_child(gameRp)
	gameRp.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------ (14c) new heroes: kits, wall, cyclone
	await _section_heroes16b()

	# ------------------------------------------------ (15b) diplomacy
	await _section_diplomacy15b()

	# ------------------------------------------------ (15e) spectator
	await _section_spectator15e()

	# ------------------------------------------------ (15g) transport
	await _section_transport15g()

	# ------------------------------------------------ verdict
	if failures == 0:
		print("ALL PASS")
	else:
		print("FAILED: %d test(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## (15e) Spectator — the follow-target chain (hero -> TC ->
## largest cluster), the pure cluster helper, mode switching +
## the manual-input break, the auto-camera pick (fresh events
## only, TC destruction outranks a cast), the delay badge; and
## (15f) the SP players panel naming the local player by their
## resolved display name. Presentation-only code, staged on a
## plain booted instance like the 15b section.
func _section_spectator15e() -> void:
	var gs = load("res://main.tscn").instantiate()
	add_child(gs)
	await get_tree().process_frame
	await get_tree().process_frame
	gs.enemy_ai.waves_enabled = false
	gs.mp_mode = true
	gs.slot_teams = [0, 1]
	gs.slot_names = ["An", "Binh"]
	gs.slot_eliminated = [false, false]
	var spec = Spectator.new()
	spec.game = gs
	# sp1: the cluster helper picks the fullest bucket.
	var pts: Array = [Vector2(0, 0), Vector2(10, 5), Vector2(20, 0),
			Vector2(900, 900)]
	var cl := Spectator.largest_cluster(pts, 96.0)
	check("sp1 cluster picks the fullest bucket",
			int(cl.get("count", 0)) == 3
			and Vector2(cl["pos"]).distance_to(Vector2(10, 2)) < 20.0,
			"got %s" % [cl])
	check("sp1 no points, no cluster",
			Spectator.largest_cluster([], 96.0).is_empty())
	# sp2: the follow chain on slot 1 (the SP enemy base).
	var tc1 = gs.tc_of(1)
	check("sp2 enemy TC staged", tc1 != null)
	var tc_centre: Vector2 = tc1.position + Vector2(tc1.size) * World.TILE * 0.5
	check("sp2 no hero: follow falls to the TC",
			spec.follow_target_pos(1) != null
			and Vector2(spec.follow_target_pos(1)).distance_to(tc_centre) < 1.0)
	var hero = gs._make_unit(1, tc_centre + Vector2(300, 120), "king")
	check("sp2 hero alive: follow targets the hero",
			Vector2(spec.follow_target_pos(1)).distance_to(hero.global_position) < 1.0)
	gs.units.erase(hero)
	hero.queue_free()
	tc1.destroyed = true
	var mpos := tc_centre + Vector2(-400, 200)
	for i in range(4):
		gs._make_unit(1, mpos + Vector2(i * 12, 0), "militia")
	gs._make_unit(1, mpos + Vector2(700, -500), "cavalry")
	var ct = spec.follow_target_pos(1)
	check("sp2 hero gone + TC down: follow falls to the largest cluster",
			ct != null and Vector2(ct).distance_to(mpos + Vector2(18, 0)) < 40.0,
			"got %s" % [ct])
	# sp3: modes are exclusive; manual input breaks to free.
	spec.set_follow(1)
	check("sp3 follow engages",
			spec.mode == Spectator.MODE_FOLLOW and spec.follow_slot == 1)
	spec._on_manual_input()
	check("sp3 manual input breaks follow to free",
			spec.mode == Spectator.MODE_FREE and spec.follow_slot == -1)
	spec.set_auto()
	check("sp3 auto engages, follow cleared",
			spec.mode == Spectator.MODE_AUTO and spec.follow_slot == -1)
	# sp4: the auto pick — fresh events only, TC fall outranks.
	var now := Time.get_ticks_msec()
	spec.note_cast(Vector2(500, 500), now)
	var pick: Dictionary = spec._auto_pick(now)
	check("sp4 fresh cast is the auto target",
			not pick.is_empty() and Vector2(pick["pos"]) == Vector2(500, 500)
			and String(pick["why"]) == "cast")
	spec.note_building_down(Vector2(900, 900), true, now)
	pick = spec._auto_pick(now)
	check("sp4 TC destruction outranks a cast",
			String(pick.get("why", "")) == "building")
	var stale = Spectator.new()
	stale.game = gs
	stale.note_cast(Vector2(1, 1), now - 60000)
	var spick: Dictionary = stale._auto_pick(now)
	check("sp4 stale events are ignored",
			Vector2(spick.get("pos", Vector2(-99, -99))) != Vector2(1, 1))
	# sp4b: a live battle cluster (3+ attackers on one target)
	# feeds the auto pick on its own.
	var foe = gs._make_unit(1, Vector2(1024, 1024), "militia")
	for i in range(3):
		var f = gs._make_unit(0, Vector2(1024 + i * 10, 990), "militia")
		f.state = "attack"
		f.attack_target = foe
	var bspec = Spectator.new()
	bspec.game = gs
	var bclusters: Array = bspec.battle_clusters()
	check("sp4b battle cluster found",
			bclusters.size() == 1 and int(bclusters[0]["count"]) >= 3,
			"got %s" % [bclusters])
	var bpick: Dictionary = bspec._auto_pick(now)
	check("sp4b battle is the auto target",
			String(bpick.get("why", "")) == "battle",
			"got %s" % [bpick])
	bspec.free()
	# sp5: the stream badge mirrors the room's delay setting.
	var old_delay := Net.cfg_obs_delay
	Net.cfg_obs_delay = 60
	check("sp5 badge shows the delay", spec._badge_text() == "Trễ 60 giây")
	Net.cfg_obs_delay = 0
	check("sp5 badge live at zero delay", spec._badge_text() == "Trực tiếp")
	Net.cfg_obs_delay = old_delay
	# sp6 (15f): the SP players panel names the local player by
	# the resolved display name — header and own card alike.
	gs.mp_mode = false # the panel's SP branch is the one under test
	Net.account_name = "tinpro"
	Net.auth_profile = {"display_name": "Tin"}
	gs.hud._refresh_players()
	var header := ""
	var own_sub := ""
	for ch in gs.hud._players_box.get_children():
		if ch is Label and header == "":
			header = String((ch as Label).text)
	for ch in gs.hud._players_box.get_children():
		for sub in ch.find_children("", "Label", true, false):
			if String((sub as Label).text).begins_with("Tin · Nhân vật:"):
				own_sub = String((sub as Label).text)
	check("sp6 players header uses the real name",
			header == "Tin đấu với Máy", "got '%s'" % header)
	check("sp6 own card sub uses the real name", own_sub != "",
			"subs scanned, none matched")
	Net.account_name = ""
	Net.auth_profile = {}
	# sp7 (15e-bis): an observer's people button opens the
	# DEDICATED spectator panel — never the players panel — and
	# a row's Theo dõi engages follow on that slot; the player
	# path through the same button is unchanged.
	gs.mp_mode = true
	var spec2 = Spectator.new()
	spec2.game = gs
	gs.add_child(spec2)
	gs.spectator = spec2
	gs.observer_mode = true
	check("sp7 spectator panel starts closed",
			not spec2.panel_is_open())
	gs.hud._on_people_button()
	check("sp7 observer button opens the spectator panel",
			spec2.panel_is_open())
	check("sp7 players panel stays shut for observers",
			gs.hud.open_tab != "players"
			and not (gs.hud._modals["players"]["panel"] as Control).visible)
	# The card must sit CENTRED (a build-time anchors-preset
	# trap once froze the panel root at 0x0 and pushed the
	# card off-screen — pin the laid-out geometry, not just
	# the visibility flags).
	await get_tree().process_frame
	var card := spec2.panel_ui.get_child(1) as Control
	var cr := card.get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	check("sp7 panel card is centred on screen",
			cr.size == Vector2(600, 470)
			and absf(cr.get_center().x - vp.x * 0.5) < 2.0
			and absf(cr.get_center().y - vp.y * 0.5) < 2.0,
			"card=%s vp=%s" % [cr, vp])
	gs.hud._on_people_button()
	check("sp7 observer button toggles the panel closed",
			not spec2.panel_is_open())
	gs.hud._on_people_button()
	var fb1: Button = spec2.panel_ui._follow_btns.get(1)
	check("sp7 row follow button exists for slot 1", fb1 != null)
	if fb1 != null:
		fb1.pressed.emit()
	check("sp7 row follow engages slot 1 and closes the panel",
			spec2.mode == Spectator.MODE_FOLLOW and spec2.follow_slot == 1
			and not spec2.panel_is_open())
	gs.slot_eliminated = [false, true]
	spec2.panel_ui.refresh()
	var fb1b: Button = spec2.panel_ui._follow_btns.get(1)
	check("sp7 eliminated slot disables Theo dõi",
			fb1b != null and fb1b.disabled)
	gs.slot_eliminated = [false, false]
	Net.cfg_obs_delay = 60
	spec2.panel_ui.refresh()
	check("sp7 panel badge shows the delay",
			spec2.panel_ui._badge_label.text == "Trễ 60 giây")
	Net.cfg_obs_delay = 0
	gs.observer_mode = false
	gs.hud._on_people_button()
	check("sp7 player button still opens the players panel",
			gs.hud.open_tab == "players")
	gs.hud._close_panel()
	# sp8 (15e-ter): the spectator screen carries NO player
	# gameplay HUD. First pin the PLAYER baseline on this very
	# HUD (it was built as a player): every gameplay piece
	# visible, the tab funnel opens pages, the skill cluster
	# follows the local hero.
	check("sp8 player: identity + age + pop + timer visible",
			gs.hud._identity_chip.visible and gs.hud._age_badge.visible
			and gs.hud._age_name_label.visible
			and gs.hud._pop_chip.visible and gs.hud._timer_box.visible)
	var res_vis: bool = gs.hud._res_chip_panels.size() == 5
	for p in gs.hud._res_chip_panels:
		if not (p as Control).visible:
			res_vis = false
	check("sp8 player: all 5 resource chips visible", res_vis)
	check("sp8 player: top bar spans wide",
			gs.hud._top_bar.anchor_left == 0.0
			and gs.hud._top_bar.anchor_right == 1.0)
	check("sp8 player: minimap buttons + action bar + sel chip visible",
			gs.hud._minimap_btns.visible and gs.hud._action_bar.visible
			and gs.hud._sel_chip.visible)
	check("sp8 player: settings surrender visible",
			gs.hud._set_surrender_btn.visible)
	gs.hud._open_tab("build")
	check("sp8 player: build tab opens the subpanel",
			gs.hud.open_tab == "build" and gs.hud._subpanel.visible)
	gs.hud._close_panel()
	var king0 = gs._make_unit(0, Vector2(1200, 1200), "king")
	gs.hud._refresh_skill_button()
	check("sp8 player: skill cluster shows for the local hero",
			gs.hud._skill_row.visible)
	# …then flip to observer and apply the gate exactly as
	# Main's boot does for a real observer match: everything
	# above must go, and stay gone under the per-frame paths.
	gs.observer_mode = true
	gs.hud._apply_observer_clean()
	check("sp8 observer: identity + age + pop + timer hidden",
			not gs.hud._identity_chip.visible
			and not gs.hud._age_badge.visible
			and not gs.hud._age_name_label.visible
			and not gs.hud._pop_chip.visible
			and not gs.hud._timer_box.visible)
	var res_hid := true
	for p in gs.hud._res_chip_panels:
		if (p as Control).visible:
			res_hid = false
	check("sp8 observer: all 5 resource chips hidden", res_hid)
	check("sp8 observer: top bar hugs the round buttons",
			gs.hud._top_bar.anchor_left == 1.0
			and gs.hud._top_bar.offset_left == -168.0
			and gs.hud._top_bar.offset_right == -6.0)
	check("sp8 observer: minimap buttons + action bar + sel chip hidden",
			not gs.hud._minimap_btns.visible
			and not gs.hud._action_bar.visible
			and not gs.hud._sel_chip.visible)
	check("sp8 observer: subpanel + diplomacy button hidden",
			not gs.hud._subpanel.visible
			and not gs.hud._dip_top_btn.visible)
	check("sp8 observer: settings surrender hidden",
			not gs.hud._set_surrender_btn.visible
			and not gs.hud._set_surrender_div.visible)
	gs.hud._refresh_skill_button()
	check("sp8 observer: skill cluster stays hidden (watched hero alive)",
			not gs.hud._skill_row.visible)
	gs.units.erase(king0)
	king0.queue_free()
	# The tab funnel refuses every gameplay tab for an
	# observer, but their own settings still open.
	gs.hud._open_tab("build")
	check("sp8 observer: build tab refuses",
			gs.hud.open_tab == "" and not gs.hud._subpanel.visible)
	gs.hud._open_tab("train")
	check("sp8 observer: train tab refuses", gs.hud.open_tab == "")
	gs.hud._open_tab("players")
	check("sp8 observer: players modal refuses",
			gs.hud.open_tab == ""
			and not (gs.hud._modals["players"]["panel"] as Control).visible)
	gs.hud._open_tab("diplomacy")
	check("sp8 observer: diplomacy modal refuses", gs.hud.open_tab == "")
	gs.hud._open_tab("settings")
	check("sp8 observer: settings still opens",
			gs.hud.open_tab == "settings"
			and (gs.hud._modals["settings"]["panel"] as Control).visible)
	gs.hud._close_panel()
	gs.observer_mode = false
	gs.spectator = null
	remove_child(spec2)
	spec2.queue_free()
	remove_child(gs)
	gs.queue_free()
	spec.free()
	stale.free()
	await get_tree().process_frame


## (15g) Land transport — trade Cart routes + payouts through
## credit_owner, partner validity (plain teams + diplomacy),
## route loss + reassignment, Wagon capacity / exclusions /
## loading rules, cargo fate on the wagon's death, ambush-alert
## gating, and the snapshot + checksum carry. SP instance first,
## then an MP-shaped pair for the snapshot round-trip.
func _section_transport15g() -> void:
	var gt = load("res://main.tscn").instantiate()
	add_child(gt)
	await get_tree().process_frame
	await get_tree().process_frame
	gt.enemy_ai.waves_enabled = false
	for bst in gt.world.beasts:
		bst.dormant = true
	gt.age = 2
	gt.resources = {"food": 5000, "wood": 5000, "gold": 5000, "stone": 500, "iron": 0}
	var tc_cell: Vector2i = gt.player_tc.origin_cell
	for i in range(4):
		gt._spawn_building("house", 0,
				gt._test_spot_near(tc_cell + Vector2i(-6, 4 + i * 3)), true, 0)
	var mkt_home = gt._spawn_building("market", 0,
			gt._test_spot_near(tc_cell + Vector2i(6, 0)), true, 0)
	var mkt_far = gt._spawn_building("market", 0,
			gt._test_spot_near(tc_cell + Vector2i(26, 10)), true, 0)
	var mkt_mid = gt._spawn_building("market", 0,
			gt._test_spot_near(tc_cell + Vector2i(16, 14)), true, 0)
	var barr = gt._spawn_building("barracks", 0,
			gt._test_spot_near(tc_cell + Vector2i(-8, -6)), true, 0)
	var mkt_enemy = gt._spawn_building("market", 1,
			gt._test_spot_near(gt.enemy_tc.origin_cell + Vector2i(6, 0)), true, 1)
	check("tr0 markets + barracks staged", mkt_home != null and mkt_far != null
			and mkt_mid != null and barr != null and mkt_enemy != null)
	# tr1: training lives where the design says — cart at the
	# Market, wagon at the Barracks, and nowhere else.
	check("tr1 HUD rosters carry the new units",
			gt.hud._roster_for("market") == ["cart"]
			and gt.hud._roster_for("barracks").has("wagon"))
	check("tr1 cart trains at the Market only",
			bool(gt.train_state(mkt_home, "cart").get("can", false))
			and not bool(gt.train_state(barr, "cart").get("can", false)))
	check("tr1 wagon trains at the Barracks only",
			bool(gt.train_state(barr, "wagon").get("can", false))
			and not bool(gt.train_state(mkt_home, "wagon").get("can", false)))
	var wood0: int = gt.resources.wood
	var gold0: int = gt.resources.gold
	check("tr1 train_at queues the cart", gt.train_at(mkt_home, "cart"))
	var cart_made = await wait_until(func() -> bool:
		for u in gt.units:
			if u.unit_type == "cart" and u.owner_id == 0:
				return true
		return false, 30000)
	check("tr1 the trained cart spawns, cost deducted", cart_made
			and int(gt.resources.wood) == wood0 - 100
			and int(gt.resources.gold) == gold0 - 50,
			"wood=%s gold=%s" % [gt.resources.wood, gt.resources.gold])
	# tr2: the payout formula — distance-scaled, floored, capped.
	var g_far: int = gt.trade_gold_for(mkt_home, mkt_far)
	var g_mid: int = gt.trade_gold_for(mkt_home, mkt_mid)
	check("tr2 longer route pays more", g_far > g_mid and g_mid >= 10,
			"far=%d mid=%d" % [g_far, g_mid])
	var d_far: float = (mkt_home.position - mkt_far.position).length() / World.TILE
	check("tr2 payout matches the distance formula",
			g_far == clampi(int(round(2.0 * d_far)), 10, 150),
			"gold=%d dist=%.1f" % [g_far, d_far])
	# tr3: a full round trip banks exactly trade_gold through
	# the economy choke point (wallet + gathered totals move).
	var cart = null
	for u in gt.units:
		if u.unit_type == "cart" and u.owner_id == 0:
			cart = u
	var gold_pre: int = gt.resources.gold
	var gathered_pre: int = gt.gathered_of(0, "gold")
	check("tr3 route assigns to the far own Market",
			gt.assign_trade_route(cart, mkt_far)
			and cart.trade_target == mkt_far and cart.trade_gold == g_far)
	var paid = await wait_until(func() -> bool:
		return int(gt.resources.gold) > gold_pre, 90000)
	check("tr3 round trip pays exactly the locked gold, via credit_owner",
			paid and int(gt.resources.gold) == gold_pre + g_far
			and gt.gathered_of(0, "gold") == gathered_pre + g_far,
			"gold=%s want=%s gathered=%s" % [gt.resources.gold,
					gold_pre + g_far, gt.gathered_of(0, "gold")])
	# tr4: an enemy Market is not a trade partner (plain teams).
	var cart2 = gt._make_unit(0, gt.world.cell_center(
			gt.world.nearest_walkable(mkt_home.origin_cell + Vector2i(1, 3))),
			"cart", 0)
	check("tr4 enemy market route refused",
			not gt.assign_trade_route(cart2, mkt_enemy)
			and cart2.trade_target == null)
	# tr5: the far Market falls mid-route — the cart gives the
	# route up (no payout for the cut trip) and takes a new one.
	var gold_pre5: int = gt.resources.gold
	mkt_far.take_damage(1000000.0)
	var idled = await wait_until(func() -> bool:
		return cart.trade_target == null and cart.state == "idle", 60000)
	check("tr5 market loss breaks the route, cart idles routeless",
			idled and int(gt.resources.gold) <= gold_pre5 + g_far,
			"state=%s gold=%s" % [cart.state, gt.resources.gold])
	check("tr5 route reassigns to the surviving Market",
			gt.assign_trade_route(cart, mkt_mid)
			and cart.trade_target == mkt_mid)
	cart.clear_trade_route()
	cart.state = "idle"
	# tr6: wagon capacity + the exclusion classes.
	var wcell: Vector2i = gt.world.nearest_walkable(tc_cell + Vector2i(10, 6))
	var wagon = gt._make_unit(0, gt.world.cell_center(wcell), "wagon", 0)
	var troops: Array = []
	for i in range(6):
		troops.append(gt._make_unit(0, gt.world.cell_center(
				gt.world.nearest_walkable(wcell + Vector2i(1, i % 3))), "militia", 0))
	var cav = gt._make_unit(0, gt.world.cell_center(
			gt.world.nearest_walkable(wcell + Vector2i(2, 0))), "cavalry", 0)
	var ram = gt._make_unit(0, gt.world.cell_center(
			gt.world.nearest_walkable(wcell + Vector2i(2, 1))), "ram", 0)
	var king_u = gt._make_unit(0, gt.world.cell_center(
			gt.world.nearest_walkable(wcell + Vector2i(2, 2))), "king", 0)
	check("tr6 loadable classes: foot only",
			Unit.wagon_loadable(troops[0]) and not Unit.wagon_loadable(cav)
			and not Unit.wagon_loadable(ram) and not Unit.wagon_loadable(king_u)
			and not Unit.wagon_loadable(wagon) and not Unit.wagon_loadable(cart))
	var pop_pre_load: int = gt.pop_current()
	var party: Array = troops.duplicate()
	party.append_array([cav, ram, king_u])
	gt.apply_order_for(party, null, wagon.global_position, 0)
	check("tr6 five aboard, sixth + excluded classes stay out",
			wagon.cargo.size() == 5 and gt.units.has(troops[5])
			and gt.units.has(cav) and gt.units.has(ram) and gt.units.has(king_u),
			"cargo=%d" % wagon.cargo.size())
	# tr7: loaded troops leave the roster (untargetable — the
	# ship rule) and stop counting toward population.
	check("tr7 loaded troops are out of the roster + pop",
			not gt.units.has(troops[0]) and not troops[0].visible
			and gt.pop_current() == pop_pre_load - 5,
			"pop=%d pre=%d" % [gt.pop_current(), pop_pre_load])
	var sixth = troops[5]
	gt.board_wagon_units([sixth], wagon, 0)
	check("tr7 a full wagon refuses the sixth", wagon.cargo.size() == 5
			and gt.units.has(sixth))
	# tr8: unload at a distant point puts everyone back, nearby.
	var dest_cell: Vector2i = gt.world.nearest_walkable(tc_cell + Vector2i(20, 16))
	wagon.order_wagon_unload(dest_cell)
	var unloaded = await wait_until(func() -> bool:
		return wagon.cargo.is_empty(), 60000)
	var near_n := 0
	for u in troops:
		if gt.units.has(u) and u.global_position.distance_to(
				gt.world.cell_center(dest_cell)) < 220.0:
			near_n += 1
	check("tr8 unload across the map restores the roster there",
			unloaded and near_n >= 5, "near=%d cargo=%d" % [near_n, wagon.cargo.size()])
	# tr9: the wagon dies — its passengers die with it, and the
	# losses reach the match statistics.
	for i in range(3):
		wagon.board_unit(troops[i])
	var lost_pre: int = int(gt._stat_rec(0).get("lost", 0))
	wagon.take_damage(1000000.0, troops[5])
	await get_tree().process_frame
	await get_tree().process_frame
	check("tr9 passengers die with the wagon, losses recorded",
			wagon.cargo.is_empty() and not is_instance_valid(troops[0])
			and int(gt._stat_rec(0).get("lost", 0)) >= lost_pre + 3,
			"lost=%s pre=%d" % [gt._stat_rec(0).get("lost", 0), lost_pre])
	# tr10: vehicles never flee and never fake an attack state.
	var cart3 = gt._make_unit(0, gt.world.cell_center(
			gt.world.nearest_walkable(mkt_home.origin_cell + Vector2i(2, 3))),
			"cart", 0)
	cart3.take_damage(10.0, troops[5])
	check("tr10 cart does not flee", cart3.state != "flee")
	cart3.order_attack(troops[5])
	check("tr10 cart attack order degrades to a move",
			cart3.attack_target == null and cart3.state != "to_attack"
			and cart3.state != "attack")
	# tr11: the ambush alert reaches the owner only, throttled.
	var foe_mil = gt._make_unit(1, gt.world.cell_center(
			gt.world.nearest_walkable(mkt_enemy.origin_cell + Vector2i(2, 3))),
			"militia", 1)
	var pings0: int = gt.hud.minimap.pings.size()
	gt.notify_transport_attacked(cart3, foe_mil)
	check("tr11 hostile hit pings the owner's minimap",
			gt.hud.minimap.pings.size() == pings0 + 1)
	gt.notify_transport_attacked(cart3, foe_mil)
	check("tr11 second hit inside 10 s is throttled",
			gt.hud.minimap.pings.size() == pings0 + 1)
	var own_mil = gt._make_unit(0, gt.world.cell_center(
			gt.world.nearest_walkable(mkt_home.origin_cell + Vector2i(3, 3))),
			"militia", 0)
	gt.notify_transport_attacked(cart3, own_mil)
	check("tr11 friendly fire never alerts",
			gt.hud.minimap.pings.size() == pings0 + 1)
	remove_child(gt)
	gt.queue_free()
	await get_tree().process_frame
	# ---- MP-shaped pair: diplomacy partner rule + the
	# snapshot/checksum carry for routes and cargo.
	var g1 = load("res://main.tscn").instantiate()
	add_child(g1)
	await get_tree().process_frame
	await get_tree().process_frame
	g1.enemy_ai.waves_enabled = false
	g1.mp_mode = true
	g1.slot_teams = [0, 1]
	g1.slot_names = ["A", "B"]
	g1.slot_eliminated = [false, false]
	g1.mp_wallets = [
		{"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0},
		{"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0}]
	g1.mp_ages = [
		{"age": 2, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0},
		{"age": 2, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0}]
	g1.mp_techs = [{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	g1.mp_rally = [Vector2.ZERO, Vector2.ZERO]
	g1.slot_tc_down = [false, false]
	g1.slot_inert = [false, false]
	g1.slot_chars = ["knight", "archer"]
	g1.slot_skins = ["", ""]
	g1.team_age = {0: 2, 1: 2}
	g1.mp_config = {"diplomacy": true}
	g1._dip_setup()
	check("tr12 enemy stance blocks foreign trade",
			not g1.trade_partner_ok(0, 1))
	g1._dip_set_stance(0, 1, g1.DIP_NEUTRAL)
	check("tr12 neutral stance opens foreign trade",
			g1.trade_partner_ok(0, 1))
	g1._dip_set_stance(0, 1, g1.DIP_ALLY)
	check("tr12 ally stance trades", g1.trade_partner_ok(0, 1))
	g1.mp_config = {}
	g1._dip_setup()
	check("tr12 without diplomacy, foreign FFA markets stay closed",
			not g1.trade_partner_ok(0, 1) and g1.trade_partner_ok(0, 0))
	# Re-arm diplomacy for the snapshot below (both instances
	# must hash the same tables) and freeze g1: the hash compare
	# needs a still sim between the snapshot and the readback.
	g1.mp_config = {"diplomacy": true}
	g1._dip_setup()
	g1.paused = true
	var tc1: Vector2i = g1.tc_of(0).origin_cell
	var gm_home = g1._spawn_building("market", 0,
			g1._test_spot_near(tc1 + Vector2i(6, 0)), true, 0)
	var gm_far = g1._spawn_building("market", 0,
			g1._test_spot_near(tc1 + Vector2i(26, 10)), true, 0)
	var gcart = g1._make_unit(0, g1.world.cell_center(
			g1.world.nearest_walkable(gm_home.origin_cell + Vector2i(1, 3))),
			"cart", 0)
	g1.assign_trade_route(gcart, gm_far)
	var gwagon = g1._make_unit(0, g1.world.cell_center(
			g1.world.nearest_walkable(gm_home.origin_cell + Vector2i(3, 3))),
			"wagon", 0)
	var gt1 = g1._make_unit(0, g1.world.cell_center(
			g1.world.nearest_walkable(gm_home.origin_cell + Vector2i(3, 4))),
			"militia", 0)
	var gt2 = g1._make_unit(0, g1.world.cell_center(
			g1.world.nearest_walkable(gm_home.origin_cell + Vector2i(4, 4))),
			"archer", 0)
	var hash_empty: int = g1._mp_state_hash()
	gwagon.board_unit(gt1)
	gwagon.board_unit(gt2)
	check("tr13 boarding moves the checksum (cargo is hashed)",
			g1._mp_state_hash() != hash_empty)
	var snap: Dictionary = g1._mp_snapshot_state()
	var g2 = load("res://main.tscn").instantiate()
	add_child(g2)
	await get_tree().process_frame
	await get_tree().process_frame
	g2.enemy_ai.waves_enabled = false
	g2.mp_mode = true
	g2.slot_teams = [0, 1]
	g2.slot_names = ["A", "B"]
	g2.slot_eliminated = [false, false]
	g2.mp_wallets = [
		{"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0},
		{"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0}]
	g2.mp_ages = [
		{"age": 2, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0},
		{"age": 2, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0}]
	g2.mp_techs = [{"levels": {}, "active": {}}, {"levels": {}, "active": {}}]
	g2.mp_rally = [Vector2.ZERO, Vector2.ZERO]
	g2.slot_tc_down = [false, false]
	g2.slot_inert = [false, false]
	g2.slot_chars = ["knight", "archer"]
	g2.slot_skins = ["", ""]
	g2.team_age = {0: 2, 1: 2}
	g2.mp_config = {"diplomacy": true}
	g2._dip_setup()
	g2.paused = true
	g2._mp_apply_snapshot(0, snap)
	Engine.time_scale = 20.0 # the snapshot path parks the clock
	var rcart = null
	var rwagon = null
	for u in g2.units:
		if u.unit_type == "cart" and u.owner_id == 0:
			rcart = u
		if u.unit_type == "wagon" and u.owner_id == 0:
			rwagon = u
	check("tr13 snapshot restores the route + the passengers",
			rcart != null and rcart.trade_target != null
			and rcart.trade_gold == gcart.trade_gold
			and rwagon != null and rwagon.cargo.size() == 2,
			"cart=%s wagon=%s" % [rcart != null, rwagon != null])
	check("tr13 restored sim hashes identically",
			g2._mp_state_hash() == g1._mp_state_hash(),
			"g1=%d g2=%d" % [g1._mp_state_hash(), g2._mp_state_hash()])
	remove_child(g1)
	g1.queue_free()
	remove_child(g2)
	g2.queue_free()
	await get_tree().process_frame
