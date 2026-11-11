package main

// Ranked matchmaking (P4 stage 3; 13z — Tín: "Đấu thường, đấu
// hạng là 8 người đấu với nhau"). Logged-in players join a FIFO
// queue; a match forms only when EIGHT players can be gathered.
// The group anchors on the longest-waiting player and fills with
// the closest-MMR players inside the MMR window that grows with
// wait time (±100 at join, +50 every 10s, capped at ±600). An
// 8-player group becomes a ranked free-for-all room owned by a
// dedicated referee process (see referee.go for orchestration,
// hub.go for the referee role). Results are placements 1..8.

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"math/big"
	"sort"
	"strings"
	"time"
)

const (
	QueueWindowStart = 100
	QueueWindowStep  = 50
	QueueWindowEvery = 10 * time.Second
	QueueWindowCap   = 600
	RankedMode1v1    = "1v1"
	// QueueMatchSize is how many players a queue match needs
	// (13z): both queues play 8-player free-for-all.
	QueueMatchSize = 8
)

// RankedRotation is the ranked map pool: the three biomes on the
// plains layout. Ranked matches now draw from it at RANDOM per
// match (13j) — the name survives from the old rotation era.
var RankedRotation = []struct{ Biome, Layout string }{
	{"grassland", "plains"},
	{"desert", "plains"},
	{"snow", "plains"},
}

type queueEntry struct {
	sess   *session
	user   string
	mmr    int // effective MMR at join time
	joined time.Time
	name   string // display name resolved at join (normal queue: guests have no account to resolve from)
}

// queueWindow is the MMR tolerance for a player who has waited `wait`.
func queueWindow(wait time.Duration) int {
	w := QueueWindowStart + QueueWindowStep*int(wait/QueueWindowEvery)
	if w > QueueWindowCap {
		w = QueueWindowCap
	}
	return w
}

// QueueJoin enqueues a logged-in session for ranked 1v1. Guests are
// rejected with ErrRankedLogin (the client shows a clear hint).
// Returns the player's profile (MMR + ladder view for the queue UI).
func (h *Hub) QueueJoin(s *session, mode string) (Profile, error) {
	if mode != RankedMode1v1 {
		return Profile{}, ErrBadQueueMode
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if s.user == "" {
		return Profile{}, ErrRankedLogin
	}
	if s.in {
		return Profile{}, ErrAlreadyIn
	}
	for _, e := range h.queue {
		if e.sess == s {
			return Profile{}, ErrAlreadyQueued
		}
	}
	for _, e := range h.nqueue {
		if e.sess == s {
			return Profile{}, ErrAlreadyQueued
		}
	}
	if h.acc == nil {
		return Profile{}, ErrRankedLogin
	}
	prof, ok := h.acc.Profile(s.user)
	if !ok {
		return Profile{}, ErrRankedLogin
	}
	h.queue = append(h.queue, &queueEntry{
		sess: s, user: s.user, mmr: prof.MMR, joined: h.mmNow(),
	})
	return prof, nil
}

// QueueLeave drops a session from whichever queue holds it — the
// ranked queue or the normal queue (cancel button or disconnect;
// the client has a single queue_leave for both). Reports whether
// it was queued anywhere.
func (h *Hub) QueueLeave(s *session) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for i, e := range h.queue {
		if e.sess == s {
			h.queue = append(h.queue[:i], h.queue[i+1:]...)
			return true
		}
	}
	for i, e := range h.nqueue {
		if e.sess == s {
			h.nqueue = append(h.nqueue[:i], h.nqueue[i+1:]...)
			return true
		}
	}
	return false
}

// QueueLen is the current queue depth (status/tests).
func (h *Hub) QueueLen() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.queue)
}

// SendQueueStatus pushes a {queue_status} update to every queued
// session when the found-count of their queue's forming group
// changed since the last push (13z — the waiting screen shows
// "Đã tìm thấy X/8 người chơi"). For the ranked queue the count
// is the size of the group that would form around the anchor
// right now (anchor + in-window candidates) — the honest state
// of the match being gathered; for the normal queue it is the
// raw FIFO depth. Both cap at QueueMatchSize. The main loop
// calls this right after the pairing passes.
func (h *Hub) SendQueueStatus() {
	h.mu.Lock()
	defer h.mu.Unlock()
	rankedFound := 0
	if len(h.queue) > 0 {
		rankedFound = len(h.rankedGroupLocked())
	}
	if rankedFound != h.lastRankedFound {
		h.lastRankedFound = rankedFound
		if rankedFound > 0 {
			data, err := json.Marshal(map[string]any{
				"t": "queue_status", "queue": "ranked",
				"found": rankedFound, "need": QueueMatchSize,
			})
			if err == nil {
				for _, e := range h.queue {
					if snd := e.sess.senderOrConn(); snd != nil {
						snd.SendText(data)
					}
				}
			}
		}
	}
	normalFound := len(h.nqueue)
	if normalFound > QueueMatchSize {
		normalFound = QueueMatchSize
	}
	if normalFound != h.lastNormalFound {
		h.lastNormalFound = normalFound
		if normalFound > 0 {
			data, err := json.Marshal(map[string]any{
				"t": "queue_status", "queue": "normal",
				"found": normalFound, "need": QueueMatchSize,
			})
			if err == nil {
				for _, e := range h.nqueue {
					if snd := e.sess.senderOrConn(); snd != nil {
						snd.SendText(data)
					}
				}
			}
		}
	}
}

// TryPairAll runs group-formation passes until no more 8-player
// groups form. A group anchors on the oldest queued player
// (strict FIFO head) and fills with the CLOSEST-MMR candidates
// inside the window — a candidate is in range when the MMR gap to
// the anchor fits EITHER player's current window (the longer
// waiter's window governs, the same rule the 1v1 pairing used).
// Fewer than QueueMatchSize in range means no match yet: the
// anchor keeps waiting and its window keeps growing.
func (h *Hub) TryPairAll() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for len(h.queue) >= QueueMatchSize {
		if !h.tryFormGroupLocked() {
			return
		}
	}
}

// rankedGroupLocked computes the group that would form around the
// queue head right now: the anchor plus every in-window candidate
// ordered by MMR closeness (ties: earlier join first), capped at
// QueueMatchSize. It does not mutate the queue.
func (h *Hub) rankedGroupLocked() []*queueEntry {
	if len(h.queue) == 0 {
		return nil
	}
	now := h.mmNow()
	head := h.queue[0]
	headWin := queueWindow(now.Sub(head.joined))
	type cand struct {
		e    *queueEntry
		diff int
	}
	cands := make([]cand, 0, len(h.queue)-1)
	for _, other := range h.queue[1:] {
		win := headWin
		if w := queueWindow(now.Sub(other.joined)); w > win {
			win = w
		}
		diff := head.mmr - other.mmr
		if diff < 0 {
			diff = -diff
		}
		if diff <= win {
			cands = append(cands, cand{e: other, diff: diff})
		}
	}
	sort.SliceStable(cands, func(i, j int) bool { return cands[i].diff < cands[j].diff })
	group := []*queueEntry{head}
	for _, c := range cands {
		if len(group) >= QueueMatchSize {
			break
		}
		group = append(group, c.e)
	}
	return group
}

func (h *Hub) tryFormGroupLocked() bool {
	group := h.rankedGroupLocked()
	if len(group) < QueueMatchSize {
		return false
	}
	inGroup := make(map[*queueEntry]bool, len(group))
	for _, e := range group {
		inGroup[e] = true
	}
	rest := h.queue[:0]
	for _, e := range h.queue {
		if !inGroup[e] {
			rest = append(rest, e)
		}
	}
	h.queue = rest
	h.createRankedRoomLocked(group)
	return true
}

// rankedMapPick draws a ranked match's map at random (13j — Tín
// replaced the fixed biome rotation with a true random pick per
// ranked match).
func (h *Hub) rankedMapPick() (pick struct{ Biome, Layout string }) {
	n, err := rand.Int(rand.Reader, big.NewInt(int64(len(RankedRotation))))
	if err != nil {
		return RankedRotation[0]
	}
	return RankedRotation[n.Int64()]
}

// createRankedRoomLocked turns a formed group of QueueMatchSize
// into a ranked free-for-all room: slot 0 = the anchor (the
// longest-waiting player), slots 1..7 follow in MMR-closeness
// order; biome/layout are drawn at random per match; a one-time
// referee token is generated (only its hash is stored) and a
// referee process is spawned with the raw token. Every client is
// told via match_found and drops into the normal room flow
// (ranked rooms skip ready/start — the referee starts the match
// after a countdown).
func (h *Hub) createRankedRoomLocked(group []*queueEntry) {
	code := h.newCodeLocked()
	pick := h.rankedMapPick()
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		log.Printf("ranked %s: token generation failed: %v", code, err)
		return
	}
	token := hex.EncodeToString(tokenBytes)
	r := &Room{
		Code:             code,
		Host:             0,
		Biome:            pick.Biome,
		Layout:           pick.Layout,
		Players:          make(map[int]*Player),
		checks:           make(map[int64]map[int]string),
		desynced:         make(map[int64]bool),
		Ranked:           true,
		Queued:           true,
		RefereeTokenHash: RefereeTokenHashOf(token),
	}
	// Characters are assigned by draw in startMatchLocked; the
	// players' cosmetic skins resolve there too (activeSkinOf).
	nameOf := func(user string) string {
		if h.acc != nil {
			return h.acc.DisplayNameOf(user)
		}
		return user
	}
	views := make([]map[string]any, 0, len(group))
	for slot, e := range group {
		r.Players[slot] = &Player{Slot: slot, Name: nameOf(e.user), User: e.user, Account: true,
			Connected: true, send: e.sess.senderOrConn(), Seq: h.nextSeqLocked()}
		rankText := ""
		if h.acc != nil {
			if prof, ok := h.acc.Profile(e.user); ok {
				rankText = prof.Rank.RankText
			}
		}
		views = append(views, map[string]any{
			"slot": slot, "user": e.user, "display_name": nameOf(e.user),
			"mmr": e.mmr, "rank_text": rankText,
		})
	}
	h.rooms[code] = r
	for slot, e := range group {
		e.sess.code, e.sess.slot, e.sess.in = code, slot, true
		data, err := json.Marshal(map[string]any{
			"t": "match_found", "code": code, "slot": slot, "ranked": true,
			"queue": "ranked", "biome": r.Biome, "layout": r.Layout,
			"players": views,
			// Legacy single-opponent field (the first other
			// player) — older client logs read it; the room
			// broadcast right after carries the full roster.
			"opponent": views[1],
		})
		if err == nil {
			e.sess.senderOrConn().SendText(data)
		}
	}
	h.broadcastRoomLocked(r)
	names := make([]string, 0, len(group))
	for _, e := range group {
		names = append(names, e.user)
	}
	log.Printf("ranked: group of %d [%s] -> room %s (%s/%s)",
		len(group), strings.Join(names, ", "), code, r.Biome, r.Layout)
	if h.Orch != nil {
		if err := h.Orch.SpawnReferee(code, token); err != nil {
			log.Printf("ranked %s: referee spawn failed: %v", code, err)
		}
	} else {
		log.Printf("ranked %s: no orchestrator configured; referee must join manually", code)
	}
}

// maybeStartCountdownLocked fires the ranked start sequence once
// the referee is attached and both players are connected: three
// chat system messages (3 · 2 · 1, one per second), then the match
// starts. Ranked rooms have no ready/host-start step.
func (h *Hub) maybeStartCountdownLocked(r *Room) {
	if !r.Ranked || r.InMatch || r.countdown {
		return
	}
	if r.Referee == nil || !r.Referee.Connected {
		return
	}
	for _, p := range r.Players {
		if !p.Connected {
			return
		}
	}
	if len(r.Players) < MinPlayersPerRoom {
		return
	}
	r.countdown = true
	code := r.Code
	go h.rankedCountdown(code)
}

func (h *Hub) rankedCountdown(code string) {
	steps := []string{
		"Trận xếp hạng bắt đầu sau 3 giây…",
		"2…",
		"1…",
	}
	for _, text := range steps {
		h.mu.Lock()
		r, ok := h.rooms[code]
		if !ok || r.InMatch {
			h.mu.Unlock()
			return
		}
		h.systemChatLocked(r, "match", text)
		h.mu.Unlock()
		time.Sleep(time.Second)
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	if !ok {
		return
	}
	r.countdown = false
	// Someone may have dropped during the countdown: abort cleanly
	// instead of starting a broken match.
	connected := 0
	for _, p := range r.Players {
		if p.Connected {
			connected++
		}
	}
	if connected < MinPlayersPerRoom || r.Referee == nil || !r.Referee.Connected {
		for _, p := range r.Players {
			if p.Connected && p.send != nil {
				sendMsg(p.send, map[string]any{
					"t": "error", "msg": "Đối thủ hoặc trọng tài đã mất kết nối — trận xếp hạng bị hủy",
				})
			}
		}
		// The room stays as a dead one-player lobby; the remaining
		// client's leave/disconnect cleans it up via Disconnect.
		return
	}
	h.startMatchLocked(r)
}

// ---------------------------------------------------------- normal queue (13t)

// Normal (unranked) matchmaking, 13t — Tín moved Đấu Thường from
// the single-player setup view to online matchmaking: same painted
// waiting screen as ranked, but a plain FIFO queue with NO MMR
// window, NO referee and NO rank/star effects. Guests are allowed.
// A paired room is an ordinary room (Ranked=false) flagged Queued:
// the host (slot 0) reports the result through the custom-room
// channel, which banks wins/losses + history only (RecordMatch
// never touches MMR or the ladder).

const NormalMode1v1 = "1v1-normal"

// normalDisplayName resolves the in-room display name for a normal
// queue entry: accounts speak with their account display name;
// guests use the name they queued with (trimmed, capped), falling
// back to "Khách".
func (h *Hub) normalDisplayName(s *session, guestName string) string {
	if s.user != "" && h.acc != nil {
		return h.acc.DisplayNameOf(s.user)
	}
	name := strings.TrimSpace(guestName)
	if r := []rune(name); len(r) > 24 {
		name = string(r[:24])
	}
	if name == "" {
		name = "Khách"
	}
	return name
}

// NormalQueueJoin enqueues any session (guest or account) for an
// unranked 1v1. A session may sit in at most one queue at a time.
func (h *Hub) NormalQueueJoin(s *session, guestName string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if s.in {
		return ErrAlreadyIn
	}
	for _, e := range h.queue {
		if e.sess == s {
			return ErrAlreadyQueued
		}
	}
	for _, e := range h.nqueue {
		if e.sess == s {
			return ErrAlreadyQueued
		}
	}
	h.nqueue = append(h.nqueue, &queueEntry{
		sess: s, user: s.user, joined: h.mmNow(),
		name: h.normalDisplayName(s, guestName),
	})
	return nil
}

// NormalQueueLen is the current normal-queue depth (status/tests).
func (h *Hub) NormalQueueLen() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.nqueue)
}

// TryPairNormalAll groups the normal queue strictly FIFO: the
// eight oldest waiting players form a match (no rating window).
// Fewer than eight queued means everyone keeps waiting.
func (h *Hub) TryPairNormalAll() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for len(h.nqueue) >= QueueMatchSize {
		group := make([]*queueEntry, QueueMatchSize)
		copy(group, h.nqueue[:QueueMatchSize])
		h.nqueue = h.nqueue[QueueMatchSize:]
		h.createNormalRoomLocked(group)
	}
}

// createNormalRoomLocked turns a formed normal group of
// QueueMatchSize into a queued free-for-all room: slot order is
// FIFO order; slot 0 is also the room host (and therefore the
// result reporter, per the custom-room trust model); the map is
// drawn at random from the same pool ranked uses. Every client
// gets match_found with ranked=false, then the start countdown
// runs — there is no ready/host-start step and no referee.
func (h *Hub) createNormalRoomLocked(group []*queueEntry) {
	code := h.newCodeLocked()
	pick := h.rankedMapPick()
	r := &Room{
		Code:     code,
		Host:     0,
		Biome:    pick.Biome,
		Layout:   pick.Layout,
		Players:  make(map[int]*Player),
		checks:   make(map[int64]map[int]string),
		desynced: make(map[int64]bool),
		Queued:   true,
	}
	mk := func(e *queueEntry, slot int) *Player {
		return &Player{Slot: slot, Name: e.name, User: e.user,
			Account: e.user != "", Connected: true,
			send: e.sess.senderOrConn(), Seq: h.nextSeqLocked()}
	}
	views := make([]map[string]any, 0, len(group))
	for slot, e := range group {
		r.Players[slot] = mk(e, slot)
		views = append(views, map[string]any{
			"slot": slot, "user": e.user, "display_name": e.name,
		})
	}
	h.rooms[code] = r
	for slot, e := range group {
		e.sess.code, e.sess.slot, e.sess.in = code, slot, true
		data, err := json.Marshal(map[string]any{
			"t": "match_found", "code": code, "slot": slot, "ranked": false,
			"queue": "normal", "biome": r.Biome, "layout": r.Layout,
			"players":  views,
			"opponent": map[string]any{"user": group[1].user, "display_name": group[1].name},
		})
		if err == nil {
			e.sess.senderOrConn().SendText(data)
		}
	}
	h.broadcastRoomLocked(r)
	r.countdown = true
	names := make([]string, 0, len(group))
	for _, e := range group {
		names = append(names, e.name)
	}
	log.Printf("normal: group of %d [%s] -> room %s (%s/%s)",
		len(group), strings.Join(names, ", "), code, r.Biome, r.Layout)
	go h.normalCountdown(code)
}

// normalCountdown is the ranked countdown without the referee: the
// same three system chat beats, then the match starts — unless a
// player dropped meanwhile, in which case the start aborts cleanly
// (the room stays as a dead one-player lobby, exactly like ranked).
func (h *Hub) normalCountdown(code string) {
	steps := []string{
		"Trận đấu thường bắt đầu sau 3 giây…",
		"2…",
		"1…",
	}
	for _, text := range steps {
		h.mu.Lock()
		r, ok := h.rooms[code]
		if !ok || r.InMatch {
			h.mu.Unlock()
			return
		}
		h.systemChatLocked(r, "match", text)
		h.mu.Unlock()
		time.Sleep(time.Second)
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	if !ok {
		return
	}
	r.countdown = false
	connected := 0
	for _, p := range r.Players {
		if p.Connected {
			connected++
		}
	}
	if connected < MinPlayersPerRoom {
		for _, p := range r.Players {
			if p.Connected && p.send != nil {
				sendMsg(p.send, map[string]any{
					"t": "error", "msg": "Đối thủ đã mất kết nối — trận đấu thường bị hủy",
				})
			}
		}
		return
	}
	h.startMatchLocked(r)
}
