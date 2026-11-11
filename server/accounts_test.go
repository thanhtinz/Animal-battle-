package main

import (
	"path/filepath"
	"testing"
	"time"
)

func testAccounts(t *testing.T) (*Accounts, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	return NewAccounts(fs), path
}

func TestRegisterLoginFlow(t *testing.T) {
	ac, _ := testAccounts(t)
	if err := ac.Register("tin_nguyen", "secret1"); err != nil {
		t.Fatalf("register: %v", err)
	}
	// Duplicate registration is rejected.
	if err := ac.Register("tin_nguyen", "other-pass"); err != ErrUserExists {
		t.Fatalf("duplicate register err = %v, want ErrUserExists", err)
	}
	// Validation.
	if err := ac.Register("ab", "secret1"); err != ErrInvalidUser {
		t.Fatalf("short user err = %v, want ErrInvalidUser", err)
	}
	if err := ac.Register("bad name", "secret1"); err != ErrInvalidUser {
		t.Fatalf("spaced user err = %v, want ErrInvalidUser", err)
	}
	if err := ac.Register("ok_user", "12345"); err != ErrWeakPassword {
		t.Fatalf("weak pass err = %v, want ErrWeakPassword", err)
	}
	// Wrong password and unknown user give the SAME generic error.
	if _, _, err := ac.Login("tin_nguyen", "wrong-pass"); err != ErrBadCredentials {
		t.Fatalf("wrong pass err = %v, want ErrBadCredentials", err)
	}
	if _, _, err := ac.Login("no_such_user", "secret1"); err != ErrBadCredentials {
		t.Fatalf("unknown user err = %v, want ErrBadCredentials", err)
	}
	// Correct login returns a token + an empty profile.
	token, prof, err := ac.Login("tin_nguyen", "secret1")
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if token == "" || len(token) != TokenBytes*2 {
		t.Fatalf("token = %q (len %d)", token, len(token))
	}
	if prof.User != "tin_nguyen" || prof.Wins != 0 || prof.Matches != 0 {
		t.Fatalf("profile = %+v", prof)
	}
	// Passwords are never stored in plaintext: the stored hash must
	// not contain or equal the password.
	a, ok := ac.store.GetAccount("tin_nguyen")
	if !ok || a.Hash == "" || a.Salt == "" {
		t.Fatalf("stored account = %+v ok=%v", a, ok)
	}
	if a.Hash == "secret1" || a.Salt == "secret1" {
		t.Fatal("password material stored in plaintext")
	}
}

func TestTokenReuseAndLogout(t *testing.T) {
	ac, _ := testAccounts(t)
	ac.Register("player_one", "secret1")
	tok1, _, _ := ac.Login("player_one", "secret1")
	tok2, _, _ := ac.Login("player_one", "secret1")
	if tok1 == tok2 {
		t.Fatal("two logins issued the same token")
	}
	// Both tokens authenticate (token reuse across sessions).
	for _, tok := range []string{tok1, tok2} {
		prof, ok := ac.Authenticate(tok)
		if !ok || prof.User != "player_one" {
			t.Fatalf("authenticate(%s…) = %+v, %v", tok[:8], prof, ok)
		}
	}
	// Garbage tokens do not.
	if _, ok := ac.Authenticate("deadbeef"); ok {
		t.Fatal("garbage token authenticated")
	}
	// Logout kills only that token.
	ac.Logout(tok1)
	if _, ok := ac.Authenticate(tok1); ok {
		t.Fatal("logged-out token still authenticates")
	}
	if _, ok := ac.Authenticate(tok2); !ok {
		t.Fatal("second token should survive the first logout")
	}
}

func TestTokenExpiry(t *testing.T) {
	ac, _ := testAccounts(t)
	ac.Register("player_two", "secret1")
	token, _, _ := ac.Login("player_two", "secret1")
	// Wind the clock past the 30-day TTL: the token must expire.
	ac.now = func() time.Time { return time.Now().Add(TokenTTL + time.Hour) }
	if _, ok := ac.Authenticate(token); ok {
		t.Fatal("expired token authenticated")
	}
}

func TestStorePersistenceAcrossRestart(t *testing.T) {
	ac, path := testAccounts(t)
	ac.Register("returning", "secret1")
	token, _, _ := ac.Login("returning", "secret1")
	ac.RecordMatch("returning", true)

	// A brand-new service over the same file = a server restart.
	fs2, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	ac2 := NewAccounts(fs2)
	prof, ok := ac2.Authenticate(token)
	if !ok {
		t.Fatal("token did not survive a restart")
	}
	if prof.Wins != 1 || prof.Matches != 1 {
		t.Fatalf("profile after restart = %+v, want 1 win / 1 match", prof)
	}
	if _, _, err := ac2.Login("returning", "secret1"); err != nil {
		t.Fatalf("login after restart: %v", err)
	}
}

func TestLeaderboardOrdering(t *testing.T) {
	ac, _ := testAccounts(t)
	mk := func(user string, wins, losses int) {
		ac.Register(user, "secret1")
		for i := 0; i < wins; i++ {
			ac.RecordMatch(user, true)
		}
		for i := 0; i < losses; i++ {
			ac.RecordMatch(user, false)
		}
	}
	mk("bravo", 3, 3)   // 3 wins, 50%
	mk("alpha", 3, 0)   // 3 wins, 100% — must outrank bravo
	mk("charlie", 5, 9) // most wins — must lead despite winrate
	mk("delta", 0, 2)   // winless — last
	rows := ac.Leaderboard()
	if len(rows) != 4 {
		t.Fatalf("rows = %d, want 4", len(rows))
	}
	want := []string{"charlie", "alpha", "bravo", "delta"}
	for i, u := range want {
		if rows[i].User != u {
			t.Fatalf("row %d = %s, want %s (rows=%v)", i, rows[i].User, u, rows)
		}
	}
}

func TestHubMatchResultRecording(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 2)
	// Bind slot 0 to an account; slot 1 stays a guest.
	if err := h.AttachAccount(r.Code, 0, "champion"); err != nil {
		t.Fatal(err)
	}
	// Views expose the account flag (lobby "Loại" column data).
	view := s[1].lastRoom()
	players := view["players"].([]any)
	if players[0].(map[string]any)["account"] != true {
		t.Fatalf("slot 0 view = %v, want account=true", players[0])
	}
	if players[1].(map[string]any)["account"] != false {
		t.Fatalf("slot 1 view = %v, want account=false", players[1])
	}
	// A guest (non-host) cannot report.
	if _, err := h.RecordMatchResult(r.Code, 1, 0, nil); err != ErrNotHost {
		t.Fatalf("guest report err = %v, want ErrNotHost", err)
	}
	// Host reports team 0 as winner: only the account is banked.
	res, err := h.RecordMatchResult(r.Code, 0, 0, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(res) != 1 || !res["champion"] {
		t.Fatalf("results = %v, want {champion: true}", res)
	}
	// Double-reporting is rejected.
	if _, err := h.RecordMatchResult(r.Code, 0, 0, nil); err != ErrResultRecorded {
		t.Fatalf("second report err = %v, want ErrResultRecorded", err)
	}
}
