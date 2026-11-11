class_name FieldPlot
extends Node2D
## A 1-tile farm field plot (self-drawn pass). Placed near a completed
## Farm; a tending villager grows it stage by stage (0 bare soil ->
## 1 sprouts -> 2 green crop -> 3 golden ripe). At stage 3 a work tick
## harvests FIELD_YIELD food and the plot falls back to sprouts while
## harvests remain; after FIELD_HARVESTS harvests it lies bare until a
## villager re-tills it (the 0 -> 1 tick resets the harvest count).
## Plots never block movement and draw flat on the terrain.

const STAGE_PATHS := [
	"res://assets/fields/field_s1.png",
	"res://assets/fields/field_s2.png",
	"res://assets/fields/field_s3.png",
	"res://assets/fields/field_s4.png",
]

var cell: Vector2i = Vector2i.ZERO
var farm = null # owning Farm building (duck-typed)
var stage: int = 0 # 0..3 (texture index = stage)
var harvests_left: int = Stats.FIELD_HARVESTS

var _spr: Sprite2D = null
# 13o presentation: crop sway — a growing plot stood perfectly
# still before this. Transform-only (no redraws), phase from the
# cell hash so neighbouring plots never sway in lockstep.
var _t := 0.0
var _phase := 0.0


func _ready() -> void:
	z_index = 2
	position = Vector2(cell) * World.TILE
	_phase = float(absi(cell.x * 41 + cell.y * 97) % 628) / 100.0
	_spr = Sprite2D.new()
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_spr.centered = false
	add_child(_spr)
	_apply_texture()


func _process(delta: float) -> void:
	_t += delta
	if _spr == null:
		return
	var amp := 0.0
	if stage == 1:
		amp = 0.010 # sprouts barely stir
	elif stage >= 2:
		amp = 0.028 # green + ripe crops rustle
	_spr.skew = sin(_t * 1.5 + _phase) * amp


func _apply_texture() -> void:
	if _spr == null:
		return
	var path: String = STAGE_PATHS[clampi(stage, 0, 3)]
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	_spr.texture = tex
	# Fit the plot art into its tile (art is drawn slightly top-down,
	# so a straight tile fit reads right from the game's camera).
	_spr.scale = Vector2(World.TILE, World.TILE) / Vector2(tex.get_size())


func set_stage(n: int) -> void:
	stage = clampi(n, 0, 3)
	_apply_texture()


## One tend tick of growth. The 0 -> 1 step is the re-till: it resets
## the harvest budget.
func advance() -> void:
	if stage == 0:
		harvests_left = Stats.FIELD_HARVESTS
	set_stage(stage + 1)


## A ripe harvest was taken: regrow from sprouts while budget lasts,
## otherwise the plot is exhausted and lies bare.
func on_harvested() -> void:
	harvests_left -= 1
	set_stage(1 if harvests_left > 0 else 0)
