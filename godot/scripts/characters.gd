class_name Characters
extends RefCounted
## The main-character ("Nhân vật chính") registry — Tín's final
## model, 2026-11-09, after several framings were replaced:
##
## * There are no "kings with skins" any more. The hero unit is
##   the player's MAIN CHARACTER. Bé's self-drawn Western king
##   was removed from the roster entirely (its files stay on disk
##   unused); the roster is Tín's supplied cast.
## * EIGHT CHARACTERS (the original four + the 14c Temple
##   Masters), each with a framed portrait avatar and a personal
##   KIT (one aura + three active skills — the numbers live in
##   Stats.HERO_KITS / HERO_SKILL2 / HERO_SKILL3; names and
##   descriptions for UI live here):
##     ngan_ky  Ngân Kỵ  — frontline knight
##     kim_hoa  Kim Hoa  — sovereign support
##     lam_bao  Lam Bào  — ice prince (sheet hair fixed to black)
##     bach_sa  Bạch Sa  — veil priestess
##     loi_chan  Lôi Chấn  — lightning twin-blade master
##     xich_diem Xích Diệm — fire fan master
##     phong_linh Phong Linh — wind longbow master (ranged hero)
##     thach_son Thạch Sơn — earth hammer master
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

const DEFAULT_CHAR := "ngan_ky"
const CFG_PATH := "user://character.cfg"
const DIRS8: Array[String] = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

const CHARACTERS := {
	"ngan_ky": {
		"name": "Ngân Kỵ",
		"aura": "Huyết Bào", "aura_desc": "Đồng minh trong 3 ô: +15% tấn công.",
		"skill": "Xung Phong", "skill_desc": "5 giây: +50% tốc độ chạy, +100% sát thương.",
		"skill2": "Kiếm Khí Tung Hoành", "skill2_desc": "Sóng kiếm khí theo hướng mặt: 45 sát thương lên mọi kẻ địch trên đường đi.",
		"skill3": "Vương Kiếm Giáng Thế", "skill3_desc": "Đại kiếm giáng xuống một vùng: 120 sát thương lên quân, 250 lên công trình, choáng 1 giây.",
	},
	"kim_hoa": {
		"name": "Kim Hoa",
		"aura": "Sinh Tồn", "aura_desc": "Đồng minh trong 3 ô: hồi 1 HP mỗi 2 giây.",
		"skill": "Vương Mệnh Hồi Phục", "skill_desc": "Hồi ngay 80 HP cho mọi đồng minh trong 3 ô.",
		"skill2": "Hoa Vũ Hồi Sinh", "skill2_desc": "Mưa hoa 6 giây: đồng minh trong vùng hồi máu dần và được giải hiệu ứng chậm/đóng băng.",
		"skill3": "Vạn Hoa Khai Thiên", "skill3_desc": "Hồi ngay 200 HP cho đồng minh trong 4 ô + miễn nhiễm sát thương 3 giây.",
	},
	"lam_bao": {
		"name": "Lam Bào",
		"aura": "Hàn Khí", "aura_desc": "Kẻ địch trong 3 ô: −15% tốc độ chạy.",
		"skill": "Băng Phong", "skill_desc": "Kẻ địch trong 2.5 ô: −60% tốc chạy, −40% tốc đánh trong 3 giây.",
		"skill2": "Thương Băng Xuyên Tâm", "skill2_desc": "Thương băng xuyên tuyến: 35 sát thương; kẻ địch đầu tiên trúng bị đóng băng cứng 1.5 giây.",
		"skill3": "Băng Hà Vĩnh Cửu", "skill3_desc": "Bão băng 8 giây: kẻ địch trong vùng bị chậm nặng + mất máu dần; công trình bên trong đóng băng, ngừng hoạt động.",
	},
	"bach_sa": {
		"name": "Bạch Sa",
		"aura": "Thánh Quang", "aura_desc": "Đồng minh trong 3 ô: nhận ít hơn 10% sát thương.",
		"skill": "Kết Giới", "skill_desc": "Kết giới 8 giây tại vị trí tung chiêu: đồng minh bên trong nhận ít hơn 30% sát thương.",
		"skill2": "Thánh Quang Phán Xét", "skill2_desc": "Cột sáng giáng lên nhóm địch: 55 sát thương và giảm 30% công của chúng trong 5 giây.",
		"skill3": "Thiên Màn Bất Diệt", "skill3_desc": "Màn thánh 8 giây: đồng minh trong vùng được khiên hấp thụ 120; công trình bên trong không nhận sát thương.",
	},
	# 14c — the four Temple Masters (NHAN-VAT-MOI-5-8.md): the
	# roster grows to eight; same rules (drawn, never recoloured).
	"loi_chan": {
		"name": "Lôi Chấn",
		"aura": "Lôi Vực", "aura_desc": "Đồng minh trong 3 ô: +12% tốc độ đánh.",
		"skill": "Lôi Độn", "skill_desc": "Lướt tối đa 5 ô như tia chớp: 40 sát thương quanh điểm đáp, +20% tốc chạy trong 4 giây.",
		"skill2": "Song Lôi Liên Kích", "skill2_desc": "Sét đánh mục tiêu 55 sát thương rồi nảy sang 3 kẻ địch gần nhất, mỗi phát 30.",
		"skill3": "Thiên Lôi Phạt Trận", "skill3_desc": "Vùng bão sét 6 giây: mỗi giây giáng 45 sát thương, kẻ địch trong vùng chậm 20%.",
	},
	"xich_diem": {
		"name": "Xích Diệm",
		"aura": "Hỏa Tâm", "aura_desc": "Đòn đánh của đồng minh trong 3 ô thiêu đốt kẻ địch: 3 HP mỗi 0.5 giây trong 2 giây.",
		"skill": "Hỏa Ấn", "skill_desc": "Gắn ấn lửa lên mục tiêu: sau 2 giây phát nổ 70 sát thương trong 1.5 ô.",
		"skill2": "Diệm Phiến Toàn", "skill2_desc": "Quạt lửa hình nón trước mặt: 50 sát thương + thiêu đốt 4 HP mỗi 0.5 giây trong 3 giây.",
		"skill3": "Phượng Hỏa Giáng", "skill3_desc": "Phượng lửa giáng xuống: 130 sát thương (150 lên công trình), mặt đất cháy 5 giây.",
	},
	"phong_linh": {
		"name": "Phong Linh",
		"aura": "Phong Hành", "aura_desc": "Đồng minh trong 3 ô: +12% tốc độ chạy.",
		"skill": "Truy Phong Tiễn", "skill_desc": "Phát bắn xuyên tuyến tầm 8 ô: 75 sát thương, bỏ qua mọi đơn vị đứng giữa.",
		"skill2": "Tiễn Vũ", "skill2_desc": "Mưa tên 3 đợt lên một vùng: mỗi đợt 20 sát thương.",
		"skill3": "Cuồng Phong Nộ", "skill3_desc": "Lốc xoáy 6 giây: kéo kẻ địch về tâm, 15 sát thương mỗi 0.5 giây, giảm 30% công của chúng.",
	},
	"thach_son": {
		"name": "Thạch Sơn",
		"aura": "Thổ Giáp", "aura_desc": "Đồng minh trong 3 ô: +3 giáp (mỗi đòn đánh vào giảm 3 sát thương).",
		"skill": "Sơn Băng Đạp", "skill_desc": "Nhảy tối đa 4 ô rồi dậm đất: 40 sát thương trong 2 ô, hất lùi 1 ô, chậm 30% trong 2 giây.",
		"skill2": "Nham Tường", "skill2_desc": "Dựng tường đá 3 ô (300 HP mỗi ô) chặn đường trong 12 giây.",
		"skill3": "Địa Long Lật Đất", "skill3_desc": "Đất lật trong 3.5 ô: 90 sát thương lên quân, 300 lên công trình, chậm 40% trong 3 giây.",
	},
}
const CHAR_IDS: Array[String] = ["ngan_ky", "kim_hoa", "lam_bao", "bach_sa",
		"loi_chan", "xich_diem", "phong_linh", "thach_son"]

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
