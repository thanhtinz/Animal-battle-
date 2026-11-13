package main

// Replay recording (KE-HOACH 13h): the relay already sees every
// command of every match it serves, stamped with its execution
// tick — so a replay is just the header (full match config) plus
// that stamped command log. Playback re-simulates the match from
// the seed + config and feeds the commands back at their ticks
// (the client's lockstep drive does the rest; no state snapshots
// are stored at all).
//
// Retention: a global LRU cap (ReplayCap newest matches). A
// replay stays fetchable while it is inside the cap; per-account
// history windows (20 entries) reference replays by id, and a
// replay whose id scrolled out answers "not found" — the client
// greys its play button only when it never had an id, and shows
// the server error otherwise.
//
// Access: ranked replays may be fetched by ANY logged-in account
// (they are ladder-public). Custom-room replays are restricted
// to the match's account participants; guests cannot fetch at
// all ("đăng nhập để xem lại") — a deliberate, documented choice.

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sort"
	"sync"
)

// GameVersion tags every replay header. Bump together with the
// client's Net.GAME_VERSION when the sim changes incompatibly;
// the client warns (but still plays) on a mismatch.
const GameVersion = "v13"

// ReplayCap is the global retention cap (newest matches kept).
const ReplayCap = 200

// ReplayCmd is one stamped command in a replay log.
type ReplayCmd struct {
	From int             `json:"from"`
	Tick int64           `json:"tick"`
	Cmd  json.RawMessage `json:"cmd"`
}

// ReplayEvent is one timeline marker sealed into a recording
// (14a): a player's elimination, at the tick the reporter's own
// sim recorded it. Age-ups and hero summons are NOT stored here —
// the client derives those from the command log itself; only
// eliminations are un-derivable from the log (they are sim
// outcomes, not commands), so only they ride this sidecar.
type ReplayEvent struct {
	Tick int64  `json:"tick"`
	Kind string `json:"kind"` // "elim"
	Slot int    `json:"slot"`
}

// ReplayPlayer is one header row of a replay.
type ReplayPlayer struct {
	Slot int    `json:"slot"`
	Name string `json:"name"`
	Team int    `json:"team"`
	User string `json:"user,omitempty"` // account name; "" for guests
	// Char is the character the player was assigned in that match
	// (13j); Skin their active cosmetic skin ("" = none) —
	// presentation metadata so playback fields the same heroes.
	Char string `json:"char,omitempty"`
	Skin string `json:"skin,omitempty"`
}

// Replay is one recorded match.
type Replay struct {
	ID            string         `json:"id"`
	V             int            `json:"v"`
	GameVersion   string         `json:"game_version"`
	Ranked        bool           `json:"ranked"`
	Room          string         `json:"room"`
	Seed          int64          `json:"seed"`
	Biome         string         `json:"biome"`
	Layout        string         `json:"layout"`
	Diplomacy     bool           `json:"diplomacy,omitempty"` // 15b: playback re-arms the diplomacy sim
	Players       []ReplayPlayer `json:"players"`
	StartedAt     int64          `json:"started_at"`
	FinishedAt    int64          `json:"finished_at"`
	WinnerTeam    int            `json:"winner_team"`
	FinalTick     int64          `json:"final_tick"`
	DurationTicks int64          `json:"duration_ticks"`
	Events        []ReplayEvent  `json:"events,omitempty"`
	Cmds          []ReplayCmd    `json:"cmds"`
}

// Participants lists the account usernames that played (guests
// excluded — they hold no account to authorise with).
func (rp *Replay) Participants() []string {
	out := []string{}
	for _, p := range rp.Players {
		if p.User != "" {
			out = append(out, p.User)
		}
	}
	return out
}

// ReplayStore persists recorded matches.
type ReplayStore interface {
	Put(rp *Replay) error
	Get(id string) (*Replay, bool)
	Count() int
}

// replayBook is the shared in-memory index + LRU order behind
// both store implementations.
type replayBook struct {
	byID  map[string]*Replay
	order []string // oldest first
}

func (b *replayBook) put(rp *Replay) {
	if _, dup := b.byID[rp.ID]; dup {
		return
	}
	b.byID[rp.ID] = rp
	b.order = append(b.order, rp.ID)
	for len(b.order) > ReplayCap {
		oldest := b.order[0]
		b.order = b.order[1:]
		delete(b.byID, oldest)
	}
}

func (b *replayBook) get(id string) (*Replay, bool) {
	rp, ok := b.byID[id]
	return rp, ok
}

// MemReplayStore keeps replays in memory only (tests).
type MemReplayStore struct {
	mu sync.Mutex
	replayBook
}

func NewMemReplayStore() *MemReplayStore {
	return &MemReplayStore{replayBook: replayBook{byID: make(map[string]*Replay)}}
}

func (s *MemReplayStore) Put(rp *Replay) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.put(rp)
	return nil
}

func (s *MemReplayStore) Get(id string) (*Replay, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.get(id)
}

func (s *MemReplayStore) Count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.byID)
}

// FileReplayStore persists replays as one JSON document (the
// payloads are command logs — small). Writes go through a temp
// file + rename so a crash cannot truncate the archive.
type FileReplayStore struct {
	mu   sync.Mutex
	path string
	replayBook
}

type replayFile struct {
	Replays map[string]*Replay `json:"replays"`
	Order   []string           `json:"order"`
}

func NewFileReplayStore(path string) (*FileReplayStore, error) {
	s := &FileReplayStore{path: path,
		replayBook: replayBook{byID: make(map[string]*Replay)}}
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return s, nil
		}
		return nil, err
	}
	var f replayFile
	if err := json.Unmarshal(raw, &f); err != nil {
		return nil, fmt.Errorf("replay store %s: %w", path, err)
	}
	for _, id := range f.Order {
		if rp, ok := f.Replays[id]; ok {
			s.put(rp)
		}
	}
	return s, nil
}

func (s *FileReplayStore) Put(rp *Replay) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.put(rp)
	return s.flushLocked()
}

func (s *FileReplayStore) Get(id string) (*Replay, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.get(id)
}

func (s *FileReplayStore) Count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.byID)
}

func (s *FileReplayStore) flushLocked() error {
	raw, err := json.Marshal(replayFile{Replays: s.byID, Order: s.order})
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

// newReplayID mints an opaque replay id.
func newReplayID() string {
	var b [6]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "rp_static"
	}
	return "rp_" + hex.EncodeToString(b[:])
}

// replayBuilder accumulates one in-progress match recording.
type replayBuilder struct {
	head Replay
	cmds []ReplayCmd
	done bool
}

// buildReplayEvents validates reporter-supplied elimination
// ticks (slot-indexed; -1 or missing = never eliminated) against
// the room and, when a placement list is present, against the
// placement order, and returns the markers to seal. ANY
// inconsistency drops the whole sidecar (nil): the events are
// garnish for the timeline — banking must never depend on them.
//
// Placement consistency (free-for-all): the winner was never
// eliminated (-1); everyone else has a tick > 0; and ticks are
// non-increasing down the placement list (a better placement fell
// no earlier than the next one; equal ticks = same-tick falls).
// Without placements (custom team result) only the range is
// checked — a winning team's member may well have fallen.
func buildReplayEvents(r *Room, placements []int, elimTicks []int64) []ReplayEvent {
	if len(elimTicks) == 0 {
		return nil
	}
	tickOf := make(map[int]int64, len(r.Players))
	for s := range r.Players {
		v := int64(-1)
		if s < len(elimTicks) {
			v = elimTicks[s]
		}
		if v != -1 && (v < 1 || v > r.Tick) {
			return nil
		}
		tickOf[s] = v
	}
	if placements != nil {
		if tickOf[placements[0]] != -1 {
			return nil
		}
		for i := 1; i < len(placements); i++ {
			if tickOf[placements[i]] < 1 {
				return nil
			}
			if i >= 2 && tickOf[placements[i]] > tickOf[placements[i-1]] {
				return nil
			}
		}
	}
	var out []ReplayEvent
	for s, v := range tickOf {
		if v > 0 {
			out = append(out, ReplayEvent{Tick: v, Kind: "elim", Slot: s})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Tick < out[j].Tick })
	return out
}

// finishReplayLocked seals the room's recording (if any) into
// the store with the match result and returns its id ("" when
// recording is off or the match had already been sealed).
// elimTicks/placements form the 14a events sidecar (see
// buildReplayEvents); pass nil from result paths that have no
// placement list.
func (h *Hub) finishReplayLocked(r *Room, winnerTeam int, placements []int, elimTicks []int64) string {
	if h.replays == nil || r.rec == nil || r.rec.done {
		return ""
	}
	r.rec.done = true
	rp := r.rec.head
	rp.ID = newReplayID()
	rp.WinnerTeam = winnerTeam
	rp.FinalTick = r.Tick
	rp.DurationTicks = r.Tick
	rp.Events = buildReplayEvents(r, placements, elimTicks)
	rp.FinishedAt = h.mmNow().Unix()
	rp.Cmds = r.rec.cmds
	if rp.Cmds == nil {
		rp.Cmds = []ReplayCmd{}
	}
	if err := h.replays.Put(&rp); err != nil {
		log.Printf("replay: store failed for room %s: %v", r.Code, err)
		return ""
	}
	r.lastReplayID = rp.ID
	log.Printf("replay %s stored: room %s ranked=%v cmds=%d ticks=%d",
		rp.ID, r.Code, rp.Ranked, len(rp.Cmds), rp.FinalTick)
	return rp.ID
}

// RoomReplayID returns the replay id sealed for a room ("" if none).
func (h *Hub) RoomReplayID(code string) string {
	h.mu.Lock()
	defer h.mu.Unlock()
	if r, ok := h.rooms[code]; ok {
		return r.lastReplayID
	}
	return ""
}

// NotifyRoomReplay hands every connected player of a room the
// replay id sealed for their match (14a) so the result screen's
// Xem lại button can open it. Used for QUEUE matches (normal +
// ranked); custom rooms keep their original custom_replay
// hand-out. Best effort like NotifyRankedResult: a disconnected
// player never sees it.
func (h *Hub) NotifyRoomReplay(code string) {
	if rid := h.RoomReplayID(code); rid != "" {
		h.NotifyRoom(code, map[string]any{
			"t": "match_replay", "replay_id": rid, "room": code,
		})
	}
}

// NotifyRoom delivers a payload to every connected player of a
// room (used for the custom-room replay id hand-out).
func (h *Hub) NotifyRoom(code string, payload map[string]any) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	if !ok {
		return
	}
	for _, p := range r.Players {
		if p.Connected && p.send != nil {
			sendMsg(p.send, payload)
		}
	}
}
