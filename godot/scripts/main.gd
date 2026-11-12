extends Node2D
## Empire Age — P2 core prototype root.
## Builds the whole scene from code: world, camera, HUD, bases, units.
## Owns game state (resources, selection, placement) and the order API.

const BUILD_DEFS := {
	"town_center": {"name": "Town Center", "size": Vector2i(3, 3), "cost": {}, "build_time": 0.0, "pop": 5},
	"house": {"name": "House", "size": Vector2i(2, 2), "cost": {"wood": 30}, "build_time": 6.0, "pop": 5},
	"barracks": {"name": "Barracks", "size": Vector2i(3, 3), "cost": {"wood": 100}, "build_time": 10.0, "pop": 0},
	"mining_camp": {"name": "Mining Camp", "size": Vector2i(3, 3), "cost": {"wood": 100}, "build_time": 8.0, "pop": 0},
	"tower": {"name": "Watch Tower", "size": Vector2i(2, 2), "cost": {"wood": 50, "stone": 100}, "build_time": 8.0, "pop": 0},
	"blacksmith": {"name": "Blacksmith", "size": Vector2i(3, 3), "cost": {"wood": 150}, "build_time": 12.0, "pop": 0},
	"lumber_camp": {"name": "Lumber Camp", "size": Vector2i(3, 3), "cost": {"wood": 100}, "build_time": 8.0, "pop": 0},
	"storage": {"name": "Storage", "size": Vector2i(3, 3), "cost": {"wood": 100}, "build_time": 8.0, "pop": 0},
	"market": {"name": "Market", "size": Vector2i(3, 3), "cost": {"wood": 150}, "build_time": 10.0, "pop": 0},
	"dock": {"name": "Dock", "size": Vector2i(3, 3), "cost": {"wood": 150}, "build_time": 10.0, "pop": 0},
	"farm": {"name": "Farm", "size": Vector2i(3, 3), "cost": {"wood": 100}, "build_time": 8.0, "pop": 0},
	"castle": {"name": "Castle", "size": Vector2i(4, 4), "cost": {"wood": 300, "stone": 200}, "build_time": 20.0, "pop": 0},
	"wallwood": {"name": "Tường gỗ", "size": Vector2i(1, 1), "cost": {"wood": 15}, "build_time": 2.0, "pop": 0},
	"wallstone": {"name": "Tường đá", "size": Vector2i(1, 1), "cost": {"stone": 30}, "build_time": 3.0, "pop": 0},
	"gatewood": {"name": "Cổng gỗ", "size": Vector2i(1, 1), "cost": {"wood": 50}, "build_time": 3.0, "pop": 0},
	"gatestone": {"name": "Cổng đá", "size": Vector2i(1, 1), "cost": {"stone": 50}, "build_time": 4.0, "pop": 0},
}
## Market exchange (fixed rates, traded from the Market's info panel):
## sell MARKET_TRADE_AMOUNT of food/wood/stone for MARKET_SELL_GOLD gold,
## buy the same amount back for MARKET_BUY_GOLD gold.
const MARKET_TRADE_AMOUNT := 100
const MARKET_SELL_GOLD := 40
const MARKET_BUY_GOLD := 60
const MARKET_TRADE_TYPES: Array = ["food", "wood", "stone"]
const VILLAGER_COST := 50
const UNIT_COSTS := {
	"villager": {"food": 50},
	"militia": {"food": 60, "gold": 20},
	"archer": {"wood": 50, "gold": 40},
	"spearman": {"food": 50, "wood": 25},
	"cavalry": {"food": 80, "gold": 40},
	"ram": {"wood": 120, "gold": 40},
	# 15g land transport (genre-default prices, flagged in
	# KE-HOACH): the trade Cart is the Market's unit (the AoE II
	# trade-cart price), the troop Wagon is the Barracks' carrier.
	"cart": {"wood": 100, "gold": 50},
	"wagon": {"wood": 120, "gold": 30},
	# The King: a hero, not a line unit — priced like a small army
	# and trained at the Castle (see training_building routing).
	"king": {"food": 500, "gold": 300},
}
const UNIT_NAMES := {"villager": "Villager", "militia": "Militia", "archer": "Archer",
	"spearman": "Spearman", "cavalry": "Cavalry", "ram": "Battering Ram",
	"cart": "Xe hàng", "wagon": "Xe chở quân",
	"king": "Nhân vật chính"}
## Minimum age to train each unit (all military trains at the one
## Barracks): spearman from Age I, cavalry from Feudal, ram Age III.
## The King breaks the one-Barracks rule by design: he is the
## Castle's hero, Age IV only, one alive per player.
const UNIT_MIN_AGE := {"spearman": 1, "cavalry": 2, "ram": 3, "king": 4, "cart": 2, "wagon": 2}

## 15g trade (genre defaults — the GDD names the trade cart but
## fixes no formula; flagged "chờ Tín chốt" in KE-HOACH 15g):
## a completed round trip pays Gold scaled by the one-way route
## distance in tiles, floored and capped; routes shorter than
## TRADE_MIN_TILES cannot be assigned at all.
const TRADE_GOLD_PER_TILE := 2.0
const TRADE_GOLD_MIN := 10
const TRADE_GOLD_CAP := 150
const TRADE_MIN_TILES := 8.0

## Vietnamese resource names for block-reason lines (13s panels).
const RES_VN := {"food": "food", "wood": "gỗ", "gold": "vàng", "stone": "đá", "iron": "sắt"}

## Ships (trained at the Dock; they live on the water grid and do
## not count toward the land population cap).
const SHIP_COSTS := {
	"fishing_boat": {"wood": 75},
	"transport": {"wood": 125},
	"war_ship": {"wood": 150, "gold": 50},
}
const SHIP_NAMES := {"fishing_boat": "Thuyền cá", "transport": "Thuyền chở quân",
	"war_ship": "Thuyền chiến"}

var resources: Dictionary = {"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0}

# --- P4 multiplayer state -----------------------------------------------------
## Set by the Net autoload before the scene (re)loads into an MP
## match (statics survive the reload; the socket lives in Net).
static var mp_active: bool = false
static var mp_config: Dictionary = {} # {seed, biome, layout, players:[{slot,name,team}]}
static var mp_debug_log: bool = false # MPLOG evidence lines (smoke test)
static var mp_referee: bool = false # P4 stage 3: this process IS the match referee
static var mp_observer: bool = false # 15a: this process WATCHES a live custom match (no slot)
static var mp_replay: bool = false # 13h: this process plays back a recorded match
static var mp_replay_test: bool = false # 13h verification driver (print + quit)

var mp_mode: bool = false
var referee_mode: bool = false # dedicated referee: owns all slots, reports the result
var observer_mode: bool = false # 15a: live observer — full vision, input + reporting off
var spectator: Spectator = null # 15e: spectator controller (observer matches only)
var replay_mode: bool = false # 13h: local replay playback (spectator, no network)
var _mp_obs_snapshot_pending: bool = false # 15a: serve an observer snapshot at the next boundary
# Replay playback state (13h). SEEK is honest re-simulation: the
# scene reloads and the feed fast-forwards from tick 0 — there is
# no state snapshot to jump to, by design (commands only).
var _replay_cmds: Array = [] # [{from, tick, cmd}] sorted by tick
var _replay_ptr: int = 0
var _replay_next_tick: int = 1
var _replay_accum: float = 0.0
var _replay_speed: float = 1.0
var _replay_playing: bool = true
var _replay_ff: bool = false # fast-forwarding (seek catch-up)
var _replay_ended: bool = false
var _replay_final_tick: int = 0
var _replay_winner_team: int = -1
## 14a: timeline markers + follow-player slot for the viewer.
const REPLAY_SPEEDS := [0.5, 1.0, 2.0, 4.0, 8.0]
var _replay_markers: Array = [] # [{tick, kind, slot}] built in _replay_init
var _replay_follow: int = -1 # slot whose fog the view uses; -1 = full vision
var _replay_bar = null # ReplayBar (CanvasLayer), built in _ready
var local_slot: int = 0
var slot_teams: Array = [] # slot -> faction team
var slot_names: Array = []
var mp_wallets: Array = [] # slot -> resources Dictionary
var mp_ages: Array = [] # slot -> {age, researching, timer, target, duration}
var mp_techs: Array = [] # slot -> {levels: {tech id -> tier}, active: {building -> research record}}
var mp_rally: Array = [] # slot -> Vector2 rally point (ZERO = unset)
var slot_chars: Array = [] # slot -> assigned main-character id (drawn at match start; presentation + kit identity, never in checksums as a value — its EFFECTS are sim)
var slot_skins: Array = [] # slot -> active cosmetic skin id ("" = none; dormant until the shop exists)
## 16b: the (single) lingering skill zone kind — the Archer's
## Mưa Tên {kind: "arrow_rain", pos, t, acc, radius, owner,
## dmg, tick_n}. SIM state: ticks in _process on the same frame
## semantics as units, damage flows through take_damage, and
## the zone feeds the MP checksum + resync snapshot.
var skill_zones: Array = []
# --- 15b diplomacy state (Custom rooms that opted in ONLY) -----------
## Pairwise slot stances inside the lockstep sim: every change
## arrives as a command (dip_propose / dip_respond / dip_cancel /
## dip_break / dip_gift), the tables ride the resync snapshot and
## the checksum, and replay playback re-derives them from the
## command log. Defaults where the GDD is silent (KE-HOACH 15b):
## Enemy is the FFA default; downgrading a stance needs a
## declaration that matures after DIP_BREAK_SECONDS — the
## breaker cannot attack during the window and shared vision
## ends the moment the declaration lands; tribute is fee-free
## with a per-pair cooldown.
const DIP_ENEMY := 0
const DIP_NEUTRAL := 1
const DIP_ALLY := 2
const DIP_BREAK_SECONDS := 30.0
const DIP_GIFT_COOLDOWN := 30.0
const DIP_GIFT_TYPES: Array = ["food", "wood", "gold", "stone"]
var dip_enabled: bool = false # armed by the room flag + FFA shape
var dip_stance: Dictionary = {} # "a:b" (a<b) -> DIP_* (absent = ENEMY)
var dip_invites: Dictionary = {} # "from>to" -> proposed DIP_* (NEUTRAL/ALLY)
var dip_breaks: Dictionary = {} # "a:b" -> {by, to, t} declaration in flight
var dip_gift_cd: Dictionary = {} # "from>to" -> seconds left (ordered pair)
var dip_winners: Array = [] # shared allied victors, once decided
var skill_fx: SkillFX
## Local targeting state (presentation/input only): which skill
## index (2 or 3) awaits a ground click, or -1. Set by the HUD.
var skill_targeting := -1
var _shake_t := 0.0 # Vương Kiếm impact camera shake (presentation)
var _sfx_pool: Array = [] # Array[AudioStreamPlayer] on the SFX bus
var _sfx_rr := 0
var hero_zone_layer: Node2D = null # presentation: zone rings (under units)
var hero_name_layer: Node2D = null # presentation: player names over heroes (late pass)
var slot_eliminated: Array = [] # bool per slot (annihilated / dropped)
## 13z: elimination bookkeeping for free-for-all placements —
## slots in the order they fell, and the lockstep tick each fell
## on. Presentation/reporting only: placements are computed from
## this at match end; the SERVER's banked placement (referee or
## host report) is canonical, never the local banner.
var mp_elim_order: Array = [] # slot ids, first eliminated first
var mp_elim_tick: Dictionary = {} # slot -> tick it was eliminated
var _referee_disconnect_slots: Array = [] # referee: slots lost to disconnect
var slot_tc_down: Array = [] # bool per slot (TC destroyed; may fight on)
var slot_inert: Array = [] # bool per slot (disconnected mid-match: frozen)
var mp_over: bool = false
var mp_local_eliminated: bool = false
var mp_built: bool = false # MP match fully built (smoke driver waits on this)
var _net_id_seq: int = 0
var lobby = null # Lobby (created on demand by open_lobby)
var home = null # HomeLobby (13g boot screen, created on demand)

# Entry flow (13r): loading → login / welcome-back → name panel
# → home. Runs once per process on a cold, windowed SP boot.
static var _entry_booted: bool = false
var _entry_holds_home: bool = false
var _entry_boot_pending: bool = false
var _entry_state: String = "off" # loading|login|welcome|name|off
var _login_screen = null # LoginScreen
var _welcome_screen = null # WelcomeScreen
var _name_panel = null # NamePanel
var _loading_screen = null # LoadingScreen
var _login_over_home: bool = false
var _entry_wired: bool = false
var _lobby_from_home: bool = false # close_lobby returns to home, not setup

# Lockstep drive: the sim only advances in fixed steps handed out by
# server ticks (3 frames of 1/30 s per tick). Between ticks the tree
# is frozen via Engine.time_scale = 0 so two clients can never drift
# apart in frame count.
var _mp_tick_queue: Array = []
var _mp_pending_cmds: Dictionary = {} # exec_tick -> Array[{from, cmd}]
var _mp_current_tick: int = 0
var _mp_stepping: bool = false
var _mp_frames_into_tick: int = 0
var _mp_steps_done: int = 0
var _mp_checksum_due: int = -1
var _mp_last_completed: int = 0
# P4 stage 2 — resync state.
var _mp_resync_wait: bool = false # diverged: frozen until snapshot lands
var _mp_snapshot_pending: bool = false # source: snapshot due at next tick boundary
var _mp_cmd_log: Dictionary = {} # exec_tick -> Array[{from, cmd}] (for re-apply)
var mp_test_kill_tick: int = -1 # smoke-test hook (set by Net's driver)
var mp_test_hero: bool = false # skill-smoke hook: spawn both heroes mid-map
var _mp_test_hero_done := false
var mp_test_transport: bool = false # 15g smoke hook: stage trade kit per slot
var _mp_test_transport_done := false
var mp_test_kill_slot: int = -1
var mp_test_kills: Array = [] # 13z list form: [[tick, slot], ...]
# P4 stage 3 — referee bookkeeping.
var _referee_dropped: int = 0 # illegal commands dropped by the validators
var _referee_win_reason: String = "elimination"
var _referee_grace_slot: int = -1 # disconnected slot inside the 30 s grace
var _referee_grace_deadline: int = -1 # tick at which the grace expires
var _referee_reported: bool = false


func _alloc_net_id() -> int:
	_net_id_seq += 1
	return _net_id_seq


## The faction team whose eyes the local player sees through
## (fog + minimap). 0 in SP.
func view_team() -> int:
	if mp_mode and local_slot >= 0 and local_slot < slot_teams.size():
		return int(slot_teams[local_slot])
	return 0


## True when `owner` is the local human (SP: owner 0 — the player).
func is_local_owner(owner: int) -> bool:
	return owner == local_slot if mp_mode else owner == 0


## The resource ledger the HUD should display (local player's).
func display_resources() -> Dictionary:
	if mp_mode:
		return mp_wallets[local_slot]
	return resources


func wallet_of(owner: int) -> Dictionary:
	if mp_mode:
		return mp_wallets[owner]
	return resources


## Lifetime amount of `rtype` this owner has actually gathered
## (villager/ship deposits only — market trades don't count).
## SP owner 1 reads the AI ledger's owner key (team == owner in SP).
func gathered_of(owner: int, rtype: String) -> int:
	return int((gathered_totals.get(owner, {}) as Dictionary).get(rtype, 0))


func owner_age(owner: int) -> int:
	if mp_mode:
		return int(mp_ages[owner].get("age", 1))
	return age if owner == 0 else int(team_age.get(owner, 1))


## Imperial logistics: at Age IV every training queue (TC, Barracks,
## Dock) runs at Stats.IMPERIAL_TRAIN_TIME_MULT of the base time.
func train_time_mult(owner: int) -> float:
	return Stats.IMPERIAL_TRAIN_TIME_MULT if owner_age(owner) >= 4 else 1.0


## Seconds to train `kind` for `owner`: every unit takes Building
## .TRAIN_TIME except the King, whose hero muster takes
## Stats.KING_TRAIN_TIME — both scaled by Imperial logistics.
func train_time_for(owner: int, kind: String) -> float:
	var base := Stats.KING_TRAIN_TIME if kind == "king" else Building.TRAIN_TIME
	return base * train_time_mult(owner)


## Where a fleeing villager runs to: its owner's Town Center first;
## if the TC is gone, the nearest completed building that accepts
## every load (TC / Storage), else any completed drop-off for what
## it carries. Null when the owner has no drop-off left at all.
func flee_haven_for(u: Unit) -> Building:
	var tc := tc_of(u.owner_id) if mp_mode else (player_tc if u.team == 0 else enemy_tc)
	if tc != null and is_instance_valid(tc) and not tc.destroyed and tc.complete:
		return tc
	var best: Building = null
	var bd := INF
	for b in buildings:
		if b.destroyed or not b.complete:
			continue
		if (b.owner_id == u.owner_id if mp_mode else b.team == u.team) \
				and (b.btype == "town_center" or b.btype == "storage"):
			var d := u.global_position.distance_squared_to(
					b.position + Vector2(b.size) * World.TILE * 0.5)
			if d < bd:
				bd = d
				best = b
	if best != null:
		return best
	return get_dropoff_for(u.team, u.carry_type if u.carry_type != "" else "food",
			u.global_position, u.owner_id)


func team_of_slot(slot: int) -> int:
	if slot >= 0 and slot < slot_teams.size():
		return int(slot_teams[slot])
	return slot


func slot_count() -> int:
	return slot_teams.size()


## The (living) Town Center owned by a player slot, or null.
func tc_of(owner: int) -> Building:
	for b in buildings:
		if b.owner_id == owner and b.btype == "town_center" and not b.destroyed:
			return b
	return null


## Owner-routed deposit credit (P4): in MP the amount lands in the
## owning slot's wallet; in SP owner == team, so this is exactly the
## old credit_resource routing (player ledger / AI ledger).
func credit_owner(owner: int, rtype: String, amount: int) -> void:
	if amount > 0:
		var gt: Dictionary = gathered_totals.get(owner, {})
		gt[rtype] = int(gt.get(rtype, 0)) + amount
		gathered_totals[owner] = gt
	if mp_mode:
		var w: Dictionary = mp_wallets[owner]
		w[rtype] = int(w.get(rtype, 0)) + amount
		if owner == local_slot and amount > 0:
			deposit_log.append({"t": match_time, "type": rtype, "amt": amount})
			while not deposit_log.is_empty() and float(deposit_log[0].t) < match_time - 180.0:
				deposit_log.pop_front()
	else:
		credit_resource(owner, rtype, amount)


## ---------------------------------------------------------------
## 13y match statistics (presentation layer — see match_stats).
## ---------------------------------------------------------------

const STAT_KEYS: Array = ["trained", "lost", "kills", "hero_kills",
		"built", "blost", "razed", "researched", "actions"]
const STAT_RES_ALL: Array = ["food", "wood", "gold", "stone", "iron"]
const STAT_SAMPLE_PERIOD: float = 30.0


## The counter record for `owner`, created on first use.
func _stat_rec(owner: int) -> Dictionary:
	var rec: Dictionary = match_stats.get(owner, {})
	if rec.is_empty() and not match_stats.has(owner):
		for k in STAT_KEYS:
			rec[k] = 0
		match_stats[owner] = rec
	return rec


func _bump_stat(owner: int, key: String, n: int = 1) -> void:
	if owner < 0:
		return
	var rec := _stat_rec(owner)
	rec[key] = int(rec.get(key, 0)) + n
	match_stats[owner] = rec


## One counted gameplay action for APM (GDD formula: valid issued
## commands only — menu/camera/selection never reach this).
func _note_action(owner: int) -> void:
	_bump_stat(owner, "actions")


## Everything the result screen shows for one owner.
func stat_counters(owner: int) -> Dictionary:
	var rec := _stat_rec(owner)
	var gat: Dictionary = {}
	var gat_total := 0
	for r in STAT_RES_ALL:
		gat[r] = gathered_of(owner, r)
		gat_total += int(gat[r])
	return {"gathered": gat, "gathered_total": gat_total,
			"trained": int(rec.get("trained", 0)),
			"lost": int(rec.get("lost", 0)),
			"kills": int(rec.get("kills", 0)),
			"hero_kills": int(rec.get("hero_kills", 0)),
			"built": int(rec.get("built", 0)),
			"blost": int(rec.get("blost", 0)),
			"razed": int(rec.get("razed", 0)),
			"researched": int(rec.get("researched", 0)),
			"actions": int(rec.get("actions", 0))}


## Valid actions per minute over the match so far (GDD APM).
func apm_of(owner: int) -> float:
	var mins := maxf(match_time / 60.0, 0.01)
	return float(int(_stat_rec(owner).get("actions", 0))) / mins


## Owners the result screen lists: every slot in MP; the two
## SP sides (player + AI) otherwise — same convention as 13u.
func result_owners() -> Array:
	return range(slot_count()) if mp_mode else [0, 1]


## Military headcount for `owner` (the 13u scoreboard kinds —
## land units only, ships excluded exactly as in HUD stats).
func owner_military_count(owner: int) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and not u.is_dead() and u.owner_id == owner \
				and ["militia", "archer", "spearman", "cavalry", "ram"].has(u.unit_type):
			n += 1
	return n


## The transparent score, computed here so the time series and
## the result screen share one source. Mirrors HUD._owner_score
## EXACTLY (gathered/10 + 20 per soldier + 15 per standing
## building + 40 per tech tier + 100 while the hero lives) —
## the 13y tests pin the two implementations together.
func match_score_of(owner: int) -> int:
	var gathered := 0
	for r in STAT_RES_ALL:
		gathered += gathered_of(owner, r)
	var bld := 0
	for b in buildings:
		if b.owner_id == owner and b.complete and not b.destroyed:
			bld += 1
	var tiers := 0
	for tid in Stats.TECHS:
		tiers += tech_level(owner, tid)
	var score := gathered / 10 + owner_military_count(owner) * 20 \
			+ bld * 15 + tiers * 40
	if king_alive(owner):
		score += 100
	return score


## Append one time-series sample at the current match time.
func _sample_stats() -> void:
	var rows: Dictionary = {}
	for owner in result_owners():
		rows[owner] = {"score": match_score_of(owner),
				"pop": owner_pop_current(owner),
				"mil": owner_military_count(owner)}
	stat_series.append({"t": match_time, "rows": rows})
	_stat_next_sample = match_time + STAT_SAMPLE_PERIOD


## A "Về sảnh" exit from a finished (or running) match: the same
## cleanup restart_match does — drop the room and MP statics,
## then reload into the boot flow, which lands on the home lobby.
func return_to_lobby() -> void:
	if mp_mode:
		mp_active = false
		mp_config = {}
		Engine.time_scale = 1.0
		Net.leave_room()
	get_tree().reload_current_scene()


func owner_pop_current(owner: int) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.owner_id == owner and not u.is_dead():
			n += 1
	return n


func owner_pop_cap(owner: int) -> int:
	var n := 0
	for b in buildings:
		if b.owner_id == owner and b.complete and not b.destroyed:
			n += b.pop_bonus
	return n


func owner_queued(owner: int) -> int:
	var n := 0
	for b in buildings:
		if b.owner_id == owner:
			n += b.train_queue
	return n


func completed_non_tc_buildings_of(owner: int) -> int:
	var n := 0
	for b in buildings:
		# 14c: skillwall segments are obstacles, not buildings —
		# they never count toward the age-up requirement.
		if b.owner_id == owner and b.complete and not b.destroyed \
				and b.btype != "town_center" and b.btype != "skillwall":
			n += 1
	return n


func building_of_net_id(nid: int) -> Building:
	for b in buildings:
		if b.net_id == nid:
			return b
	return null


## First living building of a type owned by a slot (13v: the
## research-freeze check needs the building behind a tech record).
func _building_of_type(owner: int, btype: String) -> Building:
	for b in buildings:
		if b.owner_id == owner and b.btype == btype and not b.destroyed:
			return b
	return null


func unit_of_net_id(nid: int) -> Unit:
	for u in units:
		if u.net_id == nid:
			return u
	return null


func ship_of_net_id(nid: int) -> Ship:
	for s in ships:
		if s.net_id == nid:
			return s
	return null

# --- Biome (map theme) -------------------------------------------------------
## The match's biome is a Main-level setting: the boot map-choice
## panel writes it, "Chơi lại" (scene reload) keeps it because these
## are statics, and P4 can later pass it in from the lobby instead.
static var chosen_biome: String = "grassland"
static var chosen_layout: String = "plains"
static var map_choice_done: bool = false
var biome_id: String = "grassland" # this instance's active biome
var layout_id: String = "plains" # this instance's chosen layout


func biome_mods() -> Dictionary:
	return Biomes.data(biome_id)["mods"]


## Per-trip yield multiplier for a deposit of `rtype`; field harvests
## use the biome's field_yield instead of the bush/node yield_food.
func yield_mult(rtype: String, from_field: bool = false) -> float:
	if from_field:
		return Biomes.mod(biome_id, "field_yield")
	return Biomes.mod(biome_id, "yield_" + rtype)


## What a villager actually delivers for a carry load (biome yield
## x the OWNER's economy technologies, 13s).
func delivered_amount(carry: int, rtype: String, from_field: bool = false, owner: int = -1) -> int:
	return int(round(float(carry) * yield_mult(rtype, from_field) \
			* tech_yield_mult(owner, rtype, from_field)))


## Effective move multiplier for a unit type on this biome (cavalry
## stacks its own extra on top of the global move multiplier).
func move_mult_for(unit_type: String) -> float:
	var m := Biomes.mod(biome_id, "move")
	if unit_type == "cavalry":
		m *= Biomes.mod(biome_id, "cavalry_move")
	return m


func field_growth_mult() -> float:
	return Biomes.mod(biome_id, "field_growth")


## Seconds per field growth stage on this biome.
func field_interval() -> float:
	return Unit.TEND_TIME / maxf(field_growth_mult(), 0.05)


## Map-choice panel entry point (HUD cards / "Vào trận" call this —
## the same path the tests drive). Picking the active biome+layout
## just closes the panel; picking others restarts the match on them.
## "random" biome resolves to a concrete one per instance in _ready.
func choose_map(biome: String, layout: String) -> void:
	if not (Biomes.is_valid(biome) or biome == "random"):
		return
	if not World.is_valid_layout(layout):
		return
	chosen_biome = biome
	chosen_layout = layout
	map_choice_done = true
	if hud != null:
		hud.hide_map_panel()
	if world != null:
		world.set_sky_active(true)
	if biome != biome_id or layout != layout_id:
		# Reload only when this instance IS the running scene (in the
		# test harness the current scene is the test root — reloading
		# there would restart the harness, so tests assert the statics
		# and spawn a fresh instance instead).
		if get_tree().current_scene == self:
			restart_match()
	else:
		set_paused(false)


func choose_biome(id: String) -> void:
	choose_map(id, chosen_layout)

# Match state (HUD glass rework).
var age: int = 1 # current age (I-IV); drives building art tiers + HUD badge
var match_time: float = 0.0 # seconds since match start (frozen while paused)
var paused: bool = false
var deposit_log: Array = [] # {t, type, amt} — deposits only, drives the "+x/s" rates
## 13u: lifetime gathered totals per owner (owner -> {rtype: int}),
## counted at the single deposit funnel (credit_owner). Pure
## presentation data for the in-match statistics panel — never
## serialised into snapshots or checksums.
var gathered_totals: Dictionary = {}

## 13y: end-of-match statistics accounting (Gameplay GDD). Per
## owner counters {trained, lost, kills, hero_kills, built, blost,
## razed, researched, actions} bumped at the same choke points the
## 13u statistics used plus death / train-complete /
## research-complete / command-apply hooks. Like gathered_totals
## this is PRESENTATION data: it never enters the sim, snapshots
## or checksums (in MP every client applies the same command
## stream and sees the same deaths, so the numbers agree anyway).
var match_stats: Dictionary = {} # owner -> counter Dictionary
## 13y: score-over-time series for the result screen — one sample
## every 30 game-seconds: {t, rows: {owner: {score, pop, mil}}}.
var stat_series: Array = []
var _stat_next_sample: float = 0.0
## 13y: replay id the server pushed for THIS match (custom rooms
## send `custom_replay` once the recording is banked); "" while
## no replay exists — the result screen's Xem lại button keys
## off it and stays hidden otherwise.
var match_replay_id: String = ""
## 13y: the local player ended this match by surrendering (the
## result banner reads ĐẦU HÀNG, not THUA).
var local_surrendered: bool = false

var enemy_tc_destroyed: bool = false # set by on_building_destroyed (P3)
var player_tc_destroyed: bool = false # set by on_building_destroyed
## Annihilation (quét sạch): a side whose TC is down is eliminated
## only when it also has no living villagers OR no completed
## train-capable building (Barracks / Dock) — see _side_annihilated.
var sp_enemy_eliminated: bool = false
var sp_player_eliminated: bool = false # latches: elimination fires once
var end_note: String = "" # subtitle for the end panel (e.g. quét sạch)
var rally_point: Vector2 = Vector2.ZERO # where newly trained villagers walk to
var rally_setting: bool = false # next map click sets the rally point

var world: World
var cam: RTSCamera
var hud: HUD
var overlay: Overlay
var vfx: VFX
var fog: Fog
var enemy_ai: EnemyAI

# --- P3 state ---------------------------------------------------------------
var match_over: String = "" # "" | "victory" | "defeat"
var team_age: Dictionary = {0: 1, 1: 1} # per-team age (player age mirrors `age`)
var age_researching: bool = false
var age_timer: float = 0.0
var age_target: int = 2 # age the current research reaches (2 or 3)
var age_duration: float = 60.0 # duration of the current research
# Technologies (13s, AoE-pattern — Stats.TECHS): SP player state;
# MP keeps the same shape per slot in mp_techs. `tech_active` maps
# a building type to its one running research {id, tier, timer,
# duration} (one research per building, like AoE).
var tech_levels: Dictionary = {} # tech id -> researched tier
var tech_active: Dictionary = {} # building type -> research record

# Farm fields (self-drawn pass).
var fields: Array = [] # Array[FieldPlot]
var placing_field: bool = false
var _field_cell := Vector2i(-1, -1)
var _field_valid: bool = false
var projectiles: Array = [] # {spr, target, dmg, attacker, team, aim, trail_t}
var _arrow_tex: Texture2D = null

var units: Array = []
var ships: Array = [] # Ship (both teams; minimap/fog filter by team)
var buildings: Array = []
var selection: Array = []
var selected_building: Building = null
var selected_ship: Ship = null
var player_tc: Building
var enemy_tc: Building

# Placement mode.
var placing_type: String = ""
var _placing_cell := Vector2i(-1, -1)
var _placing_valid := false

# Input state.
var _lmb_down := false
var _drag_start := Vector2.ZERO
var _drag_cur := Vector2.ZERO
var _dragging_box := false
var _press_msec := 0
var _press_pos := Vector2.ZERO
var _long_fired := false
var _was_double := false
var _rmb_down := false
var _rmb_press_pos := Vector2.ZERO
var _rmb_moved := false


class Overlay:
	extends Node2D
	var game = null

	func _draw() -> void:
		if game == null:
			return
		if game._dragging_box:
			var r := Rect2(game._drag_start, game._drag_cur - game._drag_start).abs()
			draw_rect(r, Color(0.4, 1.0, 0.4, 0.16))
			draw_rect(r, Color(0.4, 1.0, 0.4, 0.9), false, 1.5)
		if game.placing_type != "" and game._placing_cell.x >= 0:
			var def: Dictionary = game.get_build_def(game.placing_type)
			var rect := Rect2(Vector2(game._placing_cell) * World.TILE, Vector2(def.size) * World.TILE)
			var col := Color(0.3, 1.0, 0.3, 0.35) if game._placing_valid else Color(1.0, 0.3, 0.3, 0.35)
			var btex: Texture2D = Building.tier_texture(game.placing_type, game.age,
					game.local_slot if game.mp_mode else 0)
			if btex != null:
				# Ghost previews the actual tier art at the in-game scale
				# (1.5x footprint, bottom-anchored), tinted by validity.
				var tint := Color(0.55, 1.0, 0.55, 0.6) if game._placing_valid else Color(1.0, 0.5, 0.5, 0.6)
				var arect := Building.art_rect(def.size, btex)
				arect.position += rect.position
				draw_texture_rect(btex, arect, false, tint)
			else:
				draw_rect(rect, col)
			draw_rect(rect, col.lightened(0.5), false, 2.0)
		if game.placing_field and game._field_cell.x >= 0:
			var frect := Rect2(Vector2(game._field_cell) * World.TILE, Vector2.ONE * World.TILE)
			var fcol := Color(0.3, 1.0, 0.3, 0.35) if game._field_valid else Color(1.0, 0.3, 0.3, 0.35)
			draw_rect(frect, fcol)
			draw_rect(frect, fcol.lightened(0.5), false, 2.0)
		# Rally point flag (player Town Center).
		if game.rally_point != Vector2.ZERO:
			var rp: Vector2 = game.rally_point
			var flag_col := Color(1.0, 0.85, 0.3) if game.rally_setting \
					else TeamColors.ui_color(game.local_slot if game.mp_mode else 0)
			draw_line(rp + Vector2(0, 2), rp + Vector2(0, -24), Color(0.92, 0.88, 0.8), 2.0)
			draw_colored_polygon(PackedVector2Array([rp + Vector2(0, -24), rp + Vector2(13, -19.5), rp + Vector2(0, -15)]), flag_col)
			draw_circle(rp, 3.0, Color(1, 1, 1, 0.8))


func get_build_def(btype: String) -> Dictionary:
	return BUILD_DEFS[btype]


# ============================================================
# P4 multiplayer core: slot setup, base spawn, tick-stepped
# lockstep drive, command application, checksums, elimination.
# ============================================================

func _mp_setup_slots() -> void:
	local_slot = Net.my_slot
	if referee_mode or replay_mode or observer_mode:
		# The referee holds no player slot; it views through slot 0
		# (fog/HUD are cosmetic headless) and owns every slot's sim.
		# Replay playback borrows the same seat (spectator), and so
		# does a live observer (15a) — except the observer's sim is
		# driven by the live relay, never by local input.
		local_slot = 0
		if observer_mode and Net.obs_needs_snapshot:
			# Mid-match join: freeze at the freshly spawned tick-0
			# state until the host's snapshot rebuild lands (the
			# exact posture of a resync-diverged client).
			_mp_resync_wait = true
		if referee_mode and Net.referee_kill_tick >= 0:
			mp_test_kill_tick = Net.referee_kill_tick
			mp_test_kill_slot = Net.referee_kill_slot
		if referee_mode and not Net.referee_kills.is_empty():
			mp_test_kills = Net.referee_kills.duplicate()
	var players: Array = mp_config.get("players", [])
	var ordered := players.duplicate()
	ordered.sort_custom(func(a, b): return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	for p in ordered:
		slot_teams.append(int(p.get("team", int(p.get("slot", 0)))))
		slot_names.append(str(p.get("name", "Người chơi")))
		slot_chars.append(Characters.normalize_char(str(p.get("char", ""))))
		slot_skins.append(Characters.normalize_skin(str(p.get("skin", ""))))
		print("MPLOG in-match chars slot=", int(p.get("slot", 0)),
				" char=", slot_chars[slot_chars.size() - 1],
				" skin=", slot_skins[slot_skins.size() - 1])
		mp_wallets.append({"food": 200, "wood": 200, "gold": 100, "stone": 0, "iron": 0})
		mp_ages.append({"age": 1, "researching": false, "timer": 0.0, "target": 1, "duration": 0.0})
		mp_techs.append({"levels": {}, "active": {}})
		mp_rally.append(Vector2.ZERO)
		slot_eliminated.append(false)
		slot_tc_down.append(false)
		slot_inert.append(false)
	mp_elim_order.clear()
	mp_elim_tick.clear()
	_referee_disconnect_slots.clear()
	team_age.clear()
	for t in slot_teams:
		team_age[t] = 1
	_dip_setup() # 15b: arm diplomacy from the room flag (+ FFA shape)
	# The sim starts frozen; the tick drive releases frames.
	Engine.time_scale = 0.0


## Spawn one base per slot (TC + 3 villagers + 1 scout cavalry +
## rally) at the world's base centres; SP spawn code stays
## untouched elsewhere.
func _mp_spawn_bases() -> void:
	for slot in range(slot_count()):
		var centre: Vector2i = world.base_centres[slot]
		var tc := _spawn_building("town_center", team_of_slot(slot),
				centre - Vector2i(1, 1), true, slot)
		var rally := centre
		for off in [Vector2i(3, 2), Vector2i(3, 1), Vector2i(3, 0),
				Vector2i(2, 3), Vector2i(1, 3), Vector2i(0, 3)]:
			var c: Vector2i = centre - Vector2i(1, 1) + off
			if not world.is_solid(c) and not world.water.has(c):
				rally = c
				break
		mp_rally[slot] = world.cell_center(rally)
		var spots: Array = world.adjacent_walkable(tc.cells())
		for i in 3:
			var spot: Vector2i = spots[i % spots.size()] if not spots.is_empty() else centre
			# _make_unit parents the unit and appends it to `units`
			# itself — doing either again here would double-register
			# the villager (a dangling duplicate once it dies).
			_make_unit(team_of_slot(slot), world.cell_center(spot),
					"villager", slot)
		# Match-start flow: ONE scout cavalry per player.
		var scout_spot: Vector2i = spots[3 % spots.size()] if not spots.is_empty() else centre
		_make_unit(team_of_slot(slot), world.cell_center(scout_spot),
				"cavalry", slot)
		if slot == local_slot:
			player_tc = tc
	if enemy_tc == null:
		for slot in range(slot_count()):
			if team_of_slot(slot) != view_team():
				enemy_tc = tc_of(slot)
				break
	var ltc := tc_of(local_slot)
	if ltc != null:
		cam.focus_on(ltc.position + Vector2(ltc.size) * World.TILE * 0.5)


func _mp_bind_net() -> void:
	if replay_mode:
		return # ticks + commands come from the local replay feed
	Net.tick_received.connect(_mp_on_tick)
	Net.command_received.connect(_mp_on_command)
	Net.player_left.connect(_mp_on_player_left)
	Net.desync_notice.connect(_mp_on_desync)
	Net.connection_closed.connect(_mp_on_connection_closed)
	Net.chat_received.connect(_mp_on_chat)
	Net.resync_started.connect(_mp_on_resync_started)
	Net.resync_notice_received.connect(_mp_on_resync_notice)
	Net.snapshot_requested.connect(_mp_on_snapshot_requested)
	Net.snapshot_received.connect(_mp_apply_snapshot)
	Net.resync_failed_notice.connect(_mp_on_resync_failed)
	Net.rank_result_received.connect(_mp_on_rank_result)
	Net.obs_snapshot_requested.connect(_mp_on_obs_snapshot_requested)
	if observer_mode and Net.obs_needs_snapshot and hud != null:
		hud.show_sync_overlay(true) # "đang đồng bộ" while the snapshot flies
		Net.send_obs_ready() # server asks the host for our snapshot now


## The server pushes our own ladder movement right after banking
## a ranked result (it can land just after the end panel opens —
## the HUD updates its rank lines in place).
func _mp_on_rank_result(info: Dictionary) -> void:
	if hud != null and hud.has_method("set_rank_result"):
		hud.set_rank_result(info)
	if mp_debug_log:
		print("MPLOG rank panel delta=", int(info.get("star_delta", 0)),
				" promoted=", bool(info.get("promoted", false)),
				" after=", String(info.get("after", {}).get("rank_text", "")))


## Commands sent while this client waits for a resync snapshot are
## dropped (input is locked): they could never be applied in the
## same order on the rebuilt sim.
func _mp_send_command(cmd: Dictionary) -> void:
	if observer_mode:
		return # 15a: observers never issue commands (server also rejects)
	if _mp_resync_wait:
		return
	Net.send_command(cmd)


## True when any other slot shares this client's team (2v2). FFA
## and 1v1 have no allies — HUD hides the team chat scope then.
func mp_has_allies() -> bool:
	var seen := {}
	for t in slot_teams:
		if seen.has(t):
			return true
		seen[t] = true
	return false


# --- 15b diplomacy ------------------------------------------------------

func _dip_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## (Re)build the diplomacy tables for the current slot set. The
## room flag alone is not enough: a room whose setup already
## fixes teams (2v2 — any two slots sharing a team) keeps fixed
## teams and diplomacy stays inert (task build rule 6).
func _dip_setup() -> void:
	dip_stance.clear()
	dip_invites.clear()
	dip_breaks.clear()
	dip_gift_cd.clear()
	dip_winners.clear()
	dip_enabled = false
	if not bool(mp_config.get("diplomacy", false)):
		return
	var seen := {}
	for t in slot_teams:
		if seen.has(int(t)):
			return
		seen[int(t)] = true
	dip_enabled = true


func diplomacy_active() -> bool:
	return mp_mode and dip_enabled


## The pairwise stance between two slots (ENEMY when nothing was
## ever agreed). Only meaningful while diplomacy_active().
func stance_of(a: int, b: int) -> int:
	if a == b:
		return DIP_ALLY
	return int(dip_stance.get(_dip_key(a, b), DIP_ENEMY))


func dip_stance_text(s: int) -> String:
	match s:
		DIP_NEUTRAL:
			return "Trung lập"
		DIP_ALLY:
			return "Đồng minh"
	return "Kẻ địch"


## The pending break declaration on a pair, or {} — {by, to, t}.
func dip_break_on(a: int, b: int) -> Dictionary:
	return dip_breaks.get(_dip_key(a, b), {})


## True while `a` has a live declaration against `b`.
func _dip_breaking_by(a: int, b: int) -> bool:
	var br: Dictionary = dip_breaks.get(_dip_key(a, b), {})
	return not br.is_empty() and int(br.get("by", -1)) == a


## Allied for protection/victory purposes: same slot, same fixed
## team outside diplomacy, or a live ALLY stance inside it. A
## pending break does NOT end the alliance until it matures —
## but it ends vision at once (dip_vision_shared).
func owners_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	if diplomacy_active():
		return stance_of(a, b) == DIP_ALLY
	return team_of_slot(a) == team_of_slot(b)


## Shared vision (fog union) between two slots: an ALLY stance
## with NO declaration in flight — vision ends the moment a
## break is declared, a full window before the stance falls.
func dip_vision_shared(a: int, b: int) -> bool:
	if a == b:
		return true
	if not diplomacy_active():
		return team_of_slot(a) == team_of_slot(b)
	return stance_of(a, b) == DIP_ALLY and dip_break_on(a, b).is_empty()


## May `a`'s forces DELIBERATELY attack `b`'s (manual orders,
## skills, projectiles in flight)? Inside diplomacy: never an
## ally (a pending break keeps the stance, so the whole window
## is covered) and never while `a`'s own declaration is in
## flight; neutrals may be attacked on order (genre convention).
## Outside diplomacy this is exactly the old team test.
func attack_allowed(a: int, b: int) -> bool:
	if a == b:
		return false
	if diplomacy_active():
		if _dip_breaking_by(a, b):
			return false
		return stance_of(a, b) != DIP_ALLY
	return team_of_slot(a) != team_of_slot(b)


## May `a`'s forces AUTO-engage `b`'s (guard acquisition, tower
## fire, ship scans)? Inside diplomacy only a true ENEMY is fair
## game — neutrals are left alone until ordered otherwise.
func auto_engage_allowed(a: int, b: int) -> bool:
	if a == b:
		return false
	if diplomacy_active():
		if _dip_breaking_by(a, b):
			return false
		return stance_of(a, b) == DIP_ENEMY
	return team_of_slot(a) != team_of_slot(b)


## Slots currently holding an ALLY stance with `slot`.
func dip_allies_of(slot: int) -> Array:
	var out: Array = []
	if not diplomacy_active():
		return out
	for s in range(slot_count()):
		if s != slot and stance_of(slot, s) == DIP_ALLY:
			out.append(s)
	return out


## The stance `from` has proposed to `to` and awaits an answer
## (-1 = no live invite).
func dip_invite_from(from: int, to: int) -> int:
	return int(dip_invites.get("%d>%d" % [from, to], -1))


## Diplomacy events are sim events: every client applies the same
## command on the same tick, so every client prints the same
## system line into its chat log. Presentation only — the state
## itself lives in the tables above.
func _dip_notice(text: String, actor: int) -> void:
	if hud != null:
		hud.add_chat_line("Hệ thống", text, "match", actor)
	if mp_debug_log:
		print("MPLOG dip event ", text)


## The ONLY writer of the stance table. A transition clears the
## pair's invites and any live attack orders between them (an
## army stops mid-swing when peace lands; a fresh enemy must be
## ordered again once a declaration matures).
func _dip_set_stance(a: int, b: int, stance: int) -> void:
	if stance == DIP_ENEMY:
		dip_stance.erase(_dip_key(a, b))
	else:
		dip_stance[_dip_key(a, b)] = stance
	dip_invites.erase("%d>%d" % [a, b])
	dip_invites.erase("%d>%d" % [b, a])
	_dip_clear_pair_targets(a, b)
	if stance == DIP_ALLY:
		_mp_check_winner()


func _dip_clear_pair_targets(a: int, b: int) -> void:
	for u in units:
		if u.is_dead() or u.attack_target == null \
				or not is_instance_valid(u.attack_target):
			continue
		var t = u.attack_target
		if not (t is Unit or t is Building or t is Ship):
			continue
		if (u.owner_id == a and int(t.owner_id) == b) \
				or (u.owner_id == b and int(t.owner_id) == a):
			u.attack_target = null
			if u.state == "to_attack" or u.state == "attack":
				u.state = "idle"
	for s in ships:
		if s.is_dead() or s.attack_target == null \
				or not is_instance_valid(s.attack_target):
			continue
		var t2 = s.attack_target
		if not (t2 is Unit or t2 is Building or t2 is Ship):
			continue
		if (s.owner_id == a and int(t2.owner_id) == b) \
				or (s.owner_id == b and int(t2.owner_id) == a):
			s.attack_target = null
			if s.state == "to_attack" or s.state == "attack":
				s.state = "idle"


func _dip_pair_ok(a: int, b: int) -> bool:
	return diplomacy_active() and a != b and b >= 0 and b < slot_count() \
			and not slot_eliminated[a] and not slot_eliminated[b]


func _mp_apply_dip_propose(from: int, to: int, stance: int) -> bool:
	if not _dip_pair_ok(from, to):
		return false
	if stance != DIP_NEUTRAL and stance != DIP_ALLY:
		return false
	if stance <= stance_of(from, to):
		return false # proposals only RAISE; drops go through declarations
	if not dip_break_on(from, to).is_empty():
		return false # a declaration is in flight on this pair
	if dip_invite_from(to, from) == stance:
		# Both sides proposed the same rise independently: that
		# IS the acceptance — the stance lands at once.
		_dip_notice("%s và %s nay là %s" % [
			_player_display_name(from), _player_display_name(to),
			dip_stance_text(stance)], from)
		_dip_set_stance(from, to, stance)
		return true
	dip_invites["%d>%d" % [from, to]] = stance
	_dip_notice("%s đề nghị %s với %s" % [
		_player_display_name(from), dip_stance_text(stance),
		_player_display_name(to)], from)
	return true


func _mp_apply_dip_respond(from: int, proposer: int, accept: bool) -> bool:
	if not _dip_pair_ok(from, proposer):
		return false
	var offered := dip_invite_from(proposer, from)
	if offered < 0:
		return false
	dip_invites.erase("%d>%d" % [proposer, from])
	if accept:
		_dip_notice("%s chấp nhận làm %s với %s" % [
			_player_display_name(from), dip_stance_text(offered),
			_player_display_name(proposer)], from)
		_dip_set_stance(from, proposer, offered)
	else:
		_dip_notice("%s từ chối đề nghị của %s" % [
			_player_display_name(from), _player_display_name(proposer)], from)
	return true


func _mp_apply_dip_cancel(from: int, to: int) -> bool:
	if not _dip_pair_ok(from, to):
		return false
	if dip_invite_from(from, to) < 0:
		return false
	dip_invites.erase("%d>%d" % [from, to])
	_dip_notice("%s hủy đề nghị với %s" % [
		_player_display_name(from), _player_display_name(to)], from)
	return true


## A declaration to DROP the stance by one step (ALLY→NEUTRAL,
## NEUTRAL→ENEMY): vision sharing ends NOW (dip_vision_shared
## reads the declaration), the breaker cannot attack during the
## window, and the new stance lands when the timer matures in
## _update_diplomacy. Both armies stand down at the declaration.
func _mp_apply_dip_break(from: int, to: int) -> bool:
	if not _dip_pair_ok(from, to):
		return false
	var cur := stance_of(from, to)
	if cur == DIP_ENEMY:
		return false # nothing to break
	if not dip_break_on(from, to).is_empty():
		return false
	dip_invites.erase("%d>%d" % [from, to])
	dip_invites.erase("%d>%d" % [to, from])
	dip_breaks[_dip_key(from, to)] = {
		"by": from, "to": cur - 1, "t": DIP_BREAK_SECONDS}
	_dip_clear_pair_targets(from, to)
	_dip_notice("%s tuyên bố cắt đứt với %s — hiệu lực sau %d giây" % [
		_player_display_name(from), _player_display_name(to),
		int(DIP_BREAK_SECONDS)], from)
	return true


## Tribute: ally-or-neutral only, fee-free, one transfer per
## ordered pair per DIP_GIFT_COOLDOWN (chosen defaults — the
## GDD is silent). Atomic debit/credit inside the sim; the
## sender's balance can never go negative.
func _mp_apply_dip_gift(from: int, to: int, rtype: String, amount: int) -> bool:
	if not _dip_pair_ok(from, to):
		return false
	if not DIP_GIFT_TYPES.has(rtype) or amount <= 0:
		return false
	if stance_of(from, to) == DIP_ENEMY:
		return false
	if float(dip_gift_cd.get("%d>%d" % [from, to], 0.0)) > 0.0:
		return false
	var w: Dictionary = mp_wallets[from]
	if int(w.get(rtype, 0)) < amount:
		return false
	w[rtype] = int(w[rtype]) - amount
	var tw: Dictionary = mp_wallets[to]
	tw[rtype] = int(tw.get(rtype, 0)) + amount
	dip_gift_cd["%d>%d" % [from, to]] = DIP_GIFT_COOLDOWN
	_dip_notice("%s tặng %s %d %s" % [
		_player_display_name(from), _player_display_name(to), amount,
		String(RES_VN.get(rtype, rtype))], from)
	return true


## Diplomacy timers (declaration windows + tribute cooldowns)
## tick with the sim beside the skill-wall timers: identical
## frame semantics, so every peer matures a declaration on the
## same step. A matured declaration lands its stance at once.
func _update_diplomacy(delta: float) -> void:
	if not diplomacy_active():
		return
	var cooled: Array = []
	for k in dip_gift_cd.keys():
		if float(dip_gift_cd[k]) - delta <= 0.0:
			cooled.append(k)
		else:
			dip_gift_cd[k] = float(dip_gift_cd[k]) - delta
	for k in cooled:
		dip_gift_cd.erase(k)
	var matured: Array = []
	for k in dip_breaks.keys():
		var br: Dictionary = dip_breaks[k]
		br["t"] = float(br["t"]) - delta
		dip_breaks[k] = br
		if float(br["t"]) <= 0.0:
			matured.append(k)
	for k in matured:
		var br2: Dictionary = dip_breaks[k]
		dip_breaks.erase(k)
		var parts := String(k).split(":")
		_dip_set_stance(int(parts[0]), int(parts[1]), int(br2["to"]))
		_dip_notice("Tuyên bố cắt đứt giữa %s và %s đã có hiệu lực" % [
			_player_display_name(int(parts[0])),
			_player_display_name(int(parts[1]))], int(br2["by"]))


## Snapshot restore for the diplomacy tables (values arrive
## JSON-shaped after a relay hop, so every number is coerced
## back to its sim type here).
func _dip_restore(st: Dictionary) -> void:
	dip_stance.clear()
	dip_invites.clear()
	dip_breaks.clear()
	dip_gift_cd.clear()
	dip_winners.clear()
	if not st.has("dip"):
		return
	var d: Dictionary = st["dip"]
	for k in (d.get("stance", {}) as Dictionary).keys():
		dip_stance[k] = int((d["stance"] as Dictionary)[k])
	for k in (d.get("invites", {}) as Dictionary).keys():
		dip_invites[k] = int((d["invites"] as Dictionary)[k])
	for k in (d.get("breaks", {}) as Dictionary).keys():
		var br: Dictionary = (d["breaks"] as Dictionary)[k]
		dip_breaks[k] = {"by": int(br["by"]), "to": int(br["to"]),
				"t": float(br["t"])}
	for k in (d.get("gift_cd", {}) as Dictionary).keys():
		dip_gift_cd[k] = float((d["gift_cd"] as Dictionary)[k])
	for w in d.get("winners", []):
		dip_winners.append(int(w))


## The local player's diplomacy orders (HUD buttons + the smoke
## driver): MP routes through the lockstep command pipeline like
## every other order. There is no SP diplomacy — the panel and
## these entries exist only in diplomacy matches.
func diplomacy_local_propose(to: int, stance: int) -> void:
	if diplomacy_active() and not observer_mode and not replay_mode:
		_mp_send_command({"kind": "dip_propose", "to": to, "stance": stance})


func diplomacy_local_respond(to: int, accept: bool) -> void:
	if diplomacy_active() and not observer_mode and not replay_mode:
		_mp_send_command({"kind": "dip_respond", "to": to, "accept": accept})


func diplomacy_local_cancel(to: int) -> void:
	if diplomacy_active() and not observer_mode and not replay_mode:
		_mp_send_command({"kind": "dip_cancel", "to": to})


func diplomacy_local_break(to: int) -> void:
	if diplomacy_active() and not observer_mode and not replay_mode:
		_mp_send_command({"kind": "dip_break", "to": to})


func diplomacy_local_gift(to: int, rtype: String, amount: int) -> void:
	if diplomacy_active() and not observer_mode and not replay_mode:
		_mp_send_command({"kind": "dip_gift", "to": to, "rtype": rtype,
				"amt": amount})


func _player_display_name(slot: int) -> String:
	for p in Net.players:
		if int(p.get("slot", -1)) == slot:
			return String(p.get("name", "Người chơi %d" % (slot + 1)))
	return "Người chơi %d" % (slot + 1)


func _mp_on_chat(scope: String, from_slot: int, sender_name: String, text: String) -> void:
	# "alliance" (17a) is the lobby guild channel: the alliance
	# screen owns it — it never lands in a match's chat or toast.
	if scope == "lobby" or scope == "alliance" or hud == null:
		return
	# 15b: in a diplomacy match the team channel belongs to the
	# CURRENT alliance — a sender who is not (or no longer) our
	# ally never lands in our Đội channel, even if a stale or
	# forged target list routed the line to us.
	if scope == "team" and diplomacy_active() and from_slot != local_slot \
			and stance_of(local_slot, from_slot) != DIP_ALLY:
		return
	hud.add_chat_line(sender_name, text, scope, from_slot)
	if not hud.is_chat_open() and from_slot != local_slot:
		hud.show_message("%s: %s" % [sender_name, text])


func _mp_on_resync_started(tick: int, source_slot: int) -> void:
	_mp_resync_wait = true
	if hud != null:
		hud.show_sync_overlay(true)
	if mp_debug_log:
		print("MPLOG resync started tick=", tick, " source=", source_slot, " slot=", local_slot)


func _mp_on_resync_notice(slots: Array) -> void:
	if hud == null or slots.is_empty():
		return
	hud.show_message("%s đang đồng bộ lại" % _player_display_name(int(slots[0])))


func _mp_on_snapshot_requested(_tick: int) -> void:
	_mp_snapshot_pending = true
	if mp_debug_log:
		print("MPLOG snapshot requested; serving at next boundary, slot=", local_slot)


func _mp_on_resync_failed(tick: int) -> void:
	_mp_resync_wait = false
	if hud != null:
		hud.show_sync_overlay(false)
		hud.show_message("Đồng bộ lại thất bại — trận có thể lệch (tick %d)" % tick)
	if mp_debug_log:
		print("MPLOG resync failed tick=", tick, " slot=", local_slot)


func _prune_cmd_log() -> void:
	var floor_tick := _mp_last_completed - 400
	for k in _mp_cmd_log.keys():
		if int(k) < floor_tick:
			_mp_cmd_log.erase(k)


func _mp_serve_snapshot() -> void:
	_mp_snapshot_pending = false
	var st := _mp_snapshot_state()
	st["tick"] = _mp_last_completed
	Net.send_snapshot(_mp_last_completed, st)
	if mp_debug_log:
		print("MPLOG snapshot sent tick=", _mp_last_completed, " slot=", local_slot)


## 15a: the server asked this client (the host) to serve a
## snapshot to a mid-match observer. Same state builder as the
## resync snapshot, but through the dedicated obs channel and
## at the same tick boundaries.
func _mp_on_obs_snapshot_requested() -> void:
	if observer_mode or referee_mode or replay_mode:
		return
	_mp_obs_snapshot_pending = true
	if mp_debug_log:
		print("MPLOG obs snapshot requested; serving at next boundary, slot=", local_slot)


func _mp_serve_obs_snapshot() -> void:
	_mp_obs_snapshot_pending = false
	var st := _mp_snapshot_state()
	st["tick"] = _mp_last_completed
	Net.send_obs_snapshot(_mp_last_completed, st)
	if mp_debug_log:
		print("MPLOG obs snapshot served tick=", _mp_last_completed, " slot=", local_slot)


# ============================================================
# Resync snapshots (P4 stage 2)
# ============================================================
## Full sim state at a tick boundary, "v":1. Extends the checksum
## field set with everything needed to resume sensibly: task
## essentials for units/ships (a mid-path unit restarts its path
## from its position; a mid-task unit is re-ordered onto its task
## target), build queues, ship cargo, beast wander RNG (as a
## string — the 64-bit PCG state would lose bits as a JSON
## number). NOT serialized (transient, no sim effect): projectiles
## in flight, decorative animals, VFX, selection; fog is
## recomputed from positions.

func _mp_unit_record(u: Unit) -> Dictionary:
	var rec := {"id": u.net_id, "type": u.unit_type, "owner": u.owner_id,
		"team": u.team, "x": u.global_position.x, "y": u.global_position.y,
		"hp": u.hp, "carry_type": u.carry_type, "carry_amt": u.carry_amount,
		"gather_t": u.gather_timer, "tend_t": u.tend_timer,
		"atk_cd": u._atk_cd, "no_flee": u.no_flee_timer,
		# Skill state: the ONE skill's cooldown, shield pool +
		# its lifetime, hard-control timers, the Khiên Sư Tử taunt.
		"scd": u.skill_cd_t,
		"shield": u.shield_hp, "shield_t": u.shield_t,
		"stun": u.stun_t, "frozen": u.frozen_t,
		"taunt_t": u.taunt_t, "taunt_id": u.taunt_id,
		"flurry": u.flurry_left, "flurry_t": u.flurry_t,
		"flurry_c": u.flurry_cursor,
		"guard": [u.guard_pos.x, u.guard_pos.y], "task": null}
	# 15g transport state: a cart's route (market net ids, leg,
	# locked payout) and a wagon's passengers (full unit records,
	# the Transport Ship cargo pattern — passengers are out of
	# game.units, so they can only ride inside the carrier's own
	# record).
	if u.unit_type == "cart":
		rec["trade_home"] = u.trade_home.net_id if u.trade_home != null else -1
		rec["trade_tgt"] = u.trade_target.net_id if u.trade_target != null else -1
		rec["trade_leg"] = u.trade_leg
		rec["trade_gold"] = u.trade_gold
		rec["trade_loaded"] = u.trade_loaded
	elif u.unit_type == "wagon":
		var cargo_recs: Array = []
		for cu in u.cargo:
			if not cu.is_dead():
				cargo_recs.append(_mp_unit_record(cu))
		rec["cargo"] = cargo_recs
	if u.garrisoned and u.flee_haven != null:
		rec["task"] = {"k": "garrison", "haven": u.flee_haven.net_id,
			"flee_t": u.flee_timer}
	elif u.state == "return":
		rec["task"] = {"k": "return"}
	elif u.target_node != null and (u.state == "to_node" or u.state == "gather"):
		rec["task"] = {"k": "node",
			"cell": [u.target_node.cell.x, u.target_node.cell.y]}
	elif u.target_field != null and (u.state == "to_field" or u.state == "tend"):
		rec["task"] = {"k": "field",
			"cell": [u.target_field.cell.x, u.target_field.cell.y]}
	elif u.target_site != null and (u.state == "to_build" or u.state == "build"):
		rec["task"] = {"k": "site", "id": u.target_site.net_id}
	elif u.attack_target != null and is_instance_valid(u.attack_target) \
			and (u.state == "to_attack" or u.state == "attack"):
		if u.attack_target is Beast:
			var ba: Vector2 = (u.attack_target as Beast).anchor
			rec["task"] = {"k": "attack_beast", "anchor": [ba.x, ba.y]}
		else:
			rec["task"] = {"k": "attack", "id": u.attack_target.net_id}
	elif (u.state == "flee" or u.state == "move") and not u.path.is_empty():
		var dc: Vector2i = world.world_to_cell(u.path[u.path.size() - 1])
		rec["task"] = {"k": "move", "cell": [dc.x, dc.y]}
	# 15g tasks override the generic ones above: a mid-route cart
	# re-paths its current leg; a wagon rolling to an unload keeps
	# its destination marker.
	if u.unit_type == "cart" and (u.state == "trade_out" or u.state == "trade_back"):
		rec["task"] = {"k": "trade"}
	elif u.unit_type == "wagon" and u.unload_cell.x >= 0:
		rec["task"] = {"k": "wagon_unload",
			"cell": [u.unload_cell.x, u.unload_cell.y]}
	return rec


func _mp_snapshot_skill_zones() -> Array:
	var out: Array = []
	for z in skill_zones:
		out.append({"kind": String(z["kind"]),
				"x": float((z["pos"] as Vector2).x),
				"y": float((z["pos"] as Vector2).y),
				"t": float(z["t"]), "acc": float(z["acc"]),
				"tick_n": int(z.get("tick_n", 0)),
				"dmg": float(z.get("dmg", 0.0)),
				"radius": float(z["radius"]), "owner": int(z["owner"])})
	return out


## First origin (ring scan out from `near`) where a 3x3 building
## fits — the deterministic placement the smoke hooks use (the
## same scan on every client lands on the same cell).
func _test_spot_near(near: Vector2i) -> Vector2i:
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := near + Vector2i(dx, dy)
				if world.can_place(cand, Vector2i(3, 3)):
					return cand
	return Vector2i(-1, -1)


func _mp_snapshot_state() -> Dictionary:
	var st := {"v": 1, "net_id_seq": _net_id_seq,
		"wallets": mp_wallets.duplicate(true), "ages": mp_ages.duplicate(true),
		"techs": mp_techs.duplicate(true),
		"rally": [], "eliminated": slot_eliminated.duplicate(),
		"tc_down": slot_tc_down.duplicate(), "inert": slot_inert.duplicate()}
	for s in range(slot_count()):
		var rp: Vector2 = mp_rally[s]
		st["rally"].append([rp.x, rp.y])
	var units_arr: Array = []
	for u in units:
		if not u.is_dead():
			units_arr.append(_mp_unit_record(u))
	st["units"] = units_arr
	# 16b: lingering skill zones are sim state — a resync rebuilds
	# the Archer's arrow rain exactly (hero cooldowns and timed
	# effects ride the unit records above).
	st["skill_zones"] = _mp_snapshot_skill_zones()
	# 15b: diplomacy tables (only an armed match carries any).
	if dip_enabled:
		st["dip"] = {"stance": dip_stance.duplicate(true),
			"invites": dip_invites.duplicate(true),
			"breaks": dip_breaks.duplicate(true),
			"gift_cd": dip_gift_cd.duplicate(true),
			"winners": dip_winners.duplicate()}
	var b_arr: Array = []
	for b in buildings:
		if b.destroyed:
			continue
		b_arr.append({"id": b.net_id, "type": b.btype, "owner": b.owner_id,
			"team": b.team, "cell": [b.origin_cell.x, b.origin_cell.y],
			"hp": b.hp, "complete": b.complete, "progress": b.progress,
			"train": b.train_types.duplicate(), "train_t": b.train_timer,
			"wall_var": b.wall_variant})
	st["buildings"] = b_arr
	var s_arr: Array = []
	for s in ships:
		if s.is_dead():
			continue
		var cargo: Array = []
		for cu in s.cargo:
			if not cu.is_dead():
				cargo.append(_mp_unit_record(cu))
		var rec := {"id": s.net_id, "type": s.ship_type, "owner": s.owner_id,
			"team": s.team, "x": s.global_position.x, "y": s.global_position.y,
			"hp": s.hp, "carry": s.carry_amount,
			"gather_t": s._gather_t, "atk_cd": s._atk_cd,
			"fish": null, "dock": -1, "atk": -1, "atk_beast": null,
			"dest": null, "cargo": cargo}
		if s.fish_spot != null:
			rec["fish"] = [s.fish_spot.cell.x, s.fish_spot.cell.y]
		if s.home_dock != null:
			rec["dock"] = s.home_dock.net_id
		if s.attack_target != null and is_instance_valid(s.attack_target):
			if s.attack_target is Beast:
				var ba2: Vector2 = (s.attack_target as Beast).anchor
				rec["atk_beast"] = [ba2.x, ba2.y]
			else:
				rec["atk"] = s.attack_target.net_id
		if not s.path.is_empty():
			var dc2: Vector2i = world.world_to_cell(s.path[s.path.size() - 1])
			rec["dest"] = [dc2.x, dc2.y]
		s_arr.append(rec)
	st["ships"] = s_arr
	var f_arr: Array = []
	for f in fields:
		f_arr.append({"cell": [f.cell.x, f.cell.y],
			"farm": f.farm.net_id if f.farm != null else -1,
			"stage": f.stage, "left": f.harvests_left})
	st["fields"] = f_arr
	var n_arr: Array = []
	for n in world.nodes:
		n_arr.append({"cell": [n.cell.x, n.cell.y], "rtype": n.rtype,
			"amt": n.amount})
	st["nodes"] = n_arr
	var fish_arr: Array = []
	for fs in world.fish_spots:
		fish_arr.append({"cell": [fs.cell.x, fs.cell.y], "amt": fs.amount})
	st["fish"] = fish_arr
	var beast_arr: Array = []
	for b in world.beasts:
		var rec2 := {"anchor": [b.anchor.x, b.anchor.y], "species": b.species,
			"skin": b.skin, "x": b.global_position.x, "y": b.global_position.y,
			"hp": b.hp, "state": b.state, "provoked": b.provoked,
			"dest": [b._dest.x, b._dest.y], "wait": b._wait, "scan": b._scan_t,
			"repath": b._repath_t, "atk_cd": b._atk_cd, "rng": str(b._rng.state),
			"target": -1}
		if b.target != null and is_instance_valid(b.target):
			rec2["target"] = b.target.net_id
		beast_arr.append(rec2)
	st["beasts"] = beast_arr
	return st


func _entity_by_net_id(nid: int) -> Node2D:
	var u := unit_of_net_id(nid)
	if u != null:
		return u
	var b := building_of_net_id(nid)
	if b != null:
		return b
	return ship_of_net_id(nid)


func _mp_reconcile_nodes(node_recs: Array) -> void:
	var want := {}
	for rec in node_recs:
		want[Vector2i(int(rec["cell"][0]), int(rec["cell"][1]))] = rec
	var existing := {}
	for n in world.nodes:
		existing[n.cell] = n
	for cell in existing.keys():
		if not want.has(cell):
			world.remove_node(existing[cell])
	for cell in want:
		var rec: Dictionary = want[cell]
		if existing.has(cell):
			existing[cell].amount = int(rec["amt"])
		else:
			world._add_node(cell, String(rec["rtype"]), int(rec["amt"]))


func _mp_reconcile_fish(fish_recs: Array) -> void:
	for rec in fish_recs:
		var cell := Vector2i(int(rec["cell"][0]), int(rec["cell"][1]))
		for fs in world.fish_spots:
			if fs.cell == cell:
				fs.amount = int(rec["amt"])
				break


func _mp_reconcile_beasts(beast_recs: Array) -> void:
	# Beast.anchor is a Vector2 in world pixels (territory centre).
	var want := {}
	for rec in beast_recs:
		want[Vector2(float(rec["anchor"][0]), float(rec["anchor"][1]))] = rec
	var existing := {}
	for b in world.beasts:
		existing[b.anchor] = b
	for anchor in existing.keys():
		if not want.has(anchor):
			var b = existing[anchor]
			world.beasts.erase(b)
			b.queue_free()
	for anchor in want:
		var rec: Dictionary = want[anchor]
		var b = existing.get(anchor)
		if b == null:
			b = world._add_beast(String(rec["species"]), String(rec["skin"]),
					world.world_to_cell(anchor))
			b.game = self
		if b == null:
			continue
		b.global_position = Vector2(float(rec["x"]), float(rec["y"]))
		b.hp = float(rec["hp"])
		b.state = String(rec["state"])
		b.provoked = bool(rec["provoked"])
		b._dest = Vector2(float(rec["dest"][0]), float(rec["dest"][1]))
		b._wait = float(rec["wait"])
		b._scan_t = float(rec["scan"])
		b._repath_t = float(rec["repath"])
		b._atk_cd = float(rec["atk_cd"])
		b._rng.state = int(String(rec["rng"]))
		b.target = null
		if int(rec["target"]) >= 0:
			b.target = unit_of_net_id(int(rec["target"]))
		if b.state == "chase" and b.target == null:
			b.state = "wander"


func _mp_restore_unit_task(u: Unit, rec: Dictionary) -> void:
	u.gather_timer = float(rec["gather_t"])
	u.tend_timer = float(rec["tend_t"])
	u.guard_pos = Vector2(float(rec["guard"][0]), float(rec["guard"][1]))
	var task = rec.get("task")
	if task == null:
		return
	match String(task.get("k", "")):
		"garrison":
			var haven := building_of_net_id(int(task["haven"]))
			if haven != null:
				u.state = "garrison"
				u.garrisoned = true
				u.visible = false
				u.flee_haven = haven
				u.flee_timer = float(task["flee_t"])
				u.global_position = haven.global_position
		"return":
			u.order_return()
		"node":
			var cell := Vector2i(int(task["cell"][0]), int(task["cell"][1]))
			for n in world.nodes:
				if n.cell == cell:
					u.order_gather(n)
					u.gather_timer = float(rec["gather_t"])
					break
		"field":
			var cell2 := Vector2i(int(task["cell"][0]), int(task["cell"][1]))
			for f in fields:
				if f.cell == cell2:
					u.order_field(f)
					u.tend_timer = float(rec["tend_t"])
					break
		"site":
			var site := building_of_net_id(int(task["id"]))
			if site != null:
				u.order_build(site)
		"attack":
			var tgt = _entity_by_net_id(int(task["id"]))
			if tgt != null:
				u.order_attack(tgt)
				u._atk_cd = float(rec["atk_cd"])
		"attack_beast":
			var ap := Vector2(float(task["anchor"][0]), float(task["anchor"][1]))
			for b in world.beasts:
				if b.anchor == ap:
					u.order_attack(b)
					u._atk_cd = float(rec["atk_cd"])
					break
		"move":
			u.order_move_cell(Vector2i(int(task["cell"][0]), int(task["cell"][1])))
		"trade":
			# 15g: re-path the leg the cart was on (its route
			# fields were restored with the unit record).
			if u.trade_leg == 1 or u.trade_leg == 2:
				u.state = "trade_out" if u.trade_leg == 1 else "trade_back"
				u._trade_path_to(u._trade_dest())
		"wagon_unload":
			u.order_wagon_unload(Vector2i(int(task["cell"][0]),
					int(task["cell"][1])))


func _mp_restore_ship_task(s: Ship, rec: Dictionary) -> void:
	if rec["fish"] != null:
		var cell := Vector2i(int(rec["fish"][0]), int(rec["fish"][1]))
		for fs in world.fish_spots:
			if fs.cell == cell:
				s.order_fish(fs)
				s._gather_t = float(rec["gather_t"])
				break
		return
	if int(rec["atk"]) >= 0:
		var tgt = _entity_by_net_id(int(rec["atk"]))
		if tgt != null:
			s.order_attack(tgt)
			s._atk_cd = float(rec["atk_cd"])
			return
	if rec["atk_beast"] != null:
		var ap2 := Vector2(float(rec["atk_beast"][0]), float(rec["atk_beast"][1]))
		for b in world.beasts:
			if b.anchor == ap2:
				s.order_attack(b)
				s._atk_cd = float(rec["atk_cd"])
				return
	if rec["dest"] != null:
		s.order_move_cell(Vector2i(int(rec["dest"][0]), int(rec["dest"][1])))


## Rebuild the whole sim from a snapshot taken at `snap_tick`'s
## boundary on the source client. Commands the source executed
## after that boundary are re-applied from the local command log
## (they were relayed to us too); commands at or before the
## boundary are already inside the snapshot.
func _mp_apply_snapshot(snap_tick: int, st: Dictionary) -> void:
	if int(st.get("v", 0)) != 1:
		_mp_on_resync_failed(snap_tick)
		return
	var old_frontier := _mp_last_completed
	# 1) Transient combat visuals die with the old sim.
	for p in projectiles:
		if p.has("spr") and is_instance_valid(p["spr"]):
			p["spr"].queue_free()
	projectiles.clear()
	# 2) Ships (+ cargo), then units.
	for s in ships:
		for cu in s.cargo:
			cu.queue_free()
		s.queue_free()
	ships.clear()
	selected_ship = null
	for u in units:
		# 15g: a wagon's passengers live outside the roster —
		# free them with their carrier (the ship pattern above).
		if u.unit_type == "wagon":
			for cu in u.cargo:
				cu.queue_free()
			u.cargo.clear()
		u.queue_free()
	units.clear()
	selection.clear()
	# 3) Buildings silently (mirrors on_building_destroyed's world
	# cleanup but with no vfx / elimination side effects).
	for b in buildings:
		for c in b.cells():
			world.set_solid(c, false)
		if b.btype == "gate":
			world.clear_gate(b.origin_cell)
		b.queue_free()
	buildings.clear()
	selected_building = null
	# 4) Fields.
	for f in fields:
		f.queue_free()
	fields.clear()
	# 5) Per-slot state first: building art reads the owner's age.
	mp_wallets = st["wallets"].duplicate(true)
	mp_ages = st["ages"].duplicate(true)
	if st.has("techs"):
		mp_techs = st["techs"].duplicate(true)
	mp_rally.clear()
	for r in st["rally"]:
		mp_rally.append(Vector2(float(r[0]), float(r[1])))
	slot_eliminated = st["eliminated"].duplicate()
	slot_tc_down = st["tc_down"].duplicate()
	slot_inert = st["inert"].duplicate()
	_net_id_seq = 0
	# 6) Resource nodes + fish before anything references them.
	_mp_reconcile_nodes(st["nodes"])
	_mp_reconcile_fish(st["fish"])
	# 7) Buildings.
	for rec in st["buildings"]:
		var cell := Vector2i(int(rec["cell"][0]), int(rec["cell"][1]))
		var nb := _spawn_building(String(rec["type"]), int(rec["team"]), cell,
				bool(rec["complete"]), int(rec["owner"]))
		if nb == null:
			continue
		nb.net_id = int(rec["id"])
		nb.hp = float(rec["hp"])
		if not nb.complete:
			nb.progress = float(rec["progress"])
		nb.train_types = (rec["train"] as Array).duplicate()
		nb.train_queue = nb.train_types.size()
		nb.train_timer = float(rec["train_t"])
		nb.queue_redraw() # HP bar is drawn in _draw()
	for rec in st["buildings"]:
		if String(rec["type"]) == "wall" or String(rec["type"]) == "gate":
			var wb := building_of_net_id(int(rec["id"]))
			if wb != null:
				wb.wall_variant = String(rec["wall_var"])
				wb.refresh_wall_art()
				world.refresh_wall_variants_around(wb.origin_cell)
	# 8) Fields.
	for rec in st["fields"]:
		var fp := FieldPlot.new()
		fp.cell = Vector2i(int(rec["cell"][0]), int(rec["cell"][1]))
		fp.farm = building_of_net_id(int(rec["farm"]))
		fp.stage = int(rec["stage"])
		fp.harvests_left = int(rec["left"])
		fields.append(fp)
		add_child(fp)
	# 9) Units (tasks restored in the second pass).
	var unit_recs: Array = []
	for rec in st["units"]:
		var nu := _make_unit(int(rec["team"]),
				Vector2(float(rec["x"]), float(rec["y"])), String(rec["type"]),
				int(rec["owner"]))
		nu.net_id = int(rec["id"])
		nu.hp = float(rec["hp"])
		nu.carry_type = String(rec["carry_type"])
		nu.carry_amount = int(rec["carry_amt"])
		nu._atk_cd = float(rec["atk_cd"])
		nu.no_flee_timer = float(rec["no_flee"])
		if rec.has("shield"): # skill state (skill cooldown,
			# shield pool, control timers, taunt — plain scalars,
			# exact restore).
			nu.skill_cd_t = float(rec.get("scd", 0.0))
			nu.shield_hp = float(rec["shield"])
			nu.shield_t = float(rec.get("shield_t", 0.0))
			nu.stun_t = float(rec["stun"])
			nu.frozen_t = float(rec["frozen"])
			nu.taunt_t = float(rec.get("taunt_t", 0.0))
			nu.taunt_id = int(rec.get("taunt_id", -1))
			nu.flurry_left = int(rec.get("flurry", 0))
			nu.flurry_t = float(rec.get("flurry_t", 0.0))
			nu.flurry_cursor = int(rec.get("flurry_c", -1))
		# 15g transport restore: the cart's route endpoints (the
		# buildings are already rebuilt above) and the wagon's
		# passengers (created like ship cargo, then boarded —
		# board_unit takes them back out of the roster).
		if rec.has("trade_home"):
			nu.trade_home = building_of_net_id(int(rec["trade_home"]))
			nu.trade_target = building_of_net_id(int(rec["trade_tgt"]))
			nu.trade_leg = int(rec["trade_leg"])
			nu.trade_gold = int(rec["trade_gold"])
			nu.trade_loaded = bool(rec["trade_loaded"])
		if rec.has("cargo"):
			for crec in rec["cargo"]:
				var cu := _make_unit(int(crec["team"]),
						Vector2(float(crec["x"]), float(crec["y"])),
						String(crec["type"]), int(crec["owner"]))
				cu.net_id = int(crec["id"])
				cu.hp = float(crec["hp"])
				cu.carry_type = String(crec["carry_type"])
				cu.carry_amount = int(crec["carry_amt"])
				nu.board_unit(cu)
		unit_recs.append([nu, rec])
	# 10) Ships + cargo.
	var ship_recs: Array = []
	for rec in st["ships"]:
		var ns := Ship.new()
		ns.game = self
		ns.world = world
		ns.ship_type = String(rec["type"])
		ns.team = int(rec["team"])
		ns.owner_id = int(rec["owner"])
		ns.home_dock = building_of_net_id(int(rec["dock"]))
		ns.global_position = Vector2(float(rec["x"]), float(rec["y"]))
		add_child(ns)
		ns.net_id = int(rec["id"])
		ns.hp = float(rec["hp"])
		ns.carry_amount = int(rec["carry"])
		ns._gather_t = float(rec["gather_t"])
		ns._atk_cd = float(rec["atk_cd"])
		ships.append(ns)
		for crec in rec["cargo"]:
			var cu := _make_unit(int(crec["team"]),
					Vector2(float(crec["x"]), float(crec["y"])),
					String(crec["type"]), int(crec["owner"]))
			cu.net_id = int(crec["id"])
			cu.hp = float(crec["hp"])
			cu.carry_type = String(crec["carry_type"])
			cu.carry_amount = int(crec["carry_amt"])
			ns.board_unit(cu)
		ship_recs.append([ns, rec])
	# 11) Beasts.
	_mp_reconcile_beasts(st["beasts"])
	# 11b) 16b skill zones (the arrow rain; hero cooldowns and
	# timed effects ride the unit records above).
	skill_zones.clear()
	if st.has("skill_zones"):
		for zr in st["skill_zones"]:
			skill_zones.append({"kind": String(zr["kind"]),
					"pos": Vector2(float(zr["x"]), float(zr["y"])),
					"t": float(zr["t"]), "acc": float(zr["acc"]),
					"tick_n": int(zr.get("tick_n", 0)),
					"dmg": float(zr.get("dmg", 0.0)),
					"radius": float(zr["radius"]), "owner": int(zr["owner"])})
			if skill_fx != null:
				skill_fx.zone_fx(String(zr["kind"]),
						Vector2(float(zr["x"]), float(zr["y"])),
						float(zr["radius"]), float(zr["t"]))
	# 11d) 15b diplomacy tables (absent from pre-15b snapshots).
	_dip_restore(st)
	# 12) Task passes.
	for pair in unit_recs:
		_mp_restore_unit_task(pair[0], pair[1])
	for pair in ship_recs:
		_mp_restore_ship_task(pair[0], pair[1])
	# 13) Identity refs + tick bookkeeping.
	_net_id_seq = int(st["net_id_seq"])
	player_tc = tc_of(local_slot)
	enemy_tc = null
	for s2 in range(slot_count()):
		if team_of_slot(s2) != view_team():
			enemy_tc = tc_of(s2)
			if enemy_tc != null:
				break
	rally_point = mp_rally[local_slot]
	match_time = float(snap_tick) * 0.1
	_mp_current_tick = snap_tick
	_mp_last_completed = snap_tick
	var kept: Array = []
	for t in _mp_tick_queue:
		if int(t) > snap_tick:
			kept.append(t)
	_mp_tick_queue = kept
	for k in _mp_pending_cmds.keys():
		if int(k) <= snap_tick:
			_mp_pending_cmds.erase(k)
	_mp_checksum_due = -1
	_mp_stepping = false
	_mp_frames_into_tick = 0
	Engine.time_scale = 0.0
	# Commands executed after the snapshot boundary are NOT inside
	# it: re-apply them from the local log, in tick order.
	var ticks := _mp_cmd_log.keys()
	ticks.sort()
	for t in ticks:
		if int(t) > snap_tick and int(t) <= old_frontier:
			for rec in _mp_cmd_log[t]:
				_mp_apply_command(int(rec["from"]), rec["cmd"])
	_mp_resync_wait = false
	if hud != null:
		hud.show_sync_overlay(false)
	if mp_debug_log:
		print("MPLOG resync applied tick=", snap_tick, " slot=", local_slot)
	# The snapshot carries the eliminated/tc_down flags: re-run the
	# winner evaluation so a client rebuilt into an already-finished
	# match (the ranked flow: the referee's kill lands while a
	# diverged client is frozen) still gets its end panel.
	if not mp_over:
		_mp_check_winner()


func _mp_on_tick(t: int) -> void:
	_mp_tick_queue.append(t)


func _mp_on_command(from_slot: int, exec_tick: int, cmd: Dictionary) -> void:
	if not _mp_pending_cmds.has(exec_tick):
		_mp_pending_cmds[exec_tick] = []
	_mp_pending_cmds[exec_tick].append({"from": from_slot, "cmd": cmd})


func _mp_on_desync(t: int) -> void:
	if hud != null:
		hud.show_message("Cảnh báo: mất đồng bộ với phòng (tick %d)" % t)
	if mp_debug_log:
		print("MPLOG desync tick=", t)


func _mp_on_connection_closed() -> void:
	if referee_mode:
		# A referee without its relay is useless: exit and let the
		# orchestrator see the process die.
		print("MPLOG referee lost relay connection; quitting")
		get_tree().quit()
		return
	if hud != null and not mp_over:
		hud.show_message("Mất kết nối máy chủ")


## A dropped player: their entities freeze (inert guards in
## unit/building/ship + tower skip) and the slot counts as
## eliminated for the win check. The REFEREE differs: a ranked
## disconnect gets a 30 s grace before the slot is eliminated and
## the win is declared with reason "disconnect".
func _mp_on_player_left(slot: int) -> void:
	if slot < 0 or slot >= slot_count():
		return
	slot_inert[slot] = true
	if referee_mode:
		if not slot_eliminated[slot] and _referee_grace_slot < 0:
			_referee_grace_slot = slot
			_referee_grace_deadline = _mp_last_completed + 300 # 30 s at 10 ticks/s
			print("MPLOG referee grace slot=", slot, " deadline tick=",
					_referee_grace_deadline)
		if mp_debug_log:
			print("MPLOG player_left slot=", slot)
		return
	slot_eliminated[slot] = true
	_mp_record_elimination(slot)
	if hud != null and slot != local_slot:
		hud.show_message("%s đã rời trận" % slot_names[slot])
	if mp_debug_log:
		print("MPLOG player_left slot=", slot)
	_mp_check_winner()


## Referee-only per-tick bookkeeping: the disconnect grace. When
## it expires the dropped slot is eliminated and the win check
## declares the remaining side the winner (reason "disconnect").
func _mp_referee_drive(t: int) -> void:
	# 13z: with eight players, several can be inside a disconnect
	# grace over one match — when no grace is running, adopt the
	# next dropped (inert, not yet eliminated) slot so each one
	# gets its own 30 s before it counts as eliminated.
	if _referee_grace_slot < 0 and not mp_over:
		for s in range(slot_count()):
			if slot_inert[s] and not slot_eliminated[s]:
				_referee_grace_slot = s
				_referee_grace_deadline = t + 300
				print("MPLOG referee grace slot=", s, " deadline tick=",
						_referee_grace_deadline)
				break
	if _referee_grace_slot >= 0 and not mp_over \
			and t >= _referee_grace_deadline:
		var slot := _referee_grace_slot
		_referee_grace_slot = -1
		_referee_win_reason = "disconnect"
		slot_eliminated[slot] = true
		_mp_record_elimination(slot)
		if not _referee_disconnect_slots.has(slot):
			_referee_disconnect_slots.append(slot)
		print("MPLOG referee grace expired slot=", slot, " tick=", t)
		_mp_check_winner()


## Tick-stepped lockstep drive, called from _process (which runs
## BEFORE children): each server tick releases exactly 3 frames of
## simulation at fixed 1/30s steps; commands apply at tick starts.
func _mp_drive() -> void:
	# A checksum is computed at the top of the frame AFTER the
	# stepped frames ran: Main._process precedes its children's, so
	# a same-frame checksum would read pre-step state.
	if _mp_checksum_due >= 0:
		var due_tick := _mp_checksum_due
		_mp_checksum_due = -1
		var h := _mp_state_hash()
		Net.send_checksum(due_tick, str(h))
		if observer_mode:
			print("MPLOG observer checksum tick=", due_tick, " hash=", h)
		if replay_mode:
			print("MPLOG replay checksum tick=", due_tick, " hash=", h)
		if mp_debug_log:
			print("MPLOG checksum slot=", local_slot, " tick=", due_tick, " hash=", h)
		if referee_mode:
			print("MPLOG referee checksum tick=", due_tick, " hash=", h)
	# Resync freeze: this client diverged — bank incoming ticks but
	# never step until the snapshot rebuild lands.
	if _mp_resync_wait:
		return
	if _mp_stepping:
		_mp_frames_into_tick += 1
		if _mp_frames_into_tick < 3:
			return
		_mp_stepping = false
		Engine.time_scale = 0.0
		_mp_last_completed = _mp_current_tick
		if _mp_current_tick > 0 and _mp_current_tick % 30 == 0:
			_mp_checksum_due = _mp_current_tick
		# True tick boundary: serve a pending snapshot request from
		# exactly this state (commands of this tick already applied).
		if _mp_snapshot_pending:
			_mp_serve_snapshot()
		if _mp_obs_snapshot_pending:
			_mp_serve_obs_snapshot()
	elif _mp_snapshot_pending:
		# Idle queue: the last completed tick IS the boundary.
		_mp_serve_snapshot()
	elif _mp_obs_snapshot_pending:
		_mp_serve_obs_snapshot()
	if _mp_tick_queue.is_empty() or paused:
		return
	var t: int = _mp_tick_queue.pop_front()
	_mp_current_tick = t
	if referee_mode:
		_mp_referee_drive(t)
	if mp_debug_log and t % 150 == 0:
		print("MPLOG drive slot=", local_slot, " tick=", t,
				" queue=", _mp_tick_queue.size(), " paused=", paused)
	# Smoke-test hook: scripted TC kill at an exact tick.
	# Skill-smoke hook: at tick 5 both slots' heroes materialise
	# mid-map, 3 tiles apart (test-only; normal matches train
	# heroes at Castles). The auto driver then orders them to
	# fight and casts both skills through the command pipeline.
	if mp_test_hero and not _mp_test_hero_done and t >= 5 and slot_count() >= 2:
		_mp_test_hero_done = true
		var mid := Vector2i(World.MAP_W / 2, World.MAP_H / 2)
		for s in range(2):
			var cell := world.nearest_walkable(mid + Vector2i(-2 + s * 4, 0))
			_make_unit(slot_teams[s], world.cell_center(cell), "king", s)
		print("MPLOG heroes spawned tick=", t)
	# 15g transport-smoke hook: at tick 5 every slot gains the
	# trade kit the choreography drives — a second Market placed
	# by a deterministic ring scan out from its TC (identical on
	# every client), a Cart beside the home Market, a Wagon and
	# five Militia beside each other. Test-only staging; normal
	# matches build and train everything themselves.
	if mp_test_transport and not _mp_test_transport_done and t >= 5 \
			and slot_count() >= 2:
		_mp_test_transport_done = true
		for s in range(slot_count()):
			var tc := tc_of(s)
			if tc == null:
				continue
			var home := _spawn_building("market", slot_teams[s],
					_test_spot_near(tc.origin_cell + Vector2i(6, 0)), true, s)
			var far := _spawn_building("market", slot_teams[s],
					_test_spot_near(tc.origin_cell + Vector2i(26, 10)), true, s)
			if home == null or far == null:
				continue
			var hc := world.nearest_walkable(home.origin_cell + Vector2i(1, 3))
			_make_unit(slot_teams[s], world.cell_center(hc), "cart", s)
			var wc := world.nearest_walkable(home.origin_cell + Vector2i(3, 3))
			_make_unit(slot_teams[s], world.cell_center(wc), "wagon", s)
			# The five riders ring the wagon inside embark range.
			for off in [Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
					Vector2i(1, 0), Vector2i(-1, 0)]:
				var mc := world.nearest_walkable(home.origin_cell + Vector2i(3, 3) + off)
				_make_unit(slot_teams[s], world.cell_center(mc), "militia", s)
		print("MPLOG transport staged tick=", t)
	# Smoke-test kill hooks: the legacy single (tick, slot) pair
	# plus the 13z list form (several slots on different ticks —
	# an 8-player match only ends when seven TCs fall).
	var kills_now: Array = mp_test_kills.duplicate()
	if mp_test_kill_tick >= 0:
		kills_now.append([mp_test_kill_tick, mp_test_kill_slot])
	for pair in kills_now:
		if t == int(pair[0]):
			var kslot := int(pair[1])
			if kslot >= 0 and kslot < slot_count() \
					and not slot_eliminated[kslot]:
				var ktc := tc_of(kslot)
				if ktc != null and not ktc.destroyed:
					ktc.take_damage(1000000.0)
	# Apply this tick's commands in relay order, then step.
	var recs: Array = _mp_pending_cmds.get(t, [])
	_mp_pending_cmds.erase(t)
	if not recs.is_empty():
		_mp_cmd_log[t] = recs.duplicate()
	for rec in recs:
		var applied := _mp_apply_command(int(rec["from"]), rec["cmd"])
		if referee_mode and not applied:
			# The referee counts every command its validators drop
			# (bad ownership, unaffordable, illegal placement…).
			_referee_dropped += 1
			print("MPLOG referee dropped cmd kind=", str(rec["cmd"].get("kind", "")),
					" from=", int(rec["from"]), " tick=", t,
					" total=", _referee_dropped)
	_prune_cmd_log()
	Engine.time_scale = 1.0
	_mp_stepping = true
	_mp_frames_into_tick = 0


## 13y wrapper: an ACCEPTED lockstep command is one valid APM
## action for its sender (GDD formula — menu/camera/selection
## never become commands, so they are excluded by construction).
## Every client applies the full stream, so every client counts
## the same APM for every slot. Replay playback is not a live
## player, so it is not counted.
func _mp_apply_command(from_slot: int, cmd: Dictionary) -> bool:
	var applied := _mp_apply_command_inner(from_slot, cmd)
	if applied and not replay_mode:
		_note_action(from_slot)
	return applied


## Execute one relayed command (validated against the commander's
## state at this tick — identical on every client). Returns whether
## the command was accepted by its validator (the referee counts
## the drops; players ignore the result).
func _mp_apply_command_inner(from_slot: int, cmd: Dictionary) -> bool:
	if from_slot < 0 or from_slot >= slot_count():
		return false
	if slot_eliminated[from_slot]:
		return false
	var kind := str(cmd.get("kind", ""))
	if mp_debug_log:
		print("MPLOG applied tick=", _mp_current_tick, " kind=", kind, " from=", from_slot)
	match kind:
		"order":
			var arr: Array = []
			for id in cmd.get("units", []):
				var u := unit_of_net_id(int(id))
				if u != null and u.owner_id == from_slot and not u.is_dead():
					arr.append(u)
			if arr.is_empty():
				return false
			apply_order_for(arr, null, Vector2(float(cmd.get("x", 0.0)),
					float(cmd.get("y", 0.0))), from_slot)
			return true
		"ship_order":
			var s := ship_of_net_id(int(cmd.get("s", -1)))
			if s == null or s.owner_id != from_slot:
				return false
			apply_ship_order_for(s, Vector2(float(cmd.get("x", 0.0)),
					float(cmd.get("y", 0.0))))
			return true
		"build":
			var c: Array = cmd.get("cell", [0, 0])
			return _mp_apply_build(from_slot, str(cmd.get("btype", "")),
					Vector2i(int(c[0]), int(c[1])))
		"field":
			var fc: Array = cmd.get("cell", [0, 0])
			return _mp_apply_field(from_slot, Vector2i(int(fc[0]), int(fc[1])))
		"train":
			return _mp_apply_train(from_slot, int(cmd.get("b", -1)), str(cmd.get("unit", "")))
		"skill":
			return _mp_apply_skill_cmd(from_slot, cmd)
		"train_ship":
			return _mp_apply_train_ship(from_slot, int(cmd.get("b", -1)), str(cmd.get("unit", "")))
		"age_up":
			return _mp_apply_age_up(from_slot, int(cmd.get("to", 2)))
		"research":
			return _mp_apply_research(from_slot, str(cmd.get("tech", "")))
		"surrender":
			return _mp_apply_surrender(from_slot)
		"dip_propose":
			return _mp_apply_dip_propose(from_slot, int(cmd.get("to", -1)),
					int(cmd.get("stance", -1)))
		"dip_respond":
			return _mp_apply_dip_respond(from_slot, int(cmd.get("to", -1)),
					bool(cmd.get("accept", false)))
		"dip_cancel":
			return _mp_apply_dip_cancel(from_slot, int(cmd.get("to", -1)))
		"dip_break":
			return _mp_apply_dip_break(from_slot, int(cmd.get("to", -1)))
		"dip_gift":
			return _mp_apply_dip_gift(from_slot, int(cmd.get("to", -1)),
					str(cmd.get("rtype", "")), int(cmd.get("amt", 0)))
		"cancel_train":
			return _mp_apply_cancel_train(from_slot, int(cmd.get("b", -1)),
					int(cmd.get("i", -1)))
		"market":
			return _mp_apply_market(from_slot, int(cmd.get("b", -1)),
					str(cmd.get("side", "")), str(cmd.get("rtype", "")))
		"rally":
			mp_rally[from_slot] = Vector2(float(cmd.get("x", 0.0)), float(cmd.get("y", 0.0)))
			if from_slot == local_slot:
				rally_point = mp_rally[from_slot]
			return true
	return false


## MP execution of a build command (mirrors confirm_placement's
## spawn + nearest-builder assignment, with the owner's wallet).
func _mp_apply_build(owner: int, btype: String, cell: Vector2i) -> bool:
	if btype == "" or not placement_valid_at(cell, btype):
		return false
	var def := get_build_def(btype)
	var cost: Dictionary = def.cost
	var w: Dictionary = mp_wallets[owner]
	for r in cost:
		if int(w.get(r, 0)) < int(cost[r]):
			return false
	for r in cost:
		w[r] = int(w[r]) - int(cost[r])
	var b := _spawn_building(btype, team_of_slot(owner), cell, false, owner)
	var builder: Unit = null
	var bd := INF
	for u in units:
		if u.owner_id != owner:
			continue
		var d: float = u.global_position.distance_squared_to(
				b.position + Vector2(def.size) * World.TILE * 0.5)
		if u.state == "idle" and d < bd:
			bd = d
			builder = u
	if builder == null:
		bd = INF
		for u in units:
			if u.owner_id != owner:
				continue
			var d: float = u.global_position.distance_squared_to(b.position)
			if d < bd:
				bd = d
				builder = u
	if builder != null:
		builder.order_build(b)
	return true


## MP execution of a field-planting command.
func _mp_apply_field(owner: int, cell: Vector2i) -> bool:
	if not field_valid_at(cell, owner):
		return false
	var w: Dictionary = mp_wallets[owner]
	if int(w.get("wood", 0)) < Stats.FIELD_COST_WOOD:
		return false
	w["wood"] = int(w["wood"]) - Stats.FIELD_COST_WOOD
	var f := FieldPlot.new()
	f.cell = cell
	f.farm = farm_for_field(cell, owner)
	fields.append(f)
	add_child(f)
	var tender: Unit = null
	var bd := INF
	for u in units:
		if u.owner_id == owner and u.unit_type == "villager" and not u.is_dead():
			var d: float = u.global_position.distance_squared_to(f.position)
			if d < bd:
				bd = d
				tender = u
	if tender != null:
		tender.order_field(f)
	return true


## MP execution of a land-unit training command.
func _mp_apply_train(owner: int, b_id: int, kind: String) -> bool:
	var b := building_of_net_id(b_id)
	if b == null or b.owner_id != owner or not b.complete or b.destroyed:
		return false
	if not UNIT_COSTS.has(kind):
		return false
	if kind == "villager" and b.btype != "town_center":
		return false
	if kind == "king" and b.btype != "castle":
		return false
	if kind == "cart" and b.btype != "market":
		return false
	if kind != "villager" and kind != "king" and kind != "cart" \
			and b.btype != "barracks":
		return false
	# The King is unique per player: reject a second muster while
	# one lives or is already in a queue (retrain after death only).
	if kind == "king" and king_busy(owner):
		return false
	if owner_age(owner) < int(UNIT_MIN_AGE.get(kind, 1)):
		return false
	if owner_pop_current(owner) + owner_queued(owner) >= owner_pop_cap(owner):
		return false
	var costs: Dictionary = UNIT_COSTS[kind]
	var w: Dictionary = mp_wallets[owner]
	for r in costs:
		if int(w.get(r, 0)) < int(costs[r]):
			return false
	for r in costs:
		w[r] = int(w[r]) - int(costs[r])
	b.start_training(kind)
	return true


## MP execution of a ship training command.
func _mp_apply_train_ship(owner: int, b_id: int, kind: String) -> bool:
	var b := building_of_net_id(b_id)
	if b == null or b.owner_id != owner or b.btype != "dock" or not b.complete or b.destroyed:
		return false
	if not SHIP_COSTS.has(kind):
		return false
	var costs: Dictionary = SHIP_COSTS[kind]
	var w: Dictionary = mp_wallets[owner]
	for r in costs:
		if int(w.get(r, 0)) < int(costs[r]):
			return false
	for r in costs:
		w[r] = int(w[r]) - int(costs[r])
	b.start_training(kind)
	return true


## MP execution of a market trade command.
func _mp_apply_market(owner: int, b_id: int, side: String, rtype: String) -> bool:
	var b := building_of_net_id(b_id)
	if b == null or b.owner_id != owner or b.btype != "market" or not b.complete:
		return false
	if not MARKET_TRADE_TYPES.has(rtype):
		return false
	var w: Dictionary = mp_wallets[owner]
	if side == "sell":
		if int(w.get(rtype, 0)) < MARKET_TRADE_AMOUNT:
			return false
		w[rtype] = int(w[rtype]) - MARKET_TRADE_AMOUNT
		w["gold"] = int(w.get("gold", 0)) + market_sell_gold(owner)
	elif side == "buy":
		if int(w.get("gold", 0)) < market_buy_gold(owner):
			return false
		w["gold"] = int(w["gold"]) - market_buy_gold(owner)
		w[rtype] = int(w.get(rtype, 0)) + MARKET_TRADE_AMOUNT
	else:
		return false
	return true


func _hash_mix(h: int, v: int) -> int:
	return int(((h ^ (v & 0x7fffffff)) * 16777619) & 0xffffffff)


## Map-generation fingerprint (solid/water grid + every resource
## node's cell, type and amount) — identical across clients iff
## the seeded generation matched.
func _mp_world_hash() -> int:
	var h := 2166136261
	for y in range(World.MAP_H):
		for x in range(World.MAP_W):
			var c := Vector2i(x, y)
			var v := 0
			if world.water.has(c):
				v = 1
			elif world.is_solid(c):
				v = 2
			h = _hash_mix(h, v)
	for n in world.nodes:
		h = _hash_mix(h, n.cell.x)
		h = _hash_mix(h, n.cell.y)
		h = _hash_mix(h, n.amount)
		h = _hash_mix(h, n.rtype.length())
	return h


## Lockstep state checksum: every entity by net_id (quantised
## position + hp), every slot's wallet and age.
func _mp_state_hash() -> int:
	var h := 2166136261
	var us: Array = units.duplicate()
	us.sort_custom(func(a, b): return a.net_id < b.net_id)
	for u in us:
		h = _hash_mix(h, u.net_id)
		h = _hash_mix(h, int(u.global_position.x))
		h = _hash_mix(h, int(u.global_position.y))
		h = _hash_mix(h, int(u.hp))
		# 13v: hero cooldowns, shield pools and hard-control timers
		# are sim state — quantised into the hash.
		h = _hash_mix(h, int(u.shield_hp))
		h = _hash_mix(h, int(u.shield_t * 10.0))
		h = _hash_mix(h, int(u.stun_t * 10.0) + int(u.frozen_t * 10.0))
		# 16b: taunt + Kiếm Vũ flurry state are sim state too.
		h = _hash_mix(h, int(u.taunt_t * 10.0) + u.taunt_id)
		h = _hash_mix(h, u.flurry_left * 100 + int(u.flurry_t * 10.0))
		# 15g: transport state — a cart's route + locked payout,
		# a wagon's passenger manifest (passengers sit outside
		# the roster, so only the carrier's record can catch a
		# divergence in them).
		if u.unit_type == "cart":
			h = _hash_mix(h, u.trade_home.net_id if u.trade_home != null else -1)
			h = _hash_mix(h, u.trade_target.net_id if u.trade_target != null else -1)
			h = _hash_mix(h, u.trade_leg * 100 + u.trade_gold)
		elif u.unit_type == "wagon":
			h = _hash_mix(h, u.cargo.size())
			for cu in u.cargo:
				h = _hash_mix(h, cu.net_id)
				h = _hash_mix(h, int(cu.hp))
	var ss: Array = ships.duplicate()
	ss.sort_custom(func(a, b): return a.net_id < b.net_id)
	for s in ss:
		h = _hash_mix(h, s.net_id)
		h = _hash_mix(h, int(s.global_position.x))
		h = _hash_mix(h, int(s.global_position.y))
		h = _hash_mix(h, int(s.hp))
	var bs: Array = buildings.duplicate()
	bs.sort_custom(func(a, b): return a.net_id < b.net_id)
	for b in bs:
		h = _hash_mix(h, b.net_id)
		h = _hash_mix(h, int(b.hp))
		h = _hash_mix(h, 1 if b.complete else 0)
	for slot in range(slot_count()):
		var w: Dictionary = mp_wallets[slot]
		for r in ["food", "wood", "gold", "stone"]:
			h = _hash_mix(h, int(w.get(r, 0)))
		h = _hash_mix(h, int(mp_ages[slot].get("age", 1)))
		# Researched technology tiers (13s): their effects also flow
		# into unit hp / wallets, but the levels themselves are
		# hashed so a research desync is caught directly.
		for tid in Stats.TECHS:
			h = _hash_mix(h, tech_level(slot, tid))
	# 13v lingering skill zones (kind + position + remaining time).
	h = _hash_mix(h, skill_zones.size())
	for z in skill_zones:
		h = _hash_mix(h, String(z["kind"]).hash())
		h = _hash_mix(h, int((z["pos"] as Vector2).x))
		h = _hash_mix(h, int(float(z["t"]) * 10.0))
	# 15b: diplomacy tables — stances, live invites, declaration
	# windows (with remaining time) and tribute cooldowns.
	if dip_enabled:
		for a in range(slot_count()):
			for b in range(a + 1, slot_count()):
				h = _hash_mix(h, stance_of(a, b))
				h = _hash_mix(h, dip_invite_from(a, b) + 2)
				h = _hash_mix(h, dip_invite_from(b, a) + 2)
				var brk: Dictionary = dip_break_on(a, b)
				if not brk.is_empty():
					h = _hash_mix(h, int(brk["by"]) + 3)
					h = _hash_mix(h, int(brk["to"]) + 5)
					h = _hash_mix(h, int(float(brk["t"]) * 10.0))
				h = _hash_mix(h, int(float(dip_gift_cd.get(
						"%d>%d" % [a, b], 0.0)) * 10.0))
				h = _hash_mix(h, int(float(dip_gift_cd.get(
						"%d>%d" % [b, a], 0.0)) * 10.0))
	return h


## MP: a Town Center fell. Under the annihilation rule the owner is
## NOT eliminated yet — the slot fights on while it still has living
## villagers AND a completed Barracks/Dock; elimination lands when
## either leg gives out (re-checked on every death/destruction).
func _mp_on_tc_destroyed(b: Building) -> void:
	var slot := b.owner_id
	if slot < 0 or slot >= slot_count() or slot_eliminated[slot]:
		return
	slot_tc_down[slot] = true
	if slot == local_slot and hud != null:
		hud.show_message("Town Center đã mất! Giữ Dân và Trại lính để chiến đấu tiếp")
	_mp_evaluate_elimination(slot)


## Annihilation test for one MP slot (its TC must already be down).
func _slot_annihilated(slot: int) -> bool:
	for u in units:
		if u.owner_id == slot and not u.is_dead() and u.unit_type == "villager":
			for b in buildings:
				if b.owner_id == slot and b.complete and not b.destroyed \
						and (b.btype == "barracks" or b.btype == "dock"):
					return false
			return true
	return true


func _mp_evaluate_elimination(slot: int) -> void:
	if slot < 0 or slot >= slot_count() or slot_eliminated[slot] or slot_inert[slot]:
		return
	if not slot_tc_down[slot]:
		return
	if _slot_annihilated(slot):
		_mp_eliminate_slot(slot)


## 13z: note a slot's fall for the placement list. Every
## elimination path funnels here (annihilation, surrender,
## disconnect, referee grace) so the order is complete.
func _mp_record_elimination(slot: int) -> void:
	if slot < 0 or slot >= slot_count():
		return
	if not mp_elim_order.has(slot):
		mp_elim_order.append(slot)
		mp_elim_tick[slot] = _mp_current_tick


## 13z placements: slot ids ordered 1st -> last. Survivors lead
## (match score desc, slot asc — FFA has exactly one survivor);
## the eliminated follow latest-fall-first, and slots that fell
## on the SAME tick order by current match score (13y formula),
## then by slot. Deterministic on every client (same sim) — but
## only the server-banked placement is canonical.
func _mp_placements() -> Array:
	var alive: Array = []
	var fallen: Array = []
	for s in range(slot_count()):
		if slot_eliminated[s]:
			fallen.append(s)
		else:
			alive.append(s)
	alive.sort_custom(func(a: int, b: int) -> bool:
		var sa: int = match_score_of(a)
		var sb: int = match_score_of(b)
		if sa != sb:
			return sa > sb
		return a < b)
	fallen.sort_custom(func(a: int, b: int) -> bool:
		var ta: int = int(mp_elim_tick.get(a, -1))
		var tb: int = int(mp_elim_tick.get(b, -1))
		if ta != tb:
			return ta > tb
		var sa: int = match_score_of(a)
		var sb: int = match_score_of(b)
		if sa != sb:
			return sa > sb
		return a < b)
	return alive + fallen


## 14a: elimination ticks as the replay sidecar wants them —
## slot-indexed, -1 for a slot that never fell (survivors).
func _mp_elim_ticks() -> Array:
	var out: Array = []
	out.resize(slot_count())
	for s in range(slot_count()):
		out[s] = int(mp_elim_tick.get(s, -1))
	return out


func _mp_eliminate_slot(slot: int) -> void:
	slot_eliminated[slot] = true
	_mp_record_elimination(slot)
	if mp_debug_log:
		print("MPLOG eliminated slot=", slot)
	if slot == local_slot and not referee_mode and not replay_mode \
			and not observer_mode:
		mp_local_eliminated = true
		match_over = "defeat"
		_sample_stats() # 13y: final chart point for the local screen
		hud.show_end_panel("defeat", match_time,
				"Bạn đã đầu hàng" if local_surrendered else
				"Bị quét sạch — không còn Dân và công trình huấn luyện")
		if mp_debug_log:
			print("MPLOG result defeat")
	_mp_check_winner()


func _mp_check_winner() -> void:
	if mp_over:
		return
	# 15b: a diplomacy match can end WITHOUT a last slot standing
	# — when every surviving slot (two or more) is mutually
	# allied with no declaration in flight, the survivors share
	# the victory. A lone survivor falls through to the ordinary
	# annihilation path below, exactly as before.
	if diplomacy_active():
		var alive: Array = []
		for s in range(slot_count()):
			if not slot_eliminated[s]:
				alive.append(s)
		if alive.size() >= 2:
			var shared := true
			for i in range(alive.size()):
				for j in range(i + 1, alive.size()):
					if stance_of(int(alive[i]), int(alive[j])) != DIP_ALLY \
							or not dip_break_on(int(alive[i]),
									int(alive[j])).is_empty():
						shared = false
			if shared:
				_mp_allied_victory(alive)
				return
	var alive_teams: Array = []
	for s in range(slot_count()):
		if not slot_eliminated[s] and not alive_teams.has(team_of_slot(s)):
			alive_teams.append(team_of_slot(s))
	if alive_teams.size() == 1:
		mp_over = true
		var winner_team := int(alive_teams[0])
		if replay_mode:
			_replay_winner_team = winner_team
			return
		if referee_mode:
			# The referee's report is the ONLY result a ranked room
			# banks (the server ignores player-sent ranked results).
			# 13z: queue matches report the full placement list.
			if not _referee_reported:
				_referee_reported = true
				# 15h: per-slot match scores ride along — only
				# tournament rooms consume them server-side.
				var scores: Array = []
				for s in range(slot_count()):
					scores.append(match_score_of(s))
				Net.report_referee_result(winner_team, _referee_win_reason,
						_mp_current_tick, _mp_placements(),
						_referee_disconnect_slots, _mp_elim_ticks(), scores)
				print("MPLOG referee result winner_team=", winner_team,
						" reason=", _referee_win_reason,
						" placements=", _mp_placements(),
						" dropped=", _referee_dropped)
				# Stay alive a while after reporting: diverged
				# clients may still need snapshots/checksums.
				get_tree().create_timer(10.0).timeout.connect(
						func() -> void: get_tree().quit())
			return
		# Custom rooms: the HOST client reports the result; the
		# server banks W/L for account players (trust model:
		# server/README). Ranked clients never report. 13z: a
		# QUEUED normal room reports the full placement list.
		if Net.is_host and not Net.ranked:
			if Net.queued_room:
				Net.report_match_result(winner_team, _mp_placements(),
						_mp_elim_ticks())
			else:
				Net.report_match_result(winner_team, [], _mp_elim_ticks())
		if mp_debug_log:
			print("MPLOG winner team=", winner_team)
		var won: bool = winner_team == view_team()
		if observer_mode:
			# 15a: an observer has no stake in the outcome — no
			# local history entry and no personal win/loss. The
			# standings panel opens in its neutral form (the HUD
			# titles it "KẾT THÚC" for observers).
			_sample_stats()
			hud.show_end_panel("victory", match_time,
					"Trận đấu đã kết thúc — bạn đang xem trận này")
			print("MPLOG observer match over winner_team=", winner_team)
			return
		if not Net.ranked:
			_record_local_history(won) # custom room -> local log
		if not mp_local_eliminated:
			match_over = "victory" if won else "defeat"
			_sample_stats() # 13y: final chart point
			hud.show_end_panel(match_over, match_time,
					"Thắng bằng quét sạch (annihilation)" if won else
					"Đối thủ đã chiến thắng trận này")
			if mp_debug_log:
				print("MPLOG result ", match_over)


## 15b end: the survivors are mutually allied — a SHARED
## victory. Winners bank through the winner-set result path
## (host-reported, custom rooms only — the server refuses queue
## rooms, which never arm diplomacy anyway). The local screen
## names the co-winners; observers stay neutral; replay
## playback just notes the first victor's team; a referee never
## reaches this (ranked rooms refuse the flag structurally).
func _mp_allied_victory(alive: Array) -> void:
	mp_over = true
	dip_winners = alive.duplicate()
	if mp_debug_log:
		print("MPLOG dip allied victory winners=", dip_winners)
	if replay_mode:
		_replay_winner_team = team_of_slot(int(alive[0]))
		return
	if referee_mode:
		return
	if Net.is_host and not Net.ranked:
		Net.report_match_result(team_of_slot(int(alive[0])), [],
				_mp_elim_ticks(), dip_winners)
	var won: bool = alive.has(local_slot)
	if observer_mode:
		_sample_stats()
		hud.show_end_panel("victory", match_time,
				"Trận đấu đã kết thúc — bạn đang xem trận này")
		print("MPLOG observer match over allied victory")
		return
	if not Net.ranked:
		_record_local_history(won)
	if not mp_local_eliminated:
		match_over = "victory" if won else "defeat"
		_sample_stats()
		var names: Array = []
		for s in alive:
			names.append(_player_display_name(int(s)))
		var note := ""
		if won:
			note = "Thắng liên minh cùng: %s" % [", ".join(PackedStringArray(names))]
		else:
			note = "Liên minh của đối thủ đã thắng trận này"
		hud.show_end_panel(match_over, match_time, note)
		if mp_debug_log:
			print("MPLOG result ", match_over)


# ============================================================
# Replay playback (13h): the recorded command log is fed into
# the SAME lockstep queues the network feeds (_mp_on_tick /
# _mp_on_command), so the drive, validators and checksums are
# literally the live ones. No snapshots exist: seeking backward
# reloads the scene and fast-forwards the feed from tick 0;
# seeking forward just fast-forwards in place.
# ============================================================

func _replay_init() -> void:
	_replay_cmds = []
	for c in Net.replay_data.get("cmds", []):
		_replay_cmds.append({"from": int(c.get("from", 0)),
				"tick": int(c.get("tick", 0)), "cmd": c.get("cmd", {})})
	_replay_cmds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["tick"]) < int(b["tick"]))
	_replay_final_tick = int(Net.replay_data.get("final_tick", 0))
	# Scripted matches (the smokes) end via the deterministic
	# test-kill hook both live clients shared; the harness passes
	# it back (--mp-kill=tick:slot) so the final state reproduces.
	if Net.auto.has("mp-kill"):
		var kp := String(Net.auto["mp-kill"]).split(":")
		if kp.size() == 2:
			mp_test_kill_tick = int(kp[0])
			mp_test_kill_slot = int(kp[1])
	_replay_winner_team = int(Net.replay_data.get("winner_team", -1))
	_replay_markers = build_replay_markers()
	# 14a smoke hook: start playback at a fixed speed.
	if Net.auto.has("mp-replay-speed"):
		replay_set_speed(float(Net.auto["mp-replay-speed"]))
	if Net.replay_seek_target > 0:
		_replay_ff = true
		Engine.max_fps = 240 # fast-forward pacing (see feed)
	hud.visible = false
	_replay_bar = ReplayBar.new()
	_replay_bar.setup(self)
	add_child(_replay_bar)
	# 14a smoke/capture hook: view the match through one slot's fog.
	if Net.auto.has("mp-replay-follow"):
		replay_set_follow(int(Net.auto["mp-replay-follow"]))
	# Capture framing only: centre the camera on a slot's town
	# centre (in real use the viewer pans freely — following a
	# player never moves the camera by itself).
	if Net.auto.has("mp-replay-camfollow"):
		var cs := int(Net.auto["mp-replay-camfollow"])
		for b in buildings:
			if b.btype == "town_center" and not b.destroyed \
					and b.team == team_of_slot(cs):
				cam.focus_on(b.position + Vector2(b.size) * World.TILE * 0.5)
				break
	print("MPLOG replay init cmds=", _replay_cmds.size(),
			" final_tick=", _replay_final_tick,
			" seek=", Net.replay_seek_target,
			" markers=", _replay_markers.size(),
			" events=", (Net.replay_data.get("events", []) as Array).size())


## 14a: timeline markers, each one DERIVED from the recording —
## never invented. Age-ups and hero summons are commands, so they
## come straight out of the command log (the marker is the tick
## the order was issued/executed; an age-up's RESEARCH completes
## AGE_UP_TIME later, which the log does not carry — the marker
## honestly means "the order"). Eliminations are sim outcomes,
## not commands, so they come from the header's events sidecar
## (14a) and are simply absent from older/queue-less recordings.
## The final tick always closes the timeline.
func build_replay_markers() -> Array:
	var out: Array = []
	for rec in _replay_cmds:
		var cmd: Dictionary = rec["cmd"]
		var kind := str(cmd.get("kind", ""))
		if kind == "age_up":
			out.append({"tick": int(rec["tick"]), "kind": "age",
					"slot": int(rec["from"]), "to": int(cmd.get("to", 2))})
		elif kind == "train" and str(cmd.get("unit", "")) == "king":
			out.append({"tick": int(rec["tick"]), "kind": "hero",
					"slot": int(rec["from"])})
	for ev in Net.replay_data.get("events", []):
		out.append({"tick": int(ev.get("tick", 0)),
				"kind": str(ev.get("kind", "elim")),
				"slot": int(ev.get("slot", -1))})
	if _replay_final_tick > 0:
		out.append({"tick": _replay_final_tick, "kind": "end", "slot": -1})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["tick"]) < int(b["tick"]))
	return out


func _replay_feed(_delta: float) -> void:
	# NOTE: delta is useless here — the sim freezes the world with
	# Engine.time_scale = 0 between ticks, which also zeroes the
	# delta Main._process receives. The feed therefore counts
	# FRAMES: one tick per 3 frames at 1x (the lockstep cadence),
	# scaled by the speed factor; the drive gate paces consumption.
	if _replay_ended:
		return
	var push := 0
	if _replay_ff:
		push = 16 # the drive gate paces actual consumption
	elif _replay_playing:
		_replay_accum += _replay_speed / 3.0
		push = int(_replay_accum)
		_replay_accum -= float(push)
	else:
		return
	for i in range(push):
		if _replay_next_tick > _replay_final_tick:
			break
		var t := _replay_next_tick
		_replay_next_tick += 1
		_mp_on_tick(t)
		while _replay_ptr < _replay_cmds.size() \
				and int(_replay_cmds[_replay_ptr]["tick"]) <= t:
			var rec: Dictionary = _replay_cmds[_replay_ptr]
			_replay_ptr += 1
			if int(rec["tick"]) == t:
				_mp_on_command(int(rec["from"]), t, rec["cmd"])
	if _replay_ff and Net.replay_seek_target > 0 \
			and _mp_last_completed >= Net.replay_seek_target:
		_replay_ff = false
		Net.replay_seek_target = 0
		Engine.max_fps = 60


var _replay_shot_done: bool = false


func _replay_post() -> void:
	if _replay_bar != null:
		_replay_bar.refresh_bar()
	# 14a smoke hooks: exercise the REAL seek entry points
	# mid-playback (the flags live in Net.auto, which survives
	# the scene reload a backward seek performs).
	if Net.auto.has("mp-replay-seekfwd") \
			and not Net.auto.has("mp-replay-seekfwd-done") \
			and _mp_last_completed >= 60 and not _replay_ff:
		Net.auto["mp-replay-seekfwd-done"] = true
		print("MPLOG replay seekfwd -> ", int(Net.auto["mp-replay-seekfwd"]))
		replay_seek(int(Net.auto["mp-replay-seekfwd"]))
	if Net.auto.has("mp-replay-seekback") \
			and not Net.auto.has("mp-replay-seekback-done") \
			and _mp_last_completed >= int(Net.auto.get("mp-replay-seekback-at", 150)):
		Net.auto["mp-replay-seekback-done"] = true
		print("MPLOG replay seekback -> ", int(Net.auto["mp-replay-seekback"]))
		replay_seek(int(Net.auto["mp-replay-seekback"]))
	# Capture harness (tests/capture_replay.sh): one mid-playback
	# frame once the sim is underway, then quit.
	if not _replay_shot_done and Net.auto.has("mp-replay-shot") \
			and _mp_last_completed >= 60:
		_replay_shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
				String(Net.auto["mp-replay-shot"]))
		print("MPLOG replay shot saved")
		get_tree().quit()
	if not _replay_ended and _replay_final_tick > 0 \
			and _mp_last_completed >= _replay_final_tick:
		_replay_ended = true
		_replay_playing = false
		print("MPLOG replay done tick=", _mp_last_completed,
				" hash=", _mp_state_hash(),
				" winner_team=", _replay_winner_team)
		if _replay_bar != null:
			_replay_bar.show_result()
		if mp_replay_test:
			# ignore_time_scale: the sim leaves time_scale = 0.
			get_tree().create_timer(0.5, true, false, true).timeout.connect(
					func() -> void: get_tree().quit())


# --- ReplayBar accessors / actions ---

func replay_final_tick() -> int:
	return _replay_final_tick


func replay_current_tick() -> int:
	return _mp_last_completed


func replay_is_playing() -> bool:
	return _replay_playing and not _replay_ended


func replay_speed() -> float:
	return _replay_speed


func replay_winner_team() -> int:
	return _replay_winner_team


func replay_toggle_play() -> void:
	if not _replay_ended:
		_replay_playing = not _replay_playing


func replay_cycle_speed() -> void:
	var i := REPLAY_SPEEDS.find(_replay_speed)
	_replay_speed = REPLAY_SPEEDS[(i + 1) % REPLAY_SPEEDS.size()]


## Sets one of the GDD speeds (0.5/1/2/4/8); anything else snaps
## to the nearest offered step so the bar label stays truthful.
func replay_set_speed(s: float) -> void:
	var best: float = REPLAY_SPEEDS[0]
	for v in REPLAY_SPEEDS:
		if absf(v - s) < absf(best - s):
			best = v
	_replay_speed = best


func replay_speed_text() -> String:
	if _replay_speed == floorf(_replay_speed):
		return "%d×" % int(_replay_speed)
	return "0.5×"


func replay_markers() -> Array:
	return _replay_markers


## 14a follow player: view the match through one slot's fog of
## war (its TEAM's vision, explored memory included). -1 restores
## full vision. The camera itself is never moved or locked.
func replay_follow_slot() -> int:
	return _replay_follow


func replay_set_follow(slot: int) -> void:
	_replay_follow = slot
	if fog != null:
		if slot < 0:
			fog.set_view_team(-1)
		else:
			fog.set_view_team(team_of_slot(slot))
	if _replay_bar != null and _replay_bar.has_method("refresh_follow"):
		_replay_bar.refresh_follow()


func replay_seek(target: int) -> void:
	target = clampi(target, 0, _replay_final_tick)
	if target < _mp_last_completed:
		# Backward = restart + fast-forward re-simulation.
		Net.begin_replay(Net.replay_data, target)
	elif target > _mp_last_completed:
		Net.replay_seek_target = target
		_replay_ff = true
		Engine.max_fps = 240


func replay_exit() -> void:
	Engine.max_fps = 0
	Net.leave_replay()


# ============================================================
# Lobby glue (the lobby itself lives in scripts/lobby.gd)
# ============================================================

func open_lobby() -> void:
	_lobby_from_home = false
	_ensure_lobby()
	hud.hide_map_panel()
	lobby.open()


func close_lobby() -> void:
	if lobby != null:
		lobby.close()
	if _lobby_from_home:
		_lobby_from_home = false
		show_home()
	else:
		hud.show_map_panel()


func _ensure_lobby() -> void:
	if lobby == null:
		lobby = Lobby.new()
		lobby.layer = 60 # above the home screen (40) and HUD (1)
		lobby.setup(self)
		add_child(lobby)


# ------------------------------------------------------------ home lobby (13g)
## The boot flow lands on the painted home screen; the map panel
## became the "setup view" behind Đấu Thường / Bộ Lệnh.

func show_home() -> void:
	if home == null:
		home = HomeLobby.new()
		home.setup(self)
		add_child(home)
	hud.hide_map_panel()
	home.open()


func hide_home() -> void:
	if home != null:
		home.close()


func refresh_home() -> void:
	if home != null:
		home.refresh()


## Home history panel: play back one recorded match (13h).
func start_replay(rp: Dictionary) -> void:
	Net.begin_replay(rp)


## Capture-harness entry: open the home history panel.
func open_history_shot() -> void:
	show_home()
	if home != null:
		home.open_history_for_shot()


## Capture-harness entry: open the home friends panel (13m).
func open_friends_shot(tab: String = "all") -> void:
	show_home()
	if home != null:
		home.open_friends_for_shot(tab)


## Profile screen (13l): opened by tapping the home avatar.
var profile_screen = null
var tournament_screen = null
var alliance_screen = null


func _ensure_profile() -> void:
	if profile_screen == null:
		profile_screen = ProfileScreen.new()
		profile_screen.setup(self)
		add_child(profile_screen)


func home_open_profile() -> void:
	_ensure_profile()
	profile_screen.open()


## Capture-harness entry: open the profile screen.
func open_profile_shot() -> void:
	show_home()
	home_open_profile()


## Profile gear -> the home settings/connection popup (the
## profile layer sits above home, so it closes first).
func home_open_settings() -> void:
	if profile_screen != null:
		profile_screen.close()
	if home != null:
		home.call("_open_popup", "settings")


## Home → setup view (the map-choice panel, rehomed).
func open_setup() -> void:
	hide_home()
	hud.show_map_panel()


## Home "Đấu thường" diamond (13i): jump straight into a normal
## single-player match on the last-used map configuration — the
## chosen_biome/chosen_layout statics, which every map-panel pick
## persists (defaults: grassland · plains).
func home_quick_match() -> void:
	hide_home()
	choose_map(chosen_biome, chosen_layout)


## Setup view's Quay lại returns to the home screen.
func return_home_from_setup() -> void:
	hud.hide_map_panel()
	show_home()


## Home buttons that land inside the multiplayer lobby.
func home_open_rooms() -> void:
	_lobby_from_home = true
	_ensure_lobby()
	hide_home()
	lobby.open_for_rooms()


func home_open_account() -> void:
	# 13r: the account entry is the painted login screen now —
	# it floats over the home screen and routes back on success
	# (the room lobby keeps its own account section for players
	# who open it directly).
	_entry_wire()
	_login_over_home = true
	_entry_state = "login"
	_ensure_login()
	_login_screen.show_login()


func home_open_ranked() -> void:
	_lobby_from_home = true
	_ensure_lobby()
	hide_home()
	lobby.open_for_ranked()


## Home mode panel → Đấu Thường (13t): online matchmaking via
## the normal queue (the painted matchmaking screen), NOT the
## single-player setup view it used to open.
func home_open_normal() -> void:
	_lobby_from_home = true
	_ensure_lobby()
	hide_home()
	lobby.open_for_normal()


## The lobby's "Đánh với máy" entry (13t): bot play moved into
## the Custom view — close the lobby and land on the setup view
## (the map-choice panel); its Quay lại returns home as usual.
func open_setup_from_lobby() -> void:
	if lobby != null:
		lobby.close()
	_lobby_from_home = false
	open_setup()


func home_open_leaderboard() -> void:
	_lobby_from_home = true
	_ensure_lobby()
	hide_home()
	lobby.open_for_leaderboard()


## Tournaments (15h): the home rail's trophy chip opens the
## tournament screen (its own layer over home, like Profile).
func _ensure_tournament() -> void:
	if tournament_screen == null:
		tournament_screen = TournamentScreen.new()
		tournament_screen.setup(self)
		add_child(tournament_screen)


func home_open_tournament() -> void:
	_ensure_tournament()
	tournament_screen.open()


## Capture-harness entry: open the tournament screen on the
## list view or on the current detail (the driver's).
func open_tournament_shot(mode: String) -> void:
	show_home()
	_ensure_tournament()
	if mode == "detail":
		tournament_screen.open_detail(String(Net.tourn_detail.get("id", "")))
	else:
		tournament_screen.open()


## Alliances (17a): the leaderboard's Liên minh tab and the
## profile's Liên minh row open the alliance screen (its own
## layer over home, like Profile/Tournament). Entry points
## close their own surface first (the profile here; the
## leaderboard board closes itself in lobby.gd).
func _ensure_alliance() -> void:
	if alliance_screen == null:
		alliance_screen = AllianceScreen.new()
		alliance_screen.setup(self)
		add_child(alliance_screen)


func home_open_alliance() -> void:
	if profile_screen != null:
		profile_screen.close()
	_ensure_alliance()
	alliance_screen.open()


## Capture-harness entry: open the real alliance screen.
func open_alliance_shot() -> void:
	show_home()
	home_open_alliance()


## Home settings: relay address shared with the lobby.
func home_set_server(url: String) -> void:
	_ensure_lobby()
	lobby.set_server_url(url)


## Host config for a created room: the start panel's current
## biome/layout picks, with "random" resolved to a concrete choice
## (the room config must name one biome/layout for every client).
func mp_host_biome() -> String:
	var sel := hud.map_selection()
	if Biomes.is_valid(sel):
		return sel
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec())
	return str(Biomes.ORDER[rng.randi_range(0, Biomes.ORDER.size() - 1)])


func mp_host_layout() -> String:
	var sel := hud.layout_selection()
	if World.LAYOUTS.has(sel):
		return sel
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec()) + 7
	return str(World.LAYOUTS[rng.randi_range(0, World.LAYOUTS.size() - 1)])


func _ready() -> void:
	if _entry_applies():
		_entry_boot_pending = true
		_entry_holds_home = true
		_entry_run()
	else:
		if Net.account_name != "":
			_entry_booted = true # mid-session reload: straight home
		_boot_build()


# ============================================================
# Entry flow (13r)
# ============================================================
## Cold windowed SP boots run the painted entry sequence. MP /
## replay / referee boots, headless test runs, mid-session
## reloads (the account already lives in the Net autoload) and
## the room smoke drivers skip it entirely.

func _entry_applies() -> bool:
	if _entry_booted or mp_active or map_choice_done:
		return false
	if DisplayServer.get_name() == "headless":
		return false
	if Net.account_name != "":
		return false
	if not Net.auto.is_empty() and not Net._entry_mode():
		return false
	return true


## Timed boot steps — every progress value maps to work that has
## ACTUALLY finished (see LoadingScreen's honesty note).
func _entry_run() -> void:
	_entry_wire()
	_entry_state = "loading"
	_loading_screen = LoadingScreen.new()
	add_child(_loading_screen)
	_loading_screen.set_progress(0.04, "Đang khởi động...")
	await get_tree().process_frame
	await get_tree().process_frame
	# Step 1: real preloads of the entry + home artwork.
	for path in ["res://assets/login_bg.png", "res://assets/loading_bg.png",
			"res://assets/login_logo.png", "res://assets/name_panel.png",
			"res://assets/plaque_red.png", "res://assets/home_bg.png",
			"res://assets/home_banner_rooms.png",
			"res://assets/home_banner_soldiers.png",
			"res://assets/matchmaking_frame.png"]:
		load(path)
	_loading_screen.set_progress(0.25, "Đang nạp hình ảnh...")
	await get_tree().process_frame
	# Step 2: the world build (the old _ready body).
	_boot_build()
	_entry_boot_pending = false
	_loading_screen.set_progress(0.55, "Đang dựng thế giới...")
	await get_tree().process_frame
	# Capture hold: the loading shot catches the bar mid-travel.
	if Net.auto.has("mp-shot-loading"):
		await get_tree().create_timer(3.2).timeout
	# Step 3: server connect — best effort; offline/guest play
	# must never be held hostage by a dead relay.
	Net.connect_to_server(Net.DEFAULT_URL)
	var slices := 0
	while not Net.connected and slices < 28:
		await get_tree().create_timer(0.1).timeout
		slices += 1
	_loading_screen.set_progress(0.80, "Đang kết nối máy chủ...")
	# Step 4: session restore from the remembered token.
	var restored := false
	var token := ""
	if not Net.auto.has("mp-norestore"):
		token = Net.saved_session_token()
	if token != "" and Net.connected:
		# A stored token exists ONLY because the player ticked
		# "Ghi nhớ đăng nhập" — say so, or the auth_ok handler
		# treats this as a non-remembered login and deletes the
		# token, making remember-me survive just one restart.
		Net.remember_session = true
		Net.login_token(token)
		slices = 0
		while Net.account_name == "" and slices < 28:
			await get_tree().create_timer(0.1).timeout
			slices += 1
		restored = Net.account_name != ""
		if not restored:
			Net.clear_saved_session()
	_loading_screen.set_progress(1.0, "Sẵn sàng!")
	await get_tree().create_timer(0.35).timeout
	_loading_screen.queue_free()
	_loading_screen = null
	_entry_booted = true
	if restored:
		_entry_state = "welcome"
		_ensure_welcome()
		_welcome_screen.show_welcome()
	elif Net.account_name != "":
		# An auto driver (capture harnesses) authed during connect.
		_entry_route_named_or_home()
	else:
		_entry_state = "login"
		_ensure_login()
		_login_screen.show_login()


func _entry_wire() -> void:
	if _entry_wired:
		return
	_entry_wired = true
	Net.auth_ok.connect(func(_t: String, _p: Dictionary) -> void:
		if _entry_state != "login":
			return
		_login_screen.hide_login()
		if _login_over_home:
			_login_over_home = false
			if Net.has_display_name():
				_entry_state = "off"
				if home != null:
					home.refresh()
			else:
				_entry_state = "name"
				_ensure_name_panel()
				_name_panel.show_panel()
		else:
			_entry_route_named_or_home())
	Net.display_name_changed.connect(func(_n: String) -> void:
		if _entry_state != "name":
			return
		_name_panel.hide_panel()
		if _login_over_home:
			_login_over_home = false
			_entry_state = "off"
			if home != null:
				home.refresh()
		else:
			_entry_to_home())


func _entry_route_named_or_home() -> void:
	if Net.has_display_name():
		_entry_to_home()
	else:
		_entry_state = "name"
		_ensure_name_panel()
		_name_panel.show_panel()


func _entry_to_home() -> void:
	_entry_state = "off"
	_entry_holds_home = false
	show_home()


func _ensure_login() -> void:
	if _login_screen == null:
		_login_screen = LoginScreen.new()
		add_child(_login_screen)
		_login_screen.guest_chosen.connect(_on_entry_guest)


func _ensure_welcome() -> void:
	if _welcome_screen == null:
		_welcome_screen = WelcomeScreen.new()
		add_child(_welcome_screen)
		_welcome_screen.start_pressed.connect(func() -> void:
			_welcome_screen.hide_welcome()
			_entry_route_named_or_home())
		_welcome_screen.switch_account_pressed.connect(func() -> void:
			_welcome_screen.hide_welcome()
			Net.logout_account()
			_entry_state = "login"
			_ensure_login()
			_login_screen.show_login())


func _ensure_name_panel() -> void:
	if _name_panel == null:
		_name_panel = NamePanel.new()
		add_child(_name_panel)


func _on_entry_guest() -> void:
	if _entry_state != "login":
		return
	_login_screen.hide_login()
	if _login_over_home:
		_login_over_home = false
		_entry_state = "off"
	else:
		_entry_to_home()


# ------------------------------------------------ entry test hooks

func entry_state() -> String:
	if _loading_screen != null:
		return "loading"
	if _name_panel != null and _name_panel.is_showing():
		return "name"
	if _welcome_screen != null and _welcome_screen.is_showing():
		return "welcome"
	if _login_screen != null and _login_screen.is_showing():
		return "login"
	if home != null and home.visible:
		return "home"
	return _entry_state


func entry_loading_progress() -> float:
	return _loading_screen.progress() if _loading_screen != null else -1.0


func entry_login_set_tab(register_tab: bool) -> void:
	if _login_screen != null:
		_login_screen.set_tab(register_tab)


func entry_debug_clear_cache() -> String:
	# The utility column (and its Xoá cache action) lives on
	# the welcome screen only — the login screen has none.
	if _welcome_screen != null:
		return _welcome_screen.debug_clear_cache()
	return ""


func entry_open_notices() -> void:
	if _welcome_screen != null and _welcome_screen.is_showing():
		_welcome_screen.debug_open_notices()


func entry_debug_submit_register(user: String, pw: String) -> void:
	if _login_screen != null:
		_login_screen.submit_register_for_test(user, pw)


func entry_debug_name_dice() -> void:
	if _name_panel != null:
		_name_panel.debug_dice()


func entry_debug_name_text() -> String:
	return _name_panel.debug_text() if _name_panel != null else ""


func entry_debug_name_confirm() -> void:
	if _name_panel != null:
		_name_panel.debug_confirm()


func entry_home_name_text() -> String:
	if home != null and home.has_method("chip_name_text"):
		return home.chip_name_text()
	return ""


## The old _ready body: world + bases + HUD construction. The
## 13r entry flow calls it as one timed boot step; every other
## path (MP, replay, referee, headless tests, reloads) calls it
## directly from _ready exactly as before.
func _boot_build() -> void:
	mp_mode = mp_active
	if mp_mode:
		referee_mode = mp_referee
		observer_mode = mp_observer
		replay_mode = mp_replay
		_mp_setup_slots()
		biome_id = String(mp_config.get("biome", "grassland"))
		layout_id = String(mp_config.get("layout", "plains"))
	else:
		biome_id = chosen_biome if Biomes.is_valid(chosen_biome) else "grassland"
		if chosen_biome == "random":
			biome_id = Biomes.ORDER[randi() % Biomes.ORDER.size()]
		layout_id = chosen_layout if World.is_valid_layout(chosen_layout) else "plains"
	world = World.new()
	world.biome_id = biome_id
	world.layout_id = layout_id
	if mp_mode:
		world.base_count = slot_count()
		Animal.deterministic_mode = true
		seed(int(mp_config.get("seed", 12345)) * 1000003 + 17)
	add_child(world)
	world.generate(int(mp_config.get("seed", 12345)) if mp_mode else 12345)
	# Beasts hunt through Main's unit roster; hand them the reference.
	for b in world.beasts:
		b.game = self

	cam = RTSCamera.new()
	cam.world_size = Vector2(World.MAP_W, World.MAP_H) * World.TILE
	add_child(cam)
	cam.position = Vector2(576, 1700)

	# Shared effects layer (water ambience, gather/construction sparks,
	# completion flashes...). Bound after generate() so it can read the
	# lake's water/shore cells.
	vfx = VFX.new()
	vfx.z_index = 95
	add_child(vfx)
	vfx.bind(self, world, cam)

	# 13v skill presentation layer (particles + shaders) and the
	# skill SFX pool on the 13u "SFX" bus.
	skill_fx = SkillFX.new()
	add_child(skill_fx)
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	overlay = Overlay.new()
	overlay.game = self
	overlay.z_index = 90
	add_child(overlay)

	hud = HUD.new()
	hud.game = self
	add_child(hud)

	# 15e: observer matches get the spectator controller (camera
	# modes + bar). Added after the camera and HUD exist; it only
	# ever reads the sim and moves the camera.
	if observer_mode:
		spectator = Spectator.new()
		spectator.game = self
		add_child(spectator)

	if mp_mode:
		_mp_spawn_bases()
	else:
		# Player base: Town Center + 3 villagers (bottom-left). TC origins
		# derive from the world's base centres so layouts that move the
		# bases (Bờ biển) spawn everything in the right place.
		player_tc = _spawn_building("town_center", 0, world.player_base - Vector2i(1, 1), true)
		var spawn_cells := world.adjacent_walkable(player_tc.cells())
		if not spawn_cells.is_empty():
			rally_point = world.cell_center(spawn_cells[0])
		for i in range(3):
			_make_unit(0, world.cell_center(spawn_cells[i % spawn_cells.size()]))
		# Match-start flow (LUONG-BAT-DAU-TRAN): every player also
		# starts with ONE scout cavalry.
		if not spawn_cells.is_empty():
			_make_unit(0, world.cell_center(spawn_cells[3 % spawn_cells.size()]), "cavalry")

		# Enemy base (top-right, P3): a proper blue stronghold — Town
		# Center + Barracks + 2 Houses + Watch Tower, all in enemy art.
		enemy_tc = _spawn_building("town_center", 1, world.enemy_base - Vector2i(1, 1), true)
		_spawn_enemy_base()
		var es_cells := world.adjacent_walkable(enemy_tc.cells())
		for i in range(3):
			_make_unit(1, world.cell_center(es_cells[i % es_cells.size()]))
		if not es_cells.is_empty():
			_make_unit(1, world.cell_center(es_cells[3 % es_cells.size()]), "cavalry")

	# Character draw (SP): the server assigns characters in MP
	# (slot_chars filled from the match payload); offline, both
	# sides draw locally — the player from the 4 mains, the AI
	# from the 4 mains too, and the AI never wears a cosmetic
	# skin. The player's active skin (dormant — nobody owns one
	# yet) would ride in slot_skins[0].
	if not mp_mode:
		var draw_rng := RandomNumberGenerator.new()
		draw_rng.seed = int(Time.get_ticks_msec()) + 99
		slot_chars = [draw_character(draw_rng), draw_character(draw_rng)]
		slot_skins = [Characters.local_active_skin(), ""]

	# Hero presentation layers: Kết Giới rings under the units,
	# player names over the heroes in a late pass (never occluded
	# by bodies; fog still hides them via Unit.visible).
	hero_zone_layer = HeroOverlay.new()
	hero_zone_layer.game = self
	hero_zone_layer.mode = "zones"
	hero_zone_layer.z_index = 5
	add_child(hero_zone_layer)
	hero_name_layer = HeroOverlay.new()
	hero_name_layer.game = self
	hero_name_layer.mode = "names"
	hero_name_layer.z_index = 120
	add_child(hero_name_layer)

	# Fog of War (player perspective) — set up after both bases exist
	# so the opening reveal covers them correctly. In MP the fog is
	# computed for the LOCAL player's faction team.
	fog = Fog.new()
	fog.z_index = 150
	fog.local_team = view_team()
	if replay_mode or observer_mode:
		fog.observer = true # spectators see the whole map (13h/15a)
		# 14a: follow-player needs every team's fog maintained
		# in parallel (playback only — live matches never pay).
		fog.track_teams = true
	add_child(fog)
	fog.setup(self, world)

	# The enemy commander (economy / production / defence / waves) —
	# single-player only; MP matches have no AI.
	if not mp_mode:
		enemy_ai = EnemyAI.new()
		enemy_ai.game = self
		add_child(enemy_ai)

	# Boot: the painted HOME LOBBY (13g) is the landing screen,
	# shown once per app run (a static flag — "Chơi lại" reloads
	# keep the chosen biome and skip it, exactly as the old map
	# panel did). The map panel itself is now the setup view
	# behind the home's Đấu Thường button. Headless runs (the
	# test suite) never show it, so the harness boots straight
	# into the default Grassland match as before.
	if not mp_mode and not map_choice_done and not DisplayServer.get_name() == "headless":
		if not _entry_holds_home:
			show_home()
		# (13r: while the entry flow holds the first screen, it
		# shows the home itself once login/welcome/name resolve.)
		world.set_sky_active(false) # clouds are world-view only
		set_paused(true)

	if mp_mode:
		_mp_bind_net()
		Net.custom_replay_received.connect(func(id: String, room: String) -> void:
			match_replay_id = id # 13y: enables the result screen's Xem lại
			LocalHistory.patch_replay(room, id)
			if hud != null and hud.has_method("refresh_result_actions"):
				hud.refresh_result_actions())
		mp_built = true
		if mp_debug_log:
			print("MPLOG worldhash slot=", local_slot, " hash=", _mp_world_hash())
			print("MPLOG built slot=", local_slot, " team=", view_team(),
					" players=", slot_count())

	if replay_mode:
		_replay_init()

	if ResourceLoader.exists("res://assets/arrow.png"):
		_arrow_tex = load("res://assets/arrow.png")


## Finds a free footprint near the enemy TC and raises the rest of
## the enemy stronghold (complete, in enemy-blue art).
func _spawn_enemy_base() -> void:
	var want := ["barracks", "house", "house", "tower"]
	var placed := {}
	for btype in want:
		var def := get_build_def(btype)
		var spot := Vector2i(-1, -1)
		for r in range(4, 11):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var cand: Vector2i = enemy_tc.origin_cell + Vector2i(dx, dy)
					if world.can_place(cand, def.size):
						spot = cand
						break
				if spot.x >= 0:
					break
			if spot.x >= 0:
				break
		if spot.x >= 0:
			placed[btype] = _spawn_building(btype, 1, spot, true)
	# Naval layouts (Quần đảo / Bờ biển): the enemy also raises a Dock
	# on its shore — the AI's scripted navy trains from it (enemy_ai).
	if world.resolved_layout == "islands" or world.resolved_layout == "coast":
		var dspot := Vector2i(-1, -1)
		for r in range(3, 13):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var cand: Vector2i = enemy_tc.origin_cell + Vector2i(dx, dy)
					if placement_valid_at(cand, "dock"):
						dspot = cand
						break
				if dspot.x >= 0:
					break
			if dspot.x >= 0:
				break
		if dspot.x >= 0:
			_spawn_building("dock", 1, dspot, true)


# ---------------------------------------------------------------- construction

func _spawn_building(btype: String, team: int, origin: Vector2i, complete: bool, owner: int = -1) -> Building:
	var def := get_build_def(btype)
	var b := Building.new()
	b.btype = btype
	b.display_name = def.name
	b.team = team
	b.owner_id = team if owner < 0 else owner
	b.net_id = _alloc_net_id()
	b.origin_cell = origin
	b.size = def.size
	b.build_time = def.build_time
	b.pop_bonus = def.pop
	b.complete = complete
	b.progress = 1.0 if complete else 0.0
	# Art tier follows the OWNER's age (the player's `age`, the AI's team_age).
	b.tier = int(mp_ages[b.owner_id].get("age", 1)) if mp_mode \
			else (age if team == 0 else int(team_age.get(1, 1)))
	b.game = self
	b.world = world
	b.position = Vector2(origin) * World.TILE
	add_child(b) # Building._ready sets its y-sort z_index + tier sprite
	# Architecture (Castle tech, GDD section 6): buildings raised
	# after the research are sturdier (spawn-time, deterministic;
	# snapshot restores re-apply it from the restored tech state).
	if tech_level(b.owner_id, "architecture") > 0:
		b.max_hp *= Stats.ARCHITECTURE_HP_MULT
		b.hp = b.max_hp
	buildings.append(b)
	for c in b.cells():
		world.set_solid(c, true)
	if b.btype.begins_with("gate"):
		world.set_gate(origin, team)
	if Building.is_wall_type(b.btype):
		refresh_wall_variants_around(origin)
	return b


## Wall/gate art follows adjacency: a segment with a wall neighbour
## above or below (and not a clean east-west run) shows the corner
## piece; everything else shows the straight piece. Recomputed for a
## segment and its four neighbours whenever one is placed/destroyed.
func refresh_wall_variants_around(cell: Vector2i) -> void:
	for c in [cell, cell + Vector2i(1, 0), cell + Vector2i(-1, 0),
			cell + Vector2i(0, 1), cell + Vector2i(0, -1)]:
		var b := building_at(world.cell_center(c))
		if b != null and Building.is_wall_type(b.btype):
			_update_wall_variant(b)


func _update_wall_variant(b: Building) -> void:
	var c := b.origin_cell
	var ew := _is_wall_at(c + Vector2i(1, 0)) and _is_wall_at(c + Vector2i(-1, 0))
	var ns := _is_wall_at(c + Vector2i(0, 1)) or _is_wall_at(c + Vector2i(0, -1))
	var v := "corner" if (ns and not ew) else "straight"
	if b.wall_variant != v:
		b.wall_variant = v
		b.refresh_wall_art()


func _is_wall_at(c: Vector2i) -> bool:
	var b := building_at(world.cell_center(c))
	return b != null and Building.is_wall_type(b.btype) and not b.destroyed


func _make_unit(team: int, pos: Vector2, kind: String = "villager", owner: int = -1) -> Unit:
	var u := Unit.new()
	u.team = team
	u.owner_id = team if owner < 0 else owner
	u.net_id = _alloc_net_id()
	u.unit_type = kind
	u.game = self
	u.world = world
	u.position = pos
	u.z_index = 20
	add_child(u)
	units.append(u)
	return u


func spawn_villager(from_building: Building) -> void:
	spawn_unit(from_building, "villager")


func spawn_unit(from_building: Building, kind: String) -> void:
	if SHIP_COSTS.has(kind):
		spawn_ship(from_building, kind)
		return
	var adj := world.adjacent_walkable(from_building.cells())
	if adj.is_empty():
		return
	var u := _make_unit(from_building.team, world.cell_center(adj[0]), kind, from_building.owner_id)
	_bump_stat(from_building.owner_id, "trained") # 13y
	if vfx != null:
		# Training complete: a small gold glint burst at the spawn point.
		for i in range(3):
			vfx.glint(u.global_position + Vector2(randf_range(-10.0, 10.0), randf_range(-24.0, -12.0)),
					Color(1.0, 0.85, 0.35, 0.95), 11.0, 0.55)
	if mp_mode:
		# Every owner's trained units honour that owner's rally point;
		# only the local player gets the message.
		var rp: Vector2 = mp_rally[from_building.owner_id]
		if rp != Vector2.ZERO and u.global_position.distance_to(rp) > 44.0:
			var rc2 := world.nearest_walkable(world.world_to_cell(rp))
			if rc2.x >= 0:
				u.order_move_cell(rc2)
		if from_building.owner_id == local_slot:
			hud.show_message("%s ready" % UNIT_NAMES.get(kind, kind))
	elif from_building.team == 0:
		# Walk to the rally point if it is set away from the spawn spot.
		if rally_point != Vector2.ZERO and u.global_position.distance_to(rally_point) > 44.0:
			var rc := world.nearest_walkable(world.world_to_cell(rally_point))
			if rc.x >= 0:
				u.order_move_cell(rc)
		hud.show_message("%s ready" % UNIT_NAMES.get(kind, kind))


## A finished ship leaves the Dock onto the nearest navigable water
## cell. On frozen (Snow) water there is none: the hull is built but
## cannot launch, so it waits at the dock (no spawn point exists).
func spawn_ship(from_building: Building, kind: String) -> Ship:
	var adj := world.water_adjacent_to(from_building.cells())
	if adj.is_empty():
		if is_local_owner(from_building.owner_id):
			hud.show_message("Nước đóng băng — thuyền không hạ thủy được")
		return null
	var s := Ship.new()
	s.ship_type = kind
	s.team = from_building.team
	s.owner_id = from_building.owner_id
	s.net_id = _alloc_net_id()
	s.game = self
	s.world = world
	s.home_dock = from_building
	s.position = world.cell_center(adj[0])
	add_child(s)
	ships.append(s)
	_bump_stat(from_building.owner_id, "trained") # 13y (launched hulls only)
	if vfx != null:
		vfx.ripple(s.global_position, Color(0.85, 0.95, 1.0, 0.6), 22.0, 1.2)
	if is_local_owner(from_building.owner_id):
		hud.show_message("%s hạ thủy" % SHIP_NAMES.get(kind, kind))
	return s


func get_team_dock(team: int) -> Building:
	for b in buildings:
		if b.team == team and b.btype == "dock" and b.complete and not b.destroyed:
			return b
	return null


func nearest_dock(team: int, from_pos: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for b in buildings:
		if b.team == team and b.btype == "dock" and b.complete and not b.destroyed:
			var d := from_pos.distance_squared_to(b.position + Vector2(b.size) * World.TILE * 0.5)
			if d < bd:
				bd = d
				best = b
	return best


## The building that trains `kind` for a player slot (MP): Town
## Center for villagers, the slot's Castle for the King, the
## slot's Barracks for everything else.
func mp_training_building(owner: int, kind: String) -> Building:
	if kind == "villager":
		return tc_of(owner)
	if kind == "king":
		return castle_of(owner)
	for b in buildings:
		if b.owner_id == owner and b.btype == "barracks" and not b.destroyed:
			return b
	return null


## The (living) Castle owned by a player slot, or null.
func castle_of(owner: int) -> Building:
	for b in buildings:
		if b.owner_id == owner and b.btype == "castle" and not b.destroyed:
			return b
	return null


func get_team_castle(team: int) -> Building:
	for b in buildings:
		if b.team == team and b.btype == "castle" and b.complete and not b.destroyed:
			return b
	return null


# ---------------------------------------------------------------- the hero

## One draw from the character pool (the 4 mains). The server
## draws for MP rooms; SP draws locally (see _ready). Cosmetic
## skins are never in the pool.
static func draw_character(rng: RandomNumberGenerator) -> String:
	return Characters.CHAR_IDS[rng.randi() % Characters.CHAR_IDS.size()]


## The main character ASSIGNED to `owner` for this match (kit +
## identity). MP: from the server payload. SP: the local draw.
func char_for(owner: int) -> String:
	if owner >= 0 and owner < slot_chars.size():
		return slot_chars[owner]
	return Characters.DEFAULT_CHAR


## What `owner`'s hero LOOKS like: the active cosmetic skin when
## one is set (and owned — enforced where the value is stored),
## else the drawn character itself. Kits never follow this.
func appearance_for(owner: int) -> String:
	if owner >= 0 and owner < slot_skins.size() and slot_skins[owner] != "":
		return slot_skins[owner]
	return char_for(owner)


## The display name over a hero's head: the owner's player name.
func hero_display_name(owner: int) -> String:
	if mp_mode:
		if owner >= 0 and owner < slot_names.size():
			return slot_names[owner]
		return "Người chơi"
	if owner == 0:
		# The local player's panel name — HUD._resolve_player_name
		# is the source of truth the players panel / result screen
		# use: the account display name, else the guest label.
		# Never a "Bạn" placeholder over the hero (owner rule, 15d).
		return Net.display_name() if Net.account_name != "" else "Khách"
	return "Máy"


func local_hero() -> Unit:
	for u in units:
		if is_instance_valid(u) and u.owner_id == (local_slot if mp_mode else 0) \
				and u.unit_type == "king" and not u.is_dead():
			return u
	return null


func hero_of_team(team: int) -> Unit:
	for u in units:
		if is_instance_valid(u) and u.team == team \
				and u.unit_type == "king" and not u.is_dead():
			return u
	return null


## A living King owned by `owner` (owner_id semantics: slot in MP,
## team in SP — the two coincide on every unit either way).
func king_alive(owner: int) -> bool:
	for u in units:
		if is_instance_valid(u) and u.owner_id == owner \
				and u.unit_type == "king" and not u.is_dead():
			return true
	return false


## A King already in a training queue of `owner`'s buildings.
func king_queued(owner: int) -> bool:
	for b in buildings:
		if b.owner_id == owner and b.train_types.has("king"):
			return true
	return false


func king_busy(owner: int) -> bool:
	return king_alive(owner) or king_queued(owner)


## Aura query (kits): is `u` inside the aura radius of an ALLIED
## hero (same team) whose drawn character is `char_id`?
## Deterministic — pure position/team arithmetic over sim state.
## The hero himself only counts when `include_self` (defensive
## auras: Kim Hoa's regen, Bạch Sa's mitigation).
func hero_aura_covers(u: Unit, char_id: String, include_self := false) -> bool:
	var k := hero_of_team(u.team)
	if k == null or char_for(k.owner_id) != char_id:
		return false
	if k == u and not include_self:
		return false
	return u.global_position.distance_to(k.global_position) \
			<= Stats.AURA_RANGE_TILES * World.TILE


## Movement-speed factor from auras: the Dragoon's allied
## "Long Hành" (x1.10 inside his aura, himself included — a
## mobility aura, like the defensive ones, is never withheld
## from the hero).
func hero_speed_factor(u: Unit) -> float:
	var f := 1.0
	if hero_aura_covers(u, "dragoon", true):
		f *= float(Stats.HERO_KITS["dragoon"]["aura_spd"])
	return f


## Damage-taken factor (the Knight's "Hộ Vệ"): x0.92 inside his
## aura (allies, himself included).
func hero_damage_factor(u: Unit) -> float:
	var f := 1.0
	if hero_aura_covers(u, "knight", true):
		f *= float(Stats.HERO_KITS["knight"]["aura_mitig"])
	return f


## Aura display query (the hero's pulsing ring, per character):
## does this hero's aura currently touch anyone it applies to?
func aura_active_for(king: Unit) -> bool:
	var ch := char_for(king.owner_id)
	var r := Stats.AURA_RANGE_TILES * World.TILE
	for u in units:
		if u == king or not is_instance_valid(u) or u.is_dead():
			continue
		if u.global_position.distance_to(king.global_position) > r:
			continue
		match ch:
			"berserker", "archer", "assassin":
				# Offensive auras: an allied military unit in reach.
				if u.team == king.team and u.is_military():
					return true
			"knight", "mage", "paladin", "dragoon", "ranger":
				# Support auras: any ally in reach.
				if u.team == king.team:
					return true
	return false


## The destination of a dash cast: `target` clamped to
## `max_tiles` from the hero and snapped to the nearest walkable
## cell centre (a dash never lands in water or inside a wall).
## A missing target (the NO_TARGET sentinel — AI casts, old-form
## commands) dashes straight along the hero's facing.
const NO_TARGET := Vector2(-99999.0, -99999.0)


func _dash_destination(hero: Unit, target: Vector2, max_tiles: float) -> Vector2:
	var from := hero.global_position
	var dest := target
	if dest.x < -90000.0:
		dest = from + _facing_vec(hero) * max_tiles * World.TILE
	var d := dest - from
	var max_d := max_tiles * World.TILE
	if d.length() > max_d:
		dest = from + d.normalized() * max_d
	var cell := world.nearest_walkable(world.world_to_cell(dest))
	return world.cell_center(cell)


## Teleport a hero (dash / blink landing): position is sim state;
## the path is dropped so the state machine restarts cleanly
## from the landing point.
func _hero_reposition(hero: Unit, dest: Vector2) -> void:
	hero.global_position = dest
	hero.path.clear()
	hero.path_cells.clear()
	if hero.state in ["move", "to_node", "return", "to_build", "to_field", "flee"]:
		hero.state = "idle"


## The enemy unit nearest to `point` (within `slack` px of it);
## ties break by net_id so every peer picks the same victim.
func _enemy_unit_near(hero: Unit, point: Vector2, slack: float) -> Unit:
	var best: Unit = null
	var bd := slack
	for u in units:
		if not attack_allowed(hero.owner_id, u.owner_id) \
				or not u.is_targetable():
			continue
		var d: float = u.global_position.distance_to(point)
		if d < bd or (best != null and absf(d - bd) <= 0.001 and u.net_id < best.net_id):
			bd = d
			best = u
	return best


## Cast a hero's ONE active skill (16b — every hero has exactly
## one, on the unified 75 s cooldown). Returns false when the
## hero is dead, missing, or on cooldown — the MP validator and
## the HUD both gate on this. Effects write ONLY sim state (unit
## effect fields, HP, skill_zones); the burst/ring VFX is
## presentation. Targeted skills (Mưa Tên / Thiên Thạch / Long
## Thương / Ám Sát) carry `target`; NO_TARGET means the cast
## derives its own (AI casts aim explicitly; an untargeted
## dash/blink resolves from the hero's position and facing).
func cast_hero_skill(hero: Unit, target: Vector2 = NO_TARGET) -> bool:
	if hero == null or not is_instance_valid(hero) or hero.is_dead() \
			or hero.skill_cd_t > 0.0:
		return false
	var ch := char_for(hero.owner_id)
	var kit: Dictionary = Stats.HERO_KITS.get(ch, {})
	if kit.is_empty():
		return false
	var r := Stats.AURA_RANGE_TILES * World.TILE
	var pos := hero.global_position
	match ch:
		"knight": # Khiên Sư Tử — 250 absorb shield + mass taunt
			hero.shield_hp = float(kit["shield"])
			hero.shield_t = float(kit["shield_t"])
			for u in units:
				if not attack_allowed(hero.owner_id, u.owner_id) \
						or not u.is_targetable() or not u.is_military():
					continue
				if u.global_position.distance_to(pos) <= r:
					u.taunt_t = float(kit["taunt_t"])
					u.taunt_id = hero.net_id
			if skill_fx != null:
				skill_fx.shield_fx(pos + Vector2(0, -20))
		"berserker": # Rìu Xoáy Cuồng Nộ — whirlwind around himself
			var sr := float(kit["radius_tiles"]) * World.TILE
			for u in units:
				if not attack_allowed(hero.owner_id, u.owner_id) \
						or not u.is_targetable():
					continue
				if u.global_position.distance_to(pos) <= sr:
					u.take_damage(float(kit["dmg"]), hero)
			if skill_fx != null:
				skill_fx.fan_fx(pos, _facing_vec(hero))
		"archer": # Mưa Tên — arrow rain at a point up to 8 tiles
			var zp := _skill_clamp_target(hero, target,
					float(kit["cast_tiles"]))
			var zr := float(kit["radius_tiles"]) * World.TILE
			skill_zones.append({"kind": "arrow_rain", "pos": zp,
					"t": float(kit["rain_t"]), "acc": 0.0, "tick_n": 0,
					"dmg": float(kit["rain_dmg"]), "radius": zr,
					"owner": hero.owner_id})
			if skill_fx != null:
				skill_fx.zone_fx("arrow_rain", zp, zr,
						float(kit["rain_t"]))
		"mage": # Thiên Thạch Ma Thuật — meteor at a point
			var c := _skill_clamp_target(hero, target)
			var mr := float(kit["radius_tiles"]) * World.TILE
			for u in units:
				if not attack_allowed(hero.owner_id, u.owner_id) \
						or not u.is_targetable():
					continue
				if u.global_position.distance_to(c) <= mr:
					u.take_damage(float(kit["dmg"]), hero)
			if skill_fx != null:
				skill_fx.plunge_fx(c, func() -> void: _shake_t = 0.3)
		"paladin": # Thánh Quang Hồi Phục — heal + cleanse in aura
			for u in units:
				if not is_instance_valid(u) or u.team != hero.team \
						or u.is_dead():
					continue
				if u.global_position.distance_to(pos) <= r:
					u.hp = minf(u.max_hp, u.hp + float(kit["heal"]))
					u.cleanse_effects()
			if skill_fx != null:
				skill_fx.pillar_fx(pos, r)
		"dragoon": # Long Thương Xuyên Tâm — line dash, path damage
			var dest := _dash_destination(hero, target,
					float(kit["dash_tiles"]))
			var half := float(kit["path_half_px"]) + 8.0
			for u in units:
				if not attack_allowed(hero.owner_id, u.owner_id) \
						or not u.is_targetable():
					continue
				if _seg_dist(u.global_position, pos, dest) <= half:
					u.take_damage(float(kit["dmg"]), hero)
			_hero_reposition(hero, dest)
			if skill_fx != null:
				skill_fx.arc_fx(pos + Vector2(0, -24),
						dest + Vector2(0, -24), Color(0.45, 0.65, 1.0))
		"assassin": # Ám Sát — blink behind an enemy, 160 stab
			var arange := float(kit["range_tiles"]) * World.TILE
			var victim: Unit = null
			if target.x > -90000.0:
				victim = _enemy_unit_near(hero, target, 1.2 * World.TILE)
			else:
				victim = _enemy_unit_near(hero, pos, arange)
			if victim == null or victim.global_position.distance_to(pos) \
					> arange + 1.2 * World.TILE:
				return false
			var away: Vector2 = victim.global_position - pos
			if away.length() < 1.0:
				away = _facing_vec(hero)
			var behind: Vector2 = victim.global_position \
					+ away.normalized() * 24.0
			var bcell := world.nearest_walkable(world.world_to_cell(behind))
			_hero_reposition(hero, world.cell_center(bcell))
			victim.take_damage(float(kit["dmg"]), hero)
			if skill_fx != null:
				skill_fx.arc_fx(pos + Vector2(0, -24),
						victim.global_position + Vector2(0, -24),
						Color(0.8, 0.35, 0.45))
		"ranger": # Kiếm Vũ Lữ Hành — flurry state (Main ticks it)
			hero.flurry_left = int(kit["slashes"])
			hero.flurry_t = 0.0
			hero.flurry_cursor = -1
		_:
			return false
	hero.skill_cd_t = Stats.hero_cd(ch)
	# Presentation hook (13n): the hero plays its cast pose — a
	# render-side timer like the VFX, never sim state.
	hero._king_cast_t = Unit.KING_CAST_TIME
	_skill_cast_fx(hero, 1, ch)
	if vfx != null:
		var col := _skill_colour(ch)
		vfx.burst(pos + Vector2(0, -20), [col], 14, 46.0)
		vfx.flash(pos + Vector2(0, -20), col, 52.0, 0.3)
	return true


## Per-skill signature colour for the generic cast burst.
func _skill_colour(ch: String) -> Color:
	match ch:
		"knight": return Color(1.0, 0.85, 0.4, 0.9)
		"berserker": return Color(1.0, 0.5, 0.25, 0.9)
		"archer": return Color(0.55, 0.95, 0.6, 0.9)
		"mage": return Color(0.75, 0.55, 1.0, 0.9)
		"paladin": return Color(1.0, 0.96, 0.82, 0.9)
		"dragoon": return Color(0.45, 0.65, 1.0, 0.9)
		"assassin": return Color(0.8, 0.35, 0.45, 0.9)
		"ranger": return Color(0.6, 0.95, 0.88, 0.9)
	return Color(1.0, 0.85, 0.4, 0.9)


## The Ranger's Kiếm Vũ Lữ Hành: while a hero's flurry lasts,
## one slash lands every slash_interval seconds on the next
## enemy (net_id round-robin) inside the flurry radius — the
## five slashes spread evenly over the enemies in reach, and a
## lone enemy eats all five. Deterministic: the foe list is
## re-derived from sim positions in net_id order each slash.
func _update_hero_flurries(delta: float) -> void:
	for u in units:
		if not is_instance_valid(u) or u.unit_type != "king" \
				or u.is_dead() or u.flurry_left <= 0:
			continue
		u.flurry_t -= delta
		if u.flurry_t > 0.0:
			continue
		var kit: Dictionary = Stats.HERO_KITS.get(char_for(u.owner_id), {})
		var r := float(kit.get("radius_tiles", 2.0)) * World.TILE
		var foes: Array = []
		for v in units:
			if attack_allowed(u.owner_id, v.owner_id) \
					and v.is_targetable() \
					and v.global_position.distance_to(u.global_position) <= r:
				foes.append(v)
		if foes.is_empty():
			u.flurry_left = 0
			continue
		foes.sort_custom(func(a, b): return a.net_id < b.net_id)
		var pick: Unit = foes[0]
		for v in foes:
			if v.net_id > u.flurry_cursor:
				pick = v
				break
		u.flurry_cursor = pick.net_id
		pick.take_damage(float(kit.get("slash_dmg", 32.0)), u)
		u.flurry_left -= 1
		u.flurry_t = float(kit.get("slash_interval", 0.2))
		if vfx != null:
			vfx.flash(pick.global_position + Vector2(0, -18),
					Color(0.65, 0.95, 0.9, 0.8), 26.0, 0.15)


## The hero's facing line for the line skills: Unit.facing is the
## 4-way string the movement code maintains ("right" by default
## posture is "down").
func _facing_vec(hero: Unit) -> Vector2:
	match hero.facing:
		"right": return Vector2.RIGHT
		"left": return Vector2.LEFT
		"up": return Vector2.UP
	return Vector2.DOWN

## True for skills cast at a chosen ground point (HUD targeting
## flow: tap button → tap ground). 16b: only the ONE skill exists
## (idx is always 1); Mưa Tên / Thiên Thạch aim at a point, Long
## Thương dashes toward it, Ám Sát picks the enemy nearest it.
## The self-centred skills (Khiên Sư Tử / Rìu Xoáy / Thánh Quang
## / Kiếm Vũ) cast instantly.
func skill_is_targeted(char_id: String, idx: int) -> bool:
	if idx != 1:
		return false
	return char_id in ["archer", "mage", "dragoon", "assassin"]


func _skill_clamp_target(hero: Unit, target: Vector2,
		max_tiles: float = Stats.SKILL_CAST_RANGE_TILES) -> Vector2:
	if target.x < -90000.0:
		return hero.global_position
	var max_d := max_tiles * World.TILE
	var d := target - hero.global_position
	if d.length() > max_d:
		return hero.global_position + d.normalized() * max_d
	return target


func _skill_cast_fx(hero: Unit, idx: int, char_id: String) -> void:
	# Presentation only (also runs on every MP peer for its own
	# speakers): cast flash + this skill's synthesised SFX.
	# 15e: the spectator auto-camera counts every cast as action.
	if spectator != null:
		spectator.note_cast(hero.global_position)
	if skill_fx != null:
		skill_fx.cast_fx(hero.global_position,
				Color(1.0, 0.85, 0.5) if idx == 3 else Color(0.85, 0.9, 1.0))
	_play_skill_sfx(char_id, idx)


func _play_skill_sfx(char_id: String, idx: int) -> void:
	if _sfx_pool.is_empty():
		return
	var path := "res://assets/sfx/%s_%d.wav" % [char_id, idx]
	if not ResourceLoader.exists(path):
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_rr % _sfx_pool.size()]
	_sfx_rr += 1
	p.stream = load(path)
	p.play()


## HUD targeting flow: arm the ground-targeted skill; the next
## world click casts it (Esc / right-click cancels — see
## _unhandled_input). Instant skills never arm.
func begin_skill_targeting(idx: int) -> void:
	var hero := local_hero()
	if hero == null:
		return
	if skill_is_targeted(slot_chars[hero.owner_id], idx):
		skill_targeting = idx
		hud.show_message("Chọn vị trí để tung %s" % _skill_name(hero, idx))


func _skill_name(hero: Unit, idx: int) -> String:
	var cd := Characters.kit_of(slot_chars[hero.owner_id])
	return String(cd.get("skill", ""))


## Local cast entry for the ONE skill (HUD button + smoke
## drivers): SP applies at once; MP sends the lockstep command.
func cast_local_skill_at(idx: int, target: Vector2) -> void:
	var hero := local_hero()
	if hero == null or idx != 1:
		return
	if mp_mode:
		_mp_send_command({"kind": "skill", "u": hero.net_id, "s": 1,
				"x": target.x, "y": target.y})
	else:
		if cast_hero_skill(hero, target):
			_note_action(0) # 13y APM


## The lingering-zone sim: 0.5 s sub-ticks. The only zone kind
## left in 16b is the Archer's arrow rain — three damage waves
## (sub-ticks 1, 2, 3) of the zone's own dmg over its 2 s life.
func _update_skill_zones(delta: float) -> void:
	for zi in range(skill_zones.size() - 1, -1, -1):
		var z: Dictionary = skill_zones[zi]
		z["t"] = float(z["t"]) - delta
		if float(z["t"]) <= 0.0:
			skill_zones.remove_at(zi)
			continue
		z["acc"] = float(z["acc"]) + delta
		while float(z["acc"]) >= 0.5:
			z["acc"] = float(z["acc"]) - 0.5
			_skill_zone_subtick(z)


func _skill_zone_subtick(z: Dictionary) -> void:
	if String(z["kind"]) != "arrow_rain":
		return
	z["tick_n"] = int(z.get("tick_n", 0)) + 1
	if int(z["tick_n"]) > 3:
		return
	var c: Vector2 = z["pos"]
	var r := float(z["radius"])
	for u in units:
		if not attack_allowed(int(z["owner"]), u.owner_id) \
				or not u.is_targetable():
			continue
		if u.global_position.distance_to(c) <= r:
			u.take_damage(float(z.get("dmg", 0.0)), null)


## Distance from point p to segment a-b (dash path sweeps).
func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.0:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The local player's cast entry (HUD skill button): SP applies
## at once; MP goes through the lockstep command pipeline like
## every other order (the referee's sim validates it the same).
func cast_local_skill() -> bool:
	var hero := local_hero()
	if hero == null:
		return false
	if mp_mode:
		_mp_send_command({"kind": "skill", "u": hero.net_id})
		return true
	var ok := cast_hero_skill(hero)
	if ok:
		_note_action(0) # 13y APM
	return ok


## MP validator for the "skill" command: the unit must be the
## sender's own living hero; cooldown gating lives in the cast.
## 16b: exactly ONE skill exists — "s" is always 1; an optional
## target point "x"/"y" rides the command for targeted skills.
## A command without "x" is the untargeted cast (NO_TARGET
## derives the destination inside the cast).
func _mp_apply_skill(from_slot: int, unit_id: int) -> bool:
	return _mp_apply_skill_cmd(from_slot, {"u": unit_id})


func _mp_apply_skill_cmd(from_slot: int, cmd: Dictionary) -> bool:
	var u := unit_of_net_id(int(cmd.get("u", -1)))
	if u == null or u.owner_id != from_slot or u.unit_type != "king" \
			or u.is_dead():
		return false
	if int(cmd.get("s", 1)) != 1:
		return false
	var tgt := Vector2(float(cmd.get("x", u.global_position.x)),
			float(cmd.get("y", u.global_position.y)))
	return cast_hero_skill(u, tgt) if cmd.has("x") else cast_hero_skill(u)


## The local player's usable Dock (selected one first) — MP paths.
func local_dock() -> Building:
	if selected_building != null and selected_building.btype == "dock" \
			and selected_building.complete and is_local_owner(selected_building.owner_id):
		return selected_building
	for b in buildings:
		if b.owner_id == local_slot and b.btype == "dock" and b.complete and not b.destroyed:
			return b
	return null


## Player ship training at the selected Dock (the AI pays from its
## own ledger and queues directly — see enemy_ai._navy).
func can_train_ship(kind: String) -> bool:
	if mp_mode:
		if local_dock() == null:
			return false
		var mcosts: Dictionary = SHIP_COSTS[kind]
		for r in mcosts:
			if int(mp_wallets[local_slot].get(r, 0)) < int(mcosts[r]):
				return false
		return true
	var dock := selected_building
	if dock == null or dock.btype != "dock" or not dock.complete or dock.team != 0:
		dock = get_team_dock(0)
		if dock == null:
			return false
	var costs: Dictionary = SHIP_COSTS[kind]
	for r in costs:
		if int(resources.get(r, 0)) < int(costs[r]):
			return false
	return true


func train_ship(kind: String) -> bool:
	if mp_mode:
		var mdock := local_dock()
		if mdock == null:
			hud.show_message("Cần Bến thuyền")
			return false
		if not can_train_ship(kind):
			hud.show_message("Not enough resources")
			return false
		_mp_send_command({"kind": "train_ship", "b": mdock.net_id, "unit": kind})
		return true
	var dock := selected_building
	if dock == null or dock.btype != "dock" or not dock.complete or dock.team != 0:
		dock = get_team_dock(0)
	if dock == null:
		hud.show_message("Cần Bến thuyền")
		return false
	if not can_train_ship(kind):
		hud.show_message("Not enough resources")
		return false
	var costs: Dictionary = SHIP_COSTS[kind]
	for r in costs:
		resources[r] = int(resources[r]) - int(costs[r])
	dock.start_training(kind)
	_note_action(0) # 13y APM
	return true


func on_ship_dead(s: Ship) -> void:
	ships.erase(s)
	if selected_ship == s:
		selected_ship = null


func get_dropoff(team: int) -> Building:
	return player_tc if team == 0 else enemy_tc


## Whether a completed building accepts drop-offs of `rtype`:
## Town Center + Storage take everything, Mining Camps take stone and
## gold, Lumber Camps take wood.
func dropoff_accepts(b: Building, rtype: String) -> bool:
	match b.btype:
		"town_center", "storage":
			return true
		"mining_camp":
			return rtype == "stone" or rtype == "gold"
		"lumber_camp":
			return rtype == "wood"
	return false


## Nearest drop-off building for a load of `rtype` carried from
## `from_pos`: the team's Town Center is the fallback; any nearer
## completed building that accepts the type wins (see dropoff_accepts).
func get_dropoff_for(team: int, rtype: String, from_pos: Vector2, owner: int = -1) -> Building:
	if mp_mode and owner >= 0:
		# MP: a villager deposits at its OWNING player's buildings
		# (allies' drop-offs are not shared), TC first as fallback.
		var obest: Building = tc_of(owner)
		if obest == null or not is_instance_valid(obest) or obest.destroyed:
			obest = null
			for b in buildings:
				if b.owner_id == owner and b.complete and not b.destroyed and dropoff_accepts(b, rtype):
					obest = b
					break
			if obest == null:
				return null
		var obd := from_pos.distance_squared_to(
				obest.position + Vector2(obest.size) * World.TILE * 0.5)
		for b in buildings:
			if b.owner_id == owner and b.complete and not b.destroyed \
					and b.btype != "town_center" and dropoff_accepts(b, rtype):
				var d2 := from_pos.distance_squared_to(
						b.position + Vector2(b.size) * World.TILE * 0.5)
				if d2 < obd:
					obd = d2
					obest = b
		return obest
	var best: Building = player_tc if team == 0 else enemy_tc
	if best == null or not is_instance_valid(best) or best.destroyed:
		# Town Center gone: fall back to any accepting building.
		best = null
		for b in buildings:
			if b.team == team and b.complete and not b.destroyed and dropoff_accepts(b, rtype):
				best = b
				break
		if best == null:
			return null
	var best_d := from_pos.distance_squared_to(
			best.position + Vector2(best.size) * World.TILE * 0.5)
	for b in buildings:
		if b.team == team and b.complete and b.btype != "town_center" \
				and dropoff_accepts(b, rtype):
			var d := from_pos.distance_squared_to(
					b.position + Vector2(b.size) * World.TILE * 0.5)
			if d < best_d:
				best_d = d
				best = b
	return best


func on_building_complete(b: Building) -> void:
	_bump_stat(b.owner_id, "built") # 13y
	if not mp_mode or b.owner_id == local_slot:
		hud.show_message("%s complete" % b.display_name)
	if vfx != null:
		# Completion: flash over the art + a dust ring at its base.
		var centre: Vector2 = b.position + Vector2(b.size) * World.TILE * 0.5
		vfx.flash(centre + Vector2(0, -14), Color(1.0, 0.95, 0.8, 0.8), 84.0, 0.35)
		vfx.ripple(centre + Vector2(0, 8), Color(0.85, 0.78, 0.6, 0.55),
				Vector2(b.size).x * World.TILE * 0.62, 0.9)
	b.queue_redraw()


# ---------------------------------------------------------------- VFX event hooks
## Called from Unit at real gameplay events; Main translates them into
## effects on the shared VFX layer. Colours per resource type.

func res_color(rtype: String) -> Color:
	match rtype:
		"wood":
			return Color(0.55, 0.80, 0.35)
		"gold":
			return Color(1.0, 0.85, 0.30)
		"stone":
			return Color(0.78, 0.79, 0.82)
		"food":
			return Color(1.0, 0.55, 0.60)
	return Color(1, 1, 1)


func on_node_gathered(node: ResourceNode) -> void:
	if vfx == null or node == null:
		return
	var pos: Vector2 = node.global_position + Vector2(0, -12)
	match node.rtype:
		"wood":
			vfx.burst(pos, [Color(0.35, 0.72, 0.28), Color(0.55, 0.85, 0.35), Color(0.25, 0.55, 0.2)],
					7, 46.0, 0.55, 9.0, 150.0)
		"stone":
			vfx.burst(pos, [Color(0.72, 0.73, 0.76), Color(0.55, 0.56, 0.6), Color(0.9, 0.9, 0.92)],
					6, 55.0, 0.4, 6.5, 190.0)
		"gold":
			vfx.burst(pos, [Color(1.0, 0.85, 0.3), Color(0.95, 0.7, 0.2), Color(1.0, 0.95, 0.6)],
					6, 55.0, 0.4, 6.5, 190.0)
			vfx.glint(pos, Color(1.0, 0.9, 0.45, 0.95), 11.0, 0.5)
		"food":
			vfx.burst(pos, [Color(1.0, 0.55, 0.6), Color(0.92, 0.35, 0.45), Color(1.0, 0.75, 0.7)],
					6, 40.0, 0.6, 7.5, 90.0)
			vfx.glint(pos + Vector2(4, -4), Color(1.0, 0.7, 0.7, 0.9), 9.0, 0.5)


func on_node_depleted(node: ResourceNode) -> void:
	if vfx == null or node == null:
		return
	var pos: Vector2 = node.global_position
	match node.rtype:
		"wood":
			# Tree falls: bigger leaf burst + a dust puff at the stump.
			vfx.burst(pos + Vector2(0, -16), [Color(0.35, 0.72, 0.28), Color(0.55, 0.85, 0.35), Color(0.45, 0.65, 0.25)],
					16, 70.0, 0.8, 7.0, 170.0)
			vfx.puff(pos, Color(0.6, 0.55, 0.45, 0.5), 5, 18.0, 1.1, 15.0)
		"stone", "gold":
			vfx.puff(pos, Color(0.62, 0.62, 0.65, 0.55), 7, 20.0, 1.2, 16.0)
			vfx.burst(pos + Vector2(0, -6), [Color(0.72, 0.73, 0.76), Color(0.55, 0.56, 0.6)],
					8, 55.0, 0.45, 5.0, 200.0)
		"food":
			vfx.puff(pos, Color(0.85, 0.55, 0.5, 0.45), 5, 16.0, 1.0, 13.0)


func on_build_effect(site: Building, builder: Unit) -> void:
	if vfx == null or site == null:
		return
	# Dust puff somewhere along the site's base + hammer glints at the
	# builder's hands every other tick.
	var base: Vector2 = site.position + Vector2(
			randf_range(4.0, site.size.x * World.TILE - 4.0), site.size.y * World.TILE - 3.0)
	vfx.puff(base, Color(0.72, 0.66, 0.55, 0.55), 3, 14.0, 0.9, 13.0)
	if builder != null and randf() < 0.5:
		vfx.glint(builder.global_position + Vector2(randf_range(-6.0, 6.0), -34.0),
				Color(1.0, 0.9, 0.5, 0.9), 8.0, 0.35)


func on_deposit_effect(team: int, rtype: String, from_pos: Vector2) -> void:
	if vfx == null:
		return
	var b := get_dropoff_for(team, rtype, from_pos)
	if b == null:
		return
	var top: Vector2 = b.position + Vector2(b.size) * World.TILE * Vector2(0.5, 0.0) + Vector2(0, -6)
	var col := res_color(rtype)
	vfx.glint(top + Vector2(randf_range(-8.0, 8.0), 0), Color(col, 0.95), 10.0, 0.5)
	vfx.burst(top, [col], 3, 26.0, 0.35, 5.0, 60.0)


# ---------------------------------------------------------------- P3 combat

## Looses an arrow from `from_pos` at `target` (Unit or Building).
## Damage is precomputed by the shooter via Stats (counters included);
## `attacker` is the shooting Unit or Building (may be null).
func fire_arrow(from_pos: Vector2, target, dmg: float, attacker) -> void:
	if target == null or not is_instance_valid(target):
		return
	var spr := Sprite2D.new()
	spr.texture = _arrow_tex
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.position = from_pos
	spr.z_index = 96
	add_child(spr)
	var team := 0
	var owner := 0
	if attacker is Unit or attacker is Building or attacker is Ship:
		team = attacker.team
		owner = attacker.owner_id
	projectiles.append({
		"spr": spr, "target": target, "dmg": dmg, "attacker": attacker,
		"team": team, "owner": owner, "aim": _entity_aim(target), "trail_t": 0.0,
	})


func _entity_aim(t) -> Vector2:
	if t is Building:
		return t.aim_point()
	return t.global_position + Vector2(0, -24)


## Ships and Beasts are neither Unit nor Building: they report
## death through a plain is_dead() method instead.
func _generic_dead(t) -> bool:
	if t is Unit or t is Building:
		return false
	return t != null and is_instance_valid(t) and t.has_method("is_dead") and t.is_dead()


func _update_projectiles(delta: float) -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = projectiles[i]
		var spr: Sprite2D = p.spr
		var target = p.target
		if target != null and is_instance_valid(target) \
				and not (target is Unit and not target.is_targetable()) \
				and not (target is Building and target.destroyed) \
				and not _generic_dead(target):
			p.aim = _entity_aim(target)
		var to: Vector2 = Vector2(p.aim) - spr.position
		var dist := to.length()
		var step := 430.0 * delta
		if dist <= maxf(step, 10.0):
			# Impact: damage lands only if the target is still alive.
			# 15b: in a DIPLOMACY match an arrow already in flight
			# fizzles when its target became undamageable since —
			# an alliance formed (or a declaration landed) after
			# the shot. Outside diplomacy the impact is exactly
			# the pre-15b behaviour: the shot was validated at
			# fire time and always lands (a staged entity whose
			# owner_id was never assigned must not become immune).
			if target != null and is_instance_valid(target) \
					and not (target is Unit and not target.is_targetable()) \
					and not (target is Building and target.destroyed) \
					and not _generic_dead(target) \
					and (int(p.get("owner", -1)) < 0 \
						or not diplomacy_active() \
						or not (target is Unit or target is Building or target is Ship) \
						or attack_allowed(int(p["owner"]), int(target.owner_id))):
				target.take_damage(float(p.dmg), p.attacker)
			spr.queue_free()
			projectiles.remove_at(i)
		else:
			var dir := to / dist
			spr.position += dir * step
			spr.rotation = dir.angle()
			p.trail_t = float(p.trail_t) - delta
			if p.trail_t <= 0.0:
				p.trail_t = 0.05
				if vfx != null:
					vfx.arrow_trail(spr.position, dir,
							TeamColors.vfx_palette(int(p.get("owner", p.team))))
		i -= 1


## Watch Towers (both teams) pick the nearest hostile unit in range
## and loose arrows from the tower top on a cooldown.
func _update_towers(delta: float) -> void:
	for b in buildings:
		if mp_mode and slot_inert[b.owner_id]:
			continue # disconnected player's towers stay silent
		if (b.btype != "tower" and b.btype != "castle") or not b.complete or b.destroyed:
			continue
		var is_castle: bool = b.btype == "castle"
		b.fire_cd -= delta
		if b.fire_cd > 0.0:
			continue
		var centre: Vector2 = b.position + Vector2(b.size) * World.TILE * 0.5
		var best: Unit = null
		var bd := (Stats.CASTLE_RANGE if is_castle else Stats.TOWER_RANGE) \
				+ tech_range_bonus(b.owner_id) # Ballistics (GDD 5–6)
		for u in units:
			# 15b: tower fire is auto-engagement — diplomacy
			# neutrals and allies are never shot at.
			if not auto_engage_allowed(b.owner_id, u.owner_id) \
					or not u.is_targetable():
				continue
			var d := centre.distance_to(u.global_position)
			if d < bd:
				bd = d
				best = u
		if best != null:
			b.fire_cd = Stats.CASTLE_COOLDOWN if is_castle else Stats.TOWER_COOLDOWN
			var dmg := Stats.castle_atk(owner_age(b.owner_id)) if is_castle \
					else Stats.tower_atk(owner_age(b.owner_id))
			fire_arrow(b.aim_point() + Vector2(0, -26), best, dmg, b)


## A unit finished its death animation: drop it from the rosters.
func on_unit_dead(u: Unit) -> void:
	# 13y: the owner loses the unit; the killing attacker (Unit /
	# Building / Ship of another owner) is credited — a hero
	# attacker's kills also count as hero kills. Unattributed
	# deaths (DoT, beasts, environment) credit nobody.
	_bump_stat(u.owner_id, "lost")
	var kb = u.killed_by
	if kb != null and is_instance_valid(kb) \
			and (kb is Unit or kb is Building or kb is Ship) \
			and int(kb.owner_id) != u.owner_id:
		_bump_stat(int(kb.owner_id), "kills")
		if kb is Unit and kb.unit_type == "king":
			_bump_stat(int(kb.owner_id), "hero_kills")
	units.erase(u)
	selection.erase(u)
	# A death can complete an annihilation (TC already down).
	if mp_mode:
		_mp_evaluate_elimination(u.owner_id)
	else:
		_sp_evaluate_annihilation(u.team)


## A building's HP hit zero: clear its footprint, play the collapse
## effects, and resolve the match if it was a Town Center.
func on_building_destroyed(b: Building) -> void:
	# 13y: the owner loses a building; the last enemy hitter
	# (Building.last_hit_owner) is credited with the raze.
	_bump_stat(b.owner_id, "blost")
	if b.last_hit_owner >= 0 and b.last_hit_owner != b.owner_id:
		_bump_stat(b.last_hit_owner, "razed")
	# 15e: the spectator auto-camera counts real destructions.
	if spectator != null:
		spectator.note_building_down(
				b.position + Vector2(b.size) * World.TILE * 0.5,
				b.btype == "town_center")
	buildings.erase(b)
	for c in b.cells():
		world.set_solid(c, false)
	if b.btype.begins_with("gate"):
		world.clear_gate(b.origin_cell)
	if Building.is_wall_type(b.btype):
		refresh_wall_variants_around(b.origin_cell)
	if selected_building == b:
		selected_building = null
	if vfx != null:
		var centre: Vector2 = b.position + Vector2(b.size) * World.TILE * 0.5
		var pal := TeamColors.vfx_palette(b.owner_id)
		vfx.death_smoke(centre + Vector2(0, -20), pal)
		vfx.death_smoke(centre + Vector2(-24, -6), pal)
		vfx.flash(centre + Vector2(0, -16), Color(1.0, 0.6, 0.3, 0.8), 110.0, 0.4)
	# Villagers garrisoned inside (fled here) pop out onto the rubble.
	for u in units:
		if u.garrisoned and u.flee_haven == b:
			u.release_garrison()
	if b.btype == "town_center":
		if mp_mode:
			_mp_on_tc_destroyed(b)
		elif b.team == 1:
			enemy_tc_destroyed = true
			if _side_annihilated(1):
				_annihilate_enemy()
			elif hud != null:
				hud.show_message("Town Center địch đã sập — quét sạch tàn quân để chiến thắng!")
		else:
			player_tc_destroyed = true
			if _side_annihilated(0):
				sp_player_eliminated = true
				end_match("defeat", "Bị quét sạch — không còn Dân và công trình huấn luyện")
			elif hud != null:
				hud.show_message("Town Center đã mất! Giữ Dân và Trại lính để chiến đấu tiếp")
	elif mp_mode:
		# Losing a Barracks/Dock can complete a slot's annihilation.
		_mp_evaluate_elimination(b.owner_id)
	else:
		_sp_evaluate_annihilation(b.team)
	b.queue_free()


## Annihilation test for one SP side (its TC must already be down —
## callers check the *_tc_destroyed flags): eliminated when it has
## no living villagers OR no completed train-capable building
## (Barracks / Dock). With villagers AND a trainer left, it fights on.
func _side_annihilated(team: int) -> bool:
	for u in units:
		if u.team == team and not u.is_dead() and u.unit_type == "villager":
			# One living villager: fights on only with a trainer too.
			for b in buildings:
				if b.team == team and b.complete and not b.destroyed \
						and (b.btype == "barracks" or b.btype == "dock"):
					return false
			return true
	return true


func _annihilate_enemy() -> void:
	sp_enemy_eliminated = true
	end_match("victory", "Thắng bằng quét sạch (annihilation)")


## Re-check after a unit death / trainer loss whether a side whose
## TC is down has now been annihilated.
func _sp_evaluate_annihilation(team: int) -> void:
	if mp_mode or match_over != "":
		return
	if team == 1 and enemy_tc_destroyed and not sp_enemy_eliminated \
			and _side_annihilated(1):
		_annihilate_enemy()
	elif team == 0 and player_tc_destroyed and not sp_player_eliminated \
			and _side_annihilated(0):
		sp_player_eliminated = true
		end_match("defeat", "Bị quét sạch — không còn Dân và công trình huấn luyện")


## True while the local player's TC is down but they are NOT
## eliminated (the HUD shows its warning state off this).
func own_tc_down_fighting_on() -> bool:
	if mp_mode:
		return local_slot >= 0 and local_slot < slot_count() \
				and slot_tc_down[local_slot] and not slot_eliminated[local_slot] \
				and not mp_over
	return player_tc_destroyed and match_over == ""


## Surrender (match-start flow doc: a match runs until a player
## surrenders or is eliminated). SP: an immediate defeat. MP: a
## lockstep command — the surrendering slot is eliminated through
## the exact routine annihilation uses, so ranked treats it as a
## loss/disconnect (the referee reports the surviving team).
func surrender() -> void:
	if match_over != "" or mp_over:
		return
	if mp_mode:
		_mp_send_command({"kind": "surrender"})
	else:
		local_surrendered = true
		end_match("defeat", "Bạn đã đầu hàng")


func _mp_apply_surrender(owner: int) -> bool:
	if owner < 0 or owner >= slot_count() or slot_eliminated[owner]:
		return false
	if owner == local_slot:
		local_surrendered = true
	_mp_eliminate_slot(owner)
	return true


func end_match(result: String, note: String = "") -> void:
	if match_over != "":
		return
	match_over = result
	end_note = note
	_sample_stats() # 13y: final chart point at the final scores
	paused = true
	_record_local_history(result == "victory")
	if hud != null and hud.has_method("show_end_panel"):
		hud.show_end_panel(result, match_time, note)


var _history_recorded: bool = false


## Records one finished UNRANKED match into the device-local
## history (13g): SP games here, custom rooms in _mp_check_winner.
## Ranked matches are banked server-side and never logged here.
func _record_local_history(won: bool) -> void:
	if _history_recorded or referee_mode:
		return
	_history_recorded = true
	var players: Array = []
	if mp_mode:
		for p in Net.players:
			players.append({"name": String(p.get("name", "?")),
					"team": int(p.get("team", 0))})
		LocalHistory.record({
			"mode": "custom", "won": won,
			"biome": String(Net.pending_cfg.get("biome", "grassland")),
			"layout": String(Net.pending_cfg.get("layout", "plains")),
			"players": players,
			"at": int(Time.get_unix_time_from_system()),
			"duration_ticks": _mp_current_tick,
			"room": Net.room_code,
		})
	else:
		players.append({"name": Net.display_name() if Net.account_name != "" else "Khách",
				"team": 0})
		players.append({"name": "Đối thủ máy", "team": 1})
		LocalHistory.record({
			"mode": "custom", "won": won,
			"biome": chosen_biome, "layout": chosen_layout,
			"players": players,
			"at": int(Time.get_unix_time_from_system()),
			"duration_ticks": int(match_time * 10.0),
			"room": "",
		})


# ---------------------------------------------------------------- P3 age-up

## Completed non-TC buildings of a team (the Feudal requirement).
func completed_non_tc_buildings(team: int) -> int:
	var n := 0
	for b in buildings:
		if b.team == team and b.complete and not b.destroyed \
				and b.btype != "town_center" and b.btype != "skillwall":
			n += 1
	return n


func can_age_up() -> bool:
	if mp_mode:
		var st: Dictionary = mp_ages[local_slot]
		return int(st.get("age", 1)) == 1 and not bool(st.get("researching", false)) \
				and not mp_over \
				and completed_non_tc_buildings_of(local_slot) >= Stats.AGE_UP_MIN_BUILDINGS \
				and int(mp_wallets[local_slot].get("food", 0)) >= int(Stats.AGE_UP_COST.food)
	return age == 1 and not age_researching and match_over == "" \
			and completed_non_tc_buildings(0) >= Stats.AGE_UP_MIN_BUILDINGS \
			and int(resources.get("food", 0)) >= int(Stats.AGE_UP_COST.food)


func start_age_up() -> bool:
	if mp_mode:
		_mp_send_command({"kind": "age_up", "to": 2})
		return true
	if age != 1 or age_researching:
		return false
	if completed_non_tc_buildings(0) < Stats.AGE_UP_MIN_BUILDINGS:
		hud.show_message("Cần ít nhất %d công trình (ngoài Town Center)" % Stats.AGE_UP_MIN_BUILDINGS)
		return false
	if int(resources.get("food", 0)) < int(Stats.AGE_UP_COST.food):
		hud.show_message("Cần %d Food để lên đời" % int(Stats.AGE_UP_COST.food))
		return false
	resources["food"] = int(resources["food"]) - int(Stats.AGE_UP_COST.food)
	age_researching = true
	age_target = 2
	age_duration = Stats.AGE_UP_TIME
	age_timer = age_duration
	hud.show_message("Đang nghiên cứu Thời đại II — Feudal…")
	_note_action(0) # 13y APM
	return true


## Feudal -> Castle Age (Age III): needs a completed Barracks plus a
## Blacksmith or a Market, 800 Food + 200 Gold, 90 s at the TC.
func can_age_up3() -> bool:
	if mp_mode:
		var st: Dictionary = mp_ages[local_slot]
		if int(st.get("age", 1)) != 2 or bool(st.get("researching", false)) or mp_over:
			return false
		var hb := false
		var hs := false
		for b in buildings:
			if b.owner_id == local_slot and b.complete and not b.destroyed:
				if b.btype == "barracks":
					hb = true
				elif b.btype == "blacksmith" or b.btype == "market":
					hs = true
		return hb and hs \
				and int(mp_wallets[local_slot].get("food", 0)) >= int(Stats.AGE3_UP_COST.food) \
				and int(mp_wallets[local_slot].get("gold", 0)) >= int(Stats.AGE3_UP_COST.gold)
	if age != 2 or age_researching or match_over != "":
		return false
	var has_barracks := false
	var has_smith_or_market := false
	for b in buildings:
		if b.team == 0 and b.complete and not b.destroyed:
			if b.btype == "barracks":
				has_barracks = true
			elif b.btype == "blacksmith" or b.btype == "market":
				has_smith_or_market = true
	return has_barracks and has_smith_or_market \
			and int(resources.get("food", 0)) >= int(Stats.AGE3_UP_COST.food) \
			and int(resources.get("gold", 0)) >= int(Stats.AGE3_UP_COST.gold)


func start_age_up3() -> bool:
	if mp_mode:
		_mp_send_command({"kind": "age_up", "to": 3})
		return true
	if age != 2 or age_researching:
		return false
	if not can_age_up3():
		hud.show_message("Lên đời III cần Trại lính + (Lò rèn hoặc Chợ), %d Food + %d Gold" % [int(Stats.AGE3_UP_COST.food), int(Stats.AGE3_UP_COST.gold)])
		return false
	resources["food"] = int(resources["food"]) - int(Stats.AGE3_UP_COST.food)
	resources["gold"] = int(resources["gold"]) - int(Stats.AGE3_UP_COST.gold)
	age_researching = true
	age_target = 3
	age_duration = Stats.AGE3_UP_TIME
	age_timer = age_duration
	hud.show_message("Đang nghiên cứu Thời đại III — Castle Age…")
	_note_action(0) # 13y APM
	return true


func age_fraction() -> float:
	if not age_researching:
		return 0.0
	return clampf(1.0 - age_timer / age_duration, 0.0, 1.0)


## Completion banner per age reached (SP + MP share the wording).
func _age_done_text(target: int) -> String:
	match target:
		2:
			return "Đã lên Thời đại II — Feudal!"
		3:
			return "Đã lên Thời đại III — Castle Age!"
		4:
			return "Đã lên Thời đại IV — Đế quốc (Imperial)!"
	return ""


## Completed Castle + (Blacksmith or Market) of a team / owner —
## the Age IV building requirements (mirrors the Age III pattern,
## with the Castle in the Barracks' seat).
func _has_castle_and_smith(team: int, owner: int) -> bool:
	var has_castle := false
	var has_smith := false
	for b in buildings:
		if b.complete and not b.destroyed \
				and (b.owner_id == owner if mp_mode else b.team == team):
			if b.btype == "castle":
				has_castle = true
			elif b.btype == "blacksmith" or b.btype == "market":
				has_smith = true
	return has_castle and has_smith


## Castle Age -> Imperial (Age IV): needs a completed Castle plus a
## Blacksmith or a Market, 1000 Food + 350 Gold, 120 s at the TC.
func can_age_up4() -> bool:
	if mp_mode:
		var st: Dictionary = mp_ages[local_slot]
		if int(st.get("age", 1)) != 3 or bool(st.get("researching", false)) or mp_over:
			return false
		return _has_castle_and_smith(view_team(), local_slot) \
				and int(mp_wallets[local_slot].get("food", 0)) >= int(Stats.AGE4_UP_COST.food) \
				and int(mp_wallets[local_slot].get("gold", 0)) >= int(Stats.AGE4_UP_COST.gold)
	if age != 3 or age_researching or match_over != "":
		return false
	return _has_castle_and_smith(0, 0) \
			and int(resources.get("food", 0)) >= int(Stats.AGE4_UP_COST.food) \
			and int(resources.get("gold", 0)) >= int(Stats.AGE4_UP_COST.gold)


func start_age_up4() -> bool:
	if mp_mode:
		_mp_send_command({"kind": "age_up", "to": 4})
		return true
	if age != 3 or age_researching:
		return false
	if not can_age_up4():
		hud.show_message("Lên đời IV cần Lâu đài + (Lò rèn hoặc Chợ), %d Food + %d Gold" % [int(Stats.AGE4_UP_COST.food), int(Stats.AGE4_UP_COST.gold)])
		return false
	resources["food"] = int(resources["food"]) - int(Stats.AGE4_UP_COST.food)
	resources["gold"] = int(resources["gold"]) - int(Stats.AGE4_UP_COST.gold)
	age_researching = true
	age_target = 4
	age_duration = Stats.AGE4_UP_TIME
	age_timer = age_duration
	hud.show_message("Đang nghiên cứu Thời đại IV — Imperial…")
	_note_action(0) # 13y APM
	return true


## Sets a team's age and swaps every one of its buildings to the
## matching art tier (the player's `age` var mirrors team 0).
func set_team_age(team: int, n: int) -> void:
	team_age[team] = n
	if team == 0:
		age = n
	for b in buildings:
		if b.team == team and not b.destroyed:
			b.set_tier(clampi(n, 1, 4))
	if hud != null:
		hud.refresh_age_badge()


## MP: set one player slot's age (per-owner ages; team_age keeps the
## strongest member for tower attack + spawn tiers), swap that
## owner's building art, mirror the local player's `age`.
func set_owner_age(owner: int, n: int) -> void:
	if mp_mode:
		mp_ages[owner]["age"] = n
		var t := team_of_slot(owner)
		var best := 1
		for s in range(slot_count()):
			if team_of_slot(s) == t:
				best = maxi(best, int(mp_ages[s].get("age", 1)))
		team_age[t] = best
	for b in buildings:
		if b.owner_id == owner and not b.destroyed:
			b.set_tier(clampi(n, 1, 4))
	if mp_mode and owner == local_slot:
		age = n
	if hud != null:
		hud.refresh_age_badge()


## MP age research timers (per slot; frozen for disconnected slots).
func _mp_update_ages(delta: float) -> void:
	for slot in range(slot_count()):
		if slot_inert[slot]:
			continue
		var st: Dictionary = mp_ages[slot]
		if bool(st.get("researching", false)):
			st["timer"] = float(st.get("timer", 0.0)) - delta
			if float(st["timer"]) <= 0.0:
				st["researching"] = false
				set_owner_age(slot, int(st.get("target", 2)))
				if slot == local_slot and hud != null:
					hud.show_message(_age_done_text(int(st.get("target", 2))))


## MP execution of an age-up command (validated against the owner's
## wallet/buildings at the tick it applies — same on every client).
func _mp_apply_age_up(owner: int, to: int) -> bool:
	var st: Dictionary = mp_ages[owner]
	if bool(st.get("researching", false)) or int(st.get("age", 1)) != to - 1:
		return false
	var w: Dictionary = mp_wallets[owner]
	if to == 2:
		if completed_non_tc_buildings_of(owner) < Stats.AGE_UP_MIN_BUILDINGS:
			return false
		if int(w.get("food", 0)) < int(Stats.AGE_UP_COST.food):
			return false
		w["food"] = int(w["food"]) - int(Stats.AGE_UP_COST.food)
		st["duration"] = Stats.AGE_UP_TIME
	elif to == 3:
		var has_barracks := false
		var has_smith_or_market := false
		for b in buildings:
			if b.owner_id == owner and b.complete and not b.destroyed:
				if b.btype == "barracks":
					has_barracks = true
				elif b.btype == "blacksmith" or b.btype == "market":
					has_smith_or_market = true
		if not (has_barracks and has_smith_or_market):
			return false
		if int(w.get("food", 0)) < int(Stats.AGE3_UP_COST.food) \
				or int(w.get("gold", 0)) < int(Stats.AGE3_UP_COST.gold):
			return false
		w["food"] = int(w["food"]) - int(Stats.AGE3_UP_COST.food)
		w["gold"] = int(w["gold"]) - int(Stats.AGE3_UP_COST.gold)
		st["duration"] = Stats.AGE3_UP_TIME
	elif to == 4:
		if not _has_castle_and_smith(team_of_slot(owner), owner):
			return false
		if int(w.get("food", 0)) < int(Stats.AGE4_UP_COST.food) \
				or int(w.get("gold", 0)) < int(Stats.AGE4_UP_COST.gold):
			return false
		w["food"] = int(w["food"]) - int(Stats.AGE4_UP_COST.food)
		w["gold"] = int(w["gold"]) - int(Stats.AGE4_UP_COST.gold)
		st["duration"] = Stats.AGE4_UP_TIME
	else:
		return false
	st["researching"] = true
	st["target"] = to
	st["timer"] = float(st["duration"])
	return true


# ---------------------------------------------------------------- economy / pop

# ---------------------------------------------------------------- technologies (13s)

## Researched tier of `tech_id` for `owner` (0 = none). SP tracks
## only the player (the SP enemy never researches); MP per slot.
func tech_level(owner: int, tech_id: String) -> int:
	if mp_mode:
		if owner < 0 or owner >= mp_techs.size():
			return 0
		return int((mp_techs[owner].get("levels", {}) as Dictionary).get(tech_id, 0))
	if owner != 0:
		return 0
	return int(tech_levels.get(tech_id, 0))


func _tech_active_for(owner: int) -> Dictionary:
	if mp_mode:
		if owner < 0 or owner >= mp_techs.size():
			return {}
		return mp_techs[owner].get("active", {})
	return tech_active


func _tech_set_active(owner: int, btype: String, rec: Dictionary) -> void:
	if mp_mode:
		var act: Dictionary = mp_techs[owner].get("active", {})
		if rec.is_empty():
			act.erase(btype)
		else:
			act[btype] = rec
		mp_techs[owner]["active"] = act
	elif owner == 0:
		if rec.is_empty():
			tech_active.erase(btype)
		else:
			tech_active[btype] = rec


func _tech_set_level(owner: int, tech_id: String, tier: int) -> void:
	if mp_mode:
		var lv: Dictionary = mp_techs[owner].get("levels", {})
		lv[tech_id] = tier
		mp_techs[owner]["levels"] = lv
	elif owner == 0:
		tech_levels[tech_id] = tier


func _owns_completed(owner: int, btype: String) -> bool:
	for b in buildings:
		if not b.complete or b.destroyed or b.btype != btype:
			continue
		if mp_mode:
			if b.owner_id == owner:
				return true
		elif owner == 0 and b.team == 0:
			return true
	return false


## Full gate check for researching the NEXT tier of `tech_id`:
## {ok, reason, level, next} — reason is the short Vietnamese
## block line the panel shows (building / age / busy / resource).
func research_check(owner: int, tech_id: String) -> Dictionary:
	var out := {"ok": false, "reason": "", "level": 0, "next": {}}
	var def := Stats.tech_def(tech_id)
	if def.is_empty():
		out.reason = "?"
		return out
	var tiers: Array = def.get("tiers", [])
	var lvl := tech_level(owner, tech_id)
	out.level = lvl
	if lvl >= tiers.size():
		out.reason = "Đã hoàn thành"
		return out
	var next: Dictionary = tiers[lvl]
	out.next = next
	var btype := str(def.get("building", ""))
	if not _owns_completed(owner, btype):
		out.reason = "Cần %s" % str(Stats.BUILDING_VN.get(btype, btype))
		return out
	if owner_age(owner) < int(next.get("age", 1)):
		out.reason = "Cần Đời %s" % ["", "I", "II", "III", "IV"][int(next.get("age", 1))]
		return out
	if _tech_active_for(owner).has(btype):
		out.reason = "Công trình đang nghiên cứu"
		return out
	var w: Dictionary = mp_wallets[owner] if mp_mode else resources
	for r in next.get("cost", {}):
		if int(w.get(r, 0)) < int(next.cost[r]):
			out.reason = "Thiếu %s" % str(RES_VN.get(r, r))
			return out
	out.ok = true
	return out


func _apply_research_start(owner: int, tech_id: String) -> void:
	var def := Stats.tech_def(tech_id)
	var lvl := tech_level(owner, tech_id)
	var next: Dictionary = (def.get("tiers", []) as Array)[lvl]
	var w: Dictionary = mp_wallets[owner] if mp_mode else resources
	for r in next.get("cost", {}):
		w[r] = int(w.get(r, 0)) - int(next.cost[r])
	_tech_set_active(owner, str(def.get("building", "")), {"id": tech_id,
			"tier": lvl + 1, "timer": float(next.get("time", 30.0)),
			"duration": float(next.get("time", 30.0))})
	if owner == local_slot and hud != null:
		hud.show_message("Đang nghiên cứu: %s…" % str(next.get("name", tech_id)))


## Local player's entry point (panel button): mirrors start_age_up.
func start_research(tech_id: String) -> bool:
	if mp_mode:
		_mp_send_command({"kind": "research", "tech": tech_id})
		return true
	var chk := research_check(0, tech_id)
	if not bool(chk.get("ok", false)):
		if hud != null:
			hud.show_message(str(chk.get("reason", "")))
		return false
	_apply_research_start(0, tech_id)
	_note_action(0) # 13y APM
	return true


func _mp_apply_research(owner: int, tech_id: String) -> bool:
	if not bool(research_check(owner, tech_id).get("ok", false)):
		return false
	_apply_research_start(owner, tech_id)
	return true


## Advance running researches (SP: the player; MP: every slot,
## frozen for inert slots — same pattern as _mp_update_ages).
func _update_techs(delta: float) -> void:
	var owners: Array = range(slot_count()) if mp_mode else [0]
	for owner in owners:
		if mp_mode and slot_inert[owner]:
			continue
		var act := _tech_active_for(owner)
		if act.is_empty():
			continue
		var done: Array = []
		for btype in act.keys():
			var rec: Dictionary = act[btype]
			rec["timer"] = float(rec.get("timer", 0.0)) - delta
			if float(rec.timer) <= 0.0:
				done.append(btype)
		for btype in done:
			var rec: Dictionary = act[btype]
			var tid := str(rec.get("id", ""))
			var tier := int(rec.get("tier", 1))
			_tech_set_level(owner, tid, tier)
			_bump_stat(owner, "researched") # 13y
			_tech_set_active(owner, btype, {})
			if owner == local_slot and hud != null:
				var tiers: Array = Stats.tech_def(tid).get("tiers", [])
				var tname := tid
				if tier >= 1 and tier <= tiers.size():
					tname = str((tiers[tier - 1] as Dictionary).get("name", tid))
				hud.show_message("Nghiên cứu xong: %s" % tname)


## Cost lookup for panels (unit or ship kind).
func unit_cost(kind: String) -> Dictionary:
	return SHIP_COSTS.get(kind, UNIT_COSTS.get(kind, {}))


## Vietnamese resource name for block-reason lines.
func res_vn(rtype: String) -> String:
	return str(RES_VN.get(rtype, rtype))


## Everything the Công nghệ panel needs for one tech line.
func tech_panel_info(tech_id: String) -> Dictionary:
	var owner := local_slot if mp_mode else 0
	var def := Stats.tech_def(tech_id)
	var chk := research_check(owner, tech_id)
	var btype := str(def.get("building", ""))
	var act := _tech_active_for(owner)
	var frac := -1.0
	if act.has(btype) and str((act[btype] as Dictionary).get("id", "")) == tech_id:
		var rec: Dictionary = act[btype]
		frac = clampf(1.0 - float(rec.get("timer", 0.0)) / maxf(float(rec.get("duration", 1.0)), 0.01), 0.0, 1.0)
	return {"level": tech_level(owner, tech_id),
		"max": (def.get("tiers", []) as Array).size(),
		"next": chk.get("next", {}), "can": bool(chk.get("ok", false)),
		"reason": str(chk.get("reason", "")), "active_frac": frac,
		"building": btype, "group": str(def.get("group", ""))}


# ---- technology effects (all read inside the sim paths) ----

## Flat attack bonus of one hit, per unit class (GDD section 4
## lines at the Barracks; the ram and the hero are excluded).
func tech_atk_bonus(owner: int, unit_type: String) -> float:
	match unit_type:
		"militia", "spearman":
			return float(Stats.MELEE_ATK[tech_level(owner, "melee")])
		"archer":
			return float(tech_level(owner, "bow"))
		"cavalry":
			return float(tech_level(owner, "cav"))
	return 0.0


## Flat damage reduction per hit for a land unit class (armour
## lines at the Blacksmith; villagers, the hero and the ram take
## full damage — the GDD has no villager armour technology).
func tech_armor(owner: int, unit_type: String) -> float:
	match unit_type:
		"militia", "spearman":
			return float(tech_level(owner, "inf_armor"))
		"cavalry":
			return float(tech_level(owner, "cav_armor"))
		"archer":
			return float(tech_level(owner, "arc_armor"))
	return 0.0


## Economy multiplier applied at deposit time, per resource lane
## (GDD section 3): field food (Granary line at Storage), wood
## (Storage Pit line at Lumber Camp), stone and gold (Storage Pit
## lines at Storage). Everything else passes through at 1.0.
func tech_yield_mult(owner: int, rtype: String, from_field: bool) -> float:
	if owner < 0:
		return 1.0
	if from_field:
		return 1.0 + 0.20 * float(tech_level(owner, "food"))
	if rtype == "wood":
		return 1.0 + 0.20 * float(tech_level(owner, "wood"))
	if rtype == "stone":
		return 1.0 + 0.20 * float(tech_level(owner, "stone"))
	if rtype == "gold":
		return 1.0 + 0.20 * float(tech_level(owner, "gold"))
	return 1.0


## Wheel (Market tech, GDD section 3.3): villagers move faster.
func tech_villager_speed_mult(owner: int) -> float:
	return 1.0 + 0.10 * float(tech_level(owner, "wheel"))


## Nobility (Castle tech, GDD section 6): cavalry mustered after
## the research get extra HP (spawn-time, like all HP in the sim).
func tech_cav_hp(owner: int) -> float:
	return Stats.NOBILITY_CAV_HP * float(tech_level(owner, "nobility"))


## Aristocracy (Castle tech, GDD section 6): spearmen move faster.
func tech_spearman_speed_mult(owner: int) -> float:
	return 1.0 + 0.10 * float(tech_level(owner, "aristocracy"))


## Ballistics (Castle tech, GDD sections 5–6): extra range for
## archers (Unit.attack_range) and towers/castles (tower loop).
func tech_range_bonus(owner: int) -> float:
	return Stats.BALLISTICS_RANGE_BONUS if tech_level(owner, "ballistics") > 0 else 0.0


## Coinage (Market tech, GDD section 3.3): better exchange rates.
func market_sell_gold(owner: int) -> int:
	return Stats.TECH_SELL_GOLD if tech_level(owner, "coinage") > 0 else MARKET_SELL_GOLD


func market_buy_gold(owner: int) -> int:
	return Stats.TECH_BUY_GOLD if tech_level(owner, "coinage") > 0 else MARKET_BUY_GOLD


# ------------------------------------------------------------------
# 15g land transport: trade routes, wagon orders, ambush alerts
# ------------------------------------------------------------------

## Gold for one completed round trip between two Markets:
## scaled by the one-way distance in tiles (genre formula —
## the TRADE_* constants by the market rates at the top).
func trade_gold_for(home: Building, target: Building) -> int:
	if home == null or target == null:
		return 0
	var hc := home.position + Vector2(home.size) * World.TILE * 0.5
	var tc := target.position + Vector2(target.size) * World.TILE * 0.5
	var d := hc.distance_to(tc) / World.TILE
	return clampi(int(round(TRADE_GOLD_PER_TILE * d)),
			TRADE_GOLD_MIN, TRADE_GOLD_CAP)


## May `owner` trade with a Market belonging to `market_owner`?
## Own Markets always. Foreign Markets only while the pair is
## not hostile: with diplomacy armed, NEUTRAL and ALLY stances
## trade and an open break declaration on either side closes
## the route; without diplomacy, only same-team Markets are
## partners (in FFA every foreign Market is an enemy's — the
## genre's stance rule; foreign trade there needs a diplomacy
## room, exactly as the brief's "non-enemy market" wording).
func trade_partner_ok(owner: int, market_owner: int) -> bool:
	if owner == market_owner:
		return true
	if diplomacy_active():
		if not dip_break_on(owner, market_owner).is_empty() \
				or not dip_break_on(market_owner, owner).is_empty():
			return false
		return stance_of(owner, market_owner) != DIP_ENEMY
	return team_of_slot(owner) == team_of_slot(market_owner)


## The home Market a cart runs back to: the owner's nearest
## completed Market other than `exclude` (its trade target).
func trade_home_market_for(owner: int, exclude: Building, near_pos: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for b in buildings:
		if b.owner_id == owner and b.btype == "market" and b.complete \
				and not b.destroyed and b != exclude:
			var d := near_pos.distance_squared_to(
					b.position + Vector2(b.size) * World.TILE * 0.5)
			if d < bd:
				bd = d
				best = b
	return best


## Assign (or re-assign) a cart's trade route to `target` —
## called inside the sim from the order pipeline, so it runs
## identically on every client; only the feedback is local.
func assign_trade_route(cart: Unit, target: Building) -> bool:
	if cart == null or cart.unit_type != "cart" or cart.is_dead():
		return false
	var mine := is_local_owner(cart.owner_id)
	if target == null or target.btype != "market" or not target.complete \
			or target.destroyed:
		if mine and hud != null:
			hud.show_message("Chỉ đặt tuyến tới một Chợ đã xây xong")
		return false
	if not trade_partner_ok(cart.owner_id, target.owner_id):
		if mine and hud != null:
			hud.show_message("Không thể buôn với Chợ của kẻ địch")
		return false
	var home: Building = null
	if target.owner_id == cart.owner_id:
		home = trade_home_market_for(cart.owner_id, target, cart.global_position)
		if home == null:
			if mine and hud != null:
				hud.show_message("Cần một Chợ nhà thứ hai để chạy tuyến này")
			return false
	else:
		home = trade_home_market_for(cart.owner_id, null, cart.global_position)
		if home == null:
			if mine and hud != null:
				hud.show_message("Bạn cần có Chợ nhà để xe hàng chạy tuyến")
			return false
	var hc := home.position + Vector2(home.size) * World.TILE * 0.5
	var tc := target.position + Vector2(target.size) * World.TILE * 0.5
	if hc.distance_to(tc) / World.TILE < TRADE_MIN_TILES:
		if mine and hud != null:
			hud.show_message("Hai Chợ quá gần nhau để chạy tuyến")
		return false
	var gold := trade_gold_for(home, target)
	cart.set_trade_route(home, target, gold)
	if mine and hud != null:
		hud.show_message("Xe hàng chạy tuyến — +%d Vàng mỗi chuyến khứ hồi" % gold)
	if mp_debug_log:
		print("MPLOG transport route set owner=", cart.owner_id,
				" gold=", gold)
	return true


## A cart banked a round trip (the credit itself went through
## credit_owner in Unit — this is only the owner's feedback).
func on_trade_completed(cart: Unit) -> void:
	if is_local_owner(cart.owner_id) and hud != null:
		hud.show_message("Xe hàng hoàn thành chuyến: +%d Vàng" % cart.trade_gold)
	if mp_debug_log:
		print("MPLOG transport trip done owner=", cart.owner_id,
				" gold=", cart.trade_gold)


## A cart's route died (Market destroyed / partner turned
## enemy). The cart has already turned for home or idled in
## Unit; this is the owner's one-off notice.
func notify_route_broken(cart: Unit) -> void:
	if is_local_owner(cart.owner_id) and hud != null:
		hud.show_message("Tuyến xe hàng bị cắt — chọn xe rồi nhấp phải vào Chợ khác để đặt tuyến mới")
	if mp_debug_log:
		print("MPLOG transport route broken owner=", cart.owner_id)


## Ambush-alert throttle stamps (PRESENTATION only — local
## wall clock, never sim state, never checksummed/snapshotted).
var _transport_alert_t: Dictionary = {} # unit net_id -> msec


## A cart / wagon is taking hostile fire: warn ITS owner —
## message + chat system line + minimap ping + alert sound —
## at most once per 10 s per unit (a destruction always warns).
## Called from Unit.take_damage on every client; everything
## past the hostility check is gated to the owner's client.
func notify_transport_attacked(u: Unit, attacker) -> void:
	var hostile := false
	if attacker is Beast:
		hostile = true
	elif attacker is Unit or attacker is Building or attacker is Ship:
		hostile = attack_allowed(int(attacker.owner_id), u.owner_id)
	if not hostile or not is_local_owner(u.owner_id):
		return
	var dead := u.hp <= 0.0
	var now := Time.get_ticks_msec()
	if not dead and now - int(_transport_alert_t.get(u.net_id, -100000)) < 10000:
		return
	_transport_alert_t[u.net_id] = now
	var kind_name := "Xe hàng" if u.unit_type == "cart" else "Xe chở quân"
	if hud != null:
		if dead:
			hud.show_message(kind_name + " đã bị phá!")
			hud.add_chat_line("Hệ thống", kind_name + " của bạn đã bị phá",
					"match", u.owner_id)
		else:
			hud.show_message(kind_name + " đang bị tấn công!")
			hud.add_chat_line("Hệ thống", kind_name + " của bạn đang bị tấn công",
					"match", u.owner_id)
		if hud.minimap != null:
			hud.minimap.ping_at(u.global_position)
	_play_alert_sfx()
	if mp_debug_log:
		print("MPLOG transport alert owner=", u.owner_id,
				" kind=", u.unit_type, " dead=", dead)


func _play_alert_sfx() -> void:
	if _sfx_pool.is_empty():
		return
	var path := "res://assets/sfx/alert.wav"
	if not ResourceLoader.exists(path):
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_rr % _sfx_pool.size()]
	_sfx_rr += 1
	p.stream = load(path)
	p.play()


## HUD entry: the one selected wagon unloads where it stands.
## MP rides the ordinary order channel (the unload partition
## in apply_order_for does the work at the execution tick);
## SP applies the same path directly.
func issue_selected_wagon_unload() -> void:
	if selection.size() != 1:
		return
	var u: Unit = selection[0]
	if u.unit_type != "wagon" or u.cargo.is_empty():
		return
	if mp_mode:
		_mp_send_command({"kind": "order", "units": [u.net_id],
			"x": u.global_position.x, "y": u.global_position.y})
	else:
		apply_order_for([u], null, u.global_position, 0)


# ---------------------------------------------------------------- per-building training + queue cancel (13s)

func _producer_btype_for(kind: String) -> String:
	if SHIP_COSTS.has(kind):
		return "dock"
	if kind == "villager":
		return "town_center"
	if kind == "king":
		return "castle"
	if kind == "cart": # 15g: the Market trains the trade cart
		return "market"
	return "barracks"


## Gate check for training `kind` at the SPECIFIC building `b`:
## {can, reason} — the panel shows `reason` on blocked cards.
func train_state(b: Building, kind: String) -> Dictionary:
	var out := {"can": false, "reason": ""}
	if b == null or not b.complete or b.destroyed:
		out.reason = "Chưa xây xong"
		return out
	if mp_mode:
		if b.owner_id != local_slot:
			out.reason = "Không phải nhà của bạn"
			return out
	elif b.team != 0:
		out.reason = "Không phải nhà của bạn"
		return out
	if b.btype != _producer_btype_for(kind):
		out.reason = "Sai công trình"
		return out
	var owner := local_slot if mp_mode else 0
	var costs: Dictionary = SHIP_COSTS.get(kind, UNIT_COSTS.get(kind, {}))
	if costs.is_empty():
		out.reason = "?"
		return out
	if not SHIP_COSTS.has(kind):
		if kind == "king" and king_busy(owner):
			out.reason = "Nhân vật đang tại trận"
			return out
		if owner_age(owner) < int(UNIT_MIN_AGE.get(kind, 1)):
			out.reason = "Cần Đời %s" % ["", "I", "II", "III", "IV"][int(UNIT_MIN_AGE.get(kind, 1))]
			return out
		var pc := owner_pop_current(owner) if mp_mode else pop_current()
		var pq := owner_queued(owner) if mp_mode else queued_total()
		var pcap := owner_pop_cap(owner) if mp_mode else pop_cap()
		if pc + pq >= pcap:
			out.reason = "Đã đầy dân số"
			return out
	var w: Dictionary = mp_wallets[local_slot] if mp_mode else resources
	for r in costs:
		if int(w.get(r, 0)) < int(costs[r]):
			out.reason = "Thiếu %s" % str(RES_VN.get(r, r))
			return out
	out.can = true
	return out


func can_train_at(b: Building, kind: String) -> bool:
	return bool(train_state(b, kind).get("can", false))


## Train at a specific building (panel entry point): SP deducts
## and queues locally; MP routes the same train/train_ship verbs
## the global buttons use, pinned to this building's net id.
func train_at(b: Building, kind: String) -> bool:
	if b == null:
		return false
	if mp_mode:
		if b.owner_id != local_slot:
			return false
		_mp_send_command({"kind": "train_ship" if SHIP_COSTS.has(kind) else "train",
				"b": b.net_id, "unit": kind})
		return true
	var st := train_state(b, kind)
	if not bool(st.get("can", false)):
		if hud != null and str(st.get("reason", "")) != "":
			hud.show_message(str(st.reason))
		return false
	var costs: Dictionary = SHIP_COSTS.get(kind, UNIT_COSTS.get(kind, {}))
	for r in costs:
		resources[r] = int(resources[r]) - int(costs[r])
	b.start_training(kind)
	_note_action(0) # 13y APM
	return true


## Cancel queue entry `index` at `b` — FULL refund of that unit's
## cost (the project's queue rule; placement cancels refund fully
## too). Works for land units and dock ships alike.
func cancel_train_at(b: Building, index: int) -> bool:
	if b == null:
		return false
	if mp_mode:
		if b.owner_id != local_slot:
			return false
		_mp_send_command({"kind": "cancel_train", "b": b.net_id, "i": index})
		return true
	if b.team != 0:
		return false
	var ok := _apply_cancel_train(0, b, index)
	if ok:
		_note_action(0) # 13y APM
	return ok


func _apply_cancel_train(owner: int, b: Building, index: int) -> bool:
	var kind := b.remove_queue_at(index)
	if kind == "":
		return false
	var costs: Dictionary = SHIP_COSTS.get(kind, UNIT_COSTS.get(kind, {}))
	var w: Dictionary = mp_wallets[owner] if mp_mode else resources
	for r in costs:
		w[r] = int(w.get(r, 0)) + int(costs[r])
	if owner == local_slot and hud != null:
		hud.show_message("Đã huỷ %s — hoàn tiền" % str(
				SHIP_NAMES.get(kind, UNIT_NAMES.get(kind, kind))))
	return true


func _mp_apply_cancel_train(owner: int, b_id: int, index: int) -> bool:
	var b := building_of_net_id(b_id)
	if b == null or b.owner_id != owner:
		return false
	return _apply_cancel_train(owner, b, index)


func add_resource(rtype: String, amount: int) -> void:
	resources[rtype] = int(resources.get(rtype, 0)) + amount
	if amount > 0:
		deposit_log.append({"t": match_time, "type": rtype, "amt": amount})
		# Prune entries far outside the rate window.
		while not deposit_log.is_empty() and float(deposit_log[0].t) < match_time - 180.0:
			deposit_log.pop_front()


## Team-routed deposit credit (P3): player villagers feed the player
## ledger (add_resource, above); enemy villagers feed the AI's own
## ledger — the two economies never mix.
func credit_resource(team: int, rtype: String, amount: int) -> void:
	if team == 0:
		add_resource(rtype, amount)
	elif enemy_ai != null:
		enemy_ai.credit(rtype, amount)


## Market exchange at the fixed rates above. Spends write the ledger
## directly (the same path as build/train costs) and gains arrive via
## add_resource (the same path as villager deposits). A trade only
## runs against a completed player Market.
func get_market() -> Building:
	for b in buildings:
		if b.team == 0 and b.btype == "market" and b.complete:
			return b
	return null


## A completed Market owned by a player slot (MP).
func market_of(owner: int) -> Building:
	for b in buildings:
		if b.owner_id == owner and b.btype == "market" and b.complete and not b.destroyed:
			return b
	return null


func market_can_sell(rtype: String) -> bool:
	if mp_mode:
		return market_of(local_slot) != null and MARKET_TRADE_TYPES.has(rtype) \
				and int(mp_wallets[local_slot].get(rtype, 0)) >= MARKET_TRADE_AMOUNT
	return get_market() != null and MARKET_TRADE_TYPES.has(rtype) \
			and int(resources.get(rtype, 0)) >= MARKET_TRADE_AMOUNT


func market_can_buy(rtype: String) -> bool:
	if mp_mode:
		return market_of(local_slot) != null and MARKET_TRADE_TYPES.has(rtype) \
				and int(mp_wallets[local_slot].get("gold", 0)) >= market_buy_gold(local_slot)
	return get_market() != null and MARKET_TRADE_TYPES.has(rtype) \
			and int(resources.get("gold", 0)) >= market_buy_gold(0)


func market_sell(rtype: String) -> bool:
	if mp_mode:
		var m := market_of(local_slot)
		if m == null:
			hud.show_message("Cần Chợ hoàn thiện")
			return false
		_mp_send_command({"kind": "market", "b": m.net_id, "side": "sell", "rtype": rtype})
		return true
	if not market_can_sell(rtype):
		hud.show_message("Not enough %s to sell" % rtype)
		return false
	resources[rtype] = int(resources[rtype]) - MARKET_TRADE_AMOUNT
	add_resource("gold", market_sell_gold(0))
	hud.show_message("Sold %d %s → +%d gold" % [MARKET_TRADE_AMOUNT, rtype, market_sell_gold(0)])
	_note_action(0) # 13y APM
	return true


func market_buy(rtype: String) -> bool:
	if mp_mode:
		var m := market_of(local_slot)
		if m == null:
			hud.show_message("Cần Chợ hoàn thiện")
			return false
		_mp_send_command({"kind": "market", "b": m.net_id, "side": "buy", "rtype": rtype})
		return true
	if not market_can_buy(rtype):
		hud.show_message("Not enough gold")
		return false
	resources["gold"] = int(resources["gold"]) - market_buy_gold(0)
	add_resource(rtype, MARKET_TRADE_AMOUNT)
	hud.show_message("Bought %d %s → -%d gold" % [MARKET_TRADE_AMOUNT, rtype, market_buy_gold(0)])
	_note_action(0) # 13y APM
	return true


## Average gather rate (per second) from deposits in the trailing 60 s.
func gather_rate(rtype: String) -> float:
	var sum := 0.0
	var cutoff := match_time - 60.0
	for e in deposit_log:
		if float(e.t) >= cutoff and String(e.type) == rtype:
			sum += float(e.amt)
	return sum / 60.0


# ---------------------------------------------------------------- match flow

func set_paused(v: bool) -> void:
	paused = v


func restart_match() -> void:
	if mp_mode:
		# Leaving an MP match returns to the boot flow (the home
		# lobby, 13g): clear the MP statics and drop the room
		# before reloading.
		mp_active = false
		mp_config = {}
		Engine.time_scale = 1.0
		Net.leave_room()
	get_tree().reload_current_scene()


## Annihilation rule: the enemy side counts as beaten when it is
## ELIMINATED (SP flag; MP: every opposing slot).
func _enemy_side_eliminated() -> bool:
	if mp_mode:
		if slot_count() == 0:
			return false
		for s in range(slot_count()):
			if team_of_slot(s) != view_team() and not slot_eliminated[s]:
				return false
		return true
	return sp_enemy_eliminated


func center_on_own_tc() -> void:
	if player_tc != null and cam != null:
		cam.focus_on(player_tc.position + Vector2(player_tc.size) * World.TILE * 0.5)


func select_all_villagers() -> void:
	var arr: Array = []
	for u in units:
		if _controllable(u) and u.unit_type == "villager":
			arr.append(u)
	set_selection(arr)


## True for entities the local player may select and order
## (SP: team 0; MP: the local slot's own entities).
func _controllable(e) -> bool:
	return e.owner_id == local_slot if mp_mode else e.team == 0


## Nearest living ship of the local player (selection clicks).
func local_ship_at(wpos: Vector2, radius: float = 38.0) -> Ship:
	var best: Ship = null
	var bd := radius
	for s in ships:
		if s.is_dead() or not is_local_owner(s.owner_id):
			continue
		var d: float = s.global_position.distance_to(wpos)
		if d < bd:
			bd = d
			best = s
	return best


func team_pop_current(team: int) -> int:
	var n := 0
	for u in units:
		if u.team == team and not u.is_dead():
			n += 1
	return n


func team_pop_cap(team: int) -> int:
	var n := 0
	for b in buildings:
		if b.team == team and b.complete and not b.destroyed:
			n += b.pop_bonus
	return n


func team_queued(team: int) -> int:
	var n := 0
	for b in buildings:
		if b.team == team:
			n += b.train_queue
	return n


func pop_current() -> int:
	return owner_pop_current(local_slot) if mp_mode else team_pop_current(0)


func pop_cap() -> int:
	return owner_pop_cap(local_slot) if mp_mode else team_pop_cap(0)


func get_team_barracks(team: int) -> Building:
	for b in buildings:
		if b.team == team and b.btype == "barracks" and b.complete and not b.destroyed:
			return b
	return null


func get_barracks() -> Building:
	for b in buildings:
		if b.team == 0 and b.btype == "barracks" and b.complete:
			return b
	return null


func training_building(kind: String) -> Building:
	if kind == "villager":
		return player_tc
	if kind == "king":
		return get_team_castle(0)
	return get_barracks()


func queued_total() -> int:
	var n := 0
	for b in buildings:
		if b.team == 0:
			n += b.train_queue
	return n


func can_train() -> bool:
	return can_train_unit("villager")


func can_train_unit(kind: String) -> bool:
	# The King is unique: one alive (or already mustering) per player.
	if kind == "king" and king_busy(local_slot if mp_mode else 0):
		return false
	if mp_mode:
		if owner_age(local_slot) < int(UNIT_MIN_AGE.get(kind, 1)):
			return false
		var mb := mp_training_building(local_slot, kind)
		if mb == null or not mb.complete:
			return false
		var mcosts: Dictionary = UNIT_COSTS[kind]
		for r in mcosts:
			if int(mp_wallets[local_slot].get(r, 0)) < int(mcosts[r]):
				return false
		return owner_pop_current(local_slot) + owner_queued(local_slot) < owner_pop_cap(local_slot)
	if age < int(UNIT_MIN_AGE.get(kind, 1)):
		return false
	var b := training_building(kind)
	if b == null or not b.complete:
		return false
	var costs: Dictionary = UNIT_COSTS[kind]
	for r in costs:
		if int(resources.get(r, 0)) < int(costs[r]):
			return false
	return pop_current() + queued_total() < pop_cap()


func _train_unit(kind: String) -> bool:
	if mp_mode:
		var mb := mp_training_building(local_slot, kind)
		if mb == null or not mb.complete:
			hud.show_message("Cần Lâu đài" if kind == "king" else
					("Cần Trại lính" if kind != "villager" else "Chưa có Town Center"))
			return false
		_mp_send_command({"kind": "train", "b": mb.net_id, "unit": kind})
		return true
	var b := training_building(kind)
	if b == null or not b.complete:
		hud.show_message("Cần Lâu đài" if kind == "king" else
				("Cần Trại lính" if kind != "villager" else "Not enough food"))
		return false
	if age < int(UNIT_MIN_AGE.get(kind, 1)):
		hud.show_message("Đơn vị này mở ở Thời đại %d" % int(UNIT_MIN_AGE[kind]))
		return false
	if not can_train_unit(kind):
		var costs: Dictionary = UNIT_COSTS[kind]
		var lacking := false
		for r in costs:
			if int(resources.get(r, 0)) < int(costs[r]):
				lacking = true
		hud.show_message("Not enough resources" if lacking else "Population cap reached")
		return false
	var costs2: Dictionary = UNIT_COSTS[kind]
	for r in costs2:
		resources[r] = int(resources[r]) - int(costs2[r])
	b.start_training(kind)
	_note_action(0) # 13y APM
	return true


func train_villager() -> bool:
	return _train_unit("villager")


func train_militia() -> bool:
	return _train_unit("militia")


func train_archer() -> bool:
	return _train_unit("archer")


func train_spearman() -> bool:
	return _train_unit("spearman")


func train_cavalry() -> bool:
	return _train_unit("cavalry")


func train_ram() -> bool:
	return _train_unit("ram")


func train_king() -> bool:
	if king_busy(local_slot if mp_mode else 0):
		hud.show_message("Nhân vật đang tại trận")
		return false
	return _train_unit("king")


# ---------------------------------------------------------------- selection

func clear_selection() -> void:
	for u in selection:
		u.selected = false
	selection.clear()
	selected_building = null
	if selected_ship != null:
		selected_ship.selected = false
		selected_ship = null


func set_selection(arr: Array) -> void:
	clear_selection()
	for u in arr:
		selection.append(u)
		u.selected = true


func building_at(wpos: Vector2) -> Building:
	var c := world.world_to_cell(wpos)
	for b in buildings:
		if b.cells().has(c):
			return b
	return null


func node_at_cell(c: Vector2i) -> ResourceNode:
	for n in world.nodes:
		if n.cell == c:
			return n
	return null


func select_unit_at(wpos: Vector2, radius: float = 20.0) -> bool:
	# Own ships first: they float on water where no land unit stands.
	var sship := local_ship_at(wpos, 38.0)
	if sship != null:
		clear_selection()
		selected_ship = sship
		sship.selected = true
		return true
	var best: Unit = null
	var bd := radius
	for u in units:
		if not _controllable(u):
			continue
		var d: float = u.global_position.distance_to(wpos)
		if d < bd:
			bd = d
			best = u
	if best != null:
		set_selection([best])
		return true
	var b := building_at(wpos)
	if b != null and _controllable(b):
		clear_selection()
		selected_building = b
		return true
	return false


func apply_box_selection(rect: Rect2) -> void:
	var found: Array = []
	var r := rect.grow(4.0)
	for u in units:
		if _controllable(u) and r.has_point(u.global_position):
			found.append(u)
	set_selection(found)


func select_all_of_type(sample: Unit) -> void:
	var found: Array = []
	for u in units:
		if _controllable(u) and u.unit_type == sample.unit_type:
			found.append(u)
	set_selection(found)


# ---------------------------------------------------------------- orders

func order_move(units_arr: Array, wpos: Vector2) -> void:
	var target := world.world_to_cell(wpos)
	var offsets: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
			Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1),
			Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
			Vector2i(2, 2), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2)]
	for i in range(units_arr.size()):
		var dest := world.nearest_walkable(target + offsets[i % offsets.size()])
		if dest.x >= 0:
			units_arr[i].order_move_cell(dest)


## Nearest living enemy unit to a world position (attack targeting).
## "Enemy" = any unit whose team differs from `for_team` (SP default
## for_team 0 finds team 1, exactly as before).
func enemy_unit_at(wpos: Vector2, radius: float = 24.0, for_team: int = 0,
		for_owner: int = -1) -> Unit:
	var best: Unit = null
	var bd := radius
	for u in units:
		if u.is_dead():
			continue
		# 15b: with an acting owner known, an ORDERED target must
		# pass the diplomacy gate (allies and break-window pairs
		# are untouchable); the plain team test is unchanged.
		if for_owner >= 0:
			if not attack_allowed(for_owner, u.owner_id):
				continue
		elif u.team == for_team:
			continue
		var d: float = u.global_position.distance_to(wpos)
		if d < bd:
			bd = d
			best = u
	return best


## Nearest living ship hostile to `for_team` (P4 generalisation of
## the old team-1 lookup). 15b: `for_owner` applies the same
## diplomacy gate as enemy_unit_at.
func enemy_ship_at(wpos: Vector2, for_team: int, radius: float = 30.0,
		for_owner: int = -1) -> Ship:
	var best: Ship = null
	var bd := radius
	for s in ships:
		if s.is_dead():
			continue
		if for_owner >= 0:
			if not attack_allowed(for_owner, s.owner_id):
				continue
		elif s.team == for_team:
			continue
		var d: float = s.global_position.distance_to(wpos)
		if d < bd:
			bd = d
			best = s
	return best


## Nearest living ship of `team` (-1 = any) to a world position.
func ship_at(wpos: Vector2, team: int = -1, radius: float = 30.0) -> Ship:
	var best: Ship = null
	var bd := radius
	for s in ships:
		if s.is_dead() or (team >= 0 and s.team != team):
			continue
		var d: float = s.global_position.distance_to(wpos)
		if d < bd:
			bd = d
			best = s
	return best


## Nearest living wild beast to a world position (attack orders).
func beast_at(wpos: Vector2, radius: float = 30.0) -> Beast:
	var best: Beast = null
	var bd := radius
	for b in world.beasts:
		if b.is_dead():
			continue
		var d: float = b.global_position.distance_to(wpos)
		if d < bd:
			bd = d
			best = b
	return best


func issue_order(wpos: Vector2) -> void:
	if mp_mode:
		# Orders are NOT applied locally in MP: they ride the relay
		# and come back stamped with an execution tick, to be applied
		# by apply_order_for at that tick like everyone else's.
		if selected_ship != null:
			_mp_send_command({"kind": "ship_order", "s": selected_ship.net_id,
					"x": wpos.x, "y": wpos.y})
		elif not selection.is_empty():
			var ids: Array = []
			for u in selection:
				ids.append(u.net_id)
			_mp_send_command({"kind": "order", "units": ids,
					"x": wpos.x, "y": wpos.y})
		return
	# 13y APM: an issued order counts once (mirrors the MP
	# validator accepting an "order"/"ship_order" command).
	if not selection.is_empty() or selected_ship != null:
		_note_action(0)
	apply_order_for(selection, selected_ship, wpos, 0)


## The right-click order logic itself, parameterised by the acting
## units/ship: SP calls it with the live selection; MP calls it at a
## command's execution tick with the commander's entities. `actor`
## is the owning slot (0 in SP) and gates HUD chatter so only the
## local player sees messages about their own orders.
func apply_order_for(units_arr: Array, ship: Ship, wpos: Vector2, actor: int) -> void:
	# A selected ship takes orders of its own (selection is empty then).
	if units_arr.is_empty():
		if ship != null:
			apply_ship_order_for(ship, wpos)
		return
	var own_team: int = units_arr[0].team
	# Boarding: right-clicking a friendly Transport with units selected.
	var ts := ship_at(wpos, own_team, 38.0)
	if ts != null and ts.ship_type == "transport":
		board_units(units_arr.duplicate(), ts, actor)
		return
	# 15g trade: right-clicking a Market with carts selected sets
	# (or re-sets) their trade route to it. Carts are peeled off
	# the selection; everyone else falls through to the ordinary
	# handling of the same click (an enemy Market stays an
	# attack target for the soldiers standing next to the cart).
	var clicked := building_at(wpos)
	if clicked != null and clicked.btype == "market":
		var carts: Array = []
		var rest0: Array = []
		for u0 in units_arr:
			if u0.unit_type == "cart":
				carts.append(u0)
			else:
				rest0.append(u0)
		if not carts.is_empty():
			for c0 in carts:
				assign_trade_route(c0, clicked)
			if rest0.is_empty():
				return
			units_arr = rest0
	# 15g wagon loading: right-clicking your own Wagon with foot
	# units selected boards the ones in reach (the ship rule);
	# the rest walk to the wagon. Clicking it with only itself
	# selected falls through to the plain move handling below.
	# (Radius covers the hull: the wagon's sprite runs ~111 world
	# px long since the 2026-11-11 scale pass, ~55 from centre.)
	var wg := own_wagon_at(wpos, actor, 56.0)
	if wg != null and not (units_arr.size() == 1 and units_arr[0] == wg):
		board_wagon_units(units_arr.duplicate(), wg, actor)
		return
	# P3: right-clicking an enemy unit or building is an attack order.
	# 15b: the acting owner's diplomacy gate decides what counts as
	# an enemy here (allies / break-window pairs are not targets).
	var eu := enemy_unit_at(wpos, 24.0, own_team, actor)
	if eu != null:
		for u in units_arr:
			u.order_attack(eu)
		return
	var es := enemy_ship_at(wpos, own_team, 38.0, actor)
	if es != null:
		for u in units_arr:
			u.order_attack(es)
		return
	var eb := building_at(wpos)
	if eb != null and eb.team != own_team and not eb.destroyed \
			and attack_allowed(actor, eb.owner_id):
		for u in units_arr:
			u.order_attack(eb)
		return
	# Wild beasts are attackable neutrals: an explicit order works
	# for every unit type, villagers included (they never auto-engage).
	var bst := beast_at(wpos)
	if bst != null:
		for u in units_arr:
			u.order_attack(bst)
		return
	var f := field_at_cell(world.world_to_cell(wpos))
	if f != null:
		for u in units_arr:
			if u.unit_type == "villager":
				u.order_field(f)
		return
	var node := node_at_cell(world.world_to_cell(wpos))
	if node != null and node.amount > 0:
		# Only villagers gather; military units just move to the node.
		var movers: Array = []
		for u in units_arr:
			if u.unit_type == "villager":
				u.order_gather(node)
			else:
				movers.append(u)
		if not movers.is_empty():
			order_move(movers, wpos)
		return
	var b := building_at(wpos)
	if b != null and b.team == own_team and not b.complete:
		for u in units_arr:
			if u.unit_type == "villager":
				u.order_build(b)
				break
		return
	# 15g: a loaded wagon ordered to plain ground travels there
	# and unloads on arrival (the Transport Ship's land rule);
	# everyone else in the click just moves.
	var movers2: Array = []
	for u2 in units_arr:
		if u2.unit_type == "wagon" and not u2.cargo.is_empty():
			u2.order_wagon_unload(world.world_to_cell(wpos))
		else:
			movers2.append(u2)
	if not movers2.is_empty():
		order_move(movers2, wpos)


## Units board a Transport: only those close enough to the hull
## (the ship must be at a shore cell, the units at the water's edge)
## actually embark; the rest are walked to the shore beside it.
func board_units(units_arr: Array, ts: Ship, actor: int = 0) -> void:
	var boarded := 0
	var movers: Array = []
	for u in units_arr:
		if u.global_position.distance_to(ts.global_position) <= 120.0 and ts.board_unit(u):
			boarded += 1
			if selection.has(u):
				selection.erase(u)
				u.selected = false
		else:
			movers.append(u)
	var chatter := not mp_mode or actor == local_slot
	if boarded > 0:
		if chatter:
			hud.show_message("Đã lên thuyền: %d/%d quân" % [ts.cargo.size(), Ship.TRANSPORT_CAP])
	elif ts.cargo.size() >= Ship.TRANSPORT_CAP:
		if chatter:
			hud.show_message("Thuyền đã đầy (5 quân)")
	if not movers.is_empty():
		var shore := world.nearest_walkable(ts.cell())
		if shore.x >= 0:
			order_move(movers, world.cell_center(shore))
		if boarded == 0 and ts.cargo.size() < Ship.TRANSPORT_CAP and chatter:
			hud.show_message("Đưa quân lại sát thuyền ở bờ nước để lên")


## 15g: nearest living Wagon of `owner` to a world position
## (the load-click lookup; allies' wagons are not loadable —
## cargo belongs to the wagon's owner by construction).
func own_wagon_at(wpos: Vector2, owner: int, radius: float = 38.0) -> Unit:
	var best: Unit = null
	var bd := radius
	for u in units:
		if u.unit_type != "wagon" or u.is_dead() or u.owner_id != owner:
			continue
		var d: float = u.global_position.distance_to(wpos)
		if d < bd:
			bd = d
			best = u
	return best


## 15g: foot units board a Wagon — only those within embark
## range of the hull actually climb in (board_units' ship rule);
## the rest are walked up to the wagon.
func board_wagon_units(units_arr: Array, wg: Unit, actor: int = 0) -> void:
	var boarded := 0
	var movers: Array = []
	for u in units_arr:
		if u == wg:
			continue
		if u.global_position.distance_to(wg.global_position) <= 120.0 \
				and wg.board_unit(u):
			boarded += 1
		elif Unit.wagon_loadable(u) and u.owner_id == wg.owner_id:
			movers.append(u)
	var chatter := not mp_mode or actor == local_slot
	if boarded > 0:
		if chatter and hud != null:
			hud.show_message("Đã lên xe: %d/%d quân" % [wg.cargo.size(), Unit.WAGON_CAP])
	elif wg.cargo.size() >= Unit.WAGON_CAP:
		if chatter and hud != null:
			hud.show_message("Xe đã đầy (5 quân)")
	if not movers.is_empty():
		var near := world.nearest_walkable(wg.cell())
		if near.x >= 0:
			order_move(movers, world.cell_center(near))
		if boarded == 0 and wg.cargo.size() < Unit.WAGON_CAP and chatter and hud != null:
			hud.show_message("Đưa quân lại sát xe để lên")


## Right-click orders for the currently selected own ship (SP entry).
func issue_ship_order(wpos: Vector2) -> void:
	if selected_ship != null:
		apply_ship_order_for(selected_ship, wpos)


## Right-click orders for one ship: SP passes the selected ship; MP
## passes the commanding slot's ship at the execution tick.
func apply_ship_order_for(s: Ship, wpos: Vector2) -> void:
	if s == null or s.is_dead():
		return
	var cell := world.world_to_cell(wpos)
	# Enemies first (war ships engage; other hulls just sail there).
	# 15b: the ship's owner's diplomacy gate applies here too.
	var eu := enemy_unit_at(wpos, 30.0, s.team, s.owner_id)
	var es := enemy_ship_at(wpos, s.team, 38.0, s.owner_id)
	var eb := building_at(wpos)
	if s.ship_type == "war_ship":
		if eu != null:
			s.order_attack(eu)
			return
		if es != null:
			s.order_attack(es)
			return
		if eb != null and eb.team != s.team and not eb.destroyed \
				and attack_allowed(s.owner_id, eb.owner_id):
			s.order_attack(eb)
			return
	# Fishing: a spot under the click (or one cell off) starts work.
	if s.ship_type == "fishing_boat":
		var spot := world.fish_spot_at_cell(cell)
		if spot == null:
			spot = world.nearest_fish_spot(wpos)
			if spot != null and spot.global_position.distance_to(wpos) > 52.0:
				spot = null
		if spot != null and spot.amount > 0:
			s.order_fish(spot)
			return
	# Transport unloading: a land click sails to the shore beside it
	# and puts the cargo ashore once arrived — handled by sailing to
	# the nearest navigable cell, then unloading immediately if the
	# hull is already shore-adjacent to the clicked land cell.
	if s.ship_type == "transport" and not s.cargo.is_empty() and not world.water.has(cell):
		var near := world.nearest_navigable(cell, 6)
		if near.x >= 0:
			s.order_move_cell(near)
			# If we are already next to that shore, unload right away.
			if Vector2(s.cell() - cell).length() <= 2.0:
				var n := s.unload_all(cell)
				if n > 0 and is_local_owner(s.owner_id):
					hud.show_message("Đã đổ bộ %d quân" % n)
			else:
				# Sail first; the unload happens on arrival via the
				# pending-unload marker checked in _process.
				s.set_meta("pending_unload", cell)
			return
	if world.water.has(cell):
		s.order_move_cell(cell)


# ---------------------------------------------------------------- farm fields

func field_at_cell(c: Vector2i) -> FieldPlot:
	for f in fields:
		if f.cell == c:
			return f
	return null


func get_farms(team: int) -> Array:
	var out: Array = []
	for b in buildings:
		if b.team == team and b.btype == "farm" and b.complete and not b.destroyed:
			out.append(b)
	return out


func fields_of_farm(farm: Building) -> int:
	var n := 0
	for f in fields:
		if f.farm == farm:
			n += 1
	return n


## Completed Farms owned by a player slot (MP).
func farms_of(owner: int) -> Array:
	var out: Array = []
	for b in buildings:
		if b.owner_id == owner and b.btype == "farm" and b.complete and not b.destroyed:
			out.append(b)
	return out


## Farms the local player can plant fields for (HUD + placement).
func local_farms() -> Array:
	return farms_of(local_slot) if mp_mode else get_farms(0)


## The completed player Farm a new plot at `cell` would belong to:
## within FIELD_RADIUS tiles of the farm's footprint, under its cap.
## owner < 0 keeps the SP team-0 lookup.
func farm_for_field(cell: Vector2i, owner: int = -1) -> Building:
	var farms: Array = get_farms(0) if owner < 0 else farms_of(owner)
	for farm in farms:
		var d := 1 << 30
		for fc in farm.cells():
			d = mini(d, maxi(absi(cell.x - fc.x), absi(cell.y - fc.y)))
		if d <= Stats.FIELD_RADIUS and fields_of_farm(farm) < Stats.FIELD_MAX_PER_FARM:
			return farm
	return null


func field_valid_at(cell: Vector2i, owner: int = -1) -> bool:
	if owner < 0 and mp_mode:
		owner = local_slot
	if field_at_cell(cell) != null:
		return false
	if not world.can_place(cell, Vector2i.ONE):
		return false
	return farm_for_field(cell, owner) != null


func enter_field_placement() -> void:
	if placing_type != "":
		cancel_placement()
	rally_setting = false
	if mp_mode:
		if local_farms().is_empty():
			hud.show_message("Cần một Farm hoàn thiện trước")
			return
		if int(mp_wallets[local_slot].get("wood", 0)) < Stats.FIELD_COST_WOOD:
			hud.show_message("Cần %d Wood cho một luống ruộng" % Stats.FIELD_COST_WOOD)
			return
		placing_field = true
		hud.show_message("Đặt luống ruộng (%d Wood) — nhấp ô cạnh Farm, Esc để xong" % Stats.FIELD_COST_WOOD)
		return
	if get_farms(0).is_empty():
		hud.show_message("Cần một Farm hoàn thiện trước")
		return
	if int(resources.get("wood", 0)) < Stats.FIELD_COST_WOOD:
		hud.show_message("Cần %d Wood cho một luống ruộng" % Stats.FIELD_COST_WOOD)
		return
	placing_field = true
	hud.show_message("Đặt luống ruộng (%d Wood) — nhấp ô cạnh Farm, Esc để xong" % Stats.FIELD_COST_WOOD)


func confirm_field_placement(cell: Vector2i) -> bool:
	if mp_mode:
		if not field_valid_at(cell):
			hud.show_message("Luống phải ở ô trống, trong %d ô quanh Farm (tối đa %d luống/Farm)" % [Stats.FIELD_RADIUS, Stats.FIELD_MAX_PER_FARM])
			return false
		_mp_send_command({"kind": "field", "cell": [cell.x, cell.y]})
		placing_field = false
		return true
	if not field_valid_at(cell):
		hud.show_message("Luống phải ở ô trống, trong %d ô quanh Farm (tối đa %d luống/Farm)" % [Stats.FIELD_RADIUS, Stats.FIELD_MAX_PER_FARM])
		return false
	if int(resources.get("wood", 0)) < Stats.FIELD_COST_WOOD:
		hud.show_message("Hết Wood cho luống ruộng")
		placing_field = false
		return false
	resources["wood"] = int(resources["wood"]) - Stats.FIELD_COST_WOOD
	var f := FieldPlot.new()
	f.cell = cell
	f.farm = farm_for_field(cell)
	fields.append(f)
	add_child(f)
	# Send the nearest selected (or any) villager to tend the new plot.
	var tender: Unit = null
	for u in selection:
		if u.team == 0 and u.unit_type == "villager" and not u.is_dead():
			tender = u
			break
	if tender == null:
		var bd := INF
		for u in units:
			if u.team == 0 and u.unit_type == "villager" and not u.is_dead():
				var d: float = u.global_position.distance_squared_to(f.position)
				if d < bd:
					bd = d
					tender = u
	if tender != null:
		tender.order_field(f)
	_note_action(0) # 13y APM (SP field confirm)
	return true


## Gather-style poof when a plot grows or is harvested.
func on_field_effect(f: FieldPlot) -> void:
	if vfx != null:
		vfx.puff(f.position + Vector2(16, 10), res_color("food"), 4)


# ---------------------------------------------------------------- placement

func can_afford(btype: String) -> bool:
	var cost: Dictionary = get_build_def(btype).cost
	var w := display_resources()
	for r in cost:
		if int(w.get(r, 0)) < int(cost[r]):
			return false
	return true


## Dock placement rule: the footprint must reach the shoreline — at
## least one footprint cell orthogonally/diagonally adjacent to a
## water cell. (Footprint cells themselves must be buildable land;
## world.can_place already rejects water, which is solid.)
func is_shore_spot(origin: Vector2i, size: Vector2i) -> bool:
	for c in world.footprint_cells(origin, size):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			if world.water.has(c + d):
				return true
	return false


## Full placement validity for a building type at `cell`: the usual
## footprint check, plus the shoreline rule for the Dock.
func placement_valid_at(cell: Vector2i, btype: String) -> bool:
	var def := get_build_def(btype)
	if not world.can_place(cell, def.size):
		return false
	if btype == "dock":
		return is_shore_spot(cell, def.size)
	return true


func enter_placement(btype: String) -> void:
	rally_setting = false
	if placing_type != "":
		cancel_placement()
	if not can_afford(btype):
		hud.show_message("Not enough resources")
		return
	if mp_mode:
		# No up-front deduction in MP: the cost is charged on every
		# client when the build command applies at its tick.
		placing_type = btype
		_placing_cell = Vector2i(-1, -1)
		return
	var cost: Dictionary = get_build_def(btype).cost
	for r in cost:
		resources[r] = int(resources[r]) - int(cost[r]) # deducted up-front; refunded if placement is cancelled
	placing_type = btype
	_placing_cell = Vector2i(-1, -1)


func cancel_placement() -> void:
	if placing_type == "":
		return
	if mp_mode:
		placing_type = "" # nothing was deducted locally
		return
	var cost: Dictionary = get_build_def(placing_type).cost
	for r in cost:
		resources[r] = int(resources[r]) + int(cost[r])
	placing_type = ""


func confirm_placement(cell: Vector2i) -> bool:
	if mp_mode:
		if placing_type == "":
			return false
		var mdef := get_build_def(placing_type)
		if not placement_valid_at(cell, placing_type):
			if placing_type == "dock" and world.can_place(cell, mdef.size):
				hud.show_message("Dock must be built at the shoreline")
			else:
				hud.show_message("Cannot build there")
			return false
		_mp_send_command({"kind": "build", "btype": placing_type,
				"cell": [cell.x, cell.y]})
		placing_type = ""
		return true
	if placing_type == "":
		return false
	var def := get_build_def(placing_type)
	if not placement_valid_at(cell, placing_type):
		if placing_type == "dock" and world.can_place(cell, def.size):
			hud.show_message("Dock must be built at the shoreline")
		else:
			hud.show_message("Cannot build there")
		return false
	var b := _spawn_building(placing_type, 0, cell, false)
	placing_type = ""
	_note_action(0) # 13y APM (SP build confirm)
	# Nearest idle villager builds it; otherwise the nearest villager overall.
	var builder: Unit = null
	var bd := INF
	for u in units:
		if u.team != 0:
			continue
		var d: float = u.global_position.distance_squared_to(b.position + Vector2(def.size) * World.TILE * 0.5)
		if u.state == "idle" and d < bd:
			bd = d
			builder = u
	if builder == null:
		bd = INF
		for u in units:
			if u.team != 0:
				continue
			var d: float = u.global_position.distance_squared_to(b.position)
			if d < bd:
				bd = d
				builder = u
	if builder != null:
		builder.order_build(b)
	return true


# ---------------------------------------------------------------- input

func _process(delta: float) -> void:
	if _entry_boot_pending:
		return # 13r: the world does not exist until boot step 2
	if mp_mode:
		if replay_mode:
			_replay_feed(delta)
		_mp_drive()
		if replay_mode:
			_replay_post()
	if not paused:
		match_time += delta
		# 13y: score-over-time sampling for the result chart.
		if match_time >= _stat_next_sample:
			_sample_stats()
		_update_projectiles(delta)
		# 16b skill sim: the arrow-rain zone + Kiếm Vũ flurries
		# tick beside the arrow sim (deterministic, checksum-
		# covered).
		_update_skill_zones(delta)
		_update_hero_flurries(delta)
		_update_diplomacy(delta) # 15b: declaration windows + tribute cooldowns
		_update_towers(delta)
		_update_ship_orders(delta)
		if mp_mode:
			_mp_update_ages(delta)
		elif age_researching:
			age_timer -= delta
			if age_timer <= 0.0:
				age_researching = false
				set_team_age(0, age_target)
				hud.show_message(_age_done_text(age_target))
		_update_techs(delta)
	# Vương Kiếm impact shake (presentation only; cam.offset is
	# never sim state).
	if _shake_t > 0.0:
		_shake_t -= delta
		var m := 7.0 * maxf(_shake_t, 0.0) / 0.32
		cam.offset = Vector2(randf_range(-m, m), randf_range(-m, m))
		if _shake_t <= 0.0:
			cam.offset = Vector2.ZERO
	if placing_type != "":
		_placing_cell = world.world_to_cell(get_global_mouse_position())
		_placing_valid = placement_valid_at(_placing_cell, placing_type)
	if placing_field:
		_field_cell = world.world_to_cell(get_global_mouse_position())
		_field_valid = field_valid_at(_field_cell)
	if _lmb_down and not _long_fired and not _dragging_box and placing_type == "":
		if Time.get_ticks_msec() - _press_msec > 450 and not selection.is_empty():
			if get_global_mouse_position().distance_to(_press_pos) < 12.0:
				_long_fired = true
				issue_order(get_global_mouse_position())
	overlay.queue_redraw()


## Transports that were ordered to a shore unload on arrival;
## fish spots occasionally ripple + flash a leaping fish.
var _fish_fx_t := 0.0


func _update_ship_orders(delta: float) -> void:
	for s in ships:
		if s.has_meta("pending_unload") and s.state == "idle":
			var cell: Vector2i = s.get_meta("pending_unload")
			s.remove_meta("pending_unload")
			if Vector2(s.cell() - cell).length() <= 2.5:
				var n: int = s.unload_all(cell)
				if n > 0 and is_local_owner(s.owner_id):
					hud.show_message("Đã đổ bộ %d quân" % n)
	_fish_fx_t -= delta
	if _fish_fx_t <= 0.0:
		_fish_fx_t = 1.6
		if vfx != null and not world.fish_spots.is_empty():
			var spot: FishSpot = world.fish_spots[randi() % world.fish_spots.size()]
			if spot.amount > 0:
				vfx.ripple(spot.global_position, Color(0.85, 0.95, 1.0, 0.5), 18.0, 1.3)
				if randf() < 0.45:
					vfx.glint(spot.global_position + Vector2(0, -6),
							Color(0.85, 0.93, 1.0, 0.9), 9.0, 0.45)


func _unhandled_input(event: InputEvent) -> void:
	if _entry_boot_pending:
		return # 13r: world not built yet
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			if skill_targeting > 0:
				skill_targeting = -1 # 13v: Esc cancels skill targeting
			elif rally_setting:
				rally_setting = false
			elif placing_field:
				placing_field = false
			elif placing_type != "":
				cancel_placement()
			elif hud != null and hud.has_method("close_panel_if_open") \
					and hud.close_panel_if_open():
				pass # 13s: Esc closes an open action panel first
			else:
				clear_selection()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var wpos := get_global_mouse_position()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if skill_targeting > 0:
					# 13v: the click IS the cast point.
					var idx := skill_targeting
					skill_targeting = -1
					cast_local_skill_at(idx, wpos)
					return
				if rally_setting:
					rally_setting = false
					if mp_mode:
						_mp_send_command({"kind": "rally", "x": wpos.x, "y": wpos.y})
					else:
						rally_point = wpos
						_note_action(0) # 13y APM
					hud.show_message("Đã đặt điểm tập kết")
					return
				_lmb_down = true
				_long_fired = false
				_was_double = mb.double_click
				_press_msec = Time.get_ticks_msec()
				_press_pos = wpos
				_drag_start = wpos
				_drag_cur = wpos
				_dragging_box = false
				if placing_field:
					confirm_field_placement(world.world_to_cell(wpos))
					_lmb_down = false
				elif placing_type != "":
					confirm_placement(world.world_to_cell(wpos))
					_lmb_down = false
				elif mb.double_click:
					# Double-click: select all own units of the clicked type (whole map).
					for u in units:
						if _controllable(u) and u.global_position.distance_to(wpos) < 20.0:
							select_all_of_type(u)
							break
			else:
				_lmb_down = false
				if placing_type != "" or placing_field:
					return
				if _long_fired:
					_long_fired = false
					return
				if _dragging_box:
					_dragging_box = false
					apply_box_selection(Rect2(_drag_start, _drag_cur - _drag_start).abs())
				elif not _was_double:
					if not select_unit_at(wpos):
						clear_selection()
				_was_double = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if skill_targeting > 0:
					skill_targeting = -1 # 13v: right-click cancels targeting
					return
				if placing_field:
					placing_field = false
					return
				if placing_type != "":
					cancel_placement()
					return
				_rmb_down = true
				_rmb_moved = false
				_rmb_press_pos = wpos
			else:
				if _rmb_down and not _rmb_moved:
					issue_order(wpos)
				_rmb_down = false
	elif event is InputEventMouseMotion:
		var wpos2 := get_global_mouse_position()
		if _lmb_down and placing_type == "":
			_drag_cur = wpos2
			if wpos2.distance_to(_drag_start) > 10.0:
				_dragging_box = true
		if _rmb_down and wpos2.distance_to(_rmb_press_pos) > 10.0:
			_rmb_moved = true
