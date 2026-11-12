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
## PER-CHARACTER KITS (16b — NHAN-VAT-TAY-TRUNG-CO.md is the
## design source of truth): the hero's kit comes from its DRAWN
## character (cosmetic skins never carry a kit). Every hero has
## ONE passive aura (radius AURA_RANGE_TILES) + exactly ONE
## active skill on the UNIFIED 75 s cooldown. Auras check sim
## positions inside Unit.strike / take_damage / movement / fog,
## so everything stays deterministic and lockstep-safe.
## Optional per-hero basic-attack overrides of the shared "king"
## frame: "atk" (damage per hit), "atk_cd" (seconds per hit),
## "range_px" (attack range; archer/mage are ranged at 160).
const KING_TRAIN_TIME := 60.0
const AURA_RANGE_TILES := 3.0
const KING_AURA_RANGE_TILES := AURA_RANGE_TILES # legacy alias
const SKILL_CAST_RANGE_TILES := 6.0

const HERO_KITS := {
	# Knight: aura — allies (hero incl.) take x0.92 damage.
	# Khiên Sư Tử: 250 absorb shield on himself for 6 s + every
	# enemy within the aura radius is taunted onto him for 4 s.
	"knight": {"cd": 75.0, "aura_mitig": 0.92,
			"shield": 250.0, "shield_t": 6.0, "taunt_t": 4.0},
	# Berserker: aura — allies (not himself) strike 10% faster.
	# Rìu Xoáy Cuồng Nộ: 110 damage to enemies within 2 tiles.
	# Slow heavy axe: 34 per hit every 1.5 s.
	"berserker": {"cd": 75.0, "aura_atkspd": 1.10,
			"atk": 34.0, "atk_cd": 1.5,
			"dmg": 110.0, "radius_tiles": 2.0},
	# Archer (RANGED, bow 160): aura — allied military (not
	# herself) deal x1.08 damage. Mưa Tên: targeted point up to
	# 8 tiles away; 3 waves of 40 over 2 s in a 2.5-tile zone.
	"archer": {"cd": 75.0, "aura_dmg": 1.08,
			"atk": 22.0, "atk_cd": 1.2, "range_px": 160.0, "ranged": true,
			"rain_dmg": 40.0, "rain_waves": 3, "rain_t": 2.0,
			"radius_tiles": 2.5, "cast_tiles": 8.0},
	# Mage (RANGED, bolt 160): aura — allies (hero incl.)
	# regenerate 1.2 HP per second. Thiên Thạch Ma Thuật: 120
	# magic damage in 2.5 tiles at a targeted point.
	"mage": {"cd": 75.0, "regen_hp": 1.2, "regen_period": 1.0,
			"atk": 24.0, "atk_cd": 1.3, "range_px": 160.0, "ranged": true,
			"dmg": 120.0, "radius_tiles": 2.5},
	# Paladin: aura — allies (hero incl.) get +3 flat armour.
	# Thánh Quang Hồi Phục: heal allies in aura radius for 160
	# and cleanse every negative effect on them.
	"paladin": {"cd": 75.0, "aura_armor": 3.0, "heal": 160.0},
	# Dragoon: aura — allies (hero incl.) move x1.10. His lance
	# outreaches a sword (57 px ≈ 1.3x the 44 px melee frame).
	# Long Thương Xuyên Tâm: dash up to 5 tiles in a line, 120
	# damage to every enemy within path_half_px of the path.
	"dragoon": {"cd": 75.0, "aura_spd": 1.10,
			"atk": 27.0, "atk_cd": 1.15, "range_px": 57.0,
			"dash_tiles": 5.0, "dmg": 120.0, "path_half_px": 20.0},
	# Assassin: aura — allies (not himself) deal x1.10 damage
	# against enemy HEROES. Ám Sát: blink behind an enemy unit
	# within 6 tiles and stab it for 160. Fastest basic attacks
	# of the roster: 20 per hit every 0.7 s.
	"assassin": {"cd": 75.0, "aura_hero_dmg": 1.10,
			"atk": 20.0, "atk_cd": 0.7,
			"dmg": 160.0, "range_tiles": 6.0},
	# Ranger: aura — allies (hero incl.) gain +1 tile of sight.
	# Kiếm Vũ Lữ Hành: 5 slashes of 32 over 1 s, dealt round-
	# robin to the enemies within 2 tiles. Quick sword: 23 per
	# hit every 0.85 s.
	"ranger": {"cd": 75.0, "aura_sight": 1,
			"atk": 23.0, "atk_cd": 0.85,
			"slashes": 5, "slash_dmg": 32.0, "slash_interval": 0.2,
			"radius_tiles": 2.0},
}

static func hero_cd(char_id: String) -> float:
	return float(HERO_KITS.get(char_id, {}).get("cd", 75.0))

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
