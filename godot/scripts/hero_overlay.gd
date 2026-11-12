class_name HeroOverlay
extends Node2D
## Hero presentation layer (13j) — one instance lives in Main:
##   mode "names" (z 120, a late pass over everything): the
##     owning PLAYER'S NAME above each hero's head, tinted with
##     the owner's slot colour. Characters carry no team colour
##     on their bodies (Tín's rule), so this label + the HP bar
##     are how allegiance reads in a fight.
## (A second "zones" instance existed for the old roster's
## barrier rings; 16b removed it — the mode value now draws
## nothing.) The layer honours Unit.visible, so fog of war and
## garrison hiding apply to names exactly as to the heroes.

var game = null # Main
var mode := "names"

## 13u: the in-match Settings toggle "Hiển thị tên" flips this —
## when false the names pass draws nothing.
static var show_names := true


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	if mode == "names" and not show_names:
		return
	if mode == "zones":
		return
	var font := ThemeDB.fallback_font
	for u in game.units:
		if not is_instance_valid(u) or u.unit_type != "king" or u.is_dead() \
				or not u.visible:
			continue
		var pname: String = game.hero_display_name(u.owner_id)
		if pname == "":
			continue
		var col: Color = TeamColors.ui_color(u.owner_id)
		var pos: Vector2 = u.global_position + Vector2(0, -u._disp_h - 14.0)
		var w: float = font.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var at: Vector2 = pos + Vector2(-w * 0.5, 0)
		draw_string_outline(font, at, pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				4, Color(0.05, 0.06, 0.1, 0.85))
		draw_string(font, at, pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
