package main

// Empire Age P4 foundation relay server.
//
// Usage: go run . [-addr :8765]   (or the built binary)
// HTTP:  GET /        -> plain status line
//        GET /healthz -> "ok"
// WS:    GET /ws      -> the game relay protocol (JSON messages)
//
// Protocol (client -> server):
//   {"t":"create","name":N,"biome":B,"layout":L}   -> {"t":"created",...} + room state
//        15a options: "room_name", "public", "room_pass", "allow_obs"
//        15b option:  "diplomacy" (in-match diplomacy opt-in, custom only)
//   {"t":"join","code":C,"name":N,"room_pass":P}   -> {"t":"joined",...} + room state / error
//   {"t":"config","biome":B,"layout":L}            host-only lobby change
//        15a fields: "room_name", "public", "allow_obs", "set_pass"+"room_pass"
//        15b field:   "diplomacy" (rides the same full-state config)
//   {"t":"chat","scope":"team","allies":[slots]}   15b: in a diplomacy room the
//        team channel follows the sender's CURRENT allies (sim state)
//   {"t":"match_result","winner_slots":[slots]}   15b: shared allied victory
//        in a diplomacy custom room (host-reported, custom only)
//   {"t":"list_rooms"}                             -> {"t":"room_list","rooms":[...]} (15a)
//   {"t":"observe","code":C,"name":N,"room_pass":P} watch-only room attach (15a)
//   {"t":"kick","slot":N} / {"t":"transfer_host","slot":N}   host powers (15a)
//   {"t":"obs_snapshot","tick":N,"state":{...}}    host serves a mid-match observer (15a)
//   {"t":"ready","ready":bool}
//   {"t":"start"}                                  host-only; all must be ready
//   {"t":"cmd","cmd":{...}}                        in-match; relayed with exec tick
//   {"t":"checksum","tick":N,"hash":"..."}
//   {"t":"leave"}
//   {"t":"set_avatar","avatar":C}                   account profile-avatar pick (17d catalogue)
//   {"t":"rename","name":N}                          display-name rename, 30d cooldown (17d)
//   {"t":"set_frame","frame":F} / {"t":"set_bubble","bubble":B} / {"t":"set_title","title":T}
//        cosmetics equips (17d) -> {"t":"profile_update","profile":...}
//   {"t":"set_name","name":N}                       account display-name pick (13r)
//   {"t":"set_active_skin","skin":S}                activate an OWNED cosmetic skin (13j; dormant — no shop yet)
//   {"t":"queue_join","mode":"1v1"} / {"t":"queue_leave"}   ranked matchmaking
//   {"t":"queue_join","queue":"normal","name":...}          normal (unranked) matchmaking, 13t
//   {"t":"referee_join","code":C,"token":T}        referee processes only
//   {"t":"world_chat","text":T} / {"t":"world_voice","audio":B64,"dur":S}
//        chat hub (17e): world channel — account-only, rate-limited
//   {"t":"alliance_voice","audio":B64,"dur":S}      17e: alliance voice
//   {"t":"dm_list"} / {"t":"dm_open","peer":U} / {"t":"dm_send","peer":U,"text":T}
//   {"t":"dm_voice","peer":U,"audio":B64,"dur":S}   17e: private chat
//   {"t":"megaphone_use","text":T}                  17e: spend a Loa thông báo
//   {"t":"admin_grant_megaphone","user":U,"count":N} 17e: EMPIRE_AGE_ADMINS only
// Protocol (server -> client): room / created / joined / match_start /
// tick / cmd / player_left / desync / error / queue_joined / match_found
// / referee_ok — see hub.go and README.md.

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

type clientMsg struct {
	T        string          `json:"t"`
	Name     string          `json:"name"`
	Code     string          `json:"code"`
	Biome    string          `json:"biome"`
	Layout   string          `json:"layout"`
	Ready    bool            `json:"ready"`
	Tick     int64           `json:"tick"`
	Hash     string          `json:"hash"`
	Cmd      json.RawMessage `json:"cmd"`
	Scope    string          `json:"scope"`
	Text     string          `json:"text"`
	User     string          `json:"user"`
	Pass     string          `json:"pass"`
	Token    string          `json:"token"`
	Team     int             `json:"winner_team"`
	State    json.RawMessage `json:"state"`
	Mode     string          `json:"mode"`      // queue mode / leaderboard mode
	Queue    string          `json:"queue"`     // queue_join: "" = ranked, "normal" = unranked (13t)
	Reason   string          `json:"reason"`    // referee result reason
	TS       int64           `json:"ts"`        // ping echo payload (client clock, opaque)
	ID       int64           `json:"id"`        // mail_read: letter id (0 = all)
	Ticks    int             `json:"ticks"`     // referee result: match length in lockstep ticks
	ReplayID string          `json:"replay_id"` // replay fetch: the recording id
	Skin     string          `json:"skin"`      // set_active_skin: cosmetic skin id ("" = clear)
	Avatar   string          `json:"avatar"`    // set_avatar: profile avatar (17d: an "art:NN" catalogue id)
	Frame    string          `json:"frame"`     // set_frame: avatar frame id ("" = none)
	Bubble   string          `json:"bubble"`    // set_bubble: chat-bubble style id
	Title    string          `json:"title"`     // set_title: display title name ("" = clear)
	Close    bool            `json:"close"`     // friend_close: the "bạn thân" flag state
	// Custom-match expansion (15a): room access + host powers.
	RoomName string `json:"room_name"` // create/config: browser display name
	RoomPass string `json:"room_pass"` // create/join/observe/config: room password
	Public   bool   `json:"public"`    // create/config: list in the room browser
	AllowObs bool   `json:"allow_obs"` // create/config: observers allowed
	SetPass  bool   `json:"set_pass"`  // config: replace the room password
	Slot     int    `json:"slot"`      // kick/transfer_host: target slot
	// Diplomacy (15b): room opt-in at create/config; the sender's
	// current ally slots on team chat; the winner SET of a shared
	// allied victory on match_result (custom rooms only).
	Diplomacy   bool  `json:"diplomacy"`
	Allies      []int `json:"allies"`
	WinnerSlots []int `json:"winner_slots"`
	// Spectator (15e): the room's observer delay in seconds on
	// create/config; the target observer's display name on
	// kick_obs rides the shared Name field.
	ObsDelay int `json:"obs_delay"`
	// Free-for-all results (13z): slots ordered 1st -> last, and
	// the slots whose elimination was a disconnect (referee only).
	Placements      []int `json:"placements"`
	DisconnectSlots []int `json:"disconnect_slots"`
	// Replay timeline sidecar (14a): elimination tick per slot
	// (index = slot; -1 or absent = never eliminated), reported
	// by the same trusted reporter as the result itself.
	ElimTicks []int64 `json:"elim_ticks"`
	// Referee per-slot match scores (15h): index = slot. Only
	// tournament rooms consume them (round-robin/group
	// tie-breaks); ranked ignores the field.
	Scores []int `json:"scores"`
	// Tournaments (15h): the tournament id + match id ride
	// these; create carries name/format/bracket/size; team
	// registration carries the partner's username; dispute
	// resolution carries uphold; manual walkover carries
	// side (0 = A, 1 = B).
	TournID    string `json:"tourn_id"`
	TournMatch int    `json:"tourn_match"`
	Format     string `json:"format"`
	Bracket    string `json:"bracket"`
	Size       int    `json:"size"`
	Partner    string `json:"partner"`
	Uphold     bool   `json:"uphold"`
	Side       int    `json:"side"`
	// Alliances (17a): the alliance id; create/settings carry
	// the badge colour id + description; the request message
	// rides Text, the join mode rides Mode ("open"/"request"),
	// role changes ride Role, and invite/kick/approve targets
	// ride User (a username the server already knows) or Name
	// (invite: a free-typed player name to resolve).
	AllyID     string `json:"ally_id"`
	BadgeIcon  int    `json:"badge_icon"`
	BadgeColor int    `json:"badge_color"`
	Desc       string `json:"desc"`
	Role       string `json:"role"`
	// Tag (17b): the alliance tag on create/settings; the
	// notice text rides Text.
	Tag string `json:"tag"`
	// Chat hub (17e): DM ops carry the other party's username
	// in Peer; voice ops carry the base64 WAV in Audio and
	// the declared duration in Dur; the megaphone grant
	// carries its amount in Count (the target rides User).
	Peer  string  `json:"peer"`
	Count int     `json:"count"`
	Audio string  `json:"audio"`
	Dur   float64 `json:"dur"`
	// Item grants (17d rule change): admin_grant_item carries
	// the family in Kind ("frame"|"title"|"bubble") and the
	// catalogue id in Item (the target rides User).
	Kind string `json:"kind"`
	Item string `json:"item"`
}

type session struct {
	hub   *Hub
	conn  *wsConn
	acc   *Accounts
	code  string
	slot  int
	in    bool   // has a room slot
	user  string // logged-in account name ("" = guest)
	token string // session token issued at login
	// userConnID (17a): this session's registration id in the
	// hub's per-user connection registry (alliance fan-out).
	userConnID uint64
	// Referee sessions (ranked rooms): the connection IS a room's
	// dedicated referee process, authenticated by token.
	isReferee bool
	refCode   string
	out       sender // test seam: when set, outbound sends go here
	// Observer sessions (15a): the connection watches a custom
	// room without holding a slot. obsCode is its room.
	obs     *observerConn
	obsCode string
}

// senderOrConn is the session's outbound channel: the test seam if
// set, else the websocket connection.
func (s *session) senderOrConn() sender {
	if s.out != nil {
		return s.out
	}
	return s.conn
}

func (s *session) sendJSON(v map[string]any) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	s.conn.SendText(data)
}

func (s *session) sendErr(err error) {
	s.sendJSON(map[string]any{"t": "error", "msg": err.Error()})
}

// sendTournDetail pushes one tournament's full detail view
// (15h) to this session, or the not-found error.
func (s *session) sendTournDetail(id string) {
	ts := s.hub.tourns
	if ts == nil {
		s.sendErr(ErrTournNotFound)
		return
	}
	t, ok := ts.Get(id)
	if !ok {
		s.sendErr(ErrTournNotFound)
		return
	}
	s.sendJSON(map[string]any{"t": "tourn_detail", "tourn": ts.View(t, s.user)})
}

func (s *session) sendAuthErr(err error) {
	s.sendJSON(map[string]any{"t": "auth_error", "msg": err.Error()})
}

// sendAllyHome pushes this session's fresh alliance_home
// payload (17a): their alliance view (nil when unaffiliated)
// plus pending invites.
func (s *session) sendAllyHome() {
	as := s.hub.allis
	if as == nil {
		s.sendJSON(map[string]any{"t": "alliance_home", "mine": nil, "invites": []map[string]any{}})
		return
	}
	mine, invites := as.HomeFor(s.user, s.hub.IsOnline)
	s.sendJSON(map[string]any{"t": "alliance_home", "mine": mine, "invites": invites})
}

// sendDMList pushes the caller's conversation list (17e):
// one row per thread with the partner's resolved display
// name, last text line, and unread count.
func (s *session) sendDMList() {
	rows := []map[string]any{}
	if s.hub.dms != nil {
		for _, c := range s.hub.dms.Conversations(s.user) {
			rows = append(rows, map[string]any{
				"user": c.User, "name": s.acc.DisplayNameOf(c.User),
				"last_text": StripEmotes(c.LastText), "last_at": c.LastAt,
				"unread": c.Unread,
			})
		}
	}
	s.sendJSON(map[string]any{"t": "dm_list", "rows": rows})
}

// sendDMThread pushes one pair's stored history (17e).
func (s *session) sendDMThread(peer string) {
	msgs := []DMMsg{}
	if s.hub.dms != nil {
		msgs = s.hub.dms.History(s.user, peer)
	}
	s.sendJSON(map[string]any{"t": "dm_thread", "peer": peer, "rows": msgs})
}

// onAuthed runs after a successful register/login: if the session
// is already sitting in a room, bind the slot to the account.
// (Characters are drawn at match start and cosmetic skins resolve
// from the account then — nothing per-slot to apply here anymore.)
func (s *session) onAuthed() {
	if s.in && s.user != "" {
		s.hub.AttachAccount(s.code, s.slot, s.user)
	}
}

// unbindUserConn drops this session's alliance fan-out
// registration, if any (17a).
func (s *session) unbindUserConn() {
	if s.user != "" && s.userConnID != 0 {
		s.hub.UnregisterUserConn(s.user, s.userConnID)
	}
	s.userConnID = 0
}

func (s *session) authOK(token string, p Profile) {
	if s.user != "" && s.user != p.User {
		s.hub.SetOnline(s.user, false) // account switch on one session
	}
	s.unbindUserConn()
	s.token = token
	s.user = p.User
	s.hub.SetOnline(p.User, true)
	s.userConnID = s.hub.RegisterUserConn(p.User, s.senderOrConn())
	s.sendJSON(map[string]any{
		"t": "auth_ok", "token": token,
		"profile": p, // {user, wins, losses, matches, mmr, rank{...}, unread_mail}
	})
	s.onAuthed()
}

// leaderRowMap is the wire shape of one leaderboard row (shared
// by the board rows and the "me" footer payload).
func leaderRowMap(r LeaderRow) map[string]any {
	return map[string]any{
		"user": r.User, "display_name": r.DisplayName, "wins": r.Wins, "losses": r.Losses,
		"matches": r.Matches, "mmr": r.MMR,
		"rank_tier": r.RankTier, "rank_text": r.RankText,
		"rank_short": r.RankShort, "rank_stars": r.RankStars,
		"rank_star_cap": r.StarCap, "emperor": r.Emperor,
		// 17d: account avatar + effective frame for BXH rows.
		"avatar_id": r.AvatarID, "frame_id": r.FrameID,
	}
}

// sendFriends pushes the caller's current friend list (with live
// presence resolved from the hub).
func (s *session) sendFriends() {
	rows := []FriendEntry{}
	if s.user != "" {
		rows = s.acc.FriendsOf(s.user)
		for i := range rows {
			rows[i].Online = s.hub.IsOnline(rows[i].User)
			if s.hub.allis != nil {
				rows[i].AllyTag = s.hub.allis.TagOf(rows[i].User)
			}
		}
		if rows == nil {
			rows = []FriendEntry{}
		}
	}
	s.sendJSON(map[string]any{"t": "friends", "rows": rows})
}

// sendMail pushes the caller's mailbox (newest first) + unread.
func (s *session) sendMail() {
	rows := []Letter{}
	unread := 0
	if s.user != "" {
		rows = s.acc.LettersOf(s.user)
		if rows == nil {
			rows = []Letter{}
		}
		for _, l := range rows {
			if !l.Read {
				unread++
			}
		}
	}
	s.sendJSON(map[string]any{"t": "mail", "rows": rows, "unread": unread})
}

func (s *session) handle(raw []byte) {
	var m clientMsg
	if err := json.Unmarshal(raw, &m); err != nil {
		s.sendJSON(map[string]any{"t": "error", "msg": "bad json"})
		return
	}
	switch m.T {
	case "ping":
		// Latency probe for the home lobby's connection readout:
		// the ts is the client's own clock, echoed untouched.
		s.sendJSON(map[string]any{"t": "pong", "ts": m.TS})
	case "replay":
		// Replay fetch (13h): ranked recordings are ladder-public
		// for logged-in accounts; custom-room recordings belong
		// to their account participants only.
		if s.hub.replays == nil {
			s.sendJSON(map[string]any{"t": "replay_error", "msg": "Máy chủ không lưu bản ghi lại."})
			return
		}
		rp, ok := s.hub.replays.Get(m.ReplayID)
		if !ok {
			s.sendJSON(map[string]any{"t": "replay_error", "msg": "Không tìm thấy bản ghi lại (có thể đã quá hạn lưu trữ)."})
			return
		}
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "replay_error", "msg": "Đăng nhập để xem lại trận đấu."})
			return
		}
		if !rp.Ranked {
			allowed := false
			for _, u := range rp.Participants() {
				if u == s.user {
					allowed = true
				}
			}
			if !allowed {
				s.sendJSON(map[string]any{"t": "replay_error", "msg": "Chỉ người chơi trong trận mới xem lại được trận thường này."})
				return
			}
		}
		s.sendJSON(map[string]any{"t": "replay_data", "replay": rp})
	case "history":
		// The caller's own ranked match history (13g home lobby).
		// Guests have no account, hence no history.
		rows := []MatchRecord{}
		if s.user != "" {
			rows = s.acc.MatchHistory(s.user)
		}
		if rows == nil {
			rows = []MatchRecord{}
		}
		s.sendJSON(map[string]any{"t": "history", "rows": rows})
	case "register":
		if err := s.acc.Register(m.User, m.Pass); err != nil {
			s.sendAuthErr(err)
			return
		}
		token, prof, err := s.acc.Login(m.User, m.Pass)
		if err != nil {
			s.sendAuthErr(err)
			return
		}
		s.authOK(token, prof)
	case "login":
		// A token in the message re-authenticates an earlier login
		// (client reconnect); user/pass is the normal path.
		if m.Token != "" && m.User == "" {
			prof, ok := s.acc.Authenticate(m.Token)
			if !ok {
				s.sendAuthErr(ErrBadCredentials)
				return
			}
			s.authOK(m.Token, prof)
			return
		}
		token, prof, err := s.acc.Login(m.User, m.Pass)
		if err != nil {
			s.sendAuthErr(err)
			return
		}
		s.authOK(token, prof)
	case "friends":
		s.sendFriends()
	case "friend_add":
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "friend_error", "msg": "Đăng nhập để dùng Bạn bè."})
			return
		}
		if err := s.acc.AddFriend(s.user, m.User); err != nil {
			s.sendJSON(map[string]any{"t": "friend_error", "msg": err.Error()})
			return
		}
		s.sendFriends()
	case "friend_remove":
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "friend_error", "msg": "Đăng nhập để dùng Bạn bè."})
			return
		}
		if err := s.acc.RemoveFriend(s.user, m.User); err != nil {
			s.sendJSON(map[string]any{"t": "friend_error", "msg": err.Error()})
			return
		}
		s.sendFriends()
	case "friend_close":
		// "Bạn thân" flag toggle (13m): per-owner, drives the
		// home rail's close-friend portraits.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "friend_error", "msg": "Đăng nhập để dùng Bạn bè."})
			return
		}
		if err := s.acc.SetCloseFriend(s.user, m.User, m.Close); err != nil {
			s.sendJSON(map[string]any{"t": "friend_error", "msg": err.Error()})
			return
		}
		s.sendFriends()
	case "mail":
		s.sendMail()
	case "mail_read":
		if s.user != "" {
			if _, err := s.acc.MarkMailRead(s.user, m.ID); err != nil {
				s.sendErr(err)
				return
			}
		}
		s.sendMail()
	case "logout":
		s.acc.Logout(s.token)
		s.unbindUserConn()
		if s.user != "" {
			s.hub.SetOnline(s.user, false)
		}
		s.token = ""
		s.user = ""
		if s.in {
			s.hub.AttachAccount(s.code, s.slot, "")
		}
		s.sendJSON(map[string]any{"t": "auth_out"})
	case "rename":
		// Display-name rename (17d): like set_name but enforces
		// the 30-day cooldown and stamps LastRenameAt. Replies
		// with a fresh profile (the panel reads the refreshed
		// rename clock from it) + the display_name echo so the
		// lobby/profile refresh like a first set.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "name_error", "msg": "Đăng nhập để đổi tên."})
			return
		}
		p, err := s.acc.RenameDisplayName(s.user, m.Name)
		if err != nil {
			var cd *RenameCooldownError
			if errors.As(err, &cd) {
				s.sendJSON(map[string]any{"t": "name_error", "msg": err.Error(),
					"rename_next_at": cd.NextAt})
				return
			}
			s.sendJSON(map[string]any{"t": "name_error", "msg": err.Error()})
			return
		}
		log.Printf("rename: %s is now %q", s.user, p.DisplayName)
		s.sendJSON(map[string]any{"t": "profile_update", "profile": p})
		s.sendJSON(map[string]any{"t": "display_name", "display_name": p.DisplayName})
		if s.in {
			s.hub.AttachAccount(s.code, s.slot, s.user)
		}
	case "set_frame":
		// Avatar frame equip (17d): ownership computed
		// server-side; the reply is the refreshed profile.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "error", "msg": "Đăng nhập để dùng khung avatar."})
			return
		}
		p, err := s.acc.SetFrame(s.user, m.Frame)
		if err != nil {
			s.sendJSON(map[string]any{"t": "error", "msg": err.Error()})
			return
		}
		s.sendJSON(map[string]any{"t": "profile_update", "profile": p})
	case "set_bubble":
		// Chat-bubble style equip (17d): same pattern.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "error", "msg": "Đăng nhập để dùng bong bóng chat."})
			return
		}
		p, err := s.acc.SetBubbleStyle(s.user, m.Bubble)
		if err != nil {
			s.sendJSON(map[string]any{"t": "error", "msg": err.Error()})
			return
		}
		s.sendJSON(map[string]any{"t": "profile_update", "profile": p})
	case "set_title":
		// Display-title equip (17d): same pattern; "" clears.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "error", "msg": "Đăng nhập để dùng danh hiệu."})
			return
		}
		p, err := s.acc.SetDisplayTitle(s.user, m.Title)
		if err != nil {
			s.sendJSON(map[string]any{"t": "error", "msg": err.Error()})
			return
		}
		s.sendJSON(map[string]any{"t": "profile_update", "profile": p})
	case "set_avatar":
		// Profile avatar pick (13j; catalogue replaced 17d):
		// one of the twenty anime avatars, persisted on the
		// account; the reply echoes the normalised stored
		// value. Decoupled from the character draw.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "error", "msg": "Đăng nhập để lưu avatar."})
			return
		}
		if _, err := s.acc.SetAvatar(s.user, m.Avatar); err != nil {
			s.sendAuthErr(err)
			return
		}
		s.sendJSON(map[string]any{"t": "avatar", "avatar_id": NormalizeAvatarID(m.Avatar)})
	case "world_chat":
		// Chat hub (17e): the world channel. Account-only —
		// guests are refused here exactly like every other
		// lobby social surface (friends/mail/alliance).
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		if text := strings.TrimSpace(m.Text); text != "" {
			s.hub.RelayWorldChat(s.user, s.acc.DisplayNameOf(s.user), text)
		}
	case "world_voice":
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		wav, err := decodeVoicePayload(m.Audio)
		if err != nil {
			s.sendErr(err)
			return
		}
		if err := s.hub.RelayWorldVoice(s.user, s.acc.DisplayNameOf(s.user), wav, m.Dur); err != nil {
			s.sendErr(err)
		}
	case "alliance_voice":
		// Chat hub (17e): voice on the alliance channel —
		// membership resolved exactly like alliance_chat.
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		if s.hub.allis == nil {
			s.sendErr(ErrAllyNotMember)
			return
		}
		a := s.hub.allis.OfUser(s.user)
		if a == nil {
			s.sendErr(ErrAllyNotMember)
			return
		}
		wav, err := decodeVoicePayload(m.Audio)
		if err != nil {
			s.sendErr(err)
			return
		}
		if err := s.hub.RelayAllianceVoice(s.user, s.acc.DisplayNameOf(s.user), a.ID,
			s.hub.allis.MemberUsers(a.ID), wav, m.Dur); err != nil {
			s.sendErr(err)
		}
	case "dm_list":
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		s.sendDMList()
	case "dm_open":
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		if _, ok := s.acc.Profile(m.Peer); !ok {
			s.sendErr(ErrDMTarget)
			return
		}
		if _, err := s.hub.dms.MarkRead(s.user, m.Peer); err != nil {
			s.sendErr(err)
			return
		}
		s.sendDMThread(m.Peer)
		s.sendDMList()
	case "dm_send":
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		if _, ok := s.acc.Profile(m.Peer); !ok {
			s.sendErr(ErrDMTarget)
			return
		}
		text := strings.TrimSpace(m.Text)
		if text == "" {
			return
		}
		if err := s.hub.RelayDMText(s.user, s.acc.DisplayNameOf(s.user), m.Peer, text); err != nil {
			s.sendErr(err)
		}
	case "dm_voice":
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		if _, ok := s.acc.Profile(m.Peer); !ok {
			s.sendErr(ErrDMTarget)
			return
		}
		wav, err := decodeVoicePayload(m.Audio)
		if err != nil {
			s.sendErr(err)
			return
		}
		if err := s.hub.RelayDMVoice(s.user, s.acc.DisplayNameOf(s.user), m.Peer, wav, m.Dur); err != nil {
			s.sendErr(err)
		}
	case "megaphone_use":
		// Loa thông báo (17e): spend one item, broadcast the
		// marquee to every online player. No item → refusal.
		if s.user == "" {
			s.sendErr(ErrNotLoggedIn)
			return
		}
		text := strings.TrimSpace(m.Text)
		if text == "" {
			return
		}
		left, err := s.hub.UseMegaphone(s.user, s.acc.DisplayNameOf(s.user), text)
		if err != nil {
			s.sendErr(err)
			return
		}
		s.sendJSON(map[string]any{"t": "megaphones", "count": left})
	case "admin_grant_megaphone":
		// Loa thông báo issuance (17e): ONLY accounts named
		// in EMPIRE_AGE_ADMINS may grant — there is no shop
		// and no self-grant. Delivery: account count + mail
		// letter (GrantMegaphones) + a live system note.
		if s.user == "" || !s.hub.IsAdmin(s.user) {
			s.sendErr(ErrNotAdmin)
			return
		}
		target := strings.TrimSpace(m.User)
		n := m.Count
		if n <= 0 {
			n = 1
		}
		total, err := s.acc.GrantMegaphones(target, n)
		if err != nil {
			s.sendJSON(map[string]any{"t": "error", "msg": "Không tìm thấy tài khoản " + target + "."})
			return
		}
		log.Printf("megaphone: admin %s granted %d to %s (total %d)", s.user, n, target, total)
		s.sendJSON(map[string]any{"t": "megaphone_granted", "user": target, "count": total, "granted": n})
		note := map[string]any{"t": "system_msg",
			"text": "Bạn nhận được: " + itoa(n) + " Loa thông báo."}
		s.hub.SendToUsers([]string{target}, note)
		s.hub.SendToUsers([]string{target},
			map[string]any{"t": "megaphones", "count": total})
	case "admin_grant_item":
		// Cosmetic item grant (17d rule change): frames,
		// titles and bubble styles are ITEMS, possessed only
		// via this admin op (in practice: event rewards).
		// Delivery mirrors the megaphone grant — a system
		// note + a mail letter, worded as an event reward —
		// plus a profile refresh for the target's panels.
		if s.user == "" || !s.hub.IsAdmin(s.user) {
			s.sendErr(ErrNotAdmin)
			return
		}
		target := strings.TrimSpace(m.User)
		name, fresh, err := s.acc.GrantItem(target, m.Kind, m.Item)
		if err != nil {
			s.sendErr(err)
			return
		}
		log.Printf("grant item: admin %s -> %s %s:%s (%q) fresh=%v", s.user, target, m.Kind, m.Item, name, fresh)
		s.sendJSON(map[string]any{"t": "item_granted", "user": target,
			"kind": m.Kind, "item": m.Item, "name": name, "fresh": fresh})
		if fresh {
			s.hub.SendToUsers([]string{target}, map[string]any{
				"t": "system_msg", "text": "Bạn nhận được: " + name + "."})
			if p, ok := s.acc.Profile(target); ok {
				s.hub.SendToUsers([]string{target}, map[string]any{
					"t": "profile_update", "profile": p})
			}
		}
	case "set_name":
		// Display-name pick (13r): the name panel after register /
		// first login. Validated + uniqueness-checked in accounts;
		// the reply carries the stored name so the client can
		// refresh every label from one payload.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "error", "msg": "Đăng nhập để đặt tên."})
			return
		}
		if _, err := s.acc.SetDisplayName(s.user, m.Name); err != nil {
			s.sendJSON(map[string]any{"t": "name_error", "msg": err.Error()})
			return
		}
		s.sendJSON(map[string]any{"t": "display_name", "display_name": s.acc.DisplayNameOf(s.user)})
		// If the session already sits in a room, its room label
		// follows the new name too.
		if s.in {
			s.hub.AttachAccount(s.code, s.slot, s.user)
		}
	case "set_active_skin":
		// Cosmetic skin activation (13j): the skin must be OWNED.
		// No shop exists yet, so every account owns none and every
		// activation is rejected — the slot ships dormant.
		if s.user == "" {
			s.sendJSON(map[string]any{"t": "error", "msg": "Đăng nhập để kích hoạt skin."})
			return
		}
		if _, err := s.acc.SetActiveSkin(s.user, m.Skin); err != nil {
			s.sendAuthErr(err)
			return
		}
		s.sendJSON(map[string]any{"t": "active_skin", "skin": NormalizeSkinID(m.Skin)})
	case "leaderboard":
		mode := m.Mode
		if mode == "alliance" {
			// Liên minh tab (17a): alliances ranked by weekly
			// points; rows carry alliance fields, me is the
			// viewer's own alliance row (with its position).
			if s.hub.allis == nil {
				s.sendJSON(map[string]any{"t": "leaderboard", "mode": "alliance",
					"rows": []map[string]any{}, "me": nil})
				return
			}
			arows, ame := s.hub.allis.RankingWire(s.user)
			var me any
			if ame != nil {
				me = map[string]any{"pos": ame["pos"], "row": ame}
			}
			s.sendJSON(map[string]any{"t": "leaderboard", "mode": "alliance",
				"rows": arows, "me": me})
			return
		}
		if mode != "ranked" && mode != "friends" {
			mode = "wl"
		}
		rows, mePos, meRow := s.acc.LeaderboardV2(mode, s.user)
		out := make([]map[string]any, 0, len(rows))
		for _, r := range rows {
			out = append(out, leaderRowMap(r))
		}
		var me any
		if meRow != nil {
			me = map[string]any{"pos": mePos, "row": leaderRowMap(*meRow)}
		}
		s.sendJSON(map[string]any{"t": "leaderboard", "mode": mode, "rows": out, "me": me})
	case "queue_join":
		if m.Queue == "normal" {
			// Unranked queue (13t): guests allowed, no MMR/rank data
			// in the acknowledgement — there is none to report.
			if err := s.hub.NormalQueueJoin(s, m.Name); err != nil {
				s.sendErr(err)
				return
			}
			s.sendJSON(map[string]any{
				"t": "queue_joined", "queue": "normal", "mode": NormalMode1v1,
			})
			return
		}
		prof, err := s.hub.QueueJoin(s, m.Mode)
		if err != nil {
			s.sendErr(err)
			return
		}
		s.sendJSON(map[string]any{
			"t": "queue_joined", "mode": RankedMode1v1, "mmr": prof.MMR,
			"rank": prof.Rank,
		})
	case "queue_leave":
		if s.hub.QueueLeave(s) {
			s.sendJSON(map[string]any{"t": "queue_left"})
		}
	case "referee_join":
		if err := s.hub.RefereeJoin(m.Code, m.Token, s.conn); err != nil {
			s.sendErr(err)
			return
		}
		s.isReferee = true
		s.refCode = strings.ToUpper(strings.TrimSpace(m.Code))
		s.sendJSON(map[string]any{"t": "referee_ok", "code": s.refCode})
		log.Printf("referee joined room %s", s.refCode)
	case "match_result":
		if s.isReferee && s.hub.IsTournamentRoom(s.refCode) {
			// 15h: a tournament match result — banked through
			// the referee path like ranked, but routed to the
			// tournament service: W/L + bracket advancement
			// only, NEVER MMR/stars/ladder. This branch must
			// precede the placements branch (the referee sends
			// placements for every room shape).
			results, err := s.hub.RecordRefereeResult(s.refCode, m.Team, m.Reason, m.ElimTicks)
			if err != nil {
				s.sendErr(err)
				return
			}
			s.hub.NotifyRoomReplay(s.refCode)
			if err := s.hub.TournamentMatchResult(s.refCode, results, m.Scores); err != nil {
				log.Printf("tournament %s: applying result failed: %v", s.refCode, err)
			}
			return
		}
		if s.isReferee && len(m.Placements) > 0 {
			// 13z: free-for-all ranked result — the referee reports
			// the full placement list; the server banks stars/MMR
			// per placement for the whole field at once.
			byUser, ordered, err := s.hub.RecordRefereePlacements(s.refCode, m.Placements, m.DisconnectSlots, m.ElimTicks)
			if err != nil {
				s.sendErr(err)
				return
			}
			_ = byUser
			// 14a: the referee's recording is canonical — hand
			// every player its id for the result screen.
			s.hub.NotifyRoomReplay(s.refCode)
			biome, layout, _ := s.hub.RoomMapInfo(s.refCode)
			// Which accounts disconnected (reputation −5): resolve
			// the referee's slot list against the placement map.
			disc := make(map[string]bool)
			slotUser := s.hub.RoomSlotUsers(s.refCode)
			for _, sl := range m.DisconnectSlots {
				if u := slotUser[sl]; u != "" {
					disc[u] = true
				}
			}
			ocs, err := s.acc.RecordRankedPlacements(ordered,
				biome, layout, m.Ticks, s.hub.RoomReplayID(s.refCode), disc)
			if err != nil {
				log.Printf("ranked %s: banking placements failed: %v", s.refCode, err)
				return
			}
			for _, oc := range ocs {
				log.Printf("ranked %s: #%d %s — MMR %d -> %d, sao %+d (%s)",
					s.refCode, oc.Placement, oc.User, oc.MMRBefore, oc.MMRAfter,
					oc.Rank.StarDelta, oc.Rank.After.Text())
				s.hub.NotifyRankedResult(s.refCode, oc.User, map[string]any{
					"t":           "rank_result",
					"won":         oc.Won,
					"placement":   oc.Placement,
					"mmr_before":  oc.MMRBefore,
					"mmr_after":   oc.MMRAfter,
					"star_delta":  oc.Rank.StarDelta,
					"bonus":       oc.Rank.Bonus,
					"daily_bonus": oc.Rank.DailyBonus,
					"promoted":    oc.Rank.Promoted,
					"demoted":     oc.Rank.Demoted,
					"before":      rankViewFromState(oc.Rank.Before, false),
					"after":       rankViewFromState(oc.Rank.After, false),
				})
			}
			return
		}
		if s.isReferee {
			// The ONLY trusted result channel for ranked rooms.
			results, err := s.hub.RecordRefereeResult(s.refCode, m.Team, m.Reason, m.ElimTicks)
			if err != nil {
				s.sendErr(err)
				return
			}
			// 14a: hand every player the sealed replay id.
			s.hub.NotifyRoomReplay(s.refCode)
			var winner, loser string
			for user, won := range results {
				if won {
					winner = user
				} else {
					loser = user
				}
			}
			if winner != "" && loser != "" && winner != loser {
				biome, layout, _ := s.hub.RoomMapInfo(s.refCode)
				wo, lo, err := s.acc.RecordRankedResultReason(winner, loser,
					biome, layout, m.Ticks, s.hub.RoomReplayID(s.refCode), m.Reason)
				if err != nil {
					log.Printf("ranked %s: banking result failed: %v", s.refCode, err)
					return
				}
				log.Printf("ranked %s: %s beat %s (reason %q) — MMR %d / %d"+
					" — sao: %s %+d (%s), %s %+d (%s)",
					s.refCode, winner, loser, m.Reason, wo.MMRAfter, lo.MMRAfter,
					winner, wo.Rank.StarDelta, wo.Rank.After.Text(),
					loser, lo.Rank.StarDelta, lo.Rank.After.Text())
				// Each player gets their own ladder movement for
				// the ranked end panel.
				for _, oc := range []RankedOutcome{wo, lo} {
					s.hub.NotifyRankedResult(s.refCode, oc.User, map[string]any{
						"t":           "rank_result",
						"won":         oc.Won,
						"mmr_before":  oc.MMRBefore,
						"mmr_after":   oc.MMRAfter,
						"star_delta":  oc.Rank.StarDelta,
						"bonus":       oc.Rank.Bonus,
						"daily_bonus": oc.Rank.DailyBonus,
						"promoted":    oc.Rank.Promoted,
						"demoted":     oc.Rank.Demoted,
						"before":      rankViewFromState(oc.Rank.Before, false),
						"after":       rankViewFromState(oc.Rank.After, false),
					})
				}
			}
			return
		}
		if s.in && len(m.WinnerSlots) > 0 {
			// 15b: a diplomacy custom match that ended in a
			// shared allied victory — the host reports the
			// winner SET (no single winning team exists). The
			// hub refuses queue rooms structurally.
			results, err := s.hub.RecordMatchResultSlots(s.code, s.slot, m.WinnerSlots, m.ElimTicks)
			if err != nil {
				s.sendErr(err)
				return
			}
			for user, won := range results {
				s.acc.RecordMatch(user, won)
			}
			if rid := s.hub.RoomReplayID(s.code); rid != "" {
				s.hub.NotifyRoom(s.code, map[string]any{
					"t": "custom_replay", "replay_id": rid, "room": s.code,
				})
			}
			return
		}
		if s.in && len(m.Placements) > 0 {
			// 13z: a queued NORMAL match — the host reports the
			// full placement list; banking stays W/L only (1st
			// place = the win), never MMR or ladder.
			placements, err := s.hub.RecordMatchPlacements(s.code, s.slot, m.Placements, m.ElimTicks)
			if err != nil {
				if err == ErrRankedRoom {
					return // ranked rooms belong to the referee
				}
				s.sendErr(err)
				return
			}
			for user, placement := range placements {
				s.acc.RecordMatch(user, placement == 1)
			}
			// 14a: queue matches hand out the replay id under
			// the match_replay type (custom rooms keep theirs).
			s.hub.NotifyRoomReplay(s.code)
			return
		}
		if s.in {
			results, err := s.hub.RecordMatchResult(s.code, s.slot, m.Team, m.ElimTicks)
			if err != nil {
				if err == ErrRankedRoom {
					// Player-sent result for a ranked room: the
					// referee owns results here. Ignore quietly.
					return
				}
				s.sendErr(err)
				return
			}
			for user, won := range results {
				s.acc.RecordMatch(user, won)
			}
			// Hand every participant the replay id so their
			// device-local history entry can link the recording.
			if rid := s.hub.RoomReplayID(s.code); rid != "" {
				s.hub.NotifyRoom(s.code, map[string]any{
					"t": "custom_replay", "replay_id": rid, "room": s.code,
				})
			}
		}
	case "tourn_list", "tourn_create", "tourn_detail", "tourn_register",
		"tourn_unregister", "tourn_start", "tourn_cancel", "tourn_checkin",
		"tourn_play", "tourn_dispute", "tourn_resolve", "tourn_walkover",
		"tourn_reset":
		// 15h tournaments: all state lives in the Tournaments
		// service; these cases are thin protocol adapters. An
		// account is required for everything (guests neither
		// create, register, nor spectate brackets here).
		ts := s.hub.tourns
		if ts == nil {
			s.sendErr(ErrTournNotFound)
			return
		}
		if s.user == "" {
			s.sendErr(ErrTournLogin)
			return
		}
		switch m.T {
		case "tourn_list":
			all := ts.List()
			rows := make([]map[string]any, 0, len(all))
			for _, t := range all {
				if t.State == "cancelled" {
					continue
				}
				rows = append(rows, ts.Summary(t, s.user))
				if len(rows) >= 50 {
					break
				}
			}
			s.sendJSON(map[string]any{"t": "tourn_list", "rows": rows})
		case "tourn_create":
			t, err := ts.Create(s.user, m.Name, m.Format, m.Bracket, m.Size)
			if err != nil {
				s.sendErr(err)
				return
			}
			s.sendJSON(map[string]any{"t": "tourn_created", "id": t.ID})
			s.sendTournDetail(t.ID)
		case "tourn_detail":
			s.sendTournDetail(m.TournID)
		case "tourn_register":
			if err := ts.Register(m.TournID, s.user, m.Partner); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_unregister":
			if err := ts.Unregister(m.TournID, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_start":
			if err := ts.OpenCheckin(m.TournID, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_cancel":
			if err := ts.Cancel(m.TournID, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_checkin":
			if err := ts.Checkin(m.TournID, m.TournMatch, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_play":
			if s.in || s.obs != nil {
				s.sendErr(ErrTournRoomBusy)
				return
			}
			code, slot, err := s.hub.TournamentPlayRoom(s.senderOrConn(), m.TournID, m.TournMatch, s.user)
			if err != nil {
				s.sendErr(err)
				return
			}
			s.code, s.slot, s.in = code, slot, true
			s.sendJSON(map[string]any{"t": "tourn_match", "code": code,
				"slot": slot, "tourn_id": m.TournID, "match": m.TournMatch})
		case "tourn_dispute":
			if err := ts.Dispute(m.TournID, m.TournMatch, s.user, m.ReplayID); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_resolve":
			if err := ts.ResolveDispute(m.TournID, m.TournMatch, s.user, m.Uphold); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_walkover":
			if err := ts.AwardWalkover(m.TournID, m.TournMatch, s.user, m.Side); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		case "tourn_reset":
			if err := ts.ResetLiveMatch(m.TournID, m.TournMatch, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendTournDetail(m.TournID)
		}
	case "alliance_home", "alliance_list", "alliance_create",
		"alliance_apply", "alliance_cancel_request", "alliance_approve",
		"alliance_reject", "alliance_invite", "alliance_accept_invite",
		"alliance_decline_invite", "alliance_leave", "alliance_kick",
		"alliance_role", "alliance_transfer", "alliance_settings",
		"alliance_disband", "alliance_chat", "alliance_notice":
		// Alliances (17a). Accounts only — guests can neither
		// create, join, apply nor chat (same rule as tournaments).
		as := s.hub.allis
		if as == nil {
			s.sendErr(ErrAllyNotFound)
			return
		}
		if s.user == "" {
			s.sendErr(ErrAllyLogin)
			return
		}
		// pushHome refreshes OTHER affected users' open alliance
		// screens (approvals, kicks, invites, …).
		pushHome := func(users ...string) {
			for _, u := range users {
				if u == "" || u == s.user {
					continue
				}
				mine, invites := as.HomeFor(u, s.hub.IsOnline)
				s.hub.SendToUsers([]string{u}, map[string]any{
					"t": "alliance_home", "mine": mine, "invites": invites})
			}
		}
		switch m.T {
		case "alliance_home":
			s.sendAllyHome()
		case "alliance_list":
			rows := as.ListWire(s.user, m.Name)
			s.sendJSON(map[string]any{"t": "alliance_list", "rows": rows, "total": len(rows)})
		case "alliance_create":
			a, err := as.Create(s.user, m.Name, m.Tag, m.BadgeIcon, m.BadgeColor, m.Mode, m.Desc)
			if err != nil {
				s.sendErr(err)
				return
			}
			_ = a
			s.sendAllyHome()
		case "alliance_apply":
			if err := as.Apply(m.AllyID, s.user, m.Text); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
		case "alliance_cancel_request":
			if err := as.CancelRequest(m.AllyID, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
		case "alliance_approve":
			if err := as.Approve(m.AllyID, s.user, m.User); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(m.User)
		case "alliance_reject":
			if err := as.Reject(m.AllyID, s.user, m.User); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(m.User)
		case "alliance_invite":
			target, err := as.Invite(m.AllyID, s.user, m.Name)
			if err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(target)
		case "alliance_accept_invite":
			if err := as.AcceptInvite(s.user, m.AllyID); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
		case "alliance_decline_invite":
			if err := as.DeclineInvite(s.user, m.AllyID); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
		case "alliance_leave":
			if err := as.Leave(m.AllyID, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
		case "alliance_kick":
			if err := as.Kick(m.AllyID, s.user, m.User); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(m.User)
		case "alliance_role":
			if err := as.SetRole(m.AllyID, s.user, m.User, m.Role); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(m.User)
		case "alliance_transfer":
			if err := as.Transfer(m.AllyID, s.user, m.User); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(m.User)
		case "alliance_settings":
			members := as.MemberUsers(m.AllyID)
			if err := as.UpdateSettings(m.AllyID, s.user, m.Tag, m.BadgeIcon, m.BadgeColor, m.Mode, m.Desc); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(members...)
		case "alliance_notice":
			// 17b notice board: leader/deputy set it, every
			// member's open screen refreshes live.
			members := as.MemberUsers(m.AllyID)
			if err := as.SetNotice(m.AllyID, s.user, m.Text); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(members...)
		case "alliance_disband":
			members := as.MemberUsers(m.AllyID)
			if err := as.Disband(m.AllyID, s.user); err != nil {
				s.sendErr(err)
				return
			}
			s.sendAllyHome()
			pushHome(members...)
		case "alliance_chat":
			a := as.OfUser(s.user)
			if a == nil {
				s.sendErr(ErrAllyNotMember)
				return
			}
			text := strings.TrimSpace(m.Text)
			if text == "" {
				return
			}
			s.hub.RelayAllianceChat(s.user, s.acc.DisplayNameOf(s.user), a.ID,
				as.MemberUsers(a.ID), text)
		}
	case "create":
		if s.in || s.obs != nil {
			s.sendJSON(map[string]any{"t": "error", "msg": "already in a room"})
			return
		}
		r := s.hub.CreateRoomEx(s.senderOrConn(), m.Name, m.Biome, m.Layout,
			RoomCreateOptions{Name: m.RoomName, Public: m.Public,
				Password: m.RoomPass, AllowObs: m.AllowObs,
				Diplomacy: m.Diplomacy, ObsDelaySec: m.ObsDelay})
		s.code, s.slot, s.in = r.Code, 0, true
		s.sendJSON(map[string]any{"t": "created", "code": r.Code, "slot": 0})
		if s.user != "" {
			s.hub.AttachAccount(s.code, s.slot, s.user)
		}
	case "join":
		if s.in || s.obs != nil {
			s.sendJSON(map[string]any{"t": "error", "msg": "already in a room"})
			return
		}
		r, p, err := s.hub.JoinRoomEx(s.senderOrConn(), m.Code, m.Name, m.RoomPass, s.user)
		if err != nil {
			s.sendErr(err)
			return
		}
		s.code, s.slot, s.in = r.Code, p.Slot, true
		s.sendJSON(map[string]any{"t": "joined", "code": r.Code, "slot": p.Slot})
		if s.user != "" {
			s.hub.AttachAccount(s.code, s.slot, s.user)
		}
	case "observe":
		// 15a: watch-only attach to a custom room. The session
		// holds NO slot afterwards: cmd/checksum/snapshot from it
		// are rejected below, chat routes to the observer path.
		if s.in || s.obs != nil {
			s.sendJSON(map[string]any{"t": "error", "msg": "already in a room"})
			return
		}
		r, obs, err := s.hub.JoinObserver(s.senderOrConn(), m.Code, m.Name, m.RoomPass, s.user)
		if err != nil {
			s.sendErr(err)
			return
		}
		s.obs, s.obsCode = obs, r.Code
		s.sendJSON(map[string]any{"t": "observing", "code": r.Code})
	case "list_rooms":
		// 15a room browser: public custom rooms waiting in lobby.
		s.sendJSON(map[string]any{"t": "room_list", "rooms": s.hub.ListPublicRooms()})
	case "obs_ready":
		// 15a: the observer's match scene is bound and listening
		// — only now does the server ask the host for its join
		// snapshot, so the snapshot can never be lost in boot.
		if s.obs != nil {
			s.hub.ObserverReady(s.obsCode, s.obs)
		}
	case "kick":
		if s.in {
			if err := s.hub.KickPlayer(s.code, s.slot, m.Slot); err != nil {
				s.sendErr(err)
			}
		}
	case "kick_obs":
		// 15e: the host removes an observer (target = display
		// name in the shared name field) and bans their return.
		if s.in {
			if err := s.hub.KickObserver(s.code, s.slot, m.Name); err != nil {
				s.sendErr(err)
			}
		}
	case "transfer_host":
		if s.in {
			if err := s.hub.TransferHost(s.code, s.slot, m.Slot); err != nil {
				s.sendErr(err)
			}
		}
	case "ready":
		if s.in {
			if err := s.hub.SetReady(s.code, s.slot, m.Ready); err != nil {
				s.sendErr(err)
			}
		}
	case "config":
		if s.in {
			err := s.hub.SetConfigEx(s.code, s.slot, RoomConfigUpdate{
				Biome: m.Biome, Layout: m.Layout, Name: m.RoomName,
				Public: m.Public, AllowObs: m.AllowObs, Diplomacy: m.Diplomacy,
				ObsDelaySec: m.ObsDelay,
				TouchAccess: true,
				SetPassword: m.SetPass, Password: m.RoomPass,
			})
			if err != nil {
				s.sendErr(err)
			}
		}
	case "start":
		if s.in {
			if err := s.hub.Start(s.code, s.slot); err != nil {
				s.sendErr(err)
			}
		}
	case "cmd":
		// Observers hold no slot: their commands are rejected at
		// the relay, never relayed (15a).
		if s.obs != nil {
			s.sendErr(ErrObserverCmd)
		} else if s.in {
			if err := s.hub.RelayCmd(s.code, s.slot, m.Cmd); err != nil {
				s.sendErr(err)
			}
		}
	case "checksum":
		if s.isReferee {
			s.hub.ReportRefereeChecksum(s.refCode, m.Tick, m.Hash)
		} else if s.in {
			s.hub.ReportChecksum(s.code, s.slot, m.Tick, m.Hash)
		} // observer checksums are dropped: they are not reporters
	case "snapshot":
		if s.isReferee {
			s.hub.RelaySnapshot(s.refCode, RefereeChecksumSlot, m.Tick, m.State)
		} else if s.in {
			s.hub.RelaySnapshot(s.code, s.slot, m.Tick, m.State)
		} // observer snapshots are dropped: they are never a source
	case "obs_snapshot":
		// 15a: a player (the host) serving a mid-match observer.
		if s.in {
			if err := s.hub.RelayObsSnapshot(s.code, s.slot, m.Tick, m.State); err != nil {
				s.sendErr(err)
			}
		}
	case "chat":
		if s.obs != nil {
			if err := s.hub.RelayObserverChat(s.obsCode, s.obs, m.Scope, m.Text); err != nil {
				s.sendErr(err)
			}
		} else if s.in {
			s.hub.RelayChatEx(s.code, s.slot, m.Scope, m.Text, m.Allies) // errors are silent by design
		}
	case "leave":
		if s.obs != nil {
			s.hub.LeaveObserver(s.obsCode, s.obs)
			s.obs, s.obsCode = nil, ""
		} else if s.in {
			s.hub.Disconnect(s.code, s.slot)
			s.in = false
		}
	}
}

func (s *session) gone() {
	s.hub.QueueLeave(s)
	if s.obs != nil {
		s.hub.LeaveObserver(s.obsCode, s.obs)
		s.obs, s.obsCode = nil, ""
	}
	if s.user != "" {
		s.unbindUserConn()
		s.hub.SetOnline(s.user, false)
		s.user = ""
	}
	if s.isReferee {
		s.hub.RefereeDisconnect(s.refCode)
		s.isReferee = false
		return
	}
	if s.in {
		s.hub.Disconnect(s.code, s.slot)
		s.in = false
	}
}

func main() {
	addr := flag.String("addr", ":8765", "listen address")
	storePath := flag.String("store", "accounts.json", "account store file (JSON)")
	seasonDays := flag.Int("season-days", DefaultSeasonDays, "ranked season length in days (season 1 starts at the store's first boot)")
	refGodot := flag.String("referee-godot", "", "headless Godot binary used to spawn ranked referees (empty = orchestration off)")
	refProject := flag.String("referee-project", "../godot", "Godot project path handed to referee processes")
	refURL := flag.String("referee-url", "", "ws URL referees connect back to (default: derived from -addr)")
	refExtra := flag.String("referee-extra-args", "", "extra args appended to every referee command line (space-separated)")
	refTimeout := flag.Duration("referee-timeout", DefaultRefereeTimeout, "hard cap for one ranked match")
	flag.Parse()
	store, err := NewFileStore(*storePath)
	if err != nil {
		log.Fatalf("account store: %v", err)
	}
	acc := NewAccounts(store)
	acc.SeasonDays = *seasonDays
	hub := NewHub()
	hub.acc = acc
	// Tournaments (15h): server-side state over the same store.
	hub.tourns = NewTournaments(store, acc)
	// Alliances (17a): same store; the match-banking hook feeds
	// member contribution + alliance XP from recorded results.
	hub.allis = NewAlliances(store, acc)
	acc.MatchHook = hub.allis.Accrue
	// 17b: the match feed drives weekly quests + member
	// counters; the tag resolver feeds profile payloads.
	acc.MatchFeed = hub.allis.FeedMatch
	acc.AllyTagOf = hub.allis.TagOf
	// 17d: alliance level feeds avatar-frame ownership.
	// WarChampOf stays nil — the Đại chiến system is not
	// built, so no one holds the reign (frame_12 / war
	// title / champion bubble grant nothing) until the war
	// plugs its resolver in here.
	acc.AllyLevelOf = hub.allis.LevelOf
	// Chat hub (17e): the DM service over the same store, and
	// the admin set for Loa thông báo grants — account
	// usernames (comma-separated) in EMPIRE_AGE_ADMINS.
	// Nobody else can grant megaphones; there is no other
	// issuance path (no shop, no self-grant).
	hub.dms = NewDMs(store)
	if env := strings.TrimSpace(os.Getenv("EMPIRE_AGE_ADMINS")); env != "" {
		for _, u := range strings.Split(env, ",") {
			if u = strings.TrimSpace(u); u != "" {
				hub.admins[u] = true
			}
		}
		log.Printf("chat hub: %d admin account(s) may grant megaphones", len(hub.admins))
	}
	// Replay archive (13h): one JSON file beside the account store.
	if rps, err := NewFileReplayStore(*storePath + ".replays.json"); err != nil {
		log.Fatalf("replay store: %v", err)
	} else {
		hub.replays = rps
		log.Printf("replay archive: %s (%d stored)", *storePath+".replays.json", rps.Count())
	}
	orch := &Orchestrator{
		GodotPath:   *refGodot,
		ProjectPath: *refProject,
		ExtraArgs:   strings.Fields(*refExtra),
		Timeout:     *refTimeout,
		hub:         hub,
	}
	orch.RelayURL = *refURL
	if orch.RelayURL == "" {
		host := *addr
		if strings.HasPrefix(host, ":") {
			host = "127.0.0.1" + host
		}
		orch.RelayURL = "ws://" + host + "/ws"
	}
	hub.Orch = orch
	hub.OnRoomClosed = orch.ReapReferee
	go func() { // matchmaking pairing loop (ranked + normal queues)
		t := time.NewTicker(250 * time.Millisecond)
		defer t.Stop()
		for range t.C {
			hub.TryPairAll()
			hub.TryPairNormalAll()
			hub.SendQueueStatus()
			hub.TournamentSweep()
		}
	}()
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		fmt.Fprintf(w, "Empire Age relay server — %d room(s)\n", hub.RoomCount())
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgradeWS(w, r)
		if err != nil {
			http.Error(w, "websocket upgrade failed", http.StatusBadRequest)
			return
		}
		s := &session{hub: hub, conn: conn, acc: acc}
		conn.onText = s.handle
		conn.onGone = s.gone
		log.Printf("client connected from %s", r.RemoteAddr)
		go conn.readLoop()
	})
	log.Printf("Empire Age relay listening on %s (ws at /ws)", *addr)
	log.Fatal(http.ListenAndServe(*addr, mux))
}
