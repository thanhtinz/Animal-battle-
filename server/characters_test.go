package main

import "testing"

// Characters (13j final model): the profile avatar is a free pick
// among the four mains and persists; cosmetic skins are OWNED
// items (none exist yet — activation is rejected for everyone);
// at match start the server DRAWS a character per player from the
// four mains and ships it in the match_start views; ranked maps
// are drawn at random from the pool.

func TestAvatarAccountPersistence(t *testing.T) {
	ac, path := testAccounts(t)
	if err := ac.Register("ava_user", "secret1"); err != nil {
		t.Fatalf("register: %v", err)
	}
	prof, ok := ac.Profile("ava_user")
	if !ok {
		t.Fatal("profile missing")
	}
	if prof.AvatarID != CharDefault {
		t.Fatalf("default avatar = %q, want %q", prof.AvatarID, CharDefault)
	}
	for _, id := range MainChars {
		p, err := ac.SetAvatar("ava_user", id)
		if err != nil {
			t.Fatalf("SetAvatar(%q): %v", id, err)
		}
		if p.AvatarID != id {
			t.Fatalf("profile avatar after set = %q, want %q", p.AvatarID, id)
		}
	}
	// Cosmetic skins have no portraits; unknown ids rejected too.
	for _, bad := range []string{"vo_hiep", "bach_y", "tu_y", "goc", "hoang_kim"} {
		if _, err := ac.SetAvatar("ava_user", bad); err != ErrBadAvatar {
			t.Fatalf("SetAvatar(%q) err = %v, want ErrBadAvatar", bad, err)
		}
	}
	// The loop above ends on the last main char (bach_sa when the
	// roster was four; thach_son since 14c grew it to eight) —
	// rejected sets must leave exactly that avatar in place.
	lastChar := MainChars[len(MainChars)-1]
	if p, _ := ac.Profile("ava_user"); p.AvatarID != lastChar {
		t.Fatalf("avatar after rejected sets = %q, want %s", p.AvatarID, lastChar)
	}
	// Persists across a store reload; login returns it.
	if _, err := ac.SetAvatar("ava_user", "kim_hoa"); err != nil {
		t.Fatal(err)
	}
	fs2, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	ac2 := NewAccounts(fs2)
	if p, _ := ac2.Profile("ava_user"); p.AvatarID != "kim_hoa" {
		t.Fatalf("avatar after reload = %q, want kim_hoa", p.AvatarID)
	}
	if _, prof2, err := ac2.Login("ava_user", "secret1"); err != nil || prof2.AvatarID != "kim_hoa" {
		t.Fatalf("login profile avatar = %q err=%v", prof2.AvatarID, err)
	}
	// Normalisation: corrupt stored values render as the default.
	a, _ := ac2.store.GetAccount("ava_user")
	a.AvatarID = "khong_ton_tai"
	_ = ac2.store.PutAccount(a)
	if p, _ := ac2.Profile("ava_user"); p.AvatarID != CharDefault {
		t.Fatalf("normalised avatar = %q, want %q", p.AvatarID, CharDefault)
	}
}

func TestActiveSkinOwnershipGate(t *testing.T) {
	ac, _ := testAccounts(t)
	if err := ac.Register("skin_fan", "secret1"); err != nil {
		t.Fatal(err)
	}
	// Launch state: nobody owns any skin — activation is rejected
	// for every real skin, and the profile stays skinless.
	for _, id := range []string{"vo_hiep", "bach_y", "tu_y"} {
		if _, err := ac.SetActiveSkin("skin_fan", id); err != ErrSkinNotOwned {
			t.Fatalf("SetActiveSkin(%q) err = %v, want ErrSkinNotOwned", id, err)
		}
	}
	if _, err := ac.SetActiveSkin("skin_fan", "hoang_kim"); err != ErrBadSkin {
		t.Fatalf("unknown skin err = %v, want ErrBadSkin", err)
	}
	if p, _ := ac.Profile("skin_fan"); p.ActiveSkin != "" || len(p.OwnedSkins) != 0 {
		t.Fatalf("profile = %+v, want no skins", p)
	}
	// Clearing is always allowed.
	if _, err := ac.SetActiveSkin("skin_fan", ""); err != nil {
		t.Fatalf("clear: %v", err)
	}
	// Simulate a future shop grant (direct store write): now the
	// same activation succeeds and the profile honours it.
	a, _ := ac.store.GetAccount("skin_fan")
	a.OwnedSkins = []string{"vo_hiep"}
	_ = ac.store.PutAccount(a)
	p, err := ac.SetActiveSkin("skin_fan", "vo_hiep")
	if err != nil {
		t.Fatalf("activate owned: %v", err)
	}
	if p.ActiveSkin != "vo_hiep" {
		t.Fatalf("active = %q, want vo_hiep", p.ActiveSkin)
	}
	// ...but a skin they still don't own stays rejected.
	if _, err := ac.SetActiveSkin("skin_fan", "tu_y"); err != ErrSkinNotOwned {
		t.Fatalf("unowned tu_y err = %v, want ErrSkinNotOwned", err)
	}
}

func TestCharacterDrawDistribution(t *testing.T) {
	h := NewHub()
	seen := map[string]int{}
	h.mu.Lock()
	for i := 0; i < 400; i++ {
		seen[h.drawCharLocked()]++
	}
	h.mu.Unlock()
	for _, id := range MainChars {
		if seen[id] == 0 {
			t.Fatalf("draw never produced %q in 400 draws: %v", id, seen)
		}
	}
	for id := range seen {
		if !mainCharIDs[id] {
			t.Fatalf("draw produced non-main %q — skins must never be drawn", id)
		}
	}
}

func TestCharacterAssignmentOnMatchStart(t *testing.T) {
	hub := NewHub()
	host := &fakeSender{}
	guest := &fakeSender{}
	r := hub.CreateRoom(host, "Host", "grassland", "plains")
	_, p, err := hub.JoinRoom(guest, r.Code, "Guest")
	if err != nil {
		t.Fatal(err)
	}
	hub.SetReady(r.Code, 0, true)
	hub.SetReady(r.Code, p.Slot, true)
	if err := hub.Start(r.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	for _, snd := range []*fakeSender{host, guest} {
		got := snd.ofType("match_start")
		if len(got) != 1 {
			t.Fatalf("match_start count = %d", len(got))
		}
		players, ok := got[0]["players"].([]any)
		if !ok || len(players) != 2 {
			t.Fatalf("match_start players = %v", got[0]["players"])
		}
		for _, pv := range players {
			pm := pv.(map[string]any)
			ch, _ := pm["char"].(string)
			if !mainCharIDs[ch] {
				t.Fatalf("assigned char = %q, want one of the mains", ch)
			}
			if sk, _ := pm["skin"].(string); sk != "" {
				t.Fatalf("assigned skin = %q, want \"\" (nobody owns any)", sk)
			}
		}
	}
	hub.Disconnect(r.Code, 0)
	hub.Disconnect(r.Code, p.Slot)
}

func TestRankedMapPickRandom(t *testing.T) {
	h := NewHub()
	legal := map[string]bool{}
	for _, p := range RankedRotation {
		legal[p.Biome+"/"+p.Layout] = true
	}
	seen := map[string]bool{}
	for i := 0; i < 90; i++ {
		pick := h.rankedMapPick()
		key := pick.Biome + "/" + pick.Layout
		if !legal[key] {
			t.Fatalf("pick %q not in the ranked pool", key)
		}
		seen[pick.Biome] = true
	}
	if len(seen) < 2 {
		t.Fatalf("90 random picks produced one biome only: %v", seen)
	}
}
