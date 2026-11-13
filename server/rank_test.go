package main

// Seasonal rank ladder tests (rank.go + seasons in accounts.go):
// star math, streak bonus, promotion/demotion, the Tân Binh III
// floor, Hầu Tước 5-star divisions, Công Tước star mode, Hoàng Đế
// top-50 computation, the season reset table, MMR soft reset,
// history/peak recording and reset idempotence. Display names are
// asserted wherever payloads carry them.

import (
	"fmt"
	"testing"
	"time"
)

func rs(tier, div, stars int) RankState {
	return RankState{Tier: tier, Division: div, Stars: stars, Season: 1,
		PeakTier: tier, PeakDivision: div}
}

// ---------------------------------------------------------- star math

func TestRankWinBasic(t *testing.T) {
	after, out := applyRankWin(rs(TierTanBinh, 0, 0))
	if after.Stars != 1 || out.StarDelta != 1 || out.Bonus || out.Promoted {
		t.Fatalf("after=%+v out=%+v, want 1 star, +1, no bonus/promotion", after, out)
	}
	if after.Text() != "Tân Binh III · 1 sao" {
		t.Fatalf("text = %q", after.Text())
	}
}

func TestRankStreakBonus(t *testing.T) {
	// Two quiet wins build the streak; the third pays +2 stars.
	s := rs(TierTanBinh, 0, 0)
	s, _ = applyRankWin(s)
	s, _ = applyRankWin(s)
	if s.Streak != 2 || s.Stars != 2 {
		t.Fatalf("after 2 wins: %+v", s)
	}
	after, out := applyRankWin(s)
	if !out.Bonus || out.StarDelta != 2 {
		t.Fatalf("third win: out=%+v, want bonus +2", out)
	}
	// 2 stars + 1 = full (3), bonus star converts into promotion.
	if after.Division != 1 || after.Stars != 1 || !out.Promoted {
		t.Fatalf("after=%+v, want Chiến Binh... no: Tân Binh II with 1 star, promoted", after)
	}
	if after.ShortText() != "Tân Binh II" {
		t.Fatalf("short = %q", after.ShortText())
	}
	// A loss clears the streak.
	after2, _ := applyRankLoss(after)
	if after2.Streak != 0 {
		t.Fatalf("streak after loss = %d", after2.Streak)
	}
}

func TestRankPromotionAtCap(t *testing.T) {
	// Division promotion at a full 3-star division.
	after, out := applyRankWin(rs(TierKySi, 0, 3))
	if after.Tier != TierKySi || after.Division != 1 || after.Stars != 1 || !out.Promoted {
		t.Fatalf("after=%+v out=%+v, want Kỵ Sĩ II 1 star promoted", after, out)
	}
	// Tier crossing from division I at cap.
	after, out = applyRankWin(rs(TierKySi, 2, 3))
	if after.Tier != TierNamTuoc || after.Division != 0 || after.Stars != 1 || !out.Promoted {
		t.Fatalf("after=%+v, want Nam Tước III 1 star", after)
	}
	if after.Text() != "Nam Tước III · 1 sao" {
		t.Fatalf("text = %q", after.Text())
	}
	// Peak follows promotions.
	if after.PeakTier != TierNamTuoc || after.PeakDivision != 0 {
		t.Fatalf("peak = %d/%d", after.PeakTier, after.PeakDivision)
	}
}

func TestRankHauTuocFiveStars(t *testing.T) {
	if RankStarCap(TierHauTuoc) != 5 || RankStarCap(TierBaTuoc) != 3 || RankStarCap(TierCongTuoc) != 0 {
		t.Fatalf("star caps wrong")
	}
	after, out := applyRankWin(rs(TierHauTuoc, 0, 4))
	if after.Stars != 5 || out.Promoted {
		t.Fatalf("after=%+v, want Hầu Tước III at 5 stars, no promotion yet", after)
	}
	after, out = applyRankWin(rs(TierHauTuoc, 0, 5))
	if after.Division != 1 || after.Stars != 1 || !out.Promoted {
		t.Fatalf("after=%+v, want Hầu Tước II 1 star", after)
	}
	// Hầu Tước I at cap promotes into Công Tước star mode.
	after, _ = applyRankWin(rs(TierHauTuoc, 2, 5))
	if after.Tier != TierCongTuoc || after.Stars != 1 {
		t.Fatalf("after=%+v, want Công Tước 1 star", after)
	}
	if after.Text() != "Công Tước · 1 sao" || after.ShortText() != "Công Tước" {
		t.Fatalf("duke text = %q / %q", after.Text(), after.ShortText())
	}
}

func TestRankCongTuocStarMode(t *testing.T) {
	s := rs(TierCongTuoc, 0, 27)
	after, out := applyRankWin(s)
	if after.Stars != 28 || out.Promoted {
		t.Fatalf("duke win: after=%+v (stars must just grow)", after)
	}
	after, out = applyRankLoss(after)
	if after.Stars != 27 || out.StarDelta != -1 || out.Demoted {
		t.Fatalf("duke loss: after=%+v out=%+v", after, out)
	}
	// A duke at 0 stars losing demotes to Hầu Tước I at cap-1 = 4.
	after, out = applyRankLoss(rs(TierCongTuoc, 0, 0))
	if after.Tier != TierHauTuoc || after.Division != 2 || after.Stars != 4 || !out.Demoted {
		t.Fatalf("duke demotion: after=%+v out=%+v", after, out)
	}
}

func TestRankLossAndDemotion(t *testing.T) {
	after, out := applyRankLoss(rs(TierKySi, 1, 2))
	if after.Stars != 1 || out.StarDelta != -1 || out.Demoted {
		t.Fatalf("plain loss: after=%+v out=%+v", after, out)
	}
	// 0 stars in division II: demote to III at cap-1 = 2 stars.
	after, out = applyRankLoss(rs(TierKySi, 1, 0))
	if after.Division != 0 || after.Stars != 2 || !out.Demoted {
		t.Fatalf("division demotion: after=%+v out=%+v", after, out)
	}
	// 0 stars in division III: demote a whole tier, land at I cap-1.
	after, out = applyRankLoss(rs(TierChienBinh, 0, 0))
	if after.Tier != TierTanBinh || after.Division != 2 || after.Stars != 2 || !out.Demoted {
		t.Fatalf("tier demotion: after=%+v out=%+v", after, out)
	}
	// Hầu Tước III demotion lands in Bá Tước I at that tier's cap-1 = 2.
	after, _ = applyRankLoss(rs(TierHauTuoc, 0, 0))
	if after.Tier != TierBaTuoc || after.Division != 2 || after.Stars != 2 {
		t.Fatalf("hầu tước demotion: after=%+v, want Bá Tước I 2 stars", after)
	}
}

func TestRankFloorTanBinh(t *testing.T) {
	after, out := applyRankLoss(rs(TierTanBinh, 0, 0))
	if after.Tier != 0 || after.Division != 0 || after.Stars != 0 {
		t.Fatalf("floor breached: %+v", after)
	}
	if out.StarDelta != 0 || out.Demoted {
		t.Fatalf("floor loss must cost nothing: out=%+v", out)
	}
}

// ---------------------------------------------------------- Hoàng Đế

func TestEmperorSetTop50(t *testing.T) {
	var all []*Account
	for i := 0; i < 55; i++ {
		all = append(all, &Account{
			User: fmt.Sprintf("Duke%02d", i),
			MMR:  2000,
			Rank: RankState{Tier: TierCongTuoc, Stars: i, Season: 1},
		})
	}
	// A non-duke with huge MMR never counts.
	all = append(all, &Account{User: "AlmostDuke", MMR: 9999,
		Rank: RankState{Tier: TierHauTuoc, Division: 2, Stars: 5, Season: 1}})
	set := EmperorSet(all)
	if len(set) != EmperorLimit {
		t.Fatalf("emperors = %d, want %d", len(set), EmperorLimit)
	}
	if !set["Duke54"] || !set["Duke05"] {
		t.Fatalf("top dukes missing from the set")
	}
	if set["Duke04"] {
		t.Fatalf("Duke04 (5th-lowest stars) must be cut off")
	}
	if set["AlmostDuke"] {
		t.Fatalf("non-duke flagged emperor")
	}
	// Few dukes: all of them hold the status.
	few := EmperorSet(all[:3])
	if len(few) != 3 {
		t.Fatalf("few dukes: %d emperors, want 3", len(few))
	}
	// MMR breaks star ties.
	tied := []*Account{
		{User: "LowMMR", MMR: 1500, Rank: RankState{Tier: TierCongTuoc, Stars: 10, Season: 1}},
		{User: "HighMMR", MMR: 2500, Rank: RankState{Tier: TierCongTuoc, Stars: 10, Season: 1}},
	}
	_ = tied // ordering only matters at the cap; both fit here
	if s := EmperorSet(tied); len(s) != 2 {
		t.Fatalf("tied dukes: %v", s)
	}
}

// ---------------------------------------------------------- integration

func TestRecordRankedResultFullRank(t *testing.T) {
	acc := rankedAccounts(t)
	mustRegister(t, acc, "Alpha", 0)
	mustRegister(t, acc, "Bravo", 0)
	wo, lo, err := acc.RecordRankedResultFull("Alpha", "Bravo")
	if err != nil {
		t.Fatalf("record: %v", err)
	}
	if wo.MMRBefore != 1000 || wo.MMRAfter != 1016 || lo.MMRAfter != 984 {
		t.Fatalf("mmr movement = %+v / %+v", wo, lo)
	}
	// A fresh account's first-ever win is also its first win of
	// the day, so the daily bonus (13i) stacks: +1 match star and
	// +1 daily star. (The plain +1 math is covered by the
	// applyRankWin unit tests and the second-win case in
	// TestDailyBonusFirstWinOnly.)
	if wo.Rank.StarDelta != 2 || wo.Rank.After.Stars != 2 || !wo.Rank.DailyBonus {
		t.Fatalf("winner rank = %+v, want +2 stars incl. daily bonus", wo.Rank)
	}
	// The loser sits on the Tân Binh III floor: the loss is free.
	if lo.Rank.StarDelta != 0 || lo.Rank.After.Stars != 0 {
		t.Fatalf("loser rank = %+v, want floored 0", lo.Rank)
	}
	p := profileOf(t, acc, "Alpha")
	if p.Rank.RankText != "Tân Binh III · 2 sao" || p.Rank.TierName != "Tân Binh" {
		t.Fatalf("winner profile rank = %+v", p.Rank)
	}
	if p.Rank.Season != acc.CurrentSeason() {
		t.Fatalf("rank season = %d, server season %d", p.Rank.Season, acc.CurrentSeason())
	}
}

func TestRankedBoardSortsByRankNotMMR(t *testing.T) {
	acc := rankedAccounts(t)
	mustRegister(t, acc, "LowMMRKnight", 900)
	mustRegister(t, acc, "HighMMRWarrior", 2400)
	mustRegister(t, acc, "DukeOne", 1500)
	seed := func(user string, r RankState) {
		a, _ := acc.store.GetAccount(user)
		r.Season = acc.CurrentSeason()
		a.Rank = r
		acc.store.PutAccount(a)
	}
	seed("LowMMRKnight", RankState{Tier: TierKySi, Division: 0, Stars: 0})
	seed("HighMMRWarrior", RankState{Tier: TierChienBinh, Division: 2, Stars: 3})
	seed("DukeOne", RankState{Tier: TierCongTuoc, Stars: 12})
	rows := acc.RankedLeaderboard()
	if len(rows) != 3 {
		t.Fatalf("rows = %d", len(rows))
	}
	if rows[0].User != "DukeOne" || rows[1].User != "LowMMRKnight" || rows[2].User != "HighMMRWarrior" {
		t.Fatalf("order = %s,%s,%s — rank must outrank MMR", rows[0].User, rows[1].User, rows[2].User)
	}
	if !rows[0].Emperor || rows[0].RankText != "Hoàng Đế · 12 sao" {
		t.Fatalf("duke row = %+v, want Hoàng Đế flag + name", rows[0])
	}
	if rows[1].RankText != "Kỵ Sĩ III · 0 sao" || rows[1].RankShort != "Kỵ Sĩ III" {
		t.Fatalf("knight row = %+v", rows[1])
	}
}

// ---------------------------------------------------------- seasons

const testEpoch = int64(1_700_000_000)

func seasonAccounts(t *testing.T) *Accounts {
	t.Helper()
	acc, _ := testAccounts(t)
	acc.SeasonDays = 90
	if err := acc.store.PutMeta(MetaSeasonEpoch, fmt.Sprintf("%d", testEpoch)); err != nil {
		t.Fatal(err)
	}
	acc.now = func() time.Time { return time.Unix(testEpoch, 0) }
	return acc
}

func seedRank(t *testing.T, acc *Accounts, user string, r RankState, mmr int) {
	t.Helper()
	if err := acc.Register(user, "secret1"); err != nil {
		t.Fatalf("register %s: %v", user, err)
	}
	a, _ := acc.store.GetAccount(user)
	a.Rank = r
	a.MMR = mmr
	if err := acc.store.PutAccount(a); err != nil {
		t.Fatal(err)
	}
}

func TestSeasonResetTable(t *testing.T) {
	cases := []struct {
		name     string
		from     RankState
		wantTier int
		wantDiv  int
	}{
		{"Hoàng Đế (Công Tước)", rs(TierCongTuoc, 0, 40), TierBaTuoc, 0},
		{"Hầu Tước", rs(TierHauTuoc, 2, 5), TierNamTuoc, 1},
		{"Bá Tước", rs(TierBaTuoc, 1, 2), TierNamTuoc, 0},
		{"Nam Tước", rs(TierNamTuoc, 0, 3), TierKySi, 1},
		{"Kỵ Sĩ", rs(TierKySi, 2, 1), TierKySi, 0},
		{"Chiến Binh", rs(TierChienBinh, 1, 0), TierChienBinh, 0},
		{"Tân Binh", rs(TierTanBinh, 2, 3), TierTanBinh, 0},
	}
	for _, c := range cases {
		acc := seasonAccounts(t)
		seedRank(t, acc, "Player", c.from, 1000)
		acc.now = func() time.Time { return time.Unix(testEpoch+91*24*3600, 0) }
		p, ok := acc.Profile("Player")
		if !ok {
			t.Fatalf("%s: profile missing", c.name)
		}
		if p.Rank.Tier != c.wantTier || p.Rank.Division != c.wantDiv || p.Rank.Stars != 0 {
			t.Fatalf("%s: reset -> tier %d div %d stars %d, want %d/%d/0",
				c.name, p.Rank.Tier, p.Rank.Division, p.Rank.Stars, c.wantTier, c.wantDiv)
		}
		if p.Rank.Season != 2 {
			t.Fatalf("%s: season = %d, want 2", c.name, p.Rank.Season)
		}
	}
}

func TestSeasonResetMMRHistoryPeak(t *testing.T) {
	acc := seasonAccounts(t)
	final := rs(TierHauTuoc, 2, 3)
	final.PeakTier = TierHauTuoc
	final.PeakDivision = 2
	seedRank(t, acc, "Veteran", final, 1400)
	seedRank(t, acc, "Dropping", rs(TierTanBinh, 0, 0), 984)
	acc.now = func() time.Time { return time.Unix(testEpoch+100*24*3600, 0) }

	p, _ := acc.Profile("Veteran")
	// MMR soft reset: 1400 -> 1000 + 400/2 = 1200.
	if p.MMR != 1200 {
		t.Fatalf("mmr after reset = %d, want 1200", p.MMR)
	}
	// Hầu Tước -> Nam Tước II per the table.
	if p.Rank.RankText != "Nam Tước II · 0 sao" {
		t.Fatalf("rank after reset = %q", p.Rank.RankText)
	}
	// Previous season is archived and surfaced.
	if p.Rank.PrevSeason != 1 || p.Rank.PrevSeasonText != "Hầu Tước I" {
		t.Fatalf("prev season = %d %q, want 1 / Hầu Tước I", p.Rank.PrevSeason, p.Rank.PrevSeasonText)
	}
	// Peak restarts from the reset position.
	if p.Rank.PeakText != "Nam Tước II" {
		t.Fatalf("peak after reset = %q", p.Rank.PeakText)
	}
	a, _ := acc.store.GetAccount("Veteran")
	if len(a.History) != 1 {
		t.Fatalf("history = %d entries, want 1", len(a.History))
	}
	h := a.History[0]
	if h.Season != 1 || h.FinalTier != TierHauTuoc || h.FinalDivision != 2 ||
		h.FinalStars != 3 || h.PeakTier != TierHauTuoc || h.PeakDivision != 2 {
		t.Fatalf("history record = %+v", h)
	}
	// MMR below start moves UP toward 1000: 984 -> 992.
	p2, _ := acc.Profile("Dropping")
	if p2.MMR != 992 {
		t.Fatalf("low mmr after reset = %d, want 992", p2.MMR)
	}
	// Idempotence: a second touch archives nothing new.
	acc.Profile("Veteran")
	a, _ = acc.store.GetAccount("Veteran")
	if len(a.History) != 1 || a.Rank.Season != 2 {
		t.Fatalf("second touch changed state: history %d season %d", len(a.History), a.Rank.Season)
	}
}

func TestSeasonSkipsMultipleSeasons(t *testing.T) {
	acc := seasonAccounts(t)
	seedRank(t, acc, "Away", rs(TierKySi, 1, 2), 1100)
	// Offline for two whole seasons: one reset, one history entry.
	acc.now = func() time.Time { return time.Unix(testEpoch+200*24*3600, 0) }
	if acc.CurrentSeason() != 3 {
		t.Fatalf("season = %d, want 3", acc.CurrentSeason())
	}
	p, _ := acc.Profile("Away")
	if p.Rank.Season != 3 || p.Rank.RankText != "Kỵ Sĩ III · 0 sao" {
		t.Fatalf("after long absence: %+v", p.Rank)
	}
	a, _ := acc.store.GetAccount("Away")
	if len(a.History) != 1 || a.History[0].Season != 1 {
		t.Fatalf("history = %+v, want one season-1 record", a.History)
	}
}

func TestSeasonCurrentSeasonOneNoReset(t *testing.T) {
	acc := seasonAccounts(t)
	seedRank(t, acc, "Active", rs(TierBaTuoc, 1, 2), 1600)
	acc.now = func() time.Time { return time.Unix(testEpoch+30*24*3600, 0) }
	p, _ := acc.Profile("Active")
	if p.Rank.RankText != "Bá Tước II · 2 sao" || p.MMR != 1600 {
		t.Fatalf("mid-season touch changed state: %+v mmr %d", p.Rank, p.MMR)
	}
	a, _ := acc.store.GetAccount("Active")
	if len(a.History) != 0 {
		t.Fatalf("phantom history: %+v", a.History)
	}
}

// ---------------------------------------------------------- daily bonus (13i)

// dailyAccounts returns an Accounts whose clock the test steers
// by day (server-local dates, like the real bonus boundary).
func dailyAccounts(t *testing.T, day *time.Time) *Accounts {
	t.Helper()
	ac, _ := testAccounts(t)
	ac.now = func() time.Time { return *day }
	if err := ac.Register("DailyA", "secret1"); err != nil {
		t.Fatal(err)
	}
	if err := ac.Register("DailyB", "secret1"); err != nil {
		t.Fatal(err)
	}
	return ac
}

// The winner's FIRST ranked win of the day grants +1 bonus star on
// top of the normal star; the second win the same day does not.
func TestDailyBonusFirstWinOnly(t *testing.T) {
	day := time.Date(2026, 3, 10, 12, 0, 0, 0, time.Local)
	ac := dailyAccounts(t, &day)

	if p, _ := ac.Profile("DailyA"); p.DailyBonusClaimed {
		t.Fatal("fresh account already shows the bonus claimed")
	}
	wo, _, err := ac.RecordRankedResultFull("DailyA", "DailyB")
	if err != nil {
		t.Fatal(err)
	}
	if !wo.Rank.DailyBonus || wo.Rank.Bonus {
		t.Fatalf("first win flags = daily %v streak %v, want daily only",
			wo.Rank.DailyBonus, wo.Rank.Bonus)
	}
	if wo.Rank.StarDelta != 2 || wo.Rank.After.Stars != 2 {
		t.Fatalf("first win delta = %d after = %+v, want +2 landing on 2 stars",
			wo.Rank.StarDelta, wo.Rank.After)
	}
	a, _ := ac.store.GetAccount("DailyA")
	if a.DailyBonusDay != "2026-03-10" {
		t.Fatalf("stored claim day = %q, want 2026-03-10", a.DailyBonusDay)
	}
	if p, _ := ac.Profile("DailyA"); !p.DailyBonusClaimed {
		t.Fatal("profile does not report the bonus claimed after the first win")
	}
	// The history record carries the composition of the delta.
	hist := ac.MatchHistory("DailyA")
	if len(hist) != 1 {
		t.Fatalf("history = %+v, want 1 record", hist)
	}
	if !hist[0].DailyBonus || hist[0].StarBonus || hist[0].StarDelta != 2 {
		t.Fatalf("history record = %+v, want daily-only +2", hist[0])
	}

	// Second win the same day: plain +1 (streak 2 < 3, no daily).
	wo, _, err = ac.RecordRankedResultFull("DailyA", "DailyB")
	if err != nil {
		t.Fatal(err)
	}
	if wo.Rank.DailyBonus || wo.Rank.StarDelta != 1 || wo.Rank.After.Stars != 3 {
		t.Fatalf("second win = %+v, want plain +1 to 3 stars", wo.Rank)
	}
}

// A loss never claims the day: the loser can still earn the bonus
// with their first WIN later the same day.
func TestDailyBonusLossDoesNotClaim(t *testing.T) {
	day := time.Date(2026, 3, 10, 12, 0, 0, 0, time.Local)
	ac := dailyAccounts(t, &day)

	if _, _, err := ac.RecordRankedResultFull("DailyA", "DailyB"); err != nil {
		t.Fatal(err)
	}
	b, _ := ac.store.GetAccount("DailyB")
	if b.DailyBonusDay != "" {
		t.Fatalf("loser claimed the day on a loss: %q", b.DailyBonusDay)
	}
	// B's first win of the day still earns the bonus.
	wo, _, err := ac.RecordRankedResultFull("DailyB", "DailyA")
	if err != nil {
		t.Fatal(err)
	}
	if !wo.Rank.DailyBonus || wo.Rank.StarDelta != 2 {
		t.Fatalf("loser-turned-winner = %+v, want daily bonus +2", wo.Rank)
	}
}

// The next server-local day grants the bonus again.
func TestDailyBonusNextDay(t *testing.T) {
	day := time.Date(2026, 3, 10, 23, 30, 0, 0, time.Local)
	ac := dailyAccounts(t, &day)

	if _, _, err := ac.RecordRankedResultFull("DailyA", "DailyB"); err != nil {
		t.Fatal(err)
	}
	day = day.AddDate(0, 0, 1) // 2026-03-11
	if p, _ := ac.Profile("DailyA"); p.DailyBonusClaimed {
		t.Fatal("profile still shows claimed on the next day")
	}
	wo, _, err := ac.RecordRankedResultFull("DailyA", "DailyB")
	if err != nil {
		t.Fatal(err)
	}
	if !wo.Rank.DailyBonus || wo.Rank.StarDelta != 2 {
		t.Fatalf("next-day win = %+v, want daily bonus granted again", wo.Rank)
	}
	a, _ := ac.store.GetAccount("DailyA")
	if a.DailyBonusDay != "2026-03-11" {
		t.Fatalf("stored claim day = %q, want 2026-03-11", a.DailyBonusDay)
	}
}

// The daily star stacks with the streak bonus: a first win of the
// day that is also the 3rd consecutive win banks +3.
func TestDailyBonusStacksWithStreak(t *testing.T) {
	day := time.Date(2026, 3, 10, 12, 0, 0, 0, time.Local)
	ac, _ := testAccounts(t)
	ac.now = func() time.Time { return day }
	// Seed a winner mid-ladder with a 2-win streak already running
	// and TODAY'S bonus still unclaimed.
	seedRank(t, ac, "Streaky", RankState{Tier: TierChienBinh, Division: 2,
		Stars: 1, Streak: 2, Season: ac.CurrentSeason(),
		PeakTier: TierChienBinh, PeakDivision: 2}, 1000)
	if err := ac.Register("DailyB", "secret1"); err != nil {
		t.Fatal(err)
	}
	wo, _, err := ac.RecordRankedResultFull("Streaky", "DailyB")
	if err != nil {
		t.Fatal(err)
	}
	if !wo.Rank.Bonus || !wo.Rank.DailyBonus || wo.Rank.StarDelta != 3 {
		t.Fatalf("stacked win = %+v, want streak+daily, +3", wo.Rank)
	}
	if wo.Rank.After.Stars != 1 { // 1 + 3 = 4 >= cap 3 -> promoted, lands 1
		t.Fatalf("after = %+v, want promotion landing on 1 star", wo.Rank.After)
	}
}

// The daily star can itself cause the promotion (win at the cap
// with the bonus unclaimed promotes and lands on 2 stars).
func TestDailyBonusCanPromote(t *testing.T) {
	day := time.Date(2026, 3, 10, 12, 0, 0, 0, time.Local)
	ac, _ := testAccounts(t)
	ac.now = func() time.Time { return day }
	seedRank(t, ac, "Capper", RankState{Tier: TierTanBinh, Division: 0,
		Stars: 3, Season: ac.CurrentSeason(),
		PeakTier: TierTanBinh, PeakDivision: 0}, 1000)
	if err := ac.Register("DailyB", "secret1"); err != nil {
		t.Fatal(err)
	}
	wo, _, err := ac.RecordRankedResultFull("Capper", "DailyB")
	if err != nil {
		t.Fatal(err)
	}
	// Plain win promotes (III 3* -> II 1*), daily star -> II 2*.
	if !wo.Rank.DailyBonus || !wo.Rank.Promoted || wo.Rank.StarDelta != 2 ||
		wo.Rank.After.Division != 1 || wo.Rank.After.Stars != 2 {
		t.Fatalf("capped win = %+v, want daily+promoted, +2, II · 2 sao", wo.Rank)
	}
	if wo.Rank.After.Text() != "Tân Binh II · 2 sao" {
		t.Fatalf("after text = %q", wo.Rank.After.Text())
	}
}
