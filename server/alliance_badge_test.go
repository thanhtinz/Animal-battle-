package main

// 17e addendum — alliance badge = icon (1..10) + colour
// (0..7 slot colours): create/settings validation, wire
// round-trip on every payload that carries the badge, and
// migration of pre-addendum records (string badge, no icon).

import (
	"os"
	"path/filepath"
	"testing"
)

func TestBadgeCreateValidation(t *testing.T) {
	e := allySetup(t)
	e.seed(t, "B1", "B2", "B3", "B4")
	for i, tc := range []struct{ icon, color int }{
		{0, 0}, {11, 0}, {-1, 0}, {1, -1}, {1, 8}, {10, 99},
	} {
		if _, err := e.as.Create("B1", "Hội Lỗi", "HL1", tc.icon, tc.color, AllianceModeOpen, ""); err != ErrAllyBadBadge {
			t.Fatalf("case %d (%d,%d): want ErrAllyBadBadge, got %v", i, tc.icon, tc.color, err)
		}
	}
	a, err := e.as.Create("B1", "Hội Chuẩn", "HC1", 10, 7, AllianceModeOpen, "")
	if err != nil {
		t.Fatal(err)
	}
	if a.BadgeIcon != 10 || a.BadgeColor != 7 {
		t.Fatalf("stored badge = %d/%d", a.BadgeIcon, a.BadgeColor)
	}
	// Settings validation too (leader-only path).
	if err := e.as.UpdateSettings(a.ID, "B1", "", 0, 0, AllianceModeOpen, ""); err != ErrAllyBadBadge {
		t.Fatalf("settings icon 0: %v", err)
	}
	if err := e.as.UpdateSettings(a.ID, "B1", "", 3, 4, AllianceModeOpen, ""); err != nil {
		t.Fatalf("settings valid: %v", err)
	}
}

func TestBadgeWireRoundTrip(t *testing.T) {
	e := allySetup(t)
	e.seed(t, "Lead", "Guest")
	a, err := e.as.Create("Lead", "Hội Huy Hiệu", "HH1", 3, 4, AllianceModeOpen, "")
	if err != nil {
		t.Fatal(err)
	}
	_ = a
	asInt := func(v any) int {
		switch n := v.(type) {
		case int:
			return n
		case float64:
			return int(n)
		}
		return -999
	}
	check := func(where string, row map[string]any) {
		t.Helper()
		if row == nil {
			t.Fatalf("%s: nil row", where)
		}
		if asInt(row["badge_icon"]) != 3 || asInt(row["badge_color"]) != 4 {
			t.Fatalf("%s: badge = %v/%v", where, row["badge_icon"], row["badge_color"])
		}
		if _, legacy := row["badge"]; legacy {
			t.Fatalf("%s: legacy badge field still shipped", where)
		}
	}
	offline := func(string) bool { return false }
	mine, _ := e.as.HomeFor("Lead", offline)
	check("home", mine)
	rows, _ := e.as.RankingWire("Lead")
	if len(rows) != 1 {
		t.Fatalf("ranking rows %d", len(rows))
	}
	check("ranking", rows[0])
	list := e.as.ListWire("Guest", "")
	if len(list) != 1 {
		t.Fatalf("list rows %d", len(list))
	}
	check("list", list[0])
	// Invite payload: invite Guest, read their invite rows.
	if _, err := e.as.Invite(a.ID, "Lead", "Guest"); err != nil {
		t.Fatal(err)
	}
	_, invites := e.as.HomeFor("Guest", offline)
	if len(invites) != 1 {
		t.Fatalf("invites %d", len(invites))
	}
	check("invite", invites[0])
}

func TestBadgeMigrationOldRecord(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "accounts.json")
	// A pre-addendum store file: two alliances with the old
	// string badge (purple = legacy index 5; an unknown value
	// must land on colour 0), no badge_icon field at all.
	raw := `{"accounts":{},"alliances":{
	 "AL1":{"id":"AL1","name":"Hội Cũ","badge":"purple","mode":"open","leader":"U1","created_at":1,
	   "members":[{"user":"U1","role":"leader","joined_at":1,"week_key":"2026-11-09"}]},
	 "AL2":{"id":"AL2","name":"Hội Lạ","badge":"pink","mode":"open","leader":"U2","created_at":1,
	   "members":[{"user":"U2","role":"leader","joined_at":1,"week_key":"2026-11-09"}]}
	}}`
	if err := os.WriteFile(path, []byte(raw), 0o644); err != nil {
		t.Fatal(err)
	}
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc := NewAccounts(fs)
	as := NewAlliances(fs, acc)
	a1, ok := as.get("AL1")
	if !ok {
		t.Fatal("AL1 missing")
	}
	if a1.BadgeIcon != 1 || a1.BadgeColor != 5 || a1.Badge != "" {
		t.Fatalf("AL1 migrated to icon %d color %d legacy %q", a1.BadgeIcon, a1.BadgeColor, a1.Badge)
	}
	a2, _ := as.get("AL2")
	if a2.BadgeIcon != 1 || a2.BadgeColor != 0 {
		t.Fatalf("AL2 migrated to icon %d color %d", a2.BadgeIcon, a2.BadgeColor)
	}
	// Persisted: a fresh store over the same file sees the
	// new fields (migration saved them back).
	fs2, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	as2 := NewAlliances(fs2, NewAccounts(fs2))
	b1, _ := as2.get("AL1")
	if b1.BadgeIcon != 1 || b1.BadgeColor != 5 {
		t.Fatalf("after reload: icon %d color %d", b1.BadgeIcon, b1.BadgeColor)
	}
}
