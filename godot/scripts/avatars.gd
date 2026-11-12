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
const CFG_PATH := "user://avatar.cfg"
const IDS: Array[String] = [
	"art:01", "art:02", "art:03", "art:04", "art:05",
	"art:06", "art:07", "art:08", "art:09", "art:10",
	"art:11", "art:12", "art:13", "art:14", "art:15",
	"art:16", "art:17", "art:18", "art:19", "art:20",
]

static var _local := ""
static var _tex_cache := {}


static func is_avatar(id: String) -> bool:
	return IDS.has(id)


static func normalize_id(id: String) -> String:
	return id if IDS.has(id) else DEFAULT_ID


static func display_name(id: String) -> String:
	return "Anime " + normalize_id(id).substr(4)


## The avatar's texture (rounded-square art; callers render
## it with STRETCH_KEEP_ASPECT_COVERED so it fills its box).
static func texture_for(id: String) -> Texture2D:
	var nid := normalize_id(id)
	if _tex_cache.has(nid):
		return _tex_cache[nid]
	var tex: Texture2D = null
	var path := "res://assets/avatars/avatar_" + nid.replace(":", "_") + ".png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[nid] = tex
	return tex


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
