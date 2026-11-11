class_name Decor
extends Node2D
## Static decoration that blocks its cell: CraftPix ruins and flat
## rocks (assets/env/). Not gatherable — pure map dressing / obstacles.

var kind: String = "ruin" # ruin | rockflat | cactus | ruin_snow | rockflat_snow
var cell: Vector2i = Vector2i.ZERO
var variant: int = 0

const TEX_PATHS := {
	"ruin": ["res://assets/env/ruin_0.png", "res://assets/env/ruin_1.png"],
	"rockflat": ["res://assets/env/rockflat_0.png"],
	"cactus": ["res://assets/env/cactus_0.png", "res://assets/env/cactus_1.png",
			"res://assets/env/cactus_2.png"],
	"ruin_snow": ["res://assets/env/ruin_snow_0.png", "res://assets/env/ruin_snow_1.png"],
	"rockflat_snow": ["res://assets/env/rockflat_snow_0.png"],
}

static var _tex_cache := {}


static func tex_for(kind: String, variant: int) -> Texture2D:
	var key := kind + ":" + str(variant)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var paths: Array = TEX_PATHS.get(kind, [])
	if not paths.is_empty():
		var p: String = paths[clampi(variant, 0, paths.size() - 1)]
		if ResourceLoader.exists(p):
			tex = load(p)
	_tex_cache[key] = tex
	return tex


func _draw() -> void:
	var tex := tex_for(kind, variant)
	if tex == null:
		draw_rect(Rect2(-12, -12, 24, 24), Color(0.5, 0.48, 0.44))
		return
	if kind == "ruin" or kind == "ruin_snow":
		# 112 px art drawn 84 px wide, ground line at the cell's bottom edge.
		draw_texture_rect(tex, Rect2(-42, -64, 84, 84), false)
	elif kind == "cactus":
		# 64 px cactus art drawn ~36 px, rooted at the cell's bottom.
		draw_texture_rect(tex, Rect2(-18, -34, 36, 36), false)
	else:
		# Wide flat rock (192x86 art): 58 px wide, sitting on the ground.
		draw_texture_rect(tex, Rect2(-29, -13, 58, 26), false)
