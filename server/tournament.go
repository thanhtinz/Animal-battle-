package main

// Tournament system (15h) — the final item of the Online
// Multiplayer GDD roadmap. Tournaments are SERVER-side state:
// a Tournaments service over the same Store seam as accounts
// (FileStore today, persisted in the same JSON file), and every
// match plays in a DEDICATED room that reuses the ranked
// REFEREE trust model — the room is created with Ranked=true
// plus the tournament markers, a one-time referee token is
// issued, and the ONLY result channel is the room's referee
// (hub.RecordRefereeResult). Players can never report a
// tournament result: RecordMatchResult refuses Ranked rooms,
// and the referee branch in main.go routes tournament rooms
// to TournamentMatchResult BEFORE the ranked placements path,
// so a tournament result never touches MMR, stars or the
// ladder. Played matches bank plain W/L through
// Accounts.RecordMatch — the same values custom matches use —
// which is also where their XP comes from (10 XP per recorded
// match + 20 per win, the existing derived level values).
//
// Bracket correctness lives here, not in the client: the
// client renders the views this file builds. Formats:
//
//   solo  (1v1) | team (2v2 — the registering captain brings
//                  one partner account; the captain checks in
//                  and launches for the whole entry)
//   single_elim    next-power-of-2 bracket, standard seeding
//                  (1vN, …), byes to the top seeds
//   double_elim    winners + losers brackets, grand final
//                  WITH a reset match when the losers-side
//                  champion wins the first grand final
//   round_robin    one group, circle-method rounds; standings
//                  by wins, then aggregate match score, then
//                  seed (registration order)
//   group_knockout 2 groups (snake split by seed), round-robin
//                  inside each group, top 2 per group cross
//                  into semifinals (A1 v B2, B1 v A2) + final
//
// State machine: open (registrations) -> checkin (bracket
// generated; registration closed; per-match check-in) ->
// running (first match live) -> finished. The creator may
// cancel from open/checkin only. There is NO global admin in
// this game: the tournament's creator is the arbiter of its
// disputes — that is the honest scope.
//
// Defaults chosen here (all flagged "chờ Tín chốt" in
// KE-HOACH 15h): walkover window 10 minutes after the other
// side checked in (server clock, swept deterministically);
// registration-order seeding; sizes 4/8/16 entries with a
// 2-entry minimum (4 for group_knockout); per-match check-in
// per round; dispute replay resolution UNBANKS the voided
// match's W/L (Accounts.RecordMatchRevert) before the rematch.

import (
	"crypto/rand"
	"errors"
	"fmt"
	"log"
	"math/big"
	"sort"
	"strings"
	"sync"
	"time"
)

// ------------------------------------------------------------ constants

const (
	// TournWalkoverWindow is how long a checked-in side waits
	// for its opponent before the server awards the walkover.
	TournWalkoverWindow = 10 * time.Minute
	// TournMaxNameRunes bounds a tournament's display name.
	TournMaxNameRunes = 40
	// TournLogCap bounds the per-tournament audit log.
	TournLogCap = 60
)

var (
	ErrTournNotFound    = errors.New("Không tìm thấy giải đấu")
	ErrTournLogin       = errors.New("Cần đăng nhập tài khoản để dùng giải đấu")
	ErrTournBadName     = errors.New("Tên giải phải có 1–40 ký tự")
	ErrTournBadFormat   = errors.New("Thể thức giải không hợp lệ")
	ErrTournBadBracket  = errors.New("Kiểu bracket không hợp lệ")
	ErrTournBadSize     = errors.New("Số suất phải là 4, 8 hoặc 16")
	ErrTournNotOpen     = errors.New("Giải không còn nhận đăng ký")
	ErrTournFull        = errors.New("Giải đã đủ số suất")
	ErrTournAlreadyIn   = errors.New("Tài khoản đã có trong một đội của giải này")
	ErrTournNotIn       = errors.New("Bạn không tham gia giải này")
	ErrTournNotCaptain  = errors.New("Chỉ đội trưởng mới làm được việc này")
	ErrTournNotCreator  = errors.New("Chỉ người tạo giải mới làm được việc này")
	ErrTournBadPartner  = errors.New("Đồng đội không hợp lệ (tài khoản phải tồn tại, khác bạn và chưa vào đội nào)")
	ErrTournTooFew      = errors.New("Chưa đủ đội để bắt đầu giải")
	ErrTournBadState    = errors.New("Giải đang ở trạng thái không cho phép việc này")
	ErrTournMatchState  = errors.New("Trận chưa sẵn sàng hoặc đã kết thúc")
	ErrTournNotYourSide = errors.New("Bạn không thuộc trận này")
	ErrTournFrozen      = errors.New("Trận đang bị đóng băng vì khiếu nại ở vòng trước")
	ErrTournDisputeLate = errors.New("Trận sau đã đấu — không thể khiếu nại nữa")
	ErrTournNoReplay    = errors.New("Trận này không có bản ghi để đối chiếu")
	ErrTournRoomBusy    = errors.New("Bạn đang ở trong một phòng khác")
)

// ------------------------------------------------------------ model

// TournEntry is one registered side of a tournament: one
// account (solo) or two (team; Members[0] is the captain who
// registered the entry and acts for it).
type TournEntry struct {
	ID      int      `json:"id"` // seed = registration order (1-based)
	Members []string `json:"members"`
}

// TournMatch is one bracket match. A/B hold entry ids; a side
// is "set" once its feeder resolved (ASet/BSet) — a set side
// with entry 0 is VACANT (a bye slot), which is how
// non-power-of-2 fields propagate byes through a bracket.
type TournMatch struct {
	ID    int    `json:"id"`
	Stage string `json:"stage"` // main | wb | lb | gf | rr | ga | gb | ko
	Round int    `json:"round"`
	Label string `json:"label"`
	A     int    `json:"a"`
	B     int    `json:"b"`
	ASet  bool   `json:"a_set"`
	BSet  bool   `json:"b_set"`
	// State: pending (sides unknown / gate closed) -> ready
	// (playable once both sides checked in) -> live -> done.
	// disputed = a done match under dispute (frozen downstream).
	State     string `json:"state"`
	CheckA    bool   `json:"check_a"`
	CheckB    bool   `json:"check_b"`
	CheckAtA  int64  `json:"check_at_a"`
	CheckAtB  int64  `json:"check_at_b"`
	Winner    int    `json:"winner"` // entry id; 0 = none / double-vacant
	ScoreA    int    `json:"score_a"`
	ScoreB    int    `json:"score_b"`
	Played    bool   `json:"played"`   // result came from a played match (W/L banked)
	Bye       bool   `json:"bye"`      // auto-resolved against a vacant side
	Walkover  bool   `json:"walkover"` // awarded without play (no-show)
	RoomCode  string `json:"room_code,omitempty"`
	ReplayID  string `json:"replay_id,omitempty"`
	DisputeBy string `json:"dispute_by,omitempty"`
	// Feeds: where the winner / loser go (match id + side:
	// 0 = A, 1 = B). 0 = no feed.
	WinTo   int `json:"win_to"`
	WinPos  int `json:"win_pos"`
	LoseTo  int `json:"lose_to"`
	LosePos int `json:"lose_pos"`
}

// Tournament is the full persisted state of one tournament.
type Tournament struct {
	ID          string        `json:"id"`
	Name        string        `json:"name"`
	Creator     string        `json:"creator"` // account username
	Format      string        `json:"format"`  // solo | team
	Bracket     string        `json:"bracket"` // single_elim | double_elim | round_robin | group_knockout
	Size        int           `json:"size"`    // entry capacity: 4 | 8 | 16
	State       string        `json:"state"`   // open | checkin | running | finished | cancelled
	CreatedAt   int64         `json:"created_at"`
	Entries     []*TournEntry `json:"entries"`
	Matches     []*TournMatch `json:"matches"`
	Champion    int           `json:"champion"` // entry id, 0 = undecided
	RunnerUp    int           `json:"runner_up"`
	RewardsDone bool          `json:"rewards_done"`
	GroupSeeded bool          `json:"group_seeded,omitempty"` // group_knockout: KO sides set
	Log         []string      `json:"log,omitempty"`
	NextMatch   int           `json:"next_match"` // next match id to allocate
}

func (t *Tournament) entry(id int) *TournEntry {
	for _, e := range t.Entries {
		if e.ID == id {
			return e
		}
	}
	return nil
}

func (t *Tournament) match(id int) *TournMatch {
	for _, m := range t.Matches {
		if m.ID == id {
			return m
		}
	}
	return nil
}

func (t *Tournament) entryOfUser(user string) *TournEntry {
	for _, e := range t.Entries {
		for _, u := range e.Members {
			if u == user {
				return e
			}
		}
	}
	return nil
}

func (t *Tournament) logf(format string, args ...any) {
	t.Log = append(t.Log, fmt.Sprintf(format, args...))
	if len(t.Log) > TournLogCap {
		t.Log = t.Log[len(t.Log)-TournLogCap:]
	}
}

// copyTournament deep-copies a tournament for the store seam
// (the FileStore account copies are shallow; bracket state
// mutates slices of structs, so tournaments copy deep).
func copyTournament(t *Tournament) *Tournament {
	if t == nil {
		return nil
	}
	cp := *t
	cp.Entries = make([]*TournEntry, len(t.Entries))
	for i, e := range t.Entries {
		ec := *e
		ec.Members = append([]string(nil), e.Members...)
		cp.Entries[i] = &ec
	}
	cp.Matches = make([]*TournMatch, len(t.Matches))
	for i, m := range t.Matches {
		mc := *m
		cp.Matches[i] = &mc
	}
	cp.Log = append([]string(nil), t.Log...)
	return &cp
}

func newTournID(store Store) string {
	for {
		b := make([]byte, 6)
		for i := range b {
			n, err := rand.Int(rand.Reader, big.NewInt(int64(len(codeAlphabet))))
			if err != nil {
				b[i] = codeAlphabet[i%len(codeAlphabet)]
			} else {
				b[i] = codeAlphabet[n.Int64()]
			}
		}
		id := "T" + string(b)
		if _, ok := store.GetTournament(id); !ok {
			return id
		}
	}
}

// ------------------------------------------------------------ brackets

// pow2ceil returns the smallest power of two >= n (min 2).
func pow2ceil(n int) int {
	p := 2
	for p < n {
		p *= 2
	}
	return p
}

// seedOrder returns the standard bracket position order of
// seeds 1..p (p a power of two): adjacent positions pair up
// so seed 1 meets the weakest seed, 2 the second-weakest…
func seedOrder(p int) []int {
	if p == 2 {
		return []int{1, 2}
	}
	prev := seedOrder(p / 2)
	out := make([]int, 0, p)
	for _, s := range prev {
		out = append(out, s, p+1-s)
	}
	return out
}

// roundLabel names a knockout round by its distance from the
// final (0 = final).
func roundLabel(fromEnd int) string {
	switch fromEnd {
	case 0:
		return "Chung kết"
	case 1:
		return "Bán kết"
	case 2:
		return "Tứ kết"
	case 3:
		return "Vòng 1/8"
	default:
		return "Vòng 1/16"
	}
}

// genSingleElim builds a single-elimination tree over the
// entries (stage "main"). P = next power of two >= field;
// positions beyond the field are vacant (byes for top seeds).
// Returns the matches with ids 1.. in round order.
func genSingleElim(entries []*TournEntry) []*TournMatch {
	n := len(entries)
	p := pow2ceil(n)
	pos := seedOrder(p)
	rounds := 0
	for x := p; x > 1; x /= 2 {
		rounds++
	}
	var matches []*TournMatch
	nextID := 1
	prevIDs := []int{}
	for r := 1; r <= rounds; r++ {
		count := p >> r
		ids := []int{}
		for i := 0; i < count; i++ {
			m := &TournMatch{ID: nextID, Stage: "main", Round: r, State: "pending",
				Label: roundLabel(rounds - r)}
			nextID++
			if r == 1 {
				sa, sb := pos[2*i], pos[2*i+1]
				m.A, m.ASet = seedEntry(entries, sa), true
				m.B, m.BSet = seedEntry(entries, sb), true
			}
			if r < rounds {
				// Winner feeds the next round; position parity
				// picks the side.
				m.WinTo = -1 // patched below once next round exists
				m.WinPos = i % 2
			}
			ids = append(ids, m.ID)
			matches = append(matches, m)
		}
		// Patch the previous round's WinTo now that this
		// round's ids exist.
		if r > 1 {
			byID := map[int]*TournMatch{}
			for _, m := range matches {
				byID[m.ID] = m
			}
			for j, pid := range prevIDs {
				byID[pid].WinTo = ids[j/2]
			}
		}
		prevIDs = ids
	}
	return matches
}

// seedEntry maps a 1-based seed to its entry id (0 = vacant
// slot beyond the registered field).
func seedEntry(entries []*TournEntry, seed int) int {
	if seed >= 1 && seed <= len(entries) {
		return entries[seed-1].ID
	}
	return 0
}

// genDoubleElim builds winners + losers brackets and the
// grand final over P = max(4, pow2ceil(field)) slots.
// Winners-bracket losers drop into the losers bracket in the
// classic alternating pattern (drop-in rounds alternate with
// consolidation rounds); drop-in pairings are REVERSED so a
// player does not immediately rematch the opponent who just
// beat them. Grand-final reset is created dynamically.
func genDoubleElim(entries []*TournEntry) []*TournMatch {
	n := len(entries)
	p := pow2ceil(n)
	if p < 4 {
		p = 4
	}
	pos := seedOrder(p)
	rounds := 0
	for x := p; x > 1; x /= 2 {
		rounds++
	}
	var matches []*TournMatch
	nextID := 1
	newMatch := func(stage string, round int, label string) *TournMatch {
		m := &TournMatch{ID: nextID, Stage: stage, Round: round, State: "pending", Label: label}
		nextID++
		matches = append(matches, m)
		return m
	}
	// Winners bracket tree (same shape as single elim).
	wbRounds := [][]*TournMatch{}
	for r := 1; r <= rounds; r++ {
		count := p >> r
		row := []*TournMatch{}
		for i := 0; i < count; i++ {
			m := newMatch("wb", r, roundLabel(rounds-r))
			if r == 1 {
				m.A, m.ASet = seedEntry(entries, pos[2*i]), true
				m.B, m.BSet = seedEntry(entries, pos[2*i+1]), true
			}
			row = append(row, m)
		}
		if r > 1 {
			for j, pm := range wbRounds[r-2] {
				pm.WinTo, pm.WinPos = row[j/2].ID, j%2
			}
		}
		wbRounds = append(wbRounds, row)
	}
	wbFinal := wbRounds[rounds-1][0]
	// Losers bracket. cur holds the matches whose WINNERS form
	// the current LB survivor line, in bracket order.
	feedLose := func(src *TournMatch, dst *TournMatch, pos int) {
		src.LoseTo, src.LosePos = dst.ID, pos
	}
	var cur []*TournMatch
	// LB round 1: WB round-1 losers paired among themselves.
	lbRound := 1
	{
		row := []*TournMatch{}
		wb1 := wbRounds[0]
		for i := 0; i+1 < len(wb1); i += 2 {
			m := newMatch("lb", lbRound, fmt.Sprintf("Nhánh thua · Vòng %d", lbRound))
			feedLose(wb1[i], m, 0)
			feedLose(wb1[i+1], m, 1)
			row = append(row, m)
		}
		cur = row
		lbRound++
	}
	for wbr := 2; wbr <= rounds; wbr++ {
		// Drop-in round: LB survivors vs losers of WB round
		// wbr (reversed pairing — anti-rematch).
		drop := wbRounds[wbr-1]
		row := []*TournMatch{}
		for i, cm := range cur {
			m := newMatch("lb", lbRound, fmt.Sprintf("Nhánh thua · Vòng %d", lbRound))
			cm.WinTo, cm.WinPos = m.ID, 0
			feedLose(drop[len(drop)-1-i], m, 1)
			row = append(row, m)
		}
		cur = row
		lbRound++
		if len(cur) > 1 {
			// Consolidation round: survivors pair off.
			row2 := []*TournMatch{}
			for i := 0; i+1 < len(cur); i += 2 {
				m := newMatch("lb", lbRound, fmt.Sprintf("Nhánh thua · Vòng %d", lbRound))
				cur[i].WinTo, cur[i].WinPos = m.ID, 0
				cur[i+1].WinTo, cur[i+1].WinPos = m.ID, 1
				row2 = append(row2, m)
			}
			cur = row2
			lbRound++
		}
	}
	// cur[0] is the losers-bracket final (its B side came from
	// the WB final loser in the last drop-in round).
	lbFinal := cur[0]
	gf := newMatch("gf", 1, "Chung kết tổng")
	wbFinal.WinTo, wbFinal.WinPos = gf.ID, 0
	lbFinal.WinTo, lbFinal.WinPos = gf.ID, 1
	return matches
}

// genRoundRobin builds one all-play-all stage with the circle
// method (rounds gate sequentially: round r+1 unlocks when
// round r is fully done). A field of odd size pads a vacant
// dummy — that entry rests that round (no match created).
func genRoundRobin(entries []*TournEntry, stage, labelPrefix string) []*TournMatch {
	line := make([]int, 0, len(entries)+1)
	for _, e := range entries {
		line = append(line, e.ID)
	}
	if len(line)%2 == 1 {
		line = append(line, 0) // dummy = resting side
	}
	m := len(line)
	var matches []*TournMatch
	nextID := 1
	for r := 0; r < m-1; r++ {
		for i := 0; i < m/2; i++ {
			a, b := line[i], line[m-1-i]
			if a == 0 || b == 0 {
				continue // resting round for the other entry
			}
			matches = append(matches, &TournMatch{
				ID: nextID, Stage: stage, Round: r + 1, State: "pending",
				Label: fmt.Sprintf("%s · Vòng %d · Trận %d", labelPrefix, r+1, i+1),
				A:     a, ASet: true, B: b, BSet: true,
			})
			nextID++
		}
		// Rotate: first element fixed, the rest cycle right.
		last := line[m-1]
		copy(line[2:], line[1:m-1])
		line[1] = last
	}
	return matches
}

// genGroupKnockout builds two snake-split round-robin groups
// (stages ga/gb) plus an unset knockout stage (semis + final)
// whose sides are seeded from the group standings once both
// groups complete (see refreshLocked).
func genGroupKnockout(entries []*TournEntry) []*TournMatch {
	var ga, gb []*TournEntry
	for i, e := range entries {
		// Snake draft: A B B A A B B A …
		if i%4 == 0 || i%4 == 3 {
			ga = append(ga, e)
		} else {
			gb = append(gb, e)
		}
	}
	matches := genRoundRobin(ga, "ga", "Bảng A")
	next := len(matches) + 1
	for _, m := range genRoundRobin(gb, "gb", "Bảng B") {
		m.ID = next
		next++
		matches = append(matches, m)
	}
	sf1 := &TournMatch{ID: next, Stage: "ko", Round: 1, State: "pending", Label: "Bán kết 1 (A1 – B2)"}
	next++
	sf2 := &TournMatch{ID: next, Stage: "ko", Round: 1, State: "pending", Label: "Bán kết 2 (B1 – A2)"}
	next++
	fin := &TournMatch{ID: next, Stage: "ko", Round: 2, State: "pending", Label: "Chung kết"}
	sf1.WinTo, sf1.WinPos = fin.ID, 0
	sf2.WinTo, sf2.WinPos = fin.ID, 1
	return append(matches, sf1, sf2, fin)
}

// ------------------------------------------------------------ service

// Tournaments is the tournament service: all state moves
// through its mutex and is persisted through the Store after
// every mutation (same honesty as Accounts: the file store
// flushes atomically per write).
type Tournaments struct {
	mu    sync.Mutex
	store Store
	acc   *Accounts
	now   func() time.Time // test seam
}

func NewTournaments(store Store, acc *Accounts) *Tournaments {
	return &Tournaments{store: store, acc: acc, now: time.Now}
}

func (ts *Tournaments) save(t *Tournament) {
	if err := ts.store.PutTournament(t); err != nil {
		log.Printf("tournament %s: save failed: %v", t.ID, err)
	}
}

func (ts *Tournaments) load(id string) (*Tournament, error) {
	t, ok := ts.store.GetTournament(strings.ToUpper(strings.TrimSpace(id)))
	if !ok {
		return nil, ErrTournNotFound
	}
	return t, nil
}

// Get returns one tournament's current state (post-refresh).
func (ts *Tournaments) Get(id string) (*Tournament, bool) {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return nil, false
	}
	ts.refreshLocked(t)
	return t, true
}

// List returns all tournaments, newest first (cancelled ones
// included; the view layer decides what to show).
func (ts *Tournaments) List() []*Tournament {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	all := ts.store.Tournaments()
	for _, t := range all {
		ts.refreshLocked(t)
	}
	sort.Slice(all, func(i, j int) bool { return all[i].CreatedAt > all[j].CreatedAt })
	return all
}

var tournSizes = map[int]bool{4: true, 8: true, 16: true}

// Create opens a new tournament in state "open". The creator
// is NOT auto-registered (they register like everyone else if
// they want to play).
func (ts *Tournaments) Create(creator, name, format, bracket string, size int) (*Tournament, error) {
	if creator == "" {
		return nil, ErrTournLogin
	}
	name = strings.TrimSpace(name)
	if n := len([]rune(name)); n < 1 || n > TournMaxNameRunes {
		return nil, ErrTournBadName
	}
	if format != "solo" && format != "team" {
		return nil, ErrTournBadFormat
	}
	switch bracket {
	case "single_elim", "double_elim", "round_robin", "group_knockout":
	default:
		return nil, ErrTournBadBracket
	}
	if !tournSizes[size] {
		return nil, ErrTournBadSize
	}
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t := &Tournament{
		ID: newTournID(ts.store), Name: name, Creator: creator,
		Format: format, Bracket: bracket, Size: size, State: "open",
		CreatedAt: ts.now().Unix(), NextMatch: 1,
	}
	t.logf("%s tạo giải", creator)
	ts.save(t)
	return t, nil
}

// Register adds the caller (solo) or the caller + partner
// (team; caller is captain) to an open tournament.
func (ts *Tournaments) Register(id, user, partner string) error {
	if user == "" {
		return ErrTournLogin
	}
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if t.State != "open" {
		return ErrTournNotOpen
	}
	if len(t.Entries) >= t.Size {
		return ErrTournFull
	}
	if t.entryOfUser(user) != nil {
		return ErrTournAlreadyIn
	}
	members := []string{user}
	if t.Format == "team" {
		partner = strings.TrimSpace(partner)
		if partner == "" || partner == user {
			return ErrTournBadPartner
		}
		if _, ok := ts.acc.store.GetAccount(partner); !ok {
			return ErrTournBadPartner
		}
		if t.entryOfUser(partner) != nil {
			return ErrTournAlreadyIn
		}
		members = append(members, partner)
	}
	e := &TournEntry{ID: len(t.Entries) + 1, Members: members}
	t.Entries = append(t.Entries, e)
	t.logf("%s đăng ký (đội %d)", user, e.ID)
	ts.save(t)
	return nil
}

// Unregister removes the caller's entry (captain only for
// teams) while registration is open.
func (ts *Tournaments) Unregister(id, user string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if t.State != "open" {
		return ErrTournNotOpen
	}
	e := t.entryOfUser(user)
	if e == nil {
		return ErrTournNotIn
	}
	if e.Members[0] != user {
		return ErrTournNotCaptain
	}
	out := t.Entries[:0]
	for _, x := range t.Entries {
		if x.ID != e.ID {
			out = append(out, x)
		}
	}
	t.Entries = out
	// Seeds are registration order: renumber to close the gap
	// so bracket generation always sees seeds 1..N in order.
	for i, x := range t.Entries {
		x.ID = i + 1
	}
	t.logf("%s huỷ đăng ký", user)
	ts.save(t)
	return nil
}

// minEntries is the smallest field a bracket can start with.
func minEntries(bracket string) int {
	if bracket == "group_knockout" {
		return 4
	}
	return 2
}

// OpenCheckin closes registration, generates the bracket and
// moves the tournament to check-in. Creator only.
func (ts *Tournaments) OpenCheckin(id, creator string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if t.Creator != creator {
		return ErrTournNotCreator
	}
	if t.State != "open" {
		return ErrTournBadState
	}
	if len(t.Entries) < minEntries(t.Bracket) {
		return ErrTournTooFew
	}
	switch t.Bracket {
	case "single_elim":
		t.Matches = genSingleElim(t.Entries)
	case "double_elim":
		t.Matches = genDoubleElim(t.Entries)
	case "round_robin":
		t.Matches = genRoundRobin(t.Entries, "rr", "Bảng xếp hạng")
	case "group_knockout":
		t.Matches = genGroupKnockout(t.Entries)
	}
	t.NextMatch = len(t.Matches) + 1
	t.State = "checkin"
	t.logf("%s mở check-in — bracket đã tạo (%d trận)", creator, len(t.Matches))
	ts.refreshLocked(t)
	ts.save(t)
	return nil
}

// Cancel cancels a tournament before it starts (open/checkin
// only). Creator only.
func (ts *Tournaments) Cancel(id, creator string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if t.Creator != creator {
		return ErrTournNotCreator
	}
	if t.State != "open" && t.State != "checkin" {
		return ErrTournBadState
	}
	t.State = "cancelled"
	t.logf("%s huỷ giải", creator)
	ts.save(t)
	return nil
}

// Checkin checks the caller's ENTRY in for a match (any
// member of the entry may check the entry in). The match must
// be ready and its round gate open.
func (ts *Tournaments) Checkin(id string, matchID int, user string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	ts.refreshLocked(t)
	m := t.match(matchID)
	if m == nil || m.State != "ready" {
		return ErrTournMatchState
	}
	side := sideOf(t, m, user)
	if side < 0 {
		return ErrTournNotYourSide
	}
	now := ts.now().Unix()
	if side == 0 && !m.CheckA {
		m.CheckA, m.CheckAtA = true, now
	}
	if side == 1 && !m.CheckB {
		m.CheckB, m.CheckAtB = true, now
	}
	ts.save(t)
	return nil
}

// sideOf returns 0/1 when the user belongs to side A/B of the
// match, -1 otherwise.
func sideOf(t *Tournament, m *TournMatch, user string) int {
	for _, cand := range []struct {
		entry int
		side  int
	}{{m.A, 0}, {m.B, 1}} {
		if cand.entry == 0 {
			continue
		}
		if e := t.entry(cand.entry); e != nil {
			for _, u := range e.Members {
				if u == user {
					return cand.side
				}
			}
		}
	}
	return -1
}

// frozenLocked reports whether a match is frozen by an open
// dispute on any match feeding it.
func frozenLocked(t *Tournament, m *TournMatch) bool {
	for _, x := range t.Matches {
		if x.State == "disputed" && (x.WinTo == m.ID || x.LoseTo == m.ID) {
			return true
		}
	}
	return false
}

// PlayableFor validates a play request and returns the match
// + the caller's side. A match is playable when it is ready
// (or already live — a team-mate may have launched the room),
// both sides checked in, and no upstream dispute freezes it.
func (ts *Tournaments) PlayableFor(id string, matchID int, user string) (*Tournament, *TournMatch, int, error) {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return nil, nil, -1, err
	}
	ts.refreshLocked(t)
	m := t.match(matchID)
	if m == nil {
		return nil, nil, -1, ErrTournMatchState
	}
	side := sideOf(t, m, user)
	if side < 0 {
		return nil, nil, -1, ErrTournNotYourSide
	}
	if m.State == "live" {
		return t, m, side, nil
	}
	if m.State != "ready" {
		return nil, nil, -1, ErrTournMatchState
	}
	if !m.CheckA || !m.CheckB {
		return nil, nil, -1, ErrTournMatchState
	}
	if frozenLocked(t, m) {
		return nil, nil, -1, ErrTournFrozen
	}
	return t, m, side, nil
}

// MarkLive records that a match's room now exists (the hub
// created it). Fails if the match changed state meanwhile
// (e.g. a walkover landed first) so the hub can tear the
// just-created room down again.
func (ts *Tournaments) MarkLive(id string, matchID int, roomCode string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	m := t.match(matchID)
	if m == nil || (m.State != "ready" && m.State != "live") {
		return ErrTournMatchState
	}
	m.State = "live"
	m.RoomCode = roomCode
	if t.State == "checkin" {
		t.State = "running"
	}
	ts.save(t)
	return nil
}

// ------------------------------------------------------------ engine

// refreshLocked brings derived state up to date after any
// change: group->knockout seeding, the bye cascade, round
// gates (pending -> ready), and the checkin -> running flip.
// It persists when it changed anything.
func (ts *Tournaments) refreshLocked(t *Tournament) {
	if t.State != "checkin" && t.State != "running" {
		return
	}
	changed := false
	// Group stage -> knockout seeding.
	if t.Bracket == "group_knockout" && !t.GroupSeeded {
		if stageDone(t, "ga") && stageDone(t, "gb") {
			sa := standingsOf(t, "ga")
			sb := standingsOf(t, "gb")
			if len(sa) >= 2 && len(sb) >= 2 {
				for _, m := range t.Matches {
					if m.Stage != "ko" {
						continue
					}
					if m.Round == 1 && strings.HasPrefix(m.Label, "Bán kết 1") {
						m.A, m.ASet = sa[0].Entry, true
						m.B, m.BSet = sb[1].Entry, true
					}
					if m.Round == 1 && strings.HasPrefix(m.Label, "Bán kết 2") {
						m.A, m.ASet = sb[0].Entry, true
						m.B, m.BSet = sa[1].Entry, true
					}
				}
				t.GroupSeeded = true
				changed = true
				t.logf("Vòng bảng xong — bán kết đã xếp")
			}
		}
	}
	// Bye cascade: a match whose sides are both known and at
	// least one is vacant resolves itself (repeatedly — a
	// resolved bye can complete the next match the same way).
	for {
		progressed := false
		for _, m := range t.Matches {
			if (m.State == "pending" || m.State == "ready") && m.ASet && m.BSet && (m.A == 0 || m.B == 0) {
				winner := m.A
				if winner == 0 {
					winner = m.B
				}
				ts.resolveMatchLocked(t, m, winner, false, 0, 0, "")
				m.Bye = true
				progressed = true
				changed = true
			}
		}
		if !progressed {
			break
		}
	}
	// Round gates: in the league stages (rr/ga/gb) only the
	// earliest unfinished round is playable; bracket stages
	// sequence themselves through their feeds.
	for _, m := range t.Matches {
		if m.State != "pending" || !m.ASet || !m.BSet {
			continue
		}
		if m.Stage == "rr" || m.Stage == "ga" || m.Stage == "gb" {
			if !roundGateOpen(t, m) {
				continue
			}
		}
		m.State = "ready"
		changed = true
	}
	// checkin -> running once real play is underway (a live
	// match, a played result, or a walkover — byes resolved at
	// generation time do not count).
	if t.State == "checkin" {
		for _, m := range t.Matches {
			if m.State == "live" || (m.State == "done" && (m.Played || m.Walkover)) {
				t.State = "running"
				changed = true
				break
			}
		}
	}
	if changed {
		ts.save(t)
	}
}

// stageDone reports whether every match of a stage is done
// (disputed matches are NOT done — they hold the stage open).
func stageDone(t *Tournament, stage string) bool {
	seen := false
	for _, m := range t.Matches {
		if m.Stage != stage {
			continue
		}
		seen = true
		if m.State != "done" {
			return false
		}
	}
	return seen
}

// roundGateOpen reports whether all earlier-round matches in
// the match's league stage are done.
func roundGateOpen(t *Tournament, m *TournMatch) bool {
	for _, x := range t.Matches {
		if x.Stage == m.Stage && x.Round < m.Round && x.State != "done" {
			return false
		}
	}
	return true
}

// standingRow is one line of a league standings table.
type standingRow struct {
	Entry int
	Wins  int
	Score int
}

// standingsOf computes a league stage's table from its done
// matches: wins desc, then aggregate match score desc, then
// seed (entry id) asc. Walkover wins count as wins; scores
// only accumulate from played matches.
func standingsOf(t *Tournament, stage string) []standingRow {
	rows := map[int]*standingRow{}
	var order []int
	for _, e := range t.Entries {
		inStage := false
		for _, m := range t.Matches {
			if m.Stage == stage && (m.A == e.ID || m.B == e.ID) {
				inStage = true
			}
		}
		if inStage {
			rows[e.ID] = &standingRow{Entry: e.ID}
			order = append(order, e.ID)
		}
	}
	for _, m := range t.Matches {
		if m.Stage != stage || m.State != "done" {
			continue
		}
		if m.Winner != 0 {
			if r := rows[m.Winner]; r != nil {
				r.Wins++
			}
		}
		if m.Played {
			if r := rows[m.A]; r != nil {
				r.Score += m.ScoreA
			}
			if r := rows[m.B]; r != nil {
				r.Score += m.ScoreB
			}
		}
	}
	out := make([]standingRow, 0, len(order))
	for _, id := range order {
		out = append(out, *rows[id])
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Wins != out[j].Wins {
			return out[i].Wins > out[j].Wins
		}
		if out[i].Score != out[j].Score {
			return out[i].Score > out[j].Score
		}
		return out[i].Entry < out[j].Entry
	})
	return out
}

// resolveMatchLocked settles a match: records the outcome,
// banks W/L for played matches, feeds winner/loser onward,
// spawns the double-elim grand-final reset when earned, and
// checks for tournament finish. Callers set Bye/Walkover on
// the match after calling (the flags describe HOW it ended).
func (ts *Tournaments) resolveMatchLocked(t *Tournament, m *TournMatch, winner int, played bool, scoreA, scoreB int, replayID string) {
	if m.State == "done" {
		return // exactly once
	}
	m.State = "done"
	m.Winner = winner
	m.Played = played
	m.ScoreA, m.ScoreB = scoreA, scoreB
	if replayID != "" {
		m.ReplayID = replayID
	}
	loser := m.A
	if winner == m.A {
		loser = m.B
	}
	if played {
		for _, cand := range []struct {
			entry int
			won   bool
		}{{m.A, winner == m.A}, {m.B, winner == m.B}} {
			if cand.entry == 0 {
				continue
			}
			if e := t.entry(cand.entry); e != nil {
				for _, u := range e.Members {
					if err := ts.acc.RecordMatch(u, cand.won); err != nil {
						log.Printf("tournament %s: bank match for %s: %v", t.ID, u, err)
					}
				}
			}
		}
	}
	// Feeds.
	if m.WinTo != 0 {
		if dst := t.match(m.WinTo); dst != nil {
			setSide(dst, m.WinPos, winner)
		}
	}
	if m.LoseTo != 0 {
		if dst := t.match(m.LoseTo); dst != nil {
			setSide(dst, m.LosePos, loser)
		}
	}
	// Double-elim grand-final reset: the losers-side champion
	// (side B of the GF) winning the first grand final earns
	// a reset match — the winners-side champion has not lost
	// yet, so one defeat cannot eliminate them.
	if t.Bracket == "double_elim" && m.Stage == "gf" && m.Round == 1 && winner != 0 && winner == m.B {
		gf2 := &TournMatch{
			ID: t.NextMatch, Stage: "gf", Round: 2, State: "pending",
			Label: "Chung kết tổng (đấu lại)",
			A:     m.A, ASet: true, B: m.B, BSet: true,
		}
		t.NextMatch++
		t.Matches = append(t.Matches, gf2)
		t.logf("Đội nhánh thua thắng chung kết tổng — có trận đấu lại")
	}
	ts.finishCheckLocked(t)
}

func setSide(m *TournMatch, pos, entry int) {
	if pos == 0 {
		m.A, m.ASet = entry, true
	} else {
		m.B, m.BSet = entry, true
	}
}

// finishCheckLocked decides the champion/runner-up when the
// bracket's deciding match (or the league) is complete, and
// writes the rewards exactly once.
func (ts *Tournaments) finishCheckLocked(t *Tournament) {
	if t.State == "finished" || t.State == "cancelled" {
		return
	}
	var champion, runnerUp int
	switch t.Bracket {
	case "single_elim":
		for _, m := range t.Matches {
			if m.Stage == "main" && m.WinTo == 0 && m.State == "done" && m.Winner != 0 {
				champion, runnerUp = m.Winner, otherEntry(m, m.Winner)
			}
		}
	case "double_elim":
		// The LAST grand final decides: round 2 when a reset
		// exists, else round 1 — but round 1 only finishes the
		// tournament when the winners-side champion won it
		// (a losers-side win spawns the reset instead).
		for _, m := range t.Matches {
			if m.Stage != "gf" || m.State != "done" || m.Winner == 0 {
				continue
			}
			if m.Round == 2 || m.Winner == m.A {
				champion, runnerUp = m.Winner, otherEntry(m, m.Winner)
			}
		}
	case "round_robin":
		if stageDone(t, "rr") {
			rows := standingsOf(t, "rr")
			if len(rows) >= 1 {
				champion = rows[0].Entry
			}
			if len(rows) >= 2 {
				runnerUp = rows[1].Entry
			}
		}
	case "group_knockout":
		for _, m := range t.Matches {
			if m.Stage == "ko" && m.Round == 2 && m.State == "done" && m.Winner != 0 {
				champion, runnerUp = m.Winner, otherEntry(m, m.Winner)
			}
		}
	}
	if champion == 0 {
		return
	}
	t.Champion, t.RunnerUp = champion, runnerUp
	t.State = "finished"
	t.logf("Giải kết thúc — vô địch: đội %d", champion)
	if !t.RewardsDone {
		t.RewardsDone = true
		ts.writeRewardsLocked(t)
	}
}

// otherEntry returns the match's non-winner entry (0 when the
// other side was vacant).
func otherEntry(m *TournMatch, winner int) int {
	if winner == m.A {
		return m.B
	}
	return m.A
}

// writeRewardsLocked banks the podium records: every member
// of the champion entry gets a champion finish (+ the
// "Vô địch giải đấu" title on their profile), every member
// of the runner-up entry a runner-up finish. The account
// write itself is idempotent per tournament, so this can
// never double-bank.
func (ts *Tournaments) writeRewardsLocked(t *Tournament) {
	for _, cand := range []struct {
		entry int
		place string
	}{{t.Champion, "champion"}, {t.RunnerUp, "runner_up"}} {
		if cand.entry == 0 {
			continue
		}
		e := t.entry(cand.entry)
		if e == nil {
			continue
		}
		for _, u := range e.Members {
			if err := ts.acc.RecordTournamentFinish(u, t.ID, t.Name, cand.place); err != nil {
				log.Printf("tournament %s: reward for %s: %v", t.ID, u, err)
			}
		}
	}
}

// ApplyResult is the hub's entry point for a referee-reported
// tournament match result: winnerEntry won, with the sides'
// aggregate match scores and the sealed replay id. It is
// idempotent — a second report for the same match is a no-op.
func (ts *Tournaments) ApplyResult(id string, matchID, winnerEntry, scoreA, scoreB int, replayID string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	m := t.match(matchID)
	if m == nil {
		return ErrTournMatchState
	}
	if m.State == "done" {
		return nil // already banked — exactly once
	}
	if m.State != "live" {
		return ErrTournMatchState
	}
	ts.resolveMatchLocked(t, m, winnerEntry, true, scoreA, scoreB, replayID)
	m.RoomCode = ""
	ts.refreshLocked(t)
	ts.save(t)
	log.Printf("tournament %s: match %d -> entry %d wins (%d-%d), replay %s",
		t.ID, matchID, winnerEntry, scoreA, scoreB, replayID)
	return nil
}

// ------------------------------------------------------------ walkovers

// AwardWalkover is the creator's manual walkover: award a
// ready match to a side (0 = A, 1 = B) without play. Covers
// the case the automatic rule cannot (neither side checked
// in). No W/L is banked for an unplayed match.
func (ts *Tournaments) AwardWalkover(id string, matchID int, creator string, side int) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if t.Creator != creator {
		return ErrTournNotCreator
	}
	ts.refreshLocked(t)
	m := t.match(matchID)
	if m == nil || m.State != "ready" {
		return ErrTournMatchState
	}
	if side != 0 && side != 1 {
		return ErrTournMatchState
	}
	winner := m.A
	if side == 1 {
		winner = m.B
	}
	if winner == 0 {
		return ErrTournMatchState
	}
	ts.resolveMatchLocked(t, m, winner, false, 0, 0, "")
	m.Walkover = true
	t.logf("%s xử thắng (walkover) trận %d cho đội %d", creator, matchID, winner)
	ts.refreshLocked(t)
	ts.save(t)
	return nil
}

// sweepWalkoversLocked awards every ready match where exactly
// one side checked in longer ago than TournWalkoverWindow.
// Deterministic on the service clock.
func (ts *Tournaments) sweepWalkoversLocked(t *Tournament) {
	if t.State != "checkin" && t.State != "running" {
		return
	}
	now := ts.now().Unix()
	window := int64(TournWalkoverWindow / time.Second)
	changed := false
	for _, m := range t.Matches {
		if m.State != "ready" || m.CheckA == m.CheckB {
			continue
		}
		var checkedAt int64
		var winner int
		if m.CheckA {
			checkedAt, winner = m.CheckAtA, m.A
		} else {
			checkedAt, winner = m.CheckAtB, m.B
		}
		if winner == 0 || now-checkedAt < window {
			continue
		}
		ts.resolveMatchLocked(t, m, winner, false, 0, 0, "")
		m.Walkover = true
		t.logf("Walkover trận %d: đội %d thắng vì đối thủ không check-in", m.ID, winner)
		changed = true
	}
	if changed {
		ts.refreshLocked(t)
		ts.save(t)
	}
}

// ResetLiveMatch returns a stuck live match to ready (its
// room is gone, or the creator resets it manually). Check-ins
// are kept so the sides can relaunch immediately.
func (ts *Tournaments) ResetLiveMatch(id string, matchID int, creator string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if creator != "" && t.Creator != creator {
		return ErrTournNotCreator
	}
	m := t.match(matchID)
	if m == nil || m.State != "live" {
		return ErrTournMatchState
	}
	m.State = "ready"
	m.RoomCode = ""
	t.logf("Trận %d được đặt lại (phòng đã đóng)", matchID)
	ts.save(t)
	return nil
}

// Sweep runs the time-based maintenance over every
// tournament: refresh + automatic walkovers. Called from the
// server's periodic ticker and safe to call any time.
func (ts *Tournaments) Sweep() {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	for _, t := range ts.store.Tournaments() {
		ts.refreshLocked(t)
		ts.sweepWalkoversLocked(t)
	}
}

// ------------------------------------------------------------ disputes

// Dispute flags a played match's result for creator review.
// The flag carries the match's own server-issued replay id —
// the evidence. While disputed, the match's downstream
// matches are frozen (Play rejects them) and league stages
// stay open. A match can only be flagged while the
// tournament is still running and none of its downstream
// matches has been played (a bye-resolved downstream match
// can still be unwound by the replay resolution).
func (ts *Tournaments) Dispute(id string, matchID int, user, replayID string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if t.State != "checkin" && t.State != "running" {
		return ErrTournBadState
	}
	m := t.match(matchID)
	if m == nil || m.State != "done" || !m.Played {
		return ErrTournMatchState
	}
	if sideOf(t, m, user) < 0 {
		return ErrTournNotYourSide
	}
	if m.ReplayID == "" || replayID != m.ReplayID {
		return ErrTournNoReplay
	}
	// Downstream guard: any match fed by this one must not be
	// live, and must not hold a played result.
	for _, x := range t.Matches {
		if x.State == "live" && feedsFrom(x, t, m.ID) {
			return ErrTournDisputeLate
		}
		if x.State == "done" && x.Played && feedsFrom(x, t, m.ID) {
			return ErrTournDisputeLate
		}
	}
	// Structural downstream that link-feeds do not express:
	// the double-elim reset match spawned by a GF result, and
	// the knockout stage seeded from group standings.
	if t.Bracket == "double_elim" && m.Stage == "gf" && m.Round == 1 {
		for _, x := range t.Matches {
			if x.Stage == "gf" && x.Round == 2 &&
				(x.State == "live" || (x.State == "done" && x.Played)) {
				return ErrTournDisputeLate
			}
		}
	}
	if (m.Stage == "ga" || m.Stage == "gb") && t.GroupSeeded {
		for _, x := range t.Matches {
			if x.Stage == "ko" && (x.State == "live" || (x.State == "done" && x.Played)) {
				return ErrTournDisputeLate
			}
		}
	}
	m.State = "disputed"
	m.DisputeBy = user
	t.logf("%s khiếu nại trận %d (replay %s)", user, matchID, replayID)
	ts.save(t)
	return nil
}

// feedsFrom reports whether match x is a DIRECT downstream
// match of the given match id (its sides were fed by it).
func feedsFrom(x *TournMatch, t *Tournament, srcID int) bool {
	src := t.match(srcID)
	if src == nil {
		return false
	}
	return src.WinTo == x.ID || src.LoseTo == x.ID
}

// ResolveDispute settles a dispute (creator only). uphold =
// the result stands and downstream unfreezes. uphold = false
// ("đấu lại") = the result is voided: its banked W/L is
// unbanked, feeds from it are unwound (bye cascades unwind
// recursively), and the match returns to ready with check-ins
// cleared for a rematch.
func (ts *Tournaments) ResolveDispute(id string, matchID int, creator string, uphold bool) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	t, err := ts.load(id)
	if err != nil {
		return err
	}
	if t.Creator != creator {
		return ErrTournNotCreator
	}
	m := t.match(matchID)
	if m == nil || m.State != "disputed" {
		return ErrTournMatchState
	}
	if uphold {
		m.State = "done"
		m.DisputeBy = ""
		t.logf("%s giữ nguyên kết quả trận %d", creator, matchID)
		ts.refreshLocked(t)
		ts.save(t)
		return nil
	}
	if err := ts.unresolveLocked(t, m); err != nil {
		return err
	}
	t.logf("%s xử đấu lại trận %d", creator, matchID)
	ts.refreshLocked(t)
	ts.save(t)
	return nil
}

// unresolveLocked voids a done/disputed match's result: it
// unbanks the W/L it recorded, unwinds its feeds (recursively
// unwinding any bye-resolved downstream match first), and
// resets the match to a fresh ready state.
func (ts *Tournaments) unresolveLocked(t *Tournament, m *TournMatch) error {
	// Structural downstream first: a reset grand final
	// spawned by this match's result is dropped entirely, and
	// knockout seeding drawn from group standings is undone.
	if t.Bracket == "double_elim" && m.Stage == "gf" && m.Round == 1 {
		kept := t.Matches[:0]
		for _, x := range t.Matches {
			if !(x.Stage == "gf" && x.Round == 2) {
				kept = append(kept, x)
			}
		}
		t.Matches = kept
	}
	if (m.Stage == "ga" || m.Stage == "gb") && t.GroupSeeded {
		for _, x := range t.Matches {
			if x.Stage == "ko" && x.Round == 1 {
				clearSide(x, 0)
				clearSide(x, 1)
			}
		}
		t.GroupSeeded = false
	}
	// Unwind downstream first.
	for _, x := range t.Matches {
		if !(feedsFrom(x, t, m.ID)) {
			continue
		}
		if x.State == "live" || (x.State == "done" && x.Played) {
			return ErrTournDisputeLate
		}
		if x.State == "done" {
			// A bye-resolved downstream match: unwind it so
			// its own feeds clear too.
			if err := ts.unresolveLocked(t, x); err != nil {
				return err
			}
		}
		// Clear the side(s) this match fed.
		if m.WinTo == x.ID {
			clearSide(x, m.WinPos)
		}
		if m.LoseTo == x.ID {
			clearSide(x, m.LosePos)
		}
		if x.State == "ready" {
			x.State = "pending"
		}
	}
	if m.Played {
		winner := m.Winner
		for _, cand := range []struct {
			entry int
			won   bool
		}{{m.A, winner == m.A}, {m.B, winner == m.B}} {
			if cand.entry == 0 {
				continue
			}
			if e := t.entry(cand.entry); e != nil {
				for _, u := range e.Members {
					if err := ts.acc.RecordMatchRevert(u, cand.won); err != nil {
						log.Printf("tournament %s: unbank match for %s: %v", t.ID, u, err)
					}
				}
			}
		}
	}
	m.State = "ready"
	m.Winner = 0
	m.ScoreA, m.ScoreB = 0, 0
	m.Played = false
	m.Bye = false
	m.Walkover = false
	m.ReplayID = ""
	m.DisputeBy = ""
	m.CheckA, m.CheckB = false, false
	m.CheckAtA, m.CheckAtB = 0, 0
	m.RoomCode = ""
	return nil
}

func clearSide(m *TournMatch, pos int) {
	if pos == 0 {
		m.A, m.ASet = 0, false
		m.CheckA, m.CheckAtA = false, 0
	} else {
		m.B, m.BSet = 0, false
		m.CheckB, m.CheckAtB = false, 0
	}
	if m.State == "ready" {
		m.State = "pending"
	}
}

// ------------------------------------------------------------ views

// entryLabel renders an entry as its members' display names
// joined for a team ("A & B"), or "" for a vacant entry.
func (ts *Tournaments) entryLabel(t *Tournament, entryID int) string {
	e := t.entry(entryID)
	if e == nil {
		return ""
	}
	names := make([]string, 0, len(e.Members))
	for _, u := range e.Members {
		names = append(names, ts.acc.DisplayNameOf(u))
	}
	return strings.Join(names, " & ")
}

// Summary renders one tournament for the list view.
func (ts *Tournaments) Summary(t *Tournament, viewer string) map[string]any {
	mine := viewer != "" && (t.Creator == viewer || t.entryOfUser(viewer) != nil)
	return map[string]any{
		"id": t.ID, "name": t.Name, "format": t.Format, "bracket": t.Bracket,
		"size": t.Size, "entered": len(t.Entries), "state": t.State,
		"creator": t.Creator, "creator_name": ts.acc.DisplayNameOf(t.Creator),
		"mine": mine, "created_at": t.CreatedAt,
		"champion_name": ts.entryLabel(t, t.Champion),
	}
}

// View renders the full detail payload for one tournament as
// seen by viewer: entries, every match (with the viewer's
// side + available actions resolved server-side), league
// standings, and the audit log tail. The client renders this
// verbatim — bracket logic never lives client-side.
func (ts *Tournaments) View(t *Tournament, viewer string) map[string]any {
	myEntry := 0
	if e := t.entryOfUser(viewer); e != nil {
		myEntry = e.ID
	}
	entries := make([]map[string]any, 0, len(t.Entries))
	for _, e := range t.Entries {
		members := make([]map[string]any, 0, len(e.Members))
		for _, u := range e.Members {
			members = append(members, map[string]any{
				"user": u, "name": ts.acc.DisplayNameOf(u)})
		}
		entries = append(entries, map[string]any{
			"id": e.ID, "label": ts.entryLabel(t, e.ID),
			"members": members, "captain": e.Members[0],
			"is_mine": e.ID == myEntry,
		})
	}
	matches := make([]map[string]any, 0, len(t.Matches))
	for _, m := range t.Matches {
		mv := map[string]any{
			"id": m.ID, "stage": m.Stage, "round": m.Round, "label": m.Label,
			"a": m.A, "b": m.B, "a_set": m.ASet, "b_set": m.BSet,
			"a_label": ts.entryLabel(t, m.A), "b_label": ts.entryLabel(t, m.B),
			"state": m.State, "check_a": m.CheckA, "check_b": m.CheckB,
			"winner": m.Winner, "winner_label": ts.entryLabel(t, m.Winner),
			"score_a": m.ScoreA, "score_b": m.ScoreB,
			"played": m.Played, "bye": m.Bye, "walkover": m.Walkover,
			"replay_id": m.ReplayID, "disputed": m.State == "disputed",
			"frozen":  frozenLocked(t, m),
			"my_side": sideOf(t, m, viewer),
		}
		matches = append(matches, mv)
	}
	standings := map[string]any{}
	for _, stage := range []string{"rr", "ga", "gb"} {
		rows := standingsOf(t, stage)
		if len(rows) == 0 {
			continue
		}
		arr := make([]map[string]any, 0, len(rows))
		for _, r := range rows {
			arr = append(arr, map[string]any{
				"entry": r.Entry, "label": ts.entryLabel(t, r.Entry),
				"wins": r.Wins, "score": r.Score})
		}
		standings[stage] = arr
	}
	logTail := t.Log
	if len(logTail) > 20 {
		logTail = logTail[len(logTail)-20:]
	}
	return map[string]any{
		"id": t.ID, "name": t.Name, "format": t.Format, "bracket": t.Bracket,
		"size": t.Size, "state": t.State, "creator": t.Creator,
		"creator_name": ts.acc.DisplayNameOf(t.Creator),
		"is_creator":   viewer != "" && viewer == t.Creator,
		"my_entry":     myEntry, "created_at": t.CreatedAt,
		"entries": entries, "matches": matches, "standings": standings,
		"champion": t.Champion, "champion_name": ts.entryLabel(t, t.Champion),
		"runner_up": t.RunnerUp, "runner_up_name": ts.entryLabel(t, t.RunnerUp),
		"log": logTail,
	}
}

// ------------------------------------------------------------ hub glue

func tournRoomKey(tournID string, matchID int) string {
	return fmt.Sprintf("%s/%d", tournID, matchID)
}

// IsTournamentRoom reports whether a room is a tournament
// match room (its results route to the tournament service).
func (h *Hub) IsTournamentRoom(code string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[code]
	return ok && r.Tournament
}

// TournamentRoomInfo returns a tournament room's binding.
func (h *Hub) TournamentRoomInfo(code string) (tournID string, matchID int, ok bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok2 := h.rooms[code]
	if !ok2 || !r.Tournament {
		return "", 0, false
	}
	return r.TournID, r.TournMatchID, true
}

// TournamentPlayRoom binds a participant into their match's
// dedicated room, creating it on first use: a ranked-style
// referee room (Ranked=true — the referee owns the result;
// Queued=false — it is not a queue room) with every member of
// both entries pre-seated (side A takes the low slots in
// member order, side B the next), a one-time referee token
// (hash only) and a spawned referee process. Later presses
// rebind the caller to their reserved slot (a slot deleted by
// a pre-start disconnect is recreated from the match roster).
func (h *Hub) TournamentPlayRoom(send sender, tournID string, matchID int, user string) (string, int, error) {
	if h.tourns == nil {
		return "", -1, ErrTournNotFound
	}
	t, m, _, err := h.tourns.PlayableFor(tournID, matchID, user)
	if err != nil {
		return "", -1, err
	}
	// Reserved slot: side A members in order, then side B.
	slotOf := map[string]int{}
	slot := 0
	for _, side := range []int{m.A, m.B} {
		if e := t.entry(side); e != nil {
			for _, u := range e.Members {
				slotOf[u] = slot
				slot++
			}
		}
	}
	mySlot, ok := slotOf[user]
	if !ok {
		return "", -1, ErrTournNotYourSide
	}
	key := tournRoomKey(t.ID, m.ID)

	h.mu.Lock()
	if code, exists := h.tournRooms[key]; exists {
		if r, rok := h.rooms[code]; rok {
			p, pok := r.Players[mySlot]
			if !pok {
				p = &Player{Slot: mySlot, User: user, Account: true,
					Name: h.acc.DisplayNameOf(user), Seq: h.nextSeqLocked()}
				r.Players[mySlot] = p
			}
			p.send = send
			p.Connected = true
			h.broadcastRoomLocked(r)
			h.maybeStartCountdownLocked(r)
			h.mu.Unlock()
			return code, mySlot, nil
		}
		delete(h.tournRooms, key)
	}
	// Create the room.
	code := h.newCodeLocked()
	pick := h.rankedMapPick()
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		h.mu.Unlock()
		return "", -1, ErrTournRoomBusy
	}
	token := fmt.Sprintf("%x", tokenBytes)
	r := &Room{
		Code: code, Host: 0, Biome: pick.Biome, Layout: pick.Layout,
		Players:  make(map[int]*Player),
		checks:   make(map[int64]map[int]string),
		desynced: make(map[int64]bool),
		Ranked:   true, Tournament: true, TournID: t.ID, TournMatchID: m.ID,
		RefereeTokenHash: RefereeTokenHashOf(token),
	}
	for u, s := range slotOf {
		p := &Player{Slot: s, User: u, Account: true,
			Name: h.acc.DisplayNameOf(u), Seq: h.nextSeqLocked()}
		if s == mySlot {
			p.send = send
			p.Connected = true
		}
		r.Players[s] = p
	}
	h.rooms[code] = r
	h.tournRooms[key] = code
	orch := h.Orch
	h.mu.Unlock()

	if err := h.tourns.MarkLive(t.ID, m.ID, code); err != nil {
		// The match changed state between validation and
		// creation (e.g. a walkover landed): tear the room
		// back down and report the match state.
		h.mu.Lock()
		if rr, ok := h.rooms[code]; ok {
			h.deleteRoomLocked(rr)
		}
		h.mu.Unlock()
		return "", -1, err
	}
	if orch != nil {
		if err := orch.SpawnReferee(code, token); err != nil {
			log.Printf("tournament %s/%d: referee spawn failed: %v", t.ID, m.ID, err)
		}
	}
	h.mu.Lock()
	if rr, ok := h.rooms[code]; ok {
		h.broadcastRoomLocked(rr)
		h.maybeStartCountdownLocked(rr)
	}
	h.mu.Unlock()
	log.Printf("tournament %s: match %d room %s (%s/%s)", t.ID, m.ID, code, r.Biome, r.Layout)
	return code, mySlot, nil
}

// TournamentMatchResult applies a referee-banked result to
// its tournament match: the winning ENTRY is derived from the
// per-user results against the match's entries, the sides'
// scores are summed from the referee's per-slot scores, and
// the sealed replay id is attached as dispute evidence.
func (h *Hub) TournamentMatchResult(code string, results map[string]bool, scores []int) error {
	tournID, matchID, ok := h.TournamentRoomInfo(code)
	if !ok || h.tourns == nil {
		return ErrTournNotFound
	}
	t, exists := h.tourns.Get(tournID)
	if !exists {
		return ErrTournNotFound
	}
	m := t.match(matchID)
	if m == nil {
		return ErrTournMatchState
	}
	slotUser := h.RoomSlotUsers(code)
	sideScore := func(entryID int) int {
		e := t.entry(entryID)
		if e == nil {
			return 0
		}
		members := map[string]bool{}
		for _, u := range e.Members {
			members[u] = true
		}
		sum := 0
		for s, u := range slotUser {
			if members[u] && s >= 0 && s < len(scores) {
				sum += scores[s]
			}
		}
		return sum
	}
	winner := 0
	for _, side := range []struct {
		entry int
	}{{m.A}, {m.B}} {
		e := t.entry(side.entry)
		if e == nil || len(e.Members) == 0 {
			continue
		}
		if won, ok := results[e.Members[0]]; ok && won {
			winner = side.entry
		}
	}
	if winner == 0 {
		return ErrTournMatchState
	}
	return h.tourns.ApplyResult(tournID, matchID, winner,
		sideScore(m.A), sideScore(m.B), h.RoomReplayID(code))
}

// TournamentSweep is the periodic maintenance hook (called
// from the server ticker): time-based tournament rules
// (walkovers), resetting live matches whose room has
// vanished without a result (all players gone / room closed)
// so their sides can relaunch, and RE-ARMING the start
// countdown of tournament rooms that have not started yet.
// The countdown trigger normally fires on referee join /
// player bind, but those are one-shot events: if the last
// bind lands before the referee attaches and a join-time
// check raced a transient disconnect, nothing would ever
// call it again and the room would wait forever (observed in
// the first tournament smoke run). Queue rooms cannot hit
// this — their players are seated before the referee spawns;
// tournament rooms bind afterwards, in any order, so the
// sweep retries the (idempotent, condition-guarded) trigger.
func (h *Hub) TournamentSweep() {
	if h.tourns == nil {
		return
	}
	h.mu.Lock()
	for _, r := range h.rooms {
		if r.Tournament && !r.InMatch {
			h.maybeStartCountdownLocked(r)
		}
	}
	h.mu.Unlock()
	h.tourns.Sweep()
	h.mu.Lock()
	type binding struct{ code, key string }
	var dead []binding
	for key, code := range h.tournRooms {
		if _, ok := h.rooms[code]; !ok {
			dead = append(dead, binding{code, key})
			delete(h.tournRooms, key)
		}
	}
	h.mu.Unlock()
	for _, b := range dead {
		tournID, rest, found := strings.Cut(b.key, "/")
		if !found {
			continue
		}
		var matchID int
		if _, err := fmt.Sscan(rest, &matchID); err == nil {
			_ = h.tourns.ResetLiveMatch(tournID, matchID, "")
		}
	}
}
