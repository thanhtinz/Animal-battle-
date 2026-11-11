class_name Biomes
extends RefCounted
## Biome definitions — the single source for everything a map theme
## changes: ground tiles, node/decor skins, ambient effects, minimap
## colours AND the gameplay number modifiers (Tín: "Mỗi khu vực sẽ
## ảnh hưởng chỉ số"). Grassland is the identity baseline (all x1.00);
## every consumer (unit speed, deposit yield, field growth) reads the
## ACTIVE biome's table through Main — no scattered literals.
##
## Modifier semantics:
##   move          all units' speed multiplier
##   cavalry_move  EXTRA multiplier for cavalry only (stacks on move)
##   yield_<rtype> per-trip carry multiplier applied at deposit time:
##                 the villager delivers round(carried x mult)
##   field_growth  field stage-interval DIVISOR (interval = TEND_TIME
##                 / field_growth): <1 means fields grow slower
##   field_yield   food delivered per field harvest (same deposit rule)

const ORDER: Array = ["grassland", "desert", "snow"]

const DATA := {
	"grassland": {
		"name": "Đồng cỏ",
		"tiles_dir": "res://assets/tiles_seamless/",
		"node_skin": "",
		"decor_kinds": ["ruin", "rockflat"],
		"ambient": "water",
		"cliff": "cliff_grass",
		"minimap_land_a": Color(0.30, 0.50, 0.22),
		"minimap_land_b": Color(0.37, 0.58, 0.26),
		"minimap_water": Color(0.15, 0.36, 0.64),
		"fallback_land_a": Color(0.32, 0.55, 0.24),
		"fallback_land_b": Color(0.38, 0.62, 0.27),
		"fallback_water": Color(0.19, 0.42, 0.70),
		"mods": {"move": 1.0, "cavalry_move": 1.0,
			"yield_wood": 1.0, "yield_gold": 1.0, "yield_stone": 1.0, "yield_food": 1.0,
			"field_growth": 1.0, "field_yield": 1.0},
		"mod_lines": "Cân bằng — mọi chỉ số gốc",
	},
	"desert": {
		"name": "Sa mạc",
		"tiles_dir": "res://assets/tiles_desert/",
		"node_skin": "desert",
		"decor_kinds": ["ruin", "cactus"],
		"ambient": "desert",
		"cliff": "cliff_sand",
		"minimap_land_a": Color(0.78, 0.64, 0.36),
		"minimap_land_b": Color(0.84, 0.70, 0.42),
		"minimap_water": Color(0.15, 0.42, 0.66),
		"fallback_land_a": Color(0.76, 0.60, 0.33),
		"fallback_land_b": Color(0.83, 0.68, 0.40),
		"fallback_water": Color(0.16, 0.44, 0.68),
		"mods": {"move": 0.95, "cavalry_move": 1.10,
			"yield_wood": 0.8, "yield_gold": 1.3, "yield_stone": 1.2, "yield_food": 1.0,
			"field_growth": 0.7, "field_yield": 0.8},
		"mod_lines": "Di chuyển −5% · Gỗ −20% · Vàng +30% · Đá +20% · Ruộng chậm −30%, ít Food",
	},
	"snow": {
		"name": "Tuyết",
		"tiles_dir": "res://assets/tiles_snow/",
		"node_skin": "snow",
		"decor_kinds": ["ruin_snow", "rockflat_snow"],
		"ambient": "snow",
		"cliff": "cliff_stone",
		"minimap_land_a": Color(0.84, 0.88, 0.94),
		"minimap_land_b": Color(0.77, 0.83, 0.91),
		"minimap_water": Color(0.55, 0.72, 0.88),
		"fallback_land_a": Color(0.83, 0.88, 0.94),
		"fallback_land_b": Color(0.76, 0.82, 0.90),
		"fallback_water": Color(0.58, 0.74, 0.89),
		"mods": {"move": 0.90, "cavalry_move": 0.85,
			"yield_wood": 1.3, "yield_gold": 1.0, "yield_stone": 1.0, "yield_food": 0.9,
			"field_growth": 0.6, "field_yield": 1.0},
		"mod_lines": "Di chuyển −10% · Kỵ binh chậm thêm · Gỗ +30% · Ruộng chậm −40%",
	},
}


static func is_valid(id: String) -> bool:
	return DATA.has(id)


static func data(id: String) -> Dictionary:
	return DATA.get(id, DATA["grassland"])


static func display_name(id: String) -> String:
	return String(data(id)["name"])


static func mod(id: String, key: String) -> float:
	var mods: Dictionary = data(id)["mods"]
	return float(mods.get(key, 1.0))
