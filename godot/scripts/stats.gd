class_name Stats
extends RefCounted
## Empire Age P3 — the single home for combat numbers.
##
## Unit stats (hp / attack / range_px / cooldown_s / sight_tiles /
## speed px-per-s). Ranges are in world pixels (1 tile = 32 px);
## melee range is measured to the target's body / footprint edge,
## the archer's 160 px = 5 tiles.
##
## COUNTER TABLE (kept deliberately small and readable):
##   * Militia strikes Archer-class targets at x1.5 (it closes the
##     distance and wins the duel it reaches).
##   * Archer strikes Villager-class targets at x1.25 (soft targets).
##   * Against BUILDINGS: Archer x0.5 and Villager x0.5 (arrows and
##     farm tools barely dent walls), Militia x1.0 — until the
##     Battering Ram asset arrives, Militia is the siege arm.
##   * Watch Tower arrows are flat damage (no counters): TOWER_ATK
##     by the OWNER's age — Feudal (age II) towers hit harder.

const UNIT_STATS := {
	"villager": {"hp": 50.0, "atk": 3.0, "range": 40.0, "cooldown": 1.2, "sight": 4, "speed": 95.0},
	"militia": {"hp": 110.0, "atk": 8.0, "range": 42.0, "cooldown": 1.0, "sight": 5, "speed": 102.0},
	"archer": {"hp": 75.0, "atk": 6.0, "range": 160.0, "cooldown": 1.4, "sight": 6, "speed": 100.0},
	# Self-drawn pass (Bé-authored art in the same family): spearman =
	# cheap Age-I pikeman; cavalry = Feudal shock unit at 1.6x villager
	# speed; ram = Age-III siege engine, walking pace of a pushed log.
	"spearman": {"hp": 95.0, "atk": 7.0, "range": 46.0, "cooldown": 1.1, "sight": 5, "speed": 105.0},
	"cavalry": {"hp": 140.0, "atk": 9.0, "range": 46.0, "cooldown": 1.1, "sight": 6, "speed": 152.0},
	"ram": {"hp": 220.0, "atk": 4.0, "range": 46.0, "cooldown": 1.5, "sight": 3, "speed": 48.0},
	# 15g land transport (genre defaults — the GDD names the units
	# but fixes no numbers; flagged "chờ Tín chốt" in KE-HOACH):
	# the trade Cart is an unarmed civilian vehicle (never flees,
	# unlike a villager — it is a wagon, not a person) a touch
	# quicker than foot soldiers; the troop Wagon is a sturdy
	# unarmed carrier at a laden pace just above infantry.
	"cart": {"hp": 70.0, "atk": 0.0, "range": 0.0, "cooldown": 1.0, "sight": 4, "speed": 110.0},
	"wagon": {"hp": 160.0, "atk": 0.0, "range": 0.0, "cooldown": 1.0, "sight": 4, "speed": 108.0},
	# The King (hero, Castle / Age IV, one alive per player): a
	# heavyweight duelist a step quicker than the Militia, with an
	# inspiration aura for nearby troops (KING_AURA_* below).
	"king": {"hp": 650.0, "atk": 26.0, "range": 44.0, "cooldown": 1.1, "sight": 6, "speed": 112.0},
}

const BUILDING_HP := {
	"town_center": 1200.0,
	"house": 350.0,
	"barracks": 650.0,
	"mining_camp": 500.0,
	"tower": 500.0,
	"blacksmith": 600.0,
	"lumber_camp": 500.0,
	"storage": 500.0,
	"market": 550.0,
	"dock": 550.0,
	"farm": 500.0,
	"castle": 1600.0,
	"wallwood": 400.0,
	"wallstone": 800.0,
	# 14c: Thạch Sơn's Nham Tường segments (300 HP per cell).
	"skillwall": 300.0,
	"gatewood": 500.0,
	"gatestone": 900.0,
}

## Unit-vs-unit class multipliers: COUNTERS[attacker][target class].
## Spearman pikes shred cavalry (x2); cavalry runs down archers and
## villagers (x1.5); archers pick off spearmen as well as villagers.
const COUNTERS := {
	"militia": {"archer": 1.5},
	"archer": {"villager": 1.25, "spearman": 1.25},
	"spearman": {"cavalry": 2.0},
	"cavalry": {"archer": 1.5, "villager": 1.5},
	# The King is a lifelong infantry duelist: +30% against the
	# infantry classes (foot soldiers and the villager rabble).
	"king": {"militia": 1.3, "spearman": 1.3, "villager": 1.3},
}

## Damage multiplier against buildings, by attacker type. The ram's
## log is built for gates and walls: x6. A ram barely scratches units
## (x0.1) and arrows plink off its hide roof (x0.25) — both applied
## as target-side rules in damage().
const VS_BUILDING := {
	"villager": 0.5,
	"militia": 1.0,
	"archer": 0.5,
	"spearman": 0.7,
	"cavalry": 0.6,
	"ram": 6.0,
	"king": 1.0,
}
## Imperial (Age IV) step: the Ram's vs-building multiplier rises
## from x6 to x7 for an Age-IV owner (applied in damage() when the
## attacker's age is passed in).
const RAM_VS_BUILDING_IMPERIAL := 7.0

## Watch Tower: arrow damage by owner age, range px, cooldown s.
## Imperial towers (age IV) hit harder again: 10 -> 14 -> 18.
const TOWER_ATK := {1: 10.0, 2: 14.0, 3: 14.0, 4: 18.0}
const TOWER_RANGE := 176.0 # 5.5 tiles
const TOWER_COOLDOWN := 1.2

## Age-up (Dark -> Feudal) research at the Town Center.
const AGE_UP_COST := {"food": 500}
const AGE_UP_TIME := 60.0
const AGE_UP_MIN_BUILDINGS := 2 # completed non-TC buildings required

## Age-up (Feudal -> Castle Age, Age III): researched at the Town
## Center once Feudal, needs a completed Barracks plus a Blacksmith
## or a Market (checked in Main.start_age_up3).
const AGE3_UP_COST := {"food": 800, "gold": 200}
const AGE3_UP_TIME := 90.0

## Age-up (Castle Age -> Imperial, Age IV): researched at the Town
## Center once in Age III, needs a completed Castle plus a Blacksmith
## or a Market (checked in Main.start_age_up4). Imperial perks: tower
## arrows step up (TOWER_ATK), castle arrows step up
## (CASTLE_ATK_BY_AGE), the Ram gains its imperial vs-building step,
## and every training queue runs faster (IMPERIAL_TRAIN_TIME_MULT —
## "Imperial logistics", applied via Main.train_time_mult).
const AGE4_UP_COST := {"food": 1000, "gold": 350}
const AGE4_UP_TIME := 120.0
const IMPERIAL_TRAIN_TIME_MULT := 0.8

## Castle: a super-tower that fires arrows like the Watch Tower but
## farther and harder (flat damage, no counters). Damage steps up
## in Imperial (Age IV): 16 -> 20.
const CASTLE_ATK := 16.0 # pre-Imperial value, kept for reference
const CASTLE_ATK_BY_AGE := {1: 16.0, 2: 16.0, 3: 16.0, 4: 20.0}
const CASTLE_RANGE := 192.0 # 6 tiles
const CASTLE_COOLDOWN := 1.2


static func castle_atk(age: int) -> float:
	return float(CASTLE_ATK_BY_AGE.get(clampi(age, 1, 4), 16.0))


## The hero (unit id "king" — the player's main character):
## trained at the Castle in Age IV only — KING_TRAIN_TIME seconds
## (every other unit trains in 5 s), one alive per player
## (enforced in Main.can_train_unit / _mp_apply_train;
## retrainable after death).
##
## PER-CHARACTER KITS (Tín's final model): the hero's kit comes
## from its DRAWN character (cosmetic skins never carry a kit).
## Auras check sim positions inside Unit.strike / take_damage /
## movement, so everything stays deterministic and lockstep-safe.
##   ngan_ky  Huyết Bào: allied military (not the hero) in aura
##            deal KING_AURA_MULT x damage. Xung Phong (CD 45 s):
##            self +50% speed, +100% damage for 5 s.
##   kim_hoa  Sinh Tồn: allies in aura (hero incl.) regenerate
##            +1 HP per 2 s. Vương Mệnh Hồi Phục (CD 60 s): heal
##            all allies in aura for 80 HP instantly.
##   lam_bao  Hàn Khí: enemies in aura move x0.85. Băng Phong
##            (CD 60 s): enemies within 2.5 tiles get x0.40 move
##            speed and x0.60 attack speed for 3 s.
##   bach_sa  Thánh Quang: allies in aura (hero incl.) take
##            x0.90 damage. Kết Giới (CD 70 s): a zone fixed at
##            the cast position for 8 s; allies inside take
##            x0.70 damage (multiplies with the aura).
const KING_TRAIN_TIME := 60.0
const AURA_RANGE_TILES := 3.0
const KING_AURA_RANGE_TILES := AURA_RANGE_TILES # legacy alias
const KING_AURA_MULT := 1.15

const HERO_KITS := {
	"ngan_ky": {"cd": 45.0, "buff_t": 5.0, "buff_spd": 1.5, "buff_dmg": 2.0},
	"kim_hoa": {"cd": 60.0, "regen_hp": 1.0, "regen_period": 2.0, "heal": 80.0},
	"lam_bao": {"cd": 60.0, "aura_slow": 0.85, "skill_range": 2.5,
			"skill_spd": 0.40, "skill_atkspd": 0.60, "skill_t": 3.0},
	"bach_sa": {"cd": 70.0, "aura_mitig": 0.90, "zone_mitig": 0.70, "zone_t": 8.0},
	# 14c — Temple Masters (NHAN-VAT-MOI-5-8.md, numbers verbatim):
	# Lôi Chấn: aura +12% attack speed. Lôi Độn (CD 50): dash up to
	# 5 tiles, 40 dmg within 1 tile of the landing, +20% move 4 s.
	"loi_chan": {"cd": 50.0, "aura_atkspd": 1.12, "dash_tiles": 5.0,
			"land_dmg": 40.0, "land_radius_tiles": 1.0,
			"buff_spd": 1.2, "buff_t": 4.0},
	# Xích Diệm: aura — allies' hits burn 3 HP / 0.5 s for 2 s.
	# Hỏa Ấn (CD 60): mark a unit in 6 tiles; it explodes after 2 s
	# for 70 dmg in 1.5 tiles (at the death spot if it dies first).
	"xich_diem": {"cd": 60.0, "aura_burn_amt": 3.0, "aura_burn_t": 2.0,
			"mark_dmg": 70.0, "mark_t": 2.0, "mark_radius_tiles": 1.5,
			"mark_range_tiles": 6.0},
	# Phong Linh (RANGED hero, bow range 5 tiles): aura +12% move.
	# Truy Phong Tiễn (CD 45): piercing snipe, range 8, 75 dmg.
	"phong_linh": {"cd": 45.0, "aura_spd": 1.12, "bow_range_tiles": 5.0,
			"snipe_dmg": 75.0, "snipe_range_tiles": 8.0},
	# Thạch Sơn: aura +3 flat armour. Sơn Băng Đạp (CD 55): leap up
	# to 4 tiles, 40 dmg in 2 tiles + knockback 1 tile + 30% slow 2 s.
	"thach_son": {"cd": 55.0, "aura_armor": 3.0, "leap_tiles": 4.0,
			"land_dmg": 40.0, "land_radius_tiles": 2.0,
			"knock_tiles": 1.0, "slow_mult": 0.70, "slow_t": 2.0},
}

## 13v: Chiêu 2 + Chiêu cuối (Ulti) numbers — Tín's approved kit
## designs (2026-11-10). Ranges/radii in TILES unless suffixed _px;
## targeted skills share SKILL_CAST_RANGE_TILES. All values feed
## Main's deterministic skill sim (zones + travelling shots).
const SKILL_CAST_RANGE_TILES := 6.0
const HERO_SKILL2 := {
	# Kiếm Khí Tung Hoành: a sword-wave shot along the facing line.
	"ngan_ky": {"cd": 30.0, "dmg": 45.0, "range_tiles": 5.0,
			"speed": 380.0, "width": 26.0},
	# Hoa Vũ Hồi Sinh: petal-rain zone — HoT + cleanse for allies.
	"kim_hoa": {"cd": 40.0, "hot": 6.0, "zone_t": 6.0,
			"radius_tiles": 2.5},
	# Thương Băng Xuyên Tâm: piercing shot; first enemy hit freezes.
	"lam_bao": {"cd": 35.0, "dmg": 35.0, "range_tiles": 6.0,
			"speed": 460.0, "width": 20.0, "freeze_t": 1.5},
	# Thánh Quang Phán Xét: targeted light pillar on an enemy group.
	"bach_sa": {"cd": 40.0, "dmg": 55.0, "radius_tiles": 2.0,
			"atk_mult": 0.70, "atk_t": 5.0},
	# 14c Chiêu 2:
	# Song Lôi Liên Kích: chain lightning — 55 to the primary target
	# (unit within 5 tiles), then 3 bounces of 30 to the nearest
	# enemies within 2 tiles of the previous victim.
	"loi_chan": {"cd": 35.0, "dmg": 55.0, "range_tiles": 5.0,
			"bounce_dmg": 30.0, "bounces": 3, "bounce_tiles": 2.0},
	# Diệm Phiến Toàn: facing cone 120° / 3 tiles — 50 dmg + burn
	# 4 HP / 0.5 s for 3 s.
	"xich_diem": {"cd": 35.0, "dmg": 50.0, "range_tiles": 3.0,
			"cone_cos": 0.5, "burn_amt": 4.0, "burn_t": 3.0},
	# Tiễn Vũ: arrow rain — 3 waves of 20 dmg over 3 s in 2.5 tiles.
	"phong_linh": {"cd": 30.0, "dmg": 20.0, "waves": 3, "zone_t": 3.0,
			"radius_tiles": 2.5},
	# Nham Tường: stone wall, 3 cells along the facing, 300 HP per
	# cell, 12 s. A Building of btype "skillwall" (obstacle rules).
	"thach_son": {"cd": 40.0, "range_tiles": 5.0, "wall_cells": 3,
			"wall_hp": 300.0, "wall_t": 12.0},
}
const HERO_SKILL3 := {
	# Vương Kiếm Giáng Thế: plunging greatsword — units AND
	# buildings, brief stun.
	"ngan_ky": {"cd": 120.0, "dmg_unit": 120.0, "dmg_bld": 250.0,
			"radius_tiles": 2.0, "stun_t": 1.0},
	# Vạn Hoa Khai Thiên: huge instant heal + brief immunity.
	"kim_hoa": {"cd": 150.0, "heal": 200.0, "radius_tiles": 4.0,
			"immune_t": 3.0},
	# Băng Hà Vĩnh Cửu: lingering blizzard — slow + DoT, and
	# buildings inside freeze (production/training/research pause).
	"lam_bao": {"cd": 130.0, "zone_t": 8.0, "radius_tiles": 3.0,
			"dot": 5.0, "slow_mult": 0.45},
	# Thiên Màn Bất Diệt: holy dome — ally shield + building immunity.
	"bach_sa": {"cd": 150.0, "zone_t": 8.0, "radius_tiles": 3.0,
			"shield": 120.0},
	# 14c Chiêu cuối:
	# Thiên Lôi Phạt Trận: storm zone 3 tiles / 6 s — a lightning
	# strike every 1 s for 45 (buildings 50%), 20% slow inside.
	"loi_chan": {"cd": 130.0, "zone_t": 6.0, "radius_tiles": 3.0,
			"dmg": 45.0, "bld_mult": 0.5, "slow_mult": 0.80},
	# Phượng Hỏa Giáng: 130 dmg in 3 tiles (150 vs buildings), then
	# burning ground 12 HP / 0.5 s for 5 s.
	"xich_diem": {"cd": 140.0, "dmg_unit": 130.0, "dmg_bld": 150.0,
			"radius_tiles": 3.0, "zone_t": 5.0, "zone_dot": 12.0},
	# Cuồng Phong Nộ: cyclone 3.5 tiles / 6 s — pulls enemies 0.5
	# tile per 0.5 s toward the centre, 15 dmg per 0.5 s, enemies
	# inside at -30% attack.
	"phong_linh": {"cd": 120.0, "zone_t": 6.0, "radius_tiles": 3.5,
			"dot": 15.0, "pull_tiles": 0.5, "atk_mult": 0.70},
	# Địa Long Lật Đất: quake in 3.5 tiles — 90 dmg units / 300
	# buildings + 40% slow for 3 s.
	"thach_son": {"cd": 150.0, "dmg_unit": 90.0, "dmg_bld": 300.0,
			"radius_tiles": 3.5, "slow_mult": 0.60, "slow_t": 3.0},
}

static func hero_cd(char_id: String) -> float:
	return float(HERO_KITS.get(char_id, {}).get("cd", 60.0))


static func hero_cd2(char_id: String) -> float:
	return float(HERO_SKILL2.get(char_id, {}).get("cd", 30.0))


static func hero_cd3(char_id: String) -> float:
	return float(HERO_SKILL3.get(char_id, {}).get("cd", 120.0))

## Villager fleeing (gameplay-completion pass): a villager hurt by a
## hostile flees to its nearest drop-off at FLEE_SPEED_MULT x speed
## and garrisons inside for up to FLEE_GARRISON_MAX seconds, leaving
## early once no hostile is within FLEE_SAFE_TILES of the building.
## A villager under an explicit player attack order does not flee
## for ATTACK_ORDER_NO_FLEE seconds after the order.
const FLEE_SPEED_MULT := 1.15
const FLEE_GARRISON_MAX := 5.0
const FLEE_GARRISON_MIN := 0.8
const FLEE_SAFE_TILES := 4.0
const ATTACK_ORDER_NO_FLEE := 10.0

## Farm fields: 1-tile plots placed near a completed Farm. A plot
## grows one stage per tend tick (villager work) and yields food per
## harvest until it exhausts, then lies bare until re-tilled.
const FIELD_COST_WOOD := 30
const FIELD_MAX_PER_FARM := 8
const FIELD_RADIUS := 6 # tiles from the Farm's footprint edge
const FIELD_HARVESTS := 3 # harvests before the plot exhausts
const FIELD_YIELD := 10 # food per harvest (= one carry load)


static func unit_stat(unit_type: String, key: String) -> float:
	var row: Dictionary = UNIT_STATS.get(unit_type, UNIT_STATS["villager"])
	return float(row.get(key, 0.0))


static func building_hp(btype: String) -> float:
	return float(BUILDING_HP.get(btype, 500.0))


static func tower_atk(age: int) -> float:
	return float(TOWER_ATK.get(clampi(age, 1, 4), 10.0))


## Ships (trained at the Dock; they live on the water grid only).
## The War Ship fights like a floating Archer: flat 6-damage arrows
## at 5-tile range, no counter table. Speeds are px/s on water.
const SHIP_STATS := {
	"fishing_boat": {"hp": 60.0, "atk": 0.0, "range": 0.0, "cooldown": 1.4, "sight": 5, "speed": 88.0},
	"transport": {"hp": 120.0, "atk": 0.0, "range": 0.0, "cooldown": 1.4, "sight": 5, "speed": 82.0},
	"war_ship": {"hp": 160.0, "atk": 6.0, "range": 160.0, "cooldown": 1.4, "sight": 6, "speed": 96.0},
}


static func ship_stat(ship_type: String, key: String) -> float:
	var row: Dictionary = SHIP_STATS.get(ship_type, SHIP_STATS["fishing_boat"])
	return float(row.get(key, 0.0))


## Wild beasts (team-neutral hostiles; see scripts/beast.gd).
## Balance guard: a lone villager (50 HP, 3 atk) LOSES to a wolf
## (kills it in ~17 s of swings; the wolf needs ~9 s), and two
## Militia (110 HP, 8 atk each) kill a bear while losing about one
## of them. `aggro` is in tiles, `carcass` is the Food left behind
## as a gatherable meat node.
const BEAST_STATS := {
	"wolf": {"hp": 40.0, "atk": 6.0, "cooldown": 1.0, "speed": 122.0, "aggro": 2.5, "carcass": 75},
	"bear": {"hp": 180.0, "atk": 14.0, "cooldown": 1.4, "speed": 72.0, "aggro": 1.5, "carcass": 150},
	"boar": {"hp": 80.0, "atk": 8.0, "cooldown": 1.2, "speed": 96.0, "aggro": 0.0, "carcass": 100},
}


static func beast_stat(species: String, key: String) -> float:
	var row: Dictionary = BEAST_STATS.get(species, BEAST_STATS["wolf"])
	return float(row.get(key, 0.0))


## ================================================================
## Technologies — GDD CÔNG NGHỆ v1.0 (Age of Empires 1 – Rise of
## Rome reference; see ~/workspace/empire-age/GDD-CONG-NGHE.md).
##
## Data-driven definitions following the GDD section-12 fields:
## each LINE below is a prerequisite chain — its id is the
## technology family, each tier is one researchable technology
## with name (the GDD field `name`), description (`fx`), the
## hosting building (`building_required`), the age gate
## (`age_required`), the four-resource `cost`
## (food/wood/gold/stone costs), `research_time` and its effect.
## `prerequisites` = the previous tier of the chain (research is
## strictly ordered, one active research per building, effects
## empire-wide and one-time — GDD section 9). The game has no
## civilization system, so `civilization_restrictions` is empty
## for every technology.
##
## Adaptations of the GDD onto this game (Tín's standing rules
## outrank the GDD; all stated in KE-HOACH 13s):
##   * ONE Barracks trains everything; Archery Range / Stable /
##     Siege Workshop do NOT exist — their military lines live at
##     the Barracks, siege + late lines at the Castle.
##   * Granary -> Storage (food line), Storage Pit -> Storage
##     (stone + gold lines) + Lumber Camp (wood line),
##     Market -> Market (Wheel, Coinage), Government Center ->
##     Castle (Architecture, Ballistics, Engineering, Nobility,
##     Aristocracy). Armour lines sit at the Blacksmith — the
##     game's smithing building (AoE 1 puts them at the Storage
##     Pit; our Lò rèn is the direct functional analog).
##   * Religion group SKIPPED: no priests, no temple.
##   * Logistics (Market) SKIPPED: population is integral per
##     unit in this sim; fractional pop cannot be represented.
##   * Writing SKIPPED: no allied-exploration sharing system.
##   * Ages Stone/Tool/Bronze/Iron map onto Ages I–IV.
##   * Ballistics is realised as +range (our projectiles always
##     hit, so accuracy has no meaning); Engineering as ram
##     damage (our ram has no range stat).
## Armour is a FLAT reduction per hit (min 1 damage lands),
## applied in Unit.take_damage.
const TECHS := {
	"food": {"building": "storage", "group": "economy", "icon": "food", "tiers": [
		{"name": "Thuần hoá (Domestication)", "age": 2, "cost": {"food": 75, "wood": 75}, "time": 30.0, "fx": "Thực phẩm từ ruộng nộp về +20%"},
		{"name": "Cày sắt (Plow)", "age": 3, "cost": {"food": 125, "wood": 125}, "time": 45.0, "fx": "Thực phẩm từ ruộng nộp về +20% nữa"},
		{"name": "Thuỷ lợi (Irrigation)", "age": 4, "cost": {"food": 200, "wood": 150}, "time": 60.0, "fx": "Thực phẩm từ ruộng nộp về +20% nữa"}]},
	"wood": {"building": "lumber_camp", "group": "economy", "icon": "wood", "tiers": [
		{"name": "Chế tác gỗ (Woodworking)", "age": 2, "cost": {"food": 100, "wood": 50}, "time": 25.0, "fx": "Gỗ nộp về +20%"},
		{"name": "Thủ công tinh xảo (Artisanship)", "age": 3, "cost": {"food": 150, "wood": 100}, "time": 40.0, "fx": "Gỗ nộp về +20% nữa"},
		{"name": "Nghệ nhân bậc thầy (Craftsmanship)", "age": 4, "cost": {"food": 200, "wood": 150}, "time": 55.0, "fx": "Gỗ nộp về +20% nữa"}]},
	"stone": {"building": "storage", "group": "economy", "icon": "stone", "tiers": [
		{"name": "Khai thác đá (Stone Mining)", "age": 2, "cost": {"food": 100, "wood": 75}, "time": 30.0, "fx": "Đá nộp về +20%"},
		{"name": "Mỏ đá sâu (Siegecraft)", "age": 3, "cost": {"food": 200, "wood": 150}, "time": 45.0, "fx": "Đá nộp về +20% nữa"}]},
	"gold": {"building": "storage", "group": "economy", "icon": "gold", "tiers": [
		{"name": "Khai thác vàng (Gold Mining)", "age": 2, "cost": {"food": 100, "wood": 75}, "time": 30.0, "fx": "Vàng nộp về +20%"},
		{"name": "Mỏ vàng sâu", "age": 3, "cost": {"food": 200, "wood": 150}, "time": 45.0, "fx": "Vàng nộp về +20% nữa"}]},
	"wheel": {"building": "market", "group": "economy", "icon": "train", "tiers": [
		{"name": "Bánh xe (Wheel)", "age": 2, "cost": {"food": 175, "wood": 50}, "time": 50.0, "fx": "Dân làng chạy nhanh hơn 10%"}]},
	"coinage": {"building": "market", "group": "economy", "icon": "gold", "tiers": [
		{"name": "Đúc tiền (Coinage)", "age": 3, "cost": {"food": 150, "gold": 100}, "time": 45.0, "fx": "Chợ bán được +50 Vàng, mua chỉ −50 Vàng"}]},
	"melee": {"building": "barracks", "group": "military", "icon": "swords", "tiers": [
		{"name": "Rèn vũ khí (Toolworking)", "age": 2, "cost": {"food": 150}, "time": 40.0, "fx": "Bộ binh +1 công"},
		{"name": "Luyện kim (Metalworking)", "age": 3, "cost": {"food": 220, "gold": 120}, "time": 50.0, "fx": "Bộ binh +1 công"},
		{"name": "Đúc kim loại (Metallurgy)", "age": 4, "cost": {"food": 275, "gold": 225}, "time": 60.0, "fx": "Bộ binh +2 công"}]},
	"bow": {"building": "barracks", "group": "military", "icon": "target", "tiers": [
		{"name": "Cung cải tiến (Improved Bow)", "age": 2, "cost": {"food": 100, "gold": 50}, "time": 30.0, "fx": "Cung thủ +1 công"},
		{"name": "Cung phức hợp (Composite Bow)", "age": 3, "cost": {"food": 200, "gold": 100}, "time": 40.0, "fx": "Cung thủ +1 công"}]},
	"cav": {"building": "barracks", "group": "military", "icon": "helmet", "tiers": [
		{"name": "Huấn luyện kỵ binh", "age": 2, "cost": {"food": 120, "gold": 40}, "time": 35.0, "fx": "Kỵ binh +1 công"},
		{"name": "Kỵ binh tinh nhuệ", "age": 3, "cost": {"food": 200, "gold": 100}, "time": 45.0, "fx": "Kỵ binh +1 công"}]},
	"academy": {"building": "barracks", "group": "military", "icon": "train", "tiers": [
		{"name": "Giáo dài (Hoplite)", "age": 3, "cost": {"food": 150, "gold": 50}, "time": 40.0, "fx": "Thương binh +2 công khi đánh kỵ binh"},
		{"name": "Trận địa giáo (Phalanx)", "age": 4, "cost": {"food": 250, "gold": 100}, "time": 50.0, "fx": "Thương binh +2 công nữa khi đánh kỵ binh"}]},
	"inf_armor": {"building": "blacksmith", "group": "defense", "icon": "iron", "tiers": [
		{"name": "Giáp da (Leather Armor)", "age": 2, "cost": {"food": 100}, "time": 40.0, "fx": "Bộ binh −1 sát thương mỗi đòn"},
		{"name": "Giáp vảy (Scale Armor)", "age": 3, "cost": {"food": 200, "gold": 100}, "time": 45.0, "fx": "Bộ binh −1 sát thương mỗi đòn"},
		{"name": "Giáp xích (Chain Mail)", "age": 4, "cost": {"food": 300, "gold": 150}, "time": 55.0, "fx": "Bộ binh −1 sát thương mỗi đòn"}]},
	"cav_armor": {"building": "blacksmith", "group": "defense", "icon": "iron", "tiers": [
		{"name": "Giáp da ngựa", "age": 2, "cost": {"food": 100}, "time": 40.0, "fx": "Kỵ binh −1 sát thương mỗi đòn"},
		{"name": "Giáp vảy ngựa", "age": 3, "cost": {"food": 200, "gold": 100}, "time": 45.0, "fx": "Kỵ binh −1 sát thương mỗi đòn"},
		{"name": "Giáp xích ngựa", "age": 4, "cost": {"food": 300, "gold": 150}, "time": 55.0, "fx": "Kỵ binh −1 sát thương mỗi đòn"}]},
	"arc_armor": {"building": "blacksmith", "group": "defense", "icon": "iron", "tiers": [
		{"name": "Áo giáp da (cung thủ)", "age": 2, "cost": {"food": 100}, "time": 35.0, "fx": "Cung thủ −1 sát thương mỗi đòn"},
		{"name": "Áo giáp vảy (cung thủ)", "age": 3, "cost": {"food": 200, "gold": 100}, "time": 40.0, "fx": "Cung thủ −1 sát thương mỗi đòn"},
		{"name": "Áo giáp xích (cung thủ)", "age": 4, "cost": {"food": 300, "gold": 150}, "time": 50.0, "fx": "Cung thủ −1 sát thương mỗi đòn"}]},
	"architecture": {"building": "castle", "group": "defense", "icon": "house", "tiers": [
		{"name": "Kiến trúc (Architecture)", "age": 4, "cost": {"wood": 300, "stone": 200}, "time": 50.0, "fx": "Công trình xây sau đó +25% máu"}]},
	"engineering": {"building": "castle", "group": "siege", "icon": "train", "tiers": [
		{"name": "Kỹ thuật công thành (Engineering)", "age": 3, "cost": {"food": 200, "gold": 150}, "time": 45.0, "fx": "Xe phá thành +25% sát thương"}]},
	"ballistics": {"building": "castle", "group": "siege", "icon": "target", "tiers": [
		{"name": "Đạn đạo (Ballistics)", "age": 3, "cost": {"food": 200, "gold": 100}, "time": 40.0, "fx": "Cung thủ, Tháp, Lâu đài +16 tầm bắn"}]},
	"nobility": {"building": "castle", "group": "special", "icon": "helmet", "tiers": [
		{"name": "Quý tộc (Nobility)", "age": 3, "cost": {"food": 150, "gold": 100}, "time": 40.0, "fx": "Kỵ binh tạo sau đó +20 máu"}]},
	"aristocracy": {"building": "castle", "group": "special", "icon": "flag", "tiers": [
		{"name": "Tốc hành (Aristocracy)", "age": 4, "cost": {"food": 150, "gold": 100}, "time": 40.0, "fx": "Thương binh chạy nhanh hơn 10%"}]},
}
## Panel order of the research buildings + their Vietnamese names.
const TECH_BUILDINGS: Array = ["town_center", "storage", "lumber_camp",
		"market", "barracks", "blacksmith", "castle"]
const TECH_GROUP_VN := {"economy": "Kinh tế", "military": "Quân sự",
	"defense": "Phòng thủ", "siege": "Công thành", "special": "Đặc biệt"}
const BUILDING_VN := {
	"town_center": "Town Center", "house": "Nhà", "barracks": "Trại lính",
	"mining_camp": "Mỏ đá", "tower": "Tháp canh", "blacksmith": "Lò rèn",
	"lumber_camp": "Trại gỗ", "storage": "Kho", "market": "Chợ",
	"dock": "Bến cảng", "farm": "Nông trại", "castle": "Lâu đài",
	"wallwood": "Tường gỗ", "wallstone": "Tường đá",
	"gatewood": "Cổng gỗ", "gatestone": "Cổng đá",
}
## Cumulative infantry attack bonus per melee-line tier.
const MELEE_ATK: Array = [0, 1, 2, 4]
const TECH_SELL_GOLD := 50
const TECH_BUY_GOLD := 50
const BALLISTICS_RANGE_BONUS := 16.0
const ARCHITECTURE_HP_MULT := 1.25
const NOBILITY_CAV_HP := 20.0


static func tech_def(tech_id: String) -> Dictionary:
	return TECHS.get(tech_id, {})


static func tech_ids_for(building: String) -> Array:
	var out: Array = []
	for id in TECHS:
		if str(TECHS[id].get("building", "")) == building:
			out.append(id)
	out.sort()
	return out


## Full damage of one hit from `attacker_type` onto `target`
## (a Unit or a Building — duck-typed on unit_type / btype).
## `attacker_age` only matters for the Ram's Imperial step.
static func damage(attacker_type: String, target, attacker_age: int = 1) -> float:
	var base := unit_stat(attacker_type, "atk")
	if target is Building:
		var mult := float(VS_BUILDING.get(attacker_type, 1.0))
		if attacker_type == "ram" and attacker_age >= 4:
			mult = RAM_VS_BUILDING_IMPERIAL
		return base * mult
	if target is Unit:
		var row: Dictionary = COUNTERS.get(attacker_type, {})
		var mult := float(row.get(target.unit_type, 1.0))
		if attacker_type == "ram":
			mult *= 0.1 # the log is for walls, not soldiers
		if target.unit_type == "ram" and attacker_type == "archer":
			mult *= 0.25 # arrows plink off the hide roof
		return base * mult
	return base
