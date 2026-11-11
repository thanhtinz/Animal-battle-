class_name Unit
extends Node2D
## A unit with a small state machine:
## idle | move | to_node -> gather -> return (loop) | to_build -> build
## Movement follows A* cell paths produced by World.
##
## Sprites: one extracted sheet per unit type (tools/extract_sprites2.py):
##   villager -> assets/villager.png  (idle/walk/work/harvest/build/carry/die)
##   militia  -> assets/militia.png   (idle/walk/attack/die/hurt)
##   archer   -> assets/archer.png    (idle/walk/attack/die/hurt)
## Sheet layout: directional anims group frames [down, left, right, up],
## `per_dir` frames each (manifest *_frames.json). The villager's side/up
## idle+walk frames are static poses from its 8-dir sheet (its animation
## sheet only has front cycles); while returning with a load the Carry
## cycle plays instead of Walk.

const CARRY_CAP := 10
const GATHER_TIME := 2.0
const TEND_TIME := 2.0 # seconds of work per farm stage / harvest

const DISPLAY_SCALE := 0.49 # cell 82 tall, character ~72 px -> ~35 px on screen

## Display ruler (scale pass, 2026-11-08): DISPLAY_SCALE was tuned on
## the original trio — the Villager's idle content is 70 sheet px tall,
## so it renders H = 70 * scale world px, and Militia (71 px) /
## Archer (73 px) land inside ±5% at the same scale. The AI-drawn
## sheets arrived with far bigger figures per cell (Cavalry and Ram
## content is 124 sheet px tall, and the Ram was 192 px = ~4 tiles
## long), so the new types carry a per-type scale derived from their
## measured idle content bbox:
##   spearman  body (helmet->feet, spear tip excluded) 79 px -> H/79
##   cavalry   height 124 px -> 1.30*H/124; its side-idle length
##             (118 px) then renders ~42 px ~ 1.3 tiles
##   ram       length 192 px -> ~69 px ~ 2.2 tiles; height renders
##             1.30*H, under the 1.5*H cap
## Second shrink (same day, Tín: "still too big"): the whole ruler
## came down by a uniform factor 0.72 from the first pass (base
## 0.68 -> 0.49) so infantry H = 34.3 world px — about the House
## art's door height (measured ~31 world px in the lineup capture),
## instead of towering over it at 47.6. Relative proportions between
## types are unchanged. One scale per sheet, applied to every frame
## alike — no size popping between directions/animations; the feet
## anchor is untouched.
## Villager exception (same day, Tín: "Nông dân bự hơn lính"): on the
## shared scale the Villager was already the shortest infantry
## (70 px -> 34.3) but its front content is the WIDEST of the foot
## soldiers (50 px -> 24.5, vs the Militia's 47 px -> 23.0) and the
## big hair reads bulkier than the armoured units. The Villager now
## carries its own scale 0.46: height 32.2 world px (inside the
## 0.95*Militia ± 1.5 px band, ~2.6 px under the Militia) AND front
## width 23.0, a hair under the Militia's — so the civilian reads
## unmistakably as the smallest person on the field. Enemy villagers
## share the sheet geometry and inherit the same scale.
const DISPLAY_SCALES := {"villager": 0.46, "spearman": 0.434, "cavalry": 0.36, "ram": 0.36,
	# 15g vehicles (sheets by tools/build_transport_assets.py):
	# cart side length 161 sheet px -> ~64 world px (~2 tiles);
	# wagon 212 px -> ~85 world px (~2.6 tiles), heights land at
	# infantry height / a shade above, like the Ram.
	"cart": 0.40, "wagon": 0.40}
## Idle-frame alpha content per sheet, sheet px (PIL alpha scan):
## [front width, full height, body height, side length]. Body height
## equals full height except the Spearman, whose spear tip adds 5 px.
const CONTENT_SIZE := {
	"villager": [50, 70, 70, 50],
	"militia": [47, 71, 71, 45],
	"archer": [52, 73, 73, 47],
	"spearman": [59, 84, 79, 60],
	"cavalry": [53, 124, 124, 118],
	"ram": [192, 124, 124, 192],
	# 15g: measured from the generated sheets (alpha bbox of the
	# front idle frame / full height / side length).
	"cart": [98, 96, 96, 161],
	"wagon": [120, 103, 103, 212],
}


static func display_scale_for(unit_type: String) -> float:
	return float(DISPLAY_SCALES.get(unit_type, DISPLAY_SCALE))


## Rendered (world px) body height of a type's idle figure: the front
## content width is index 0, body height index 2 of CONTENT_SIZE.
static func rendered_body_height(unit_type: String) -> float:
	var c: Array = CONTENT_SIZE.get(unit_type, CONTENT_SIZE["villager"])
	return float(c[2]) * display_scale_for(unit_type)


## Rendered (world px) front content width of a type's idle figure:
## index 0 of CONTENT_SIZE, same scale path as the heights.
static func rendered_front_width(unit_type: String) -> float:
	var c: Array = CONTENT_SIZE.get(unit_type, CONTENT_SIZE["villager"])
	return float(c[0]) * display_scale_for(unit_type)


static func rendered_full_height(unit_type: String) -> float:
	var c: Array = CONTENT_SIZE.get(unit_type, CONTENT_SIZE["villager"])
	return float(c[1]) * display_scale_for(unit_type)


static func rendered_side_length(unit_type: String) -> float:
	var c: Array = CONTENT_SIZE.get(unit_type, CONTENT_SIZE["villager"])
	return float(c[3]) * display_scale_for(unit_type)
const SHEET_DEFS := {
	"villager": ["res://assets/villager.png", "res://assets/villager_frames.json"],
	"militia": ["res://assets/militia.png", "res://assets/militia_frames.json"],
	"archer": ["res://assets/archer.png", "res://assets/archer_frames.json"],
	"spearman": ["res://assets/spearman.png", "res://assets/spearman_frames.json"],
	"cavalry": ["res://assets/cavalry.png", "res://assets/cavalry_frames.json"],
	"ram": ["res://assets/ram.png", "res://assets/ram_frames.json"],
	"cart": ["res://assets/cart.png", "res://assets/cart_frames.json"],
	"wagon": ["res://assets/wagon.png", "res://assets/wagon_frames.json"],
}
## Per-SLOT coloured sheets (tools/recolor_teams.py, generalising
## the old recolor_enemy.py): SAME base sprites for every faction —
## only the red hue band is rotated to the slot's team colour
## (TeamColors). The lookup key is the OWNER SLOT, not the faction
## team: slots 0/1/2/3 render red/blue/green/yellow even when two
## slots share a team (2v2). SP keeps owner == team, so the player
## is red and the AI blue exactly as before.

static var _sheets := {} # "slot:unit_type" -> {tex, cell, baseline, anims, work_loop} or {}


static func get_sheet(unit_type: String, owner: int = 0) -> Dictionary:
	var cache_key := str(owner) + ":" + unit_type
	if _sheets.has(cache_key):
		return _sheets[cache_key]
	var data: Dictionary = {}
	var def: Array = SHEET_DEFS.get(unit_type, SHEET_DEFS["villager"])
	if owner != 0 and SHEET_DEFS.has(unit_type):
		var edef: Array = TeamColors.unit_sheet(owner, unit_type)
		if ResourceLoader.exists(edef[0]) and FileAccess.file_exists(edef[1]):
			def = edef
	if ResourceLoader.exists(def[0]) and FileAccess.file_exists(def[1]):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(def[1]))
		if typeof(parsed) == TYPE_DICTIONARY:
			data = {
				"tex": load(def[0]),
				"cell": Vector2i(int(parsed.get("cell_w", 82)), int(parsed.get("cell_h", 82))),
				"baseline": int(parsed.get("baseline", 78)),
				"anims": parsed.get("animations", {}),
				"work_loop": parsed.get("work_loop", []),
			}
	_sheets[cache_key] = data
	return data


var _data: Dictionary = {}
var disp_scale: float = DISPLAY_SCALE # per-type display scale (see ruler above)
var _disp_h: float = 34.3 # rendered full content height, world px
var _disp_side_w: float = 34.0 # rendered side content length, world px
var spr: Sprite2D = null
var _atlas: AtlasTexture = null
var facing: String = "down"
var anim_name: String = ""
var _anim_t := 0.0
var _anim_key := ""
var _cur_region := Rect2i(-1, -1, 0, 0)

# --- 13o presentation life (never sim state, never checksummed) ----
## The military sheets all ship a "hurt" row that no state ever
## selected, the Spearman/Cavalry/Ram idle rows are a single frame
## per direction, and the Ram's whole sheet is ONE image repeated
## (pixel-verified) — so those units stood frozen like statues.
## take_damage arms _hurt_t; _update_sprite plays the hurt row
## while it runs and _life_tick adds the white flash, idle
## breathing, the cavalry gait bob and the Ram's rock + ram-thrust.
const HURT_TIME := 0.28
var _hurt_t := 0.0
var _flash_on := false
var _life_t := 0.0
var _gait := 0.0 # walk-phase accumulator for cavalry / ram motion
var _phase := 0.0 # per-unit phase offset so crowds don't sync up
var _base_spr_pos := Vector2.ZERO
var _base_modulate := Color.WHITE


func sheet_anim_count(anim: String) -> int:
	var anims: Dictionary = _data.get("anims", {})
	if anims.has(anim):
		return int(anims[anim].get("count", 0))
	return 0


## Y-sort band shared with Building: a unit sorts by its feet row, a
## building by its footprint's bottom row — so a unit north of a
## building is covered by the (overflowing) roof and a unit south of
## it draws in front of the building's base.
func _update_z() -> void:
	z_index = 10 + int(global_position.y / World.TILE)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # smooth shadow gradient in _draw
	_update_z()
	# Combat stats come from the single Stats table (P3).
	max_hp = Stats.unit_stat(unit_type, "hp")
	# Nobility (Castle tech, GDD section 6): cavalry mustered
	# after the research are tougher (spawn-time HP).
	if unit_type == "cavalry" and game != null and game.has_method("tech_cav_hp"):
		max_hp += game.tech_cav_hp(owner_id)
	hp = max_hp
	speed = Stats.unit_stat(unit_type, "speed")
	# Biome movement modifier (Biomes table via Main): soft sand /
	# deep snow slow everyone; cavalry stacks its own extra.
	if game != null and game.has_method("move_mult_for"):
		speed *= game.move_mult_for(unit_type)
	# Wheel (Market tech, GDD section 3.3): villagers move faster.
	if unit_type == "villager" and game.has_method("tech_villager_speed_mult"):
		speed *= game.tech_villager_speed_mult(owner_id)
	# Aristocracy (Castle tech, GDD section 6): spearmen faster.
	if unit_type == "spearman" and game != null \
			and game.has_method("tech_spearman_speed_mult"):
		speed *= game.tech_spearman_speed_mult(owner_id)
	guard_pos = global_position
	if unit_type == "king":
		# The hero renders from single-pose character art (Characters),
		# not an animation sheet — see the king block below.
		_setup_king_sprite()
		return
	_data = get_sheet(unit_type, owner_id)
	if _data.is_empty():
		return # fallback: _draw() renders the old placeholder circles
	_atlas = AtlasTexture.new()
	_atlas.atlas = _data.tex
	spr = Sprite2D.new()
	spr.texture = _atlas
	spr.centered = false
	# Painted art with smooth-matted edges: linear + mipmaps so the
	# fractional DISPLAY_SCALE (and camera zooms) sample smoothly
	# instead of chunking into nearest-neighbour steps.
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	disp_scale = display_scale_for(unit_type)
	_disp_h = rendered_full_height(unit_type)
	_disp_side_w = rendered_side_length(unit_type)
	spr.scale = Vector2.ONE * disp_scale
	var cell: Vector2i = _data.cell
	# Feet land exactly on the unit origin (its ground point).
	spr.position = Vector2(-cell.x * disp_scale * 0.5, -int(_data.baseline) * disp_scale)
	if owner_id != 0 and (_data.tex == null or String(_data.tex.resource_path)
			!= TeamColors.unit_sheet(owner_id, unit_type)[0]):
		# Fallback tint if this slot's coloured sheet is missing.
		spr.modulate = Color(1, 1, 1).lerp(TeamColors.ui_color(owner_id), 0.55)
	add_child(spr)
	# 13o: rest pose for the procedural life layer (_life_tick).
	_base_spr_pos = spr.position
	_base_modulate = spr.modulate
	_phase = float(absi(net_id * 37 + unit_type.length() * 11) % 628) / 100.0
	_update_sprite(0.0)


func _set_frame(anim: String, idx: int) -> void:
	var anims: Dictionary = _data.get("anims", {})
	if not anims.has(anim):
		return
	var cell: Vector2i = _data.cell
	var row: int = int(anims[anim].get("row", 0))
	var region := Rect2i(idx * cell.x, row * cell.y, cell.x, cell.y)
	if region != _cur_region:
		_cur_region = region
		_atlas.region = region


func _target_is_left() -> bool:
	if state == "gather" and target_node != null and is_instance_valid(target_node):
		return target_node.global_position.x < global_position.x
	if state == "build" and target_site != null:
		var centre: Vector2 = target_site.position + Vector2(target_site.size) * (World.TILE * 0.5)
		return centre.x < global_position.x
	if (state == "attack" or state == "to_attack") and attack_target != null and is_instance_valid(attack_target):
		return aim_pos_of(attack_target).x < global_position.x
	return false


func _update_sprite(delta: float) -> void:
	if spr == null:
		return
	var anims: Dictionary = _data.get("anims", {})
	var anim := "idle"
	var fps := 4.0
	match state:
		"move", "to_node", "return", "to_build", "to_attack", "to_field", "flee", "trade_out", "trade_back":
			if state == "return" and carry_amount > 0 and anims.has("carry"):
				anim = "carry"
			else:
				anim = "walk"
			fps = 8.0
		"tend":
			anim = "work" if anims.has("work") else "idle"
			fps = 6.0
		"attack":
			anim = "attack" if anims.has("attack") else "work"
			fps = 7.0
		"dead":
			anim = "die" if anims.has("die") else "idle"
			fps = 6.0
		"gather":
			if target_node != null and is_instance_valid(target_node) \
					and target_node.rtype == "food" and anims.has("harvest"):
				anim = "harvest"
			elif anims.has("work"):
				anim = "work"
			fps = 6.0
		"build":
			anim = "build" if anims.has("build") else "work"
			fps = 6.0
	# 13o: the hurt row finally plays — a short flinch whenever a
	# hit landed recently (take_damage arms _hurt_t). The Villager
	# sheet has no hurt row; villagers get the flash only.
	if _hurt_t > 0.0 and state != "dead" and anims.has("hurt"):
		anim = "hurt"
		fps = 10.0
	if not anims.has(anim):
		anim = "idle"
	var info: Dictionary = anims.get(anim, {})
	var count: int = int(info.get("count", 0))
	var per_dir: int = int(info.get("per_dir", count))
	if count <= 0:
		return
	var key := anim + "|" + (facing if per_dir < count else "")
	if key != _anim_key:
		_anim_key = key
		_anim_t = 0.0
	_anim_t += delta * fps
	if per_dir < count:
		# Directional cycle: frames grouped [down, left, right, up].
		var base := 0
		match facing:
			"down":
				base = 0
			"left":
				base = per_dir
			"right":
				base = per_dir * 2
			"up":
				base = per_dir * 3
		anim_name = anim + "_" + facing
		# The ram ships as a single side view (see README): its sheet
		# repeats one right-facing figure in every slot, so horizontal
		# travel flips it; up/down keep the side view.
		spr.flip_h = unit_type == "ram" and facing == "left"
		if anim == "die":
			_set_frame(anim, base + mini(int(_anim_t), per_dir - 1)) # death plays once, holds last frame
		else:
			_set_frame(anim, base + int(_anim_t) % per_dir)
	else:
		anim_name = anim
		var idx: int
		if anim == "work" and not (_data.get("work_loop", []) as Array).is_empty():
			var loop: Array = _data.work_loop
			idx = int(loop[int(_anim_t) % loop.size()])
		elif anim == "die":
			idx = mini(int(_anim_t), count - 1)
		else:
			idx = int(_anim_t) % count
		if anim == "carry":
			spr.flip_h = facing == "left" # Carry frames face right
		elif state == "gather" or state == "build" or state == "attack":
			spr.flip_h = _target_is_left() # work-style frames face right
		else:
			spr.flip_h = false
		_set_frame(anim, idx)

## 13o procedural life for sheet units (presentation only): hurt
## flash, idle breathing, cavalry gait bob, and the Ram's motion —
## its sheet is a single repeated image, so ALL of its movement
## life comes from here: a speed-synced rock while rolling and a
## pull-back/thrust cycle while it is battering a target.
func _life_tick(delta: float) -> void:
	if spr == null:
		return
	_life_t += delta
	# Hurt flash: rgb only — the death branch owns modulate.a.
	if _hurt_t > 0.0 or _flash_on:
		var b := 1.0
		if _hurt_t > 0.0:
			b = 1.0 + clampf(_hurt_t / HURT_TIME, 0.0, 1.0) * 1.1
		spr.modulate = Color(_base_modulate.r * b, _base_modulate.g * b,
				_base_modulate.b * b, spr.modulate.a)
		_flash_on = _hurt_t > 0.0
	var off := Vector2.ZERO
	var rot := 0.0
	var squash := 1.0
	if state != "dead":
		var moving := state in ["move", "to_node", "return", "to_build",
				"to_field", "flee", "to_attack", "trade_out", "trade_back"]
		if state == "idle":
			if unit_type != "ram":
				# Breathing: a slow ±0.7 px rise with a matching
				# squash, phase-offset per unit so crowds don't sync.
				var br := sin(_life_t * 2.1 + _phase)
				off.y = br * 0.7
				squash = 1.0 + br * 0.010
		elif unit_type == "cavalry" and moving:
			_gait += delta * speed * 0.11
			off.y = -absf(sin(_gait)) * 1.3
		elif unit_type == "ram" or unit_type == "cart" or unit_type == "wagon":
			if moving:
				_gait += delta * speed * 0.09
				off.y = -absf(sin(_gait)) * 0.8
				rot = sin(_gait) * 0.018
			elif state == "attack":
				# Wind back, thrust, recover — a 1.5 s cycle.
				var ph := fmod(_life_t + _phase, 1.5) / 1.5
				var thrust := 0.0
				if ph < 0.55:
					thrust = -3.0 * (ph / 0.55)
				elif ph < 0.72:
					thrust = lerpf(-3.0, 6.0, (ph - 0.55) / 0.17)
				else:
					thrust = lerpf(6.0, 0.0, (ph - 0.72) / 0.28)
				var dv := Vector2.RIGHT
				match facing:
					"left":
						dv = Vector2.LEFT
					"up":
						dv = Vector2.UP
					"down":
						dv = Vector2.DOWN
				off += dv * thrust
	spr.position = _base_spr_pos + off
	spr.rotation = rot
	spr.scale = Vector2(disp_scale, disp_scale * squash)


static var _shadow_tex: Texture2D = null


## Soft radial-gradient ellipse used as the ground shadow. The sheets'
## baked contact shadow was cut away with the source page's other
## baked-in effects (tools/recut_smooth.py), so units draw this
## instead to stay grounded.
static func get_shadow_tex() -> Texture2D:
	if _shadow_tex != null:
		return _shadow_tex
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(64):
			var dx := (float(x) - 31.5) / 31.5
			var dy := (float(y) - 15.5) / 15.5
			var q: float = clampf(1.0 - (dx * dx + dy * dy), 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, q * q * (3.0 - 2.0 * q)))
	_shadow_tex = ImageTexture.create_from_image(img)
	return _shadow_tex


var team: int = 0
var owner_id: int = 0 # player slot owning this unit (P4 MP; == team in SP)
var net_id: int = 0 # stable id for lockstep commands (P4 MP)
var unit_type: String = "villager"
var speed: float = 95.0
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()

var game = null # Main (duck-typed)
var world = null # World (duck-typed)

var state: String = "idle"
var path: Array = [] # Array[Vector2] world points
var path_cells: Array = [] # Array[Vector2i] of the current order (kept for inspection/tests)

var target_node: ResourceNode = null
var target_field = null # FieldPlot being tended (duck-typed)
var tend_timer: float = 0.0
var target_site = null # Building under construction
var carry_type: String = ""
var carry_amount: int = 0
## True while the load came from a farm field (deposit then uses the
## biome's field_yield instead of the node/bush yield for food).
var carry_from_field: bool = false
var gather_timer: float = 0.0
var fx_timer: float = 0.0 # construction-dust cadence while in "build" state

# --- P3 combat -------------------------------------------------------------
var hp: float = 50.0
var killed_by = null # 13y: attacker object of the killing blow (match-stats credit)
var max_hp: float = 50.0
var attack_target = null # Unit or Building (duck-typed), hostile team
var guard_pos: Vector2 = Vector2.ZERO # leash anchor for auto-engage
var _atk_cd: float = 0.0
var _repath_t: float = 0.0
var _scan_t: float = 0.0
var _death_t: float = 0.0

# --- Villager fleeing ------------------------------------------------------
## A hurt villager (never military, never while under a fresh player
## attack order) drops its task, runs to its nearest drop-off and
## garrisons inside: invisible + untargetable until the coast is
## clear or the stay cap runs out, then it pops out and stays IDLE
## (no auto-resume — the match-start flow doc forbids automatic
## villager control; the player re-orders it). All triggers are
## damage events inside the sim, so MP lockstep stays deterministic.
var garrisoned: bool = false
var flee_haven = null # Building (duck-typed) fled to / hidden inside
var flee_resume: Dictionary = {} # legacy slot, always empty: tasks are NOT resumed after fleeing (flow doc)
var flee_timer: float = 0.0 # garrison stay countdown
var no_flee_timer: float = 0.0 # attack-order grace against fleeing
var _flee_scan_t: float = 0.0

# --- 15g land transport (SIM state — set only through Main's
# order pipeline / snapshot restore, ticked with the sim, carried
# by snapshots and mixed into the checksum via Main) --------------
## Trade cart: runs a persistent route between the owner's home
## Market and a target Market. `trade_leg` 1 = outbound (empty),
## 2 = returning (loaded — the payout lands when this leg ends at
## the home Market, and only if the cart actually reached the
## target: `trade_loaded`). `trade_gold` is locked in when the
## route is assigned (Main.trade_gold_for — distance-scaled).
var trade_home = null # Building (duck-typed)
var trade_target = null # Building (duck-typed)
var trade_leg: int = 0
var trade_loaded: bool = false
var trade_gold: int = 0
var _trade_retry_t: float = 0.0
## Troop wagon: boarded foot units ride in `cargo` — out of
## game.units entirely (hidden, frozen, untargetable), exactly
## the Transport Ship's rule; they die if the wagon dies.
const WAGON_CAP := 5
var cargo: Array = [] # Array[Unit] (wagon only)
var unload_cell := Vector2i(-1, -1) # wagon: pending unload target


func is_military() -> bool:
	return unit_type in ["militia", "archer", "spearman", "cavalry", "ram", "king"]


func is_dead() -> bool:
	return state == "dead"


## Attackers may only pick targetable units: a garrisoned (fled)
## villager is inside a building and cannot be hit or chased.
func is_targetable() -> bool:
	return state != "dead" and not garrisoned


func attack_range() -> float:
	var r := Stats.unit_stat(unit_type, "range")
	# 14c: Phong Linh is a RANGED hero — her basic attack is a bow
	# shot at archer-like range (see strike()).
	if unit_type == "king" and hero_char() == "phong_linh":
		return float(Stats.HERO_KITS["phong_linh"]["bow_range_tiles"]) * World.TILE
	# Ballistics (Castle tech, GDD sections 5–6): archers shoot
	# further (towers/castles get the same bonus in Main's loop).
	if unit_type == "archer" and game != null \
			and game.has_method("tech_range_bonus"):
		r += game.tech_range_bonus(owner_id)
	return r


func sight_px() -> float:
	return Stats.unit_stat(unit_type, "sight") * World.TILE


## World position used to aim at / measure range to an entity.
func aim_pos_of(t) -> Vector2:
	if t is Building:
		return t.position + Vector2(t.size) * World.TILE * 0.5
	return t.global_position


## Distance from this unit to an entity: centre distance for units,
## distance to the footprint rect for buildings.
func dist_to_entity(t) -> float:
	if t is Building:
		var rect := Rect2(t.position, Vector2(t.size) * World.TILE)
		var cx := clampf(global_position.x, rect.position.x, rect.position.x + rect.size.x)
		var cy := clampf(global_position.y, rect.position.y, rect.position.y + rect.size.y)
		return global_position.distance_to(Vector2(cx, cy))
	return global_position.distance_to(t.global_position)


func in_attack_range(t) -> bool:
	return t != null and is_instance_valid(t) and dist_to_entity(t) <= attack_range() + 4.0


func cell() -> Vector2i:
	return world.world_to_cell(global_position)


func _process(delta: float) -> void:
	if game != null and game.paused:
		return
	# P4 MP: a disconnected player's units freeze (death still plays out).
	if game != null and game.get("mp_mode") == true and game.slot_inert[owner_id] \
			and state != "dead":
		return
	_update_z()
	if hp < max_hp:
		queue_redraw() # keep the HP bar live while damaged
	if selected and unit_type == "cart":
		queue_redraw() # 15g: the route line follows the cart
	if no_flee_timer > 0.0:
		no_flee_timer -= delta
	_tick_effects(delta)
	# 13v hard control (stun / freeze): the state machine idles —
	# no movement, work or combat — while effect timers keep
	# ticking above and the render tail below still runs.
	match state if state == "dead" or not control_locked() else "__locked__":
		"move", "to_node", "return", "to_build", "to_field", "flee":
			_follow_path(delta)
		"trade_out", "trade_back":
			_trade_tick(delta)
		"garrison":
			_garrison_tick(delta)
		"tend":
			if target_field == null or not is_instance_valid(target_field):
				target_field = null
				state = "idle"
			else:
				tend_timer -= delta
				if tend_timer <= 0.0:
					tend_timer = _tend_interval()
					_tend_tick()
		"to_attack":
			_combat_tick(delta, true)
		"attack":
			_combat_tick(delta, false)
		"dead":
			_death_t -= delta
			if unit_type == "king":
				# The hero's fall: tip sideways + sink while fading.
				# The rig root carries the parts, so a rigged hero
				# topples as one articulated figure.
				var prog := clampf(1.0 - _death_t / 1.5, 0.0, 1.0)
				if _rig_active and _hero_root != null:
					_hero_root.rotation = _king_fall_dir * prog * 1.35
					_hero_root.position = Vector2(0, prog * 5.0)
				elif spr != null:
					spr.rotation = _king_fall_dir * prog * 1.35
					spr.position = _king_base_pos + Vector2(0, prog * 5.0)
			if spr != null and _death_t < 0.5:
				spr.modulate.a = clampf(_death_t / 0.5, 0.0, 1.0)
			if _rig_active and _hero_root != null and _death_t < 0.5:
				_hero_root.modulate.a = clampf(_death_t / 0.5, 0.0, 1.0)
			if _death_t <= 0.0:
				if game != null and game.has_method("on_unit_dead"):
					game.on_unit_dead(self)
				queue_free()
				return
		"idle":
			if is_military():
				_scan_t -= delta
				if _scan_t <= 0.0:
					_scan_t = 0.25
					_auto_engage()
		"gather":
			gather_timer -= delta
			if gather_timer <= 0.0:
				_finish_gather()
		"build":
			if target_site == null or target_site.complete:
				target_site = null
				state = "idle"
			else:
				target_site.add_progress(delta)
				fx_timer -= delta
				if fx_timer <= 0.0:
					fx_timer = 0.45
					if game != null and game.has_method("on_build_effect"):
						game.on_build_effect(target_site, self)
				if target_site.complete:
					target_site = null
					state = "idle"
	if unit_type != "king":
		_life_tick(delta)
	_update_sprite(delta)
	if unit_type != "king" and _hurt_t > 0.0:
		# Decay AFTER the render consumers above have read _hurt_t
		# this frame: with decay-first, one frame delta >= HURT_TIME
		# (heavy suite instances) erased the flash + hurt row before
		# they were ever drawn. Presentation only, same total window.
		_hurt_t -= delta
	if unit_type == "king":
		_king_tick(delta)


func _follow_path(delta: float) -> void:
	if path.is_empty():
		_on_arrive()
		return
	var target: Vector2 = path[0]
	var to := target - global_position
	if to.length() < 5.0:
		path.pop_front()
		if path.is_empty():
			_on_arrive()
		return
	if absf(to.x) > absf(to.y):
		facing = "right" if to.x > 0.0 else "left"
	else:
		facing = "down" if to.y > 0.0 else "up"
	var spd := speed * (Stats.FLEE_SPEED_MULT if state == "flee" else 1.0)
	spd *= eff_speed_mult()
	global_position += to.normalized() * spd * delta


## Movement-speed multiplier from timed skill effects (own buffs
## and debuffs) and from Lam Bào's enemy aura "Hàn Khí" (queried
## live from sim positions — no state of its own to drift).
func eff_speed_mult() -> float:
	if frozen_t > 0.0 or stun_t > 0.0:
		return 0.0
	var m := eff_spd_mult if eff_spd_t > 0.0 else 1.0
	if chill_t > 0.0:
		m *= float(Stats.HERO_SKILL3["lam_bao"]["slow_mult"])
	if game != null and game.has_method("hero_speed_factor"):
		m *= game.hero_speed_factor(self)
	return m


## True while a 13v hard control effect (stun / freeze) locks the
## unit out of its state machine: no moving, gathering, building
## or attacking — timers (including the locks themselves) still
## tick in _tick_effects.
func control_locked() -> bool:
	return stun_t > 0.0 or frozen_t > 0.0


## Hoa Vũ Hồi Sinh cleanse: clears slow-type debuffs and the hard
## freeze. Deliberately does NOT clear stun (a different class of
## control) or the caster-side buffs (mult >= 1 is kept).
func cleanse_effects() -> void:
	if eff_spd_t > 0.0 and eff_spd_mult < 1.0:
		eff_spd_mult = 1.0
		eff_spd_t = 0.0
	if eff_atkspd_t > 0.0 and eff_atkspd_f < 1.0:
		eff_atkspd_f = 1.0
		eff_atkspd_t = 0.0
	frozen_t = 0.0
	chill_t = 0.0


func eff_atkspd_mult() -> float:
	var m := eff_atkspd_f if eff_atkspd_t > 0.0 else 1.0
	# 14c: Lôi Chấn's aura "Lôi Vực" — allies in radius strike
	# faster (the hero never buffs himself, hero_aura_covers
	# excludes him for offensive auras).
	if game != null and game.has_method("hero_aura_covers") \
			and game.hero_aura_covers(self, "loi_chan"):
		m *= float(Stats.HERO_KITS["loi_chan"]["aura_atkspd"])
	return m


## Sim ticking for the timed skill effects + the hero's cooldown
## + Kim Hoa's aura regeneration (all sim state; runs identically
## on every client because it is driven by the same lockstep
## frames). Dead units keep no effects.
func _tick_effects(delta: float) -> void:
	if state == "dead":
		return
	if eff_spd_t > 0.0:
		eff_spd_t -= delta
	if eff_dmg_t > 0.0:
		eff_dmg_t -= delta
	if eff_atkspd_t > 0.0:
		eff_atkspd_t -= delta
	if skill_cd_t > 0.0:
		skill_cd_t -= delta
	if skill2_cd_t > 0.0:
		skill2_cd_t -= delta
	if skill3_cd_t > 0.0:
		skill3_cd_t -= delta
	if stun_t > 0.0:
		stun_t -= delta
	if frozen_t > 0.0:
		frozen_t -= delta
	if atk_down_t > 0.0:
		atk_down_t -= delta
		if atk_down_t <= 0.0:
			atk_down_mult = 1.0
	if immune_t > 0.0:
		immune_t -= delta
	if chill_t > 0.0:
		chill_t -= delta
	# 14c: Xích Diệm burn — fixed 0.5 s ticks, damage flagged as
	# DoT so it cannot re-apply the aura burn to itself.
	if burn_ticks > 0:
		burn_acc += delta
		while burn_acc >= 0.5 and burn_ticks > 0:
			burn_acc -= 0.5
			burn_ticks -= 1
			if burn_ticks == 0:
				burn_t = 0.0
			var src: Unit = burn_from if (burn_from != null \
					and is_instance_valid(burn_from)) else null
			take_damage(burn_amt, src, true)
			if state == "dead":
				break
		if burn_ticks == 0:
			burn_t = 0.0
			burn_acc = 0.0
	elif burn_t > 0.0:
		burn_t = maxf(0.0, burn_t - delta)
	# 14c: Hỏa Ấn — the mark detonates on schedule (Main resolves
	# the blast; a dying bearer detonates early in die()).
	if mark_t > 0.0:
		mark_t -= delta
		if mark_t <= 0.0:
			mark_t = 0.0
			if game != null and game.has_method("explode_hero_mark"):
				game.explode_hero_mark(self)
	# Kim Hoa "Sinh Tồn": +1 HP per 2 s while inside her aura.
	if game != null and game.has_method("hero_aura_covers") \
			and game.hero_aura_covers(self, "kim_hoa", true):
		_regen_t += delta
		var kit: Dictionary = Stats.HERO_KITS["kim_hoa"]
		while _regen_t >= float(kit["regen_period"]):
			_regen_t -= float(kit["regen_period"])
			if hp < max_hp:
				hp = minf(max_hp, hp + float(kit["regen_hp"]))
	else:
		_regen_t = 0.0


func _set_path(cells: Array) -> void:
	path_cells = cells.duplicate()
	path = world.cells_to_points(cells)
	# Drop the first point if we are already standing on it.
	if path.size() > 1 and global_position.distance_to(path[0]) < 6.0:
		path.pop_front()


func order_move_cell(dest: Vector2i) -> void:
	target_node = null
	target_field = null
	target_site = null
	attack_target = null
	# 15g: a plain move order takes manual control of a vehicle —
	# a cart's trade route and a wagon's pending unload are both
	# cancelled (order_wagon_unload re-arms its own marker after
	# calling this).
	clear_trade_route()
	unload_cell = Vector2i(-1, -1)
	var cells: Array = world.get_path_cells(cell(), dest, team)
	if cells.is_empty():
		state = "idle"
		return
	_set_path(cells)
	state = "move"


# ------------------------------------------------------------------
# 15g land transport: trade cart + troop wagon
# ------------------------------------------------------------------

## Drop any trade route (manual move order, route broken, cart
## reassigned). The cart keeps nothing: no cargo is banked.
func clear_trade_route() -> void:
	trade_home = null
	trade_target = null
	trade_leg = 0
	trade_loaded = false
	trade_gold = 0


## Begin (or restart) the route Main validated: home Market ->
## target Market, payout locked at `gold`. The first leg starts
## at once from wherever the cart stands.
func set_trade_route(home, target, gold: int) -> void:
	trade_home = home
	trade_target = target
	trade_gold = gold
	trade_loaded = false
	trade_leg = 1
	state = "trade_out"
	_trade_path_to(trade_target)


func _trade_dest():
	return trade_target if trade_leg == 1 else trade_home


func _trade_path_to(b) -> void:
	if b == null or not is_instance_valid(b):
		path.clear()
		path_cells.clear()
		return
	var cells: Array = world.path_to_footprint(cell(), b.cells(), team)
	if cells.is_empty():
		path.clear()
		path_cells.clear()
		return
	_set_path(cells)


## The route is alive while both Markets stand complete and the
## target's owner is still a legal trade partner (Main's rule —
## a diplomacy break maturing mid-route kills the route too).
func _trade_route_alive() -> bool:
	if trade_home == null or trade_target == null:
		return false
	if not is_instance_valid(trade_home) or not is_instance_valid(trade_target):
		return false
	if trade_home.destroyed or trade_target.destroyed:
		return false
	if not trade_home.complete or not trade_target.complete:
		return false
	if game != null and game.has_method("trade_partner_ok"):
		return game.trade_partner_ok(owner_id, trade_target.owner_id)
	return true


func _trade_tick(delta: float) -> void:
	if trade_leg == 1:
		if not _trade_route_alive():
			_trade_abort()
			return
	elif trade_home == null or not is_instance_valid(trade_home) \
			or trade_home.destroyed or not trade_home.complete:
		# The home Market fell mid-return: the route is over
		# wherever the cart stands (goods already aboard are
		# lost with it — no Market, no payout).
		clear_trade_route()
		state = "idle"
		if game != null and game.has_method("notify_route_broken"):
			game.notify_route_broken(self)
		return
	if path.is_empty():
		# Stalled (walled in / just spawned adjacent): retry the
		# leg on a cadence; standing at the destination's edge IS
		# the arrival.
		_trade_retry_t -= delta
		if _trade_retry_t <= 0.0:
			_trade_retry_t = 1.0
			var dest = _trade_dest()
			if dest != null and dist_to_entity(dest) <= 46.0:
				_on_arrive()
			else:
				_trade_path_to(dest)
		return
	_follow_path(delta)


## Route broken (a Market fell, a partner turned enemy): an
## outbound cart turns for home with empty hands; once home (or
## if home itself is gone) it idles and waits for a new route.
## The owner is told once, through Main's presentation gate.
func _trade_abort() -> void:
	if trade_leg == 1 and trade_home != null and is_instance_valid(trade_home) \
			and not trade_home.destroyed and trade_home.complete:
		trade_target = null
		trade_leg = 2
		trade_loaded = false
		state = "trade_back"
		_trade_path_to(trade_home)
		if game != null and game.has_method("notify_route_broken"):
			game.notify_route_broken(self)
		return
	clear_trade_route()
	state = "idle"
	if game != null and game.has_method("notify_route_broken"):
		game.notify_route_broken(self)


## One leg ended at a Market (from _on_arrive / _trade_tick).
func _trade_leg_arrived() -> void:
	if trade_leg == 1:
		# Reached the foreign Market: the goods are aboard.
		trade_loaded = true
		trade_leg = 2
		state = "trade_back"
		_trade_path_to(trade_home)
	else:
		if trade_loaded and trade_gold > 0 and game != null \
				and game.has_method("credit_owner"):
			game.credit_owner(owner_id, "gold", trade_gold)
			if game.has_method("on_trade_completed"):
				game.on_trade_completed(self)
		trade_loaded = false
		if _trade_route_alive():
			trade_leg = 1
			state = "trade_out"
			_trade_path_to(trade_target)
		else:
			# The far Market fell (or turned enemy) while the
			# cart was coming home: the trip paid out, the
			# route does not continue.
			clear_trade_route()
			state = "idle"
			if game != null and game.has_method("notify_route_broken"):
				game.notify_route_broken(self)


## Foot units that may ride the wagon (genre defaults, flagged
## in KE-HOACH): infantry + villagers. Cavalry are mounted, the
## Ram and the vehicles are machines, the hero never rides.
static func wagon_loadable(u) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	return u.unit_type in ["villager", "militia", "archer", "spearman"]


## Wagon: take a foot unit aboard (the Transport Ship's rule —
## the unit leaves game.units: hidden, frozen, untargetable,
## and it dies if the wagon dies). The caller (Main) checks the
## embark range; here we enforce capacity + ownership + class.
func board_unit(u) -> bool:
	if unit_type != "wagon" or state == "dead" or cargo.size() >= WAGON_CAP:
		return false
	if u == null or not is_instance_valid(u) or u == self:
		return false
	if u.owner_id != owner_id or u.is_dead() or u.garrisoned:
		return false
	if not wagon_loadable(u):
		return false
	cargo.append(u)
	u.visible = false
	u.state = "idle"
	u.path.clear()
	u.attack_target = null
	u.target_node = null
	u.target_site = null
	u.clear_trade_route()
	if game != null:
		game.units.erase(u)
		game.selection.erase(u)
		u.selected = false
	return true


## Wagon: put every passenger out on walkable cells around
## `at_cell` (ring search, the ship's pattern). Returns how many
## units disembarked (0 = stayed loaded: no room anywhere).
func unload_all_at(at_cell: Vector2i) -> int:
	if unit_type != "wagon" or cargo.is_empty():
		return 0
	var spots: Array = []
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = at_cell + Vector2i(dx, dy)
				if world.in_bounds(c) and not world.is_solid(c) and not spots.has(c):
					spots.append(c)
		if spots.size() >= cargo.size():
			break
	var n := 0
	for u in cargo:
		if n >= spots.size():
			break
		if u == null or not is_instance_valid(u):
			continue
		u.global_position = world.cell_center(spots[n])
		u.visible = true
		if game != null and not game.units.has(u):
			game.units.append(u)
		u.state = "idle"
		n += 1
	cargo = cargo.slice(n)
	return n


## Wagon order: travel to `dest` and unload everyone on arrival
## (right-click ground with a loaded wagon — the Transport
## Ship's land-click rule). Already there = unload in place.
func order_wagon_unload(dest: Vector2i) -> void:
	if unit_type != "wagon" or cargo.is_empty() or state == "dead":
		return
	if cell() == dest:
		unload_all_at(dest)
		return
	order_move_cell(dest)
	if state == "move":
		unload_cell = dest


func order_gather(node: ResourceNode) -> void:
	target_node = node
	target_field = null
	target_site = null
	attack_target = null
	var cells: Array = world.path_to_footprint(cell(), [node.cell], team)
	if cells.is_empty():
		state = "idle"
		return
	_set_path(cells)
	state = "to_node"


func order_return() -> void:
	# Nearest drop-off for what we carry: Town Center for everything,
	# Mining Camps too for stone/gold (see Main.get_dropoff_for).
	var tc = game.get_dropoff_for(team, carry_type, global_position, owner_id)
	if tc == null:
		state = "idle"
		return
	var cells: Array = world.path_to_footprint(cell(), tc.cells(), team)
	if cells.is_empty():
		_deposit() # already adjacent / unreachable edge: deposit in place
		state = "idle"
		return
	_set_path(cells)
	state = "return"


func order_build(site) -> void:
	target_site = site
	target_node = null
	target_field = null
	attack_target = null
	var cells: Array = world.path_to_footprint(cell(), site.cells(), team)
	if cells.is_empty():
		state = "idle"
		return
	_set_path(cells)
	state = "to_build"


func _on_arrive() -> void:
	match state:
		"move":
			state = "idle"
			guard_pos = global_position # the leash anchor follows move orders
			# 15g: a loaded wagon that was ordered to a point
			# unloads everyone on arrival.
			if unit_type == "wagon" and unload_cell.x >= 0:
				var uc := unload_cell
				unload_cell = Vector2i(-1, -1)
				unload_all_at(uc)
		"trade_out", "trade_back":
			_trade_leg_arrived()
		"flee":
			if flee_haven != null and is_instance_valid(flee_haven) and not flee_haven.destroyed:
				_enter_garrison()
			else:
				flee_haven = null
				state = "idle"
		"to_node":
			if target_node != null and is_instance_valid(target_node) and target_node.amount > 0:
				state = "gather"
				gather_timer = GATHER_TIME
			else:
				_seek_or_idle()
		"return":
			_deposit()
			if target_field != null and is_instance_valid(target_field):
				order_field(target_field)
			elif target_node != null and is_instance_valid(target_node) and target_node.amount > 0:
				order_gather(target_node)
			else:
				_seek_or_idle()
		"to_build":
			state = "build"
		"to_field":
			if target_field != null and is_instance_valid(target_field):
				state = "tend"
				tend_timer = _tend_interval()
				facing = "down"
			else:
				state = "idle"


# ---------------------------------------------------------------- combat

## Send a villager to tend a farm field plot: it walks beside the
## plot, then works it — one growth stage per TEND_TIME tick; at the
## ripe stage a tick becomes a harvest (carry food home, loop back).
func order_field(f) -> void:
	target_field = f
	target_node = null
	target_site = null
	attack_target = null
	var cells: Array = world.path_to_footprint(cell(), [f.cell], team)
	if cells.is_empty():
		state = "idle"
		return
	_set_path(cells)
	state = "to_field"


## Seconds per growth stage here: TEND_TIME divided by the biome's
## field_growth (arid desert / short snow season grow slower).
func _tend_interval() -> float:
	if game != null and game.has_method("field_interval"):
		return game.field_interval()
	return TEND_TIME


## One work tick on the tended plot.
func _tend_tick() -> void:
	if target_field == null or not is_instance_valid(target_field):
		state = "idle"
		return
	if target_field.stage < 3:
		target_field.advance()
		if game != null and game.has_method("on_field_effect"):
			game.on_field_effect(target_field)
	else:
		carry_type = "food"
		carry_amount = Stats.FIELD_YIELD
		carry_from_field = true
		target_field.on_harvested()
		if game != null and game.has_method("on_field_effect"):
			game.on_field_effect(target_field)
		order_return()


func order_attack(t) -> void:
	if t == null or not is_instance_valid(t):
		return
	# 15g: the vehicles are unarmed — an attack order on a cart
	# or wagon degrades to a plain move toward the target, so a
	# mixed selection never leaves them standing in a fake
	# "attack" state swinging for 0 damage.
	if unit_type == "cart" or unit_type == "wagon":
		var ac: Vector2i = world.nearest_walkable(
				world.world_to_cell(aim_pos_of(t)))
		if ac.x >= 0:
			order_move_cell(ac)
		return
	target_node = null
	target_field = null
	target_site = null
	attack_target = t
	# An explicit attack order is a stand-and-fight order: a villager
	# under one does not flee for the grace window.
	if unit_type == "villager":
		no_flee_timer = Stats.ATTACK_ORDER_NO_FLEE
	guard_pos = aim_pos_of(t) # after the kill the unit holds near the target
	state = "to_attack"
	_repath_t = 0.0
	_repath_attack()


func _repath_attack() -> void:
	if attack_target == null or not is_instance_valid(attack_target):
		return
	var cells: Array = []
	if attack_target is Building:
		cells = world.path_to_footprint(cell(), attack_target.cells(), team)
	else:
		cells = world.get_path_cells(cell(), attack_target.cell(), team)
	if cells.is_empty():
		# 14c: if an enemy Nham Tường (Thạch Sơn's skill wall)
		# seals the way, the wall itself becomes the target —
		# armies break through it instead of idling against an
		# unreachable order. Only when a path to the wall exists.
		var wall := _blocking_skillwall()
		if wall != null:
			var wcells: Array = world.path_to_footprint(cell(), wall.cells(), team)
			if not wcells.is_empty():
				attack_target = wall
				_set_path(wcells)
				return
		path.clear()
		path_cells.clear()
		return
	_set_path(cells)


## The nearest living enemy skill-wall segment within ~3.5
## tiles (14c breakthrough targeting), or null.
func _blocking_skillwall() -> Building:
	if game == null:
		return null
	var best: Building = null
	var bd := 3.5 * World.TILE + 16.0
	for b in game.buildings:
		if b.btype != "skillwall" or not game.attack_allowed(owner_id, b.owner_id) \
				or b.destroyed or not b.complete:
			continue
		var d := dist_to_entity(b)
		if d < bd:
			bd = d
			best = b
	return best


func _nearest_hostile_unit(radius: float):
	if game == null:
		return null
	var best = null
	var bd := radius
	for u in game.units:
		if not game.auto_engage_allowed(owner_id, u.owner_id) \
				or not u.is_targetable():
			continue
		var d := global_position.distance_to(u.global_position)
		if d < bd:
			bd = d
			best = u
	return best


## A hostile worth engaging from the guard anchor: a unit inside our
## sight whose position is also inside the leash (so idle defenders
## never chase across the map), else a hostile building in sight.
func _acquire_near_guard():
	if game == null:
		return null
	var leash := sight_px() + 64.0
	var best = null
	var bd := sight_px()
	for u in game.units:
		if not game.auto_engage_allowed(owner_id, u.owner_id) \
				or not u.is_targetable():
			continue
		var d := global_position.distance_to(u.global_position)
		if d <= bd and guard_pos.distance_to(u.global_position) <= leash:
			bd = d
			best = u
	if best != null:
		return best
	for b in game.buildings:
		if not game.auto_engage_allowed(owner_id, b.owner_id) \
				or not b.complete or b.destroyed:
			continue
		if dist_to_entity(b) <= sight_px() \
				and guard_pos.distance_to(aim_pos_of(b)) <= leash + 48.0:
			return b
	return null


func _auto_engage() -> void:
	var t = _acquire_near_guard()
	if t != null:
		attack_target = t
		state = "to_attack"
		_repath_t = 0.0
		_repath_attack()


func _after_target_lost() -> void:
	var t = _acquire_near_guard()
	if t != null:
		attack_target = t
		state = "to_attack"
		_repath_t = 0.0
		_repath_attack()
		return
	if global_position.distance_to(guard_pos) > 26.0:
		var gc: Vector2i = world.nearest_walkable(world.world_to_cell(guard_pos))
		if gc.x >= 0:
			order_move_cell(gc)
			return
	state = "idle"


func _combat_tick(delta: float, _moving: bool) -> void:
	if attack_target == null or not is_instance_valid(attack_target) \
			or (attack_target is Unit and not attack_target.is_targetable()) \
			or (attack_target is Building and attack_target.destroyed) \
			or (not (attack_target is Unit) and not (attack_target is Building) \
				and attack_target.has_method("is_dead") and attack_target.is_dead()):
		attack_target = null
		_after_target_lost()
		return
	# Face the target (drives the directional attack/walk rows).
	var tp := aim_pos_of(attack_target)
	var d := tp - global_position
	if absf(d.x) > absf(d.y):
		facing = "right" if d.x > 0.0 else "left"
	else:
		facing = "down" if d.y > 0.0 else "up"
	if in_attack_range(attack_target):
		if state != "attack":
			state = "attack"
			_atk_cd = 0.3 # wind-up before the first strike
		_atk_cd -= delta
		if _atk_cd <= 0.0:
			strike()
			_atk_cd = Stats.unit_stat(unit_type, "cooldown") / eff_atkspd_mult()
		return
	if state != "to_attack":
		state = "to_attack"
	# Marching on a building: swat hostile units standing in the way.
	if attack_target is Building:
		var near = _nearest_hostile_unit(70.0)
		if near != null:
			attack_target = near
	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = 0.4
		_repath_attack()
	_follow_path(delta)


## One hit on the current target: archers loose a projectile through
## Main, everyone else applies melee damage immediately. Damage runs
## through Stats (counter table + vs-building multipliers).
func strike() -> void:
	if attack_target == null or not is_instance_valid(attack_target):
		return
	var atk_age := 1
	if game != null and game.has_method("owner_age"):
		atk_age = game.owner_age(owner_id)
	var dmg := Stats.damage(unit_type, attack_target, atk_age)
	# Ngân Kỵ's aura "Huyết Bào": an allied military unit striking
	# within its own hero's aura radius hits harder when the hero
	# is Ngân Kỵ. Positions are sim state, so the check is
	# deterministic; the hero never buffs himself this way.
	if is_military() and unit_type != "king" and game != null \
			and game.has_method("hero_aura_covers") \
			and game.hero_aura_covers(self, "ngan_ky"):
		dmg *= Stats.KING_AURA_MULT
	# Xung Phong (the hero's own timed buff): +100% damage.
	if eff_dmg_t > 0.0:
		dmg *= eff_dmg_mult
	# Thánh Quang Phán Xét (13v): the judged hit weaker.
	if atk_down_t > 0.0:
		dmg *= atk_down_mult
	# Attack technologies (GDD section 4, at the Barracks): flat
	# per-hit bonus from the OWNER's researched tiers (archers
	# carry it into their projectile — `dmg` is fixed at strike).
	if game != null and game.has_method("tech_atk_bonus"):
		dmg += game.tech_atk_bonus(owner_id, unit_type)
	# Academy line (GDD section 4.4): spearmen hit cavalry harder.
	if unit_type == "spearman" and attack_target is Unit \
			and (attack_target as Unit).unit_type == "cavalry" \
			and game != null and game.has_method("tech_level"):
		dmg += 2.0 * float(game.tech_level(owner_id, "academy"))
	# Engineering (Castle tech, GDD section 5): rams hit harder.
	if unit_type == "ram" and game != null and game.has_method("tech_level") \
			and game.tech_level(owner_id, "engineering") > 0:
		dmg *= 1.25
	if unit_type == "king":
		# Presentation hook: lunge + gold slash VFX (see _king_tick).
		_king_slash_t = KING_SLASH_TIME
		if game != null and game.vfx != null:
			var dv := (aim_pos_of(attack_target) - global_position).normalized()
			if dv == Vector2.ZERO:
				dv = Vector2.DOWN
			game.vfx.trail_segment(global_position + Vector2(0, -22) + dv * 14.0,
					dv, Color(1.0, 0.85, 0.4, 0.95), 0.22)
			game.vfx.flash(global_position + Vector2(0, -22) + dv * 22.0,
					Color(1.0, 0.88, 0.45, 0.7), 34.0, 0.16)
	if unit_type == "archer" or (unit_type == "king" and hero_char() == "phong_linh"):
		# Archers — and Phong Linh, the ranged hero — loose a
		# projectile through Main; damage was fixed above.
		if game != null and game.has_method("fire_arrow"):
			game.fire_arrow(global_position + Vector2(0, -34), attack_target, dmg, self)
	else:
		attack_target.take_damage(dmg, self)


func take_damage(amount: float, _attacker = null, dot := false) -> void:
	if state == "dead":
		return
	# Bạch Sa's kit (defender side): her aura "Thánh Quang" softens
	# damage to allies in radius (herself included); her "Kết Giới"
	# zone softens it further for allies standing inside.
	if game != null and game.has_method("hero_damage_factor"):
		amount *= game.hero_damage_factor(self)
	# Armour technologies (13s): flat per-hit reduction from the
	# OWNER's researched tier for this unit's class (Blacksmith
	# lines; Loom for villagers). At least 1 damage always lands.
	if game != null and game.has_method("tech_armor"):
		var arm: float = game.tech_armor(owner_id, unit_type)
		if arm > 0.0:
			amount = maxf(1.0, amount - arm)
	# 14c: Thạch Sơn's aura "Thổ Giáp" — a flat 3 off every hit for
	# allies inside (himself included), same at-least-1 rule.
	if game != null and game.has_method("hero_aura_covers") \
			and game.hero_aura_covers(self, "thach_son", true):
		amount = maxf(1.0, amount - float(Stats.HERO_KITS["thach_son"]["aura_armor"]))
	# 14c: Xích Diệm's aura "Hỏa Tâm" — a hostile unit striking
	# while covered by an allied Xích Diệm hero sets its victim
	# burning. Direct hits only: DoT ticks (dot) never re-apply.
	if not dot and _attacker is Unit and game != null \
			and game.attack_allowed((_attacker as Unit).owner_id, owner_id) \
			and amount > 0.0 \
			and game.has_method("hero_aura_covers") \
			and game.hero_aura_covers(_attacker, "xich_diem"):
		apply_burn(float(Stats.HERO_KITS["xich_diem"]["aura_burn_amt"]),
				float(Stats.HERO_KITS["xich_diem"]["aura_burn_t"]),
				_attacker)
	# 13v: Vạn Hoa Khai Thiên immunity swallows the hit whole;
	# a Thiên Màn shield pool absorbs before HP is touched.
	if immune_t > 0.0:
		amount = 0.0
	elif shield_hp > 0.0 and amount > 0.0:
		var absorbed := minf(shield_hp, amount)
		shield_hp -= absorbed
		amount -= absorbed
	hp -= amount
	# 15g ambush alert: a cart / wagon under hostile fire warns
	# its owner (Main owns the presentation + throttle; the call
	# itself is a pure sim event, identical on every client).
	if amount > 0.0 and (unit_type == "cart" or unit_type == "wagon") \
			and game != null and game.has_method("notify_transport_attacked"):
		game.notify_transport_attacked(self, _attacker)
	_hurt_t = HURT_TIME # 13o: flinch row + white flash, presentation only
	if unit_type == "king":
		_king_flash_t = KING_FLASH_TIME # white flash, presentation only
		_king_hurt_t = KING_HURT_TIME # flinch pose, presentation only
	if game != null and game.vfx != null:
		game.vfx.hit_spark(global_position + Vector2(0, -26),
				TeamColors.vfx_palette(owner_id))
	if hp <= 0.0:
		hp = 0.0
		killed_by = _attacker # 13y: Main.on_unit_dead credits the kill
		die()
	else:
		_maybe_flee(_attacker)


func die() -> void:
	if state == "dead":
		return
	state = "dead"
	# 15g: a wagon's passengers die with it (the Transport Ship's
	# rule). They are out of game.units, so Main is told about
	# each loss directly (statistics + elimination stay true)
	# before the nodes are freed.
	if unit_type == "wagon":
		for cu in cargo:
			if cu != null and is_instance_valid(cu):
				cu.killed_by = killed_by
				if game != null and game.has_method("on_unit_dead"):
					game.on_unit_dead(cu)
				cu.queue_free()
		cargo.clear()
		unload_cell = Vector2i(-1, -1)
	clear_trade_route()
	# 14c: a bearer dying under Hỏa Ấn detonates the mark at the
	# spot where it fell (Main resolves the blast).
	if mark_t > 0.0 and game != null and game.has_method("explode_hero_mark"):
		game.explode_hero_mark(self)
	garrisoned = false
	visible = true
	flee_haven = null
	flee_resume = {}
	_death_t = 1.5
	_anim_key = "" # restart the anim cycle on the die row
	carry_amount = 0
	carry_type = ""
	carry_from_field = false
	attack_target = null
	path.clear()
	if game != null and game.vfx != null:
		game.vfx.death_smoke(global_position, TeamColors.vfx_palette(owner_id))


# ---------------------------------------------------------------- the hero
## The hero (unit id "king" = the player's main character) is
## rendered from SINGLE-POSE art: every character — and every
## cosmetic skin — ships one still per direction (8 dirs). There
## are no animation frames to play, so ALL hero motion is
## PROCEDURAL (presentation only — the offsets/rotations/flashes
## below never touch sim state, never enter checksums or
## snapshots). Two generations of that procedural layer:
##   13j (all appearances; still the path for cosmetic SKINS):
##     transforms on the one sprite in _king_tick —
##     idle breathing bob + skew sway, walk step bob + lean +
##     dust puffs, attack lunge + gold slash-arc VFX, hurt white
##     flash, death tip-over fall.
##   13n (the four MAIN CHARACTERS): a cutout LIMB RIG built by
##     tools/build_hero_rig.py — each still is partitioned into
##     jointed parts (back/under/legs/torso/arms) plus a drawn
##     WEAPON per character (longsword / flower sceptre / ice
##     spear / holy staff). _rig_pose poses the parts:
##     real alternating leg swings, counter-swinging arms,
##     keyframed sword slash / spear thrust / staff tap on the
##     attack cadence, a weapon-raised cast pose, a flinch —
##     see _rig_pose. The single sprite remains as the rig's
##     hidden fallback carrier (shadow/HP-bar anchor in _draw).
## Facing: 8-sector mapping of the movement/attack vector.
## APPEARANCE vs CHARACTER: the sprite follows the owner's
## APPEARANCE (Main.appearance_for — the active cosmetic skin if
## any, else the drawn character); the KIT always follows the
## drawn character (Main.char_for). Characters are never
## team-recoloured — one canonical colour set for all slots.

const KING_SLASH_TIME := 0.22
const KING_FLASH_TIME := 0.12
const KING_CAST_TIME := 0.65 # cast pose length (presentation)
const KING_HURT_TIME := 0.25 # flinch pose length (presentation)
const KING_DIR_VECS := {
	"e": Vector2(1, 0), "se": Vector2(0.7071, 0.7071),
	"s": Vector2(0, 1), "sw": Vector2(-0.7071, 0.7071),
	"w": Vector2(-1, 0), "nw": Vector2(-0.7071, -0.7071),
	"n": Vector2(0, -1), "ne": Vector2(0.7071, -0.7071),
}
const KING_DIR_BY_SECTOR: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

var hero_appearance: String = Characters.DEFAULT_CHAR
var king_dir8: String = "s"
## Timed skill effects (SIM state — set only by Main.cast_hero_skill
## and by aura-free debuffs; ticked with the sim, never by the
## renderer): generic multipliers with their remaining seconds.
var eff_spd_mult := 1.0
var eff_spd_t := 0.0
var eff_dmg_mult := 1.0
var eff_dmg_t := 0.0
var eff_atkspd_f := 1.0
var eff_atkspd_t := 0.0
## 13v skill state (SIM — set only by Main's skill sim): the two
## extra hero cooldowns, hard control locks (stun from Vương Kiếm,
## freeze from Thương Băng), the Phán Xét attack cut, the Thiên
## Màn absorb shield, Vạn Hoa damage immunity, and the blizzard
## chill (refreshed by Main's zone tick while inside Băng Hà).
var skill2_cd_t := 0.0
var skill3_cd_t := 0.0
var stun_t := 0.0
var frozen_t := 0.0
var atk_down_mult := 1.0
var atk_down_t := 0.0
var shield_hp := 0.0
var immune_t := 0.0
var chill_t := 0.0
## 14c skill state (SIM — set only by Main's skill sim / aura
## hooks): the Xích Diệm burn (HP per 0.5 s tick, refreshed not
## stacked) and her Hỏa Ấn delayed mark (Main detonates it via
## explode_hero_mark when the timer ends or the bearer dies).
var burn_t := 0.0
var burn_amt := 0.0
var burn_ticks := 0
var burn_acc := 0.0
var burn_from: Unit = null
var mark_t := 0.0
var mark_dmg := 0.0
var mark_radius := 0.0
var mark_owner := -1


## The drawn character of this hero unit (kit identity), or ""
## for non-heroes. Main.char_for is the authority (appearance —
## a cosmetic skin — never changes the kit).
func hero_char() -> String:
	if unit_type != "king" or game == null or not game.has_method("char_for"):
		return ""
	return game.char_for(owner_id)


## Xích Diệm burns: `amt` HP per 0.5 s for `dur` seconds. A fresh
## hit REFRESHES the burn (duration + tick count restart, the
## amount never stacks — a stronger active burn keeps its amount).
func apply_burn(amt: float, dur: float, from: Unit) -> void:
	if state == "dead":
		return
	if burn_t > 0.0:
		burn_amt = maxf(burn_amt, amt)
	else:
		burn_amt = amt
	burn_t = dur
	burn_ticks = int(round(dur / 0.5))
	burn_acc = 0.0
	burn_from = from
## The hero's active-skill cooldown, seconds remaining (sim).
var skill_cd_t := 0.0
var _regen_t := 0.0
var _king_base_pos := Vector2.ZERO
var _king_t := 0.0
var _king_phase := 0.0
var _king_dust_t := 0.0
var _king_slash_t := 0.0
var _king_flash_t := 0.0
var _king_aura_on := false
var _king_aura_t := 0.0
var _king_fall_dir := 1.0
## 13n cutout rig (main characters only; skins keep the
## single-sprite path above). All rig state is presentation-only.
var _hero_root: Node2D = null # carries every rig part + weapon
var _rig_active := false
var _rig_parts: Dictionary = {} # part key -> Sprite2D
var _rig_weapon_spr: Sprite2D = null
var _rig_dir: Dictionary = {} # HeroRig.dir_data of the facing
var _king_cast_t := 0.0 # set by Main.cast_hero_skill (a hook like the VFX)
var _king_hurt_t := 0.0 # set by take_damage, beside _king_flash_t
var _atk_phase := 0.0 # attack-swing cycle phase while in combat


func _setup_king_sprite() -> void:
	hero_appearance = Characters.DEFAULT_CHAR
	if game != null and game.has_method("appearance_for"):
		hero_appearance = str(game.appearance_for(owner_id))
	_king_fall_dir = 1.0 if net_id % 2 == 0 else -1.0
	disp_scale = display_scale_for(unit_type) # 0.49 — the roster base
	spr = Sprite2D.new()
	spr.centered = false
	# Painted/pixel skin art at a fractional display scale: sample
	# like the sheets (linear + mipmaps), never nearest steps.
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(spr)
	_king_apply_dir("s")
	# A missing texture must not crash the roster fallback in _draw.
	if spr.texture == null:
		spr.queue_free()
		spr = null
	# 13n: the four main characters upgrade to the cutout limb rig
	# (the single sprite stays as the hidden fallback carrier —
	# _draw's shadow/ring branch and the ac18/ac19 texture checks
	# keep reading it). Skins have no rig data and skip this.
	if spr != null and Characters.is_character(hero_appearance) \
			and HeroRig.has_rig(hero_appearance):
		_hero_root = Node2D.new()
		add_child(_hero_root)
		_rig_active = true
		spr.visible = false
		_rig_build_dir(king_dir8)


func _king_apply_dir(dir8: String) -> void:
	if spr == null:
		return
	var tex := Characters.texture_for(hero_appearance, dir8)
	if tex == null:
		return
	spr.texture = tex
	var sz := Vector2(tex.get_size())
	spr.scale = Vector2.ONE * disp_scale
	# Feet land exactly on the unit origin (bottom-centre anchor).
	_king_base_pos = Vector2(-sz.x * disp_scale * 0.5, -sz.y * disp_scale)
	spr.position = _king_base_pos
	_disp_h = sz.y * disp_scale
	_disp_side_w = sz.x * disp_scale
	spr.flip_h = false # every appearance ships real 8-dir art
	if _rig_active:
		_rig_build_dir(dir8)


## (Re)build the rig's part sprites for a facing. Each part is a
## full-canvas sprite whose node origin sits on the part's joint
## pivot, so rotating the node rotates the limb around the joint
## exactly as the offline QA renders in build_hero_rig.py do.
func _rig_build_dir(dir8: String) -> void:
	for c in _hero_root.get_children():
		c.queue_free()
	_rig_parts.clear()
	_rig_weapon_spr = null
	_rig_dir = HeroRig.dir_data(hero_appearance, dir8)
	var parts: Dictionary = _rig_dir.get("parts", {})
	for key in parts:
		var pd: Dictionary = parts[key]
		var s := Sprite2D.new()
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.texture = HeroRig.tex(String(pd.get("tex", "")))
		if s.texture == null:
			continue
		var pv: Array = pd.get("pivot", [0, 0])
		var pivot := Vector2(float(pv[0]), float(pv[1]))
		s.position = _king_base_pos + pivot * disp_scale
		s.offset = -pivot
		s.scale = Vector2.ONE * disp_scale
		s.z_index = int(pd.get("z", 2))
		_hero_root.add_child(s)
		_rig_parts[key] = s
	# Side views: shade the FAR leg (the one drawn behind, lower
	# z) so the two legs separate visually when they scissor.
	# The builder keeps the textures untouched (rest reassembly
	# stays pixel-exact); this is a node modulate, presentation
	# only, and it multiplies under the root's hurt-flash tint.
	if dir8 in ["e", "w"]:
		var far_key := ""
		var far_z := 999
		for key in ["leg_l", "leg_r"]:
			if _rig_parts.has(key) and int(parts[key].get("z", 2)) < far_z:
				far_z = int(parts[key].get("z", 2))
				far_key = key
		if far_key != "":
			_rig_parts[far_key].modulate = Color(0.74, 0.74, 0.8)
			var far_shin := "shin_" + far_key.substr(4)
			if _rig_parts.has(far_shin):
				_rig_parts[far_shin].modulate = Color(0.74, 0.74, 0.8)
	# The weapon rides on top (or, for back views of the gown
	# characters, tucked behind — its z comes from the rig data).
	var wp: Dictionary = _rig_dir.get("weapon", {})
	if not wp.is_empty():
		var ws := Sprite2D.new()
		ws.centered = false
		ws.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ws.texture = HeroRig.tex(String(HeroRig.char_data(hero_appearance)
				.get("weapon", {}).get("tex", "")))
		if ws.texture != null:
			# 13v: official weapon art ships at 2x resolution with a
			# "wscale" of 0.5 in the rig char data — same on-screen
			# size as the 13n drawn weapons, twice the detail.
			var wscale := float(HeroRig.char_data(hero_appearance)
					.get("weapon", {}).get("wscale", 1.0))
			ws.scale = Vector2.ONE * disp_scale * wscale
			ws.z_index = int(wp.get("z", 6))
			# Pose it at rest right away: _rig_pose only re-poses
			# per frame, and the spawn frame (or a direction whose
			# weapon arm is not separable) must never show the
			# weapon sitting at the uninitialised origin.
			var grip_a: Array = HeroRig.char_data(hero_appearance) \
					.get("weapon", {}).get("grip", [0, 0])
			var hand_a: Array = wp.get("hand", [0, 0])
			ws.position = _king_base_pos + Vector2(float(hand_a[0]),
					float(hand_a[1])) * disp_scale
			ws.offset = -Vector2(float(grip_a[0]), float(grip_a[1]))
			ws.rotation = deg_to_rad(float(wp.get("rest", 0.0)))
			_hero_root.add_child(ws)
			_rig_weapon_spr = ws


func king_dir_vec() -> Vector2:
	return KING_DIR_VECS.get(king_dir8, Vector2.DOWN)


## Map a world-space direction vector to one of the 8 facings.
static func dir8_of(v: Vector2) -> String:
	var idx := int(round(v.angle() / (PI * 0.25)))
	idx = ((idx % 8) + 8) % 8
	return KING_DIR_BY_SECTOR[idx]


func _king_tick(delta: float) -> void:
	if spr == null:
		return
	_king_t += delta
	if _king_cast_t > 0.0:
		_king_cast_t -= delta
	if _king_hurt_t > 0.0:
		_king_hurt_t -= delta
	# --- facing (movement or target vector, 45-degree sectors)
	var dirv := Vector2.ZERO
	if attack_target != null and is_instance_valid(attack_target) \
			and (state == "attack" or state == "to_attack"):
		dirv = aim_pos_of(attack_target) - global_position
	elif not path.is_empty():
		dirv = path[0] - global_position
	if state != "dead" and dirv.length() > 2.0:
		var nd := dir8_of(dirv)
		if nd != king_dir8:
			king_dir8 = nd
			_king_apply_dir(nd)
	# --- hurt flash (rgb only; the death fade owns alpha)
	if _king_flash_t > 0.0:
		_king_flash_t -= delta
	var bright := 1.0
	if _king_flash_t > 0.0:
		bright = 1.0 + (_king_flash_t / KING_FLASH_TIME) * 1.4
	spr.modulate = Color(bright, bright, bright, spr.modulate.a)
	if _rig_active and _hero_root != null:
		_hero_root.modulate = Color(bright, bright, bright, _hero_root.modulate.a)
	if state == "dead":
		return # the fall is posed by the death branch in _process
	# --- procedural body motion
	var moving := state in ["move", "to_node", "return", "to_build",
			"to_field", "flee", "to_attack"]
	var off := Vector2.ZERO
	var rot := 0.0
	var squash := 1.0
	if moving:
		# Step cadence follows speed. Rigged heroes step faster
		# (13n follow-up): at the old rate the stride covered
		# ~37 world px per step while the feet swept ~4 px — the
		# classic foot-slide that reads as "no leg movement".
		_king_phase += delta * speed * (0.13 if _rig_active else 0.085)
		off.y = -absf(sin(_king_phase)) * 2.4
		rot = king_dir_vec().x * 0.045 # lean into the travel direction
		spr.skew = 0.0
		_king_dust_t -= delta
		if _king_dust_t <= 0.0:
			_king_dust_t = 0.26
			if game != null and game.vfx != null:
				game.vfx.puff(global_position + Vector2(0, 2),
						Color(0.62, 0.58, 0.52, 0.4), 2, 16.0, 0.4)
	elif state == "attack":
		off.y = sin(_king_t * 2.2) * 0.6 # planted, breathing hard
		spr.skew = sin(_king_t * 1.6) * 0.010
	else:
		# Idle: breathing bob; the skew sways a beat off-phase so
		# hair/scarf seem to drift against the body's rise and fall.
		off.y = sin(_king_t * 2.2) * 1.0
		squash = 1.0 + sin(_king_t * 2.2) * 0.006
		spr.skew = sin(_king_t * 1.6 + 0.9) * 0.018
	if _king_slash_t > 0.0:
		_king_slash_t -= delta
		var k := clampf(_king_slash_t / KING_SLASH_TIME, 0.0, 1.0)
		off += king_dir_vec() * (sin((1.0 - k) * PI) * 6.0) # lunge out and back
	if _rig_active and _hero_root != null:
		# The root carries the whole articulated figure: body bob /
		# lean / breathing squash apply to it as they did to the
		# single sprite; the limbs are posed per part afterwards.
		_hero_root.position = off
		_hero_root.rotation = rot
		_hero_root.scale = Vector2(1.0, squash)
		_rig_pose(delta, moving)
	else:
		spr.position = _king_base_pos + off
		spr.rotation = rot
		spr.scale = Vector2(disp_scale, disp_scale * squash)
	# --- aura ring state (polled on a cadence; drawn in _draw)
	_king_aura_t -= delta
	if _king_aura_t <= 0.0:
		_king_aura_t = 0.25
		var on: bool = game != null and game.has_method("aura_active_for") \
				and game.aura_active_for(self)
		if on != _king_aura_on:
			_king_aura_on = on
			queue_redraw()
	if _king_aura_on:
		queue_redraw() # keep the ring's pulse alive


## Piecewise-linear keyframe sampler for the attack/cast curves.
## keys: [[u, degrees], ...] sorted by u.
static func _kf(u: float, keys: Array) -> float:
	if u <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var u1 := float(keys[i][0])
		if u <= u1:
			var u0 := float(keys[i - 1][0])
			var v0 := float(keys[i - 1][1])
			var v1 := float(keys[i][1])
			return v0 + (v1 - v0) * (u - u0) / maxf(u1 - u0, 0.0001)
	return float(keys[keys.size() - 1][1])


## 13n pose evaluation for the cutout rig: set every part's
## rotation (around its joint pivot) and foot-lift offset for this
## frame, plus the weapon's transform. The curves were verified
## offline against tools/build_hero_rig.py's QA pose sheets (walk
## extremes / strike frame / cast apex) and run continuously here:
##   walk    legs swing in opposite phases around the hip (side
##           views at full amplitude; front/back views add an
##           alternating foot lift so the step reads head-on),
##           arms counter-swing against the same-side leg, the
##           weapon arm steadier (factor from the rig data)
##   attack  keyframed swing per weapon class on the hero's real
##           attack cadence: sword slash, spear thrust, staff tap
##   cast    weapon arm raises the weapon overhead (apex curve),
##           off-arm extends, slight crouch — driven by
##           _king_cast_t, set from Main.cast_hero_skill
##   hurt    a flinch overlay (arm sag + recoil) on _king_hurt_t
##   idle    breathing-scale arm sway + cape/back drift
## Presentation only — nothing here feeds back into sim state.
func _rig_pose(delta: float, moving: bool) -> void:
	if _rig_dir.is_empty():
		return
	var tun := HeroRig.tuning(hero_appearance)
	var wclass := HeroRig.weapon_class(hero_appearance)
	var wp: Dictionary = _rig_dir.get("weapon", {})
	var warm := String(wp.get("arm", ""))
	# f = +1 when the weapon arm is the screen-right arm; every
	# raise/slash curve is authored for f=+1 and mirrored by f
	# (the builder already mirrors rest angles in the data).
	var f := 1.0 if warm == "arm_r" else -1.0
	var side := king_dir8 in ["e", "w"]
	var swing := float(_rig_dir.get("swing", 1))
	var leg_amp := float(tun.get("leg_amp", 0.3)) \
			* (1.0 if side else HeroRig.front_leg_factor(hero_appearance))
	var arm_amp := float(tun.get("arm_amp", 0.2))
	var phase := _king_phase * float(tun.get("cadence", 1.0))
	var parts: Dictionary = _rig_dir.get("parts", {})
	var rots := {}
	var dys := {}
	var dxs := {}
	var knee_rots := {}
	for key in _rig_parts:
		rots[key] = 0.0
		dys[key] = 0.0
		dxs[key] = 0.0
		knee_rots[key] = 0.0
	var weapon_abs := 0.0
	var weapon_is_abs := false
	if _king_cast_t > 0.0:
		# ---- cast: raise the weapon overhead on an apex curve.
		var u := clampf(1.0 - _king_cast_t / KING_CAST_TIME, 0.0, 1.0)
		var raise := sin(PI * minf(u * 1.2, 1.0))
		if _rig_parts.has(warm):
			rots[warm] = -1.92 * f * raise
		var other := "arm_l" if warm == "arm_r" else "arm_r"
		if _rig_parts.has(other):
			rots[other] = 0.55 * f * raise
		for key in ["leg_l", "leg_r"]:
			if _rig_parts.has(key):
				rots[key] = (0.12 if int(parts[key].get("phase", 0)) == 0 else -0.06) * raise
		if _rig_parts.has("back"):
			rots["back"] = -0.05 * raise
		_hero_root.position += Vector2(0, 1.6 * sin(PI * u)) # crouch mid-cast
		var cast_abs: float = float({"ngan_ky": -18.0, "lam_bao": -24.0,
				"kim_hoa": -8.0, "bach_sa": -6.0,
				"loi_chan": -28.0, "xich_diem": -14.0,
				"phong_linh": -22.0, "thach_son": -18.0}.get(hero_appearance, -10.0))
		var rest_auth := float(wp.get("rest", 0.0)) * f
		weapon_abs = deg_to_rad(lerpf(rest_auth, cast_abs, raise) * f)
		weapon_is_abs = true
	elif state == "attack":
		# ---- attack: keyframed swing on the hero's real cadence.
		var spd_f := eff_atkspd_f if eff_atkspd_t > 0.0 else 1.0
		_atk_phase += delta / (Stats.unit_stat("king", "cooldown") / clampf(spd_f, 0.3, 2.5))
		var u := fmod(_atk_phase, 1.0)
		var rest_auth := float(wp.get("rest", 0.0)) * f
		var arm_keys: Array
		var wabs_keys: Array
		match wclass:
			"sword":
				arm_keys = [[0.0, 0.0], [0.30, -52.0], [0.46, 30.0], [0.75, 18.0], [1.0, 0.0]]
				wabs_keys = [[0.0, rest_auth], [0.30, -58.0], [0.46, 190.0], [0.75, 175.0], [1.0, rest_auth]]
			"spear":
				var thrust := 92.0 if side else 55.0
				arm_keys = [[0.0, 0.0], [0.30, -14.0], [0.46, 12.0], [0.8, 6.0], [1.0, 0.0]]
				wabs_keys = [[0.0, rest_auth], [0.30, rest_auth - 14.0], [0.46, thrust], [0.8, thrust - 10.0], [1.0, rest_auth]]
			"bow":
				# 14c (Phong Linh): raise the bow, draw, hold the
				# aim, loose. Side views swing the bow level toward
				# the facing; front/back views barely rotate it
				# (a vertical bow reads correctly shooting up/down
				# screen) — the aim factor follows the direction.
				var aim := 86.0 if side else (52.0 if king_dir8 in
						["se", "sw", "ne", "nw"] else 12.0)
				arm_keys = [[0.0, 0.0], [0.30, -34.0], [0.46, -40.0], [0.8, -36.0], [1.0, 0.0]]
				wabs_keys = [[0.0, rest_auth], [0.30, rest_auth - aim * 0.8],
						[0.46, rest_auth - aim], [0.8, rest_auth - aim],
						[1.0, rest_auth]]
			_: # staff tap
				arm_keys = [[0.0, 0.0], [0.30, -20.0], [0.46, 16.0], [1.0, 0.0]]
				wabs_keys = [[0.0, rest_auth], [0.30, rest_auth - 22.0], [0.46, rest_auth + 36.0], [1.0, rest_auth]]
		if _rig_parts.has(warm):
			rots[warm] = deg_to_rad(_kf(u, arm_keys)) * f
		var other := "arm_l" if warm == "arm_r" else "arm_r"
		if _rig_parts.has(other):
			rots[other] = -0.35 * rots.get(warm, 0.0)
		for key in ["leg_l", "leg_r"]:
			if _rig_parts.has(key) and int(parts[key].get("phase", 0)) == 0:
				rots[key] = deg_to_rad(13.0) * swing * (1.0 if side else 0.7) \
						* clampf(sin(PI * clampf((u - 0.3) / 0.3, 0.0, 1.0)), 0.0, 1.0)
		weapon_abs = deg_to_rad(_kf(u, wabs_keys) * f)
		weapon_is_abs = true
	elif moving:
		# ---- walk (13n follow-up — the stride must READ): thighs
		# swing ±leg_amp around a hip pivot placed at the fauld
		# hem (long lever, ~20-25 sprite px to the foot); mid
		# swing-through the shin FOLDS at the knee (knights) so
		# the foot tucks and clears the ground; front/back views
		# trade some rotation for a hard alternating foot lift
		# plus a stance widening on the stepping leg. Gown hem
		# panels trail the stride phase, and their shoe tips
		# slide out from under the hem and lift each step.
		var knee_fold_max := float(tun.get("knee_fold", 0.0))
		var hem_lag := float(tun.get("hem_lag", 0.0))
		var shoe_amp := float(tun.get("shoe_amp", 0.0))
		for key in ["leg_l", "leg_r"]:
			if _rig_parts.has(key):
				var th := phase + float(int(parts[key].get("phase", 0))) * PI
				var lift := maxf(0.0, cos(th)) # peaks mid swing-through
				if hem_lag > 0.0:
					var thl := th - hem_lag
					rots[key] = sin(thl) * leg_amp * (swing if side else 1.0)
					if side:
						dxs[key] = -sin(thl) * 1.8 * swing
				else:
					rots[key] = sin(th) * leg_amp * (swing if side else 1.0)
				if side:
					dys[key] = -1.2 * lift
				else:
					dxs[key] += (-1.2 if key == "leg_l" else 1.2) * lift
					dys[key] = -4.0 * lift
				var fold := knee_fold_max * pow(lift, 1.5) \
						* (1.0 if side else 0.35)
				knee_rots[key] = fold * swing
		for key in ["shoe_l", "shoe_r"]:
			if _rig_parts.has(key):
				var sth := phase + float(int(parts[key].get("phase", 0))) * PI
				dxs[key] = sin(sth) * 3.6 * shoe_amp * (swing if side else 0.6)
				dys[key] = -maxf(0.0, cos(sth)) * 3.0 * shoe_amp
				rots[key] = sin(sth) * 0.09
		for key in ["arm_l", "arm_r"]:
			if _rig_parts.has(key):
				var leg_key := "leg_l" if key == "arm_l" else "leg_r"
				var lph := 0
				if parts.has(leg_key):
					lph = int(parts[leg_key].get("phase", 0))
				elif parts.has("leg_l"):
					lph = int(parts["leg_l"].get("phase", 0))
				var w := sin(phase + float(lph) * PI)
				var wf := 0.45 if key == warm else 1.0
				rots[key] = -w * arm_amp * wf * (swing if side else 1.0)
		if _rig_parts.has("back"):
			rots["back"] = sin(phase - 0.6) * 0.05
	else:
		# ---- idle: breathing arm sway + back/cape drift.
		for key in ["arm_l", "arm_r"]:
			if _rig_parts.has(key):
				var wf := 0.6 if key == warm else 1.0
				rots[key] = sin(_king_t * 2.2 + (0.0 if key == "arm_l" else 0.7)) * 0.05 * wf
		if _rig_parts.has("back"):
			rots["back"] = sin(_king_t * 1.6 + 0.9) * 0.02
	# ---- hurt overlay: flinch (arms sag, body recoils).
	if _king_hurt_t > 0.0 and state != "dead":
		var k := _king_hurt_t / KING_HURT_TIME
		if _rig_parts.has(warm):
			rots[warm] += 0.35 * k * f
		var other2 := "arm_l" if warm == "arm_r" else "arm_r"
		if _rig_parts.has(other2):
			rots[other2] += 0.22 * k * f
		_hero_root.position -= king_dir_vec() * (k * 3.0)
	# ---- compose shins: a shin rides its thigh — its rotation
	# is thigh + knee fold, and its pivot (the knee point) lands
	# where the thigh's rotation carried it, plus the leg's own
	# lift/slide offsets.
	for suffix in ["l", "r"]:
		var lk: String = "leg_" + suffix
		var sk: String = "shin_" + suffix
		if _rig_parts.has(sk) and parts.has(lk) and parts[lk].has("knee"):
			var hip_a: Array = parts[lk].get("pivot", [0, 0])
			var knee_a: Array = parts[lk].get("knee", hip_a)
			var hip := Vector2(float(hip_a[0]), float(hip_a[1]))
			var knee := Vector2(float(knee_a[0]), float(knee_a[1]))
			var ta := float(rots.get(lk, 0.0))
			var knee_now := hip + (knee - hip).rotated(ta)
			rots[sk] = ta + float(knee_rots.get(lk, 0.0))
			dxs[sk] = (knee_now.x - knee.x) + float(dxs.get(lk, 0.0))
			dys[sk] = (knee_now.y - knee.y) + float(dys.get(lk, 0.0))
	# ---- apply parts
	for key in _rig_parts:
		var s: Sprite2D = _rig_parts[key]
		var pv: Array = parts[key].get("pivot", [0, 0])
		var pivot := Vector2(float(pv[0]), float(pv[1]))
		s.rotation = float(rots.get(key, 0.0))
		s.position = _king_base_pos + pivot * disp_scale \
				+ Vector2(float(dxs.get(key, 0.0)),
						float(dys.get(key, 0.0))) * disp_scale
	# ---- apply weapon: the grip rides the weapon arm's hand,
	# rotated around the shoulder pivot; the weapon's own angle
	# follows the arm at rest/walk (data "follow") and is
	# keyframed absolutely during attack/cast. Directions whose
	# weapon arm is not a separable part (the gown characters'
	# back views — the veil/gown covers the arms in the source
	# art) anchor the grip on the direction's static hand point
	# instead; the absolute attack/cast angles still apply, so
	# the weapon lifts even there instead of dangling unposed.
	if _rig_weapon_spr != null and not wp.is_empty():
		var grip_a: Array = HeroRig.char_data(hero_appearance).get("weapon", {}).get("grip", [0, 0])
		var grip := Vector2(float(grip_a[0]), float(grip_a[1]))
		_rig_weapon_spr.offset = -grip
		if _rig_parts.has(warm) and parts.has(warm):
			var pv2: Array = parts[warm].get("pivot", [0, 0])
			var pivot2 := Vector2(float(pv2[0]), float(pv2[1]))
			var hand_a: Array = wp.get("hand", pv2)
			var hand := Vector2(float(hand_a[0]), float(hand_a[1]))
			var a := float(rots.get(warm, 0.0))
			var dv := hand - pivot2
			var hand_now := pivot2 + Vector2(dv.x * cos(a) - dv.y * sin(a),
					dv.x * sin(a) + dv.y * cos(a))
			_rig_weapon_spr.position = _king_base_pos + hand_now * disp_scale
			if weapon_is_abs:
				_rig_weapon_spr.rotation = weapon_abs
			else:
				_rig_weapon_spr.rotation = deg_to_rad(float(wp.get("rest", 0.0))) \
						+ a * float(wp.get("follow", 1.0))
		else:
			var hand_a2: Array = wp.get("hand", [0, 0])
			_rig_weapon_spr.position = _king_base_pos + Vector2(
					float(hand_a2[0]), float(hand_a2[1])) * disp_scale
			if weapon_is_abs:
				_rig_weapon_spr.rotation = weapon_abs
			else:
				_rig_weapon_spr.rotation = deg_to_rad(float(wp.get("rest", 0.0)))

# ---------------------------------------------------------------- fleeing
## Flee entry point, called from take_damage with a surviving hit.
## Only villagers flee, only from hostiles (enemy unit / building /
## ship, or a wild beast), never while garrisoned or already fleeing,
## and never inside the attack-order grace window.
func _maybe_flee(attacker) -> void:
	if unit_type != "villager" or garrisoned or state == "flee" or state == "dead":
		return
	if no_flee_timer > 0.0 or game == null:
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	var hostile := false
	if attacker is Beast:
		hostile = true
	elif attacker is Unit or attacker is Building or attacker is Ship:
		hostile = not game.owners_allied(owner_id, attacker.owner_id)
	if hostile:
		_start_flee(attacker)


func _start_flee(attacker) -> void:
	# The interrupted task is ABANDONED, not snapshotted: per the
	# match-start flow doc there is no automatic villager control —
	# after fleeing, the villager waits for a fresh player order.
	target_node = null
	target_field = null
	target_site = null
	attack_target = null
	var haven = null
	if game.has_method("flee_haven_for"):
		haven = game.flee_haven_for(self)
	flee_haven = haven
	if haven != null:
		var cells: Array = world.path_to_footprint(cell(), haven.cells(), team)
		if not cells.is_empty():
			_set_path(cells)
			state = "flee"
			return
		flee_haven = null
	# No (reachable) haven: bolt ~4 tiles directly away from the attacker.
	var from_pos: Vector2 = attacker.global_position if attacker is Node2D else global_position
	var away := global_position - from_pos
	if away.length() < 1.0:
		away = Vector2(1, 0)
	var dest: Vector2i = world.nearest_walkable(
			world.world_to_cell(global_position + away.normalized() * World.TILE * 4.0))
	if dest.x >= 0:
		var cells2: Array = world.get_path_cells(cell(), dest, team)
		if not cells2.is_empty():
			_set_path(cells2)
			state = "flee"
			return
	state = "idle"


func _enter_garrison() -> void:
	state = "garrison"
	garrisoned = true
	visible = false
	selected = false
	path.clear()
	_deposit() # the haven IS a drop-off: bank the load on the way in
	flee_timer = Stats.FLEE_GARRISON_MAX
	_flee_scan_t = 0.0
	# Wait at the haven's centre while hidden; pop-out picks an edge.
	global_position = flee_haven.position \
			+ Vector2(flee_haven.size) * World.TILE * 0.5


func _garrison_tick(delta: float) -> void:
	flee_timer -= delta
	if flee_haven == null or not is_instance_valid(flee_haven) or flee_haven.destroyed:
		_exit_garrison()
		return
	if flee_timer <= 0.0:
		_exit_garrison() # stay cap reached: come out regardless
		return
	# Early exit once the building's surroundings are clear (checked
	# on a cadence, after a minimum stay so it cannot strobe).
	if flee_timer <= Stats.FLEE_GARRISON_MAX - Stats.FLEE_GARRISON_MIN:
		_flee_scan_t -= delta
		if _flee_scan_t <= 0.0:
			_flee_scan_t = 0.3
			var centre: Vector2 = flee_haven.position \
					+ Vector2(flee_haven.size) * World.TILE * 0.5
			if not _hostiles_near(centre, Stats.FLEE_SAFE_TILES * World.TILE):
				_exit_garrison()


func _hostiles_near(pos: Vector2, radius: float) -> bool:
	if game == null:
		return false
	for u in game.units:
		if game.auto_engage_allowed(owner_id, u.owner_id) and u.is_targetable() \
				and pos.distance_to(u.global_position) <= radius:
			return true
	if game.get("ships") != null:
		for s in game.ships:
			if game.auto_engage_allowed(owner_id, s.owner_id) and not s.is_dead() \
					and pos.distance_to(s.global_position) <= radius:
				return true
	if world != null and world.get("beasts") != null:
		for bst in world.beasts:
			if not bst.is_dead() and pos.distance_to(bst.global_position) <= radius:
				return true
	return false


func _exit_garrison() -> void:
	garrisoned = false
	visible = true
	state = "idle"
	var haven = flee_haven
	flee_haven = null
	flee_timer = 0.0
	if haven != null and is_instance_valid(haven) and not haven.destroyed:
		var adj: Array = world.adjacent_walkable(haven.cells())
		if not adj.is_empty():
			global_position = world.cell_center(adj[0])
	# NO auto-resume (match-start flow doc: no automatic villager
	# control): the villager pops out and stays IDLE by the haven
	# until the player issues a new order.
	flee_resume = {}
	state = "idle"


## Main calls this when the haven building is destroyed from under
## its garrison: the villager pops out where it stood.
func release_garrison() -> void:
	if state == "garrison":
		_exit_garrison()


func _finish_gather() -> void:
	if target_node == null or not is_instance_valid(target_node):
		_seek_or_idle()
		return
	var got: int = target_node.take(CARRY_CAP)
	# A beast carcass ("meat") is carried and banked as Food.
	carry_type = "food" if target_node.rtype == "meat" else target_node.rtype
	carry_amount = got
	carry_from_field = false
	var depleted := target_node.amount <= 0
	var dead_node: ResourceNode = target_node
	if game != null and got > 0 and game.has_method("on_node_gathered"):
		game.on_node_gathered(dead_node)
	if depleted and game != null and game.has_method("on_node_depleted"):
		game.on_node_depleted(dead_node)
	if depleted:
		target_node = null
		world.remove_node(dead_node)
	if got <= 0:
		_seek_or_idle()
		return
	order_return()


func _deposit() -> void:
	if carry_amount > 0:
		if game != null and game.has_method("on_deposit_effect"):
			game.on_deposit_effect(team, carry_type, global_position)
		# Biome yield: the delivered amount is round(carried x biome
		# yield) — rich desert gold, sparse desert wood (Biomes table).
		var delivered := carry_amount
		if game != null and game.has_method("delivered_amount"):
			delivered = game.delivered_amount(carry_amount, carry_type, carry_from_field, owner_id)
		# Owner-routed: deposits feed the owning player's ledger
		# (in SP owner_id == team: player ledger / AI ledger, never mixed).
		game.credit_owner(owner_id, carry_type, delivered)
		carry_amount = 0
		carry_type = ""
		carry_from_field = false


func _seek_or_idle() -> void:
	# NO auto-tasking (match-start flow doc: the player issues
	# every work order): when the target node is gone/depleted the
	# villager simply goes idle — it does NOT pick a new node.
	state = "idle"


func _draw() -> void:
	if spr != null:
		# Sprite is a child node (drawn after this, i.e. above the ring);
		# here we draw the soft ground shadow + selection ring under the
		# feet and the carried-resource box above the head (the Carry
		# cycle's sack already shows the load, so the box is skipped
		# while it plays).
		# Shadow / ring / bars follow the rendered size (the formulas
		# reduce to the original fixed offsets for the Villager).
		var sh_w := clampf(_disp_side_w * 0.55, 34.0, 100.0)
		draw_texture_rect(get_shadow_tex(), Rect2(-sh_w * 0.5, -6, sh_w, 12), false, Color(1, 1, 1, 0.30))
		if unit_type == "king" and _king_aura_on and state != "dead":
			# Inspiration aura made visible: a faint pulsing gold
			# ring at the King's feet while troops nearby benefit.
			var pulse := 0.26 + 0.10 * sin(_king_t * 3.0)
			draw_arc(Vector2(0, 1), 21.0, 0, TAU, 40,
					Color(1.0, 0.84, 0.35, pulse), 2.0)
		if selected:
			draw_arc(Vector2(0, 1), clampf(_disp_side_w * 0.30, 14.0, 34.0), 0, TAU, 28, TeamColors.ui_color(owner_id), 2.0)
		# 15g: a selected trade cart shows its route — a faint
		# gold line cart -> target Market -> home Market
		# (presentation only; the route itself is sim state).
		if selected and unit_type == "cart" and state != "dead" \
				and trade_target != null and is_instance_valid(trade_target):
			var pts := PackedVector2Array()
			pts.append(Vector2(0, 1))
			pts.append(to_local(trade_target.position
					+ Vector2(trade_target.size) * World.TILE * 0.5))
			if trade_home != null and is_instance_valid(trade_home):
				pts.append(to_local(trade_home.position
						+ Vector2(trade_home.size) * World.TILE * 0.5))
			draw_polyline(pts, Color(1.0, 0.85, 0.40, 0.45), 2.0)
		if carry_amount > 0 and anim_name != "carry":
			var cc2 := Color(0.5, 0.35, 0.18)
			if carry_type == "gold":
				cc2 = Color(0.95, 0.8, 0.25)
			elif carry_type == "stone":
				cc2 = Color(0.65, 0.66, 0.68)
			elif carry_type == "food":
				cc2 = Color(0.85, 0.3, 0.3)
			draw_rect(Rect2(-5, -(_disp_h + 12.0), 10, 7), cc2)
		if hp < max_hp and state != "dead":
			var frac := clampf(hp / max_hp, 0.0, 1.0)
			var bcol := TeamColors.ui_color(owner_id)
			var bw := clampf(_disp_side_w * 0.5, 34.0, 48.0)
			var by := -(_disp_h + 14.0) # floats just above the head at any ruler size
			draw_rect(Rect2(-bw * 0.5, by, bw, 4.5), Color(0, 0, 0, 0.55))
			draw_rect(Rect2(-bw * 0.5, by, bw * frac, 4.5), bcol)
		return
	if selected:
		draw_arc(Vector2.ZERO, 14, 0, TAU, 28, TeamColors.ui_color(owner_id), 2.0)
	var body_col := TeamColors.ui_color(owner_id)
	draw_circle(Vector2(0, 2), 9, body_col)
	draw_circle(Vector2(0, -4), 5, Color(0.96, 0.8, 0.64)) # head
	if carry_amount > 0:
		var cc := Color(0.5, 0.35, 0.18)
		if carry_type == "gold":
			cc = Color(0.95, 0.8, 0.25)
		elif carry_type == "stone":
			cc = Color(0.65, 0.66, 0.68)
		draw_rect(Rect2(-5, -19, 10, 7), cc)
	if state == "gather" or state == "build":
		# little work indicator
		draw_arc(Vector2(0, -14), 4, 0, TAU, 12, Color(1, 1, 1, 0.8), 1.5)
