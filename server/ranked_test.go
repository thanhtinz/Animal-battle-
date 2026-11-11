package main

// P4 stage 3 tests: Elo/MMR math, matchmaking windows (fake clock),
// referee token gating, referee-only ranked results, ranked resync
// sourced from the referee, and referee spawn-arg construction.

import (
	"reflect"
	"testing"
	"time"
)

func rankedAccounts(t *testing.T) *Accounts {
	t.Helper()
	acc, _ := testAccounts(t)
	return acc
}

func mustRegister(t *testing.T, acc *Accounts, user string, mmr int) {
	t.Helper()
	if err := acc.Register(user, "secret1"); err != nil {
		t.Fatalf("register %s: %v", user, err)
	}
	if mmr != 0 {
		a, ok := acc.store.GetAccount(user)
		if !ok {
			t.Fatalf("account %s missing", user)
		}
		a.MMR = mmr
		if err := acc.store.PutAccount(a); err != nil {
			t.Fatalf("seed mmr %s: %v", user, err)
		}
	}
}

func profileOf(t *testing.T, acc *Accounts, user string) Profile {
	t.Helper()
	p, ok := acc.Profile(user)
	if !ok {
		t.Fatalf("profile %s missing", user)
	}
	return p
}

// ---------------------------------------------------------- MMR math

func TestEloEqualMatch(t *testing.T) {
	acc := rankedAccounts(t)
	mustRegister(t, acc, "Alpha", 0)
	mustRegister(t, acc, "Bravo", 0)
	w, l, err := acc.RecordRankedResult("Alpha", "Bravo")
	if err != nil {
		t.Fatalf("record: %v", err)
	}
	// 1000 vs 1000: expected 0.5, K=32 -> ±16 exactly.
	if w != 1016 || l != 984 {
		t.Fatalf("mmr = %d/%d, want 1016/984", w, l)
	}
	pw, pl := profileOf(t, acc, "Alpha"), profileOf(t, acc, "Bravo")
	if pw.Wins != 1 || pw.Matches != 1 || pl.Losses != 1 || pl.Matches != 1 {
		t.Fatalf("W/L not banked: %+v / %+v", pw, pl)
	}
}

func TestEloUnderdogAndFavourite(t *testing.T) {
	acc := rankedAccounts(t)
	mustRegister(t, acc, "Low", 1000)
	mustRegister(t, acc, "High", 1400)
	w, l, err := acc.RecordRankedResult("Low", "High")
	if err != nil {
		t.Fatalf("record: %v", err)
	}
	// expected(Low) = 1/(1+10^1) = 1/11; delta = round(32*10/11) = 29.
	if w != 1029 || l != 1371 {
		t.Fatalf("mmr = %d/%d, want 1029/1371", w, l)
	}
}

func TestEloHighKAndFloor(t *testing.T) {
	acc := rankedAccounts(t)
	mustRegister(t, acc, "Pro1", 2100)
	mustRegister(t, acc, "Pro2", 2100)
	w, l, err := acc.RecordRankedResult("Pro1", "Pro2")
	if err != nil {
		t.Fatalf("record: %v", err)
	}
	// K=16 above 2000: equal match -> ±8.
	if w != 2108 || l != 2092 {
		t.Fatalf("mmr = %d/%d, want 2108/2092", w, l)
	}
	mustRegister(t, acc, "LowA", 115)
	mustRegister(t, acc, "LowB", 115)
	_, l2, err := acc.RecordRankedResult("LowA", "LowB")
	if err != nil {
		t.Fatalf("record: %v", err)
	}
	// 115 - 16 = 99 -> floored at 100.
	if l2 != MMRFloor {
		t.Fatalf("loser mmr = %d, want floor %d", l2, MMRFloor)
	}
}

func TestRankedLeaderboardOrder(t *testing.T) {
	acc := rankedAccounts(t)
	mustRegister(t, acc, "Charlie", 1200)
	mustRegister(t, acc, "Alpha", 1500)
	mustRegister(t, acc, "Bravo", 0) // unrated -> effective 1000
	rows := acc.RankedLeaderboard()
	if len(rows) != 3 {
		t.Fatalf("rows = %d", len(rows))
	}
	if rows[0].User != "Alpha" || rows[1].User != "Charlie" || rows[2].User != "Bravo" {
		t.Fatalf("order = %s,%s,%s", rows[0].User, rows[1].User, rows[2].User)
	}
	if rows[2].MMR != MMRStart {
		t.Fatalf("unrated effective mmr = %d, want %d", rows[2].MMR, MMRStart)
	}
}

// ---------------------------------------------------------- matchmaking

type mmFixture struct {
	hub   *Hub
	acc   *Accounts
	clock time.Time
}

func newMMFixture(t *testing.T) *mmFixture {
	f := &mmFixture{acc: rankedAccounts(t), clock: time.Unix(1_700_000_000, 0)}
	f.hub = NewHub()
	f.hub.acc = f.acc
	f.hub.mmNow = func() time.Time { return f.clock }
	return f
}

func (f *mmFixture) joinQueue(t *testing.T, user string) (*session, *fakeSender) {
	t.Helper()
	fs := &fakeSender{}
	s := &session{hub: f.hub, acc: f.acc, user: user, out: fs}
	if _, err := f.hub.QueueJoin(s, RankedMode1v1); err != nil {
		t.Fatalf("queue join %s: %v", user, err)
	}
	return s, fs
}

func TestQueueGuestRejected(t *testing.T) {
	f := newMMFixture(t)
	guest := &session{hub: f.hub, acc: f.acc, out: &fakeSender{}}
	if _, err := f.hub.QueueJoin(guest, RankedMode1v1); err != ErrRankedLogin {
		t.Fatalf("guest err = %v, want ErrRankedLogin", err)
	}
	if _, err := f.hub.QueueJoin(guest, "2v2"); err != ErrBadQueueMode {
		t.Fatalf("mode err = %v, want ErrBadQueueMode", err)
	}
}

func TestQueueWindowExpansion(t *testing.T) {
	f := newMMFixture(t)
	// 13z: the group anchors on Alpha (1000) and needs SEVEN more
	// in-window players. Six close players (1010..1060) plus Bravo
	// (1500, diff 500) are queued: at the starting window (±100)
	// only the six fit, so no match forms yet.
	mustRegister(t, f.acc, "Alpha", 0)    // 1000
	mustRegister(t, f.acc, "Bravo", 1500) // diff 500
	closeNames := []string{"C10", "C20", "C30", "C40", "C50", "C60"}
	for i, n := range closeNames {
		mustRegister(t, f.acc, n, 1010+i*10)
	}
	sa, fa := f.joinQueue(t, "Alpha")
	closeSess := make([]*session, 0, len(closeNames))
	for _, n := range closeNames {
		s, _ := f.joinQueue(t, n)
		closeSess = append(closeSess, s)
	}
	sb, _ := f.joinQueue(t, "Bravo")
	f.hub.TryPairAll()
	if f.hub.QueueLen() != 8 {
		t.Fatalf("group formed too early: window 100 < diff 500 (queue = %d)", f.hub.QueueLen())
	}
	if sa.in || sb.in {
		t.Fatalf("nobody may be placed before the group is full")
	}
	// After 80s the window is 100 + 50*8 = 500: Bravo now fits and
	// the group of eight forms.
	f.clock = f.clock.Add(80 * time.Second)
	f.hub.TryPairAll()
	if f.hub.QueueLen() != 0 {
		t.Fatalf("group not formed at window 500 vs diff 500 (queue = %d)", f.hub.QueueLen())
	}
	if !sa.in || !sb.in || sa.code == "" || sa.code != sb.code {
		t.Fatalf("sessions not bound: %+v / %+v", sa, sb)
	}
	// Anchor takes slot 0; fillers follow by MMR closeness, so the
	// closest (C10) is slot 1 and the far Bravo (diff 500) slot 7.
	if sa.slot != 0 || closeSess[0].slot != 1 || sb.slot != 7 {
		t.Fatalf("slots: anchor %d, closest %d, bravo %d — want 0/1/7",
			sa.slot, closeSess[0].slot, sb.slot)
	}
	mf := fa.ofType("match_found")
	if len(mf) != 1 || mf[0]["code"] != sa.code {
		t.Fatalf("match_found A = %v", mf)
	}
	// Ranked maps are drawn at RANDOM per match (13j) — assert the
	// pick is a legal pool member, not a fixed rotation step.
	legal := map[string]bool{}
	for _, p := range RankedRotation {
		legal[p.Biome+"/"+p.Layout] = true
	}
	if !legal[mf[0]["biome"].(string)+"/"+mf[0]["layout"].(string)] {
		t.Fatalf("ranked map = %v/%v, not in the ranked pool", mf[0]["biome"], mf[0]["layout"])
	}
	players, ok := mf[0]["players"].([]any)
	if !ok || len(players) != QueueMatchSize {
		t.Fatalf("match_found players = %v, want %d entries", mf[0]["players"], QueueMatchSize)
	}
	opp := mf[0]["opponent"].(map[string]any)
	if opp["user"] != "C10" {
		t.Fatalf("opponent = %v, want the closest filler C10", opp)
	}
	if !f.hub.IsRankedRoom(sa.code) {
		t.Fatalf("room %s not marked ranked", sa.code)
	}
	f.hub.mu.Lock()
	room := f.hub.rooms[sa.code]
	f.hub.mu.Unlock()
	if len(room.Players) != QueueMatchSize {
		t.Fatalf("ranked room players = %d, want %d", len(room.Players), QueueMatchSize)
	}
}

func TestQueueWindowCap(t *testing.T) {
	f := newMMFixture(t)
	mustRegister(t, f.acc, "Alpha", 0)    // 1000
	mustRegister(t, f.acc, "Bravo", 1700) // diff 700 > cap 600
	f.joinQueue(t, "Alpha")
	f.joinQueue(t, "Bravo")
	f.clock = f.clock.Add(30 * time.Minute) // window long since capped
	f.hub.TryPairAll()
	if f.hub.QueueLen() != 2 {
		t.Fatalf("paired beyond the 600 cap")
	}
}

func TestQueueFIFOOrder(t *testing.T) {
	f := newMMFixture(t)
	// 13z: nine equally-rated players queue; the FIRST eight form
	// the match (anchor = the first joiner at slot 0) and the
	// ninth keeps waiting.
	names := []string{"First", "Mate2", "Mate3", "Mate4", "Mate5", "Mate6", "Mate7", "Mate8", "Ninth"}
	sessions := make([]*session, 0, len(names))
	for _, n := range names {
		mustRegister(t, f.acc, n, 1000)
		s, _ := f.joinQueue(t, n)
		sessions = append(sessions, s)
	}
	f.hub.TryPairAll()
	for i := 0; i < QueueMatchSize; i++ {
		if !sessions[i].in || sessions[i].slot != i {
			t.Fatalf("player %d should be in at slot %d: %+v", i, i, sessions[i])
		}
		if sessions[i].code != sessions[0].code {
			t.Fatalf("all eight share one room code")
		}
	}
	if sessions[8].in || f.hub.QueueLen() != 1 {
		t.Fatalf("ninth must stay queued")
	}
	if err := f.hub.QueueLeave(sessions[8]); !err {
		t.Fatalf("queue leave should report true")
	}
}

// ---------------------------------------------------------- referee gating

func rankedRoomFixture(t *testing.T, h *Hub, token string) *Room {
	t.Helper()
	r := &Room{
		Code:             "RANK1",
		Host:             0,
		Biome:            "grassland",
		Layout:           "plains",
		Players:          make(map[int]*Player),
		checks:           make(map[int64]map[int]string),
		desynced:         make(map[int64]bool),
		Ranked:           true,
		RefereeTokenHash: RefereeTokenHashOf(token),
		InMatch:          true,
	}
	r.Players[0] = &Player{Slot: 0, Name: "Alpha", User: "Alpha", Account: true,
		Connected: true, send: &fakeSender{}}
	r.Players[1] = &Player{Slot: 1, Name: "Bravo", User: "Bravo", Account: true,
		Connected: true, send: &fakeSender{}}
	h.rooms[r.Code] = r
	return r
}

func TestRefereeTokenGate(t *testing.T) {
	h := NewHub()
	r := rankedRoomFixture(t, h, "correct-token")
	if err := h.RefereeJoin("RANK1", "wrong-token", &fakeSender{}); err != ErrRefereeDenied {
		t.Fatalf("wrong token err = %v, want ErrRefereeDenied", err)
	}
	if r.Referee != nil {
		t.Fatalf("referee attached despite wrong token")
	}
	if err := h.RefereeJoin("RANK1", "correct-token", &fakeSender{}); err != nil {
		t.Fatalf("right token: %v", err)
	}
	if r.Referee == nil || !r.Referee.Connected {
		t.Fatalf("referee not attached")
	}
	if err := h.RefereeJoin("RANK1", "correct-token", &fakeSender{}); err != ErrRefereeBusy {
		t.Fatalf("second referee err = %v, want ErrRefereeBusy", err)
	}
	// A custom (unranked) room never accepts a referee.
	custom := h.CreateRoom(&fakeSender{}, "Host", "grassland", "plains")
	if err := h.RefereeJoin(custom.Code, "correct-token", &fakeSender{}); err != ErrRefereeDenied {
		t.Fatalf("unranked referee err = %v, want ErrRefereeDenied", err)
	}
}

func TestRankedResultsRefereeOnly(t *testing.T) {
	h := NewHub()
	acc := rankedAccounts(t)
	h.acc = acc
	mustRegister(t, acc, "Alpha", 0)
	mustRegister(t, acc, "Bravo", 0)
	rankedRoomFixture(t, h, "tok")
	// A player (even the host) reporting a ranked result is refused.
	if _, err := h.RecordMatchResult("RANK1", 0, 0, nil); err != ErrRankedRoom {
		t.Fatalf("player result err = %v, want ErrRankedRoom", err)
	}
	if p := profileOf(t, acc, "Alpha"); p.Matches != 0 {
		t.Fatalf("player report banked something: %+v", p)
	}
	// The referee's report is accepted — exactly once.
	results, err := h.RecordRefereeResult("RANK1", 0, "elimination", nil)
	if err != nil {
		t.Fatalf("referee result: %v", err)
	}
	if !results["Alpha"] || results["Bravo"] {
		t.Fatalf("results = %v", results)
	}
	if _, err := h.RecordRefereeResult("RANK1", 0, "elimination", nil); err != ErrResultRecorded {
		t.Fatalf("second report err = %v, want ErrResultRecorded", err)
	}
	// Banking through the accounts layer moves MMR exactly ±16.
	w, l, err := acc.RecordRankedResult("Alpha", "Bravo")
	if err != nil || w != 1016 || l != 984 {
		t.Fatalf("banked = %d/%d err %v, want 1016/984", w, l, err)
	}
	// Referee results on an unranked room are refused too.
	custom := h.CreateRoom(&fakeSender{}, "Host", "grassland", "plains")
	custom.InMatch = true
	if _, err := h.RecordRefereeResult(custom.Code, 0, "elimination", nil); err != ErrNotRankedRoom {
		t.Fatalf("unranked referee result err = %v, want ErrNotRankedRoom", err)
	}
	_ = custom
}

func TestRankedChecksumRefereeCanonical(t *testing.T) {
	h := NewHub()
	r := rankedRoomFixture(t, h, "tok")
	ref := &fakeSender{}
	if err := h.RefereeJoin("RANK1", "tok", ref); err != nil {
		t.Fatalf("referee join: %v", err)
	}
	p0 := r.Players[0].send.(*fakeSender)
	p1 := r.Players[1].send.(*fakeSender)
	// Everyone agrees with the referee: silence.
	h.ReportChecksum("RANK1", 0, 30, "H")
	h.ReportChecksum("RANK1", 1, 30, "H")
	h.ReportRefereeChecksum("RANK1", 30, "H")
	if len(p0.ofType("desync")) != 0 || r.resync != nil {
		t.Fatalf("false desync on agreement")
	}
	// Slot 1 disagrees with the referee at tick 60: desync + a
	// resync cycle sourced from the REFEREE (slot -1).
	h.ReportChecksum("RANK1", 0, 60, "H")
	h.ReportRefereeChecksum("RANK1", 60, "H")
	h.ReportChecksum("RANK1", 1, 60, "X")
	if len(p1.ofType("desync")) != 1 {
		t.Fatalf("no desync broadcast")
	}
	if r.resync == nil || r.resync.source != RefereeChecksumSlot {
		t.Fatalf("resync = %+v, want referee-sourced", r.resync)
	}
	if len(ref.ofType("snapshot_request")) != 1 {
		t.Fatalf("referee not asked for a snapshot")
	}
	if len(p1.ofType("resync")) != 1 {
		t.Fatalf("diverged player not frozen")
	}
	// The referee's snapshot is relayed to the diverged player only.
	if err := h.RelaySnapshot("RANK1", RefereeChecksumSlot, 60,
		[]byte(`{"v":1}`)); err != nil {
		t.Fatalf("relay snapshot: %v", err)
	}
	if len(p1.ofType("snapshot")) != 1 || len(p0.ofType("snapshot")) != 0 {
		t.Fatalf("snapshot routing wrong")
	}
	if r.resync != nil {
		t.Fatalf("cycle not closed")
	}
	// A player-impersonated snapshot (slot 1 claiming to be the
	// source of a new cycle) is ignored by the hub.
	h.ReportChecksum("RANK1", 0, 90, "H")
	h.ReportRefereeChecksum("RANK1", 90, "H")
	h.ReportChecksum("RANK1", 1, 90, "Y")
	if r.resync == nil {
		t.Fatalf("second cycle did not open")
	}
	_ = h.RelaySnapshot("RANK1", 1, 90, []byte(`{"v":1}`))
	if r.resync == nil {
		t.Fatalf("player snapshot closed a referee cycle")
	}
	if len(p1.ofType("snapshot")) != 1 {
		t.Fatalf("player snapshot was relayed")
	}
}

// ---------------------------------------------------------- orchestration

func TestRefereeBuildArgs(t *testing.T) {
	o := &Orchestrator{
		GodotPath:   "/opt/godot",
		ProjectPath: "/srv/empire-age/godot",
		RelayURL:    "ws://127.0.0.1:8765/ws",
		ExtraArgs:   []string{"--referee-test-kill=120", "--referee-test-kill-slot=1"},
	}
	want := []string{
		"--headless", "--fixed-fps", "30",
		"--path", "/srv/empire-age/godot",
		"--",
		"--referee",
		"--referee-room=ABC12",
		"--referee-token=deadbeef",
		"--referee-url=ws://127.0.0.1:8765/ws",
		"--referee-test-kill=120", "--referee-test-kill-slot=1",
	}
	if got := o.buildArgs("ABC12", "deadbeef"); !reflect.DeepEqual(got, want) {
		t.Fatalf("args = %v\nwant %v", got, want)
	}
	off := &Orchestrator{}
	if err := off.SpawnReferee("ABC12", "x"); err == nil {
		t.Fatalf("spawn without a binary must error")
	}
}
