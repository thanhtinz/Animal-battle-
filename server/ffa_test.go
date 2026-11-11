package main

// 13z tests: 8-player free-for-all queues — group formation
// (closest-seven ranked fill, strict FIFO normal), the placement
// star table with streak/daily composition and the ladder floor,
// FFA Elo directions, placement banking through the hub, and the
// queue_status progress push.

import (
	"fmt"
	"testing"
)

// registerFFAField registers n fresh accounts Play1..PlayN at
// one MMR and returns their usernames in order.
func registerFFAField(t *testing.T, f *mmFixture, n, mmr int) []string {
	t.Helper()
	users := make([]string, 0, n)
	for i := 1; i <= n; i++ {
		u := fmt.Sprintf("Play%d", i)
		mustRegister(t, f.acc, u, mmr)
		users = append(users, u)
	}
	return users
}

func TestRankedQueueClosestSeven(t *testing.T) {
	f := newMMFixture(t)
	mustRegister(t, f.acc, "Anchor", 1000)
	mustRegister(t, f.acc, "Far", 1090)
	anchor, _ := f.joinQueue(t, "Anchor")
	far, _ := f.joinQueue(t, "Far")
	closes := make([]*session, 0, 7)
	for i := 0; i < 7; i++ {
		name := fmt.Sprintf("Close%d", i)
		mustRegister(t, f.acc, name, 1010)
		s, _ := f.joinQueue(t, name)
		closes = append(closes, s)
	}
	f.hub.TryPairAll()
	// The group is anchor + the seven CLOSEST in-window players;
	// Far (diff 90, joined early) loses the last seat to the seven
	// at diff 10.
	if !anchor.in || anchor.slot != 0 {
		t.Fatalf("anchor should head the group: %+v", anchor)
	}
	for i, s := range closes {
		if !s.in || s.code != anchor.code {
			t.Fatalf("close %d not in the group: %+v", i, s)
		}
	}
	if far.in || f.hub.QueueLen() != 1 {
		t.Fatalf("far player must stay queued: in=%v len=%d", far.in, f.hub.QueueLen())
	}
}

func TestQueueStatusPush(t *testing.T) {
	f := newMMFixture(t)
	// Normal queue: three guests -> found 3/8 for everyone.
	guests, senders := joinNormalGuests(t, f, 3, 0)
	_ = guests
	f.hub.SendQueueStatus()
	for i, fs := range senders {
		st := fs.ofType("queue_status")
		if len(st) != 1 || st[0]["found"] != float64(3) ||
			st[0]["need"] != float64(QueueMatchSize) || st[0]["queue"] != "normal" {
			t.Fatalf("guest %d queue_status = %v", i, st)
		}
	}
	// No movement -> no duplicate push.
	f.hub.SendQueueStatus()
	if n := len(senders[0].ofType("queue_status")); n != 1 {
		t.Fatalf("queue_status resent without change: %d", n)
	}
	// Ranked queue: five accounts see the forming group's count.
	users := registerFFAField(t, f, 5, 1000)
	rankedSenders := make([]*fakeSender, 0, 5)
	for _, u := range users {
		_, fs := f.joinQueue(t, u)
		rankedSenders = append(rankedSenders, fs)
	}
	f.hub.SendQueueStatus()
	st := rankedSenders[0].ofType("queue_status")
	if len(st) != 1 || st[0]["found"] != float64(5) || st[0]["queue"] != "ranked" {
		t.Fatalf("ranked queue_status = %v", st)
	}
}

func TestFFAPlacementsStarTableAndElo(t *testing.T) {
	f := newMMFixture(t)
	users := registerFFAField(t, f, 8, 0) // all MMR 1000
	disc := map[string]bool{"Play8": true}   // last place disconnected
	outcomes, err := f.acc.RecordRankedPlacements(
		users, "grassland", "plains", 9000, "", disc)
	if err != nil {
		t.Fatalf("bank placements: %v", err)
	}
	// Equal ratings: every pairwise expectation is 0.5, so the
	// FFA Elo delta is round(32 * ((8-p)/7 - 0.5)).
	wantMMR := []int{1016, 1011, 1007, 1002, 998, 993, 989, 984}
	wantDelta := []int{3, 1, 1, 0, 0, 0, 0, 0} // P1: +2 table +1 daily; losers floored
	for i, oc := range outcomes {
		p := profileOf(t, f.acc, users[i])
		if oc.Placement != i+1 || p.MMR != wantMMR[i] {
			t.Fatalf("%s: placement %d MMR %d, want %d/%d",
				users[i], oc.Placement, p.MMR, i+1, wantMMR[i])
		}
		if oc.Rank.StarDelta != wantDelta[i] {
			t.Fatalf("%s: star delta %d, want %d", users[i], oc.Rank.StarDelta, wantDelta[i])
		}
		if i == 0 {
			if !oc.Won || !oc.Rank.DailyBonus || p.Wins != 1 || p.Matches != 1 {
				t.Fatalf("winner outcome wrong: %+v / %+v", oc, p)
			}
		} else if oc.Won || p.Losses != 1 || p.Matches != 1 {
			t.Fatalf("%s should bank a loss: %+v", users[i], p)
		}
	}
	// Stars actually sitting on the ladder: winner 3 (2 + daily),
	// 2nd/3rd one each, the rest zero (floor swallows the −1s).
	if s := profileOf(t, f.acc, "Play1").Rank.Stars; s != 3 {
		t.Fatalf("winner stars = %d, want 3", s)
	}
	if s := profileOf(t, f.acc, "Play2").Rank.Stars; s != 1 {
		t.Fatalf("2nd stars = %d, want 1", s)
	}
	if s := profileOf(t, f.acc, "Play8").Rank.Stars; s != 0 {
		t.Fatalf("8th stars = %d, want 0 (floor)", s)
	}
	// XP/Level derive from Matches/Wins: winner 10 + 20 = 30 XP,
	// everyone else 10 XP.
	if xp := profileOf(t, f.acc, "Play1").XP; xp != 30 {
		t.Fatalf("winner XP = %d, want 30", xp)
	}
	if xp := profileOf(t, f.acc, "Play5").XP; xp != 10 {
		t.Fatalf("mid XP = %d, want 10", xp)
	}
	// Reputation: the completion +1 clamps away at the 100 cap and
	// the disconnect −5 then applies in full — net 95, exactly the
	// 1v1 disconnect treatment in recordRankedResult.
	if c := profileOf(t, f.acc, "Play8").Credit; c != 95 {
		t.Fatalf("disconnect credit = %d, want 95", c)
	}
	// History carries the placement.
	a, _ := f.acc.store.GetAccount("Play8")
	if len(a.MatchHistory) != 1 || a.MatchHistory[0].Placement != 8 || a.MatchHistory[0].Won {
		t.Fatalf("P8 history = %+v", a.MatchHistory)
	}
	a1, _ := f.acc.store.GetAccount("Play1")
	if a1.MatchHistory[0].Placement != 1 || !a1.MatchHistory[0].Won {
		t.Fatalf("P1 history = %+v", a1.MatchHistory)
	}
}

func TestFFAStreakAndDemotion(t *testing.T) {
	f := newMMFixture(t)
	users := registerFFAField(t, f, 8, 0)
	// Seed P1 on a 2-win streak with today's daily already claimed
	// (isolates the streak star), and P8 mid-ladder with 0 stars
	// so a bottom finish must DEMOTE, not floor.
	a1, _ := f.acc.store.GetAccount("Play1")
	a1.Rank.Streak = 2
	a1.DailyBonusDay = dayKey(f.acc.now())
	if err := f.acc.store.PutAccount(a1); err != nil {
		t.Fatalf("seed P1: %v", err)
	}
	a8, _ := f.acc.store.GetAccount("Play8")
	a8.Rank.Tier = 1    // Chiến Binh
	a8.Rank.Division = 1 // đoàn II (encoding: 0=III, 1=II, 2=I)
	a8.Rank.Stars = 0
	if err := f.acc.store.PutAccount(a8); err != nil {
		t.Fatalf("seed P8: %v", err)
	}
	outcomes, err := f.acc.RecordRankedPlacements(users, "desert", "plains", 6000, "", nil)
	if err != nil {
		t.Fatalf("bank: %v", err)
	}
	// 1st: +2 table, streak hits 3 -> +1 bonus, no daily (claimed).
	if outcomes[0].Rank.StarDelta != 3 || !outcomes[0].Rank.Bonus ||
		outcomes[0].Rank.DailyBonus {
		t.Fatalf("streak outcome = %+v", outcomes[0].Rank)
	}
	if p := profileOf(t, f.acc, "Play1"); p.Rank.Streak != 3 {
		t.Fatalf("streak after win = %d, want 3", p.Rank.Streak)
	}
	// 8th from Chiến Binh II · 0 sao: demote to đoàn III with
	// cap−1 stars, delta −1.
	oc8 := outcomes[7]
	if oc8.Rank.StarDelta != -1 || !oc8.Rank.Demoted {
		t.Fatalf("demotion outcome = %+v", oc8.Rank)
	}
	p8 := profileOf(t, f.acc, "Play8")
	if p8.Rank.Division != 0 || p8.Rank.Stars != 2 {
		t.Fatalf("demoted position = div %d stars %d, want III (0) · 2 sao",
			p8.Rank.Division, p8.Rank.Stars)
	}
	// A mid placement breaks the streak without moving stars.
	outcomes2, err := f.acc.RecordRankedPlacements(
		[]string{"Play2", "Play3", "Play4", "Play5", "Play1", "Play6", "Play7", "Play8"},
		"desert", "plains", 6000, "", nil)
	if err != nil {
		t.Fatalf("bank 2: %v", err)
	}
	if outcomes2[4].Rank.StarDelta != 0 {
		t.Fatalf("5th place delta = %d, want 0", outcomes2[4].Rank.StarDelta)
	}
	if p := profileOf(t, f.acc, "Play1"); p.Rank.Streak != 0 {
		t.Fatalf("streak after mid finish = %d, want 0", p.Rank.Streak)
	}
	// Tín's streak definition (approved 2026-11-11): "win" means
	// PLACEMENT 1 ONLY — a 2nd place still pays its +1 star but
	// does NOT extend the streak; it breaks it like any non-win.
	a3, _ := f.acc.store.GetAccount("Play3")
	a3.Rank.Streak = 2
	if err := f.acc.store.PutAccount(a3); err != nil {
		t.Fatalf("seed Play3: %v", err)
	}
	outcomes3, err := f.acc.RecordRankedPlacements(
		[]string{"Play4", "Play3", "Play5", "Play6", "Play7", "Play8", "Play1", "Play2"},
		"desert", "plains", 6000, "", nil)
	if err != nil {
		t.Fatalf("bank 3: %v", err)
	}
	if outcomes3[1].Rank.StarDelta != 1 || outcomes3[1].Rank.Bonus {
		t.Fatalf("2nd place outcome = %+v, want +1 star, no bonus", outcomes3[1].Rank)
	}
	if p := profileOf(t, f.acc, "Play3"); p.Rank.Streak != 0 {
		t.Fatalf("streak after 2nd place = %d, want 0 (1st-only rule)", p.Rank.Streak)
	}
}

func TestHubRefereePlacements(t *testing.T) {
	f := newMMFixture(t)
	users := registerFFAField(t, f, 8, 0)
	sessions := make([]*session, 0, 8)
	for _, u := range users {
		s, _ := f.joinQueue(t, u)
		sessions = append(sessions, s)
	}
	f.hub.TryPairAll()
	code := sessions[0].code
	if code == "" {
		t.Fatalf("ranked group did not form")
	}
	// Player-side placement reports are refused in ranked rooms.
	if _, err := f.hub.RecordMatchPlacements(code, 0,
		[]int{0, 1, 2, 3, 4, 5, 6, 7}, nil); err != ErrRankedRoom {
		t.Fatalf("player placements in ranked room: %v", err)
	}
	// The room must be in a match; stage that flag like the
	// countdown would leave it.
	f.hub.mu.Lock()
	f.hub.rooms[code].InMatch = true
	f.hub.mu.Unlock()
	// Broken permutations are refused.
	if _, _, err := f.hub.RecordRefereePlacements(code,
		[]int{0, 1, 2, 3, 4, 5, 6, 6}, nil, nil); err != ErrBadPlacement {
		t.Fatalf("bad placements: %v, want ErrBadPlacement", err)
	}
	// Slot 7 wins, slot 0 finishes last; slot 0 disconnected.
	byUser, ordered, err := f.hub.RecordRefereePlacements(code,
		[]int{7, 6, 5, 4, 3, 2, 1, 0}, []int{0}, nil)
	if err != nil {
		t.Fatalf("referee placements: %v", err)
	}
	slotUser := map[int]string{}
	for _, s := range sessions {
		slotUser[s.slot] = s.user
	}
	if byUser[slotUser[7]] != 1 || byUser[slotUser[0]] != 8 {
		t.Fatalf("byUser wrong: %v", byUser)
	}
	if len(ordered) != 8 || ordered[0] != slotUser[7] || ordered[7] != slotUser[0] {
		t.Fatalf("ordered wrong: %v", ordered)
	}
	// Only once.
	if _, _, err := f.hub.RecordRefereePlacements(code,
		[]int{0, 1, 2, 3, 4, 5, 6, 7}, nil, nil); err != ErrResultRecorded {
		t.Fatalf("second report: %v, want ErrResultRecorded", err)
	}
}

// 14a: queue matches hand the sealed replay id out to every
// player (match_replay), and the elimination sidecar must agree
// with the placement order across the whole 8-player field.
func TestQueueReplayHandoutAndEvents(t *testing.T) {
	f := newMMFixture(t)
	f.hub.replays = NewMemReplayStore()
	users := registerFFAField(t, f, 8, 0)
	senders := make([]*fakeSender, 0, 8)
	sessions := make([]*session, 0, 8)
	for _, u := range users {
		s, fs := f.joinQueue(t, u)
		sessions = append(sessions, s)
		senders = append(senders, fs)
	}
	f.hub.TryPairAll()
	code := sessions[0].code
	if code == "" {
		t.Fatal("ranked group did not form")
	}
	f.hub.mu.Lock()
	room := f.hub.rooms[code]
	f.hub.startMatchLocked(room)
	room.Tick = 9000
	f.hub.mu.Unlock()
	// Placements in slot order; elimination ticks fall strictly
	// later for better placements (slot s falls at 100*s).
	placements := []int{0, 1, 2, 3, 4, 5, 6, 7}
	elim := []int64{-1, 800, 700, 600, 500, 400, 300, 200}
	if _, _, err := f.hub.RecordRefereePlacements(code, placements,
		nil, elim); err != nil {
		t.Fatalf("referee placements: %v", err)
	}
	rid := f.hub.RoomReplayID(code)
	if rid == "" {
		t.Fatal("no replay sealed for the ranked match")
	}
	rp, ok := f.hub.replays.Get(rid)
	if !ok || len(rp.Events) != 7 {
		t.Fatalf("events = %+v, want 7 eliminations", rp)
	}
	if rp.Events[0].Slot != 7 || rp.Events[6].Slot != 1 {
		t.Fatalf("events not sorted by tick: %+v", rp.Events)
	}
	f.hub.NotifyRoomReplay(code)
	for i, fs := range senders {
		msgs := fs.ofType("match_replay")
		if len(msgs) != 1 || msgs[0]["replay_id"] != rid {
			t.Fatalf("player %d handout = %v, want one match_replay %s",
				i, msgs, rid)
		}
	}
}

// 14a: an elimination order that contradicts the placements
// (a later placement fell LATER than an earlier one) drops the
// sidecar but never the result.
func TestQueueReplayEventsMonotonicity(t *testing.T) {
	f := newMMFixture(t)
	f.hub.replays = NewMemReplayStore()
	users := registerFFAField(t, f, 8, 0)
	sessions := make([]*session, 0, 8)
	for _, u := range users {
		s, _ := f.joinQueue(t, u)
		sessions = append(sessions, s)
	}
	f.hub.TryPairAll()
	code := sessions[0].code
	f.hub.mu.Lock()
	room := f.hub.rooms[code]
	f.hub.startMatchLocked(room)
	room.Tick = 9000
	f.hub.mu.Unlock()
	// Slot 2 (3rd place) supposedly fell AFTER slot 1 (2nd):
	// impossible — 2nd place outlives 3rd by definition.
	elim := []int64{-1, 200, 800, 600, 500, 400, 300, 250}
	byUser, _, err := f.hub.RecordRefereePlacements(code,
		[]int{0, 1, 2, 3, 4, 5, 6, 7}, nil, elim)
	if err != nil {
		t.Fatalf("banking must survive a bad sidecar: %v", err)
	}
	if len(byUser) != 8 {
		t.Fatalf("placements banked = %v", byUser)
	}
	rp, ok := f.hub.replays.Get(f.hub.RoomReplayID(code))
	if !ok {
		t.Fatal("replay not sealed")
	}
	if len(rp.Events) != 0 {
		t.Fatalf("contradictory events sealed: %+v", rp.Events)
	}
}
