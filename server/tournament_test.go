package main

// 15h tournament tests: bracket generation for all four
// bracket types (incl. byes for non-power-of-2 fields),
// advancement, round-robin standings tie-breaks, walkovers,
// dispute freeze + both resolution paths, rewards written
// exactly once, store persistence, and the hub trust model
// (referee-only results; players cannot report; no MMR/stars).

import (
	"fmt"
	"path/filepath"
	"testing"
	"time"
)

type tournEnv struct {
	ts    *Tournaments
	acc   *Accounts
	hub   *Hub
	clock *time.Time
}

func tournSetup(t *testing.T) *tournEnv {
	t.Helper()
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc := NewAccounts(fs)
	ts := NewTournaments(fs, acc)
	now := time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	clock := &now
	ts.now = func() time.Time { return *clock }
	hub := NewHub()
	hub.acc = acc
	hub.tourns = ts
	return &tournEnv{ts: ts, acc: acc, hub: hub, clock: clock}
}

func (e *tournEnv) reg(t *testing.T, users ...string) {
	t.Helper()
	for _, u := range users {
		if err := e.acc.Register(u, "secret1"); err != nil {
			t.Fatalf("register %s: %v", u, err)
		}
	}
}

// build creates a tournament, registers the given users as
// solo entries (or captain+partner pairs for team format from
// pairs), and opens check-in.
func (e *tournEnv) build(t *testing.T, creator, format, bracket string, size int, entrants ...string) *Tournament {
	t.Helper()
	tn, err := e.ts.Create(creator, "Giải test", format, bracket, size)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if format == "team" {
		for i := 0; i+1 < len(entrants); i += 2 {
			if err := e.ts.Register(tn.ID, entrants[i], entrants[i+1]); err != nil {
				t.Fatalf("register team %s: %v", entrants[i], err)
			}
		}
	} else {
		for _, u := range entrants {
			if err := e.ts.Register(tn.ID, u, ""); err != nil {
				t.Fatalf("register %s: %v", u, err)
			}
		}
	}
	if err := e.ts.OpenCheckin(tn.ID, creator); err != nil {
		t.Fatalf("open checkin: %v", err)
	}
	got, ok := e.ts.Get(tn.ID)
	if !ok {
		t.Fatalf("tournament vanished")
	}
	return got
}

// play settles a ready match through the service result path
// (MarkLive + ApplyResult, as the hub does for referee rooms).
func (e *tournEnv) play(t *testing.T, tn *Tournament, m *TournMatch, winner, scoreA, scoreB int, replay string) {
	t.Helper()
	if m.State == "done" {
		t.Fatalf("match %d already done", m.ID)
	}
	if err := e.ts.MarkLive(tn.ID, m.ID, "ROOMX"); err != nil {
		t.Fatalf("mark live match %d (%s): %v", m.ID, m.State, err)
	}
	if err := e.ts.ApplyResult(tn.ID, m.ID, winner, scoreA, scoreB, replay); err != nil {
		t.Fatalf("apply result match %d: %v", m.ID, err)
	}
}

// fresh reloads the tournament (post-refresh) for assertions.
func (e *tournEnv) fresh(t *testing.T, id string) *Tournament {
	t.Helper()
	tn, ok := e.ts.Get(id)
	if !ok {
		t.Fatalf("tournament %s missing", id)
	}
	return tn
}

func findMatch(tn *Tournament, stage string, a, b int) *TournMatch {
	for _, m := range tn.Matches {
		if m.Stage == stage && ((m.A == a && m.B == b) || (m.A == b && m.B == a)) {
			return m
		}
	}
	return nil
}

func profile(t *testing.T, acc *Accounts, user string) Profile {
	t.Helper()
	p, ok := acc.Profile(user)
	if !ok {
		t.Fatalf("profile %s missing", user)
	}
	return p
}

// ---------------------------------------------------------- validation

func TestTournValidation(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Play1", "Play2", "Play3")
	if _, err := env.ts.Create("", "Cup", "solo", "single_elim", 4); err == nil {
		t.Fatal("guest create must fail")
	}
	if _, err := env.ts.Create("Boss", "Cup", "solo", "single_elim", 5); err == nil {
		t.Fatal("size 5 must fail")
	}
	if _, err := env.ts.Create("Boss", "Cup", "solo", "swiss", 4); err == nil {
		t.Fatal("bad bracket must fail")
	}
	tn, err := env.ts.Create("Boss", "Cup", "team", "single_elim", 4)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := env.ts.Register(tn.ID, "Play1", "Ghost"); err == nil {
		t.Fatal("unknown partner must fail")
	}
	if err := env.ts.Register(tn.ID, "Play1", "Play2"); err != nil {
		t.Fatalf("register team: %v", err)
	}
	if err := env.ts.Register(tn.ID, "Play3", "Play2"); err == nil {
		t.Fatal("partner already in an entry must fail")
	}
	if err := env.ts.Register(tn.ID, "Play1", "Play3"); err == nil {
		t.Fatal("captain already in an entry must fail")
	}
	if err := env.ts.OpenCheckin(tn.ID, "Play3"); err == nil {
		t.Fatal("non-creator start must fail")
	}
	if err := env.ts.OpenCheckin(tn.ID, "Boss"); err == nil {
		t.Fatal("1 entry is too few for team SE")
	}
}

// ---------------------------------------------------------- single elim

func TestSingleElimGenerationAndByes(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung", "Emma")
	// 5 entries in an 8-cap: P=8, seeds 1,2,3 draw byes.
	tn := env.build(t, "Boss", "solo", "single_elim", 8, "Anh", "Bao", "Chi", "Dung", "Emma")
	if len(tn.Matches) != 7 {
		t.Fatalf("matches = %d, want 7", len(tn.Matches))
	}
	byes := 0
	for _, m := range tn.Matches {
		if m.Round == 1 && m.State == "done" && m.Bye {
			byes++
		}
	}
	if byes != 3 {
		t.Fatalf("round-1 byes = %d, want 3", byes)
	}
	// The one real round-1 match is seed 4 vs seed 5 (D vs E).
	real := findMatch(tn, "main", 4, 5)
	if real == nil || real.State != "ready" {
		t.Fatalf("seed4v5 match = %+v", real)
	}
	// Semis hold the bye winners already; the D/E semi side
	// stays UNSET until that match resolves.
	for _, m := range tn.Matches {
		if m.Round == 2 && (m.A == 1 || m.B == 1) {
			otherSet := m.BSet
			if m.B == 1 {
				otherSet = m.ASet
			}
			if otherSet {
				t.Fatalf("semi side should await the D/E winner: %+v", m)
			}
		}
	}
	// 16 entries: full bracket, 15 matches, no byes.
	env2 := tournSetup(t)
	users := []string{"Boss"}
	var field []string
	for i := 0; i < 16; i++ {
		u := fmt.Sprintf("Pl%02d", i+1)
		users = append(users, u)
		field = append(field, u)
	}
	env2.reg(t, users...)
	tn2 := env2.build(t, "Boss", "solo", "single_elim", 16, field...)
	if len(tn2.Matches) != 15 {
		t.Fatalf("16-field matches = %d, want 15", len(tn2.Matches))
	}
	for _, m := range tn2.Matches {
		if m.Bye {
			t.Fatal("full 16 field must have no byes")
		}
	}
}

func TestSingleElimPlaythroughAndRewards(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "single_elim", 4, "Anh", "Bao", "Chi", "Dung")
	// Seeds: SF1 = 1v4 (A v D), SF2 = 2v3 (B v C).
	sf1 := findMatch(tn, "main", 1, 4)
	sf2 := findMatch(tn, "main", 2, 3)
	env.play(t, tn, sf1, 1, 300, 100, "RP-SF1")
	env.play(t, tn, sf2, 2, 300, 100, "RP-SF2")
	tn = env.fresh(t, tn.ID)
	fin := findMatch(tn, "main", 1, 2)
	if fin == nil || fin.State != "ready" {
		t.Fatalf("final = %+v", fin)
	}
	env.play(t, tn, fin, 1, 400, 200, "RP-F")
	tn = env.fresh(t, tn.ID)
	if tn.State != "finished" || tn.Champion != 1 || tn.RunnerUp != 2 {
		t.Fatalf("state=%s champion=%d runner=%d", tn.State, tn.Champion, tn.RunnerUp)
	}
	pa := profile(t, env.acc, "Anh")
	if pa.Wins != 2 || pa.Matches != 2 {
		t.Fatalf("champion W/L = %d/%d, want 2 wins in 2", pa.Wins, pa.Matches)
	}
	if len(pa.TournHistory) != 1 || pa.TournHistory[0].Place != "champion" {
		t.Fatalf("champion history = %+v", pa.TournHistory)
	}
	hasTitle := false
	for _, x := range pa.Titles {
		if x == TitleChampion {
			hasTitle = true
		}
	}
	if !hasTitle {
		t.Fatalf("champion titles = %v", pa.Titles)
	}
	pb := profile(t, env.acc, "Bao")
	if pb.Wins != 1 || pb.Losses != 1 || len(pb.TournHistory) != 1 ||
		pb.TournHistory[0].Place != "runner_up" {
		t.Fatalf("runner-up = %+v history %+v", pb, pb.TournHistory)
	}
	// No ladder impact: MMR stays at the unrated default and
	// no season stars move.
	if pa.MMR != MMRStart || pa.SeasonStars != 0 {
		t.Fatalf("ladder touched: mmr=%d stars=%d", pa.MMR, pa.SeasonStars)
	}
	// Rewards exactly once: more refreshes/sweeps change nothing.
	env.ts.Sweep()
	_ = env.fresh(t, tn.ID)
	pa2 := profile(t, env.acc, "Anh")
	if len(pa2.TournHistory) != 1 {
		t.Fatalf("history after sweep = %d entries, want 1", len(pa2.TournHistory))
	}
	if err := env.acc.RecordTournamentFinish("Anh", tn.ID, tn.Name, "champion"); err != nil {
		t.Fatal(err)
	}
	if got := profile(t, env.acc, "Anh"); len(got.TournHistory) != 1 {
		t.Fatalf("idempotent finish write failed: %d entries", len(got.TournHistory))
	}
}

// ---------------------------------------------------------- double elim

func TestDoubleElimGeneration(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "double_elim", 4, "Anh", "Bao", "Chi", "Dung")
	if len(tn.Matches) != 6 {
		t.Fatalf("DE4 matches = %d, want 6 (WB3+LB2+GF1)", len(tn.Matches))
	}
	for _, m := range tn.Matches {
		if m.Stage != "gf" && m.WinTo == 0 {
			t.Fatalf("match %d (%s) has no winner feed", m.ID, m.Stage)
		}
		if m.Stage == "wb" && m.LoseTo == 0 {
			t.Fatalf("WB match %d has no loser feed", m.ID)
		}
	}
	env2 := tournSetup(t)
	env2.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung", "Emma", "Phuc", "Giang", "Hanh")
	tn2 := env2.build(t, "Boss", "solo", "double_elim", 8,
		"Anh", "Bao", "Chi", "Dung", "Emma", "Phuc", "Giang", "Hanh")
	if len(tn2.Matches) != 14 {
		t.Fatalf("DE8 matches = %d, want 14 (WB7+LB6+GF1)", len(tn2.Matches))
	}
}

func TestDoubleElimPlaythroughWithReset(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "double_elim", 4, "Anh", "Bao", "Chi", "Dung")
	// WB: A beats D, B beats C, A beats B.
	env.play(t, tn, findMatch(tn, "wb", 1, 4), 1, 10, 5, "R1")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "wb", 2, 3), 2, 10, 5, "R2")
	tn = env.fresh(t, tn.ID)
	// LB round 1: D vs C — C wins.
	lb1 := findMatch(tn, "lb", 4, 3)
	if lb1 == nil {
		t.Fatalf("LB1 (losers D,C) missing: %+v", tn.Matches)
	}
	env.play(t, tn, lb1, 3, 10, 5, "R3")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "wb", 1, 2), 1, 10, 5, "R4")
	tn = env.fresh(t, tn.ID)
	// LB final: C vs B (WB final loser) — B wins.
	lbf := findMatch(tn, "lb", 3, 2)
	if lbf == nil {
		t.Fatalf("LB final (C,B) missing")
	}
	env.play(t, tn, lbf, 2, 10, 5, "R5")
	tn = env.fresh(t, tn.ID)
	// Grand final: A (WB) vs B (LB). B wins -> reset match.
	gf := findMatch(tn, "gf", 1, 2)
	if gf == nil {
		t.Fatalf("grand final missing")
	}
	env.play(t, tn, gf, 2, 10, 5, "R6")
	tn = env.fresh(t, tn.ID)
	if tn.State == "finished" {
		t.Fatal("tournament must NOT finish when the LB champion wins GF1")
	}
	gf2 := findMatch(tn, "gf", 1, 2)
	// findMatch returns the first; find the round-2 one.
	for _, m := range tn.Matches {
		if m.Stage == "gf" && m.Round == 2 {
			gf2 = m
		}
	}
	if gf2 == nil || gf2.State != "ready" {
		t.Fatalf("reset match = %+v", gf2)
	}
	env.play(t, tn, gf2, 1, 10, 5, "R7")
	tn = env.fresh(t, tn.ID)
	if tn.State != "finished" || tn.Champion != 1 || tn.RunnerUp != 2 {
		t.Fatalf("after reset: state=%s champ=%d runner=%d", tn.State, tn.Champion, tn.RunnerUp)
	}
}

func TestDoubleElimNoResetWhenWBChampWins(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "double_elim", 4, "Anh", "Bao", "Chi", "Dung")
	env.play(t, tn, findMatch(tn, "wb", 1, 4), 1, 10, 5, "R1")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "wb", 2, 3), 2, 10, 5, "R2")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "lb", 4, 3), 4, 10, 5, "R3")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "wb", 1, 2), 1, 10, 5, "R4")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "lb", 4, 2), 2, 10, 5, "R5")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "gf", 1, 2), 1, 10, 5, "R6")
	tn = env.fresh(t, tn.ID)
	if tn.State != "finished" || tn.Champion != 1 {
		t.Fatalf("state=%s champ=%d", tn.State, tn.Champion)
	}
	if len(tn.Matches) != 6 {
		t.Fatalf("no reset expected: matches = %d", len(tn.Matches))
	}
}

// ---------------------------------------------------------- round robin

func TestRoundRobinStandingsTieBreak(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "round_robin", 4, "Anh", "Bao", "Chi", "Dung")
	if len(tn.Matches) != 6 {
		t.Fatalf("RR4 matches = %d, want 6", len(tn.Matches))
	}
	// Round gates: round-2 matches stay pending in round 1.
	for _, m := range tn.Matches {
		if m.Round > 1 && m.State != "pending" {
			t.Fatalf("round %d match %d state = %s, want pending (gate)", m.Round, m.ID, m.State)
		}
		if m.Round == 1 && m.State != "ready" {
			t.Fatalf("round 1 match %d state = %s, want ready", m.ID, m.State)
		}
	}
	// Script (see KE-HOACH): A wins all; B/C/D one win each;
	// scores break the tie C(180) > D(140) > B(130).
	script := []struct {
		a, b, winner, sa, sb int
	}{
		{1, 4, 1, 100, 50},
		{2, 3, 3, 40, 90},
		{1, 3, 1, 100, 30},
		{4, 2, 2, 20, 80},
		{1, 2, 1, 100, 10},
		{3, 4, 4, 60, 70},
	}
	for _, s := range script {
		tn = env.fresh(t, tn.ID)
		m := findMatch(tn, "rr", s.a, s.b)
		if m == nil {
			t.Fatalf("match %dv%d missing", s.a, s.b)
		}
		env.play(t, tn, m, s.winner, s.sa, s.sb, "RR")
	}
	tn = env.fresh(t, tn.ID)
	if tn.State != "finished" || tn.Champion != 1 || tn.RunnerUp != 3 {
		t.Fatalf("state=%s champ=%d runner=%d (want finished/1/3 by score tie-break)",
			tn.State, tn.Champion, tn.RunnerUp)
	}
	rows := standingsOf(tn, "rr")
	want := []int{1, 3, 4, 2}
	for i, w := range want {
		if rows[i].Entry != w {
			t.Fatalf("standings[%d] = entry %d, want %d (rows %+v)", i, rows[i].Entry, w, rows)
		}
	}
}

// ---------------------------------------------------------- group knockout

func TestGroupKnockoutSeeding(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung", "Emma", "Phuc", "Giang", "Hanh")
	tn := env.build(t, "Boss", "solo", "group_knockout", 8,
		"Anh", "Bao", "Chi", "Dung", "Emma", "Phuc", "Giang", "Hanh")
	if len(tn.Matches) != 15 {
		t.Fatalf("GK8 matches = %d, want 15 (6+6+2+1)", len(tn.Matches))
	}
	// Snake split: group A = seeds 1,4,5,8; group B = 2,3,6,7.
	if findMatch(tn, "ga", 1, 4) == nil || findMatch(tn, "gb", 2, 3) == nil {
		t.Fatal("group membership wrong (snake split)")
	}
	// Group A: 1 beats all; 4 beats 5,8; 5 beats 8.
	// Group B: 2 beats all; 3 beats 6,7; 6 beats 7.
	groupScript := []struct {
		stage      string
		a, b, wins int
	}{
		{"ga", 1, 4, 1}, {"ga", 1, 5, 1}, {"ga", 1, 8, 1},
		{"ga", 4, 5, 4}, {"ga", 4, 8, 4}, {"ga", 5, 8, 5},
		{"gb", 2, 3, 2}, {"gb", 2, 6, 2}, {"gb", 2, 7, 2},
		{"gb", 3, 6, 3}, {"gb", 3, 7, 3}, {"gb", 6, 7, 6},
	}
	// Group rounds gate sequentially, so play whichever
	// scripted match is currently ready, round by round.
	remaining := groupScript
	for len(remaining) > 0 {
		progress := false
		var next []struct {
			stage      string
			a, b, wins int
		}
		for _, s := range remaining {
			tn = env.fresh(t, tn.ID)
			m := findMatch(tn, s.stage, s.a, s.b)
			if m == nil {
				t.Fatalf("group match %s %dv%d missing", s.stage, s.a, s.b)
			}
			if m.State != "ready" {
				next = append(next, s)
				continue
			}
			env.play(t, tn, m, s.wins, 100, 50, "GRP")
			progress = true
		}
		if !progress {
			t.Fatalf("group script stuck: %+v", remaining)
		}
		remaining = next
	}
	tn = env.fresh(t, tn.ID)
	sf1 := findMatch(tn, "ko", 1, 3)
	sf2 := findMatch(tn, "ko", 2, 4)
	if sf1 == nil || sf2 == nil {
		t.Fatalf("semis not seeded A1vB2 / B1vA2: matches %+v", tn.Matches)
	}
	env.play(t, tn, sf1, 1, 100, 50, "SF")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "ko", 2, 4), 4, 100, 50, "SF")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "ko", 1, 4), 1, 100, 50, "Phuc")
	tn = env.fresh(t, tn.ID)
	if tn.State != "finished" || tn.Champion != 1 || tn.RunnerUp != 4 {
		t.Fatalf("state=%s champ=%d runner=%d", tn.State, tn.Champion, tn.RunnerUp)
	}
}

// ---------------------------------------------------------- walkovers

func TestWalkoverAutoAndManual(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "single_elim", 4, "Anh", "Bao", "Chi", "Dung")
	sf1 := findMatch(tn, "main", 1, 4)
	if err := env.ts.Checkin(tn.ID, sf1.ID, "Anh"); err != nil {
		t.Fatalf("checkin: %v", err)
	}
	// Inside the window: no walkover yet.
	*env.clock = env.clock.Add(9 * time.Minute)
	env.ts.Sweep()
	tn = env.fresh(t, tn.ID)
	if got := tn.match(sf1.ID); got.State == "done" {
		t.Fatal("walkover fired inside the window")
	}
	// Past the window: the checked-in side wins by walkover,
	// and NO W/L is banked for an unplayed match.
	*env.clock = env.clock.Add(2 * time.Minute)
	env.ts.Sweep()
	tn = env.fresh(t, tn.ID)
	got := tn.match(sf1.ID)
	if got.State != "done" || !got.Walkover || got.Winner != 1 {
		t.Fatalf("after window: %+v", got)
	}
	if p := profile(t, env.acc, "Anh"); p.Matches != 0 {
		t.Fatalf("walkover banked W/L: matches=%d", p.Matches)
	}
	// Neither side checked in on SF2: no automatic walkover —
	// the creator awards it manually instead.
	*env.clock = env.clock.Add(30 * time.Minute)
	env.ts.Sweep()
	tn = env.fresh(t, tn.ID)
	sf2 := findMatch(tn, "main", 2, 3)
	if sf2.State == "done" {
		t.Fatal("auto-walkover must not fire with neither side checked in")
	}
	if err := env.ts.AwardWalkover(tn.ID, sf2.ID, "Bao", 1); err == nil {
		t.Fatal("non-creator walkover must fail")
	}
	if err := env.ts.AwardWalkover(tn.ID, sf2.ID, "Boss", 1); err != nil {
		t.Fatalf("creator walkover: %v", err)
	}
	tn = env.fresh(t, tn.ID)
	if got := tn.match(sf2.ID); got.Winner != 3 || !got.Walkover {
		t.Fatalf("manual walkover: %+v", got)
	}
}

// ---------------------------------------------------------- disputes

func TestDisputeFreezeAndResolutions(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "single_elim", 4, "Anh", "Bao", "Chi", "Dung")
	sf1 := findMatch(tn, "main", 1, 4)
	sf2 := findMatch(tn, "main", 2, 3)
	env.play(t, tn, sf1, 1, 300, 100, "RP-SF1")
	env.play(t, tn, sf2, 2, 300, 100, "RP-SF2")
	tn = env.fresh(t, tn.ID)
	fin := findMatch(tn, "main", 1, 2)
	// Both finalists check in to the final.
	if err := env.ts.Checkin(tn.ID, fin.ID, "Anh"); err != nil {
		t.Fatal(err)
	}
	if err := env.ts.Checkin(tn.ID, fin.ID, "Bao"); err != nil {
		t.Fatal(err)
	}
	// Wrong replay id cannot flag.
	if err := env.ts.Dispute(tn.ID, sf1.ID, "Dung", "WRONG"); err == nil {
		t.Fatal("dispute with wrong replay id must fail")
	}
	// The loser of SF1 flags it with the real replay id.
	if err := env.ts.Dispute(tn.ID, sf1.ID, "Dung", "RP-SF1"); err != nil {
		t.Fatalf("dispute: %v", err)
	}
	// The final is now frozen: even fully checked in, it
	// cannot launch.
	if _, _, _, err := env.ts.PlayableFor(tn.ID, fin.ID, "Anh"); err == nil {
		t.Fatal("final must be frozen while SF1 is disputed")
	}
	// Uphold: result stands, final unfreezes.
	if err := env.ts.ResolveDispute(tn.ID, sf1.ID, "Boss", true); err != nil {
		t.Fatalf("resolve uphold: %v", err)
	}
	if _, _, _, err := env.ts.PlayableFor(tn.ID, fin.ID, "Anh"); err != nil {
		t.Fatalf("final should be playable after uphold: %v", err)
	}
	// Flag again and resolve with a REPLAY: the result is
	// voided, its W/L unbanked, the final's side cleared.
	if err := env.ts.Dispute(tn.ID, sf1.ID, "Dung", "RP-SF1"); err != nil {
		t.Fatalf("re-dispute: %v", err)
	}
	if err := env.ts.ResolveDispute(tn.ID, sf1.ID, "Boss", false); err != nil {
		t.Fatalf("resolve replay: %v", err)
	}
	tn = env.fresh(t, tn.ID)
	got := tn.match(sf1.ID)
	if got.State != "ready" || got.Winner != 0 || got.Played {
		t.Fatalf("after replay resolution: %+v", got)
	}
	if p := profile(t, env.acc, "Anh"); p.Wins != 0 || p.Matches != 0 {
		t.Fatalf("W/L not unbanked: %+v", p)
	}
	if p := profile(t, env.acc, "Dung"); p.Losses != 0 {
		t.Fatalf("loser W/L not unbanked: %+v", p)
	}
	finNow := tn.match(fin.ID)
	if finNow.ASet {
		t.Fatalf("final side A should be cleared, got %+v", finNow)
	}
	// Rematch: D wins this time and takes the final slot.
	env.play(t, tn, got, 4, 300, 100, "RP-SF1B")
	tn = env.fresh(t, tn.ID)
	if finNow = tn.match(fin.ID); !finNow.ASet || finNow.A != 4 {
		t.Fatalf("final after rematch: %+v", finNow)
	}
}

func TestDisputeTooLateAfterDownstreamPlayed(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "single_elim", 4, "Anh", "Bao", "Chi", "Dung")
	env.play(t, tn, findMatch(tn, "main", 1, 4), 1, 10, 5, "RP1")
	env.play(t, tn, findMatch(tn, "main", 2, 3), 2, 10, 5, "RP2")
	tn = env.fresh(t, tn.ID)
	env.play(t, tn, findMatch(tn, "main", 1, 2), 1, 10, 5, "RP3")
	// The tournament is finished: too late for any dispute.
	sf1 := findMatch(env.fresh(t, tn.ID), "main", 1, 4)
	if err := env.ts.Dispute(tn.ID, sf1.ID, "Dung", "RP1"); err == nil {
		t.Fatal("dispute after tournament finish must fail")
	}
}

// ---------------------------------------------------------- persistence + hub trust

func TestTournamentPersistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc := NewAccounts(fs)
	ts := NewTournaments(fs, acc)
	for _, u := range []string{"Boss", "Anh", "Bao", "Chi", "Dung"} {
		if err := acc.Register(u, "secret1"); err != nil {
			t.Fatal(err)
		}
	}
	tn, err := ts.Create("Boss", "Persist Cup", "solo", "single_elim", 4)
	if err != nil {
		t.Fatal(err)
	}
	for _, u := range []string{"Anh", "Bao", "Chi", "Dung"} {
		if err := ts.Register(tn.ID, u, ""); err != nil {
			t.Fatal(err)
		}
	}
	if err := ts.OpenCheckin(tn.ID, "Boss"); err != nil {
		t.Fatal(err)
	}
	// A fresh store+service over the same file sees it all.
	fs2, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	ts2 := NewTournaments(fs2, NewAccounts(fs2))
	got, ok := ts2.Get(tn.ID)
	if !ok || len(got.Entries) != 4 || len(got.Matches) != 3 || got.State != "checkin" {
		t.Fatalf("reloaded: ok=%v entries=%d matches=%d state=%s",
			ok, len(got.Entries), len(got.Matches), got.State)
	}
}

func TestHubTournamentRoomTrustModel(t *testing.T) {
	env := tournSetup(t)
	env.reg(t, "Boss", "Anh", "Bao", "Chi", "Dung")
	tn := env.build(t, "Boss", "solo", "single_elim", 4, "Anh", "Bao", "Chi", "Dung")
	sf1 := findMatch(tn, "main", 1, 4)
	if err := env.ts.Checkin(tn.ID, sf1.ID, "Anh"); err != nil {
		t.Fatal(err)
	}
	if err := env.ts.Checkin(tn.ID, sf1.ID, "Dung"); err != nil {
		t.Fatal(err)
	}
	sa, sd := &fakeSender{}, &fakeSender{}
	code, slotA, err := env.hub.TournamentPlayRoom(sa, tn.ID, sf1.ID, "Anh")
	if err != nil {
		t.Fatalf("play room A: %v", err)
	}
	code2, slotD, err := env.hub.TournamentPlayRoom(sd, tn.ID, sf1.ID, "Dung")
	if err != nil {
		t.Fatalf("play room D: %v", err)
	}
	if code != code2 || slotA != 0 || slotD != 1 {
		t.Fatalf("rooms/slots: %s/%d vs %s/%d", code, slotA, code2, slotD)
	}
	r := env.hub.rooms[code]
	if r == nil || !r.Ranked || !r.Tournament || r.Queued {
		t.Fatalf("room flags: %+v", r)
	}
	if r.RefereeTokenHash == [32]byte{} {
		t.Fatal("referee token hash not set")
	}
	if !env.hub.IsTournamentRoom(code) {
		t.Fatal("IsTournamentRoom false")
	}
	// A PLAYER trying to report this room's result is refused
	// (ranked rooms belong to the referee).
	if _, err := env.hub.RecordMatchResult(code, slotA, 0, nil); err == nil {
		t.Fatal("player-reported result on a tournament room must fail")
	}
	// The referee path banks it into the tournament instead.
	r.InMatch = true // (normally set by startMatchLocked)
	results, err := env.hub.RecordRefereeResult(code, 0, "elimination", nil)
	if err != nil {
		t.Fatalf("referee result: %v", err)
	}
	if err := env.hub.TournamentMatchResult(code, results, []int{500, 300}); err != nil {
		t.Fatalf("apply tournament result: %v", err)
	}
	tn = env.fresh(t, tn.ID)
	got := tn.match(sf1.ID)
	if got.State != "done" || got.Winner != 1 || got.ScoreA != 500 || got.ScoreB != 300 {
		t.Fatalf("match after referee result: %+v", got)
	}
	if p := profile(t, env.acc, "Anh"); p.Wins != 1 || p.MMR != MMRStart || p.SeasonStars != 0 {
		t.Fatalf("winner profile: wins=%d mmr=%d stars=%d", p.Wins, p.MMR, p.SeasonStars)
	}
	// Exactly once: a second referee report for the room is
	// refused by the hub, and re-applying changes nothing.
	if _, err := env.hub.RecordRefereeResult(code, 0, "elimination", nil); err == nil {
		t.Fatal("second result for one room must fail")
	}
}
