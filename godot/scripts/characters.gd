class_name Characters
extends RefCounted
## The main-character ("Nhân vật chính") registry — Tín's final
## model, 2026-11-09, after several framings were replaced:
##
## * There are no "kings with skins" any more. The hero unit is
##   the player's MAIN CHARACTER. Bé's self-drawn Western king
##   was removed from the roster entirely (its files stay on disk
##   unused); the roster is Tín's supplied cast.
## * EIGHT CHARACTERS (16b: Tín's Western Medieval generals —
##   NHAN-VAT-TAY-TRUNG-CO.md is the design source of truth),
##   each with a framed portrait avatar and a personal KIT (one
##   passive aura + exactly ONE active skill on a unified 75 s
##   cooldown — the numbers live in Stats.HERO_KITS; names and
##   descriptions for UI live here):
##     knight    Hiệp Sĩ Hoàng Gia — royal knight (tank)
##     berserker Chiến Binh Cuồng Nộ — berserker (fighter)
##     archer    Cung Thủ Tinh Anh — elven archer (ranged)
##     mage      Pháp Sư Cung Đình — court mage (ranged)
##     paladin   Thánh Kỵ Sĩ — holy paladin (support)
##     dragoon   Kỵ Sĩ Long — dragon knight (mobility)
##     assassin  Sát Thủ Bóng Đêm — assassin
##     ranger    Nhà Thám Hiểm — explorer (skirmisher)
## * Characters are NOT chosen. At match start every player is
##   randomly ASSIGNED one character from their owned pool (the
##   server draws for MP rooms and puts char_id in the match
##   payload; SP draws locally). The draw pool is characters
##   only — never skins.
## * The three wuxia sets (vo_hiep / bach_y / tu_y) are COSMETIC
##   SKINS: appearance packs {id, name, 8-dir sprites, premium}.
##   A skin has NO kit — a hero wearing one keeps the drawn
##   character's kit, stats and name label; only the pixels
##   change. They are FUTURE PAID content: nobody owns one yet
##   (no shop), so the active-skin slot ships DORMANT — the
##   collection screen shows them locked and activation is
##   rejected client- and server-side.
## * Characters are NEVER recoloured per team: one canonical
##   colour set (the original art) serves every slot. Allegiance
##   in match is carried by the player NAME over the hero's head,
##   tinted with the owner's slot colour (Main's hero overlay).
##   Soldiers/buildings/ships keep the 4-slot colour system.
## * The profile AVATAR is decoupled from the draw: a free pick
##   among the 8 portraits, stored on the account (avatar_id).

const DEFAULT_CHAR := "knight"
const CFG_PATH := "user://character.cfg"
const DIRS8: Array[String] = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

const CHARACTERS := {
	"knight": {
		"name": "Hiệp Sĩ Hoàng Gia", "role": "Đỡ Đòn",
		"aura": "Hộ Vệ", "aura_desc": "Đồng minh trong 3 ô: giảm 8% sát thương nhận vào.",
		"skill": "Khiên Sư Tử", "skill_desc": "Giương khiên sư tử: nhận khiên hấp thụ 250 sát thương trong 6 giây; mọi địch trong 3 ô bị khiêu khích, buộc phải tấn công Hiệp Sĩ trong 4 giây.",
	},
	"berserker": {
		"name": "Chiến Binh Cuồng Nộ", "role": "Đấu Sĩ",
		"aura": "Cuồng Chiến", "aura_desc": "Đồng minh trong 3 ô: +10% tốc độ đánh.",
		"skill": "Rìu Xoáy Cuồng Nộ", "skill_desc": "Xoay rìu một vòng lớn: 110 sát thương cho mọi địch trong 2 ô quanh mình.",
	},
	"archer": {
		"name": "Cung Thủ Tinh Anh", "role": "Xạ Thủ",
		"aura": "Ngắm Chuẩn", "aura_desc": "Đồng minh trong 3 ô: +8% sát thương đòn đánh.",
		"skill": "Mưa Tên", "skill_desc": "Gọi mưa tên xuống một vùng 2,5 ô trong tầm 8 ô: 3 đợt trong 2 giây, mỗi đợt 40 sát thương cho địch trong vùng.",
	},
	"mage": {
		"name": "Pháp Sư Cung Đình", "role": "Pháp Sư",
		"aura": "Sinh Lực", "aura_desc": "Đồng minh trong 3 ô: hồi 1,2 HP mỗi giây.",
		"skill": "Thiên Thạch Ma Thuật", "skill_desc": "Gọi thiên thạch ma thuật giáng xuống điểm chọn: 120 sát thương phép cho địch trong 2,5 ô.",
	},
	"paladin": {
		"name": "Thánh Kỵ Sĩ", "role": "Hỗ Trợ",
		"aura": "Thánh Giáp", "aura_desc": "Đồng minh trong 3 ô: +3 giáp (mỗi đòn đánh vào giảm 3 sát thương).",
		"skill": "Thánh Quang Hồi Phục", "skill_desc": "Cầu nguyện thánh quang: hồi 160 HP cho mọi đồng minh trong 3 ô và giải mọi hiệu ứng xấu trên họ.",
	},
	"dragoon": {
		"name": "Kỵ Sĩ Long", "role": "Cơ Động",
		"aura": "Long Hành", "aura_desc": "Đồng minh trong 3 ô: +10% tốc độ di chuyển.",
		"skill": "Long Thương Xuyên Tâm", "skill_desc": "Lao thẳng tối đa 5 ô: 120 sát thương cho mọi địch nằm trên đường lao.",
	},
	"assassin": {
		"name": "Sát Thủ Bóng Đêm", "role": "Sát Thủ",
		"aura": "Thích Sát", "aura_desc": "Đồng minh trong 3 ô: +10% sát thương khi đánh tướng địch.",
		"skill": "Ám Sát", "skill_desc": "Biến mất rồi xuất hiện ngay sau lưng một địch trong 6 ô, đâm một đòn chí mạng 160 sát thương.",
	},
	"ranger": {
		"name": "Nhà Thám Hiểm", "role": "Thám Hiểm",
		"aura": "Viễn Thị", "aura_desc": "Đồng minh trong 3 ô: +1 ô tầm nhìn.",
		"skill": "Kiếm Vũ Lữ Hành", "skill_desc": "Múa kiếm thần tốc: 5 nhát chém trong 1 giây, mỗi nhát 32 sát thương, chia đều cho các địch trong 2 ô quanh mình.",
	},
}
const CHAR_IDS: Array[String] = ["knight", "berserker", "archer", "mage",
		"paladin", "dragoon", "assassin", "ranger"]

## Cosmetic appearance skins — NO kits, never in the draw pool.
const SKINS := {
	"vo_hiep": {"name": "Võ Hiệp"},
	"bach_y": {"name": "Bạch Y"},
	"tu_y": {"name": "Tử Y"},
}
const SKIN_IDS: Array[String] = ["vo_hiep", "bach_y", "tu_y"]

static var _local_avatar := ""
static var _owned_skins: Array = [] # from the account profile (Net)
static var _tex_cache := {}


static func normalize_char(id: String) -> String:
	return id if CHARACTERS.has(id) else DEFAULT_CHAR


static func normalize_skin(id: String) -> String:
	return id if SKINS.has(id) else ""


static func is_character(id: String) -> bool:
	return CHARACTERS.has(id)


static func char_name(id: String) -> String:
	return String(CHARACTERS[normalize_char(id)].get("name", ""))


static func skin_name(id: String) -> String:
	return String(SKINS[id].get("name", id)) if SKINS.has(id) else ""


static func kit_of(char_id: String) -> Dictionary:
	return CHARACTERS[normalize_char(char_id)]


## SQUARE bust portrait of a MAIN character (the profile-avatar
## pool): a clean square crop from inside the supplied portrait's
## aperture, so it fills the game's plain square frames exactly
## (tools/build_square_avatars.py). Every avatar slot — home chip,
## rail, friends, leaderboard, profile — resolves through here.
## Skins have no portraits — their front pose serves as thumb.
static func avatar_for(avatar_id: String) -> Texture2D:
	var id := normalize_char(avatar_id)
	var key := "avatar|" + id
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var path := "res://assets/avatars/avatar_sq_" + id + ".png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[key] = tex
	return tex


## The supplied FRAMED portrait art itself (octagonal frame baked
## in) — only for surfaces that display it as a picture in its own
## right, i.e. the collection-screen character cards.
static func framed_avatar_for(avatar_id: String) -> Texture2D:
	var id := normalize_char(avatar_id)
	var key := "framed|" + id
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var path := "res://assets/avatars/king_avatar_" + id + ".png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[key] = tex
	return tex


## Canonical sprite of an appearance (a character OR a cosmetic
## skin — same generated file layout), facing `dir8`. ONE colour
## set for every slot: characters are never team-recoloured.
static func texture_for(appearance_id: String, dir8: String) -> Texture2D:
	var key := appearance_id + "|" + dir8
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var path := "res://assets/king_" + appearance_id + "_" + dir8 + ".png"
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[key] = tex
	return tex


## The local player's profile-avatar pick (mains only). The
## account's server-side avatar_id wins once logged in (Net
## pushes it here on auth); guests keep the local cfg value.
static func local_avatar() -> String:
	if _local_avatar == "":
		var cfg := ConfigFile.new()
		if cfg.load(CFG_PATH) == OK:
			_local_avatar = normalize_char(String(cfg.get_value("avatar", "id", DEFAULT_CHAR)))
		else:
			_local_avatar = DEFAULT_CHAR
	return _local_avatar


static func set_local_avatar(id: String) -> void:
	_local_avatar = normalize_char(id)
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("avatar", "id", _local_avatar)
	cfg.save(CFG_PATH)


## Cosmetic-skin ownership + activation (dormant until the shop
## exists): ownership arrives with the account profile; the
## active skin is a local choice validated against ownership —
## today nobody owns any skin, so activation always fails.
static func set_owned_skins(list: Array) -> void:
	_owned_skins = list.duplicate()


static func owns_skin(id: String) -> bool:
	return _owned_skins.has(id)


static func local_active_skin() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		var id := normalize_skin(String(cfg.get_value("skin", "active", "")))
		if id != "" and owns_skin(id):
			return id
	return ""


static func try_set_active_skin(id: String) -> bool:
	var sid := normalize_skin(id)
	if sid == "" or not owns_skin(sid):
		return false
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("skin", "active", sid)
	cfg.save(CFG_PATH)
	return true
