package main

// Display names (13r): the "Đặt Tên Nhân Vật" panel — validation
// per the baked caption (3–16 ký tự, chữ/số/_), case-insensitive
// uniqueness across accounts, and propagation into the profile,
// friend rows and leaderboard rows.

import "testing"

func TestSetDisplayNameValidAndPropagates(t *testing.T) {
	ac, _ := testAccounts(t)
	if err := ac.Register("HiepSi", "secret1"); err != nil {
		t.Fatal(err)
	}
	if err := ac.Register("BaTuoc1", "secret1"); err != nil {
		t.Fatal(err)
	}
	// Before any pick, the profile carries the raw empty name.
	if p, _ := ac.Profile("HiepSi"); p.DisplayName != "" {
		t.Fatalf("fresh profile display_name = %q, want empty", p.DisplayName)
	}
	prof, err := ac.SetDisplayName("HiepSi", "Hiệp Sĩ 9")
	if err == nil {
		t.Fatalf("space in name should be rejected (chữ, số và _ only)")
	}
	_ = prof
	prof, err = ac.SetDisplayName("HiepSi", "HiepSi_9")
	if err != nil {
		t.Fatalf("valid name rejected: %v", err)
	}
	if prof.DisplayName != "HiepSi_9" {
		t.Fatalf("profile display_name = %q", prof.DisplayName)
	}
	if got := ac.DisplayNameOf("HiepSi"); got != "HiepSi_9" {
		t.Fatalf("DisplayNameOf = %q", got)
	}
	// Leaderboard rows carry the effective name.
	for _, r := range ac.Leaderboard() {
		if r.User == "HiepSi" && r.DisplayName != "HiepSi_9" {
			t.Fatalf("leader row display_name = %q", r.DisplayName)
		}
		if r.User == "BaTuoc1" && r.DisplayName != "BaTuoc1" {
			t.Fatalf("unpicked account should fall back to username, got %q", r.DisplayName)
		}
	}
	// Friend rows too.
	if err := ac.AddFriend("BaTuoc1", "HiepSi"); err != nil {
		t.Fatal(err)
	}
	rows := ac.FriendsOf("BaTuoc1")
	if len(rows) != 1 || rows[0].DisplayName != "HiepSi_9" {
		t.Fatalf("friend rows = %+v", rows)
	}
}

func TestSetDisplayNameValidation(t *testing.T) {
	ac, _ := testAccounts(t)
	if err := ac.Register("Player1", "secret1"); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{"", "ab", "abcdefghijklmnopq", "có dấu!", "a b", "x-y", "tên."} {
		if _, err := ac.SetDisplayName("Player1", bad); err != ErrInvalidName {
			t.Fatalf("name %q: err = %v, want ErrInvalidName", bad, err)
		}
	}
	// Vietnamese letters ARE letters: a fully-accented name is fine.
	if _, err := ac.SetDisplayName("Player1", "HiệpSĩ"); err != nil {
		t.Fatalf("accented name rejected: %v", err)
	}
	// Boundary lengths pass.
	if _, err := ac.SetDisplayName("Player1", "Abc"); err != nil {
		t.Fatalf("3-char name rejected: %v", err)
	}
	if _, err := ac.SetDisplayName("Player1", "Abcdefghijklmnop"); err != nil {
		t.Fatalf("16-char name rejected: %v", err)
	}
	if _, err := ac.SetDisplayName("Nobody", "Valid_1"); err != ErrBadCredentials {
		t.Fatalf("unknown user: err = %v", err)
	}
}

func TestSetDisplayNameUniquenessCaseInsensitive(t *testing.T) {
	ac, _ := testAccounts(t)
	for _, u := range []string{"First1", "Second1"} {
		if err := ac.Register(u, "secret1"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := ac.SetDisplayName("First1", "ChienBinh"); err != nil {
		t.Fatal(err)
	}
	// Same name, different case → taken.
	if _, err := ac.SetDisplayName("Second1", "chienbinh"); err != ErrNameTaken {
		t.Fatalf("case-variant dup: err = %v, want ErrNameTaken", err)
	}
	// Another account's USERNAME is also reserved (no impersonation).
	if _, err := ac.SetDisplayName("Second1", "first1"); err != ErrNameTaken {
		t.Fatalf("username shadow: err = %v, want ErrNameTaken", err)
	}
	// One's own username is allowed.
	if _, err := ac.SetDisplayName("Second1", "second1"); err != nil {
		t.Fatalf("own username as display name rejected: %v", err)
	}
	// Re-setting one's own current name is fine.
	if _, err := ac.SetDisplayName("First1", "CHIENBINH"); err != nil {
		t.Fatalf("own re-set rejected: %v", err)
	}
}
