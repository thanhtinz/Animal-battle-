class_name ChatBubbles
extends Node2D

## In-match chat speech bubbles (17d, Đại chiến spec §7.2B).
## When a player sends an in-match chat message, a bubble
## with the text renders above their hero for ~4 seconds in
## their EQUIPPED style. Fallbacks: hero dead / not summoned
## → above their Town Center; no TC → nothing (the panel line
## still exists). Presentation only — never sim state.
##
## Fog rule (§7.2B): a bubble draws only while its anchor is
## in the LOCAL viewer's currently-visible fog cells.
## Teammates always reveal each other (their units generate
## their own vision), enemies show only when their hero/TC is
## actually in our vision — the team channel's routing is
## separate (server + Main filter); this layer only gates
## DRAWING by fog.
##
## The static style table + paint helpers are shared with the
## settings panel previews and the chat panel's block skinning
## (Hud._new_chat_block), so all three surfaces agree.

const LIFE := 4.0 # seconds on screen (spec default, §11.17)
const MAX_W := 190.0
const FONT_SIZE := 13

const STYLES := {
	"mac_dinh": {
		"name": "Mặc định",
		"bg": Color(0.05, 0.07, 0.14, 0.92),
		"border": Color(0.98, 0.80, 0.35),
		"border_w": 1,
		"text": Color(0.96, 0.93, 0.85),
		"glyph": false,
	},
	"hang": {
		"name": "Hạng",
		"bg": Color(0.10, 0.13, 0.22, 0.92),
		"border": Color(0.75, 0.82, 0.95),
		"border_w": 1,
		"text": Color(1, 1, 1),
		"glyph": false,
	},
	"vo_dich": {
		"name": "Vô địch Đại chiến",
		"bg": Color(0.16, 0.11, 0.03, 0.94),
		"border": Color(0.85, 0.62, 0.15),
		"border_w": 2,
		"text": Color(1, 0.92, 0.60),
		"glyph": true,
	},
}
const STYLE_IDS: Array[String] = ["mac_dinh", "hang", "vo_dich"]

var game: Node = null # Main (set at creation)
var _font: Font = null
var _active := {} # slot -> {text, style, until (msec)}


static func normalize_style(id: String) -> String:
	return id if STYLES.has(id) else "mac_dinh"


## Wrap text to at most 2 lines of ~MAX_W px (longer text is
## cut with "…", per spec).
static func wrap_lines(font: Font, text: String) -> Array:
	var words := text.split(" ", false)
	var lines: Array = []
	var cur := ""
	for w in words:
		var cand := w if cur == "" else cur + " " + w
		if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= MAX_W - 16.0 or cur == "":
			cur = cand
		else:
			lines.append(cur)
			cur = w
			if lines.size() == 2:
				break
	if lines.size() < 2 and cur != "":
		lines.append(cur)
	if lines.size() == 2:
		# More words remained than fit: mark the cut.
		var joined := " ".join(words)
		var shown := String(lines[0]) + " " + String(lines[1])
		if joined.length() > shown.length():
			var l2 := String(lines[1])
			while l2.length() > 1 and font.get_string_size(l2 + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > MAX_W - 16.0:
				l2 = l2.substr(0, l2.length() - 1)
			lines[1] = l2 + "…"
	return lines


static func bubble_size(font: Font, lines: Array) -> Vector2:
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var lh := font.get_height(FONT_SIZE)
	return Vector2(w + 16.0, lines.size() * lh + 10.0)


## Paint one bubble centred at `center` (its box centre);
## used by this layer and by the settings preview control.
static func paint(ci: CanvasItem, font: Font, center: Vector2, text: String, style_id: String) -> void:
	var st: Dictionary = STYLES[normalize_style(style_id)]
	var lines := wrap_lines(font, text)
	if lines.is_empty():
		return
	var sz := bubble_size(font, lines)
	var rect := Rect2(center - sz * 0.5, sz)
	ci.draw_rect(rect, st["bg"])
	ci.draw_rect(rect, st["border"], false, float(st.get("border_w", 1)))
	# Tail: a small triangle under the box, pointing down.
	var tail := PackedVector2Array([
		center + Vector2(-5, sz.y * 0.5),
		center + Vector2(5, sz.y * 0.5),
		center + Vector2(0, sz.y * 0.5 + 7),
	])
	ci.draw_colored_polygon(tail, st["bg"])
	ci.draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), st["border"], 1.0)
	if bool(st.get("glyph", false)):
		# Champion style: a small shield glyph at the top-left
		# corner (spec §7.2B) — plain polygon, no emoji.
		var c := rect.position + Vector2(7, 7)
		var shield := PackedVector2Array([
			c + Vector2(-3.5, -4), c + Vector2(3.5, -4), c + Vector2(3.5, 1),
			c + Vector2(0, 4.5), c + Vector2(-3.5, 1),
		])
		ci.draw_colored_polygon(shield, st["border"])
	var lh := font.get_height(FONT_SIZE)
	var y := rect.position.y + 5.0 + font.get_ascent(FONT_SIZE)
	for l in lines:
		ci.draw_string(font, Vector2(rect.position.x + 8, y), String(l),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, st["text"])
		y += lh


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if _active.is_empty():
		return
	var now := Time.get_ticks_msec()
	var dirty := false
	for slot in _active.keys():
		if now > int(_active[slot]["until"]):
			_active.erase(slot)
			dirty = true
	if dirty or not _active.is_empty():
		queue_redraw()


## Show (or replace) the bubble for a slot. Main calls this
## for every in-match chat line it accepts.
func show_bubble(slot: int, text: String, style_id: String) -> void:
	if text.strip_edges() == "":
		return
	_active[slot] = {
		"text": text, "style": normalize_style(style_id),
		"until": Time.get_ticks_msec() + int(LIFE * 1000.0),
	}
	queue_redraw()


## World anchor for a slot's bubble: the hero's head, else
## the Town Center's top. Null when neither exists.
func _anchor_for(slot: int) -> Variant:
	if game == null:
		return null
	for u in game.units:
		if u != null and is_instance_valid(u) and u.unit_type == "king" \
				and u.owner_id == slot and not u.is_dead():
			return u.global_position + Vector2(0, -u._disp_h - 16)
	if game.has_method("tc_of"):
		var tc = game.tc_of(slot)
		if tc != null and is_instance_valid(tc):
			# TC art is ~1.5x its 3-tile footprint, bottom-
			# anchored: its top sits ~150px above the node's
			# footprint origin (top-left), centred at +48x.
			return tc.global_position + Vector2(48, -150)
	return null


func _draw() -> void:
	if game == null or game.world == null or game.fog == null or _font == null:
		return
	for slot in _active.keys():
		var anchor = _anchor_for(int(slot))
		if anchor == null:
			continue
		# Fog gate: only draw while the anchor cell is in the
		# local viewer's VISIBLE set (teammates reveal
		# themselves through their own vision).
		var cell: Vector2i = game.world.world_to_cell(anchor)
		if not game.fog.is_visible_cell(cell):
			continue
		var entry: Dictionary = _active[slot]
		var sz := bubble_size(_font, wrap_lines(_font, String(entry["text"])))
		paint(self, _font, anchor + Vector2(0, -sz.y * 0.5 - 2),
			String(entry["text"]), String(entry["style"]))
