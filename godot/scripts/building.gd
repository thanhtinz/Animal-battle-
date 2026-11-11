class_name Building
extends Node2D
## A placed building: multi-tile footprint that blocks grid cells.
## States: under construction (progress 0..1) -> complete.
## Town Center can train villagers through a simple queue.

const TRAIN_TIME := 5.0

## Building art (tools/extract_buildings.py, cut from Tín's official
## 4-tier charts): every building type has assets/buildings/<stem>_tN.png.
## The displayed tier follows the match age (age I -> t1; tiers 3-4 wait
## for later ages). SCALE RULE (Tín, 2026-11-08): the art is drawn at
## ART_SCALE x the footprint, anchored at the footprint's bottom-centre
## and overflowing upward — collision / placement / minimap keep using
## the footprint (AoE style). Draw order is y-sorted against units via
## z_index bands: a building sorts by its footprint's bottom row, a unit
## by its feet row, so units north of a building are covered by its roof
## and units south of it draw in front of its base.
const ART_SCALE := 1.5
const TIER_STEMS := {
	"town_center": "towncenter",
	"house": "house",
	"barracks": "barracks",
	"mining_camp": "miningcamp",
	"tower": "tower",
	"blacksmith": "blacksmith",
	"lumber_camp": "lumbercamp",
	"storage": "storage",
	"market": "market",
	"dock": "dock",
	"farm": "farm",
	"castle": "castle",
}
## Wall / gate segments (self-drawn pass): single-tile buildings whose
## art is NOT tiered — the material IS the look (wood for Ages I-II,
## stone for Age III). Each type has a straight + a corner variant,
## chosen from wall neighbours (Main.refresh_wall_variants).
const WALL_STEMS := {
	"wallwood": ["wallwood", "wallwood_corner"],
	"wallstone": ["wallstone", "wallstone_corner"],
	"gatewood": ["gatewood", "gatewood"],
	"gatestone": ["gatestone", "gatestone"],
	# 14c: Thạch Sơn's temporary Nham Tường (skill-raised, expires).
	"skillwall": ["skillwall", "skillwall_corner"],
}


static func is_wall_type(btype: String) -> bool:
	return WALL_STEMS.has(btype)


static func wall_texture(btype: String, variant: String) -> Texture2D:
	var stems: Array = WALL_STEMS.get(btype, [])
	if stems.is_empty():
		return null
	var stem: String = stems[1] if variant == "corner" else stems[0]
	var cache_key := "w:" + stem
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key]
	var tex: Texture2D = null
	var path := "res://assets/buildings/" + stem + ".png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[cache_key] = tex
	return tex
## Kept for compatibility with older references.
const BARRACKS_TEX_PATH := "res://assets/buildings/barracks_t1.png"

static var _tex_cache := {} # "stem_tN" -> Texture2D (or null)

## Building types whose art carries a flag/banner on a pole at the
## very top (13o animation pass): their art sprite gets the
## flag_wave shader so the baked flag ripples in the wind instead
## of standing frozen. The Watch Tower's lantern and the Market's
## awning are baked mid-art with no separable element — they stay
## as painted (see KE-HOACH 13o).
const FLAG_TYPES := ["town_center", "castle", "barracks"]
static var _flag_shader: Shader = null


## Faction-coloured variants (tools/recolor_teams.py) exist for
## these stems — their art carries the slot colour (flags, banners,
## red roofs). Other buildings share one art for every slot.
const COLORED_STEMS := ["towncenter", "barracks", "house", "tower"]
## Back-compat alias (older references).
const ENEMY_STEMS := COLORED_STEMS


## `owner` is the owning PLAYER SLOT (team colours key off the
## slot, not the faction team — see TeamColors).
static func tier_texture(btype: String, tier: int, owner: int = 0) -> Texture2D:
	if WALL_STEMS.has(btype):
		return wall_texture(btype, "straight")
	var stem: String = TIER_STEMS.get(btype, "")
	if stem == "":
		return null
	var key := stem + "_t" + str(clampi(tier, 1, 4))
	var cache_key := "c" + str(TeamColors.slot_of(owner)) + ":" + key
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key]
	var tex: Texture2D = null
	if owner != 0 and COLORED_STEMS.has(stem):
		var epath := TeamColors.building_path(owner, key)
		if ResourceLoader.exists(epath):
			tex = load(epath)
	if tex == null:
		var path := "res://assets/buildings/" + key + ".png"
		if ResourceLoader.exists(path):
			tex = load(path)
	_tex_cache[cache_key] = tex
	return tex


## Rect (building-local coords) the tier art occupies for a footprint of
## `size` tiles: ART_SCALE x the footprint wide, texture aspect kept,
## bottom edge flush with the footprint bottom, horizontally centred.
static func art_rect(size: Vector2i, tex: Texture2D) -> Rect2:
	var fp := Vector2(size) * World.TILE
	if tex == null:
		return Rect2(Vector2.ZERO, fp)
	var disp_w := fp.x * ART_SCALE
	var disp_h := disp_w * float(tex.get_height()) / float(tex.get_width())
	return Rect2(Vector2(fp.x * 0.5 - disp_w * 0.5, fp.y - disp_h),
			Vector2(disp_w, disp_h))


var btype: String = "town_center"
var display_name: String = "Town Center"
var team: int = 0
var owner_id: int = 0 # player slot owning this building (P4 MP; == team in SP)
var last_hit_owner: int = -1 # 13y: slot that most recently damaged this building (razed credit)
var net_id: int = 0 # stable id for lockstep commands (P4 MP)
var origin_cell: Vector2i = Vector2i.ZERO # top-left cell
var size: Vector2i = Vector2i(3, 3)
var complete: bool = false
var progress: float = 0.0
var build_time: float = 1.0
var pop_bonus: int = 0
var tier: int = 1 # art tier shown (follows the match age)

var game = null # Main (duck-typed)
var world = null # World (duck-typed)

var train_queue: int = 0 # count (train_types holds the actual unit kinds)
var train_types: Array = [] # Array[String], FIFO — "villager" | "militia" | "archer"
var train_timer: float = 0.0

# --- P3 combat -------------------------------------------------------------
var hp: float = 500.0
var max_hp: float = 500.0
var destroyed: bool = false
var fire_cd: float = 0.0 # watch-tower shot cooldown (driven by Main)

var wall_variant: String = "straight" # "straight" | "corner" (wall types)

var _label: Label
var art_sprite: Sprite2D = null # tier art; null only if the texture is missing


## The texture this building currently shows: wall/gate pieces use
## their adjacency variant; everything else uses the tier art.
func current_texture() -> Texture2D:
	if WALL_STEMS.has(btype):
		return wall_texture(btype, wall_variant)
	return tier_texture(btype, tier, owner_id)


## Re-point the sprite after the wall variant changed (a neighbour
## wall was placed or destroyed).
func refresh_wall_art() -> void:
	if not WALL_STEMS.has(btype) or art_sprite == null:
		return
	var tex := current_texture()
	if tex == null:
		return
	var r := art_rect(size, tex)
	art_sprite.texture = tex
	art_sprite.position = r.get_center()
	art_sprite.scale = r.size / Vector2(tex.get_size())


func _ready() -> void:
	# Y-sort band shared with Unit: sort by the footprint's bottom row.
	z_index = 10 + origin_cell.y + size.y
	max_hp = Stats.building_hp(btype)
	hp = max_hp
	var tex := current_texture()
	if tex != null:
		var r := art_rect(size, tex)
		art_sprite = Sprite2D.new()
		art_sprite.texture = tex
		art_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art_sprite.centered = true
		art_sprite.position = r.get_center()
		art_sprite.scale = r.size / Vector2(tex.get_size())
		art_sprite.visible = complete # revealed when construction finishes
		add_child(art_sprite)
		if FLAG_TYPES.has(btype):
			# Wind in the baked flag (13o): per-building material so
			# each flag ripples on its own phase (cell-hash offset).
			if _flag_shader == null:
				_flag_shader = load("res://shaders/flag_wave.gdshader")
			if _flag_shader != null:
				var mat := ShaderMaterial.new()
				mat.shader = _flag_shader
				mat.set_shader_parameter("phase",
						float(absi(origin_cell.x * 31 + origin_cell.y * 57) % 628) / 100.0)
				art_sprite.material = mat
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 12)
	# Name label wears the owner's slot colour (lightened for
	# legibility against the dark shadow) — Tín's team-color rule.
	_label.add_theme_color_override("font_color",
			TeamColors.ui_color(owner_id).lightened(0.55))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	# Label sits at the TOP of the drawn (scaled) art, clear of the roof.
	var label_top := size.y * World.TILE * 0.5 - 9.0
	if tex != null:
		label_top = art_rect(size, tex).position.y - 20.0
	_label.position = Vector2(0, label_top)
	_label.size = Vector2(size.x * World.TILE, 18)
	_label.text = display_name
	# Wall/gate segments are 1-tile: a name label per segment smears
	# into an unreadable band along the wall, so segments go unlabelled.
	_label.visible = not WALL_STEMS.has(btype)
	add_child(_label)


## Local-space rect the tier art is drawn into (footprint rect if no art).
func art_display_rect() -> Rect2:
	return art_rect(size, current_texture())


## Age-up art swap: point the sprite (and the label) at the new tier's
## texture, recomputing scale/position from its aspect.
func set_tier(n: int) -> void:
	tier = n
	if WALL_STEMS.has(btype):
		return # wall material does not change with age
	var tex := tier_texture(btype, tier, owner_id)
	if tex == null:
		return
	var r := art_rect(size, tex)
	if art_sprite != null:
		art_sprite.texture = tex
		art_sprite.position = r.get_center()
		art_sprite.scale = r.size / Vector2(tex.get_size())
	if _label != null:
		_label.position.y = r.position.y - 20.0
	queue_redraw()


## World-space point attackers aim at (upper-middle of the art).
func aim_point() -> Vector2:
	var r := art_display_rect()
	return position + Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.35)


func take_damage(amount: float, _attacker = null) -> void:
	if destroyed:
		return
	# 13y: remember the most recent enemy hitter so Main can
	# credit the raze when the building falls (presentation-layer
	# match statistics only — never sim/checksum state).
	if (_attacker is Unit or _attacker is Ship) \
			and int(_attacker.owner_id) != owner_id:
		last_hit_owner = int(_attacker.owner_id)
	# 13v: a building inside an allied Thiên Màn dome takes NO
	# damage at all while the dome stands (Main resolves zones).
	if game != null and game.has_method("building_dome_protected") \
			and game.building_dome_protected(self):
		if game.vfx != null:
			game.vfx.hit_spark(aim_point(), TeamColors.vfx_palette(owner_id))
		return
	hp -= amount
	if game != null and game.vfx != null:
		game.vfx.hit_spark(aim_point(), TeamColors.vfx_palette(owner_id))
	queue_redraw()
	if hp <= 0.0:
		hp = 0.0
		destroyed = true
		if game != null and game.has_method("on_building_destroyed"):
			game.on_building_destroyed(self)


func _bar_y() -> float:
	# Training bar floats above the name label, which itself sits just
	# above the drawn art (label occupies art_top-20 .. art_top-2).
	if art_sprite != null:
		return art_display_rect().position.y - 27.0
	return -10.0


func cells() -> Array:
	return world.footprint_cells(origin_cell, size)


func add_progress(delta: float) -> void:
	if complete:
		return
	progress += delta / build_time
	if progress >= 1.0:
		progress = 1.0
		complete = true
		if art_sprite != null:
			art_sprite.visible = true
		if game != null:
			game.on_building_complete(self)
	queue_redraw()


func start_training(unit_kind: String = "villager") -> void:
	train_queue += 1
	train_types.append(unit_kind)
	if train_queue == 1:
		train_timer = _train_time()


## Seconds for the trainee at the FRONT of this queue: the base
## TRAIN_TIME for ordinary units, Stats.KING_TRAIN_TIME for the
## King, scaled by the owner's Imperial logistics (Age IV: x0.8 —
## Stats.IMPERIAL_TRAIN_TIME_MULT via Main.train_time_mult).
## Applies to TC / Barracks / Dock / Castle alike.
func _train_time() -> float:
	if game != null and game.has_method("train_time_for"):
		var kind: String = train_types[0] if not train_types.is_empty() else "villager"
		return game.train_time_for(owner_id, kind)
	if game != null and game.has_method("train_time_mult"):
		return TRAIN_TIME * game.train_time_mult(owner_id)
	return TRAIN_TIME


func training_fraction() -> float:
	if train_queue <= 0:
		return 0.0
	return 1.0 - train_timer / _train_time()


## Remove the queue entry at `index` (0 = the one training now) and
## return its kind ("" if out of range). Cancelling the front entry
## restarts the timer for the new front at its full train time —
## the caller (Main) refunds the removed kind's cost in full.
func remove_queue_at(index: int) -> String:
	if index < 0 or index >= train_types.size():
		return ""
	var kind: String = train_types[index]
	train_types.remove_at(index)
	train_queue = train_types.size()
	if index == 0:
		train_timer = _train_time() if train_queue > 0 else 0.0
	queue_redraw()
	return kind


func _process(delta: float) -> void:
	if game != null and game.paused:
		return
	# P4 MP: a disconnected player's entities freeze in place.
	if game != null and game.get("mp_mode") == true and game.slot_inert[owner_id]:
		return
	# 13v: inside an enemy Băng Hà blizzard the building is frozen
	# — training pauses (research pauses in Main._update_techs).
	if game != null and game.has_method("building_frozen") \
			and game.building_frozen(self):
		return
	if train_queue > 0 and complete:
		train_timer -= delta
		if train_timer <= 0.0:
			train_queue -= 1
			var kind: String = train_types.pop_front() if not train_types.is_empty() else "villager"
			if game != null:
				game.spawn_unit(self, kind)
			if train_queue > 0:
				train_timer = _train_time()
		queue_redraw()


## Slot-coloured HP bar, drawn only while damaged. `top` is the
## local y of the bar; width follows the footprint.
func _draw_hp_bar(top: float, width: float) -> void:
	if hp >= max_hp or destroyed:
		return
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var bcol := TeamColors.ui_color(owner_id)
	var w := width - 10.0
	draw_rect(Rect2(5, top, w, 5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(5, top, w * frac, 5), bcol)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(size) * World.TILE)
	var wall := Color(0.72, 0.66, 0.55)
	# No-art fallback shapes: the roof wears the owner's slot colour.
	var roof := TeamColors.ui_color(owner_id).darkened(0.35)
	match btype:
		"house":
			wall = Color(0.78, 0.68, 0.5)
			roof = TeamColors.ui_color(owner_id).darkened(0.45)
		"barracks":
			wall = Color(0.5, 0.46, 0.42)
			roof = TeamColors.ui_color(owner_id).darkened(0.5)
	if not complete:
		draw_rect(rect, Color(wall, 0.45))
		draw_rect(rect, Color(0.2, 0.15, 0.1), false, 2.0)
		draw_line(rect.position, rect.position + rect.size, Color(0.2, 0.15, 0.1, 0.6), 2.0)
		draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y),
				Vector2(rect.position.x + rect.size.x, rect.position.y), Color(0.2, 0.15, 0.1, 0.6), 2.0)
		# Build progress bar.
		var bw := rect.size.x - 8.0
		draw_rect(Rect2(4, -10, bw, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(4, -10, bw * progress, 5), Color(0.45, 0.9, 0.4))
		_draw_hp_bar(-18.0, rect.size.x)
		return
	if art_sprite != null:
		# Complete: the tier sprite is the building. Only the training
		# progress bar stays code-drawn.
		_draw_hp_bar(art_display_rect().position.y - 8.0, rect.size.x)
		if train_queue > 0:
			var tbw := rect.size.x - 8.0
			var by := _bar_y()
			draw_rect(Rect2(4, by, tbw, 5), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(4, by, tbw * training_fraction(), 5), Color(0.4, 0.7, 1.0))
		return
	draw_rect(rect, wall)
	draw_rect(Rect2(0, 0, rect.size.x, rect.size.y * 0.32), roof)
	draw_rect(rect, Color(0.25, 0.2, 0.14), false, 2.0)
	# Door.
	draw_rect(Rect2(rect.size.x * 0.5 - 6, rect.size.y - 16, 12, 16), Color(0.3, 0.2, 0.12))
	if train_queue > 0:
		var bw := rect.size.x - 8.0
		draw_rect(Rect2(4, -10, bw, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(4, -10, bw * training_fraction(), 5), Color(0.4, 0.7, 1.0))
