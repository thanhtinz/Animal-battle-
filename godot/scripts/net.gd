extends Node
## Net — Empire Age P4 multiplayer relay client (autoload singleton).
##
## Wraps the WebSocket connection to the Go relay server (a dumb
## relay: rooms, lobby, tick clock, command stamping, checksum
## comparison — see server/README.md). This node owns NO game state:
## Main connects to its signals when an MP match boots.
##
## Lockstep model: the server ticks at 10/s. A client sends its
## player's commands WITHOUT applying them; the server relays every
## command to all clients stamped with the tick at which it must be
## applied (receipt tick + input delay). Main applies commands only
## at tick boundaries and advances the simulation in fixed steps per
## tick, so every client runs the same commands in the same order at
## the same sim tick. Clients report a state checksum every 30 ticks;
## the server broadcasts DESYNC when they diverge — and, since P4
## stage 2, runs a resync cycle: a majority-hash client serves a
## full-state snapshot and diverged clients rebuild from it. Stage 2
## also added room/team chat relay and optional accounts (register/
## login tokens, W/L profiles, leaderboard) — chat and auth are pure
## relay/session traffic, never part of lockstep state.
##
## Also hosts the automated smoke-test driver (--mp-auto): it drives
## the lobby flow and scripted in-match actions for two headless
## clients (tests/mp_smoke.sh). Inert unless the arg is present.

signal room_updated
signal joined_room(code: String, slot: int)
signal match_started(cfg: Dictionary)
signal tick_received(tick: int)
signal command_received(from_slot: int, exec_tick: int, cmd: Dictionary)
signal player_left(slot: int)
signal desync_notice(tick: int)
signal lobby_error(msg: String)
signal connection_closed
# P4 stage 2: chat / accounts / resync.
signal chat_received(scope: String, from_slot: int, sender_name: String, text: String, ally_tag: String, bubble_style: String)
signal auth_ok(token: String, profile: Dictionary)
signal avatar_changed(avatar_id: String)
# 17d: a fresh full profile after a cosmetics op (set_frame /
# set_bubble / set_title / rename); surfaces re-render from it.
signal profile_updated(profile: Dictionary)
# 17d: a rename rejected by the 30-day cooldown carries the
# next allowed date (unix seconds; name_error fires too).
signal rename_failed(msg: String, next_at: int)
# 13r: display-name system (the "Đặt Tên Nhân Vật" panel).
signal display_name_changed(display_name: String)
signal name_error(msg: String)
signal auth_error(msg: String)
signal auth_out
signal leaderboard_received(rows: Array, mode: String, me: Dictionary)
signal resync_started(tick: int, source_slot: int)
signal resync_notice_received(slots: Array)
signal snapshot_requested(tick: int)
signal snapshot_received(tick: int, state: Dictionary)
signal resync_failed_notice(tick: int)
# P4 stage 3: ranked matchmaking + referee.
signal queue_joined_notice(mmr: int)
signal queue_left_notice
## 13z: live queue progress from the server ({queue_status}):
## how many players the forming match already has, of how many.
signal queue_status_notice(found: int, need: int, queue: String)
signal match_found_notice(code: String, slot: int, opponent: Dictionary)
# P4 stage 4: seasonal rank ladder — the server pushes each player
# their own ladder movement right after banking a ranked result.
signal rank_result_received(info: Dictionary)
# P4 stage 5 (13g home lobby): match history, friends, mail, ping.
signal history_received(rows: Array)
# Replay (13h): fetch + playback hand-off.
signal replay_received(rp: Dictionary)
signal replay_failed(msg: String)
signal custom_replay_received(replay_id: String, room: String)
signal friends_received(rows: Array)
signal friend_error(msg: String)
signal mail_received(rows: Array, unread: int)
# 15a custom-match expansion: room browser, observers, host powers.
signal room_list_received(rows: Array)
signal kicked_notice
signal room_closed_notice
signal obs_snapshot_requested
# 15h tournaments: list/detail payloads + dedicated-room entry.
signal tourn_list_received(rows: Array)
signal tourn_detail_received(tourn: Dictionary)
signal tourn_created_notice(id: String)
signal tourn_room_joined(code: String, slot: int)
# 17a alliances: home payload (my alliance view + my invites)
# and the not-joined browser rows. Alliance CHAT rides the
# shared chat_received signal with scope == "alliance".
signal alliance_home_received(mine: Dictionary, invites: Array)
signal alliance_list_received(rows: Array)
# 17e chat hub: the raw chat line (peer / from_user / war_champ
# ride here; chat_received keeps its fixed signature for the
# in-match listeners), voice lines, marquee + megaphone
# pushes, DM pushes, and the system feed.
signal chat_line_received(m: Dictionary)
signal voice_line_received(m: Dictionary, wav: PackedByteArray)
signal marquee_received(sender_name: String, text: String)
signal megaphones_changed(count: int)
signal dm_list_received(rows: Array)
signal dm_thread_received(peer: String, rows: Array)
signal dm_line_received(peer: String, mine: bool)
signal system_feed_changed

const DEFAULT_URL := "ws://127.0.0.1:8765/ws"
## Sim compatibility tag; must match the server's GameVersion.
## A replay recorded under another tag still plays, but the home
## screen warns first (the sim may have changed since).
const GAME_VERSION := "v13"
## The replay being played / about to play (survives the scene
## reload into the match scene, like pending_cfg).
var replay_data: Dictionary = {}
var replay_seek_target: int = 0

var peer: WebSocketPeer = null
var connected: bool = false
var my_slot: int = -1
var room_code: String = ""
var is_host: bool = false
var in_match: bool = false
var current_tick: int = 0
var players: Array = [] # latest room views [{slot,name,ready,team,connected}]
var host_slot: int = 0
var room_in_match: bool = false
var cfg_biome: String = "grassland"
var cfg_layout: String = "plains"
var pending_cfg: Dictionary = {}

# Account session (P4 stage 2). Guests simply never fill these in.
var auth_token: String = ""
var auth_profile: Dictionary = {} # {user, wins, losses, matches, mmr}
var account_name: String = ""

# "Ghi nhớ đăng nhập" (13r): when true at auth time, the session
# TOKEN (never the password) is written to user://session.cfg and
# restored at boot via login_token. Set by the login screen's
# checkbox before it fires login/register.
var remember_session: bool = false
const SESSION_PATH := "user://session.cfg"

# Ranked state (P4 stage 3). `ranked` marks the current room as a
# matchmade, referee-owned room; leaderboard_mode echoes which
# board the last leaderboard response carried.
var ranked: bool = false
var ranked_opponent: Dictionary = {} # {user, mmr, rank_text}
# 15a: the current room's public face + this session's observer
# state, mirrored from the server's room broadcasts.
var is_observer: bool = false
## Set by the server's obs_sync_pending (mid-match observer
## join): Main freezes its sim until the host's snapshot lands.
var obs_needs_snapshot: bool = false
var cfg_room_name: String = ""
var cfg_public: bool = false
var cfg_has_password: bool = false
var cfg_allow_obs: bool = false
var cfg_diplomacy: bool = false # 15b: in-match diplomacy opt-in (custom only)
var cfg_obs_delay: int = 0 # 15e: spectator delay seconds (0 = live stream)
var room_observers: Array = [] # observer display names in the room
var room_list_rows: Array = [] # last room-browser payload
# 13t: the current room came out of a matchmaking queue (ranked or
# normal) — such rooms auto-start on the server countdown and skip
# the ready/start step in the room view.
var queued_room: bool = false
var leaderboard_mode: String = "wl"
var leaderboard_me: Dictionary = {} # {pos, row} of the caller (13g BXH footer)
var last_rank_result: Dictionary = {} # latest rank_result payload (stage 4)
var tourn_list_rows: Array = [] # latest tourn_list payload (15h)
var tourn_detail: Dictionary = {} # latest tourn_detail payload (15h)
var tourn_room: Dictionary = {} # {code, slot, tourn_id, match} once bound (15h)
var alliance_mine: Dictionary = {}
# 17e chat-hub session state: world transcript (cap 200),
# DM threads/conversations + live unread, the megaphone
# count, and the Hệ thống feed (real session events only —
# server system pushes, ranked results, alliance notices,
# and the mailbox rendered read-only by the panel).
var world_chat_lines: Array = []
var dm_threads: Dictionary = {}
var dm_convs: Array = []
var dm_unread: Dictionary = {}
var megaphone_count: int = 0
var system_feed: Array = []
var _last_ally_notice: String = ""
var _mq_seen: Array = []
var _mq_layer: CanvasLayer = null
var _mq_strip: PanelContainer = null
var _mq_clip: Control = null
var _mq_label: Label = null
var _mq_queue: Array = []
var _mq_x: float = 0.0
var _mq_text_w: float = 0.0
var _mq_active: bool = false
var alliance_invites: Array = [] # alliances holding an invite for me (17a)
var alliance_rows: Array = [] # latest alliance_list payload (17a)
var alliance_chat_lines: Array = [] # session transcript [{name, text}] of the alliance channel (17a)
# Stage 5 (home lobby): social + history caches and the latency
# readout (app-level ping/pong against the relay).
var history_rows: Array = []
var friends_rows: Array = []
var mail_rows: Array = []
var mail_unread: int = 0
var ping_ms: int = -1 # -1 = not connected / no sample yet
var _ping_accum: float = 0.0

# Referee process state (P4 stage 3): set from --referee* args.
var is_referee: bool = false
var referee_room: String = ""
var referee_token: String = ""
var referee_url: String = DEFAULT_URL
var referee_kill_tick: int = -1 # ranked-smoke hook (referee sim only)
var referee_kill_slot: int = -1
var referee_kills: Array = [] # 13z list form: [[tick, slot], ...]
var _referee_join_sent: bool = false
var _referee_connect_tried: bool = false

# --- automated smoke-test driver state --------------------------------------
var auto: Dictionary = {}
var _auto_phase: String = ""
var _auto_issued: bool = false
var _auto_last_order_tick: int = -1000
var _auto_stage: int = 0
var _auto_stage_at_issue: int = -1
var _auto_target := Vector2.ZERO
var _auto_last_centre := Vector2.INF
var _auto_stall_tick: int = 0
var _auto_lobby_opened: bool = false
var _auto_shot_done: bool = false
var _auto_started_ticks: int = -1
var _auto_scout_unit = null
var _auto_corrupted: bool = false
var _auto_authed: bool = false
var _auto_auth_login_tried: bool = false
var _auto_lb_requested: bool = false
var _auto_lb_received: bool = false
var _auto_chat_sent: bool = false
var _auto_chat_at: int = 0 # msec when the host's greeting went out
var _auto_chat_reply_due: int = 0 # msec when the peer should answer
var _auto_ranked_queued: bool = false
var _auto_mm_seeded: bool = false # 13p: queue clock seeded for the shot
var _auto_cancel_phase: int = 0 # 13p: matchmaking-cancel shot phase
# 15a custom-expansion driver state.
var _auto_kicked_at: int = 0 # msec when kicked/room_closed landed
var _auto_kick_done: bool = false
var _auto_transfer_done: bool = false
var _auto_browse_stage: int = 0
var _auto_browse_at: int = 0 # msec when the current browse stage began
var _auto_browse_got_list: bool = false
var _auto_obs_cmd_tried: bool = false
# 15e spectator driver state (smoke/capture hooks only).
var _auto_boot_ms: int = 0 # msec when the auto driver first ticked
var _auto_obs_wait_printed: bool = false
var _auto_obs_live_printed: bool = false
var _auto_spec_mode_set: bool = false
var _auto_spec_last_print: int = -1 # last tick a spec debug line was printed
var _auto_spec_scout_moved: bool = false
var _auto_lb_rows: Array = []
var _auto_home_at: int = 0 # msec when the home-shot driver authed
# 15h tournament smoke driver state (--mp-tourn=create|join|joinany).
var _tourn_id: String = ""
var _tourn_next_poll: int = 0
var _tourn_create_sent: bool = false
var _tourn_registered: bool = false
var _tourn_started: bool = false
var _tourn_checked: Dictionary = {} # match id -> true once our check-in was sent
var _tourn_play_sent: Dictionary = {} # match id -> msec the play request was sent
var _tourn_finished_printed: bool = false
var _tourn_quit_at: int = 0
var _tourn_shot_stage: int = 0
# 17a alliance smoke driver state (--mp-alliance=create|apply|outside).
var _ally_stage: int = 0
var _ally_next_poll: int = 0
var _ally_authed_at: int = 0
var _ally_quit_at: int = 0
var _ally_id: String = ""



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep pumping during end-panel pauses
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("mp-auto") or args.has("mp-shot-lobby") or args.has("mp-scout-shot") \
			or args.has("mp-shot-account") or args.has("mp-chat-shot") \
			or args.has("mp-ranked") or args.has("mp-lbcheck") \
			or args.has("mp-normal") or args.has("mp-shot-normal") \
			or args.has("mp-shot-ranked") or args.has("mp-shot-mm-cancel") \
			or args.has("mp-shot-ranklb") \
			or args.has("mp-shot-home") or args.has("mp-shot-history") \
			or args.has("mp-shot-profile") \
			or args.has("mp-shot-friends") \
			or args.has("mp-replay-fetch") or args.has("mp-replay-shot") \
			or args.has("mp-shot-login") or args.has("mp-shot-login-register") \
			or args.has("mp-shot-login-notice") or args.has("mp-test-cache") \
			or args.has("mp-shot-loading") or args.has("mp-shot-namepanel") \
			or args.has("mp-shot-welcome") \
			or args.has("mp-register-flow") \
			or args.has("mp-shot-create") or args.has("mp-shot-browser") \
			or args.has("mp-shot-create-delay") \
			or args.has("mp-tourn") or args.has("mp-shot-tourn-list") \
			or args.has("mp-shot-tourn-bracket") \
			or args.has("mp-alliance") or args.has("mp-shot-alliance") \
			or args.has("mp-alliance2") or args.has("mp-shot-alliance2") \
			or args.has("mp-settings") or args.has("mp-shot-settings") \
			or args.has("mp-chathub") or args.has("mp-shot-chathub") \
			or args.has("mp-kill"):
		auto = args
		_auto_phase = "boot"
		if _entry_mode():
			_auto_phase = "entry"
		print("MPLOG auto driver armed: ", args)
	if args.has("referee"):
		# Dedicated-referee process: no auto driver, no human. It
		# connects, authenticates with the one-time token, and boots
		# the match when the server says match_start.
		is_referee = true
		referee_room = String(args.get("referee-room", ""))
		referee_token = String(args.get("referee-token", ""))
		referee_url = String(args.get("referee-url", DEFAULT_URL))
		referee_kill_tick = int(args.get("referee-test-kill", "-1"))
		referee_kill_slot = int(args.get("referee-test-kill-slot", "-1"))
		# 13z: --referee-test-kills=120:1,135:2,... arms a whole
		# elimination sequence (an 8-player match needs seven).
		for pair in String(args.get("referee-test-kills", "")).split(","):
			var kv := pair.split(":")
			if kv.size() == 2 and kv[0].is_valid_int() and kv[1].is_valid_int():
				referee_kills.append([int(kv[0]), int(kv[1])])
		print("MPLOG referee armed room=", referee_room,
				" kill_tick=", referee_kill_tick, " kill_slot=", referee_kill_slot,
				" kills=", referee_kills)
	auth_ok.connect(func(_t: String, p: Dictionary) -> void:
		_auto_authed = true
		if not auto.is_empty():
			print("MPLOG profile user=", String(p.get("user", "")),
					" mmr=", int(p.get("mmr", 0)),
					" wins=", int(p.get("wins", 0)),
					" losses=", int(p.get("losses", 0)),
					" rank=", String(p.get("rank", {}).get("rank_text", ""))))
	leaderboard_received.connect(func(rows: Array, _mode: String, _me: Dictionary) -> void:
		_auto_lb_rows = rows)
	auth_error.connect(func(_msg: String) -> void:
		# Account-shot driver: a duplicate registration just means
		# the account already exists on this server — log in instead.
		if auto.has("mp-account") and not _auto_authed and not _auto_auth_login_tried:
			_auto_auth_login_tried = true
			var parts := String(auto["mp-account"]).split(":", true, 1)
			if parts.size() == 2:
				login_account(parts[0], parts[1]))
	leaderboard_received.connect(func(_rows: Array, _mode: String, _me: Dictionary) -> void:
		_auto_lb_received = true)
	replay_received.connect(func(rp: Dictionary) -> void:
		# Replay verification driver: fetch -> play back at once.
		if auto.has("mp-replay-fetch") and not auto.has("mp-replay-begun"):
			auto["mp-replay-begun"] = true
			print("MPLOG replay fetched final_tick=", int(rp.get("final_tick", 0)),
					" winner_team=", int(rp.get("winner_team", -1)),
					" cmds=", (rp.get("cmds", []) as Array).size())
			# 14a: seek-at-start for the seek-correctness smoke.
			begin_replay(rp, int(auto.get("mp-replay-seek", 0))))
	chat_received.connect(func(_scope: String, from_slot: int, _n: String, _t: String, _tag: String, _bub: String) -> void:
		# Chat-shot peer: answer the host's greeting shortly after
		# it actually arrives (order-safe even on a slow host).
		if auto.has("mp-chat-peer") and from_slot != my_slot \
				and not _auto_chat_sent and _auto_chat_reply_due == 0:
			_auto_chat_reply_due = Time.get_ticks_msec() + 1200)
	lobby_error.connect(func(msg: String) -> void:
		# 15a drivers assert on server error lines (wrong room
		# password, observer command rejection, bans).
		if not auto.is_empty():
			print("MPLOG lobby error=", msg))
	room_list_received.connect(func(_rows: Array) -> void:
		_auto_browse_got_list = true)


# ------------------------------------------------------------------ transport

func connect_to_server(url: String) -> void:
	disconnect_from_server()
	peer = WebSocketPeer.new()
	var err := peer.connect_to_url(url)
	if err != OK:
		lobby_error.emit("Không nối được máy chủ (%d)" % err)
		peer = null
		return
	set_process(true)


func disconnect_from_server() -> void:
	if peer != null:
		peer.close()
		peer = null
	connected = false
	in_match = false
	my_slot = -1
	room_code = ""


func _process(delta: float) -> void:
	if _mq_active:
		_marquee_tick(delta)
	if is_referee and peer == null and not _referee_connect_tried:
		_referee_connect_tried = true
		connect_to_server(referee_url)
	if peer != null:
		peer.poll()
		var st := peer.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			if not connected:
				connected = true
				_ping_accum = 2.3 # first latency sample almost at once
				_auto_on_connected()
				if is_referee:
					_referee_on_connected()
			while peer.get_available_packet_count() > 0:
				var txt := peer.get_packet().get_string_from_utf8()
				_handle_message(txt)
			# Latency probe for the home lobby readout: an app-level
			# ping every ~2.5 s; the relay echoes the timestamp.
			if not is_referee:
				_ping_accum += delta
				if _ping_accum >= 2.5:
					_ping_accum = 0.0
					_send({"t": "ping", "ts": Time.get_ticks_msec()})
		elif st == WebSocketPeer.STATE_CLOSED:
			var was := connected
			peer = null
			connected = false
			ping_ms = -1
			if was:
				connection_closed.emit()
				if is_referee:
					print("MPLOG referee connection closed; quitting")
					get_tree().quit()
	_auto_process()


## Referee handshake: claim the room's referee role with the
## one-time token the server spawned this process with.
func _referee_on_connected() -> void:
	if _referee_join_sent:
		return
	_referee_join_sent = true
	_send({"t": "referee_join", "code": referee_room, "token": referee_token})
	print("MPLOG referee join sent room=", referee_room)


func _send(msg: Dictionary) -> void:
	if peer != null and connected:
		peer.send_text(JSON.stringify(msg))


func _handle_message(txt: String) -> void:
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return
	var m: Dictionary = parsed
	match String(m.get("t", "")):
		"created":
			room_code = String(m.get("code", ""))
			my_slot = int(m.get("slot", 0))
			is_host = true
			print("MPLOG room code=", room_code, " slot=", my_slot)
			joined_room.emit(room_code, my_slot)
		"joined":
			room_code = String(m.get("code", ""))
			my_slot = int(m.get("slot", -1))
			is_host = false
			print("MPLOG room code=", room_code, " slot=", my_slot)
			joined_room.emit(room_code, my_slot)
		"room":
			room_code = String(m.get("code", room_code))
			host_slot = int(m.get("host", 0))
			room_in_match = bool(m.get("in_match", false))
			ranked = bool(m.get("ranked", ranked))
			cfg_biome = String(m.get("biome", cfg_biome))
			cfg_layout = String(m.get("layout", cfg_layout))
			cfg_room_name = String(m.get("room_name", cfg_room_name))
			cfg_public = bool(m.get("public", cfg_public))
			cfg_has_password = bool(m.get("has_password", cfg_has_password))
			cfg_allow_obs = bool(m.get("allow_obs", cfg_allow_obs))
			cfg_diplomacy = bool(m.get("diplomacy", cfg_diplomacy))
			cfg_obs_delay = int(m.get("obs_delay", cfg_obs_delay))
			room_observers = m.get("observers", [])
			players = m.get("players", [])
			# 15a: outside ranked rooms the host role is whatever
			# the latest room state says (host transfer + auto-
			# transfer move it live). Ranked rooms never report
			# through a player, so their flag stays as match_found
			# set it (false for everyone).
			if my_slot >= 0 and not ranked:
				is_host = host_slot == my_slot
			if not auto.is_empty():
				print("MPLOG room host=", host_slot, " players=", players.size(),
						" observers=", room_observers.size(),
						" public=", cfg_public, " pass=", cfg_has_password,
						" obs=", cfg_allow_obs)
			room_updated.emit()
		"observing":
			room_code = String(m.get("code", ""))
			my_slot = -1
			is_host = false
			is_observer = true
			print("MPLOG observing code=", room_code)
			joined_room.emit(room_code, -1)
		"room_list":
			room_list_rows = m.get("rooms", [])
			print("MPLOG room list rows=", room_list_rows.size())
			room_list_received.emit(room_list_rows)
		"tourn_list":
			tourn_list_rows = m.get("rows", [])
			print("MPLOG tourn list rows=", tourn_list_rows.size())
			tourn_list_received.emit(tourn_list_rows)
		"tourn_detail":
			tourn_detail = m.get("tourn", {})
			print("MPLOG tourn detail id=", String(tourn_detail.get("id", "")),
					" state=", String(tourn_detail.get("state", "")),
					" entries=", (tourn_detail.get("entries", []) as Array).size(),
					" matches=", (tourn_detail.get("matches", []) as Array).size(),
					" champion=", String(tourn_detail.get("champion_name", "")))
			tourn_detail_received.emit(tourn_detail)
		"tourn_created":
			print("MPLOG tourn created id=", String(m.get("id", "")))
			tourn_created_notice.emit(String(m.get("id", "")))
		"tourn_match":
			# A tournament match's dedicated room: referee-owned
			# like ranked (nobody reports), entered directly (no
			# queue). The room broadcast that follows carries the
			# roster; match_start drives the match as usual.
			room_code = String(m.get("code", ""))
			my_slot = int(m.get("slot", -1))
			ranked = true
			queued_room = true
			is_host = false
			tourn_room = {"code": room_code, "slot": my_slot,
					"tourn_id": String(m.get("tourn_id", "")),
					"match": int(m.get("match", 0))}
			print("MPLOG tourn room code=", room_code, " slot=", my_slot,
					" tourn=", String(tourn_room["tourn_id"]),
					" match=", int(tourn_room["match"]))
			joined_room.emit(room_code, my_slot)
			tourn_room_joined.emit(room_code, my_slot)
		"kicked":
			print("MPLOG kicked")
			leave_room()
			kicked_notice.emit()
			if not auto.is_empty():
				_auto_phase = "kicked"
				_auto_kicked_at = Time.get_ticks_msec()
		"room_closed":
			print("MPLOG room closed")
			leave_room()
			room_closed_notice.emit()
			if not auto.is_empty():
				_auto_phase = "kicked"
				_auto_kicked_at = Time.get_ticks_msec()
		"obs_snapshot_request":
			obs_snapshot_requested.emit()
		"obs_sync_pending":
			obs_needs_snapshot = true
			print("MPLOG observer sync pending (mid-match join)")
		"queue_joined":
			print("MPLOG queue joined mmr=", int(m.get("mmr", 0)),
					" rank=", String(m.get("rank", {}).get("rank_text", "")),
					" queue=", String(m.get("queue", "ranked")))
			queue_joined_notice.emit(int(m.get("mmr", 0)))
		"rank_result":
			last_rank_result = m
			print("MPLOG rank_result won=", bool(m.get("won", false)),
					" placement=", int(m.get("placement", 0)),
					" delta=", int(m.get("star_delta", 0)),
					" bonus=", bool(m.get("bonus", false)),
					" daily=", bool(m.get("daily_bonus", false)),
					" promoted=", bool(m.get("promoted", false)),
					" demoted=", bool(m.get("demoted", false)),
					" after=", String(m.get("after", {}).get("rank_text", "")),
					" mmr=", int(m.get("mmr_after", 0)))
			rank_result_received.emit(m)
			_sys_note("Đấu hạng kết thúc — hạng %d, biến động sao %+d." % [
				int(m.get("placement", 0)), int(m.get("star_delta", 0))])
		"queue_left":
			print("MPLOG queue left")
			queue_left_notice.emit()
		"queue_status":
			# 13z: the waiting screen's found-players readout.
			print("MPLOG queue status found=", int(m.get("found", 0)),
					"/", int(m.get("need", 8)),
					" queue=", String(m.get("queue", "")))
			queue_status_notice.emit(int(m.get("found", 0)),
					int(m.get("need", 8)), String(m.get("queue", "")))
		"match_found":
			room_code = String(m.get("code", ""))
			my_slot = int(m.get("slot", -1))
			ranked = bool(m.get("ranked", false))
			queued_room = true
			# Ranked rooms are referee-owned (nobody reports); in a
			# normal queue room slot 0 IS the host and reports the
			# result like a custom-room host.
			is_host = my_slot == 0 and not ranked
			ranked_opponent = m.get("opponent", {})
			print("MPLOG match found code=", room_code, " slot=", my_slot,
					" opponent=", String(ranked_opponent.get("user", "?")),
					" ommr=", int(ranked_opponent.get("mmr", 0)),
					" orank=", String(ranked_opponent.get("rank_text", "")),
					" ranked=", ranked)
			if auto.has("mp-ranked") or auto.has("mp-normal"):
				_auto_phase = "lobby"
			joined_room.emit(room_code, my_slot)
			match_found_notice.emit(room_code, my_slot, ranked_opponent)
		"referee_ok":
			print("MPLOG referee attached room=", String(m.get("code", "")))
		"match_start":
			in_match = true
			current_tick = 0
			last_rank_result = {}
			pending_cfg = {
				"seed": int(m.get("seed", 12345)),
				"biome": String(m.get("biome", "grassland")),
				"layout": String(m.get("layout", "plains")),
				"diplomacy": bool(m.get("diplomacy", false)),
				"players": m.get("players", []),
			}
			# Capture-harness only: --mp-seed pins the world seed on
			# BOTH auto clients (same value passed to each) so scout
			# routes are reproducible; normal play uses the server's.
			if auto.has("mp-seed"):
				pending_cfg["seed"] = int(auto["mp-seed"])
			match_started.emit(pending_cfg)
			if is_referee:
				call_deferred("begin_referee_match")
			_auto_on_match_started()
		"tick":
			current_tick = int(m.get("tick", current_tick))
			tick_received.emit(current_tick)
		"cmd":
			command_received.emit(int(m.get("from", -1)), int(m.get("tick", 0)),
					m.get("cmd", {}))
		"player_left":
			player_left.emit(int(m.get("slot", -1)))
		"desync":
			desync_notice.emit(int(m.get("tick", 0)))
		"chat":
			var cscope := String(m.get("scope", "match"))
			var cname := String(m.get("name", "?"))
			var ctext := String(m.get("text", ""))
			# 17b: the sender's alliance tag (server-resolved,
			# presentation only) rides every chat line.
			var ctag := String(m.get("ally_tag", ""))
			# 17d: the sender's equipped chat-bubble style
			# (server-resolved, presentation only).
			var cbub := String(m.get("bubble", "mac_dinh"))
			var cchamp := bool(m.get("war_champ", false))
			if cscope == "alliance":
				# 17a: keep a session transcript for the alliance
				# screen; the line still rides chat_received.
				alliance_chat_lines.append({"name": cname, "text": ctext, "tag": ctag, "bubble": cbub, "champ": cchamp})
				if alliance_chat_lines.size() > 100:
					alliance_chat_lines.pop_front()
				print("MPLOG alliance chat from=", cname, " text=", ctext)
			elif cscope == "world":
				# 17e: the world channel transcript.
				world_chat_lines.append({"name": cname, "text": ctext, "tag": ctag, "bubble": cbub, "champ": cchamp})
				if world_chat_lines.size() > 200:
					world_chat_lines.pop_front()
				print("MPLOG world chat from=", cname, " text=", ctext)
			elif cscope == "dm":
				_file_dm_line(m, cname, ctext, ctag, cbub, cchamp)
			if ctag != "":
				print("MPLOG chat ally_tag=", ctag, " scope=", cscope)
			chat_received.emit(cscope, int(m.get("from", -1)), cname, ctext, ctag, cbub)
			chat_line_received.emit(m)
		"voice":
			# 17e chat voice: one relayed WAV payload; the hub
			# files it into the channel's session transcript
			# (live only — the server stores no voice).
			var vwav := Marshalls.base64_to_raw(String(m.get("data", "")))
			_on_voice_msg(m, vwav)
			voice_line_received.emit(m, vwav)
			print("MPLOG voice scope=", String(m.get("scope", "")),
				" from=", String(m.get("name", "")), " bytes=", vwav.size())
		"marquee":
			# 17e Loa thông báo: dedupe by mid (a logged-in
			# room player is reached twice by construction).
			var mmid := int(m.get("mid", 0))
			if not _mq_seen.has(mmid):
				_mq_seen.append(mmid)
				if _mq_seen.size() > 32:
					_mq_seen.pop_front()
				var mdisp := _decor_name(String(m.get("name", "")),
					String(m.get("ally_tag", "")), bool(m.get("war_champ", false)))
				_show_marquee(mdisp, String(m.get("text", "")))
				marquee_received.emit(mdisp, String(m.get("text", "")))
				print("MPLOG marquee mid=", mmid, " from=", mdisp,
					" text=", String(m.get("text", "")))
		"megaphones":
			megaphone_count = int(m.get("count", 0))
			megaphones_changed.emit(megaphone_count)
			print("MPLOG megaphones count=", megaphone_count)
		"megaphone_granted":
			print("MPLOG megaphone granted user=", String(m.get("user", "")),
				" total=", int(m.get("count", 0)))
		"system_msg":
			_sys_note(String(m.get("text", "")))
			print("MPLOG system_msg text=", String(m.get("text", "")))
		"dm_list":
			dm_convs = m.get("rows", [])
			dm_unread.clear()
			for r in dm_convs:
				var ru := int(r.get("unread", 0))
				if ru > 0:
					dm_unread[String(r.get("user", ""))] = ru
			dm_list_received.emit(dm_convs)
			print("MPLOG dm_list rows=", dm_convs.size(), " unread=", dm_total_unread())
		"dm_thread":
			var dpeer := String(m.get("peer", ""))
			var drows: Array = m.get("rows", [])
			var conv: Array = []
			for r in drows:
				conv.append({"name": String(r.get("name", "")),
					"text": String(r.get("text", "")),
					"mine": String(r.get("from", "")) == account_name,
					"tag": "", "bubble": "mac_dinh", "champ": false})
			dm_threads[dpeer] = conv
			dm_unread.erase(dpeer)
			dm_thread_received.emit(dpeer, drows)
			print("MPLOG dm_thread peer=", dpeer, " rows=", drows.size())
		"auth_ok":
			auth_token = String(m.get("token", ""))
			auth_profile = m.get("profile", {})
			account_name = String(auth_profile.get("user", ""))
			mail_unread = int(auth_profile.get("unread_mail", 0))
			megaphone_count = int(auth_profile.get("megaphones", 0))
			dm_request_list()
			# Remember-me persistence follows the checkbox state at
			# auth time: on → store the token; off → drop any
			# stored one, so an old remembered session never
			# outlives a deliberate non-remembered login.
			if remember_session:
				_save_session_token(auth_token)
			else:
				clear_saved_session()
			# The account's stored avatar becomes the local pick
			# (17d catalogue — Avatars, not the hero registry);
			# cosmetic-skin ownership arrives with the profile too.
			if auth_profile.has("avatar_id"):
				Avatars.set_local_avatar(String(auth_profile.get("avatar_id", Avatars.DEFAULT_ID)))
			Characters.set_owned_skins(auth_profile.get("owned_skins", []))
			auth_ok.emit(auth_token, auth_profile)
		"avatar":
			# Server echo of the persisted avatar pick (set_avatar).
			var avatar_id := Avatars.normalize_id(String(m.get("avatar_id", Avatars.DEFAULT_ID)))
			auth_profile["avatar_id"] = avatar_id
			Avatars.set_local_avatar(avatar_id)
			avatar_changed.emit(avatar_id)
		"profile_update":
			# 17d: refreshed profile after a cosmetics equip or
			# a rename — surfaces re-render from it.
			auth_profile = m.get("profile", {})
			if auth_profile.has("avatar_id"):
				Avatars.set_local_avatar(String(auth_profile.get("avatar_id", Avatars.DEFAULT_ID)))
			print("MPLOG profile_update frame=", String(auth_profile.get("frame_id", "")),
				" bubble=", String(auth_profile.get("bubble_style", "")),
				" title=", String(auth_profile.get("display_title", "")))
			profile_updated.emit(auth_profile)
		"auth_error":
			auth_error.emit(String(m.get("msg", "Lỗi đăng nhập")))
		"display_name":
			var dn := String(m.get("display_name", ""))
			auth_profile["display_name"] = dn
			print("MPLOG display_name set=", dn)
			display_name_changed.emit(dn)
		"name_error":
			name_error.emit(String(m.get("msg", "Tên không hợp lệ")))
			# 17d: a cooldown rejection carries the next date.
			if m.has("rename_next_at"):
				rename_failed.emit(String(m.get("msg", "")), int(m.get("rename_next_at", 0)))
		"auth_out":
			auth_token = ""
			auth_profile = {}
			account_name = ""
			mail_unread = 0
			clear_saved_session()
			friends_rows = []
			mail_rows = []
			history_rows = []
			auth_out.emit()
		"pong":
			var ts := int(m.get("ts", 0))
			if ts > 0:
				ping_ms = maxi(0, Time.get_ticks_msec() - ts)
		"history":
			history_rows = m.get("rows", [])
			history_received.emit(history_rows)
		"friends":
			friends_rows = m.get("rows", [])
			friends_received.emit(friends_rows)
		"friend_error":
			friend_error.emit(String(m.get("msg", "Lỗi bạn bè")))
		"replay_data":
			replay_received.emit(m.get("replay", {}))
		"replay_error":
			replay_failed.emit(String(m.get("msg", "Không xem lại được")))
		"custom_replay", "match_replay":
			# match_replay (14a) is the queue-match twin of
			# custom_replay: the server hands every player of a
			# finished normal/ranked match the sealed replay id,
			# and Main treats both identically (result screen's
			# Xem lại button + history patch).
			print("MPLOG replay id received id=", String(m.get("replay_id", "")),
					" room=", String(m.get("room", "")))
			custom_replay_received.emit(String(m.get("replay_id", "")),
					String(m.get("room", "")))
		"mail":
			mail_rows = m.get("rows", [])
			mail_unread = int(m.get("unread", 0))
			mail_received.emit(mail_rows, mail_unread)
		"alliance_home":
			var mine_v = m.get("mine", null)
			alliance_mine = mine_v if mine_v is Dictionary else {}
			alliance_invites = m.get("invites", [])
			# 17b: seed the chat transcript from the server's
			# persisted history when this session has none yet
			# (a fresh login sees the last 50 lines; live lines
			# append after them).
			if not alliance_mine.is_empty() and alliance_chat_lines.is_empty():
				var mtag := String(alliance_mine.get("tag", ""))
				for cm in alliance_mine.get("chat", []):
					alliance_chat_lines.append({
						"name": String(cm.get("name", "?")),
						"text": String(cm.get("text", "")),
						"tag": mtag, "hist": true})
			print("MPLOG alliance home mine=", String(alliance_mine.get("name", "")),
					" role=", String(alliance_mine.get("my_role", "")),
					" members=", int(alliance_mine.get("members_count", 0)),
					" invites=", alliance_invites.size())
			alliance_home_received.emit(alliance_mine, alliance_invites)
			var anotice := String(alliance_mine.get("notice", ""))
			if anotice != "" and anotice != _last_ally_notice:
				_last_ally_notice = anotice
				_sys_note("Thông báo liên minh: " + anotice)
		"alliance_list":
			alliance_rows = m.get("rows", [])
			print("MPLOG alliance list rows=", alliance_rows.size())
			alliance_list_received.emit(alliance_rows)
		"leaderboard":
			leaderboard_mode = String(m.get("mode", "wl"))
			var me_v = m.get("me", {})
			leaderboard_me = me_v if me_v is Dictionary else {}
			leaderboard_received.emit(m.get("rows", []), leaderboard_mode, leaderboard_me)
		"resync":
			resync_started.emit(int(m.get("tick", 0)), int(m.get("source", -1)))
		"resync_notice":
			resync_notice_received.emit(m.get("slots", []))
		"snapshot_request":
			snapshot_requested.emit(int(m.get("tick", 0)))
		"snapshot":
			obs_needs_snapshot = false
			snapshot_received.emit(int(m.get("tick", 0)), m.get("state", {}))
		"resync_failed":
			resync_failed_notice.emit(int(m.get("tick", 0)))
		"error":
			lobby_error.emit(String(m.get("msg", "lỗi máy chủ")))


# ------------------------------------------------------------------ lobby API

## Creates a custom room. opts (15a, all optional): room_name,
## room_pass, public, allow_obs; (15b): diplomacy — see server
## RoomCreateOptions.
func create_room(player_name: String, biome: String, layout: String,
		opts: Dictionary = {}) -> void:
	ranked = false
	ranked_opponent = {}
	queued_room = false
	is_observer = false
	_send({"t": "create", "name": player_name, "biome": biome, "layout": layout,
			"room_name": String(opts.get("room_name", "")),
			"room_pass": String(opts.get("room_pass", "")),
			"public": bool(opts.get("public", false)),
			"allow_obs": bool(opts.get("allow_obs", false)),
			"diplomacy": bool(opts.get("diplomacy", false)),
			"obs_delay": int(opts.get("obs_delay", 0))})


func join_room(code: String, player_name: String, room_pass: String = "") -> void:
	ranked = false
	ranked_opponent = {}
	queued_room = false
	is_observer = false
	_send({"t": "join", "code": code.to_upper(), "name": player_name,
			"room_pass": room_pass})


## Watch-only attach to a custom room (15a): no slot is held;
## the server streams the room and rejects our commands.
func observe_room(code: String, player_name: String, room_pass: String = "") -> void:
	ranked = false
	ranked_opponent = {}
	queued_room = false
	_send({"t": "observe", "code": code.to_upper(), "name": player_name,
			"room_pass": room_pass})


## Room browser (15a): the answer lands on room_list_received.
func request_room_list() -> void:
	_send({"t": "list_rooms"})


## Tournaments (15h): every answer lands on tourn_list_received
## / tourn_detail_received; errors ride the shared error ->
## lobby_error channel. All require a logged-in account.
func tourn_request_list() -> void:
	_send({"t": "tourn_list"})


func tourn_create(name_: String, format: String, bracket: String, size: int) -> void:
	_send({"t": "tourn_create", "name": name_, "format": format,
			"bracket": bracket, "size": size})


func tourn_request_detail(id: String) -> void:
	_send({"t": "tourn_detail", "tourn_id": id})


## Alliances (17a): every mutation answers with a fresh
## alliance_home on alliance_home_received; the browser list
## lands on alliance_list_received; errors ride the shared
## error -> lobby_error channel. All require a logged-in
## account (guests are refused server-side).
func alliance_request_home() -> void:
	_send({"t": "alliance_home"})


func alliance_request_list(search: String) -> void:
	_send({"t": "alliance_list", "name": search})


func alliance_create(ally_name: String, tag: String, icon: int, color_idx: int, mode: String, desc: String) -> void:
	_send({"t": "alliance_create", "name": ally_name, "tag": tag,
			"badge_icon": icon, "badge_color": color_idx,
			"mode": mode, "desc": desc})


func alliance_apply(id: String, msg: String) -> void:
	_send({"t": "alliance_apply", "ally_id": id, "text": msg})


func alliance_cancel_request(id: String) -> void:
	_send({"t": "alliance_cancel_request", "ally_id": id})


func alliance_approve(id: String, user: String) -> void:
	_send({"t": "alliance_approve", "ally_id": id, "user": user})


func alliance_reject(id: String, user: String) -> void:
	_send({"t": "alliance_reject", "ally_id": id, "user": user})


func alliance_invite(id: String, player_name: String) -> void:
	_send({"t": "alliance_invite", "ally_id": id, "name": player_name})


func alliance_accept_invite(id: String) -> void:
	_send({"t": "alliance_accept_invite", "ally_id": id})


func alliance_decline_invite(id: String) -> void:
	_send({"t": "alliance_decline_invite", "ally_id": id})


func alliance_leave(id: String) -> void:
	_send({"t": "alliance_leave", "ally_id": id})


func alliance_kick(id: String, user: String) -> void:
	_send({"t": "alliance_kick", "ally_id": id, "user": user})


func alliance_role(id: String, user: String, role: String) -> void:
	_send({"t": "alliance_role", "ally_id": id, "user": user, "role": role})


func alliance_transfer(id: String, user: String) -> void:
	_send({"t": "alliance_transfer", "ally_id": id, "user": user})


func alliance_settings(id: String, tag: String, icon: int, color_idx: int, mode: String, desc: String) -> void:
	_send({"t": "alliance_settings", "ally_id": id, "tag": tag,
			"badge_icon": icon, "badge_color": color_idx,
			"mode": mode, "desc": desc})


func alliance_disband(id: String) -> void:
	_send({"t": "alliance_disband", "ally_id": id})


func alliance_chat(text: String) -> void:
	_send({"t": "alliance_chat", "text": text})

# ------------------------------------------------------------------
# 17e chat hub API: world channel, DM ops, voice relays, the
# megaphone, and the admin grant. All lobby traffic — the
# server validates login, rate limits, and permissions.

func world_chat(text: String) -> void:
	_send({"t": "world_chat", "text": text})


func world_voice(wav: PackedByteArray, dur: float) -> void:
	_send({"t": "world_voice", "audio": Marshalls.raw_to_base64(wav), "dur": dur})


func alliance_voice(wav: PackedByteArray, dur: float) -> void:
	_send({"t": "alliance_voice", "audio": Marshalls.raw_to_base64(wav), "dur": dur})


func dm_request_list() -> void:
	if account_name != "":
		_send({"t": "dm_list"})


func dm_open(peer: String) -> void:
	_send({"t": "dm_open", "peer": peer})


func dm_send(peer: String, text: String) -> void:
	_send({"t": "dm_send", "peer": peer, "text": text})


func dm_voice(peer: String, wav: PackedByteArray, dur: float) -> void:
	_send({"t": "dm_voice", "peer": peer, "audio": Marshalls.raw_to_base64(wav), "dur": dur})


func use_megaphone(text: String) -> void:
	_send({"t": "megaphone_use", "text": text})


func admin_grant_megaphone(user: String, count: int) -> void:
	_send({"t": "admin_grant_megaphone", "user": user, "count": count})


## Item grant op (17d rule change): kind is "frame" |
## "title" | "bubble"; item is the catalogue id. Admin-list
## accounts only — the server refuses everyone else.
func admin_grant_item(user: String, kind: String, item: String) -> void:
	_send({"t": "admin_grant_item", "user": user, "kind": kind, "item": item})


func dm_total_unread() -> int:
	var total := 0
	for k in dm_unread:
		total += int(dm_unread[k])
	return total


## _decor_name renders a chat sender with the standing
## presentation riders: [TAG] before, <Liên minh vô địch>
## after (spec §7.1; the suffix appears only while the
## sender holds the reign).
func _decor_name(sender_name: String, tag: String, champ: bool) -> String:
	var out := sender_name
	if tag != "":
		out = "[" + tag + "] " + out
	if champ:
		out += " <Liên minh vô địch>"
	return out


## _sys_note appends one REAL session event to the Hệ thống
## feed (server system pushes, ranked results, alliance
## notice changes — the panel also renders the mailbox).
func _sys_note(text: String) -> void:
	if text == "":
		return
	system_feed.append({"text": text, "at": int(Time.get_unix_time_from_system())})
	if system_feed.size() > 100:
		system_feed.pop_front()
	system_feed_changed.emit()


func _file_dm_line(m: Dictionary, cname: String, ctext: String,
		ctag: String, cbub: String, cchamp: bool) -> void:
	var peer := String(m.get("peer", ""))
	if peer == "":
		return
	var mine := String(m.get("from_user", "")) == account_name
	var lines: Array = dm_threads.get(peer, [])
	lines.append({"name": cname, "text": ctext, "tag": ctag,
		"bubble": cbub, "champ": cchamp, "mine": mine})
	if lines.size() > 200:
		lines.pop_front()
	dm_threads[peer] = lines
	if not mine:
		dm_unread[peer] = int(dm_unread.get(peer, 0)) + 1
	dm_line_received.emit(peer, mine)
	print("MPLOG dm from=", cname, " peer=", peer, " text=", ctext)


func _on_voice_msg(m: Dictionary, wav: PackedByteArray) -> void:
	var scope := String(m.get("scope", ""))
	var entry := {"name": String(m.get("name", "")),
		"tag": String(m.get("ally_tag", "")),
		"bubble": String(m.get("bubble", "mac_dinh")),
		"champ": bool(m.get("war_champ", false)),
		"voice": true, "dur": float(m.get("dur", 0.0)), "data": wav}
	match scope:
		"world":
			world_chat_lines.append(entry)
			if world_chat_lines.size() > 200:
				world_chat_lines.pop_front()
		"alliance":
			alliance_chat_lines.append(entry)
			if alliance_chat_lines.size() > 100:
				alliance_chat_lines.pop_front()
		"dm":
			var peer := String(m.get("peer", ""))
			if peer == "":
				return
			entry["mine"] = String(m.get("from_user", "")) == account_name
			var lines: Array = dm_threads.get(peer, [])
			lines.append(entry)
			if lines.size() > 200:
				lines.pop_front()
			dm_threads[peer] = lines
			if not bool(entry["mine"]):
				dm_unread[peer] = int(dm_unread.get(peer, 0)) + 1
			dm_line_received.emit(peer, bool(entry["mine"]))


# ------------------------------------------------------------------
# 17e megaphone marquee: a top-of-screen scrolling strip on
# its own layer (96 — above every panel), presentation only.
# Entries queue (max 3); each scrolls once at ~110 px/s and
# dismisses. Mid-scroll it never blocks input (strip is
# mouse-transparent).

const MARQUEE_SPEED := 110.0


func _ensure_marquee() -> void:
	if _mq_layer != null:
		return
	_mq_layer = CanvasLayer.new()
	_mq_layer.layer = 96
	add_child(_mq_layer)
	_mq_strip = PanelContainer.new()
	_mq_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_mq_strip.offset_bottom = 34
	_mq_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.12, 0.94)
	sb.border_color = Color(0.85, 0.68, 0.25)
	sb.set_border_width_all(0)
	sb.border_width_bottom = 2
	_mq_strip.add_theme_stylebox_override("panel", sb)
	_mq_clip = Control.new()
	_mq_clip.clip_contents = true
	_mq_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mq_strip.add_child(_mq_clip)
	_mq_label = Label.new()
	_mq_label.add_theme_font_size_override("font_size", 17)
	_mq_label.add_theme_color_override("font_color", Color(0.98, 0.90, 0.70))
	_mq_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mq_clip.add_child(_mq_label)
	_mq_layer.add_child(_mq_strip)
	_mq_strip.visible = false


func _show_marquee(sender_name: String, text: String) -> void:
	_ensure_marquee()
	var line := "[Loa] " + sender_name + ": " + text
	if _mq_active:
		if _mq_queue.size() < 3:
			_mq_queue.append(line)
		return
	_mq_start(line)


func _mq_start(line: String) -> void:
	_mq_label.text = line
	var vp_w := get_viewport().get_visible_rect().size.x
	_mq_text_w = ThemeDB.fallback_font.get_string_size(line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_mq_x = vp_w
	_mq_label.position = Vector2(_mq_x, 6)
	_mq_strip.visible = true
	_mq_active = true


func _marquee_tick(delta: float) -> void:
	if _mq_label == null:
		_mq_active = false
		return
	_mq_x -= MARQUEE_SPEED * delta
	_mq_label.position.x = _mq_x
	if _mq_x < -_mq_text_w:
		if _mq_queue.is_empty():
			_mq_active = false
			_mq_strip.visible = false
		else:
			_mq_start(String(_mq_queue.pop_front()))


## 17b: set the alliance notice board (leader/deputy). The
## server pushes a fresh alliance_home to every member.
func alliance_notice(id: String, text: String) -> void:
	_send({"t": "alliance_notice", "ally_id": id, "text": text})


## 17b: "[TAG] Name" composition for chat lines, friend rows
## and player panels. Presentation only — the bare name (and
## every sim value) is never touched.
static func ally_disp(pname: String, tag: String) -> String:
	return ("[%s] %s" % [tag, pname]) if tag != "" else pname


func tourn_register(id: String, partner: String = "") -> void:
	_send({"t": "tourn_register", "tourn_id": id, "partner": partner})


func tourn_unregister(id: String) -> void:
	_send({"t": "tourn_unregister", "tourn_id": id})


func tourn_start(id: String) -> void:
	_send({"t": "tourn_start", "tourn_id": id})


func tourn_cancel(id: String) -> void:
	_send({"t": "tourn_cancel", "tourn_id": id})


func tourn_checkin(id: String, match_id: int) -> void:
	_send({"t": "tourn_checkin", "tourn_id": id, "tourn_match": match_id})


func tourn_play(id: String, match_id: int) -> void:
	_send({"t": "tourn_play", "tourn_id": id, "tourn_match": match_id})


func tourn_dispute(id: String, match_id: int, replay_id: String) -> void:
	_send({"t": "tourn_dispute", "tourn_id": id, "tourn_match": match_id,
			"replay_id": replay_id})


func tourn_resolve(id: String, match_id: int, uphold: bool) -> void:
	_send({"t": "tourn_resolve", "tourn_id": id, "tourn_match": match_id,
			"uphold": uphold})


func tourn_walkover(id: String, match_id: int, side: int) -> void:
	_send({"t": "tourn_walkover", "tourn_id": id, "tourn_match": match_id,
			"side": side})


func tourn_reset_match(id: String, match_id: int) -> void:
	_send({"t": "tourn_reset", "tourn_id": id, "tourn_match": match_id})


## Host powers (15a, custom rooms): kick also bans the target
## from this room; transfer hands over the whole host role.
func kick_player(slot: int) -> void:
	_send({"t": "kick", "slot": slot})


## 15e: host power over observers — removes the named observer
## and bans their return to this room (server KickObserver).
func kick_observer(obs_name: String) -> void:
	_send({"t": "kick_obs", "name": obs_name})


func transfer_host(slot: int) -> void:
	_send({"t": "transfer_host", "slot": slot})


func set_ready(ready: bool) -> void:
	_send({"t": "ready", "ready": ready})


func set_config(biome: String, layout: String) -> void:
	set_config_full({"biome": biome, "layout": layout,
			"room_name": cfg_room_name, "public": cfg_public,
			"allow_obs": cfg_allow_obs, "diplomacy": cfg_diplomacy,
			"obs_delay": cfg_obs_delay})


## Full host config edit (15a): keys biome/layout/room_name/
## public/allow_obs (+15b diplomacy); set_pass=true + room_pass
## replaces the room password ("" clears it). Host-only, lobby
## phase (server-side).
func set_config_full(cfg: Dictionary) -> void:
	var msg := {"t": "config",
			"biome": String(cfg.get("biome", cfg_biome)),
			"layout": String(cfg.get("layout", cfg_layout)),
			"room_name": String(cfg.get("room_name", cfg_room_name)),
			"public": bool(cfg.get("public", cfg_public)),
			"allow_obs": bool(cfg.get("allow_obs", cfg_allow_obs)),
			"diplomacy": bool(cfg.get("diplomacy", cfg_diplomacy)),
			"obs_delay": int(cfg.get("obs_delay", cfg_obs_delay)),
			"set_pass": bool(cfg.get("set_pass", false)),
			"room_pass": String(cfg.get("room_pass", ""))}
	_send(msg)


func request_start() -> void:
	_send({"t": "start"})


func leave_room() -> void:
	_send({"t": "leave"})
	room_code = ""
	my_slot = -1
	in_match = false
	players = []
	ranked = false
	ranked_opponent = {}
	queued_room = false
	is_observer = false
	room_observers = []


# ------------------------------------------------------------------ match API

func send_command(cmd: Dictionary) -> void:
	if in_match:
		_send({"t": "cmd", "cmd": cmd})


func send_checksum(tick: int, hash_value: String) -> void:
	# Observers are not reporters: the server's checksum sets
	# count connected PLAYERS only (15a).
	if in_match and not is_observer:
		_send({"t": "checksum", "tick": tick, "hash": hash_value})


## Host -> server -> a mid-match observer waiting on its first
## snapshot (15a). Distinct from the resync "snapshot" message:
## that path is gated on an open resync cycle.
func send_obs_snapshot(tick: int, state: Dictionary) -> void:
	if in_match and not is_observer:
		_send({"t": "obs_snapshot", "tick": tick, "state": state})


## Observer -> server: "my match scene is bound and listening"
## (15a). Only after this does the server ask the host for the
## join snapshot, so the snapshot can never be lost in the boot.
func send_obs_ready() -> void:
	if is_observer:
		_send({"t": "obs_ready"})


# ------------------------------------------------------------------ chat / accounts / resync API

## Chat is pure relay — it is NEVER part of lockstep state.
## 15b: in a diplomacy room the "team" scope follows the sender's
## CURRENT alliances (sim state the relay cannot derive), so the
## caller passes its ally slots along; the server routes the line
## to exactly sender + allies. Empty allies = legacy routing.
func send_chat(scope: String, text: String, allies: Array = []) -> void:
	if room_code != "":
		var msg := {"t": "chat", "scope": scope, "text": text}
		if scope == "team" and not allies.is_empty():
			msg["allies"] = allies
		_send(msg)


func register_account(user: String, password: String) -> void:
	_send({"t": "register", "user": user, "pass": password})


func login_account(user: String, password: String) -> void:
	_send({"t": "login", "user": user, "pass": password})


func login_token(token: String) -> void:
	_send({"t": "login", "token": token})


func logout_account() -> void:
	_send({"t": "logout"})


## The label other players see (13r): the account's chosen
## display name when one is set, else the username. Guests get "".
func display_name() -> String:
	var dn := String(auth_profile.get("display_name", ""))
	return dn if dn != "" else account_name


## True once the account has picked its display name (13r).
func has_display_name() -> bool:
	return String(auth_profile.get("display_name", "")) != ""


## Ask the server to store this display name (name panel). The
## answer lands on display_name_changed / name_error.
func set_display_name(name: String) -> void:
	_send({"t": "set_name", "name": name})


# ------------------------------------------------- session persistence (13r)

func _save_session_token(token: String) -> void:
	if token == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("session", "token", token)
	cfg.save(SESSION_PATH)


## The remembered session token from a previous run ("" = none).
func saved_session_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) == OK:
		return String(cfg.get_value("session", "token", ""))
	return ""


func clear_saved_session() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)


## Profile avatar pick (17d catalogue — see Avatars): the pick
## lands locally first (guests keep it in the cfg); logged-in
## sessions also persist it on the account, and the server
## echoes the stored value in an "avatar" message.
func set_avatar(id: String) -> void:
	Avatars.set_local_avatar(id)
	if account_name != "":
		_send({"t": "set_avatar", "avatar": Avatars.normalize_id(id)})


## Display-name rename (17d): set_name's sibling WITH the
## 30-day cooldown. Success lands as profile_update +
## display_name; a cooldown rejection lands as name_error +
## rename_failed (with the next allowed date).
func rename(name: String) -> void:
	_send({"t": "rename", "name": name})


## Avatar-frame equip (17d): "" = no frame. Ownership is
## computed server-side; the answer is a profile_update.
func set_frame(id: String) -> void:
	_send({"t": "set_frame", "frame": id})


## Chat-bubble style equip (17d): same pattern.
func set_bubble(id: String) -> void:
	_send({"t": "set_bubble", "bubble": id})


## Display-title equip (17d): the title NAME ("" = clear).
func set_title(title_name: String) -> void:
	_send({"t": "set_title", "title": title_name})


func request_leaderboard(mode: String = "wl") -> void:
	_send({"t": "leaderboard", "mode": mode})


## Match history (home lobby "Lịch Sử"): the caller's last ranked
## results, newest first. Guests get an empty list.
func request_history() -> void:
	_send({"t": "history"})


## Friend list (home lobby "Bạn bè"): rows carry rank + presence.
func request_friends() -> void:
	_send({"t": "friends"})


func add_friend(user: String) -> void:
	_send({"t": "friend_add", "user": user})


func remove_friend(user: String) -> void:
	_send({"t": "friend_remove", "user": user})


## Flag/unflag a friend as "bạn thân" (close friend, 13m). The
## server replies with a fresh friends list carrying the flag.
func set_close_friend(user: String, close: bool) -> void:
	_send({"t": "friend_close", "user": user, "close": close})


## System mailbox (home lobby "Thư"): letters + unread count.
func request_mail() -> void:
	_send({"t": "mail"})


## Mark one letter read (id > 0) or the whole mailbox (id == 0);
## the server answers with a fresh "mail" payload.
func mark_mail_read(id: int = 0) -> void:
	_send({"t": "mail_read", "id": id})


## Ranked queue (P4 stage 3): 1v1 only this stage; the server
## rejects guests with a plain error the lobby displays.
func queue_join() -> void:
	_send({"t": "queue_join", "mode": "1v1"})


func queue_leave() -> void:
	_send({"t": "queue_leave"})


## Normal queue (13t): unranked 1v1 matchmaking — guests allowed,
## no MMR, no ladder effects. The server pairs FIFO and auto-starts
## the room on a countdown; slot 0 is the host and reports the
## result through the custom-room channel (W/L banking only).
## `name` is the guest display name (accounts resolve theirs
## server-side). Cancel reuses queue_leave — the server drops the
## session from whichever queue holds it.
func queue_join_normal(pname: String) -> void:
	_send({"t": "queue_join", "queue": "normal", "name": pname})


## Host-only: report the finished match's winning team so the
## server can bank W/L for account players (see server README for
## the trust model). Custom rooms only — ranked rooms are reported
## by their referee and the server ignores player reports there.
func report_match_result(winner_team: int, placements: Array = [],
		elim_ticks: Array = [], winner_slots: Array = []) -> void:
	var msg := {"t": "match_result", "winner_team": winner_team}
	# 15b: a diplomacy custom match ending in shared allied
	# victory reports the winner SET (checked before placements
	# server-side; custom rooms never send both).
	if not winner_slots.is_empty():
		msg["winner_slots"] = winner_slots
	# 13z: queued normal rooms report the full placement list
	# (slots 1st -> last); custom rooms keep the team report.
	if not placements.is_empty():
		msg["placements"] = placements
	# 14a: elimination ticks (slot-indexed, -1 = never fell) ride
	# along as the replay timeline's events sidecar.
	if not elim_ticks.is_empty():
		msg["elim_ticks"] = elim_ticks
	_send(msg)


## Referee-only: the authoritative ranked result (the server
## accepts this solely from the room's referee connection).
## ticks = the match's final lockstep tick, banked into the
## players' history records as the match duration. 13z: ranked
## queue matches also carry the full placement list plus the
## slots whose elimination was a disconnect (reputation).
func report_referee_result(winner_team: int, reason: String, ticks: int = 0,
		placements: Array = [], disconnect_slots: Array = [],
		elim_ticks: Array = [], scores: Array = []) -> void:
	var msg := {"t": "match_result", "winner_team": winner_team,
			"reason": reason, "referee": true, "ticks": ticks}
	if not placements.is_empty():
		msg["placements"] = placements
		msg["disconnect_slots"] = disconnect_slots
	# 14a: the referee's elimination ticks are the canonical
	# events sidecar for ranked replays.
	if not elim_ticks.is_empty():
		msg["elim_ticks"] = elim_ticks
	# 15h: per-slot match scores (index = slot) — only
	# tournament rooms consume them (league tie-breaks).
	if not scores.is_empty():
		msg["scores"] = scores
	_send(msg)


## Snapshot source -> server -> diverged clients (resync).
func send_snapshot(tick: int, state: Dictionary) -> void:
	if in_match:
		_send({"t": "snapshot", "tick": tick, "state": state})


## Hands the match config to Main (statics survive the scene reload;
## this autoload keeps the socket) and reloads into the match scene.
func begin_match() -> void:
	if pending_cfg.is_empty():
		return
	var ms = load("res://scripts/main.gd")
	ms.mp_config = pending_cfg.duplicate(true)
	ms.mp_active = true
	ms.mp_observer = is_observer # 15a: watch-only seat (no slot, full vision)
	ms.map_choice_done = true
	ms.chosen_biome = String(pending_cfg.get("biome", "grassland"))
	ms.chosen_layout = String(pending_cfg.get("layout", "plains"))
	if not auto.is_empty():
		ms.mp_debug_log = true
	var tree := get_tree()
	if tree.current_scene != null and tree.current_scene.scene_file_path == "res://main.tscn":
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file("res://main.tscn")


## Ask the relay for one recorded match (13h). The answer lands
## on replay_received / replay_failed.
func fetch_replay(id: String) -> void:
	_send({"t": "replay", "replay_id": id})


## Enters replay playback: same statics as a referee match (the
## sim runs with no local player) plus the replay flag — Main
## then feeds ticks + commands from replay_data locally instead
## of the network. seek_target > 0 starts fast-forwarded.
func begin_replay(rp: Dictionary, seek_target: int = 0) -> void:
	replay_data = rp
	replay_seek_target = seek_target
	var ms = load("res://scripts/main.gd")
	ms.mp_config = {
		"seed": int(rp.get("seed", 12345)),
		"biome": String(rp.get("biome", "grassland")),
		"layout": String(rp.get("layout", "plains")),
		"diplomacy": bool(rp.get("diplomacy", false)),
		"players": rp.get("players", []),
	}
	ms.mp_active = true
	ms.mp_observer = false
	ms.mp_referee = false
	ms.mp_replay = true
	ms.mp_replay_test = not auto.is_empty() and auto.has("mp-replay-fetch")
	ms.map_choice_done = true
	ms.chosen_biome = String(rp.get("biome", "grassland"))
	ms.chosen_layout = String(rp.get("layout", "plains"))
	if not auto.is_empty():
		ms.mp_debug_log = true
	var tree := get_tree()
	if tree.current_scene != null and tree.current_scene.scene_file_path == "res://main.tscn":
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file("res://main.tscn")


## Leaves replay playback back to the boot flow (home screen).
func leave_replay() -> void:
	replay_data = {}
	replay_seek_target = 0
	var ms = load("res://scripts/main.gd")
	ms.mp_active = false
	ms.mp_observer = false
	ms.mp_replay = false
	ms.mp_replay_test = false
	ms.map_choice_done = false
	get_tree().reload_current_scene()


## Referee twin of begin_match(): same statics, plus the referee
## flag — Main then runs the authoritative sim with no local player
## and reports the result itself.
func begin_referee_match() -> void:
	if pending_cfg.is_empty():
		return
	var ms = load("res://scripts/main.gd")
	ms.mp_config = pending_cfg.duplicate(true)
	ms.mp_active = true
	ms.mp_observer = false
	ms.mp_referee = true
	ms.mp_debug_log = true
	ms.map_choice_done = true
	ms.chosen_biome = String(pending_cfg.get("biome", "grassland"))
	ms.chosen_layout = String(pending_cfg.get("layout", "plains"))
	print("MPLOG referee booting match seed=", int(pending_cfg.get("seed", 0)))
	var tree := get_tree()
	if tree.current_scene != null and tree.current_scene.scene_file_path == "res://main.tscn":
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file("res://main.tscn")


# ------------------------------------------------------- auto smoke-test driver
## Drives: connect -> create/join -> (open lobby UI if a shot is
## wanted) -> ready -> host starts -> in match: slot 0 issues a move
## order at tick ~30; both clients arm a scripted TC kill of slot 1
## at tick 120 (Main performs it inside the sim at the tick boundary
## on every client); quit at tick ~175. All evidence is printed as
## MPLOG lines by Main/Net for tests/mp_smoke.sh to compare.

## 13r entry-flow capture/flow modes: Main's entry sequence owns
## the connection + routing; the driver only observes and pokes
## the real UI through Main's entry_* hooks.
func _entry_mode() -> bool:
	return auto.has("mp-shot-login") or auto.has("mp-shot-login-register") \
			or auto.has("mp-shot-login-notice") or auto.has("mp-test-cache") \
			or auto.has("mp-shot-loading") or auto.has("mp-shot-namepanel") \
			or auto.has("mp-shot-welcome") \
			or auto.has("mp-register-flow")


func _auto_on_connected() -> void:
	if _entry_mode():
		# Name-panel capture: register (or log in) the seeded
		# account; Main's entry routing shows the panel on auth_ok.
		if auto.has("mp-account") and not _auto_authed:
			var parts := String(auto["mp-account"]).split(":", true, 1)
			if parts.size() == 2:
				register_account(parts[0], parts[1])
		return
	if auto.is_empty() or _auto_phase == "lobby" or _auto_phase == "match" \
			or _auto_phase == "queue" or _auto_phase == "lbcheck" \
			or _auto_phase == "ranked-shot" or _auto_phase == "ranklb-shot" \
			or _auto_phase == "normal-shot" \
			or _auto_phase == "home-shot" or _auto_phase == "replay-fetch" \
			or _auto_phase == "tourn":
		return
	# Account flows register (or log in) BEFORE any room action; the
	# auth_ok handler flips _auto_authed and _auto_process re-enters.
	if auto.has("mp-account") and not _auto_authed:
		var parts := String(auto["mp-account"]).split(":", true, 1)
		if parts.size() == 2:
			register_account(parts[0], parts[1])
		return
	# Replay verification: fetch the recording, play it back.
	if auto.has("mp-replay-fetch"):
		_auto_phase = "replay-fetch"
		fetch_replay(String(auto["mp-replay-fetch"]))
		return
	# Home-lobby screenshot: no room at all — the home screen over
	# the boot scene is the whole subject.
	if auto.has("mp-shot-home") or auto.has("mp-shot-history") or auto.has("mp-shot-profile") \
			or auto.has("mp-shot-friends"):
		_auto_phase = "home-shot"
		return
	# 15a captures: lobby-only stills (create form / room
	# browser) — the client connects but takes NO room action;
	# _auto_process drives the lobby UI and the shot.
	if auto.has("mp-shot-create") or auto.has("mp-shot-browser"):
		_auto_phase = "lobby-shot"
		return
	# Ranked smoke flow: queue for matchmaking instead of a room.
	if auto.has("mp-ranked") and not _auto_ranked_queued:
		_auto_ranked_queued = true
		_auto_phase = "queue"
		queue_join()
		return
	# Normal-queue smoke flow (13t): unranked matchmaking — guests
	# queue with just a display name (no account needed).
	if auto.has("mp-normal") and not _auto_ranked_queued:
		_auto_ranked_queued = true
		_auto_phase = "queue"
		queue_join_normal(String(auto.get("mp-name", "Auto")))
		return
	# 15h tournament smoke driver: the state machine runs in
	# _auto_process; here we only arm it (after auth).
	if auto.has("mp-tourn"):
		_auto_phase = "tourn"
		_tourn_id = String(auto.get("mp-tourn-id", ""))
		return
	# Leaderboard probe: fetch the ranked board, print it, quit.
	if auto.has("mp-lbcheck"):
		_auto_phase = "lbcheck"
		if not _auto_lb_requested:
			_auto_lb_requested = true
			request_leaderboard("ranked")
		return
	# Ranked queue screenshot: the lobby UI drives this one.
	if auto.has("mp-shot-ranked"):
		_auto_phase = "ranked-shot"
		return
	# Normal queue screenshot (13t): the lobby UI drives this one.
	if auto.has("mp-shot-normal"):
		_auto_phase = "normal-shot"
		return
	# Rank leaderboard screenshot: the lobby UI drives this one too.
	if auto.has("mp-shot-ranklb"):
		_auto_phase = "ranklb-shot"
		return
	var pname := String(auto.get("mp-name", "Auto"))
	# 15a browse driver: list rooms first; _auto_process sequences
	# the wrong/right-password joins off the list payload.
	if String(auto.get("mp-auto", "")) == "browse":
		_auto_phase = "browse"
		_auto_browse_stage = 0
		_auto_browse_at = Time.get_ticks_msec()
		return
	# 15a observer driver: attach watch-only; the match streams
	# to us and the server must reject our scripted command.
	if String(auto.get("mp-auto", "")) == "observe":
		_auto_phase = "observing"
		observe_room(String(auto.get("mp-code", "")), pname,
				String(auto.get("mp-room-pass", "")))
		return
	_auto_phase = "lobby"
	if String(auto.get("mp-auto", "")) == "create" or auto.has("mp-shot-lobby") \
			or auto.has("mp-shot-account"):
		var biome := String(auto.get("mp-biome", "grassland"))
		var layout := String(auto.get("mp-layout", "plains"))
		create_room(pname, biome, layout, {
			"room_name": String(auto.get("mp-room-name", "")),
			"room_pass": String(auto.get("mp-room-pass", "")),
			"public": auto.has("mp-room-public"),
			"allow_obs": auto.has("mp-room-obs"),
			"diplomacy": auto.has("mp-diplomacy"),
			"obs_delay": int(auto.get("mp-room-delay", "0"))})
	else:
		join_room(String(auto.get("mp-code", "")), pname,
				String(auto.get("mp-room-pass", "")))


func _auto_on_match_started() -> void:
	if auto.is_empty():
		return
	_auto_phase = "starting"
	call_deferred("begin_match")


var _entry_stage: int = 0 # 13r entry driver progress
var _entry_stage_at: int = 0 # msec when the current stage began
var _entry_boot_at: int = 0 # msec when the entry driver first ticked


## 13r entry-flow driver: captures + the register→name→lobby
## flow check. Everything goes through Main's real entry UI.
func _auto_entry_process(cs) -> void:
	if _entry_boot_at == 0:
		_entry_boot_at = Time.get_ticks_msec()
		_entry_stage_at = _entry_boot_at
	var now := Time.get_ticks_msec()
	if now - _entry_boot_at > 40000:
		print("MPLOG entry driver TIMEOUT stage=", _entry_stage)
		get_tree().quit()
		return
	if cs == null or not cs.has_method("entry_state"):
		return
	var state := String(cs.entry_state())
	var wait = func(ms: int) -> bool:
		if now - _entry_stage_at >= ms:
			_entry_stage += 1
			_entry_stage_at = now
			return true
		return false
	if auto.has("mp-shot-loading"):
		if state == "loading" and _entry_stage == 0:
			var p := float(cs.entry_loading_progress())
			if p >= 0.5 and p < 0.99 and wait.call(700):
				# The world build blocks the main thread for
				# seconds: the last PRESENTED frame still shows
				# the previous step. Capture only after two
				# fresh frames have actually been drawn.
				_entry_stage = 99
				_shot_then_quit(String(auto["mp-shot-loading"]), p)
		return
	if auto.has("mp-test-cache"):
		if state == "login" and _entry_stage == 0:
			print("MPLOG cache ", cs.entry_debug_clear_cache())
			_entry_stage = 99
			get_tree().quit()
		return
	if auto.has("mp-shot-login-notice"):
		if state == "login" or state == "welcome":
			if _entry_stage == 0:
				cs.entry_open_notices()
				_entry_stage = 1
				_entry_stage_at = now
			elif wait.call(800):
				_save_shot(String(auto["mp-shot-login-notice"]))
				print("MPLOG login notice shot saved")
				get_tree().quit()
		return
	if auto.has("mp-shot-login") or auto.has("mp-shot-login-register"):
		if state == "login":
			if auto.has("mp-shot-login-register") and _entry_stage == 0:
				cs.entry_login_set_tab(true)
				_entry_stage = 1
				_entry_stage_at = now
			elif wait.call(800):
				var key := "mp-shot-login-register" if auto.has("mp-shot-login-register") else "mp-shot-login"
				_save_shot(String(auto[key]))
				print("MPLOG login shot saved")
				get_tree().quit()
		return
	if auto.has("mp-shot-namepanel"):
		if state == "name" and _entry_stage == 0 and wait.call(800):
			_save_shot(String(auto["mp-shot-namepanel"]))
			print("MPLOG namepanel shot saved")
			get_tree().quit()
		return
	if auto.has("mp-shot-welcome"):
		if state == "welcome" and _entry_stage == 0 and wait.call(800):
			_save_shot(String(auto["mp-shot-welcome"]))
			print("MPLOG welcome shot saved")
			get_tree().quit()
		return
	if auto.has("mp-register-flow"):
		var parts := String(auto["mp-register-flow"]).split(":", true, 1)
		if parts.size() != 2:
			print("MPLOG flow BAD ARG")
			get_tree().quit()
			return
		match _entry_stage:
			0:
				if state == "login":
					print("MPLOG flow submitting register user=", parts[0])
					cs.entry_debug_submit_register(parts[0], parts[1])
					_entry_stage = 1
					_entry_stage_at = now
			1:
				if state == "name":
					cs.entry_debug_name_dice()
					var nm := String(cs.entry_debug_name_text())
					print("MPLOG flow dice name=", nm)
					cs.entry_debug_name_confirm()
					_entry_stage = 2
					_entry_stage_at = now
				elif state == "home":
					print("MPLOG flow SKIP name panel (already named?)")
					_entry_stage = 3
					_entry_stage_at = now
			2:
				if state == "home":
					_entry_stage = 3
					_entry_stage_at = now
			3:
				if wait.call(900):
					print("MPLOG flow home name=", String(cs.entry_home_name_text()),
							" display=", display_name())
					print("MPLOG flow DONE")
					get_tree().quit()
		return


## 15a smoke choreography for the HOST client: optional kick /
## host-transfer / wait-for-observer steps that must complete
## BEFORE the host readies up (otherwise the match starts before
## the steps can happen). Returns true while a step is pending.
func _auto_pre_start_steps() -> bool:
	if not is_host or my_slot < 0:
		return false
	if not (auto.has("mp-kick-slot") or auto.has("mp-transfer-slot")
			or auto.has("mp-wait-obs")):
		return false
	if auto.has("mp-wait-obs") and room_observers.is_empty():
		return true
	if auto.has("mp-kick-slot") and not _auto_kick_done:
		var ks := int(auto["mp-kick-slot"])
		for p in players:
			if int(p.get("slot", -1)) == ks:
				kick_player(ks)
				_auto_kick_done = true
				print("MPLOG auto kicked slot=", ks)
				break
		return true
	if auto.has("mp-transfer-slot") and not _auto_transfer_done:
		transfer_host(int(auto["mp-transfer-slot"]))
		_auto_transfer_done = true
		print("MPLOG auto transferred host to slot=", int(auto["mp-transfer-slot"]))
		return true
	return false


func _auto_process() -> void:
	if auto.is_empty():
		return
	if _auto_boot_ms == 0:
		_auto_boot_ms = Time.get_ticks_msec()
	# 15e delay proof (observer drivers): stamp when the stream
	# goes live — in a delayed room match_start only lands after
	# the server's buffer releases it.
	if is_observer:
		var el := Time.get_ticks_msec() - _auto_boot_ms
		if not in_match and not _auto_obs_wait_printed and el >= 30000:
			_auto_obs_wait_printed = true
			print("MPLOG observer waiting ms=", el, " delay=", cfg_obs_delay)
		if in_match and not _auto_obs_live_printed:
			_auto_obs_live_printed = true
			print("MPLOG observer live ms=", el, " delay=", cfg_obs_delay)
	if _entry_mode():
		_auto_entry_process(get_tree().current_scene)
		return
	# Auto-connect once (the driver has no human to press Connect).
	if _auto_phase == "boot" and peer == null:
		_auto_phase = "connecting"
		connect_to_server(DEFAULT_URL)
	var cs = get_tree().current_scene
	# Account driver: once auth_ok landed, re-run the connect step
	# (it now proceeds to create/join with the account bound).
	if auto.has("mp-account") and _auto_authed and connected \
			and _auto_phase != "lobby" and _auto_phase != "match" \
			and _auto_phase != "starting":
		_auto_on_connected()
	# 15h tournament smoke driver + captures.
	if auto.has("mp-tourn") and _auto_authed:
		if _auto_tourn_process(cs):
			return
	if auto.has("mp-shot-tourn-list") and _auto_authed and not _auto_shot_done:
		_auto_tourn_shot(cs, false)
		return
	if auto.has("mp-shot-tourn-bracket") and _auto_authed and not _auto_shot_done:
		_auto_tourn_shot(cs, true)
		return
	# 17a alliance smoke driver + captures.
	if auto.has("mp-alliance") and _auto_authed:
		if _auto_alliance_process(cs):
			return
	if auto.has("mp-shot-alliance") and _auto_authed and not _auto_shot_done:
		_auto_alliance_shot(cs)
		return
	# 17b alliance-expansion smoke driver + captures.
	if auto.has("mp-alliance2") and _auto_authed:
		if _auto_alliance2_process(cs):
			return
	if auto.has("mp-shot-alliance2") and _auto_authed and not _auto_shot_done:
		_auto_alliance2_shot(cs)
		return
	# 17d settings smoke driver + captures.
	if auto.has("mp-settings") and _auto_authed:
		if _auto_settings_process(cs):
			return
	if auto.has("mp-shot-settings") and _auto_authed and not _auto_shot_done:
		_auto_settings_shot(cs)
		return
	# 17e chat-hub smoke driver + captures.
	if auto.has("mp-chathub") and _auto_authed:
		if _auto_chathub_process(cs):
			return
	if auto.has("mp-shot-chathub") and _auto_authed and not _auto_shot_done:
		_auto_chathub_shot(cs)
		return
	# Home-lobby screenshot: once authed, give the home screen a
	# beat to fill the profile chip from the auth payload, then
	# shoot and quit.
	# Profile capture (13l): open the profile screen once the
	# seeded account is in, then save.
	if auto.has("mp-shot-profile") and _auto_authed and not _auto_shot_done:
		var cs2 := get_tree().current_scene
		if _auto_home_at == 0:
			_auto_home_at = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _auto_home_at > 1100 and not _auto_lb_requested:
			_auto_lb_requested = true
			if cs2 != null and cs2.has_method("open_profile_shot"):
				cs2.open_profile_shot()
		elif _auto_lb_requested and Time.get_ticks_msec() - _auto_home_at > 2200:
			_auto_shot_done = true
			_save_shot(String(auto["mp-shot-profile"]))
			print("MPLOG profile shot saved")
			get_tree().quit()
		return
	# 15a captures: open the lobby; the create shot photographs
	# the menu view (with the new room options), the browser
	# shot opens the room browser and waits for the list.
	if auto.has("mp-shot-create") and connected and not _auto_shot_done:
		if cs != null and cs.has_method("open_lobby") and not _auto_lobby_opened:
			_auto_lobby_opened = true
			_auto_home_at = Time.get_ticks_msec()
			cs.open_lobby()
		elif _auto_lobby_opened and Time.get_ticks_msec() - _auto_home_at > 1400:
			_auto_shot_done = true
			_save_shot(String(auto["mp-shot-create"]))
			print("MPLOG create shot saved")
			get_tree().quit()
		return
	# 15e capture: same create form, but the spectator-delay
	# selector is set to 60 giây before the shot.
	if auto.has("mp-shot-create-delay") and connected and not _auto_shot_done:
		if cs != null and cs.has_method("open_lobby") and not _auto_lobby_opened:
			_auto_lobby_opened = true
			_auto_home_at = Time.get_ticks_msec()
			cs.open_lobby()
		elif _auto_lobby_opened and Time.get_ticks_msec() - _auto_home_at > 1400:
			_auto_shot_done = true
			var dlb = cs.get("lobby")
			if dlb != null and dlb.has_method("set_delay_for_test"):
				dlb.set_delay_for_test(1)
			await get_tree().create_timer(0.5).timeout
			_save_shot(String(auto["mp-shot-create-delay"]))
			print("MPLOG create delay shot saved")
			get_tree().quit()
		return
	if auto.has("mp-shot-browser") and connected and not _auto_shot_done:
		if cs != null and cs.has_method("open_lobby") and not _auto_lobby_opened:
			_auto_lobby_opened = true
			_auto_home_at = Time.get_ticks_msec()
			cs.open_lobby()
		elif _auto_lobby_opened:
			var blb = cs.get("lobby")
			if blb != null and blb.has_method("show_browser_for_test"):
				if not _auto_lb_requested:
					_auto_lb_requested = true
					blb.show_browser_for_test()
				elif not room_list_rows.is_empty() \
						or Time.get_ticks_msec() - _auto_home_at > 7000:
					_auto_shot_done = true
					await get_tree().create_timer(0.8).timeout
					_save_shot(String(auto["mp-shot-browser"]))
					print("MPLOG browser shot saved")
					get_tree().quit()
		return
	if auto.has("mp-shot-home") and _auto_authed and not _auto_shot_done:
		if _auto_home_at == 0:
			_auto_home_at = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _auto_home_at > 1200:
			_auto_shot_done = true
			if cs != null and cs.has_method("refresh_home"):
				cs.refresh_home()
			_save_shot(String(auto["mp-shot-home"]))
			print("MPLOG home shot saved")
			get_tree().quit()
	# History-panel screenshot: same login, then open the panel,
	# let the server history land, shoot, quit.
	if auto.has("mp-shot-history") and _auto_authed and not _auto_shot_done:
		if _auto_home_at == 0:
			_auto_home_at = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _auto_home_at > 1100 and not _auto_lb_requested:
			_auto_lb_requested = true
			if cs != null and cs.has_method("open_history_shot"):
				cs.open_history_shot()
		elif _auto_lb_requested and Time.get_ticks_msec() - _auto_home_at > 2200:
			_auto_shot_done = true
			_save_shot(String(auto["mp-shot-history"]))
			print("MPLOG history shot saved")
			get_tree().quit()
	# Friends-panel screenshot (13m): same login, then open the
	# panel on the requested tab (--mp-friends-tab, default
	# "all"), let the friends payload land, shoot, quit.
	if auto.has("mp-shot-friends") and _auto_authed and not _auto_shot_done:
		if _auto_home_at == 0:
			_auto_home_at = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _auto_home_at > 1100 and not _auto_lb_requested:
			_auto_lb_requested = true
			if cs != null and cs.has_method("open_friends_shot"):
				cs.open_friends_shot(String(auto.get("mp-friends-tab", "all")))
		elif _auto_lb_requested and Time.get_ticks_msec() - _auto_home_at > 2400:
			_auto_shot_done = true
			_save_shot(String(auto["mp-shot-friends"]))
			print("MPLOG friends shot saved")
			get_tree().quit()
	# Open the lobby UI over the boot scene when a lobby shot is due.
	if auto.has("mp-shot-lobby") and not _auto_lobby_opened:
		if cs != null and cs.has_method("open_lobby") and room_code != "":
			_auto_lobby_opened = true
			cs.open_lobby()
	# Lobby shot: two players present and we are the host. Wait a
	# beat first — the room broadcast updates Net.players in the
	# same frame, but the lobby list needs a rendered frame to show
	# the second row (a same-frame capture shows stale UI).
	if auto.has("mp-shot-lobby") and _auto_lobby_opened and not _auto_shot_done:
		if is_host and players.size() >= 2:
			_auto_shot_done = true
			await get_tree().create_timer(0.5).timeout
			_save_shot(String(auto["mp-shot-lobby"]))
			print("MPLOG lobby shot saved")
			get_tree().quit()
	# 15a browse driver: list -> print rows -> join with the WRONG
	# password (the error line is the evidence) -> join with the
	# right one -> fall into the normal lobby flow as a player.
	if _auto_phase == "browse":
		var now_b := Time.get_ticks_msec()
		match _auto_browse_stage:
			0:
				request_room_list()
				_auto_browse_stage = 1
				_auto_browse_at = now_b
			1:
				if _auto_browse_got_list:
					for row in room_list_rows:
						print("MPLOG roomlist code=", String(row.get("code", "")),
								" name=", String(row.get("name", "")),
								" host=", String(row.get("host", "")),
								" players=", int(row.get("players", 0)),
								" pass=", int(bool(row.get("has_password", false))),
								" obs=", int(bool(row.get("allow_obs", false))))
					join_room(String(auto.get("mp-code", "")),
							String(auto.get("mp-name", "Auto")),
							String(auto.get("mp-wrong-pass", "")))
					_auto_browse_stage = 2
					_auto_browse_at = now_b
				elif now_b - _auto_browse_at > 15000:
					print("MPLOG browse TIMEOUT waiting for room list")
					get_tree().quit()
			2:
				if now_b - _auto_browse_at > 1500:
					join_room(String(auto.get("mp-code", "")),
							String(auto.get("mp-name", "Auto")),
							String(auto.get("mp-room-pass", "")))
					_auto_browse_stage = 3
					_auto_browse_at = now_b
			3:
				if room_code != "":
					_auto_phase = "lobby"
				elif now_b - _auto_browse_at > 15000:
					print("MPLOG browse TIMEOUT joining")
					get_tree().quit()
	# Kicked / room-closed driver clients exit shortly after.
	if _auto_phase == "kicked" and Time.get_ticks_msec() - _auto_kicked_at > 800:
		print("MPLOG auto done (kicked/closed) slot=", my_slot)
		get_tree().quit()
	# Scout shot flow: same lobby behaviour as a normal auto client.
	if _auto_phase == "lobby" and room_code != "" and not in_match:
		if not _auto_pre_start_steps():
			set_ready(true)
			# --mp-min-players=N: the host waits for N seats before
			# starting (3+ player custom smokes; default 2 as ever).
			var need := maxi(2, int(auto.get("mp-min-players", "2")))
			if is_host and players.size() >= need and not auto.has("mp-shot-lobby") \
					and not auto.has("mp-shot-account"):
				var all_ready := true
				for p in players:
					if not bool(p.get("ready", false)):
						all_ready = false
				if all_ready:
					request_start()
	# Account-lobby shot: logged-in host, second player present,
	# leaderboard fetched and opened, then capture.
	if auto.has("mp-shot-account"):
		if cs != null and cs.has_method("open_lobby") and room_code != "" \
				and not _auto_lobby_opened:
			_auto_lobby_opened = true
			cs.open_lobby()
		if _auto_lobby_opened and not _auto_shot_done and players.size() >= 2 \
				and account_name != "":
			if not _auto_lb_requested:
				_auto_lb_requested = true
				request_leaderboard()
			elif _auto_lb_received:
				var lb = cs.get("lobby") if cs != null else null
				if lb != null and lb.has_method("open_leaderboard"):
					_auto_shot_done = true
					lb.open_leaderboard()
					await get_tree().create_timer(1.2).timeout
					print("MPLOG lb open before shot=", lb.is_leaderboard_open())
					_save_shot(String(auto["mp-shot-account"]))
					print("MPLOG account shot saved")
					get_tree().quit()
	# Ranked leaderboard probe: dump the board as MPLOG lines.
	if auto.has("mp-lbcheck") and _auto_lb_received and not _auto_shot_done:
		_auto_shot_done = true
		for row in _auto_lb_rows:
			print("MPLOG lb row user=", String(row.get("user", "")),
					" mmr=", int(row.get("mmr", 0)),
					" wins=", int(row.get("wins", 0)),
					" losses=", int(row.get("losses", 0)),
					" rank=", String(row.get("rank_text", "")),
					" emperor=", bool(row.get("emperor", false)))
		print("MPLOG lb done mode=", leaderboard_mode)
		get_tree().quit()
	# Ranked queue screenshot (13p matchmaking screen): log in,
	# open the lobby, press the ranked button, seed the wait
	# clock to ~28 s (the reference state), capture it.
	if auto.has("mp-shot-ranked"):
		if cs != null and cs.has_method("open_lobby") and connected \
				and account_name != "" and not _auto_lobby_opened:
			_auto_lobby_opened = true
			cs.open_lobby()
		if _auto_lobby_opened and not _auto_shot_done and cs != null:
			var rlb = cs.get("lobby")
			if rlb != null and rlb.has_method("press_ranked_for_test"):
				if not _auto_ranked_queued:
					_auto_ranked_queued = true
					rlb.press_ranked_for_test()
				elif rlb.is_queue_open():
					_auto_shot_done = true
					if not _auto_mm_seeded:
						_auto_mm_seeded = true
						if rlb.has_method("set_queue_elapsed_for_test"):
							rlb.set_queue_elapsed_for_test(28.0)
					await get_tree().create_timer(0.8).timeout
					_save_shot(String(auto["mp-shot-ranked"]))
					print("MPLOG ranked queue shot saved")
					get_tree().quit()
	# Normal-queue screenshot (13t): same painted matchmaking
	# screen as ranked, but the driver queues as a GUEST through
	# the lobby's normal button (guests are allowed here) and
	# seeds the wait clock to ~12 s. A single client never pairs,
	# so the queue view holds.
	if auto.has("mp-shot-normal"):
		if cs != null and cs.has_method("open_lobby") and connected \
				and not _auto_lobby_opened:
			_auto_lobby_opened = true
			cs.open_lobby()
		if _auto_lobby_opened and not _auto_shot_done and cs != null:
			var nlb = cs.get("lobby")
			if nlb != null and nlb.has_method("press_normal_for_test"):
				if not _auto_ranked_queued:
					_auto_ranked_queued = true
					nlb.press_normal_for_test()
				elif nlb.is_queue_open():
					_auto_shot_done = true
					if not _auto_mm_seeded:
						_auto_mm_seeded = true
						if nlb.has_method("set_queue_elapsed_for_test"):
							nlb.set_queue_elapsed_for_test(12.0)
					await get_tree().create_timer(0.8).timeout
					_save_shot(String(auto["mp-shot-normal"]))
					print("MPLOG normal queue shot saved")
					get_tree().quit()
	# Matchmaking cancel screenshot (13p): queue, cancel through
	# the screen button's own handler (server answers
	# queue_left -> "MPLOG queue left"), capture the lobby menu
	# the player lands back on.
	if auto.has("mp-shot-mm-cancel"):
		if cs != null and cs.has_method("open_lobby") and connected \
				and account_name != "" and not _auto_lobby_opened:
			_auto_lobby_opened = true
			cs.open_lobby()
		if _auto_lobby_opened and not _auto_shot_done and cs != null:
			var clb = cs.get("lobby")
			if clb != null and clb.has_method("press_ranked_for_test"):
				if not _auto_ranked_queued:
					_auto_ranked_queued = true
					clb.press_ranked_for_test()
				elif _auto_cancel_phase == 0 and clb.is_queue_open():
					_auto_cancel_phase = 1
					clb.cancel_queue_for_test()
				elif _auto_cancel_phase == 1 and not clb.is_queue_open():
					_auto_shot_done = true
					await get_tree().create_timer(0.8).timeout
					_save_shot(String(auto["mp-shot-mm-cancel"]))
					print("MPLOG mm cancel shot saved")
					get_tree().quit()
	# Rank leaderboard shot: log in, open the lobby, fetch the
	# ranked board, open it (header shows the viewer's own badge),
	# capture.
	if auto.has("mp-shot-ranklb"):
		if cs != null and cs.has_method("open_lobby") and connected \
				and account_name != "" and not _auto_lobby_opened:
			_auto_lobby_opened = true
			cs.open_lobby()
		if _auto_lobby_opened and not _auto_shot_done and cs != null:
			var rlb2 = cs.get("lobby")
			if rlb2 != null and rlb2.has_method("open_ranked_leaderboard"):
				if not _auto_lb_requested:
					_auto_lb_requested = true
					request_leaderboard("ranked")
				elif _auto_lb_received:
					_auto_shot_done = true
					rlb2.open_ranked_leaderboard()
					await get_tree().create_timer(1.2).timeout
					_save_shot(String(auto["mp-shot-ranklb"]))
					print("MPLOG ranklb shot saved")
					get_tree().quit()
	# Chat shot: the host greets early; the peer answers once the
	# greeting lands (see the chat_received hook in _ready); the
	# host opens the chat panel a few real seconds later and
	# captures it. Real-time spacing keeps the message order and
	# the shot correct even when a windowed client renders slowly.
	if (auto.has("mp-chat-shot") or auto.has("mp-chat-peer")) \
			and _auto_phase == "match" and cs != null:
		if my_slot == 0 and current_tick >= 6 and not _auto_chat_sent:
			_auto_chat_sent = true
			_auto_chat_at = Time.get_ticks_msec()
			send_chat("match", "Xin chào! Lên đánh thôi.")
		if auto.has("mp-chat-peer") and _auto_chat_reply_due > 0 \
				and not _auto_chat_sent \
				and Time.get_ticks_msec() >= _auto_chat_reply_due:
			_auto_chat_sent = true
			send_chat("match", "Ok, tôi theo ngay!")
		if auto.has("mp-chat-shot") and my_slot == 0 and _auto_chat_sent \
				and not _auto_shot_done \
				and Time.get_ticks_msec() >= _auto_chat_at + 3500:
			_auto_shot_done = true
			if cs.get("hud") != null:
				cs.hud.open_chat()
			await get_tree().create_timer(0.6).timeout
			_save_shot(String(auto["mp-chat-shot"]))
			print("MPLOG chat shot saved")
			get_tree().quit()
	# 15b diplomacy capture hooks (windowed clients in a live
	# diplomacy match): the panel shot fires while the host's
	# invite is still pending on this client — so this client
	# runs WITHOUT --mp-dip and never accepts; the panel shows
	# the incoming proposal with its accept/decline buttons. The
	# vision shot fires once this client's fog has unioned with
	# the host's (it runs WITH --mp-dip and accepts): camera on
	# the host's Town Center, revealed by the ally's own sight.
	if auto.has("mp-dip-shot-panel") and _auto_phase == "match" \
			and cs != null and bool(cs.get("mp_mode")) \
			and not _auto_shot_done:
		if cs.dip_invite_from(0, my_slot) >= 0 and cs.get("hud") != null:
			_auto_shot_done = true
			cs.hud.toggle_tab("diplomacy")
			await get_tree().create_timer(0.8).timeout
			_save_shot(String(auto["mp-dip-shot-panel"]))
			print("MPLOG dip panel shot saved")
			get_tree().quit()
	if auto.has("mp-dip-shot-vision") and _auto_phase == "match" \
			and cs != null and bool(cs.get("mp_mode")) \
			and not _auto_shot_done:
		if cs.dip_vision_shared(my_slot, 0) and cs.fog != null:
			var atc = cs.tc_of(0)
			if atc != null:
				var cc: Vector2i = atc.origin_cell + Vector2i(1, 1)
				if cs.fog.cell_state(cc) == 2:
					_auto_shot_done = true
					cs.cam.focus_on(atc.position + Vector2(48, 48))
					await get_tree().create_timer(0.8).timeout
					_save_shot(String(auto["mp-dip-shot-vision"]))
					print("MPLOG dip vision shot saved")
					get_tree().quit()
	# Host-perspective variant of the vision shot: the WINDOWED
	# client is the host (slot 0) and the guest is headless — a
	# windowed guest falls too far behind the server's tick pace
	# on this machine for its fog to union in time, while the
	# host only needs the first ~60 ticks. Fires once the host's
	# fog reveals the GUEST's Town Center through shared vision.
	if auto.has("mp-dip-shot-vision-host") and _auto_phase == "match" \
			and cs != null and bool(cs.get("mp_mode")) \
			and not _auto_shot_done:
		if cs.dip_vision_shared(my_slot, 1) and cs.fog != null:
			var btc = cs.tc_of(1)
			if btc != null:
				var cc2: Vector2i = btc.origin_cell + Vector2i(1, 1)
				if cs.fog.cell_state(cc2) == 2:
					_auto_shot_done = true
					cs.cam.focus_on(btc.position + Vector2(48, 48))
					await get_tree().create_timer(0.8).timeout
					_save_shot(String(auto["mp-dip-shot-vision-host"]))
					print("MPLOG dip vision host shot saved")
					get_tree().quit()
	# 15c capture hooks: the skill cluster (raised, with name
	# labels) and the press-and-hold info card. The hold is a
	# REAL injected mouse press at the button's centre (window
	# coordinates derived from the viewport transform), so the
	# whole input path — catcher, 0.4 s threshold, release
	# dismissal, no cast — is exercised, not just the visuals.
	if auto.has("mp-skill-shot") and _auto_phase == "match" \
			and cs != null and bool(cs.get("mp_mode")) \
			and not _auto_shot_done:
		var lh = cs.local_hero()
		if lh != null:
			_auto_shot_done = true
			cs.cam.focus_on(lh.global_position)
			await get_tree().create_timer(1.0).timeout
			_save_shot(String(auto["mp-skill-shot"]))
			print("MPLOG skill cluster shot saved")
			get_tree().quit()
	if auto.has("mp-skill-hold-shot") and _auto_phase == "match" \
			and cs != null and bool(cs.get("mp_mode")):
		_skill_hold_capture(cs)
	# Resync smoke hook: slot 1 quietly nudges one of its own idle
	# villagers +1px at tick 60 — its checksum at tick 60 must then
	# diverge, the server opens a resync cycle, and this client
	# rebuilds from the host's snapshot.
	if auto.has("mp-corrupt") and not _auto_corrupted and my_slot == 1 \
			and current_tick >= 60 and cs != null and bool(cs.get("mp_mode")):
		for cand in cs.units:
			if int(cand.owner_id) == my_slot and not cand.is_dead():
				cand.global_position.x += 1.0
				_auto_corrupted = true
				print("MPLOG corrupted slot=1 at client tick ", current_tick)
				break
	# In-match scripted actions.
	if _auto_phase == "starting":
		if cs != null and bool(cs.get("mp_built")):
			_auto_phase = "match"
			_auto_started_ticks = current_tick
			# Arm the deterministic TC-kill hook inside Main's sim
			# (smoke runs only — a scout capture must not end early,
			# and --mp-nokill suppresses it explicitly).
			if (auto.has("mp-auto") or auto.has("mp-normal")) \
					and not auto.has("mp-nokill") and not ranked:
				if auto.has("mp-normal"):
					# 13z: a normal-queue match seats 8 — the match
					# only ends when slots 1..7 have all fallen.
					# Identical on every client (it runs inside the
					# shared sim), so all eight agree on placements.
					for k in range(1, 8):
						cs.mp_test_kills.append([120 + (k - 1) * 15, k])
				else:
					cs.mp_test_kill_tick = 120
					cs.mp_test_kill_slot = 1
			# Skill smoke: heroes materialise mid-map (Main hook).
			if auto.has("mp-hero-test"):
				cs.mp_test_hero = true
			# 15g transport smoke: the trade kit materialises
			# per slot inside the sim (Main hook).
			if auto.has("mp-transport"):
				cs.mp_test_transport = true
			# 14c hero smoke: force both slots' characters so the
			# new kits run over lockstep deterministically — every
			# client applies the SAME override from the same flag,
			# so the sims still agree (chars are presentation
			# metadata; only their effects are sim).
			if auto.has("mp-hero-chars"):
				var parts := String(auto["mp-hero-chars"]).split(",")
				for i in range(mini(parts.size(), cs.slot_chars.size())):
					cs.slot_chars[i] = parts[i]
				print("MPLOG hero chars forced ", parts)
			print("MPLOG auto in match slot=", my_slot)
	if _auto_phase == "match" and cs != null and bool(cs.get("mp_mode")):
		if not _auto_issued and my_slot == 0 and current_tick >= 30 \
				and not auto.has("mp-scout-shot") and not auto.has("mp-dip") \
				and not auto.has("mp-transport"):
			_auto_issued = true
			_auto_issue_move(cs)
		# 15a observer driver: fire one raw command at the relay —
		# the server must reject it (error line) and the sim must
		# NOT diverge (our checksums keep matching the players').
		if is_observer and not _auto_obs_cmd_tried and current_tick >= 40:
			_auto_obs_cmd_tried = true
			send_command({"kind": "order", "units": [], "x": 0, "y": 0})
			print("MPLOG observer cmd sent tick=", current_tick)
		# 15e: slot 1 marches its scout cavalry to the map centre
		# (spectator smoke: gives the follow camera a moving
		# target once slot 1's TC falls to the scripted kill).
		if auto.has("mp-spec-scout-move") and my_slot == 1 \
				and not _auto_spec_scout_moved and current_tick >= 40:
			_auto_spec_scout_moved = true
			_auto_spec_move_scout(cs)
		if auto.has("mp-spec-scout-move") and my_slot == 1 \
				and current_tick % 30 == 0 and current_tick != _auto_spec_last_print:
			_auto_spec_last_print = current_tick
			for cand in cs.units:
				if int(cand.owner_id) == 1 and cand.unit_type == "cavalry" \
						and not cand.is_dead():
					print("MPLOG spec scout pos=", cand.global_position,
							" tick=", current_tick)
					break
		# 15e spectator driver: engage follow/auto on the
		# observer's spectator controller and report its state.
		if is_observer and (auto.has("mp-spec-follow") or auto.has("mp-spec-auto") \
				or auto.has("mp-spec-shot-bar") or auto.has("mp-spec-shot-panel")):
			_auto_spec_observer(cs)
		if auto.has("mp-hero-test"):
			_auto_hero_actions(cs)
		if auto.has("mp-transport"):
			_auto_transport_actions(cs, current_tick)
		if auto.has("mp-dip"):
			_auto_dip_actions(cs, current_tick)
		if auto.has("mp-scout-shot") and not _auto_shot_done:
			_auto_scout(cs)
		if current_tick >= int(auto.get("mp-hold", "175")) and not auto.has("mp-scout-shot"):
			print("MPLOG auto done slot=", my_slot)
			get_tree().quit()


## 15h tournament smoke driver: create/join a solo
## single-elim, register, check in, launch each playable
## match, leave when it ends, and loop until the tournament
## finishes — then print the champion every client agrees on
## (read from the same server-rendered detail payload).
## Returns true when it consumed the frame (not in a match).
func _auto_tourn_process(cs) -> bool:
	if _auto_phase == "starting":
		return false
	if _auto_phase == "match":
		# Match over -> leave the room, reload to the home-mode
		# scene and resume the tournament loop.
		if cs != null and bool(cs.get("mp_over")):
			print("MPLOG tourn match over, leaving room")
			leave_room()
			tourn_room = {}
			_auto_phase = "tourn"
			_tourn_next_poll = 0
			get_tree().reload_current_scene()
			return false
		# The referee's result is canonical: if the server has
		# already banked our current match (its finish can be
		# referee-side only, e.g. a scripted test kill the local
		# sim never sees), leave the decided room and resume the
		# tournament loop instead of idling in it forever.
		var now2 := Time.get_ticks_msec()
		if _tourn_id != "" and not tourn_room.is_empty() \
				and now2 >= _tourn_next_poll:
			_tourn_next_poll = now2 + 2000
			tourn_request_detail(_tourn_id)
			var mid2 := int(tourn_room.get("match", 0))
			if mid2 > 0 and String(tourn_detail.get("id", "")) == _tourn_id:
				for m in (tourn_detail.get("matches", []) as Array):
					if int(m.get("id", 0)) == mid2:
						var st2 := String(m.get("state", ""))
						if st2 == "done" or st2 == "disputed":
							print("MPLOG tourn match banked by server, leaving room")
							leave_room()
							tourn_room = {}
							_auto_phase = "tourn"
							_tourn_next_poll = 0
							get_tree().reload_current_scene()
						break
		return false
	if _auto_phase != "tourn":
		return false
	var now := Time.get_ticks_msec()
	if now < _tourn_next_poll:
		return true
	_tourn_next_poll = now + 700
	# Drop a stale local room binding (a scene reload can
	# rebuild a phantom match from leftover config and keep
	# room_code set) so the play gates below follow the
	# server's state, not the client's leftover one.
	if room_code != "" and tourn_room.is_empty():
		leave_room()
	var role := String(auto.get("mp-tourn", "join"))
	var tname := String(auto.get("mp-tourn-name", "Smoke Cup"))
	# Creator: create once; the created push brings the detail
	# (with the id) back.
	if role == "create" and not _tourn_create_sent:
		_tourn_create_sent = true
		tourn_create(tname, String(auto.get("mp-tourn-format", "solo")),
				String(auto.get("mp-tourn-bracket", "single_elim")),
				int(auto.get("mp-tourn-size", "4")))
		return true
	# Joiner-by-name: find our tournament in the list.
	if role == "joinany" and _tourn_id == "":
		tourn_request_list()
		for row in tourn_list_rows:
			if String(row.get("name", "")) == tname:
				_tourn_id = String(row.get("id", ""))
				print("MPLOG tourn joinany found id=", _tourn_id)
				break
		return true
	if _tourn_id == "":
		if not tourn_detail.is_empty():
			_tourn_id = String(tourn_detail.get("id", ""))
			if _tourn_id != "":
				print("MPLOG tourn id=", _tourn_id)
		return true
	tourn_request_detail(_tourn_id)
	var d := tourn_detail
	if d.is_empty() or String(d.get("id", "")) != _tourn_id:
		return true
	var state := String(d.get("state", ""))
	if state == "open":
		if int(d.get("my_entry", 0)) == 0 and not _tourn_registered:
			_tourn_registered = true
			print("MPLOG tourn registering user=", account_name)
			tourn_register(_tourn_id)
			return true
		var expect := int(auto.get("mp-tourn-expect", "4"))
		if role == "create" and not _tourn_started \
				and (d.get("entries", []) as Array).size() >= expect:
			_tourn_started = true
			print("MPLOG tourn starting checkin entries=",
					(d.get("entries", []) as Array).size())
			tourn_start(_tourn_id)
		return true
	if state == "finished":
		if not _tourn_finished_printed:
			_tourn_finished_printed = true
			_tourn_quit_at = now + 1500
			print("MPLOG tourn finished champion=",
					String(d.get("champion_name", "")),
					" runner=", String(d.get("runner_up_name", "")),
					" user=", account_name)
		elif _tourn_quit_at > 0 and now >= _tourn_quit_at:
			get_tree().quit()
		return true
	if state != "checkin" and state != "running":
		return true
	# Find my earliest actionable match.
	for m in (d.get("matches", []) as Array):
		var my_side := int(m.get("my_side", -1))
		if my_side < 0:
			continue
		var mstate := String(m.get("state", ""))
		var mid := int(m.get("id", 0))
		if mstate == "ready":
			var checked := bool(m.get("check_a", false)) if my_side == 0 \
					else bool(m.get("check_b", false))
			if not checked and not _tourn_checked.has(mid):
				_tourn_checked[mid] = true
				print("MPLOG tourn checkin match=", mid, " user=", account_name)
				tourn_checkin(_tourn_id, mid)
				return true
			var both := bool(m.get("check_a", false)) and bool(m.get("check_b", false))
			var bound := not tourn_room.is_empty() \
					and int(tourn_room.get("match", 0)) == mid \
					and room_code != ""
			var sent_at := int(_tourn_play_sent.get(mid, 0))
			if both and not bound and (sent_at == 0 or now - sent_at > 6000):
				_tourn_play_sent[mid] = now
				print("MPLOG tourn play match=", mid, " user=", account_name)
				tourn_play(_tourn_id, mid)
				return true
		elif mstate == "live" and (tourn_room.is_empty() \
				or int(tourn_room.get("match", 0)) != mid):
			var sent_at2 := int(_tourn_play_sent.get(mid, 0))
			if sent_at2 == 0 or now - sent_at2 > 6000:
				_tourn_play_sent[mid] = now
				print("MPLOG tourn play (live) match=", mid, " user=", account_name)
				tourn_play(_tourn_id, mid)
				return true
	return true


## 15h captures: list view (a freshly created open
## tournament) and bracket view (a started 4-entry
## single-elim, filled by --mp-tourn=joinany filler clients).
## 17a alliance smoke driver: three roles prove the whole
## flow against a live server — "create" founds a request-mode
## alliance and approves the applicant, "apply" finds it in the
## browser, applies, joins on approval, receives the alliance
## chat and leaves; "outside" never joins and must receive
## nothing. Sequencing between the processes is the shell
## script's job (it greps the MPLOG lines).
func _auto_alliance_process(_cs) -> bool:
	var now := Time.get_ticks_msec()
	if _ally_authed_at == 0:
		_ally_authed_at = now
	var role := String(auto.get("mp-alliance", "apply"))
	var aname := String(auto.get("mp-alliance-name", "Hội Khói Lam"))
	# Global timeout: fail loudly instead of hanging the smoke.
	if _ally_quit_at == 0 and now - _ally_authed_at > 110000:
		print("MPLOG alliance TIMEOUT role=", role, " stage=", _ally_stage)
		_ally_quit_at = now + 500
	if _ally_quit_at > 0:
		if now >= _ally_quit_at:
			get_tree().quit()
		return true
	if now < _ally_next_poll:
		return true
	_ally_next_poll = now + 900
	match role:
		"create":
			match _ally_stage:
				0:
					print("MPLOG alliance create sent name=", aname)
					alliance_create(aname, String(auto.get("mp-alliance-tag", "HKL1")),
							2, 1, "request", "Chung một chiến tuyến")
					_ally_stage = 1
				1:
					alliance_request_home()
					if not alliance_mine.is_empty():
						_ally_id = String(alliance_mine.get("id", ""))
						print("MPLOG alliance created id=", _ally_id,
								" name=", String(alliance_mine.get("name", "")))
						_ally_stage = 2
				2:
					alliance_request_home()
					# Approve any pending request the moment it lands.
					for rq in alliance_mine.get("requests", []):
						print("MPLOG alliance approving user=",
								String(rq.get("user", "")))
						alliance_approve(_ally_id, String(rq.get("user", "")))
						_ally_stage = 3
				3:
					alliance_request_home()
					if int(alliance_mine.get("members_count", 0)) >= 2:
						for mem in alliance_mine.get("members", []):
							print("MPLOG alliance member user=",
									String(mem.get("user", "")),
									" role=", String(mem.get("role", "")))
						alliance_chat("Xin chào liên minh 17a")
						print("MPLOG alliance chat sent")
						_ally_stage = 4
				4:
					alliance_request_home()
					if int(alliance_mine.get("members_count", 0)) == 1:
						print("MPLOG alliance flow done")
						_ally_quit_at = now + 800
		"apply":
			match _ally_stage:
				0:
					alliance_request_list(aname)
					for row in alliance_rows:
						if String(row.get("name", "")) == aname:
							_ally_id = String(row.get("id", ""))
							print("MPLOG alliance found id=", _ally_id)
							_ally_stage = 1
							break
				1:
					print("MPLOG alliance apply sent id=", _ally_id)
					alliance_apply(_ally_id, "Cho mình xin vào với")
					_ally_stage = 2
				2:
					alliance_request_home()
					if not alliance_mine.is_empty():
						print("MPLOG alliance joined role=",
								String(alliance_mine.get("my_role", "")),
								" name=", String(alliance_mine.get("name", "")),
								" leader=", String(alliance_mine.get("leader_name", "")))
						_ally_stage = 3
				3:
					# The chat receipt itself is printed by the
					# "chat" dispatch (MPLOG alliance chat from=…).
					if not alliance_chat_lines.is_empty():
						_ally_stage = 4
				4:
					print("MPLOG alliance leave sent")
					alliance_leave(_ally_id)
					_ally_stage = 5
				5:
					alliance_request_home()
					if alliance_mine.is_empty():
						print("MPLOG alliance flow done")
						_ally_quit_at = now + 800
		"outside":
			match _ally_stage:
				0:
					alliance_request_home()
					if now - _ally_authed_at > 3000:
						_ally_stage = 1
				1:
					if now - _ally_authed_at > 26000:
						print("MPLOG alliance outsider clean mine=",
								0 if alliance_mine.is_empty() else 1,
								" chats=", alliance_chat_lines.size())
						_ally_quit_at = now + 500
	return true


## 17a captures: open the REAL alliance screen and save the
## shot. With --mp-alliance-name=<name> the shot client first
## applies to that alliance and waits for approval (a headless
## leader driver approves), so the joined view photographs
## real membership; without a name it photographs whatever
## state the account is in (the not-joined browser for a
## fresh account).
func _auto_alliance_shot(cs) -> void:
	var now := Time.get_ticks_msec()
	if _auto_home_at == 0:
		_auto_home_at = now
	if now < _ally_next_poll:
		return
	_ally_next_poll = now + 700
	var aname := String(auto.get("mp-alliance-name", ""))
	match _ally_stage:
		0:
			if aname == "":
				_ally_stage = 2
			elif now - _auto_home_at > 800:
				alliance_request_list(aname)
				_ally_stage = 1
		1:
			if not alliance_mine.is_empty():
				print("MPLOG alliance shot joined name=",
						String(alliance_mine.get("name", "")))
				_ally_stage = 2
			else:
				alliance_request_home()
				if _ally_id == "":
					for row in alliance_rows:
						if String(row.get("name", "")) == aname:
							_ally_id = String(row.get("id", ""))
							print("MPLOG alliance shot apply id=", _ally_id)
							alliance_apply(_ally_id, "Xin vào để chụp ảnh")
							break
		2:
			if aname == "" and now - _auto_home_at < 1500:
				return
			if auto.has("mp-alliance-createform") and cs != null \
					and cs.has_method("open_alliance_create_shot"):
				var bp := String(auto.get("mp-alliance-badge", "1,0")).split(",")
				cs.open_alliance_create_shot(int(bp[0]),
						int(bp[1]) if bp.size() > 1 else 0)
			elif cs != null and cs.has_method("open_alliance_shot"):
				cs.open_alliance_shot()
			_ally_stage = 3
			_ally_next_poll = now + 2600
		3:
			_auto_shot_done = true
			_save_shot(String(auto["mp-shot-alliance"]))
			print("MPLOG alliance shot saved")
			get_tree().quit()


## 17b alliance-expansion smoke driver (--mp-alliance2):
##   lead   — creates the alliance WITH a tag, sends a chat
##            line BEFORE the member joins (history seed),
##            approves the member, promotes them to deputy,
##            and waits to SEE the notice the deputy sets;
##   mem    — finds the alliance (row carries the tag), joins,
##            asserts the pre-join chat line is in the server
##            history payload, chats back, and once promoted
##            sets the notice board;
##   verify — a FRESH process after a real recorded match:
##            prints the quest progress + member counters +
##            persisted history + notice for shell asserts
##            (this is the "history after relog" evidence).
var _ally2_stage: int = 0


func _auto_alliance2_process(_cs) -> bool:
	var now := Time.get_ticks_msec()
	if _ally_authed_at == 0:
		_ally_authed_at = now
	var role := String(auto.get("mp-alliance2", "mem"))
	var aname := String(auto.get("mp-alliance-name", "Hội Sông Lam 17b"))
	var atag := String(auto.get("mp-alliance-tag", "SL17"))
	var notice_text := "Tối nay 20h tập trung đánh xếp hạng nhé"
	if _ally_quit_at == 0 and now - _ally_authed_at > 110000:
		print("MPLOG ally2 TIMEOUT role=", role, " stage=", _ally2_stage)
		_ally_quit_at = now + 500
	if _ally_quit_at > 0:
		if now >= _ally_quit_at:
			get_tree().quit()
		return true
	if now < _ally_next_poll:
		return true
	_ally_next_poll = now + 900
	match role:
		"lead":
			match _ally2_stage:
				0:
					print("MPLOG ally2 create sent name=", aname, " tag=", atag)
					alliance_create(aname, atag, 2, 1, "request",
							"Liên minh kiểm thử 17b")
					_ally2_stage = 1
				1:
					alliance_request_home()
					if not alliance_mine.is_empty():
						_ally_id = String(alliance_mine.get("id", ""))
						print("MPLOG ally2 created id=", _ally_id,
								" tag=", String(alliance_mine.get("tag", "")))
						# Sent while the leader is ALONE: the
						# member must still see it via history.
						alliance_chat("Chào cả nhà 17b")
						print("MPLOG ally2 lead chat sent")
						_ally2_stage = 2
				2:
					alliance_request_home()
					for rq in alliance_mine.get("requests", []):
						print("MPLOG ally2 approving user=",
								String(rq.get("user", "")))
						alliance_approve(_ally_id, String(rq.get("user", "")))
						_ally2_stage = 3
				3:
					alliance_request_home()
					if int(alliance_mine.get("members_count", 0)) >= 2:
						for mem in alliance_mine.get("members", []):
							var mu := String(mem.get("user", ""))
							if mu != account_name:
								print("MPLOG ally2 promoting user=", mu)
								alliance_role(_ally_id, mu, "deputy")
						_ally2_stage = 4
				4:
					alliance_request_home()
					if String(alliance_mine.get("notice", "")) == notice_text:
						print("MPLOG ally2 notice seen text=",
								String(alliance_mine.get("notice", "")))
						print("MPLOG ally2 lead done")
						_ally_quit_at = now + 800
		"mem":
			match _ally2_stage:
				0:
					alliance_request_list(aname)
					for row in alliance_rows:
						if String(row.get("name", "")) == aname:
							_ally_id = String(row.get("id", ""))
							print("MPLOG ally2 found id=", _ally_id,
									" tag=", String(row.get("tag", "")))
							_ally2_stage = 1
							break
				1:
					print("MPLOG ally2 apply sent id=", _ally_id)
					alliance_apply(_ally_id, "Cho mình vào kiểm thử 17b")
					_ally2_stage = 2
				2:
					alliance_request_home()
					if not alliance_mine.is_empty():
						var hist: Array = alliance_mine.get("chat", [])
						var has_seed := false
						for cm in hist:
							if String(cm.get("text", "")) == "Chào cả nhà 17b":
								has_seed = true
						print("MPLOG ally2 history ok=", has_seed,
								" lines=", hist.size())
						print("MPLOG ally2 joined role=",
								String(alliance_mine.get("my_role", "")),
								" tag=", String(alliance_mine.get("tag", "")))
						alliance_chat("Thành viên chào 17b")
						print("MPLOG ally2 mem chat sent")
						_ally2_stage = 3
				3:
					alliance_request_home()
					if String(alliance_mine.get("my_role", "")) == "deputy":
						alliance_notice(_ally_id, notice_text)
						print("MPLOG ally2 notice set")
						_ally2_stage = 4
				4:
					alliance_request_home()
					if String(alliance_mine.get("notice", "")) == notice_text:
						print("MPLOG ally2 mem done")
						_ally_quit_at = now + 800
		"verify":
			match _ally2_stage:
				0:
					alliance_request_home()
					if not alliance_mine.is_empty():
						for q in alliance_mine.get("quests", []):
							print("MPLOG ally2 verify quest key=",
									String(q.get("key", "")),
									" prog=", int(q.get("prog", 0)),
									" done=", bool(q.get("done", false)))
						for mem in alliance_mine.get("members", []):
							print("MPLOG ally2 verify member user=",
									String(mem.get("user", "")),
									" games=", int(mem.get("week_games", 0)),
									" wins=", int(mem.get("week_wins", 0)),
									" week=", int(mem.get("week", 0)))
						var has_seed := false
						for cm in alliance_mine.get("chat", []):
							if String(cm.get("text", "")) == "Chào cả nhà 17b":
								has_seed = true
						print("MPLOG ally2 verify history has=", has_seed,
								" lines=", (alliance_mine.get("chat", []) as Array).size())
						print("MPLOG ally2 verify notice=",
								String(alliance_mine.get("notice", "")))
						print("MPLOG ally2 verify done")
						_ally2_stage = 1
						_ally_quit_at = now + 800
	return true


## 17b captures: open the REAL alliance screen on a given tab
## (--mp-alliance2-tab=members|requests|quests|activity|chat),
## optionally with a member detail card open
## (--mp-alliance2-member=<username>), then save the shot.
## The account must already belong to the alliance (the
## capture harness seeds the store beforehand).
func _auto_alliance2_shot(cs) -> void:
	var now := Time.get_ticks_msec()
	if _auto_home_at == 0:
		_auto_home_at = now
	if now < _ally_next_poll:
		return
	_ally_next_poll = now + 700
	match _ally2_stage:
		0:
			if now - _auto_home_at > 800:
				alliance_request_home()
				_ally2_stage = 1
		1:
			if not alliance_mine.is_empty():
				if cs != null and cs.has_method("open_alliance_shot"):
					cs.open_alliance_shot()
				_ally2_stage = 2
				_ally_next_poll = now + 1500
			elif now - _auto_home_at > 15000:
				print("MPLOG ally2 shot: no alliance for this account")
				get_tree().quit()
		2:
			var scr = cs.get("alliance_screen") if cs != null else null
			if scr != null:
				var tab := String(auto.get("mp-alliance2-tab", "members"))
				if tab == "chat":
					scr.shot_open_chat()
				else:
					scr.shot_set_tab(tab, String(auto.get("mp-alliance2-member", "")))
			_ally2_stage = 3
			_ally_next_poll = now + 1400
		3:
			_auto_shot_done = true
			_save_shot(String(auto["mp-shot-alliance2"]))
			print("MPLOG ally2 shot saved tab=", String(auto.get("mp-alliance2-tab", "members")))
			get_tree().quit()


func _auto_tourn_shot(cs, bracket: bool) -> void:
	var now := Time.get_ticks_msec()
	if _auto_home_at == 0:
		_auto_home_at = now
	if now < _tourn_next_poll:
		return
	_tourn_next_poll = now + 700
	var tname := String(auto.get("mp-tourn-name", "Giải Vô Địch Mở Rộng"))
	match _tourn_shot_stage:
		0:
			if bracket:
				# Adopt the tournament the list shot created
				# (same name) instead of creating a second one
				# the fillers would never find.
				tourn_request_list()
				for row in tourn_list_rows:
					if String(row.get("name", "")) == tname:
						_tourn_id = String(row.get("id", ""))
						break
				if _tourn_id != "":
					_tourn_shot_stage = 2
					tourn_request_detail(_tourn_id)
			else:
				_tourn_shot_stage = 1
				tourn_create(tname, "solo", "single_elim", 8)
		1:
			if not tourn_detail.is_empty():
				_tourn_id = String(tourn_detail.get("id", ""))
				if _tourn_id != "":
					_tourn_shot_stage = 2
					_tourn_registered = true
					tourn_register(_tourn_id)
		2:
			if int(tourn_detail.get("my_entry", 0)) != 0:
				if not bracket:
					_tourn_shot_stage = 4
				else:
					_tourn_shot_stage = 3
					tourn_request_detail(_tourn_id)
			else:
				if not _tourn_registered and _tourn_id != "":
					_tourn_registered = true
					tourn_register(_tourn_id)
				tourn_request_detail(_tourn_id)
		3:
			# Bracket shot: wait for the 3 filler clients, then
			# open check-in so the bracket exists.
			tourn_request_detail(_tourn_id)
			if (tourn_detail.get("entries", []) as Array).size() >= 4:
				_tourn_shot_stage = 4
				tourn_start(_tourn_id)
		4:
			tourn_request_detail(_tourn_id)
			if not bracket and cs != null and cs.has_method("open_tournament_shot"):
				_auto_shot_done = true
				cs.open_tournament_shot("list")
				await get_tree().create_timer(1.4).timeout
				_save_shot(String(auto["mp-shot-tourn-list"]))
				print("MPLOG tourn list shot saved")
				get_tree().quit()
			elif bracket and String(tourn_detail.get("state", "")) in ["checkin", "running"] \
					and cs != null and cs.has_method("open_tournament_shot"):
				_auto_shot_done = true
				cs.open_tournament_shot("detail")
				await get_tree().create_timer(1.4).timeout
				_save_shot(String(auto["mp-shot-tourn-bracket"]))
				print("MPLOG tourn bracket shot saved")
				get_tree().quit()


var _skill_cap_stage := 0

## 15c capture (16b: the ONE skill button): hold the button
## with an injected press,
## shoot the info card, release (card must close, no cast, no
## targeting), then force a local cooldown and hold again —
## the card must open even while the button is disabled.
func _skill_hold_capture(cs) -> void:
	if _skill_cap_stage != 0:
		return
	var lh = cs.local_hero()
	if lh == null or cs.get("hud") == null:
		return
	_skill_cap_stage = 1
	cs.cam.focus_on(lh.global_position)
	await get_tree().create_timer(0.6).timeout
	var hud = cs.hud
	var btn = hud._skill_btns[0]
	var centre: Vector2 = (btn as Control).get_global_rect().get_center()
	var wpos := _win_pos(centre)
	_inject_mb(wpos, true)
	await get_tree().create_timer(0.8).timeout
	print("MPLOG skill hold card visible=", hud._skill_info_card.visible)
	_save_shot(String(auto["mp-skill-hold-shot"]))
	print("MPLOG skill hold shot saved")
	_inject_mb(wpos, false)
	await get_tree().create_timer(0.3).timeout
	print("MPLOG skill hold after release: card=", hud._skill_info_card.visible,
			" targeting=", cs.skill_targeting, " cd=", lh.skill_cd_t)
	lh.skill_cd_t = 25.0
	await get_tree().create_timer(0.3).timeout
	print("MPLOG skill btn disabled=", (btn as Button).disabled)
	_inject_mb(wpos, true)
	await get_tree().create_timer(0.8).timeout
	print("MPLOG skill hold on cooldown card visible=",
			hud._skill_info_card.visible)
	_inject_mb(wpos, false)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


## Viewport coords -> window coords for Input.parse_input_event
## (the stretch transform: uniform scale + letterbox bars).
func _win_pos(vp_pos: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var win := get_window().size
	var sc := minf(float(win.x) / vp.x, float(win.y) / vp.y)
	var bar := Vector2((float(win.x) - vp.x * sc) * 0.5,
			(float(win.y) - vp.y * sc) * 0.5)
	return vp_pos * sc + bar


func _inject_mb(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = down
	Input.parse_input_event(ev)


var _auto_hero_ordered := false
var _auto_hero_cast := false

var _dip_base_logged := false
var _dip_stage := 0 # slot 0's scripted steps (one-shot stages)
var _dip_accepted := false
var _dip_vision_before := false
var _dip_vision_after := false
var _dip_parked := false
var _dip_wood_before := -1
var _dip_wood_after := false
var _dip_hp_window := -1
var _dip_hp_late := false
var _dip_hp_dropped := false


var _tr_stage := 0
var _tr_gold_before := -1
var _tr_gold_after := false
var _tr_cargo_seen := false
var _tr_unload_seen := false


func _tr_unit_of(g, owner: int, kind: String):
	for u in g.units:
		if u.owner_id == owner and u.unit_type == kind and not u.is_dead():
			return u
	return null


## One of a slot's staged Markets: `far` picks the one farthest
## from its TC (the route target), otherwise the home Market.
func _tr_market_of(g, owner: int, far: bool):
	var tc = g.tc_of(owner)
	if tc == null:
		return null
	var best = null
	var bd := -1.0 if far else INF
	for b in g.buildings:
		if b.owner_id == owner and b.btype == "market" and not b.destroyed:
			var d: float = tc.position.distance_squared_to(b.position)
			if (far and d > bd) or (not far and d < bd):
				bd = d
				best = b
	return best


## 15g transport smoke choreography (--mp-transport): slot 0
## sets its cart's route to its second Market through the order
## pipeline, loads five Militia into its Wagon and sends the
## wagon across to unload at the far Market; slot 1 then sends
## its scout to ambush slot 0's cart. Both clients print the
## gold / cargo lines the smoke greps; the ambush alert line
## (Main's presentation gate) must appear on slot 0's client
## ONLY. One-shot stages gated on tick >= mark, like the
## diplomacy choreography below.
func _auto_transport_actions(g, tick: int) -> void:
	if g == null or not bool(g.get("mp_mode")) or is_observer:
		return
	if bool(g.get("mp_over")):
		return
	var slot := my_slot
	# Sim-state observers (every client prints the same values).
	if _tr_gold_before < 0 and tick >= 100:
		_tr_gold_before = int(g.mp_wallets[0].get("gold", 0))
		print("MPLOG transport gold before=", _tr_gold_before)
	if _tr_gold_before >= 0 and not _tr_gold_after and tick >= 320:
		_tr_gold_after = true
		print("MPLOG transport gold after=", int(g.mp_wallets[0].get("gold", 0)))
	if not _tr_cargo_seen and tick >= 90:
		var wg = _tr_unit_of(g, 0, "wagon")
		if wg != null and wg.cargo.size() == 5:
			_tr_cargo_seen = true
			print("MPLOG transport cargo=5")
	if not _tr_unload_seen and tick >= 200:
		var wg2 = _tr_unit_of(g, 0, "wagon")
		var fm = _tr_market_of(g, 0, true)
		if wg2 != null and fm != null and wg2.cargo.is_empty():
			var near := 0
			var fc: Vector2 = fm.position + Vector2(fm.size) * World.TILE * 0.5
			for u in g.units:
				if u.owner_id == 0 and u.unit_type == "militia" \
						and u.global_position.distance_to(fc) < 220.0:
					near += 1
			if near >= 5:
				_tr_unload_seen = true
				print("MPLOG transport unloaded=5")
	if slot == 0:
		match _tr_stage:
			0:
				if tick >= 30:
					var cart = _tr_unit_of(g, 0, "cart")
					var fm2 = _tr_market_of(g, 0, true)
					if cart != null and fm2 != null:
						_tr_stage = 1
						g.selection = [cart]
						g.selected_ship = null
						g.issue_order(fm2.position
								+ Vector2(fm2.size) * World.TILE * 0.5)
						print("MPLOG transport route ordered")
			1:
				if tick >= 45:
					var wg3 = _tr_unit_of(g, 0, "wagon")
					if wg3 != null:
						var troops: Array = []
						for u in g.units:
							if u.owner_id == 0 and u.unit_type == "militia" \
									and not u.is_dead():
								troops.append(u)
						if troops.size() >= 5:
							_tr_stage = 2
							g.selection = troops
							g.selected_ship = null
							g.issue_order(wg3.global_position)
							print("MPLOG transport load ordered n=", troops.size())
			2:
				if tick >= 75:
					var wg4 = _tr_unit_of(g, 0, "wagon")
					var fm3 = _tr_market_of(g, 0, true)
					if wg4 != null and fm3 != null and wg4.cargo.size() == 5:
						_tr_stage = 3
						g.selection = [wg4]
						g.selected_ship = null
						g.issue_order(fm3.position
								+ Vector2(fm3.size) * World.TILE * 0.5)
						print("MPLOG transport unload ordered")
	if slot == 1 and _tr_stage == 0 and tick >= 380:
		_tr_stage = 1
		var scout = _dip_scout_of(g, 1)
		var cart2 = _tr_unit_of(g, 0, "cart")
		if scout != null and cart2 != null:
			g.selection = [scout]
			g.selected_ship = null
			g.issue_order(cart2.global_position)
			print("MPLOG transport ambush ordered")


## 15b diplomacy smoke choreography (--mp-dip): slot 0 proposes
## an alliance to slot 1, slot 1 accepts, a tribute flows, slot 0
## declares a break and attacks — first inside the declaration
## window (must not land), then after it matures (must land).
## Every step prints MPLOG dip lines the smoke greps for. In a
## 2-player room the accept itself ends the match (the last two
## are mutually allied -> shared victory).
## NOTE: _auto_tick does NOT run once per tick (the same tick
## repeats while the sim waits, and values can be skipped while
## catching up), so every step is a one-shot stage gated on
## tick >= its mark — the pattern the older hooks use.
func _auto_dip_actions(g, tick: int) -> void:
	if g == null or not bool(g.get("mp_mode")) or is_observer:
		return
	var slot := my_slot
	if not _dip_base_logged and tick >= 3:
		var tc0 = g.tc_of(slot)
		if tc0 != null:
			_dip_base_logged = true
			print("MPLOG dip base slot=", slot, " cell=", tc0.origin_cell)
	if bool(g.get("mp_over")):
		return
	if slot == 1:
		# Vision BEFORE any alliance: A's base must be unseen.
		# (Fires at the first call past tick 30 — still well
		# before A's tick-40 proposal can execute.)
		if not _dip_vision_before and tick >= 30:
			var atc = g.tc_of(0)
			if atc != null and g.fog != null:
				_dip_vision_before = true
				var cc: Vector2i = atc.origin_cell + Vector2i(1, 1)
				print("MPLOG dip vision before b_sees_a=",
						g.fog.cell_state(cc))
		if not _dip_accepted and g.dip_invite_from(0, 1) == g.DIP_ALLY:
			_dip_accepted = true
			g.diplomacy_local_respond(0, true)
			print("MPLOG dip accepted by=1")
		if _dip_accepted and not _dip_vision_after and g.fog != null:
			var atc2 = g.tc_of(0)
			if atc2 != null:
				var cc2: Vector2i = atc2.origin_cell + Vector2i(1, 1)
				if g.fog.cell_state(cc2) == 2:
					_dip_vision_after = true
					print("MPLOG dip vision after b_sees_a=2")
		# Park every villager so no deposit can pollute the
		# tribute delta sampled around the gift tick.
		if not _dip_parked and tick >= 100:
			_dip_parked = true
			var mine: Array = []
			for u in g.units:
				if u.owner_id == 1 and u.unit_type == "villager" \
						and not u.is_dead():
					mine.append(u)
			if not mine.is_empty():
				g.selection = mine
				g.selected_ship = null
				g.issue_order(mine[0].global_position)
		if _dip_wood_before < 0 and tick >= 112:
			_dip_wood_before = int(g.mp_wallets[1].get("wood", 0))
			print("MPLOG dip b wood before=", _dip_wood_before)
		if _dip_wood_before >= 0 and not _dip_wood_after and tick >= 140:
			_dip_wood_after = true
			print("MPLOG dip b wood after=",
					int(g.mp_wallets[1].get("wood", 0)))
		if _dip_hp_window < 0 and tick >= 399:
			var sc = _dip_scout_of(g, 1)
			if sc != null:
				_dip_hp_window = int(sc.hp)
				print("MPLOG dip b scout hp at399=", _dip_hp_window)
		if _dip_hp_window >= 0 and not _dip_hp_late and tick >= 549:
			var sc1 = _dip_scout_of(g, 1)
			if sc1 != null:
				_dip_hp_late = true
				print("MPLOG dip b scout hp at549=", int(sc1.hp))
		if tick >= 565 and not _dip_hp_dropped and _dip_hp_window > 0:
			var sc2 = _dip_scout_of(g, 1)
			if sc2 != null and int(sc2.hp) < _dip_hp_window:
				_dip_hp_dropped = true
				print("MPLOG dip b scout hp dropped=1 hp=", int(sc2.hp))
	if slot == 0:
		# Vision-shot capture: the host proposes and then holds —
		# no gift, no break; the shot hook ends the run.
		if auto.has("mp-dip-shot-vision-host") and _dip_stage >= 1:
			return
		match _dip_stage:
			0:
				if tick >= 40:
					_dip_stage = 1
					g.diplomacy_local_propose(1, g.DIP_ALLY)
					print("MPLOG dip proposed from=0 to=1")
			1:
				if tick >= 45:
					_dip_stage = 2
					_dip_order_scout(g, 0, _dip_scout_of(g, 1))
			2:
				if tick >= 120:
					_dip_stage = 3
					g.diplomacy_local_gift(1, "wood", 100)
					print("MPLOG dip gift sent")
			3:
				if tick >= 260:
					_dip_stage = 4
					g.diplomacy_local_break(1)
					print("MPLOG dip break declared")
			4:
				if tick >= 280:
					_dip_stage = 5
					_dip_order_scout(g, 0, _dip_scout_of(g, 1))
					print("MPLOG dip attack order in window")
			5:
				if tick >= 620:
					_dip_stage = 6
					_dip_order_scout(g, 0, _dip_scout_of(g, 1))
					print("MPLOG dip attack order after window")


func _dip_scout_of(g, owner: int):
	for u in g.units:
		if u.owner_id == owner and u.unit_type == "cavalry" \
				and not u.is_dead():
			return u
	return null


## Order `owner`'s scout cavalry onto the target unit's position
## through the normal selection/order path — the sim's own
## targeting rules decide whether that becomes an attack or a
## plain move (which is exactly what the smoke verifies).
func _dip_order_scout(g, owner: int, target_unit) -> void:
	var sc = _dip_scout_of(g, owner)
	if sc == null or target_unit == null:
		return
	g.selection = [sc]
	g.selected_ship = null
	g.issue_order(target_unit.global_position)


## Skill-smoke scripted hero play: at tick 35 the local hero is
## ordered onto the enemy hero (position order — apply_order_for
## resolves it as an attack); at tick 55 the local hero casts its
## active skill through the normal command pipeline. Both clients
## do this for their own slot, so aura + active effects flow into
## the tick-60/90 checksums on both sides.
func _auto_hero_actions(game) -> void:
	var hero = null
	var foe = null
	for cand in game.units:
		if cand.unit_type != "king" or cand.is_dead():
			continue
		if int(cand.owner_id) == my_slot:
			hero = cand
		else:
			foe = cand
	if hero == null or foe == null:
		return
	if not _auto_hero_ordered and current_tick >= 35:
		_auto_hero_ordered = true
		game.set_selection([hero])
		game.issue_order(foe.global_position)
		print("MPLOG hero order slot=", my_slot, " char=", game.char_for(my_slot),
				" tick=", current_tick)
	if not _auto_hero_cast and current_tick >= 55:
		_auto_hero_cast = true
		# 16b: the ONE skill — targeted skills go through the
		# targeted command form, aimed at the foe hero.
		# cast_local_skill_at returns void — it sends the command
		# outright, so "sent" is true once it has been called.
		var ok := false
		if game.skill_is_targeted(game.char_for(my_slot), 1):
			game.cast_local_skill_at(1, foe.global_position)
			ok = true
		else:
			ok = game.cast_local_skill()
		print("MPLOG hero cast slot=", my_slot, " sent=", ok, " tick=", current_tick)


func _auto_issue_move(game) -> void:
	var u = null
	for cand in game.units:
		if int(cand.owner_id) == my_slot and cand.unit_type == "villager" and not cand.is_dead():
			u = cand
			break
	if u == null:
		print("MPLOG auto move FAILED: no villager")
		return
	# March the villager ~10 tiles toward the map centre: the order is
	# sent through the normal right-click path (Net relay + tick).
	var dest: Vector2 = u.global_position + Vector2(320, -320)
	game.set_selection([u])
	game.issue_order(dest)
	print("MPLOG auto move issued by slot 0 at client tick ", current_tick)


## 15e smoke: slot 1 sends its scout cavalry to the map centre
## through the real order path (so every client applies it).
func _auto_spec_move_scout(game) -> void:
	for cand in game.units:
		if int(cand.owner_id) == my_slot and cand.unit_type == "cavalry" \
				and not cand.is_dead():
			var dest: Vector2 = game.world.cell_center(
					Vector2i(World.MAP_W / 2, World.MAP_H / 2))
			game.set_selection([cand])
			game.issue_order(dest)
			print("MPLOG spec scout move issued from=", cand.global_position,
					" to=", dest)
			return
	print("MPLOG spec scout move FAILED: no cavalry")


## 15e spectator driver: drive the observer's Spectator
## controller per --mp-spec-follow=N / --mp-spec-auto=1, print a
## state line every 30 ticks, and (for the bar capture) shoot
## once follow has settled.
func _auto_spec_observer(game) -> void:
	var spec = game.get("spectator")
	if spec == null:
		return
	if not _auto_spec_mode_set:
		_auto_spec_mode_set = true
		if auto.has("mp-spec-follow"):
			spec.set_follow(int(auto["mp-spec-follow"]))
		elif auto.has("mp-spec-auto"):
			spec.set_auto()
	if current_tick % 30 == 0 and current_tick != _auto_spec_last_print:
		_auto_spec_last_print = current_tick
		var d: Dictionary = spec.debug_state()
		print("MPLOG spec state mode=", String(d.get("mode", "?")),
				" slot=", int(d.get("slot", -1)),
				" cam=", Vector2(d.get("cam", Vector2.ZERO)),
				" target=", d.get("target", null),
				" tick=", current_tick)
	if auto.has("mp-spec-shot-bar") and not _auto_shot_done \
			and current_tick >= 45:
		_auto_shot_done = true
		await get_tree().create_timer(1.2).timeout
		_save_shot(String(auto["mp-spec-shot-bar"]))
		print("MPLOG spec bar shot saved")
		get_tree().quit()
	# 15e-bis: the spectator PANEL capture — open it through the
	# same toggle the HUD people button uses, let it refresh,
	# shoot, quit.
	if auto.has("mp-spec-shot-panel") and not _auto_shot_done \
			and current_tick >= 45:
		_auto_shot_done = true
		spec.set_panel_open(true)
		await get_tree().create_timer(1.2).timeout
		_save_shot(String(auto["mp-spec-shot-panel"]))
		print("MPLOG spec panel shot saved")
		get_tree().quit()


func _auto_scout(game) -> void:
	# Send ALL own living units at the enemy TC as a scout group
	# (a lone villager too often dies to beasts on the long crossing,
	# especially in a drifted capture client); when fog says the TC
	# cell is visible, take the shot and quit. The route is an
	# L-shape — first along our own map edge to the enemy's column,
	# then straight at the TC — because the direct diagonal crosses
	# the central lake, whose shore wedges groups in drifted sims.
	# A group that has not moved for 200 stepped ticks gets a short
	# perpendicular hop to unstick it, then the stage order again.
	var stepped := int(game.get("_mp_current_tick"))
	# Shot logic FIRST (it must run even when every scout is dead):
	# fallback at the stepped-tick budget, primary when fog reveals
	# the enemy TC.
	if stepped >= 1500 and not _auto_shot_done:
		_auto_shot_done = true
		_save_shot(String(auto["mp-scout-shot"]))
		print("MPLOG scout shot fallback")
		get_tree().quit()
		return
	if _auto_issued and game.fog != null:
		for b in game.buildings:
			if b.btype == "town_center" and int(b.owner_id) != my_slot and not b.destroyed:
				var c: Vector2i = b.origin_cell + Vector2i(1, 1)
				if game.fog.is_visible_cell(c):
					_auto_shot_done = true
					game.cam.focus_on(b.position + Vector2(48, 48))
					await get_tree().create_timer(0.35).timeout
					_save_shot(String(auto["mp-scout-shot"]))
					print("MPLOG scout shot saved")
					get_tree().quit()
					return
	var enemy_tc = null
	var own_tc = null
	for b in game.buildings:
		if b.btype == "town_center" and not b.destroyed:
			if int(b.owner_id) != my_slot:
				enemy_tc = b
			else:
				own_tc = b
	if enemy_tc == null or own_tc == null:
		return
	var group: Array = []
	for cand in game.units:
		if int(cand.owner_id) == my_slot and not cand.is_dead():
			group.append(cand)
	if group.is_empty():
		return
	var centre := Vector2.ZERO
	for u in group:
		centre += u.global_position
	centre /= float(group.size())
	if _auto_stage == 0:
		_auto_target = Vector2(enemy_tc.position.x + 48.0,
				own_tc.position.y + 48.0)
		if centre.distance_to(_auto_target) < 130.0:
			_auto_stage = 1
	else:
		_auto_target = enemy_tc.position + Vector2(48, 48)
	var stalled := false
	if _auto_last_centre == Vector2.INF:
		_auto_last_centre = centre
		_auto_stall_tick = stepped
	elif centre.distance_to(_auto_last_centre) > 64.0:
		_auto_last_centre = centre
		_auto_stall_tick = stepped
	elif stepped - _auto_stall_tick >= 200:
		stalled = true
	if (not _auto_issued and current_tick >= 10) or stalled or \
			(_auto_issued and _auto_stage != _auto_stage_at_issue
					and not _auto_shot_done):
		_auto_issued = true
		_auto_stage_at_issue = _auto_stage
		_auto_last_order_tick = stepped
		_auto_scout_unit = group[0]
		game.set_selection(group)
		if stalled:
			# Nudge the destination diagonally: one order that both
			# unsticks the group and still progresses the stage.
			var nudge := Vector2(128, -128) if _auto_stage == 0 \
					else Vector2(96, -96)
			game.issue_order(_auto_target + nudge)
			_auto_last_centre = Vector2.INF
		else:
			game.issue_order(_auto_target)


func _save_shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("MPLOG shot save err=", err, " path=", path)


## Capture after two presented frames, then quit (13r loading
## shot: the caller fires the instant a long synchronous build
## unblocks, when the presented frame is still the old step).
func _shot_then_quit(path: String, p: float) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save_shot(path)
	print("MPLOG loading shot saved progress=", p)
	get_tree().quit()


# ------------------------------------------------ 17d settings drivers

var _set_stage: int = 0
var _set_next_poll: int = 0
var _set_authed_at: int = 0
var _set_hooked: bool = false
var _set_rename_next: int = 0
var _set_last_error: String = ""
var _set_quit_at: int = 0
var _set_shot_stage: int = 0
var _set_shot_at: int = 0


func _set_hook() -> void:
	if _set_hooked:
		return
	_set_hooked = true
	rename_failed.connect(func(_msg: String, nxt: int) -> void:
		_set_rename_next = nxt
		print("MPLOG settings rename_failed next=", nxt))
	lobby_error.connect(func(msg: String) -> void:
		_set_last_error = msg)


## mp-settings smoke: rename -> cooldown blocks the second
## rename; avatar + frame + bubble equips land on the profile.
## The seeded account must own frame_01 (Lv 5 stats).
func _auto_settings_process(_cs) -> bool:
	_set_hook()
	var now := Time.get_ticks_msec()
	if _set_authed_at == 0:
		_set_authed_at = now
	if _set_quit_at == 0 and now - _set_authed_at > 90000:
		print("MPLOG settings TIMEOUT stage=", _set_stage)
		_set_quit_at = now + 400
	if _set_quit_at > 0:
		if now >= _set_quit_at:
			get_tree().quit()
		return true
	if now < _set_next_poll:
		return true
	_set_next_poll = now + 700
	var target := String(auto.get("mp-rename-to", "TenMoi17d"))
	match _set_stage:
		0:
			print("MPLOG settings profile name=", String(auth_profile.get("display_name", "")),
				" avatar=", String(auth_profile.get("avatar_id", "")),
				" frames_owned=", (auth_profile.get("owned_frames", []) as Array).size(),
				" rename_next=", int(auth_profile.get("rename_next_at", 0)))
			rename(target)
			_set_stage = 1
		1:
			if String(auth_profile.get("display_name", "")) == target:
				print("MPLOG settings rename ok name=", target)
				rename("TenKhac17d")
				_set_stage = 2
		2:
			if _set_rename_next > 0:
				var ok := _set_rename_next > int(Time.get_unix_time_from_system())
				print("MPLOG settings rename blocked next_valid=", ok)
				set_avatar("art:05")
				_set_stage = 3
		3:
			if String(auth_profile.get("avatar_id", "")) == "art:05":
				print("MPLOG settings avatar ok id=art:05")
				set_frame("frame_01")
				_set_stage = 4
		4:
			if String(auth_profile.get("frame_id", "")) == "frame_01":
				print("MPLOG settings frame ok id=frame_01")
				set_frame("frame_06")
				_set_stage = 5
				_set_last_error = ""
		5:
			if _set_last_error != "":
				print("MPLOG settings unowned frame rejected err=", _set_last_error)
				set_bubble("mac_dinh")
				_set_stage = 6
		6:
			if String(auth_profile.get("bubble_style", "")) == "mac_dinh":
				print("MPLOG settings bubble ok id=mac_dinh")
				print("MPLOG settings done")
				_set_quit_at = now + 500
	return true


## mp-shot-settings=<panel> + mp-shot-file=<path>: open the
## panel and shoot. Panel "profileframe" instead equips
## frame_01 + art:03, opens the PROFILE, and shoots twice
## (~0.9s apart) so the frame animation is provable.
func _auto_settings_shot(cs) -> void:
	_set_hook()
	var now := Time.get_ticks_msec()
	if _auto_home_at == 0:
		_auto_home_at = now
		return
	var mode := String(auto.get("mp-shot-settings", "hub"))
	var path := String(auto.get("mp-shot-file", ""))
	match _set_shot_stage:
		0:
			if now - _auto_home_at > 900:
				_set_shot_at = now
				if mode == "profileframe":
					set_avatar("art:03")
					set_frame("frame_01")
					_set_shot_stage = 1
				elif mode == "frames_popup":
					if cs != null and cs.has_method("open_settings_shot"):
						cs.open_settings_shot("frames")
					if cs != null and cs.settings_panels != null:
						cs.settings_panels.shot_open_frame_detail("frame_06")
					_set_shot_stage = 3
				else:
					if cs != null and cs.has_method("open_settings_shot"):
						cs.open_settings_shot(mode)
					_set_shot_stage = 3
		1:
			if String(auth_profile.get("frame_id", "")) == "frame_01" \
					or now - _set_shot_at > 5000:
				if cs != null and cs.has_method("open_profile_shot"):
					cs.open_profile_shot()
				_set_shot_at = now
				_set_shot_stage = 2
		2:
			if now - _set_shot_at > 900:
				# NOT _auto_shot_done yet — stage 5 still needs
				# the driver alive for the animation-proof shot.
				_save_shot(path)
				print("MPLOG settings profileframe shot A saved")
				_set_shot_at = now
				_set_shot_stage = 5
		5:
			if now - _set_shot_at > 900:
				var path_b := path.replace(".png", "_b.png")
				_save_shot(path_b)
				print("MPLOG settings profileframe shot B saved")
				get_tree().quit()
		3:
			if now - _set_shot_at > 1100:
				_auto_shot_done = true
				_save_shot(path)
				print("MPLOG settings shot saved panel=", mode)
				get_tree().quit()


# ------------------------------------------------------------------
# 17e chat-hub drivers (tests/chathub_smoke.sh,
# tests/capture_chathub.sh). Roles via --mp-chathub=<role>:
#   a     — world send; waits for B's world reply, DM, voice,
#           and marquee; then proves a non-admin grant fails.
#   b     — replies on world, DMs A, sends a synthetic voice
#           note, proves the empty-megaphone refusal, waits
#           for the admin grant, then broadcasts a marquee.
#   admin — grants HubB two megaphones after a warm-up wait.
#   a2    — fresh process: relogs as A and verifies the DM
#           history survived on the server.
# Captures via --mp-shot-chathub=<mode>: world / picker /
# alliance / dm_list / dm_thread / marquee.

var _hub_stage: int = 0
var _hub_next_poll: int = 0
var _hub_authed_at: int = 0
var _hub_quit_at: int = 0
var _hub_hooked: bool = false
var _hub_world_from: Dictionary = {}   # sender name -> last world text
var _hub_dm_from: Dictionary = {}      # peer -> last text
var _hub_voice_world_from: String = ""
var _hub_marquee_text: String = ""
var _hub_last_error: String = ""
var _hub_grant_used: bool = false
var _hub_thread_rows: int = -1
var _hub_shot_stage: int = 0
var _hub_shot_at: int = 0


func _hub_hook() -> void:
	if _hub_hooked:
		return
	_hub_hooked = true
	chat_line_received.connect(func(m: Dictionary) -> void:
		if String(m.get("scope", "")) == "world":
			_hub_world_from[String(m.get("name", ""))] = String(m.get("text", ""))
		elif String(m.get("scope", "")) == "dm":
			_hub_dm_from[String(m.get("peer", ""))] = String(m.get("text", "")))
	voice_line_received.connect(func(m: Dictionary, _wav: PackedByteArray) -> void:
		if String(m.get("scope", "")) == "world":
			_hub_voice_world_from = String(m.get("name", "")))
	marquee_received.connect(func(_n: String, text: String) -> void:
		_hub_marquee_text = text)
	lobby_error.connect(func(msg: String) -> void:
		_hub_last_error = msg)
	dm_thread_received.connect(func(_peer: String, rows: Array) -> void:
		_hub_thread_rows = rows.size()
		for r in rows:
			if String(r.get("text", "")).find("nhan rieng") != -1:
				print("MPLOG chathub a2 dm history ok rows=", rows.size()))


func _auto_chathub_process(_cs) -> bool:
	_hub_hook()
	var now := Time.get_ticks_msec()
	if _hub_authed_at == 0:
		_hub_authed_at = now
	if _hub_quit_at == 0 and now - _hub_authed_at > 150000:
		print("MPLOG chathub TIMEOUT role=", String(auto.get("mp-chathub", "")), " stage=", _hub_stage)
		_hub_quit_at = now + 400
	if _hub_quit_at > 0:
		if now >= _hub_quit_at:
			get_tree().quit()
		return true
	if now < _hub_next_poll:
		return true
	_hub_next_poll = now + 600
	var role := String(auto.get("mp-chathub", ""))
	match role:
		"a":
			match _hub_stage:
				0:
					world_chat("A chao the gioi [e:vui]")
					print("MPLOG chathub a world sent")
					_hub_stage = 1
				1:
					if _hub_world_from.has("HubB"):
						print("MPLOG chathub a got world from b text=", String(_hub_world_from["HubB"]))
						_hub_stage = 2
				2:
					if _hub_dm_from.has("HubB"):
						print("MPLOG chathub a got dm from b text=", String(_hub_dm_from["HubB"]))
						_hub_stage = 3
				3:
					if _hub_voice_world_from == "HubB":
						print("MPLOG chathub a got voice world from b")
						_hub_stage = 4
				4:
					if _hub_marquee_text.find("Tran dau") != -1:
						print("MPLOG chathub a got marquee text=", _hub_marquee_text)
						_hub_stage = 5
				5:
					_hub_last_error = ""
					admin_grant_megaphone("HubA", 1)
					_hub_stage = 6
				6:
					if _hub_last_error.find("Không có quyền") != -1:
						print("MPLOG chathub a grant refused err=", _hub_last_error)
						print("MPLOG chathub a done")
						_hub_quit_at = now + 600
		"b":
			match _hub_stage:
				0:
					if _hub_world_from.has("HubA"):
						var t := String(_hub_world_from["HubA"])
						print("MPLOG chathub b got world from a emote=", t.find("[e:vui]") != -1, " text=", t)
						world_chat("B chao lai [e:tim]")
						print("MPLOG chathub b world sent")
						_hub_stage = 1
				1:
					dm_send("HubA", "B nhan rieng cho A [e:cuoi]")
					print("MPLOG chathub b dm sent")
					_hub_stage = 2
				2:
					world_voice(VoiceRec.synth_wav(0.6), 0.6)
					print("MPLOG chathub b voice sent")
					_hub_stage = 3
				3:
					_hub_last_error = ""
					use_megaphone("B bao som")
					_hub_stage = 4
				4:
					if _hub_last_error.find("Loa thông báo") != -1:
						print("MPLOG chathub b megaphone refused")
						_hub_stage = 5
				5:
					if megaphone_count >= 2 and not _hub_grant_used:
						_hub_grant_used = true
						print("MPLOG chathub b megaphones n=", megaphone_count)
						use_megaphone("B: Tran dau 20h tap trung!")
						print("MPLOG chathub b megaphone used")
					elif _hub_grant_used and megaphone_count == 1:
						print("MPLOG chathub b megaphone left count=", megaphone_count)
						print("MPLOG chathub b done")
						_hub_quit_at = now + 600
		"admin":
			match _hub_stage:
				0:
					if now - _hub_authed_at > 5000:
						admin_grant_megaphone("HubB", 2)
						print("MPLOG chathub admin grant sent")
						_hub_stage = 1
				1:
					if now - _hub_authed_at > 9000:
						print("MPLOG chathub admin done")
						_hub_quit_at = now + 600
		"a2":
			match _hub_stage:
				0:
					dm_open("HubB")
					_hub_stage = 1
				1:
					if _hub_thread_rows >= 0:
						print("MPLOG chathub a2 done")
						_hub_quit_at = now + 600
	return true


## mp-shot-chathub captures (account HubShotA; the store is
## seeded by tests/capture_chathub.sh). Modes: world (emote +
## voice lines in the world tab), picker (emoticon grid
## open), alliance (creates an alliance, posts, opens the
## Liên minh tab), dm_list / dm_thread (seeded thread with
## HubShotB), marquee (seeded with 2 megaphones).
func _auto_chathub_shot(cs) -> void:
	_hub_hook()
	var now := Time.get_ticks_msec()
	if _hub_authed_at == 0:
		_hub_authed_at = now
		return
	var mode := String(auto.get("mp-shot-chathub", "world"))
	var path := String(auto.get("mp-shot-file", ""))
	match _hub_shot_stage:
		0:
			if now - _hub_authed_at > 1000:
				_hub_shot_at = now
				match mode:
					"world", "picker":
						world_chat("Chao ca nha [e:vui] toi moi vao [e:tim]")
						world_voice(VoiceRec.synth_wav(0.8), 0.8)
						_hub_shot_stage = 1
					"alliance":
						alliance_create("Hub Minh 17e", "H17", 2, 1, "open", "")
						_hub_shot_stage = 5
					"dm_list":
						dm_request_list()
						if cs != null and cs.has_method("open_chat_hub_shot"):
							cs.open_chat_hub_shot("dm")
						_hub_shot_stage = 3
					"dm_thread":
						dm_open("HubShotB")
						_hub_shot_stage = 7
					"marquee":
						use_megaphone("Dai chien lien minh — dang ky da mo!")
						_hub_shot_stage = 9
		1:
			if now - _hub_shot_at > 900:
				if cs != null and cs.has_method("open_chat_hub_shot"):
					cs.open_chat_hub_shot("world")
				if mode == "picker" and cs != null and cs.chat_hub != null:
					cs.chat_hub.shot_open_picker()
				_hub_shot_at = now
				_hub_shot_stage = 3
		5:
			if not alliance_mine.is_empty():
				alliance_chat("Tap trung danh tran [e:like] [e:vui]")
				_hub_shot_at = now
				_hub_shot_stage = 6
			elif now - _hub_shot_at > 15000:
				_hub_shot_stage = 6
		6:
			if now - _hub_shot_at > 900:
				if cs != null and cs.has_method("open_chat_hub_shot"):
					cs.open_chat_hub_shot("alliance")
				_hub_shot_at = now
				_hub_shot_stage = 3
		7:
			if _hub_thread_rows >= 0 or now - _hub_shot_at > 8000:
				if cs != null and cs.has_method("open_chat_hub_shot"):
					cs.open_chat_hub_shot("dm")
				if cs != null and cs.chat_hub != null:
					cs.chat_hub.shot_open_thread("HubShotB")
				_hub_shot_at = now
				_hub_shot_stage = 3
		9:
			# Save MID-SCROLL: wait until the marquee text has
			# travelled into the left half of the strip.
			var want_x := get_viewport().get_visible_rect().size.x * 0.45
			if (_mq_active and _mq_x < want_x) or now - _hub_shot_at > 12000:
				_auto_shot_done = true
				_save_shot(path)
				print("MPLOG chathub marquee shot saved")
				get_tree().quit()
		3:
			if now - _hub_shot_at > 1200:
				_auto_shot_done = true
				_save_shot(path)
				print("MPLOG chathub shot saved mode=", mode)
				get_tree().quit()
