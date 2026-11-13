// settings_test.go — 17d profile settings: rename cooldown
// (incl. the first-set exemption + the rejection date),
// avatar catalogue validation + migration, the GRANT model
// for frames/titles/bubbles (rule change 2026-11-12:
// possession = admin grants only; achievement data and the
// reign seam grant nothing), equip persistence + fallback,
// and the titles catalogue with thời hạn.
package main

import (
	"errors"
	"strings"
	"testing"
	"time"
)

// register17d makes an account and returns its session-free
// Accounts handle root.
func register17d(t *testing.T, ac *Accounts, user string) {
	t.Helper()
	if err := ac.Register(user, "secret1"); err != nil {
		t.Fatalf("register %s: %v", user, err)
	}
}

func TestRenameCooldown(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "renamer")
	// First set (registration): no cooldown consumed.
	p, err := ac.SetDisplayName("renamer", "FirstName")
	if err != nil {
		t.Fatalf("first set: %v", err)
	}
	if p.RenameNextAt != 0 {
		t.Fatalf("first set must leave rename open, got next=%d", p.RenameNextAt)
	}
	// First real rename: allowed, stamps the clock.
	p, err = ac.RenameDisplayName("renamer", "SecondName")
	if err != nil {
		t.Fatalf("first rename: %v", err)
	}
	now := ac.now().Unix()
	if p.DisplayName != "SecondName" {
		t.Fatalf("display name = %q", p.DisplayName)
	}
	if p.RenameNextAt <= now || p.RenameNextAt > now+int64(RenameCooldown/time.Second)+1 {
		t.Fatalf("rename_next_at = %d, want ~now+30d", p.RenameNextAt)
	}
	// Second rename immediately: blocked with the date.
	_, err = ac.RenameDisplayName("renamer", "ThirdName")
	var cd *RenameCooldownError
	if !errors.As(err, &cd) {
		t.Fatalf("second rename err = %v, want RenameCooldownError", err)
	}
	if cd.NextAt != p.RenameNextAt {
		t.Fatalf("cooldown NextAt = %d, want %d", cd.NextAt, p.RenameNextAt)
	}
	// Same-name rename during cooldown: no-op success.
	if _, err := ac.RenameDisplayName("renamer", "SecondName"); err != nil {
		t.Fatalf("same-name rename must be a no-op: %v", err)
	}
	// After the cooldown window passes, renaming works again.
	base := ac.now
	ac.now = func() time.Time { return base().Add(RenameCooldown + time.Hour) }
	defer func() { ac.now = base }()
	p, err = ac.RenameDisplayName("renamer", "ThirdName")
	if err != nil {
		t.Fatalf("rename after cooldown: %v", err)
	}
	if p.DisplayName != "ThirdName" {
		t.Fatalf("display name = %q", p.DisplayName)
	}
	// Validation still applies.
	if _, err := ac.RenameDisplayName("renamer", "ab"); err == nil {
		t.Fatal("short name must be rejected")
	}
	// Uniqueness still applies (another account's name).
	register17d(t, ac, "other")
	if _, err := ac.SetDisplayName("other", "OtherName"); err != nil {
		t.Fatal(err)
	}
	if _, err := ac.RenameDisplayName("renamer", "othername"); err == nil {
		t.Fatal("taken name must be rejected (case-insensitive)")
	}
}

func TestSetAvatarCatalogue(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "picker")
	if _, err := ac.SetAvatar("picker", "art:03"); err != nil {
		t.Fatalf("art:03: %v", err)
	}
	if got := ac.AvatarOf("picker"); got != "art:03" {
		t.Fatalf("avatar = %q", got)
	}
	for _, bad := range []string{"knight", "fan:mario", "art:99", "art:1", ""} {
		if _, err := ac.SetAvatar("picker", bad); !errors.Is(err, ErrBadAvatar) {
			t.Fatalf("avatar %q err = %v, want ErrBadAvatar", bad, err)
		}
	}
	// A stored legacy hero id normalises to the default.
	a, _ := ac.store.GetAccount("picker")
	a.AvatarID = "berserker"
	ac.store.PutAccount(a)
	if got := ac.AvatarOf("picker"); got != AvatarDefaultID {
		t.Fatalf("legacy avatar migration = %q, want %q", got, AvatarDefaultID)
	}
}

// seedStats writes Matches/Wins directly (the XP/level math
// reads them raw).
func seedStats(t *testing.T, ac *Accounts, user string, matches, wins int) {
	t.Helper()
	a, ok := ac.store.GetAccount(user)
	if !ok {
		t.Fatalf("no account %s", user)
	}
	a.Matches, a.Wins = matches, wins
	ac.store.PutAccount(a)
}

func ownedSet(p Profile) map[string]bool {
	out := map[string]bool{}
	for _, f := range p.OwnedFrames {
		out[f] = true
	}
	return out
}

func TestGrantModelOwnership(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "owner")
	prof := func() Profile {
		a, _ := ac.store.GetAccount("owner")
		return ac.profileOf(a)
	}
	// Rule change 2026-11-12: achievement data grants
	// NOTHING anymore — max out every old source at once
	// (Lv via stats, 150 wins, banked champion title, Hầu
	// Tước peak, alliance Lv 5 seam) and the account still
	// owns no frame, no title, no bubble beyond Mặc định.
	seedStats(t, ac, "owner", 400, 150)
	a, _ := ac.store.GetAccount("owner")
	a.Titles = []string{TitleChampion}
	a.History = []SeasonRecord{{FinalTier: TierHauTuoc}}
	ac.store.PutAccount(a)
	ac.AllyLevelOf = func(user string) int { return 5 }
	if got := prof().OwnedFrames; len(got) != 0 {
		t.Fatalf("achievement-stacked account frames = %v, want none", got)
	}
	if _, err := ac.SetFrame("owner", "frame_01"); !errors.Is(err, ErrFrameNotOwned) {
		t.Fatalf("ungranted frame equip err = %v", err)
	}
	if _, err := ac.SetDisplayTitle("owner", TitleChampion); !errors.Is(err, ErrTitleNotOwned) {
		t.Fatalf("banked-but-ungranted title equip err = %v", err)
	}
	if _, err := ac.SetBubbleStyle("owner", BubbleRank); !errors.Is(err, ErrBubbleNotOwned) {
		t.Fatalf("ungranted bubble equip err = %v", err)
	}
	// Grants confer possession, one family at a time.
	name, fresh, err := ac.GrantItem("owner", "frame", "frame_01")
	if err != nil || !fresh || !strings.Contains(name, "Dây Dâu Tây") {
		t.Fatalf("grant frame: name=%q fresh=%v err=%v", name, fresh, err)
	}
	if got := ownedSet(prof()); !got["frame_01"] || len(got) != 1 {
		t.Fatalf("frames after grant = %v", got)
	}
	if p, err := ac.SetFrame("owner", "frame_01"); err != nil || p.FrameID != "frame_01" {
		t.Fatalf("equip granted frame: %v frame=%q", err, p.FrameID)
	}
	// A re-grant is idempotent: no duplicate, no new letter.
	unreadBefore := prof().UnreadMail
	if _, fresh, err := ac.GrantItem("owner", "frame", "frame_01"); err != nil || fresh {
		t.Fatalf("re-grant: fresh=%v err=%v", fresh, err)
	}
	if prof().UnreadMail != unreadBefore {
		t.Fatal("re-grant must not file a second letter")
	}
	if _, _, err := ac.GrantItem("owner", "title", TitleIDChampion); err != nil {
		t.Fatalf("grant title: %v", err)
	}
	if p, err := ac.SetDisplayTitle("owner", TitleChampion); err != nil || p.DisplayTitle != TitleChampion {
		t.Fatalf("equip granted title: %v title=%q", err, p.DisplayTitle)
	}
	if _, _, err := ac.GrantItem("owner", "bubble", BubbleRank); err != nil {
		t.Fatalf("grant bubble: %v", err)
	}
	if p, err := ac.SetBubbleStyle("owner", BubbleRank); err != nil || p.BubbleStyle != BubbleRank {
		t.Fatalf("equip granted bubble: %v bubble=%q", err, p.BubbleStyle)
	}
	// Bad grants are rejected: unknown frame, the free
	// default bubble, unknown title id, unknown kind, ghost.
	for _, bad := range [][2]string{
		{"frame", "frame_99"}, {"bubble", BubbleDefault},
		{"title", "king"}, {"skin", "frame_01"},
	} {
		if _, _, err := ac.GrantItem("owner", bad[0], bad[1]); !errors.Is(err, ErrBadGrantItem) {
			t.Fatalf("grant %v err = %v, want ErrBadGrantItem", bad, err)
		}
	}
	if _, _, err := ac.GrantItem("ghost", "frame", "frame_01"); !errors.Is(err, ErrBadCredentials) {
		t.Fatalf("grant to ghost err = %v", err)
	}
	// Fallback on read: strip the grant directly in the
	// store (the no-longer-granted state) — the profile
	// falls back to no frame while the stored equip value
	// itself survives untouched.
	a, _ = ac.store.GetAccount("owner")
	a.GrantedFrames = nil
	ac.store.PutAccount(a)
	if p := prof(); p.FrameID != "" {
		t.Fatalf("ungranted equipped frame must fall back, got %q", p.FrameID)
	}
	a, _ = ac.store.GetAccount("owner")
	if a.FrameID != "frame_01" {
		t.Fatalf("stored frame must survive the fallback, got %q", a.FrameID)
	}
	// Every frame's obtain note is the event wording.
	for _, id := range FrameIDs {
		if FrameUnlockText[id] != "Nhận qua sự kiện" {
			t.Fatalf("frame %s unlock text = %q", id, FrameUnlockText[id])
		}
	}
}

func TestWarSeamDoesNotGrantItems(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "champ")
	// The reign seam stays ONLY as the automatic chat
	// suffix (§7.1 exception) — even with the reign ON it
	// grants no item: frame_12, the war bubble and the war
	// title all stay unowned until granted.
	ac.WarChampOf = func(user string) bool { return true }
	a, _ := ac.store.GetAccount("champ")
	p := ac.profileOf(a)
	for _, f := range p.OwnedFrames {
		if f == "frame_12" {
			t.Fatal("reign must not grant frame_12 anymore")
		}
	}
	for _, r := range p.TitleRows {
		if r.ID == TitleIDWarChampion && r.Owned {
			t.Fatal("reign must not grant the war title item anymore")
		}
	}
	if _, err := ac.SetFrame("champ", "frame_12"); !errors.Is(err, ErrFrameNotOwned) {
		t.Fatalf("frame_12 under reign err = %v", err)
	}
	if _, err := ac.SetBubbleStyle("champ", BubbleWarChamp); !errors.Is(err, ErrBubbleNotOwned) {
		t.Fatalf("war bubble under reign err = %v", err)
	}
	if _, err := ac.SetDisplayTitle("champ", TitleWarChampion); !errors.Is(err, ErrTitleNotOwned) {
		t.Fatalf("war title under reign err = %v", err)
	}
	// Granted, they equip normally (reign state irrelevant).
	if _, _, err := ac.GrantItem("champ", "frame", "frame_12"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := ac.GrantItem("champ", "title", TitleIDWarChampion); err != nil {
		t.Fatal(err)
	}
	if _, _, err := ac.GrantItem("champ", "bubble", BubbleWarChamp); err != nil {
		t.Fatal(err)
	}
	if p, err := ac.SetFrame("champ", "frame_12"); err != nil || p.FrameID != "frame_12" {
		t.Fatalf("equip granted frame_12: %v %q", err, p.FrameID)
	}
	if p, err := ac.SetDisplayTitle("champ", TitleWarChampion); err != nil || p.DisplayTitle != TitleWarChampion {
		t.Fatalf("equip granted war title: %v %q", err, p.DisplayTitle)
	}
	if p, err := ac.SetBubbleStyle("champ", BubbleWarChamp); err != nil || p.BubbleStyle != BubbleWarChamp {
		t.Fatalf("equip granted war bubble: %v %q", err, p.BubbleStyle)
	}
}

func TestEquipPersistenceAcrossReload(t *testing.T) {
	dir := t.TempDir()
	store, err := NewFileStore(dir + "/accounts.json")
	if err != nil {
		t.Fatal(err)
	}
	ac := NewAccounts(store)
	register17d(t, ac, "keeper")
	if _, _, err := ac.GrantItem("keeper", "frame", "frame_01"); err != nil {
		t.Fatal(err)
	}
	if _, err := ac.SetFrame("keeper", "frame_01"); err != nil {
		t.Fatal(err)
	}
	if _, err := ac.SetAvatar("keeper", "art:07"); err != nil {
		t.Fatal(err)
	}
	if _, err := ac.SetBubbleStyle("keeper", BubbleDefault); err != nil {
		t.Fatal(err)
	}
	// Reload from disk: equips AND the grant list survive.
	store2, err := NewFileStore(dir + "/accounts.json")
	if err != nil {
		t.Fatal(err)
	}
	ac2 := NewAccounts(store2)
	a, ok := ac2.store.GetAccount("keeper")
	if !ok {
		t.Fatal("account lost on reload")
	}
	p := ac2.profileOf(a)
	if p.FrameID != "frame_01" || a.AvatarID != "art:07" {
		t.Fatalf("reloaded equips: frame=%q avatar=%q", p.FrameID, a.AvatarID)
	}
	if len(a.GrantedFrames) != 1 || a.GrantedFrames[0] != "frame_01" {
		t.Fatalf("reloaded grants = %v", a.GrantedFrames)
	}
	// Ungranted + unknown equips are rejected.
	if _, err := ac.SetFrame("keeper", "frame_06"); !errors.Is(err, ErrFrameNotOwned) {
		t.Fatalf("ungranted frame err = %v", err)
	}
	if _, err := ac.SetFrame("keeper", "frame_99"); !errors.Is(err, ErrBadFrame) {
		t.Fatalf("unknown frame err = %v", err)
	}
	if _, err := ac.SetBubbleStyle("keeper", "neon"); !errors.Is(err, ErrBadBubble) {
		t.Fatalf("unknown bubble err = %v", err)
	}
	// Clearing the frame with "" always works.
	if p, err := ac.SetFrame("keeper", ""); err != nil || p.FrameID != "" {
		t.Fatalf("clear frame: %v frame=%q", err, p.FrameID)
	}
}

func TestTitlesCatalogue(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "titled")
	a, _ := ac.store.GetAccount("titled")
	p := ac.profileOf(a)
	if len(p.TitleRows) != 2 {
		t.Fatalf("title rows = %d, want the full catalogue (2)", len(p.TitleRows))
	}
	for _, r := range p.TitleRows {
		if r.Owned {
			t.Fatalf("fresh account must own no titles: %+v", r)
		}
		if r.Expiry == "" || r.How == "" {
			t.Fatalf("row missing how/expiry: %+v", r)
		}
	}
	// Banking the tournament title (15h) is UNTOUCHED as a
	// record — but it no longer confers the cosmetic: the
	// row stays dark and the equip is refused until the
	// title arrives as a grant (event reward hand-out).
	a.Titles = []string{TitleChampion}
	ac.store.PutAccount(a)
	p = ac.profileOf(a)
	for _, r := range p.TitleRows {
		if r.ID == TitleIDChampion && r.Owned {
			t.Fatal("banked title must not light the row without a grant")
		}
	}
	if _, err := ac.SetDisplayTitle("titled", TitleChampion); !errors.Is(err, ErrTitleNotOwned) {
		t.Fatalf("banked-only title equip err = %v", err)
	}
	// Granted: the row lights up, Vĩnh viễn, equippable.
	if _, _, err := ac.GrantItem("titled", "title", TitleIDChampion); err != nil {
		t.Fatal(err)
	}
	p, err := ac.SetDisplayTitle("titled", TitleChampion)
	if err != nil {
		t.Fatalf("equip granted champion title: %v", err)
	}
	if p.DisplayTitle != TitleChampion {
		t.Fatalf("display title = %q", p.DisplayTitle)
	}
	for _, r := range p.TitleRows {
		if r.ID == TitleIDChampion {
			if !r.Owned || r.Expiry != "Vĩnh viễn" || !r.Equipped {
				t.Fatalf("champion row = %+v", r)
			}
		}
	}
	// Unknown title rejected.
	if _, err := ac.SetDisplayTitle("titled", "Vua Bếp"); !errors.Is(err, ErrTitleNotOwned) {
		t.Fatalf("unknown title err = %v", err)
	}
}

func TestBubbleRankStyleOwnership(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "ranked")
	// Fresh account: rank bubble locked.
	if _, err := ac.SetBubbleStyle("ranked", BubbleRank); !errors.Is(err, ErrBubbleNotOwned) {
		t.Fatalf("rank bubble err = %v", err)
	}
	// A Kỵ Sĩ peak no longer unlocks it (grant model).
	a, _ := ac.store.GetAccount("ranked")
	a.History = []SeasonRecord{{FinalTier: TierKySi}}
	ac.store.PutAccount(a)
	if _, err := ac.SetBubbleStyle("ranked", BubbleRank); !errors.Is(err, ErrBubbleNotOwned) {
		t.Fatalf("rank bubble after peak tier err = %v, want still unowned", err)
	}
	// Granted, it equips and resolves.
	if _, _, err := ac.GrantItem("ranked", "bubble", BubbleRank); err != nil {
		t.Fatal(err)
	}
	p, err := ac.SetBubbleStyle("ranked", BubbleRank)
	if err != nil {
		t.Fatalf("rank bubble after grant: %v", err)
	}
	if p.BubbleStyle != BubbleRank || ac.EquippedBubbleOf("ranked") != BubbleRank {
		t.Fatalf("bubble = %q", p.BubbleStyle)
	}
}
