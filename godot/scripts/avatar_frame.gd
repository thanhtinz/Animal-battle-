class_name AvatarFrame
extends Control

## Shared account-avatar + frame composer (17d). ONE helper
## renders an equipped avatar frame AROUND the avatar on
## every account surface (profile card, home identity chip,
## friends rows, leaderboard rows, players panel): the frame
## art fills this control's rect; the avatar is fitted as the
## centred square inscribed in the frame's calibrated window
## (aperture), measured from the owner's GIFs and baked into
## assets/avatar_frames/manifest.json by
## tools/build_avatar_frames.py. With no frame equipped the
## avatar simply fills the rect. Status dots / online badges
## are added by CALLERS after this control so they always
## draw on top of the frame art.
##
## animated=true plays the frame's sprite-sheet animation
## (profile card, avatar panel); list rows pass false and
## get the static first frame.

const MANIFEST_PATH := "res://assets/avatar_frames/manifest.json"

static var _manifest: Dictionary = {}
static var _manifest_tried := false
static var _tex_cache := {}

var _avatar_rect: TextureRect
var _frame_rect: TextureRect
var _avatar_tex: Texture2D = null
var _frame_id := ""
var _anim_idx := 0
var _anim_acc := 0.0
var _animating := false


static func _load_manifest() -> void:
	if _manifest_tried:
		return
	_manifest_tried = true
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			_manifest = parsed


static func has_frame(id: String) -> bool:
	_load_manifest()
	return _manifest.has(id)


static func frame_ids() -> Array:
	_load_manifest()
	var out := _manifest.keys()
	out.sort()
	return out


static func _sheet_texture(id: String) -> Texture2D:
	_load_manifest()
	var key := "sheet|" + id
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var meta: Dictionary = _manifest.get(id, {})
	var path := String(meta.get("sheet", ""))
	if path == "":
		path = "res://assets/avatar_frames/" + id + "_sheet.png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[key] = tex
	return tex


static func _frame_atlas(id: String, idx: int) -> Texture2D:
	var meta: Dictionary = _manifest.get(id, {})
	var sheet := _sheet_texture(id)
	if sheet == null or meta.is_empty():
		return null
	var cell := int(meta.get("cell", 256))
	var cols := maxi(1, int(meta.get("cols", 1)))
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2((idx % cols) * cell, (idx / cols) * cell, cell, cell)
	return at


## First-frame texture (list rows).
static func static_texture(id: String) -> Texture2D:
	_load_manifest()
	var key := "static|" + id
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex := _frame_atlas(id, 0)
	_tex_cache[key] = tex
	return tex


## One animation frame's atlas texture (cached per id+idx).
## NOTE: Godot 4.4's AnimatedTexture draws AtlasTexture
## frames WRONG (the whole sheet leaks into the draw — seen
## on the 17d captures), so animation is stepped manually by
## the control below: plain AtlasTextures draw correctly.
static func frame_texture_at(id: String, idx: int) -> Texture2D:
	_load_manifest()
	var key := "atlas|%s|%d" % [id, idx]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex := _frame_atlas(id, idx)
	_tex_cache[key] = tex
	return tex


static func frame_count(id: String) -> int:
	_load_manifest()
	var meta: Dictionary = _manifest.get(id, {})
	return int(meta.get("frames", 0))


static func frame_fps(id: String) -> float:
	_load_manifest()
	var meta: Dictionary = _manifest.get(id, {})
	return maxf(1.0, float(meta.get("fps", 10.0)))


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_rect = TextureRect.new()
	_avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_frame_rect = TextureRect.new()
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_avatar_rect)
	add_child(_frame_rect)
	resized.connect(_layout)


## Compose: avatar texture + frame id ("" = no frame).
func set_content(avatar_tex: Texture2D, fid: String, animated: bool) -> void:
	_avatar_tex = avatar_tex
	_frame_id = fid if has_frame(fid) else ""
	_avatar_rect.texture = avatar_tex
	_anim_idx = 0
	_anim_acc = 0.0
	_animating = animated and _frame_id != "" and frame_count(_frame_id) > 1
	if _frame_id == "":
		_frame_rect.texture = null
	else:
		_frame_rect.texture = frame_texture_at(_frame_id, 0)
	set_process(_animating)
	_layout()


func _process(delta: float) -> void:
	if not _animating or _frame_id == "":
		return
	_anim_acc += delta
	var step := 1.0 / frame_fps(_frame_id)
	if _anim_acc < step:
		return
	_anim_acc = fmod(_anim_acc, step)
	_anim_idx = (_anim_idx + 1) % frame_count(_frame_id)
	_frame_rect.texture = frame_texture_at(_frame_id, _anim_idx)


func _layout() -> void:
	if _avatar_rect == null:
		return
	_frame_rect.position = Vector2.ZERO
	_frame_rect.size = size
	if _frame_id == "":
		_avatar_rect.position = Vector2.ZERO
		_avatar_rect.size = size
		return
	var meta: Dictionary = _manifest.get(_frame_id, {})
	var ap: Array = meta.get("aperture", [0.0, 0.0, 1.0, 1.0])
	if ap.size() != 4:
		ap = [0.0, 0.0, 1.0, 1.0]
	# The frame's window in this control's pixels; the avatar
	# is the centred square inscribed in it.
	var win := Rect2(
		float(ap[0]) * size.x, float(ap[1]) * size.y,
		(float(ap[2]) - float(ap[0])) * size.x,
		(float(ap[3]) - float(ap[1])) * size.y)
	var side := minf(win.size.x, win.size.y)
	_avatar_rect.size = Vector2(side, side)
	_avatar_rect.position = win.position + (win.size - _avatar_rect.size) * 0.5
