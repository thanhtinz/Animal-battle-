package main

// 13t tests: the NORMAL (unranked) matchmaking queue — guests
// allowed, strict FIFO pairing, queued rooms that auto-start on
// the server countdown, and result banking that records
// wins/losses WITHOUT touching MMR or the seasonal ladder.

import (
	"testing"
	"time"
)

func guestSession(f *mmFixture, fs *fakeSender) *session {
	return &session{hub: f.hub, acc: f.acc, out: fs}
}

func accountSession(f *mmFixture, user string, fs *fakeSender) *session {
	return &session{hub: f.hub, acc: f.acc, user: user, out: fs}
}

// joinNormalGuests adds n guest sessions to the normal queue and
// returns them in join order; names run KhachA, KhachB, ...
// continuing from `start` so two calls never collide.
func joinNormalGuests(t *testing.T, f *mmFixture, n, start int) ([]*session, []*fakeSender) {
	t.Helper()
	sessions := make([]*session, 0, n)
	senders := make([]*fakeSender, 0, n)
	for i := 0; i < n; i++ {
		fs := &fakeSender{}
		gs := guestSession(f, fs)
		name := "Khach" + string(rune('A'+start+i))
		if err := f.hub.NormalQueueJoin(gs, name); err != nil {
			t.Fatalf("guest %s join: %v", name, err)
		}
		sessions = append(sessions, gs)
		senders = append(senders, fs)
	}
	return sessions, senders
}

func TestNormalQueueGuestsPair(t *testing.T) {
	f := newMMFixture(t)
	// 13z: a normal match needs EIGHT players — seven guests wait.
	seven, _ := joinNormalGuests(t, f, 7, 0)
	f.hub.TryPairNormalAll()
	if f.hub.NormalQueueLen() != 7 {
		t.Fatalf("7 guests must keep waiting, queue = %d", f.hub.NormalQueueLen())
	}
	if seven[0].in {
		t.Fatalf("no room may form below %d players", QueueMatchSize)
	}
	// The eighth guest completes the group, strictly FIFO.
	eight, senders := joinNormalGuests(t, f, 1, 7)
	_ = eight
	all := append(append([]*session{}, seven...), eight...)
	f.hub.TryPairNormalAll()
	if f.hub.NormalQueueLen() != 0 {
		t.Fatalf("queue not drained: %d left", f.hub.NormalQueueLen())
	}
	code := all[0].code
	for i, gs := range all {
		if !gs.in || gs.code != code {
			t.Fatalf("guest %d not bound to the room: %+v", i, gs)
		}
		if gs.slot != i {
			t.Fatalf("guest %d slot = %d, want %d (FIFO order)", i, gs.slot, i)
		}
	}
	mf := senders[0].ofType("match_found")
	if len(mf) != 1 || mf[0]["code"] != code {
		t.Fatalf("match_found A = %v", mf)
	}
	if mf[0]["ranked"] != false {
		t.Fatalf("match_found ranked = %v, want false", mf[0]["ranked"])
	}
	players, ok := mf[0]["players"].([]any)
	if !ok || len(players) != QueueMatchSize {
		t.Fatalf("match_found players = %v, want %d entries", mf[0]["players"], QueueMatchSize)
	}
	opp := mf[0]["opponent"].(map[string]any)
	if opp["display_name"] != "KhachB" || opp["user"] != "" {
		t.Fatalf("opponent = %v, want guest KhachB", opp)
	}
	if _, hasMMR := opp["mmr"]; hasMMR {
		t.Fatalf("normal match_found must not carry mmr: %v", opp)
	}
	if f.hub.IsRankedRoom(code) {
		t.Fatalf("normal room %s must not be ranked", code)
	}
	f.hub.mu.Lock()
	r := f.hub.rooms[code]
	f.hub.mu.Unlock()
	if r == nil || !r.Queued || r.Ranked || r.Host != 0 {
		t.Fatalf("room flags wrong: %+v", r)
	}
	if len(r.Players) != QueueMatchSize {
		t.Fatalf("room players = %d, want %d", len(r.Players), QueueMatchSize)
	}
	if r.Players[0].Name != "KhachA" || r.Players[7].Name != "KhachH" {
		t.Fatalf("player names = %q..%q", r.Players[0].Name, r.Players[7].Name)
	}
	for _, p := range r.Players {
		if p.Account {
			t.Fatalf("guests must not be account-bound")
		}
	}
}

func TestNormalQueueAccountAndGuestPair(t *testing.T) {
	f := newMMFixture(t)
	mustRegister(t, f.acc, "Alpha", 0)
	fa := &fakeSender{}
	sa := accountSession(f, "Alpha", fa)
	if err := f.hub.NormalQueueJoin(sa, "ignored-for-accounts"); err != nil {
		t.Fatalf("account join: %v", err)
	}
	guests, _ := joinNormalGuests(t, f, 7, 0)
	f.hub.TryPairNormalAll()
	if !sa.in || sa.slot != 0 {
		t.Fatalf("account should head the group at slot 0: %+v", sa)
	}
	for i, gs := range guests {
		if !gs.in || gs.slot != i+1 || gs.code != sa.code {
			t.Fatalf("guest %d not placed: %+v", i, gs)
		}
	}
	f.hub.mu.Lock()
	r := f.hub.rooms[sa.code]
	f.hub.mu.Unlock()
	if !r.Players[0].Account || r.Players[0].User != "Alpha" {
		t.Fatalf("slot 0 should be account Alpha: %+v", r.Players[0])
	}
	if r.Players[0].Name != "Alpha" {
		t.Fatalf("account display name = %q, want account name", r.Players[0].Name)
	}
	if r.Players[1].Account {
		t.Fatalf("guest slot must stay guest")
	}
	// The account's match_found names the first guest as opponent.
	mf := fa.ofType("match_found")
	opp := mf[0]["opponent"].(map[string]any)
	if opp["display_name"] != "KhachA" {
		t.Fatalf("opponent = %v", opp)
	}
}

func TestNormalQueueCancelAndCrossQueue(t *testing.T) {
	f := newMMFixture(t)
	mustRegister(t, f.acc, "Alpha", 0)
	fa := &fakeSender{}
	sa := accountSession(f, "Alpha", fa)
	if err := f.hub.NormalQueueJoin(sa, ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	// Already queued (normal) -> the ranked queue refuses too.
	if _, err := f.hub.QueueJoin(sa, RankedMode1v1); err != ErrAlreadyQueued {
		t.Fatalf("ranked join while normal-queued: %v, want ErrAlreadyQueued", err)
	}
	if err := f.hub.NormalQueueJoin(sa, ""); err != ErrAlreadyQueued {
		t.Fatalf("double normal join: %v, want ErrAlreadyQueued", err)
	}
	// The shared QueueLeave (client cancel / disconnect) finds it.
	if !f.hub.QueueLeave(sa) {
		t.Fatalf("QueueLeave should report the normal entry")
	}
	if f.hub.NormalQueueLen() != 0 {
		t.Fatalf("queue len = %d after leave", f.hub.NormalQueueLen())
	}
	// And the reverse direction: ranked-queued blocks normal join.
	if _, err := f.hub.QueueJoin(sa, RankedMode1v1); err != nil {
		t.Fatalf("ranked join: %v", err)
	}
	if err := f.hub.NormalQueueJoin(sa, ""); err != ErrAlreadyQueued {
		t.Fatalf("normal join while ranked-queued: %v, want ErrAlreadyQueued", err)
	}
	if !f.hub.QueueLeave(sa) || f.hub.QueueLen() != 0 {
		t.Fatalf("ranked leave cleanup failed")
	}
}

func TestNormalMatchResultBanksWLOnly(t *testing.T) {
	f := newMMFixture(t)
	mustRegister(t, f.acc, "WinA", 0)
	mustRegister(t, f.acc, "LoseB", 0)
	beforeW := profileOf(t, f.acc, "WinA")
	beforeL := profileOf(t, f.acc, "LoseB")
	fa, fb := &fakeSender{}, &fakeSender{}
	sa := accountSession(f, "WinA", fa)
	sb := accountSession(f, "LoseB", fb)
	if err := f.hub.NormalQueueJoin(sa, ""); err != nil {
		t.Fatalf("join A: %v", err)
	}
	if err := f.hub.NormalQueueJoin(sb, ""); err != nil {
		t.Fatalf("join B: %v", err)
	}
	// Six guests fill the 8-player group (13z); WinA is host
	// (slot 0), LoseB slot 1.
	guests, _ := joinNormalGuests(t, f, 6, 0)
	_ = guests
	f.hub.TryPairNormalAll()
	code := sa.code
	// The room auto-starts via the server countdown (3 beats).
	deadline := time.Now().Add(8 * time.Second)
	for {
		f.hub.mu.Lock()
		started := f.hub.rooms[code] != nil && f.hub.rooms[code].InMatch
		f.hub.mu.Unlock()
		if started {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("normal room never auto-started")
		}
		time.Sleep(50 * time.Millisecond)
	}
	// A non-host report is refused, and so is a broken list.
	if _, err := f.hub.RecordMatchPlacements(code, 1,
		[]int{0, 1, 2, 3, 4, 5, 6, 7}, nil); err != ErrNotHost {
		t.Fatalf("non-host placements: %v, want ErrNotHost", err)
	}
	if _, err := f.hub.RecordMatchPlacements(code, 0,
		[]int{0, 0, 2, 3, 4, 5, 6, 7}, nil); err != ErrBadPlacement {
		t.Fatalf("duplicate placements: %v, want ErrBadPlacement", err)
	}
	// Host (slot 0) reports the full placement list (13z): slot 0
	// first, slot 1 second — 2nd place is still a LOSS for banking.
	placements, err := f.hub.RecordMatchPlacements(code, 0,
		[]int{0, 1, 2, 3, 4, 5, 6, 7}, nil)
	if err != nil {
		t.Fatalf("record placements: %v", err)
	}
	if placements["WinA"] != 1 || placements["LoseB"] != 2 {
		t.Fatalf("placements = %v, want WinA 1 / LoseB 2", placements)
	}
	for user, placement := range placements {
		if err := f.acc.RecordMatch(user, placement == 1); err != nil {
			t.Fatalf("bank %s: %v", user, err)
		}
	}
	pw, pl := profileOf(t, f.acc, "WinA"), profileOf(t, f.acc, "LoseB")
	if pw.Wins != 1 || pw.Matches != 1 || pl.Losses != 1 || pl.Matches != 1 {
		t.Fatalf("W/L not banked: %+v / %+v", pw, pl)
	}
	// The whole point of the normal queue: MMR and ladder unmoved.
	if pw.MMR != beforeW.MMR || pl.MMR != beforeL.MMR {
		t.Fatalf("MMR moved: %d/%d (was %d/%d)", pw.MMR, pl.MMR, beforeW.MMR, beforeL.MMR)
	}
	if pw.Rank.RankText != beforeW.Rank.RankText || pl.Rank.RankText != beforeL.Rank.RankText {
		t.Fatalf("rank moved: %q/%q (was %q/%q)",
			pw.Rank.RankText, pl.Rank.RankText, beforeW.Rank.RankText, beforeL.Rank.RankText)
	}
	if pw.Rank.Stars != beforeW.Rank.Stars || pl.Rank.Stars != beforeL.Rank.Stars {
		t.Fatalf("stars moved: %d/%d", pw.Rank.Stars, pl.Rank.Stars)
	}
}
