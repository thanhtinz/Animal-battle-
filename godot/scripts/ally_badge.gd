class_name AllyBadge
extends RefCounted

## Empire Age 17e addendum — alliance badge = ICON + COLOUR.
##
## The owner's sheet (assets/alliance_icons/icon_01..10.png)
## is a set of white silhouettes; the badge colour is one of
## the game's 8 slot colours (TeamColors.ui_color). Every
## surface that shows an alliance badge builds it through
## here: `make(icon, color_idx, px)` returns a TextureRect
## with the silhouette tinted by the slot colour. Unknown
## icon ids fall back to icon 1 (Sư Tử).

const NAMES := {
	1: "Sư Tử", 2: "Rồng", 3: "Phượng Hoàng", 4: "Sói",
	5: "Đầu Lâu", 6: "Kiếm Cánh", 7: "Anh Đào", 8: "Trúc",
	9: "Đinh Ba", 10: "Bánh Răng",
}
const COUNT := 10

static var _cache: Dictionary = {}


static func icon_id(v: int) -> int:
	return v if v >= 1 and v <= COUNT else 1


static func icon_texture(icon: int) -> Texture2D:
	var id := icon_id(icon)
	if _cache.has(id):
		return _cache[id]
	var t: Texture2D = load("res://assets/alliance_icons/icon_%02d.png" % id)
	_cache[id] = t
	return t


static func color_of(color_idx: int) -> Color:
	return TeamColors.ui_color(clampi(color_idx, 0, 7))


static func icon_name(icon: int) -> String:
	return String(NAMES.get(icon_id(icon), "Sư Tử"))


## A tinted badge image at px × px.
static func make(icon: int, color_idx: int, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon_texture(icon)
	tr.modulate = color_of(color_idx)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
