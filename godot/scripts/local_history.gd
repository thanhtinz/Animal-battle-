class_name LocalHistory
extends RefCounted

## Local match log for UNRANKED matches (13g history panel,
## "Đấu Thường" rows): custom-room and single-player results are
## recorded on this device only — the server never sees them.
## Stored newest-first in user://match_log.json, capped at CAP
## entries. Ranked results live server-side instead (Net history)
## and are NOT duplicated here.

const PATH := "user://match_log.json"
const CAP := 20

static var _cache: Array = []
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = []
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		_cache = parsed


static func entries() -> Array:
	_ensure_loaded()
	return _cache.duplicate()


static func record(entry: Dictionary) -> void:
	_ensure_loaded()
	_cache.push_front(entry)
	while _cache.size() > CAP:
		_cache.pop_back()
	_save()


## Links a server-recorded replay (13h) to the local entry of
## the room it was played in, when the relay hands the id out at
## result time.
static func patch_replay(room: String, replay_id: String) -> void:
	if room == "" or replay_id == "":
		return
	_ensure_loaded()
	for e in _cache:
		if String(e.get("room", "")) == room and String(e.get("replay_id", "")) == "":
			e["replay_id"] = replay_id
			_save()
			return


static func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cache))
	f.close()
