class_name Avatars
extends RefCounted

## Account-avatar catalogue (17d). OWNER CORRECTION 2 +
## ADDITION (2026-11-12): the catalogue is ONLY the owner's
## twenty anime avatars (art_candidates/avatars_anime/
## art_01..20.png, built into assets/avatars/ by
## tools/build_account_avatars.py) — the zip fan-art set was
## dropped entirely, and the old hero portraits are NOT
## account avatars anymore (they remain on hero-specific
## surfaces via Characters). Every avatar is FREE for every
## account; the server validates picks against the same
## catalogue (server/cosmetics.go). Ids are namespaced
## "art:NN". The default is art:01; stored ids outside the
## catalogue (incl. every pre-17d hero id) fall back to it.

const DEFAULT_ID := "art:01"
## 17f §5: the self-uploaded photo's avatar id. It is NOT in
## IDS (the catalogue stays the twenty anime) — it is a
## per-account picture the server stores and other clients
## fetch on demand (see texture_for_user).
const CUSTOM_ID := "custom"
const CUSTOM_PATH := "user://custom_avatar.jpg"
const CFG_PATH := "user://avatar.cfg"
const IDS: Array[String] = [
	"art:01", "art:02", "art:03", "art:04", "art:05",
	"art:06", "art:07", "art:08", "art:09", "art:10",
	"art:11", "art:12", "art:13", "art:14", "art:15",
	"art:16", "art:17", "art:18", "art:19", "art:20",
]

static var _local := ""
static var _tex_cache := {}
static var _custom_cache := {} # user -> Texture2D (17f §5)
static var _own_tex: Texture2D = null


static func is_avatar(id: String) -> bool:
	return IDS.has(id)


static func normalize_id(id: String) -> String:
	if IDS.has(id) or id == CUSTOM_ID:
		return id
	return DEFAULT_ID


static func display_name(id: String) -> String:
	if id == CUSTOM_ID:
		return "Ảnh của bạn"
	return "Anime " + normalize_id(id).substr(4)


## The avatar's texture (rounded-square art; callers render
## it with STRETCH_KEEP_ASPECT_COVERED so it fills its box).
## "custom" resolves to the LOCAL player's own photo (own
## surfaces); other players' photos go through
## texture_for_user so the fetch knows whose bytes to get.
static func texture_for(id: String) -> Texture2D:
	var nid := normalize_id(id)
	if nid == CUSTOM_ID:
		var own := own_custom_texture()
		return own if own != null else texture_for(DEFAULT_ID)
	if _tex_cache.has(nid):
		return _tex_cache[nid]
	var tex: Texture2D = null
	var path := "res://assets/avatars/avatar_" + nid.replace(":", "_") + ".png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[nid] = tex
	return tex


## Avatar texture in the context of a KNOWN account (rows,
## posts, chat): a "custom" id returns that account's photo
## — from the session cache when present, otherwise the
## default avatar for now while Net fetches the photo (the
## owning surface re-renders when Net.custom_avatar_ready
## fires, or on its next refresh).
static func texture_for_user(id: String, user: String) -> Texture2D:
	if normalize_id(id) != CUSTOM_ID:
		return texture_for(id)
	if user != "" and user == Net.account_name:
		return texture_for(CUSTOM_ID)
	if _custom_cache.has(user):
		return _custom_cache[user]
	if user != "":
		Net.request_custom_avatar(user)
	return texture_for(DEFAULT_ID)


## Stores fetched/uploaded photo bytes as a usable texture.
## For the local player the bytes also persist to disk so
## own surfaces work before any fetch (and offline).
static func set_custom_bytes(user: String, jpg: PackedByteArray) -> void:
	var img := Image.new()
	if img.load_jpg_from_buffer(jpg) != OK:
		return
	var tex := ImageTexture.create_from_image(img)
	_custom_cache[user] = tex
	if user != "" and user == Net.account_name:
		_own_tex = tex
		var f := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(jpg)


## The local player's own uploaded photo (uploaded this
## session or restored from the on-disk copy), or null.
static func own_custom_texture() -> Texture2D:
	if _own_tex != null:
		return _own_tex
	if FileAccess.file_exists(CUSTOM_PATH):
		var img := Image.new()
		if img.load(CUSTOM_PATH) == OK:
			_own_tex = ImageTexture.create_from_image(img)
	return _own_tex


## True when the local player has an uploaded photo on this
## device (the settings upload cell's state label).
static func has_own_custom() -> bool:
	return own_custom_texture() != null


## The local player's pick. The account's server-side value
## wins once logged in (Net pushes it here on auth /
## profile_update); guests keep the local cfg value.
static func local_avatar() -> String:
	if _local == "":
		var cfg := ConfigFile.new()
		if cfg.load(CFG_PATH) == OK:
			_local = normalize_id(String(cfg.get_value("avatar", "id", DEFAULT_ID)))
		else:
			_local = DEFAULT_ID
	return _local


static func set_local_avatar(id: String) -> void:
	_local = normalize_id(id)
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("avatar", "id", _local)
	cfg.save(CFG_PATH)
