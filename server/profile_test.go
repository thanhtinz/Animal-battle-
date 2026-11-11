package main

// Profile-screen backing data (13l): numeric account ids,
// XP/levels and the reputation score ("Uy tín").

import (
	"path/filepath"
	"testing"
	"time"
)

// ---------------------------------------------------------- account ids

func TestAccountIDsSequentialAtRegistration(t *testing.T) {
	ac, _ := testAccounts(t)
	for i, user := range []string{"First", "Second", "Third"} {
		if err := ac.Register(user, "secret1"); err != nil {
			t.Fatalf("register %s: %v", user, err)
		}
		p, ok := ac.Profile(user)
		if !ok {
			t.Fatalf("profile %s missing", user)
		}
		if p.ID != i+1 {
			t.Fatalf("%s id = %d, want %d", user, p.ID, i+1)
		}
	}
	// Ids are immutable: a login re-render keeps them.
	_, prof, err := ac.Login("Second", "secret1")
	if err != nil {
		t.Fatal(err)
	}
	if prof.ID != 2 {
		t.Fatalf("login profile id = %d, want 2", prof.ID)
	}
}

func TestAccountIDBackfillByRegistrationOrder(t *testing.T) {
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	// Legacy accounts (no id field), written newest-first on
	// purpose; one pair shares a Created stamp so the username
	// tiebreak decides.
	legacy := []*Account{
		{User: "Newest", Created: 300},
		{User: "Beta", Created: 100},
		{User: "Alpha", Created: 100},
		{User: "Oldest", Created: 50},
	}
	for _, a := range legacy {
		if err := fs.PutAccount(a); err != nil {
			t.Fatal(err)
		}
	}
	ac := NewAccounts(fs) // migration runs here
	want := map[string]int{"Oldest": 1, "Alpha": 2, "Beta": 3, "Newest": 4}
	for user, id := range want {
		a, ok := fs.GetAccount(user)
		if !ok || a.ID != id {
			t.Fatalf("%s id = %d (ok %v), want %d", user, a.ID, ok, id)
		}
		// Legacy accounts also gain the reputation default.
		if !a.CreditSet || a.Credit != 100 {
			t.Fatalf("%s credit = %d set %v, want 100/true", user, a.Credit, a.CreditSet)
		}
	}
	// Registration continues the sequence, never reusing an id.
	if err := ac.Register("Fresh", "secret1"); err != nil {
		t.Fatal(err)
	}
	if p, _ := ac.Profile("Fresh"); p.ID != 5 {
		t.Fatalf("fresh id = %d, want 5", p.ID)
	}
	// A second service over the same store changes nothing.
	ac2 := NewAccounts(fs)
	if p, _ := ac2.Profile("Beta"); p.ID != 3 {
		t.Fatalf("after re-boot Beta id = %d, want 3", p.ID)
	}
	if p, _ := ac2.Profile("Fresh"); p.ID != 5 {
		t.Fatalf("after re-boot Fresh id = %d, want 5", p.ID)
	}
}

// ---------------------------------------------------------- XP / level

func TestLevelForXPEdges(t *testing.T) {
	cases := []struct {
		xp               int
		level, into, nxt int
	}{
		{0, 1, 0, 100},
		{99, 1, 99, 100},
		{100, 2, 0, 200},
		{240, 2, 140, 200},
		{299, 2, 199, 200},
		{300, 3, 0, 300},
		{600, 4, 0, 400},
		{1000, 5, 0, 500},
		{1500, 6, 0, 600},
	}
	for _, c := range cases {
		l, i, n := LevelForXP(c.xp)
		if l != c.level || i != c.into || n != c.nxt {
			t.Fatalf("LevelForXP(%d) = (%d, %d, %d), want (%d, %d, %d)",
				c.xp, l, i, n, c.level, c.into, c.nxt)
		}
	}
	if got := XPFor(10, 7); got != 240 {
		t.Fatalf("XPFor(10, 7) = %d, want 240", got)
	}
}

func TestProfileProgressionFromRecordedMatches(t *testing.T) {
	ac, _ := testAccounts(t)
	if err := ac.Register("Grinder", "secret1"); err != nil {
		t.Fatal(err)
	}
	// Fresh account: Lv1, no XP, full reputation.
	p, _ := ac.Profile("Grinder")
	if p.Level != 1 || p.XP != 0 || p.XPInto != 0 || p.XPForNext != 100 || p.Credit != 100 {
		t.Fatalf("fresh profile = %+v", p)
	}
	// 3 wins + 1 loss of reported customs: 4 matches, 3 wins
	// -> XP = 10*4 + 20*3 = 100 -> exactly Lv2.
	for _, won := range []bool{true, true, false, true} {
		if err := ac.RecordMatch("Grinder", won); err != nil {
			t.Fatal(err)
		}
	}
	p, _ = ac.Profile("Grinder")
	if p.XP != 100 || p.Level != 2 || p.XPInto != 0 || p.XPForNext != 200 {
		t.Fatalf("profile after 4 matches = xp %d lv %d into %d next %d, want 100/2/0/200",
			p.XP, p.Level, p.XPInto, p.XPForNext)
	}
}

// ---------------------------------------------------------- reputation

func setCredit(t *testing.T, ac *Accounts, user string, credit int) {
	t.Helper()
	a, ok := ac.store.GetAccount(user)
	if !ok {
		t.Fatalf("account %s missing", user)
	}
	a.Credit = credit
	a.CreditSet = true
	if err := ac.store.PutAccount(a); err != nil {
		t.Fatal(err)
	}
}

func creditOf(t *testing.T, ac *Accounts, user string) int {
	t.Helper()
	p, ok := ac.Profile(user)
	if !ok {
		t.Fatalf("profile %s missing", user)
	}
	return p.Credit
}

func TestCreditFlow(t *testing.T) {
	ac, _ := testAccounts(t)
	if err := ac.Register("Winner", "secret1"); err != nil {
		t.Fatal(err)
	}
	if err := ac.Register("Quitter", "secret1"); err != nil {
		t.Fatal(err)
	}
	setCredit(t, ac, "Winner", 90)
	setCredit(t, ac, "Quitter", 50)

	// Completed match (elimination): both sides +1.
	if _, _, err := ac.RecordRankedResultReason("Winner", "Quitter", "", "", 0, "", "elimination"); err != nil {
		t.Fatal(err)
	}
	if got := creditOf(t, ac, "Winner"); got != 91 {
		t.Fatalf("winner credit = %d, want 91", got)
	}
	if got := creditOf(t, ac, "Quitter"); got != 51 {
		t.Fatalf("loser credit = %d, want 51", got)
	}

	// Disconnect loss: loser +1 for the completed match, −5 for
	// the forfeit -> net −4.
	if _, _, err := ac.RecordRankedResultReason("Winner", "Quitter", "", "", 0, "", "disconnect"); err != nil {
		t.Fatal(err)
	}
	if got := creditOf(t, ac, "Winner"); got != 92 {
		t.Fatalf("winner credit = %d, want 92", got)
	}
	if got := creditOf(t, ac, "Quitter"); got != 47 {
		t.Fatalf("quitter credit = %d, want 47", got)
	}

	// Floor: 2 + 1 − 5 clamps at 0, then a completed match
	// recovers +1.
	setCredit(t, ac, "Quitter", 2)
	if _, _, err := ac.RecordRankedResultReason("Winner", "Quitter", "", "", 0, "", "disconnect"); err != nil {
		t.Fatal(err)
	}
	if got := creditOf(t, ac, "Quitter"); got != 0 {
		t.Fatalf("quitter credit at floor = %d, want 0", got)
	}
	if _, _, err := ac.RecordRankedResultReason("Winner", "Quitter", "", "", 0, "", "elimination"); err != nil {
		t.Fatal(err)
	}
	if got := creditOf(t, ac, "Quitter"); got != 1 {
		t.Fatalf("quitter credit recovering = %d, want 1", got)
	}

	// Cap: a perfect score cannot grow past 100.
	setCredit(t, ac, "Winner", 100)
	if _, _, err := ac.RecordRankedResultReason("Winner", "Quitter", "", "", 0, "", "elimination"); err != nil {
		t.Fatal(err)
	}
	if got := creditOf(t, ac, "Winner"); got != 100 {
		t.Fatalf("winner credit at cap = %d, want 100", got)
	}
}

// ---------------------------------------------------------- season stars + prev card

func TestSeasonStarsArchiveIntoPrevRank(t *testing.T) {
	acc := seasonAccounts(t)
	seedRank(t, acc, "Hero", rs(TierHauTuoc, 2, 3), 1400)
	seedRank(t, acc, "Fodder", rs(TierTanBinh, 0, 0), 1000)

	// One ranked win inside season 1: every gained star (the
	// outcome's own delta, daily bonus included) lands in the
	// gross season counter.
	wo, _, err := acc.RecordRankedResultMeta("Hero", "Fodder", "", "", 0, "")
	if err != nil {
		t.Fatal(err)
	}
	p, _ := acc.Profile("Hero")
	if p.SeasonStars != wo.Rank.StarDelta || p.SeasonStars <= 0 {
		t.Fatalf("season stars = %d, outcome delta = %d", p.SeasonStars, wo.Rank.StarDelta)
	}
	earned := p.SeasonStars
	if p.PrevRank != nil {
		t.Fatalf("prev rank before any rollover = %+v, want nil", p.PrevRank)
	}

	// Season 2 begins: the finished season archives with its
	// gross total; the counter restarts; the profile exposes
	// the previous-season card data.
	acc.now = func() time.Time { return time.Unix(testEpoch+100*24*3600, 0) }
	p, _ = acc.Profile("Hero")
	if p.SeasonStars != 0 {
		t.Fatalf("season stars after rollover = %d, want 0", p.SeasonStars)
	}
	if p.PrevRank == nil {
		t.Fatal("prev rank missing after rollover")
	}
	if p.PrevSeason != 1 || p.PrevSeasonStars != earned {
		t.Fatalf("prev season = %d stars %d, want 1 / %d",
			p.PrevSeason, p.PrevSeasonStars, earned)
	}
	// Hero ended season 1 at Hầu Tước I (the win's stars kept
	// him there or promoted within the tier): the card shows
	// that final position.
	if p.PrevRank.TierName != "Hầu Tước" {
		t.Fatalf("prev rank tier = %q, want Hầu Tước", p.PrevRank.TierName)
	}
}
