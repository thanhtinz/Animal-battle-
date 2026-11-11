class_name HeroRig
extends RefCounted
## Cutout limb rig for the four MAIN CHARACTERS (13n) — Tín:
## "vẽ thêm animation cho chân tay đồ hoạt động đi" + "Vẽ thêm
## vũ khí cho nó". The characters ship one static pose per
## direction, so tools/build_hero_rig.py partitions each sprite
## into parts (back / under / leg_l / leg_r / torso / arm_l /
## arm_r) with joint pivots, and draws each character's weapon;
## assets/hero_rig.json is the generated data this class serves.
##
## The pose math lives in Unit._king_tick_rig (unit.gd) and is
## PRESENTATION ONLY, like the 13j procedural motion it extends:
## part rotations/offsets are computed from render-side timers
## and the unit's state string; nothing here is sim state, and
## nothing enters checksums, snapshots or the lockstep stream.
## Cosmetic SKINS have no rig (they cannot be owned yet): heroes
## wearing one keep the 13j single-sprite procedural treatment.

const DATA_PATH := "res://assets/hero_rig.json"
const ASSET_ROOT := "res://assets/"

static var _data: Dictionary = {}
static var _loaded := false
static var _tex_cache := {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed


static func has_rig(char_id: String) -> bool:
	_ensure()
	return _data.get("chars", {}).has(char_id)


static func char_data(char_id: String) -> Dictionary:
	_ensure()
	return _data.get("chars", {}).get(char_id, {})


static func dir_data(char_id: String, dir8: String) -> Dictionary:
	return char_data(char_id).get("dirs", {}).get(dir8, {})


static func tuning(char_id: String) -> Dictionary:
	return char_data(char_id).get("tuning", {})


static func weapon_class(char_id: String) -> String:
	return String(char_data(char_id).get("wclass", "staff"))


static func front_leg_factor(char_id: String) -> float:
	return float(char_data(char_id).get("front_leg_factor", 0.7))


static func tex(rel_path: String) -> Texture2D:
	if _tex_cache.has(rel_path):
		return _tex_cache[rel_path]
	var t: Texture2D = null
	var path := ASSET_ROOT + rel_path
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[rel_path] = t
	return t
