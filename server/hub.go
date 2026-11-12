package main

// Room / lobby / match-relay logic for the Empire Age P4 foundation
// server. The server is a DUMB RELAY by design this pass: it owns no
// game state. It creates rooms (2–4 players — Tín's hard rule), runs
// the lobby (names, ready flags, host start), broadcasts the match
// config with a shared seed, stamps every client command with the
// tick at which all clients must apply it (current tick + input
// delay), and compares per-tick state checksums the clients report,
// broadcasting a DESYNC notice when they diverge. Resync and an
// authoritative simulation are later stages (Master doc roadmap).

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log"
	"math/big"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	MaxPlayersPerRoom = 4
	MinPlayersPerRoom = 2
	InputDelayTicks   = 2
	TickInterval      = 100 * time.Millisecond
	// MaxObserversPerRoom caps watch-only observers per custom
	// room (15a). Observers hold no slot, send no commands and
	// never enter checksum math — the cap only bounds relay load.
	MaxObserversPerRoom = 8
	// ObserverSlot is the chat "from" value for observer messages
	// (players use their slot >= 0, the server itself uses -1).
	ObserverSlot = -2
)

type sender interface {
	SendText([]byte) error
}

type Player struct {
	Slot      int
	Name      string
	Ready     bool
	Connected bool
	User      string // account username when logged in ("" = guest)
	Account   bool   // true when this slot is bound to an account
	// Char is the main character ASSIGNED to this player for the
	// match (13j): drawn by the server in startMatchLocked from
	// the eight mains and carried in the match_start views so
	// every client + the referee field the same heroes. Skin is
	// the player's active COSMETIC skin ("" = none) — appearance
	// only; the hero's kit always comes from Char.
	Char    string
	Skin    string
	Seq     int64 // hub-wide join order (host auto-transfer picks the smallest)
	chatWin []time.Time
	send    sender
}

// observerConn is a watch-only room participant (15a): no slot,
// no commands, no checksum reports. It receives every room
// broadcast (room state, ticks, commands, all-chat) and may send
// all-channel chat. User is the account name when the observing
// session was logged in at join time ("" = guest).
type observerConn struct {
	Name    string
	User    string
	send    sender
	chatWin []time.Time
	// 15e: FIFO of match traffic held back by the room's
	// spectator delay, flushed by flushObsDelayLocked once each
	// entry's release time passes. Broadcast order is
	// preserved, so the observer's stream is the live stream
	// shifted by a constant delay.
	delayQ []obsDelayedMsg
}

// obsDelayedMsg is one marshalled message waiting out the
// room's spectator delay for one observer (15e).
type obsDelayedMsg struct {
	at   time.Time // release time
	data []byte
}

type resyncState struct {
	tick     int64 // tick at which divergence was detected
	source   int   // slot holding the winning checksum (snapshot source)
	diverged map[int]bool
	atTick   int64 // room tick when the cycle started (retry clock)
	retried  bool
}

type Room struct {
	Code           string
	Host           int
	InMatch        bool
	Biome          string
	Layout         string
	Seed           int64
	Players        map[int]*Player
	Tick           int64
	stopTick       chan struct{}
	checks         map[int64]map[int]string // tick -> slot -> hash
	desynced       map[int64]bool
	resync         *resyncState   // non-nil while a resync cycle is open
	rec            *replayBuilder // in-progress replay recording (13h)
	lastReplayID   string         // sealed replay id for this room
	resultRecorded bool           // match_result already banked
	// Queued rooms (13t): created by a matchmaking queue (ranked or
	// normal). The server auto-starts them on a countdown; there is
	// no ready/host-start step.
	Queued bool
	// Ranked rooms (P4 stage 3): created by the matchmaker, owned by
	// a dedicated referee process. Players never report results here.
	Ranked  bool
	Referee *refereeConn
	// Tournament rooms (15h): a ranked-referee room dedicated
	// to one tournament match. Tournament results route to the
	// tournament service (never the ladder) in main.go.
	Tournament       bool
	TournID          string
	TournMatchID     int
	RefereeTokenHash [32]byte // sha256 of the one-time referee token
	ResultReason     string   // "elimination" | "disconnect" (referee-reported)
	countdown        bool     // ranked start countdown in flight
	// Custom-match expansion (15a): room identity + access control.
	// Queue rooms leave all of these at zero values (private, no
	// password, no observers) and are never listed or observed.
	Name     string // display name for the room browser
	Public   bool   // listed in the room browser while waiting
	AllowObs bool   // observers may attach (host toggle)
	// Diplomacy (15b): the host's opt-in for in-match diplomacy
	// (stances / shared vision / tribute). Custom rooms only —
	// queue rooms never set it, so their matches structurally
	// cannot carry diplomacy state.
	Diplomacy bool
	// Spectator delay (15e): anti-cheat delay in seconds for
	// observer streams (0 = live). Chosen by the host at room
	// creation (Tắt / 60s / 120s in the client); the hub accepts
	// any non-negative value. Queue rooms never set it.
	ObsDelaySec int
	passSalt    []byte // room password: salted PBKDF2, never plaintext
	passHash    []byte // nil = no password
	Observers   []*observerConn
	Banned      map[string]bool // "u:<user>" / "g:<guest name>" keys set by kicks
	CreatedAt   time.Time
	obsSync     map[*observerConn]bool // observers awaiting a mid-match snapshot
	obsReq      map[*observerConn]bool // observers the host was already asked for
}

// RefereeChecksumSlot keys the referee's reports inside the room's
// checksum maps (players use their slot >= 0).
const RefereeChecksumSlot = -1

// refereeConn is the dedicated referee process attached to a ranked
// room: not a player, holds no slot, but receives every broadcast
// (tick/cmd/result traffic) and is the canonical checksum and
// snapshot source for the room.
type refereeConn struct {
	send      sender
	Connected bool
}

type Hub struct {
	mu    sync.Mutex
	rooms map[string]*Room
	// Account presence for the friend list (13g): a refcount of
	// live sessions per logged-in username.
	onlineMu sync.Mutex
	online   map[string]int
	// Replay recording (13h): nil disables it; main() installs
	// a FileReplayStore.
	replays ReplayStore
	// Ranked matchmaking (set by main; nil-safe in tests).
	acc  *Accounts
	Orch *Orchestrator
	// Tournaments (15h; set by main; nil-safe in tests).
	// tournRooms maps "tournID/matchID" -> room code for the
	// tournament matches whose dedicated room exists.
	tourns       *Tournaments
	tournRooms   map[string]string
	OnRoomClosed func(code string) // e.g. reap the room's referee process
	queue        []*queueEntry
	nqueue       []*queueEntry    // normal (unranked) queue, 13t
	mmNow        func() time.Time // test seam for queue timing
	// Last queue_status found-count pushed per queue (13z) — the
	// periodic pusher only sends when the number actually moves.
	lastRankedFound int
	lastNormalFound int
	seqCounter      int64 // join-order sequence for Players (15a)
}

// nextSeqLocked stamps the next join-order value (host transfer
// picks the longest-present player = smallest Seq).
func (h *Hub) nextSeqLocked() int64 {
	h.seqCounter++
	return h.seqCounter
}

func NewHub() *Hub {
	return &Hub{rooms: make(map[string]*Room), mmNow: time.Now,
		online: make(map[string]int), tournRooms: make(map[string]string)}
}

// RoomSlotUsers returns slot -> account username for a room
// ("" for guest-held slots); used to resolve a referee's
// disconnect slot list into account names (13z).
func (h *Hub) RoomSlotUsers(code string) map[int]string {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := make(map[int]string)
	if r := h.rooms[code]; r != nil {
		for slot, p := range r.Players {
			if p.Account {
				out[slot] = p.User
			} else {
				out[slot] = ""
			}
		}
	}
	return out
}

// RoomMapInfo returns a room's map keys (for banking the match
// context into ranked history records).
func (h *Hub) RoomMapInfo(code string) (biome, layout string, ok bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r := h.rooms[code]
	if r == nil {
		return "", "", false
	}
	return r.Biome, r.Layout, true
}

// SetOnline adjusts the live-session refcount for an account.
// When the LAST live session for an account ends, the account's
// last-online stamp is recorded (13m) so friend lists can show
// "gần đây … trước" — the stamp write happens after the
// presence lock is released and tolerates a missing account
// service (bare-hub tests).
func (h *Hub) SetOnline(user string, on bool) {
	if user == "" {
		return
	}
	h.onlineMu.Lock()
	if h.online == nil {
		h.online = make(map[string]int)
	}
	nowOffline := false
	if on {
		h.online[user]++
	} else {
		h.online[user]--
		if h.online[user] <= 0 {
			delete(h.online, user)
			nowOffline = true
		}
	}
	h.onlineMu.Unlock()
	if nowOffline && h.acc != nil {
		h.acc.MarkOffline(user)
	}
}

// IsOnline reports whether any live session is logged in as user.
func (h *Hub) IsOnline(user string) bool {
	h.onlineMu.Lock()
	defer h.onlineMu.Unlock()
	return h.online[user] > 0
}

// teamsFor assigns faction teams by join order for a match of n
// players: 2 -> 1v1 [0 1]; 3 -> FFA [0 1 2]; 4 -> 2v2 [0 0 1 1];
// 5..8 -> free-for-all, every slot its own team (13z queue
// matches; custom rooms cap at MaxPlayersPerRoom = 4, so n >= 5
// only ever occurs in an 8-player queue room).
func teamsFor(n int) []int {
	switch {
	case n <= 1:
		return []int{0}
	case n == 2:
		return []int{0, 1}
	case n == 3:
		return []int{0, 1, 2}
	case n == 4:
		return []int{0, 0, 1, 1}
	default:
		out := make([]int, n)
		for i := range out {
			out[i] = i
		}
		return out
	}
}

const codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

func (h *Hub) newCodeLocked() string {
	for {
		b := make([]byte, 5)
		for i := range b {
			n, err := rand.Int(rand.Reader, big.NewInt(int64(len(codeAlphabet))))
			if err != nil {
				b[i] = codeAlphabet[i%len(codeAlphabet)]
			} else {
				b[i] = codeAlphabet[n.Int64()]
			}
		}
		code := string(b)
		if _, taken := h.rooms[code]; !taken {
			return code
		}
	}
}

func cleanName(name string, slot int) string {
	name = strings.TrimSpace(name)
	if len(name) > 24 {
		name = name[:24]
	}
	if name == "" {
		name = "Người chơi " + string(rune('1'+slot))
	}
	return name
}

// RoomCreateOptions carries the 15a creation-time room settings.
// Password is the plaintext from the wire — it is salted and
// hashed before storage and never logged.
type RoomCreateOptions struct {
	Name      string // browser display name ("" = "Phòng của <host>")
	Public    bool
	Password  string
	AllowObs  bool
	Diplomacy bool // 15b: in-match diplomacy opt-in (custom only)
	// 15e: spectator delay in seconds (0 = live; the client's
	// choices are 0 / 60 / 120, clamped to >= 0 here).
	ObsDelaySec int
}

// setRoomPasswordLocked (re)sets a room's password from plaintext:
// a fresh random salt + PBKDF2 hash (the accounts hasher). An
// empty password clears it.
func setRoomPasswordLocked(r *Room, password string) {
	if password == "" {
		r.passSalt, r.passHash = nil, nil
		return
	}
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		salt = []byte("empire-age-room-salt")
	}
	r.passSalt = salt
	r.passHash = hashPassword(password, salt)
}

// checkRoomPassword reports whether a join attempt's password
// satisfies the room (rooms without a password accept anything).
func (r *Room) checkPassword(password string) bool {
	if r.passHash == nil {
		return true
	}
	got := hashPassword(password, r.passSalt)
	return subtle.ConstantTimeCompare(got, r.passHash) == 1
}

// banKeys are the ban-list identities of a player: the account
// key when bound, plus the guest-name key (the name the room
// knows them by). Guest bans are therefore name-based — a guest
// rejoining under a different name is a different identity
// (documented limit; accounts are banned durably).
func banKeys(user, name string) []string {
	keys := []string{"g:" + name}
	if user != "" {
		keys = append(keys, "u:"+user)
	}
	return keys
}

func (r *Room) isBanned(user, name string) bool {
	if len(r.Banned) == 0 {
		return false
	}
	for _, k := range banKeys(user, strings.TrimSpace(name)) {
		if r.Banned[k] {
			return true
		}
	}
	return false
}

// CreateRoom makes a room with the caller as host (slot 0).
func (h *Hub) CreateRoom(send sender, name, biome, layout string) *Room {
	return h.CreateRoomEx(send, name, biome, layout, RoomCreateOptions{})
}

// CreateRoomEx is CreateRoom with the 15a options (visibility,
// password, observers, display name).
func (h *Hub) CreateRoomEx(send sender, name, biome, layout string, opts RoomCreateOptions) *Room {
	h.mu.Lock()
	defer h.mu.Unlock()
	code := h.newCodeLocked()
	r := &Room{
		Code:        code,
		Host:        0,
		Biome:       biome,
		Layout:      layout,
		Players:     make(map[int]*Player),
		checks:      make(map[int64]map[int]string),
		desynced:    make(map[int64]bool),
		Public:      opts.Public,
		AllowObs:    opts.AllowObs,
		Diplomacy:   opts.Diplomacy,
		ObsDelaySec: opts.ObsDelaySec,
		Banned:      make(map[string]bool),
		CreatedAt:   h.mmNow(),
		obsSync:     make(map[*observerConn]bool),
	}
	hostName := cleanName(name, 0)
	r.Name = strings.TrimSpace(opts.Name)
	if r.Name == "" {
		r.Name = "Phòng của " + hostName
	}
	if len([]rune(r.Name)) > 40 {
		r.Name = string([]rune(r.Name)[:40])
	}
	setRoomPasswordLocked(r, opts.Password)
	if r.ObsDelaySec < 0 {
		r.ObsDelaySec = 0
	}
	r.Players[0] = &Player{Slot: 0, Name: hostName, Connected: true, send: send, Seq: h.nextSeqLocked()}
	h.rooms[code] = r
	h.broadcastRoomLocked(r)
	return r
}

var (
	ErrRoomNotFound  = errors.New("room not found")
	ErrRoomFull      = errors.New("room is full")
	ErrMatchRunning  = errors.New("match already running")
	ErrNotHost       = errors.New("only the host can do that")
	ErrNotReady      = errors.New("not all players are ready")
	ErrTooFew        = errors.New("need at least 2 players")
	ErrNotInRoom     = errors.New("player not in room")
	ErrRankedRoom    = errors.New("ranked room: only the referee reports results")
	ErrBadPlacement  = errors.New("placements must list every slot of the room exactly once")
	ErrNotRankedRoom = errors.New("room is not a ranked room")
	ErrRefereeDenied = errors.New("invalid referee token")
	ErrRefereeBusy   = errors.New("room already has a referee")
	ErrRankedLogin   = errors.New("login required for ranked play")
	ErrAlreadyIn     = errors.New("already in a room")
	ErrAlreadyQueued = errors.New("already in the ranked queue")
	ErrBadQueueMode  = errors.New("ranked supports mode 1v1 only")
	// 15a custom-match expansion.
	ErrBadPassword = errors.New("wrong room password")
	ErrBanned      = errors.New("you were removed from this room by the host")
	ErrObsDenied   = errors.New("this room does not allow observers")
	ErrObsFull     = errors.New("observer seats are full")
	ErrQueuedRoom  = errors.New("queue rooms have no host powers")
	ErrObserverCmd = errors.New("observers cannot send commands")
)

// JoinRoom adds a player to the lowest free slot of a lobby room.
func (h *Hub) JoinRoom(send sender, code, name string) (*Room, *Player, error) {
	return h.JoinRoomEx(send, code, name, "", "")
}

// JoinRoomEx is JoinRoom with the 15a access checks: the room
// password (verified against the salted hash) and the host's ban
// list. user is the joiner's account name when already logged in
// ("" = guest) — it keys the durable half of the ban list.
func (h *Hub) JoinRoomEx(send sender, code, name, password, user string) (*Room, *Player, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[strings.ToUpper(strings.TrimSpace(code))]
	if !ok {
		return nil, nil, ErrRoomNotFound
	}
	if r.isBanned(user, name) {
		return nil, nil, ErrBanned
	}
	if !r.checkPassword(password) {
		return nil, nil, ErrBadPassword
	}
	if r.InMatch {
		return nil, nil, ErrMatchRunning
	}
	if len(r.Players) >= MaxPlayersPerRoom {
		return nil, nil, ErrRoomFull
	}
	slot := 0
	for {
		if _, taken := r.Players[slot]; !taken {
			break
		}
		slot++
	}
	p := &Player{Slot: slot, Name: cleanName(name, slot), Connected: true, send: send, Seq: h.nextSeqLocked()}
	if user != "" {
		p.User = user
		p.Account = true
	}
	r.Players[slot] = p
	h.broadcastRoomLocked(r)
	return r, p, nil
}

func (h *Hub) roomLocked(code string) (*Room, error) {
	r, ok := h.rooms[code]
	if !ok {
		return nil, ErrRoomNotFound
	}
	return r, nil
}

// SetReady flips a player's ready flag (lobby only).
func (h *Hub) SetReady(code string, slot int, ready bool) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	p, ok := r.Players[slot]
	if !ok {
		return ErrNotInRoom
	}
	if !r.InMatch {
		p.Ready = ready
		h.broadcastRoomLocked(r)
	}
	return nil
}

// SetConfig lets the host change biome/layout in the lobby.
func (h *Hub) SetConfig(code string, slot int, biome, layout string) error {
	return h.SetConfigEx(code, slot, RoomConfigUpdate{Biome: biome, Layout: layout})
}

// RoomConfigUpdate is one host config edit (15a). Empty string
// fields keep their current values; TouchAccess gates the two
// booleans (so the legacy biome/layout-only edit cannot silently
// reset visibility); SetPassword + Password replace the room
// password ("" clears it).
type RoomConfigUpdate struct {
	Biome, Layout, Name string
	Public, AllowObs    bool
	Diplomacy           bool // 15b: rides the TouchAccess group like the other flags
	ObsDelaySec         int  // 15e: rides the TouchAccess group too (clamped >= 0)
	TouchAccess         bool
	SetPassword         bool
	Password            string
}

// SetConfigEx applies a host config edit. Host-only, lobby phase
// only (an in-match call is a no-op, matching SetConfig's legacy
// contract). Every applied change rides the room broadcast, so
// joiners see the live config before they ready up.
func (h *Hub) SetConfigEx(code string, slot int, upd RoomConfigUpdate) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if slot != r.Host {
		return ErrNotHost
	}
	if !r.InMatch {
		if upd.Biome != "" {
			r.Biome = upd.Biome
		}
		if upd.Layout != "" {
			r.Layout = upd.Layout
		}
		if upd.Name != "" {
			r.Name = upd.Name
			if len([]rune(r.Name)) > 40 {
				r.Name = string([]rune(r.Name)[:40])
			}
		}
		if upd.TouchAccess {
			r.Public = upd.Public
			r.AllowObs = upd.AllowObs
			r.Diplomacy = upd.Diplomacy
			r.ObsDelaySec = upd.ObsDelaySec
			if r.ObsDelaySec < 0 {
				r.ObsDelaySec = 0
			}
		}
		if upd.SetPassword {
			setRoomPasswordLocked(r, upd.Password)
		}
		h.broadcastRoomLocked(r)
	}
	return nil
}

// ------------------------------------------------------------ observers (15a)

// JoinObserver attaches a watch-only observer to a custom room.
// Queue rooms (ranked + normal) refuse observers — the dedicated
// Spectator system is a later roadmap item. Joining a room whose
// match is already running is supported: the observer is sent the
// match_start payload immediately and parked in the room's sync
// set; the host is asked for a snapshot, and RelayObsSnapshot
// forwards it when it arrives (the observer's client freezes its
// sim at tick 0 until then, exactly like a resync rebuild).
func (h *Hub) JoinObserver(send sender, code, name, password, user string) (*Room, *observerConn, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[strings.ToUpper(strings.TrimSpace(code))]
	if !ok {
		return nil, nil, ErrRoomNotFound
	}
	if r.Queued || r.Ranked || !r.AllowObs {
		return nil, nil, ErrObsDenied
	}
	if r.isBanned(user, name) {
		return nil, nil, ErrBanned
	}
	if !r.checkPassword(password) {
		return nil, nil, ErrBadPassword
	}
	if len(r.Observers) >= MaxObserversPerRoom {
		return nil, nil, ErrObsFull
	}
	obs := &observerConn{Name: cleanName(name, 0), User: user, send: send}
	r.Observers = append(r.Observers, obs)
	if r.InMatch {
		if r.obsSync == nil {
			r.obsSync = make(map[*observerConn]bool)
		}
		r.obsSync[obs] = true
		// Sent BEFORE match_start so the client knows, before it
		// boots the match scene, that it must freeze its sim
		// until the snapshot lands (no ordering race). The host
		// is NOT asked yet: the observer's match scene needs a
		// moment to boot and bind, and a snapshot served before
		// that would be lost — the observer asks again with
		// ObserverReady once it is listening.
		sendMsg(send, map[string]any{"t": "obs_sync_pending"})
		sendMsg(send, map[string]any{
			"t": "match_start", "seed": r.Seed,
			"biome": r.Biome, "layout": r.Layout,
			"diplomacy": r.Diplomacy, "obs_delay": r.ObsDelaySec,
			"players": h.playerViewsLocked(r),
		})
	}
	h.broadcastRoomLocked(r)
	return r, obs, nil
}

// ObserverReady is the mid-match observer's "my scene is bound,
// send the snapshot now" signal: the host is asked for a
// snapshot (once per waiting observer) and RelayObsSnapshot
// forwards it when it lands. Until then the observer's client
// holds its sim frozen and banks the tick/command stream, so
// no tick between the snapshot and its arrival is ever lost.
func (h *Hub) ObserverReady(code string, obs *observerConn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	if !ok || obs == nil || !r.obsSync[obs] {
		return
	}
	if r.obsReq == nil {
		r.obsReq = make(map[*observerConn]bool)
	}
	if r.obsReq[obs] {
		return
	}
	r.obsReq[obs] = true
	if hp := r.Players[r.Host]; hp != nil && hp.Connected && hp.send != nil {
		sendMsg(hp.send, map[string]any{"t": "obs_snapshot_request"})
	}
}

// LeaveObserver detaches an observer (voluntary leave or a
// dropped connection). Safe on rooms that no longer exist.
func (h *Hub) LeaveObserver(code string, obs *observerConn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	if !ok || obs == nil {
		return
	}
	h.removeObserverLocked(r, obs)
	h.broadcastRoomLocked(r)
}

// removeObserverLocked detaches one observer from the room
// (roster + sync sets). The caller broadcasts. Any delayed
// messages still queued for the observer die with the conn.
func (h *Hub) removeObserverLocked(r *Room, obs *observerConn) {
	for i, o := range r.Observers {
		if o == obs {
			r.Observers = append(r.Observers[:i], r.Observers[i+1:]...)
			break
		}
	}
	delete(r.obsSync, obs)
	delete(r.obsReq, obs)
}

// KickObserver removes an OBSERVER on the host's order and bans
// their identities from rejoining this room — the observer half
// of the 15a host powers (KickPlayer covers slots; before 15e
// there was no way to remove a disruptive spectator). The
// target is matched by observer display name (first match wins
// if two guests picked the same name — the same caveat the
// guest ban key has). Custom rooms only, host only, mirroring
// KickPlayer's refusals.
func (h *Hub) KickObserver(code string, slot int, targetName string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if r.Queued || r.Ranked {
		return ErrQueuedRoom
	}
	if slot != r.Host {
		return ErrNotHost
	}
	var target *observerConn
	for _, o := range r.Observers {
		if o.Name == targetName {
			target = o
			break
		}
	}
	if target == nil {
		return ErrNotInRoom
	}
	for _, k := range banKeys(target.User, target.Name) {
		r.Banned[k] = true
	}
	if target.send != nil {
		sendMsg(target.send, map[string]any{"t": "kicked"})
	}
	h.removeObserverLocked(r, target)
	h.broadcastRoomLocked(r)
	return nil
}

// RelayObsSnapshot forwards a host-served snapshot to every
// observer parked in the room's sync set, completing their
// mid-match join. Only the host may serve; anything else is
// ignored quietly (same contract as RelaySnapshot).
func (h *Hub) RelayObsSnapshot(code string, slot int, tick int64, state json.RawMessage) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if !r.InMatch || slot != r.Host || len(r.obsSync) == 0 {
		return nil
	}
	log.Printf("obs %s: snapshot relayed to %d observer(s) tick=%d (%d bytes)",
		r.Code, len(r.obsSync), tick, len(state))
	msg := map[string]any{"t": "snapshot", "tick": tick, "state": state}
	data, _ := json.Marshal(msg)
	for obs := range r.obsSync {
		if obs.send == nil {
			continue
		}
		// 15e delay: the snapshot joins the observer's delay
		// queue like any other match traffic. Because the whole
		// stream is shifted by the same delay and the queue is
		// FIFO, the snapshot the observer applies is exactly
		// ObsDelaySec old relative to the live match at the
		// moment it lands, with only older (already-banked)
		// traffic before it and only newer commands after it —
		// a self-consistent delayed join with no server-side
		// snapshot history needed.
		if r.ObsDelaySec > 0 {
			obs.delayQ = append(obs.delayQ, obsDelayedMsg{
				at:   time.Now().Add(time.Duration(r.ObsDelaySec) * time.Second),
				data: data,
			})
			continue
		}
		obs.send.SendText(data)
	}
	r.obsSync = make(map[*observerConn]bool)
	r.obsReq = make(map[*observerConn]bool)
	return nil
}

// RelayObserverChat delivers one observer chat message. Observers
// may use the all-channel scopes ("lobby" / "match") only — the
// team scope is rejected outright, so an observer can never read
// or write a team's private channel. The message is marked with
// from = ObserverSlot and observer = true so clients can label
// it. Same rate limit and length cap as player chat.
func (h *Hub) RelayObserverChat(code string, obs *observerConn, scope, text string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if obs == nil {
		return ErrNotInRoom
	}
	found := false
	for _, o := range r.Observers {
		if o == obs {
			found = true
		}
	}
	if !found {
		return ErrNotInRoom
	}
	if scope != "lobby" && scope != "match" {
		return ErrObserverCmd
	}
	now := time.Now()
	win := obs.chatWin[:0]
	for _, t := range obs.chatWin {
		if now.Sub(t) < ChatRateWindow {
			win = append(win, t)
		}
	}
	if len(win) >= ChatRateCount {
		obs.chatWin = win
		return nil // silently dropped, like player chat
	}
	obs.chatWin = append(win, now)
	if rs := []rune(text); len(rs) > ChatMaxLen {
		text = string(rs[:ChatMaxLen])
	}
	h.broadcastLocked(r, map[string]any{
		"t": "chat", "scope": scope, "from": ObserverSlot,
		"name": obs.Name, "text": text, "observer": true,
	})
	return nil
}

// ------------------------------------------------------------ room browser (15a)

// ListPublicRooms returns the browser rows for PUBLIC custom
// rooms still waiting in their lobby: private rooms, queue rooms
// and running matches are never listed. Age is measured on the
// hub's queue clock (mmNow) so tests can pin it.
func (h *Hub) ListPublicRooms() []map[string]any {
	h.mu.Lock()
	defer h.mu.Unlock()
	type row struct {
		at time.Time
		m  map[string]any
	}
	rows := []row{}
	now := h.mmNow()
	for _, r := range h.rooms {
		if !r.Public || r.Queued || r.Ranked || r.InMatch {
			continue
		}
		hostName := ""
		if hp := r.Players[r.Host]; hp != nil {
			hostName = hp.Name
		}
		age := int64(now.Sub(r.CreatedAt) / time.Second)
		if age < 0 {
			age = 0
		}
		rows = append(rows, row{r.CreatedAt, map[string]any{
			"code": r.Code, "name": r.Name, "host": hostName,
			"players": len(r.Players), "max": MaxPlayersPerRoom,
			"biome": r.Biome, "layout": r.Layout,
			"has_password": r.passHash != nil, "allow_obs": r.AllowObs,
			"diplomacy": r.Diplomacy, "obs_delay": r.ObsDelaySec,
			"observers": len(r.Observers), "age_sec": age,
		}})
	}
	sort.Slice(rows, func(i, j int) bool {
		if !rows[i].at.Equal(rows[j].at) {
			return rows[i].at.Before(rows[j].at)
		}
		return rows[i].m["code"].(string) < rows[j].m["code"].(string)
	})
	out := make([]map[string]any, 0, len(rows))
	for _, rw := range rows {
		out = append(out, rw.m)
	}
	return out
}

// ------------------------------------------------------------ host powers (15a)

// KickPlayer removes a player on the host's order and bans their
// identities (account + room name) from rejoining THIS room. The
// removal itself reuses the disconnect path, so a mid-match kick
// freezes/eliminates the slot exactly like a dropout and never
// corrupts slot accounting. Custom rooms only: queue rooms have
// no host powers.
func (h *Hub) KickPlayer(code string, slot, target int) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if r.Queued || r.Ranked {
		return ErrQueuedRoom
	}
	if slot != r.Host {
		return ErrNotHost
	}
	p, ok := r.Players[target]
	if !ok {
		return ErrNotInRoom
	}
	if target == slot {
		return ErrNotHost // the host leaves; they do not kick themselves
	}
	if r.Banned == nil {
		r.Banned = make(map[string]bool)
	}
	for _, k := range banKeys(p.User, p.Name) {
		r.Banned[k] = true
	}
	if p.Connected && p.send != nil {
		sendMsg(p.send, map[string]any{"t": "kicked"})
	}
	h.disconnectLocked(code, target)
	return nil
}

// TransferHost hands the host role to another player of the room
// (custom rooms only). The new host inherits everything the role
// carries: config, start, kick and result reporting.
func (h *Hub) TransferHost(code string, slot, target int) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if r.Queued || r.Ranked {
		return ErrQueuedRoom
	}
	if slot != r.Host {
		return ErrNotHost
	}
	if _, ok := r.Players[target]; !ok {
		return ErrNotInRoom
	}
	if target != r.Host {
		r.Host = target
		h.broadcastRoomLocked(r)
	}
	return nil
}

// longestPresentLocked picks the remaining player who has been in
// the room the longest (smallest join Seq; slot order breaks
// ties, which also covers queue-room players stamped in order).
func longestPresentLocked(r *Room) int {
	best := -1
	var bestSeq int64
	for s, p := range r.Players {
		if best < 0 || p.Seq < bestSeq || (p.Seq == bestSeq && s < best) {
			best, bestSeq = s, p.Seq
		}
	}
	return best
}

// Start validates the lobby and begins the match: assigns teams by
// join order, draws the shared seed and starts the tick loop.
func (h *Hub) Start(code string, slot int) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if slot != r.Host {
		return ErrNotHost
	}
	if r.InMatch {
		return ErrMatchRunning
	}
	if len(r.Players) < MinPlayersPerRoom {
		return ErrTooFew
	}
	for _, p := range r.Players {
		if !p.Ready {
			return ErrNotReady
		}
	}
	h.startMatchLocked(r)
	return nil
}

// startMatchLocked begins the match for a validated room: draws the
// shared seed, broadcasts the config and starts the tick loop. The
// custom-room Start path and the ranked countdown path share it.
func (h *Hub) startMatchLocked(r *Room) {
	seedBig, err := rand.Int(rand.Reader, big.NewInt(1<<31-1))
	if err != nil {
		r.Seed = 12345
	} else {
		r.Seed = seedBig.Int64() + 1
	}
	r.InMatch = true
	r.Tick = 0
	// The character draw (13j): every player is randomly assigned
	// one of the eight mains for this match; their active cosmetic
	// skin (launch: nobody owns one) rides along as appearance.
	for _, p := range r.Players {
		p.Char = h.drawCharLocked()
		p.Skin = h.activeSkinOf(p.User)
	}
	if h.replays != nil {
		rec := &replayBuilder{}
		rec.head = Replay{
			V: 1, GameVersion: GameVersion, Ranked: r.Ranked,
			Room: r.Code, Seed: r.Seed, Biome: r.Biome, Layout: r.Layout,
			Diplomacy: r.Diplomacy,
			StartedAt: h.mmNow().Unix(),
		}
		for _, s := range h.sortedSlotsLocked(r) {
			p := r.Players[s]
			rec.head.Players = append(rec.head.Players, ReplayPlayer{
				Slot: s, Name: p.Name, Team: h.teamOfLocked(r, s), User: p.User,
				Char: p.Char, Skin: NormalizeSkinID(p.Skin),
			})
		}
		r.rec = rec
	}
	start := map[string]any{
		"t": "match_start", "seed": r.Seed,
		"biome": r.Biome, "layout": r.Layout,
		"diplomacy": r.Diplomacy, "obs_delay": r.ObsDelaySec,
		"players": h.playerViewsLocked(r),
	}
	h.broadcastLocked(r, start)
	r.stopTick = make(chan struct{})
	go h.tickLoop(r)
}

func (h *Hub) tickLoop(r *Room) {
	ticker := time.NewTicker(TickInterval)
	defer ticker.Stop()
	for {
		select {
		case <-r.stopTick:
			return
		case <-ticker.C:
			h.mu.Lock()
			if _, alive := h.rooms[r.Code]; alive && r.InMatch {
				r.Tick++
				h.broadcastLocked(r, map[string]any{"t": "tick", "tick": r.Tick})
				// 15e: release observer messages whose spectator
				// delay has elapsed (no-op in live rooms).
				h.flushObsDelayLocked(r, time.Now())
				h.resyncMaintenanceLocked(r)
				// Drop checksum bookkeeping far behind the frontier.
				// The horizon must comfortably exceed the slowest
				// reporter's lag: the referee reports a tick almost
				// immediately, while a loaded client can trail the
				// frontier by several hundred ticks — pruning the
				// referee's lone hash before the set completes makes
				// the canonical comparison impossible (14b).
				for t := range r.checks {
					if t < r.Tick-ChecksumKeepTicks {
						delete(r.checks, t)
						delete(r.desynced, t)
					}
				}
			}
			h.mu.Unlock()
		}
	}
}

// RelayCmd stamps a command with its execution tick (now + input
// delay) and broadcasts it to every player, sender included — the
// sender applies its own command only when the relay returns, which
// is what keeps all clients in the same command order.
func (h *Hub) RelayCmd(code string, slot int, cmd json.RawMessage) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if !r.InMatch {
		return ErrMatchRunning
	}
	if _, ok := r.Players[slot]; !ok {
		return ErrNotInRoom
	}
	exec := r.Tick + InputDelayTicks
	if r.rec != nil && !r.rec.done {
		raw := make(json.RawMessage, len(cmd))
		copy(raw, cmd)
		r.rec.cmds = append(r.rec.cmds, ReplayCmd{From: slot, Tick: exec, Cmd: raw})
	}
	h.broadcastLocked(r, map[string]any{
		"t": "cmd", "from": slot, "tick": exec, "cmd": cmd,
	})
	return nil
}

// ReportChecksum records one client's state hash for a tick; once
// every connected match player has reported for that tick, hashes are
// compared and a mismatch broadcasts a DESYNC notice (once per tick).
func (h *Hub) ReportChecksum(code string, slot int, tick int64, hash string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if !r.InMatch {
		return nil
	}
	m, ok := r.checks[tick]
	if !ok {
		m = make(map[int]string)
		r.checks[tick] = m
	}
	m[slot] = hash
	h.checkTickLocked(r, tick)
	return nil
}

func (h *Hub) checkTickLocked(r *Room, tick int64) {
	m := r.checks[tick]
	expected := 0
	for _, p := range r.Players {
		if p.Connected {
			expected++
		}
	}
	refIn := r.Referee != nil && r.Referee.Connected
	if refIn {
		expected++
	}
	if len(m) < expected {
		return
	}
	// Ranked rooms with a live referee: the REFEREE's hash is
	// canonical. Any connected player disagreeing with it resyncs
	// FROM the referee (the permanent snapshot source).
	if r.Ranked && refIn {
		refHash, ok := m[RefereeChecksumSlot]
		if !ok {
			return
		}
		diverged := make(map[int]bool)
		for s, hash := range m {
			if s < 0 || hash == refHash {
				continue
			}
			if p := r.Players[s]; p != nil && p.Connected {
				diverged[s] = true
			}
		}
		if len(diverged) > 0 && !r.desynced[tick] {
			r.desynced[tick] = true
			h.broadcastLocked(r, map[string]any{"t": "desync", "tick": tick})
			h.openResyncLocked(r, tick, RefereeChecksumSlot, diverged)
		}
		return
	}
	if expected < 2 {
		return
	}
	// Player-majority comparison: the referee's entry (slot -1) is
	// NOT a player vote. Once the referee has disconnected, its
	// stale hash can linger in a late-completing tick map; counting
	// it here produced a phantom "desync" broadcast whose majority
	// math then found no diverged PLAYER and opened no cycle (14b).
	var first string
	diverged := false
	for s, v := range m {
		if s < 0 {
			continue
		}
		if first == "" {
			first = v
		} else if v != first {
			diverged = true
		}
	}
	if diverged && !r.desynced[tick] {
		r.desynced[tick] = true
		h.broadcastLocked(r, map[string]any{"t": "desync", "tick": tick})
		h.beginResyncLocked(r, tick, m)
	}
}

// ------------------------------------------------------------ resync

const (
	ResyncRetryTicks = 100 // re-ask the source for its snapshot
	ResyncFailTicks  = 200 // then give up and release the frozen clients
	// ChecksumKeepTicks is how long per-tick checksum reports are
	// retained while a tick's reporter set is still incomplete
	// (14b): entries are tiny (one short hash per reporter, and
	// reports land only every 30 sim ticks), so a generous horizon
	// costs nothing and guarantees a lagging client's late report
	// still meets the referee's early one.
	ChecksumKeepTicks = 3000
)

// beginResyncLocked opens a resync cycle for a diverging tick: the
// winning checksum is the majority hash (held by more than half of
// the reporting clients); with no majority the HOST's hash wins.
// One holder of the winning hash becomes the snapshot source; every
// client holding a different hash is told to freeze and wait for
// the snapshot, and the rest are notified.
func (h *Hub) beginResyncLocked(r *Room, tick int64, m map[int]string) {
	if r.resync != nil {
		return // one cycle at a time; later divergences queue behind it
	}
	counts := make(map[string]int)
	for s, hash := range m {
		if s < 0 {
			continue // referee entry: not a player vote (14b)
		}
		counts[hash]++
	}
	winner := ""
	for hash, n := range counts {
		if n > len(m)/2 {
			winner = hash
			break
		}
	}
	if winner == "" {
		if hh, ok := m[r.Host]; ok {
			winner = hh
		}
	}
	if winner == "" {
		// No majority and the host did not report: most frequent
		// hash, ties broken by the lowest holding slot.
		best := -1
		for _, s := range h.sortedSlotsLocked(r) {
			if counts[m[s]] > best {
				best = counts[m[s]]
				winner = m[s]
			}
		}
	}
	source := -1
	diverged := make(map[int]bool)
	for _, s := range h.sortedSlotsLocked(r) {
		p := r.Players[s]
		if !p.Connected {
			continue
		}
		if m[s] == winner {
			if source < 0 {
				source = s
			}
		} else if _, reported := m[s]; reported {
			diverged[s] = true
		}
	}
	if source < 0 || len(diverged) == 0 {
		return
	}
	h.openResyncLocked(r, tick, source, diverged)
}

// openResyncLocked starts a resync cycle with a known source (a
// player slot, or RefereeChecksumSlot for the room's referee):
// asks the source for its snapshot and freezes the diverged set.
func (h *Hub) openResyncLocked(r *Room, tick int64, source int, diverged map[int]bool) {
	if r.resync != nil {
		return // one cycle at a time
	}
	log.Printf("resync %s: cycle opened tick=%d source=%d diverged=%d", r.Code, tick, source, len(diverged))
	r.resync = &resyncState{
		tick: tick, source: source, diverged: diverged, atTick: r.Tick,
	}
	h.requestSnapshotLocked(r, tick)
	divSlots := make([]int, 0, len(diverged))
	for s := range diverged {
		divSlots = append(divSlots, s)
	}
	sort.Ints(divSlots)
	for _, s := range divSlots {
		if p := r.Players[s]; p != nil && p.Connected && p.send != nil {
			sendMsg(p.send, map[string]any{"t": "resync", "tick": tick, "source": source})
		}
	}
	for _, s := range h.sortedSlotsLocked(r) {
		if s == source || diverged[s] {
			continue
		}
		if p := r.Players[s]; p != nil && p.Connected && p.send != nil {
			sendMsg(p.send, map[string]any{"t": "resync_notice", "slots": divSlots})
		}
	}
}

// requestSnapshotLocked (re)asks the open cycle's source — player or
// referee — for its snapshot of the diverged tick.
func (h *Hub) requestSnapshotLocked(r *Room, tick int64) {
	rs := r.resync
	if rs == nil {
		return
	}
	msg := map[string]any{"t": "snapshot_request", "tick": tick}
	if rs.source == RefereeChecksumSlot {
		if r.Referee != nil && r.Referee.Connected && r.Referee.send != nil {
			sendMsg(r.Referee.send, msg)
		}
		return
	}
	if sp := r.Players[rs.source]; sp != nil && sp.Connected && sp.send != nil {
		sendMsg(sp.send, msg)
	}
}

// failResyncLocked closes the open cycle by releasing every frozen
// client with resync_failed (source lost or deadline exceeded).
func (h *Hub) failResyncLocked(r *Room) {
	rs := r.resync
	if rs == nil {
		return
	}
	log.Printf("resync %s: cycle FAILED tick=%d source=%d (frozen clients released)", r.Code, rs.tick, rs.source)
	for s := range rs.diverged {
		if p := r.Players[s]; p != nil && p.Connected && p.send != nil {
			sendMsg(p.send, map[string]any{"t": "resync_failed", "tick": rs.tick})
		}
	}
	r.resync = nil
}

// RelaySnapshot forwards a snapshot from the designated source to
// the diverged clients only, closing the resync cycle.
func (h *Hub) RelaySnapshot(code string, slot int, tick int64, state json.RawMessage) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if r.resync == nil || slot != r.resync.source {
		return nil // stale or unauthorised snapshot: ignore quietly
	}
	log.Printf("resync %s: snapshot relayed tick=%d (%d bytes)", r.Code, tick, len(state))
	msg := map[string]any{"t": "snapshot", "tick": tick, "state": state}
	for s := range r.resync.diverged {
		if p := r.Players[s]; p != nil && p.Connected && p.send != nil {
			sendMsg(p.send, msg)
		}
	}
	r.resync = nil
	return nil
}

// resyncMaintenanceLocked drives the retry/give-up clock for an
// open resync cycle (called from the room's tick loop).
func (h *Hub) resyncMaintenanceLocked(r *Room) {
	rs := r.resync
	if rs == nil {
		return
	}
	age := r.Tick - rs.atTick
	if age > ResyncFailTicks {
		h.failResyncLocked(r)
		return
	}
	if age > ResyncRetryTicks && !rs.retried {
		rs.retried = true
		h.requestSnapshotLocked(r, rs.tick)
	}
}

// resyncOnDisconnectLocked keeps an open cycle consistent when a
// participant drops: losing the source aborts the cycle (frozen
// clients are released with resync_failed); losing a diverged
// client just shrinks the waiting set.
func (h *Hub) resyncOnDisconnectLocked(r *Room, slot int) {
	rs := r.resync
	if rs == nil {
		return
	}
	if slot == rs.source {
		h.failResyncLocked(r)
		return
	}
	delete(rs.diverged, slot)
	if len(rs.diverged) == 0 {
		r.resync = nil
	}
}

// deleteRoomLocked removes a room, telling any attached
// observers first (their session otherwise dangles silently).
func (h *Hub) deleteRoomLocked(r *Room) {
	for _, obs := range r.Observers {
		if obs.send != nil {
			sendMsg(obs.send, map[string]any{"t": "room_closed"})
		}
	}
	delete(h.rooms, r.Code)
	if r.Tournament {
		delete(h.tournRooms, tournRoomKey(r.TournID, r.TournMatchID))
	}
	h.roomClosedLocked(r.Code)
}

// Disconnect handles a dropped connection. In the lobby the slot is
// freed (host passes to the longest-present remaining player; an
// empty room is deleted). Mid-match the slot stays but is marked
// disconnected and PLAYER_LEFT is broadcast — remaining players
// keep playing.
func (h *Hub) Disconnect(code string, slot int) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.disconnectLocked(code, slot)
}

// disconnectLocked is Disconnect with the hub lock already held
// (KickPlayer reuses the exact same removal semantics).
func (h *Hub) disconnectLocked(code string, slot int) {
	r, ok := h.rooms[code]
	if !ok {
		return
	}
	p, ok := r.Players[slot]
	if !ok {
		return
	}
	if !r.InMatch {
		delete(r.Players, slot)
		if len(r.Players) == 0 {
			h.deleteRoomLocked(r)
			return
		}
		if r.Host == slot {
			// 15a: the host role passes to the LONGEST-PRESENT
			// remaining player (was: lowest slot).
			r.Host = longestPresentLocked(r)
		}
		h.broadcastRoomLocked(r)
		return
	}
	p.Connected = false
	p.Ready = false
	h.resyncOnDisconnectLocked(r, slot)
	h.broadcastLocked(r, map[string]any{"t": "player_left", "slot": slot})
	if slot == r.Host && !r.Ranked {
		// 15a: a dropped host mid-match hands the role to the
		// longest-present CONNECTED player, so the match keeps a
		// result reporter (custom + normal-queue rooms). Ranked
		// rooms never move it — the referee owns their results.
		best := -1
		var bestSeq int64
		for s, pl := range r.Players {
			if pl.Connected && (best < 0 || pl.Seq < bestSeq ||
				(pl.Seq == bestSeq && s < best)) {
				best, bestSeq = s, pl.Seq
			}
		}
		if best >= 0 {
			r.Host = best
		}
	}
	h.broadcastRoomLocked(r)
	anyLeft := false
	for _, pl := range r.Players {
		if pl.Connected {
			anyLeft = true
		}
	}
	if !anyLeft {
		close(r.stopTick)
		h.deleteRoomLocked(r)
		return
	}
	// A departure can complete pending checksum ticks.
	for t := range r.checks {
		h.checkTickLocked(r, t)
	}
}

// ------------------------------------------------------------ chat

const (
	ChatMaxLen     = 200 // runes; longer texts are truncated server-side
	ChatRateCount  = 5   // messages …
	ChatRateWindow = 2 * time.Second
)

// RelayChat delivers one chat message inside a room. Scopes:
// "lobby" and "match" go to every player in the room, "team" only
// to the sender's team-mates (the server owns the team table).
// Over-rate messages are dropped silently. Chat is pure relay: it
// never touches match state.
func (h *Hub) RelayChat(code string, slot int, scope, text string) error {
	return h.RelayChatEx(code, slot, scope, text, nil)
}

// RelayChatEx is RelayChat with the 15b diplomacy extension: in a
// diplomacy room, a "team" message carries the sender's CURRENT
// ally slots (alliance state lives in the clients' shared sim —
// the relay cannot derive it), and the message goes to the sender
// plus exactly those slots instead of the fixed-team set. In any
// other room the targets are ignored and the fixed-team routing
// below applies. (Receiving clients additionally drop a team line
// whose sender is not their current ally, so a stale or forged
// target list can never put words in a non-ally's team channel.)
func (h *Hub) RelayChatEx(code string, slot int, scope, text string, targets []int) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	p, ok := r.Players[slot]
	if !ok {
		return ErrNotInRoom
	}
	now := time.Now()
	win := p.chatWin[:0]
	for _, t := range p.chatWin {
		if now.Sub(t) < ChatRateWindow {
			win = append(win, t)
		}
	}
	if len(win) >= ChatRateCount {
		p.chatWin = win
		return nil // silently dropped
	}
	p.chatWin = append(win, now)
	if rs := []rune(text); len(rs) > ChatMaxLen {
		text = string(rs[:ChatMaxLen])
	}
	msg := map[string]any{
		"t": "chat", "scope": scope, "from": slot, "name": p.Name, "text": text,
	}
	if scope == "team" {
		if r.Diplomacy && len(targets) > 0 {
			// 15b: alliance channel — sender + declared allies.
			want := map[int]bool{slot: true}
			for _, ts := range targets {
				want[ts] = true
			}
			for _, pl := range r.Players {
				if pl.Connected && pl.send != nil && want[pl.Slot] {
					sendMsg(pl.send, msg)
				}
			}
			return nil
		}
		team := h.teamOfLocked(r, slot)
		for _, pl := range r.Players {
			if pl.Connected && pl.send != nil && h.teamOfLocked(r, pl.Slot) == team {
				sendMsg(pl.send, msg)
			}
		}
		return nil
	}
	h.broadcastLocked(r, msg)
	return nil
}

// teamOfLocked resolves a slot's faction team from the room's
// current player set (same derivation as the player views).
func (h *Hub) teamOfLocked(r *Room, slot int) int {
	slots := h.sortedSlotsLocked(r)
	teams := teamsFor(len(slots))
	for i, s := range slots {
		if s == slot {
			return teams[i]
		}
	}
	return slot
}

func sendMsg(s sender, msg map[string]any) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	s.SendText(data)
}

// AttachAccount binds a room slot to a logged-in account: the
// display name locks to the account name and the player view gains
// the account flag (shown as the "Loại" column in the lobby).
func (h *Hub) AttachAccount(code string, slot int, user string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	p, ok := r.Players[slot]
	if !ok {
		return ErrNotInRoom
	}
	p.User = user
	p.Account = user != ""
	if user != "" {
		// The room label is the account's DISPLAY name (13r) —
		// lobby rows, chat and in-match overhead names all read
		// it from the player view / match_start payload.
		p.Name = user
		if h.acc != nil {
			p.Name = h.acc.DisplayNameOf(user)
		}
	}
	h.broadcastRoomLocked(r)
	return nil
}

// drawCharLocked picks one main character uniformly at random
// (the match draw — pool is the eight mains for every player;
// cosmetic skins are never drawn). Crypto randomness: the pick
// is broadcast in match_start, so all clients agree by payload,
// not by shared state.
func (h *Hub) drawCharLocked() string {
	n, err := rand.Int(rand.Reader, big.NewInt(int64(len(MainChars))))
	if err != nil {
		return MainChars[0]
	}
	return MainChars[n.Int64()]
}

// activeSkinOf resolves a player's active cosmetic skin from
// their account ("" for guests and for anyone who owns none —
// the launch state).
func (h *Hub) activeSkinOf(user string) string {
	if user == "" || h.acc == nil {
		return ""
	}
	a, ok := h.acc.store.GetAccount(user)
	if !ok {
		return ""
	}
	return EffectiveActiveSkin(a)
}

// ------------------------------------------------------------ match results

var ErrResultRecorded = errors.New("match result already recorded")

// RecordMatchResult banks a finished match. Only the room's HOST
// may report (the trust model for this stage — see README), and
// only once per room. Returns username -> won for every
// account-bound player in the room; guests are skipped.
func (h *Hub) RecordMatchResult(code string, slot int, winnerTeam int, elimTicks []int64) (map[string]bool, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return nil, err
	}
	if r.Ranked {
		// Ranked results are accepted from the referee ONLY — a
		// player-sent result for a ranked room banks nothing.
		return nil, ErrRankedRoom
	}
	if slot != r.Host {
		return nil, ErrNotHost
	}
	if !r.InMatch {
		return nil, ErrMatchRunning
	}
	if r.resultRecorded {
		return nil, ErrResultRecorded
	}
	r.resultRecorded = true
	out := make(map[string]bool)
	for _, p := range r.Players {
		if p.Account && p.User != "" {
			out[p.User] = h.teamOfLocked(r, p.Slot) == winnerTeam
		}
	}
	h.finishReplayLocked(r, winnerTeam, nil, elimTicks)
	return out, nil
}

var ErrBadWinners = errors.New("winner slots must be a non-empty set of the room's slots")

// RecordMatchResultSlots banks a finished DIPLOMACY custom match
// whose winners are an explicit slot set (15b shared allied
// victory — the survivors were mutually allied, so no single
// winning team exists). Same trust model as RecordMatchResult:
// host-only, once per room, custom rooms only; queue rooms
// (normal/ranked) refuse structurally, exactly like the 15a host
// powers. Returns username -> won like RecordMatchResult.
func (h *Hub) RecordMatchResultSlots(code string, slot int, winnerSlots []int, elimTicks []int64) (map[string]bool, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return nil, err
	}
	if r.Ranked {
		return nil, ErrRankedRoom
	}
	if r.Queued {
		return nil, ErrQueuedRoom
	}
	if slot != r.Host {
		return nil, ErrNotHost
	}
	if !r.InMatch {
		return nil, ErrMatchRunning
	}
	if r.resultRecorded {
		return nil, ErrResultRecorded
	}
	if len(winnerSlots) == 0 {
		return nil, ErrBadWinners
	}
	winners := make(map[int]bool)
	for _, ws := range winnerSlots {
		if _, ok := r.Players[ws]; !ok {
			return nil, ErrBadWinners
		}
		winners[ws] = true
	}
	r.resultRecorded = true
	out := make(map[string]bool)
	for _, p := range r.Players {
		if p.Account && p.User != "" {
			out[p.User] = winners[p.Slot]
		}
	}
	// The replay header names ONE winning team: the first
	// winner's (the recording's diplomacy flag + command log
	// carry the real outcome; playback re-derives the set).
	first := winnerSlots[0]
	for _, ws := range winnerSlots {
		if ws < first {
			first = ws
		}
	}
	h.finishReplayLocked(r, h.teamOfLocked(r, first), nil, elimTicks)
	return out, nil
}

// roomClosedLocked runs hub-level cleanup when a room disappears
// (orchestrator reaps the room's referee process, if any).
func (h *Hub) roomClosedLocked(code string) {
	if h.OnRoomClosed != nil {
		h.OnRoomClosed(code)
	}
}

func lowestSlot(r *Room) int {
	best := 1 << 30
	for s := range r.Players {
		if s < best {
			best = s
		}
	}
	return best
}

func (h *Hub) sortedSlotsLocked(r *Room) []int {
	slots := make([]int, 0, len(r.Players))
	for s := range r.Players {
		slots = append(slots, s)
	}
	sort.Ints(slots)
	return slots
}

func (h *Hub) playerViewsLocked(r *Room) []map[string]any {
	slots := h.sortedSlotsLocked(r)
	teams := teamsFor(len(slots))
	out := make([]map[string]any, 0, len(slots))
	for i, s := range slots {
		p := r.Players[s]
		out = append(out, map[string]any{
			"slot": p.Slot, "name": p.Name, "ready": p.Ready,
			"connected": p.Connected, "team": teams[i], "account": p.Account,
			"char": NormalizeCharID(p.Char), "skin": NormalizeSkinID(p.Skin),
		})
	}
	return out
}

func (h *Hub) broadcastRoomLocked(r *Room) {
	obsNames := make([]string, 0, len(r.Observers))
	for _, o := range r.Observers {
		obsNames = append(obsNames, o.Name)
	}
	h.broadcastLocked(r, map[string]any{
		"t": "room", "code": r.Code, "host": r.Host,
		"in_match": r.InMatch, "biome": r.Biome, "layout": r.Layout,
		"ranked": r.Ranked,
		// 15a: the room's public face — name, visibility,
		// password + observer flags, live config and the
		// observer roster, so joiners see all of it pre-ready.
		"room_name": r.Name, "public": r.Public,
		"has_password": r.passHash != nil, "allow_obs": r.AllowObs,
		"diplomacy": r.Diplomacy, "obs_delay": r.ObsDelaySec,
		"observers": obsNames,
		"players":   h.playerViewsLocked(r),
	})
}

func (h *Hub) broadcastLocked(r *Room, msg map[string]any) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	for _, p := range r.Players {
		if p.Connected && p.send != nil {
			p.send.SendText(data) // best-effort; a dead conn reports via Disconnect
		}
	}
	// The referee is a room participant too: it consumes the same
	// tick/command stream the players do.
	if r.Referee != nil && r.Referee.Connected && r.Referee.send != nil {
		r.Referee.send.SendText(data)
	}
	// Observers (15a) receive the same stream — that is the
	// whole point of watching — but hold no slot in it.
	//
	// 15e: in a room with a spectator delay, match-phase traffic
	// for observers is not sent but queued per observer with a
	// release time of now+delay (flushObsDelayLocked delivers it
	// from the room's tick loop). Players and the referee are
	// never delayed. The one exception is observer-authored
	// chat, which stays realtime (it carries no game state).
	// Lobby-phase traffic is never delayed either: the delay
	// exists to hide live match state, and InMatch only turns on
	// at match start.
	delay := r.ObsDelaySec > 0 && r.InMatch && !isObserverChatMsg(msg)
	for _, o := range r.Observers {
		if o.send == nil {
			continue
		}
		if delay {
			o.delayQ = append(o.delayQ, obsDelayedMsg{
				at:   time.Now().Add(time.Duration(r.ObsDelaySec) * time.Second),
				data: data,
			})
			continue
		}
		o.send.SendText(data)
	}
}

// isObserverChatMsg reports whether msg is chat authored by an
// observer (the RelayObserverChat shape: t=chat carrying the
// observer flag). Player chat is ordinary match traffic and IS
// delayed for observers in a delayed room (15e).
func isObserverChatMsg(msg map[string]any) bool {
	if msg["t"] != "chat" {
		return false
	}
	ob, _ := msg["observer"].(bool)
	return ob
}

// flushObsDelayLocked delivers every due delayed message to
// each observer of r, strictly in queue order — the observer's
// stream stays a constant-delay shift of the live stream.
// `now` is a parameter so tests can drive the buffer with a
// synthetic clock at the production delay values. The caller
// holds h.mu.
func (h *Hub) flushObsDelayLocked(r *Room, now time.Time) {
	if r.ObsDelaySec <= 0 {
		return
	}
	for _, o := range r.Observers {
		for len(o.delayQ) > 0 && !o.delayQ[0].at.After(now) {
			m := o.delayQ[0]
			o.delayQ = o.delayQ[1:]
			if o.send != nil {
				o.send.SendText(m.data)
			}
		}
	}
}

// RoomCount reports how many rooms exist (status page).
func (h *Hub) RoomCount() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.rooms)
}

// TeamOf returns the faction team of a slot in the room's current
// player set (used by tests and the views above).
func (h *Hub) TeamOf(code string, slot int) (int, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return -1, err
	}
	slots := h.sortedSlotsLocked(r)
	teams := teamsFor(len(slots))
	for i, s := range slots {
		if s == slot {
			return teams[i], nil
		}
	}
	return -1, ErrNotInRoom
}

// ------------------------------------------------- referee (ranked rooms)

// RefereeTokenHashOf hashes a raw referee token for storage/compare.
func RefereeTokenHashOf(token string) [32]byte {
	return sha256.Sum256([]byte(token))
}

// RefereeJoin attaches a dedicated referee process to a ranked room.
// The one-time token is compared by hash in constant time; a wrong
// token (or a non-ranked room) is rejected and attaches nothing.
func (h *Hub) RefereeJoin(code, token string, send sender) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(strings.ToUpper(strings.TrimSpace(code)))
	if err != nil {
		return err
	}
	if !r.Ranked {
		return ErrRefereeDenied
	}
	sum := RefereeTokenHashOf(token)
	if subtle.ConstantTimeCompare(sum[:], r.RefereeTokenHash[:]) != 1 {
		return ErrRefereeDenied
	}
	if r.Referee != nil && r.Referee.Connected {
		return ErrRefereeBusy
	}
	r.Referee = &refereeConn{send: send, Connected: true}
	h.broadcastRoomLocked(r)
	h.maybeStartCountdownLocked(r)
	return nil
}

// ReportRefereeChecksum files the referee's canonical hash for a
// tick under RefereeChecksumSlot and runs the comparison.
func (h *Hub) ReportRefereeChecksum(code string, tick int64, hash string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return err
	}
	if !r.InMatch || r.Referee == nil || !r.Referee.Connected {
		return nil
	}
	m, ok := r.checks[tick]
	if !ok {
		m = make(map[int]string)
		r.checks[tick] = m
	}
	m[RefereeChecksumSlot] = hash
	h.checkTickLocked(r, tick)
	return nil
}

// RefereeDisconnect marks the room's referee gone. An open resync
// cycle sourced from the referee fails (frozen clients release);
// the room itself degrades to player-majority checksums.
func (h *Hub) RefereeDisconnect(code string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	if !ok || r.Referee == nil {
		return
	}
	r.Referee.Connected = false
	r.Referee.send = nil
	if r.resync != nil && r.resync.source == RefereeChecksumSlot {
		h.failResyncLocked(r)
	}
	h.broadcastRoomLocked(r)
}

// RecordRefereeResult banks a finished RANKED match on the
// referee's word alone (the caller in main.go has already verified
// the reporting connection IS this room's referee). Only once per
// room. Returns username -> won for the room's players.
func (h *Hub) RecordRefereeResult(code string, winnerTeam int, reason string, elimTicks []int64) (map[string]bool, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return nil, err
	}
	if !r.Ranked {
		return nil, ErrNotRankedRoom
	}
	if !r.InMatch {
		return nil, ErrMatchRunning
	}
	if r.resultRecorded {
		return nil, ErrResultRecorded
	}
	r.resultRecorded = true
	r.ResultReason = reason
	h.finishReplayLocked(r, winnerTeam, nil, elimTicks)
	out := make(map[string]bool)
	for _, p := range r.Players {
		if p.Account && p.User != "" {
			out[p.User] = h.teamOfLocked(r, p.Slot) == winnerTeam
		}
	}
	return out, nil
}

// validatePlacementsLocked checks that placements is an exact
// permutation of the room's slots (index 0 = 1st place, last =
// first eliminated). Returns slot -> placement (1-based).
func (h *Hub) validatePlacementsLocked(r *Room, placements []int) (map[int]int, error) {
	if len(placements) != len(r.Players) || len(placements) < 2 {
		return nil, ErrBadPlacement
	}
	out := make(map[int]int, len(placements))
	for i, s := range placements {
		if _, ok := r.Players[s]; !ok {
			return nil, ErrBadPlacement
		}
		if _, dup := out[s]; dup {
			return nil, ErrBadPlacement
		}
		out[s] = i + 1
	}
	return out, nil
}

// placementsByUserLocked converts slot placements to the account
// view: username -> placement for account-bound players, plus the
// usernames ordered 1st -> last (guests hold slots but bank
// nothing, so they are absent from both).
func (h *Hub) placementsByUserLocked(r *Room, placements []int, bySlot map[int]int) (map[string]int, []string) {
	byUser := make(map[string]int)
	ordered := make([]string, 0, len(placements))
	for _, s := range placements {
		p := r.Players[s]
		if p != nil && p.Account && p.User != "" {
			byUser[p.User] = bySlot[s]
			ordered = append(ordered, p.User)
		}
	}
	return byUser, ordered
}

// RecordRefereePlacements banks a finished RANKED free-for-all
// match on the referee's word alone: placements lists every slot
// from 1st to last; disconnectSlots names the slots whose
// elimination came from a disconnect (reputation penalty). Only
// once per room. Returns username -> placement (1-based) plus the
// account usernames ordered 1st -> last.
func (h *Hub) RecordRefereePlacements(code string, placements []int, disconnectSlots []int, elimTicks []int64) (map[string]int, []string, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return nil, nil, err
	}
	if !r.Ranked {
		return nil, nil, ErrNotRankedRoom
	}
	if !r.InMatch {
		return nil, nil, ErrMatchRunning
	}
	if r.resultRecorded {
		return nil, nil, ErrResultRecorded
	}
	bySlot, err := h.validatePlacementsLocked(r, placements)
	if err != nil {
		return nil, nil, err
	}
	r.resultRecorded = true
	r.ResultReason = "elimination"
	for _, s := range disconnectSlots {
		if _, ok := bySlot[s]; ok && s != placements[0] {
			r.ResultReason = "disconnect"
			break
		}
	}
	h.finishReplayLocked(r, h.teamOfLocked(r, placements[0]), placements, elimTicks)
	byUser, ordered := h.placementsByUserLocked(r, placements, bySlot)
	return byUser, ordered, nil
}

// RecordMatchPlacements banks a finished QUEUED normal match from
// the host's placement report (same trust model as
// RecordMatchResult: host-only, once per room). Custom rooms do
// not take placements — they report a winning team as before.
// Returns username -> placement (1-based).
func (h *Hub) RecordMatchPlacements(code string, slot int, placements []int, elimTicks []int64) (map[string]int, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, err := h.roomLocked(code)
	if err != nil {
		return nil, err
	}
	if r.Ranked {
		return nil, ErrRankedRoom
	}
	if !r.Queued {
		return nil, ErrBadPlacement
	}
	if slot != r.Host {
		return nil, ErrNotHost
	}
	if !r.InMatch {
		return nil, ErrMatchRunning
	}
	if r.resultRecorded {
		return nil, ErrResultRecorded
	}
	bySlot, err := h.validatePlacementsLocked(r, placements)
	if err != nil {
		return nil, err
	}
	r.resultRecorded = true
	h.finishReplayLocked(r, h.teamOfLocked(r, placements[0]), placements, elimTicks)
	byUser, _ := h.placementsByUserLocked(r, placements, bySlot)
	return byUser, nil
}

// NotifyRankedResult delivers one player's personal rank_result
// payload (their own ladder movement) to their slot in a room.
// Best effort: a disconnected player simply never sees it.
func (h *Hub) NotifyRankedResult(code, user string, payload map[string]any) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	if !ok {
		return
	}
	for _, p := range r.Players {
		if p.User == user && p.Connected && p.send != nil {
			sendMsg(p.send, payload)
		}
	}
}

// IsRankedRoom reports whether a room is a ranked (referee-owned) one.
func (h *Hub) IsRankedRoom(code string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	return ok && r.Ranked
}

// systemChatLocked sends a chat line from the server itself (slot
// -1, displayed as "Hệ thống") — used by the ranked countdown.
func (h *Hub) systemChatLocked(r *Room, scope, text string) {
	h.broadcastLocked(r, map[string]any{
		"t": "chat", "scope": scope, "from": -1, "name": "Hệ thống", "text": text,
	})
}
