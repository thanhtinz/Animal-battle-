class_name ResourceNode
extends Node2D
## A gatherable resource tile: tree (wood), gold mine, stone pile,
## berry bush (food). Occupies exactly one grid cell and blocks it
## while it has amount left.
## Wood / stone / food nodes draw real CraftPix sprites (assets/env/,
## `variant` picks the artwork); gold keeps the drawn polygon (no
## CraftPix gold art in the packs).

var rtype: String = "wood" # wood | gold | stone | food
var amount: int = 100
var max_amount: int = 100
var cell: Vector2i = Vector2i.ZERO
var variant: int = 0
## Biome skin suffix ("" = grassland originals, "desert" / "snow"
## pick the "<rtype>_<skin>" rows below). World stamps this from the
## active biome at spawn; art comes from the CraftPix packs Tín
## provided (palms / snow trees / cacti) + graded rocks.
var skin: String = ""

const TEX_PATHS := {
	"wood": ["res://assets/env/tree_0.png", "res://assets/env/tree_1.png",
			"res://assets/env/tree_2.png", "res://assets/env/tree_3.png",
			"res://assets/env/tree_4.png"],
	"stone": ["res://assets/env/rock_0.png", "res://assets/env/rock_1.png",
			"res://assets/env/rock_2.png"],
	"food": ["res://assets/env/bush_0.png", "res://assets/env/bush_1.png",
			"res://assets/env/bush_2.png"],
	"wood_desert": ["res://assets/env/tree_desert_0.png", "res://assets/env/tree_desert_1.png",
			"res://assets/env/tree_desert_2.png", "res://assets/env/tree_desert_3.png",
			"res://assets/env/tree_desert_4.png"],
	"stone_desert": ["res://assets/env/rock_desert_0.png", "res://assets/env/rock_desert_1.png",
			"res://assets/env/rock_desert_2.png"],
	"food_desert": ["res://assets/env/bush_desert_0.png", "res://assets/env/bush_desert_1.png",
			"res://assets/env/bush_desert_2.png"],
	"wood_snow": ["res://assets/env/tree_snow_0.png", "res://assets/env/tree_snow_1.png",
			"res://assets/env/tree_snow_2.png", "res://assets/env/tree_snow_3.png",
			"res://assets/env/tree_snow_4.png"],
	"stone_snow": ["res://assets/env/rock_snow_0.png", "res://assets/env/rock_snow_1.png",
			"res://assets/env/rock_snow_2.png"],
	"food_snow": ["res://assets/env/bush_snow_0.png", "res://assets/env/bush_snow_1.png",
			"res://assets/env/bush_snow_2.png"],
}
const DRAW_RECTS := {
	"wood": Rect2(-27, -46, 54, 54),
	"stone": Rect2(-19, -19, 38, 38),
	"food": Rect2(-20, -25, 40, 40),
}

static var _tex_cache := {}

# 13o presentation: tree / berry-bush sway. Nodes are _draw-based,
# so the sway is a small rotation of the whole sprite around its
# ground point, re-drawn only when the angle actually changes by
# a visible step (a few redraws per sway cycle per node, not per
# frame). Stone / gold / meat never sway — rock doesn't bend.
var _t := 0.0
var _phase := 0.0
var _sway_rot := 0.0


func _ready() -> void:
	_phase = float(absi(cell.x * 73 + cell.y * 149) % 628) / 100.0
	if rtype != "wood" and rtype != "food":
		set_process(false)


func _process(delta: float) -> void:
	_t += delta
	var target := sin(_t * 1.15 + _phase) * (0.020 if rtype == "wood" else 0.013)
	if absf(target - _sway_rot) > 0.004:
		_sway_rot = target
		queue_redraw()


static func tex_for(rtype: String, variant: int, skin: String = "") -> Texture2D:
	var key := rtype + ":" + str(variant) + ":" + skin
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var paths: Array = []
	if skin != "":
		paths = TEX_PATHS.get(rtype + "_" + skin, [])
	if paths.is_empty():
		paths = TEX_PATHS.get(rtype, [])
	if not paths.is_empty():
		var p: String = paths[clampi(variant, 0, paths.size() - 1)]
		if ResourceLoader.exists(p):
			tex = load(p)
	_tex_cache[key] = tex
	return tex


func take(n: int) -> int:
	var t: int = mini(n, amount)
	amount -= t
	queue_redraw()
	return t


func _draw() -> void:
	var tex := tex_for(rtype, variant, skin)
	if tex != null and DRAW_RECTS.has(rtype):
		if rtype == "wood" or rtype == "food":
			# 13o sway: pivot at the trunk base (the rect's bottom
			# edge sits ~8 px under the node origin).
			draw_set_transform(Vector2(0, 8), _sway_rot, Vector2.ONE)
			draw_texture_rect(tex, DRAW_RECTS[rtype], false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, DRAW_RECTS[rtype], false)
		return
	match rtype:
		"wood":
			# Trunk + foliage blobs (fallback if the sprite is missing).
			draw_rect(Rect2(-2, 0, 4, 9), Color(0.4, 0.27, 0.14))
			draw_circle(Vector2(0, -6), 10, Color(0.13, 0.4, 0.16))
			draw_circle(Vector2(-7, -1), 7, Color(0.17, 0.48, 0.2))
			draw_circle(Vector2(7, -1), 7, Color(0.15, 0.44, 0.18))
			draw_circle(Vector2(0, -9), 5, Color(0.22, 0.56, 0.24))
		"gold":
			var pts := PackedVector2Array([Vector2(0, -11), Vector2(10, 2), Vector2(5, 10),
					Vector2(-5, 10), Vector2(-10, 2)])
			draw_colored_polygon(pts, Color(0.85, 0.66, 0.15))
			var pts2 := PackedVector2Array([Vector2(0, -6), Vector2(5, 1), Vector2(-4, 5)])
			draw_colored_polygon(pts2, Color(0.98, 0.83, 0.3))
		"stone":
			var pts := PackedVector2Array([Vector2(-11, 8), Vector2(-6, -4), Vector2(1, -9),
					Vector2(9, -3), Vector2(11, 8)])
			draw_colored_polygon(pts, Color(0.55, 0.56, 0.58))
			var pts2 := PackedVector2Array([Vector2(-6, 6), Vector2(-2, -3), Vector2(4, 5)])
			draw_colored_polygon(pts2, Color(0.68, 0.69, 0.71))
		"food":
			draw_circle(Vector2(0, 0), 11, Color(0.16, 0.42, 0.18))
			draw_circle(Vector2(-6, 3), 7, Color(0.2, 0.5, 0.22))
			draw_circle(Vector2(6, 3), 7, Color(0.18, 0.46, 0.2))
			for p in [Vector2(-4, -3), Vector2(3, -5), Vector2(5, 2), Vector2(-2, 4)]:
				draw_circle(p, 2.2, Color(0.9, 0.25, 0.3))
		"meat":
			# A beast carcass: a fur mound with ribs showing. Sized by
			# the remaining amount so a bear reads bigger than a wolf.
			var s := clampf(float(amount) / 100.0, 0.7, 1.4)
			draw_ellipse_poly(Vector2(0, 2), 15.0 * s, 8.0 * s, Color(0.42, 0.3, 0.2))
			draw_ellipse_poly(Vector2(-3, 0), 10.0 * s, 6.0 * s, Color(0.55, 0.4, 0.26))
			for i in range(3):
				var bx := -5.0 + float(i) * 5.0
				draw_arc(Vector2(bx, -1), 3.4, PI * 1.05, PI * 1.95, 8,
						Color(0.92, 0.9, 0.84), 1.6)
			draw_circle(Vector2(9.0 * s, 3), 2.6, Color(0.75, 0.3, 0.25))


## Filled ellipse via polygon (Node2D has no draw_ellipse).
func draw_ellipse_poly(centre: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(14):
		var a := TAU * float(i) / 14.0
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
