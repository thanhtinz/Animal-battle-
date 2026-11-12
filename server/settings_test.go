// settings_test.go — 17d profile settings: rename cooldown
// (incl. the first-set exemption + the rejection date),
// avatar catalogue validation + migration, frame ownership
// computation from fixtures (incl. the champion-reign
// frame_12 grant/revoke through the WarChampOf seam), equip
// persistence, and the titles catalogue with thời hạn.
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

func TestFrameOwnershipFixtures(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "owner")
	prof := func() Profile {
		a, _ := ac.store.GetAccount("owner")
		return ac.profileOf(a)
	}
	// Fresh account (Lv 1, 0 wins): no frames.
	if got := prof().OwnedFrames; len(got) != 0 {
		t.Fatalf("fresh account frames = %v", got)
	}
	// Level 5 needs XP 2000: XPFor = 10m + 20w; 200 matches
	// 0 wins = 2000 XP exactly -> frame_01 only.
	seedStats(t, ac, "owner", 200, 0)
	if got := ownedSet(prof()); !got["frame_01"] || len(got) != 1 {
		t.Fatalf("Lv5 frames = %v", got)
	}
	// 50 wins -> frame_05 joins (wins also add XP: 200m/50w
	// = 3000 XP = still Lv 5 band? LevelForXP(3000): L=6
	// needs 3000 -> Lv 6; frame_03 needs Lv 15, not yet).
	seedStats(t, ac, "owner", 200, 50)
	got := ownedSet(prof())
	if !got["frame_05"] || got["frame_03"] {
		t.Fatalf("50-win frames = %v", got)
	}
	// 150 wins -> frame_11 too.
	seedStats(t, ac, "owner", 400, 150)
	got = ownedSet(prof())
	if !got["frame_11"] {
		t.Fatalf("150-win frames = %v", got)
	}
	// Tournament champion title -> frame_07.
	a, _ := ac.store.GetAccount("owner")
	a.Titles = []string{TitleChampion}
	ac.store.PutAccount(a)
	if got := ownedSet(prof()); !got["frame_07"] {
		t.Fatalf("champion frames = %v", got)
	}
	// Peak tier Hầu Tước via season history -> frame_06.
	a, _ = ac.store.GetAccount("owner")
	a.History = []SeasonRecord{{FinalTier: TierHauTuoc}}
	ac.store.PutAccount(a)
	if got := ownedSet(prof()); !got["frame_06"] {
		t.Fatalf("peak-tier frames = %v", got)
	}
	// frame_09 stays locked: its cumulative counter does not
	// exist yet (honest unlock text).
	if got["frame_09"] {
		t.Fatal("frame_09 must stay locked until its counter exists")
	}
	if !strings.Contains(FrameUnlockText["frame_09"], "chưa mở") {
		t.Fatalf("frame_09 unlock text must be honest: %q", FrameUnlockText["frame_09"])
	}
}

func TestFrameAllianceLevelSeam(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "member")
	lvl := 0
	ac.AllyLevelOf = func(user string) int { return lvl }
	frame := func(id string) bool {
		a, _ := ac.store.GetAccount("member")
		for _, f := range ac.profileOf(a).OwnedFrames {
			if f == id {
				return true
			}
		}
		return false
	}
	if frame("frame_04") || frame("frame_10") {
		t.Fatal("no alliance: frames 04/10 must be locked")
	}
	lvl = 3
	if !frame("frame_04") || frame("frame_10") {
		t.Fatal("alliance Lv 3: frame_04 owned, frame_10 locked")
	}
	lvl = 5
	if !frame("frame_10") {
		t.Fatal("alliance Lv 5: frame_10 owned")
	}
}

func TestWarChampSeamGrantsAndRevoke(t *testing.T) {
	ac, _ := testAccounts(t)
	register17d(t, ac, "champ")
	reign := false
	ac.WarChampOf = func(user string) bool { return reign }
	// No reign: nothing war-related is owned, equips rejected.
	if _, err := ac.SetFrame("champ", "frame_12"); !errors.Is(err, ErrFrameNotOwned) {
		t.Fatalf("frame_12 without reign err = %v", err)
	}
	if _, err := ac.SetBubbleStyle("champ", BubbleWarChamp); !errors.Is(err, ErrBubbleNotOwned) {
		t.Fatalf("champion bubble without reign err = %v", err)
	}
	if _, err := ac.SetDisplayTitle("champ", TitleWarChampion); !errors.Is(err, ErrTitleNotOwned) {
		t.Fatalf("war title without reign err = %v", err)
	}
	// Reign on: frame_12 + war title row + champion bubble.
	reign = true
	p, err := ac.SetFrame("champ", "frame_12")
	if err != nil {
		t.Fatalf("frame_12 with reign: %v", err)
	}
	if p.FrameID != "frame_12" {
		t.Fatalf("equipped frame = %q", p.FrameID)
	}
	if _, err := ac.SetBubbleStyle("champ", BubbleWarChamp); err != nil {
		t.Fatalf("champion bubble with reign: %v", err)
	}
	if _, err := ac.SetDisplayTitle("champ", TitleWarChampion); err != nil {
		t.Fatalf("war title with reign: %v", err)
	}
	rows := map[string]TitleRow{}
	for _, r := range p.TitleRows {
		rows[r.ID] = r
	}
	// (p predates the title equip; re-read for rows.)
	a, _ := ac.store.GetAccount("champ")
	for _, r := range ac.profileOf(a).TitleRows {
		rows[r.ID] = r
	}
	if !rows[TitleIDWarChampion].Owned ||
		rows[TitleIDWarChampion].Expiry != "Khi đang giữ ngôi vô địch Đại chiến" ||
		!rows[TitleIDWarChampion].Equipped {
		t.Fatalf("war title row = %+v", rows[TitleIDWarChampion])
	}
	// Reign ends: effective frame/bubble/display-title all
	// fall back WITHOUT touching the stored values.
	reign = false
	a, _ = ac.store.GetAccount("champ")
	p = ac.profileOf(a)
	if p.FrameID != "" || p.BubbleStyle != BubbleDefault || p.DisplayTitle != "" {
		t.Fatalf("after reign: frame=%q bubble=%q title=%q, want defaults",
			p.FrameID, p.BubbleStyle, p.DisplayTitle)
	}
	if a.FrameID != "frame_12" {
		t.Fatalf("stored frame must survive a lapsed reign, got %q", a.FrameID)
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
	seedStats(t, ac, "keeper", 200, 0) // Lv 5 -> frame_01
	if _, err := ac.SetFrame("keeper", "frame_01"); err != nil {
		t.Fatal(err)
	}
	if _, err := ac.SetAvatar("keeper", "art:07"); err != nil {
		t.Fatal(err)
	}
	if _, err := ac.SetBubbleStyle("keeper", BubbleDefault); err != nil {
		t.Fatal(err)
	}
	// Reload from disk: equips survive.
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
	// Unowned + unknown equips are rejected.
	if _, err := ac.SetFrame("keeper", "frame_06"); !errors.Is(err, ErrFrameNotOwned) {
		t.Fatalf("unowned frame err = %v", err)
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
	// Earn the tournament title: row lights up, Vĩnh viễn,
	// equippable, and shows on the profile.
	a.Titles = []string{TitleChampion}
	ac.store.PutAccount(a)
	p, err := ac.SetDisplayTitle("titled", TitleChampion)
	if err != nil {
		t.Fatalf("equip champion title: %v", err)
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
	// Peak tier Kỵ Sĩ via history unlocks it.
	a, _ := ac.store.GetAccount("ranked")
	a.History = []SeasonRecord{{FinalTier: TierKySi}}
	ac.store.PutAccount(a)
	p, err := ac.SetBubbleStyle("ranked", BubbleRank)
	if err != nil {
		t.Fatalf("rank bubble with peak tier: %v", err)
	}
	if p.BubbleStyle != BubbleRank || ac.EquippedBubbleOf("ranked") != BubbleRank {
		t.Fatalf("bubble = %q", p.BubbleStyle)
	}
}
