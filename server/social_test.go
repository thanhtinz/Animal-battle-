package main

// Stage 13g home-lobby social tests: system mail (welcome /
// promotion / season summary), the account friend list with hub
// presence, and the ping/history wire protocol.

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// ------------------------------------------------------------ mail

func TestWelcomeLetterOnRegister(t *testing.T) {
	acc, _ := testAccounts(t)
	if err := acc.Register("ThuLinh", "secret1"); err != nil {
		t.Fatalf("register: %v", err)
	}
	letters := acc.LettersOf("ThuLinh")
	if len(letters) != 1 {
		t.Fatalf("letters = %d, want 1 welcome letter", len(letters))
	}
	if !strings.Contains(letters[0].Title, "Chào mừng") || letters[0].Read {
		t.Fatalf("welcome letter wrong: %+v", letters[0])
	}
	p := profileOf(t, acc, "ThuLinh")
	if p.UnreadMail != 1 {
		t.Fatalf("profile unread = %d, want 1", p.UnreadMail)
	}
	// Mark the whole mailbox read: unread must drop to 0.
	left, err := acc.MarkMailRead("ThuLinh", 0)
	if err != nil || left != 0 {
		t.Fatalf("mark read: left=%d err=%v", left, err)
	}
	if p = profileOf(t, acc, "ThuLinh"); p.UnreadMail != 0 {
		t.Fatalf("profile unread after read = %d, want 0", p.UnreadMail)
	}
}

func TestPromotionLetter(t *testing.T) {
	acc, _ := testAccounts(t)
	mustRegister(t, acc, "Leo", 0)
	mustRegister(t, acc, "Dai", 0)
	// Seed Leo at Kỵ Sĩ I with a full division (3 stars): one win
	// promotes to Nam Tước III.
	a, _ := acc.store.GetAccount("Leo")
	a.Rank = RankState{Tier: TierKySi, Division: 2, Stars: 3, Season: acc.CurrentSeason(),
		PeakTier: TierKySi, PeakDivision: 2}
	if err := acc.store.PutAccount(a); err != nil {
		t.Fatal(err)
	}
	if _, _, err := acc.RecordRankedResultFull("Leo", "Dai"); err != nil {
		t.Fatalf("record: %v", err)
	}
	letters := acc.LettersOf("Leo")
	if len(letters) != 2 { // welcome + promotion
		t.Fatalf("letters = %d, want 2 (welcome+promotion)", len(letters))
	}
	top := letters[0] // newest first
	if !strings.Contains(top.Title, "Lên hạng") || !strings.Contains(top.Title, "Nam Tước") {
		t.Fatalf("promotion title = %q", top.Title)
	}
	if !strings.Contains(top.Body, "Dai") {
		t.Fatalf("promotion body should name the opponent: %q", top.Body)
	}
	// The loser gets no letter beyond the welcome one.
	if got := acc.LettersOf("Dai"); len(got) != 1 {
		t.Fatalf("loser letters = %d, want 1 (welcome only)", len(got))
	}
	// Mark a single letter read by id.
	left, err := acc.MarkMailRead("Leo", top.ID)
	if err != nil || left != 1 { // welcome still unread
		t.Fatalf("mark one: left=%d err=%v, want 1", left, err)
	}
}

func TestSeasonSummaryLetter(t *testing.T) {
	acc, _ := testAccounts(t)
	mustRegister(t, acc, "Mua", 0)
	// Age the season epoch so "now" sits in season 2, then put
	// the account mid-ladder in season 1.
	epoch := time.Now().Add(-acc.seasonLength() - time.Hour).Unix()
	if err := acc.store.PutMeta(MetaSeasonEpoch, fmt.Sprintf("%d", epoch)); err != nil {
		t.Fatal(err)
	}
	if cur := acc.CurrentSeason(); cur != 2 {
		t.Fatalf("current season = %d, want 2", cur)
	}
	a, _ := acc.store.GetAccount("Mua")
	a.Rank = RankState{Tier: TierKySi, Division: 1, Stars: 2, Season: 1,
		PeakTier: TierBaTuoc, PeakDivision: 0}
	if err := acc.store.PutAccount(a); err != nil {
		t.Fatal(err)
	}
	_ = profileOf(t, acc, "Mua") // touch archives + resets + mails
	letters := acc.LettersOf("Mua")
	if len(letters) != 2 {
		t.Fatalf("letters = %d, want welcome+season summary", len(letters))
	}
	top := letters[0]
	if !strings.Contains(top.Title, "Tổng kết Mùa") {
		t.Fatalf("season letter title = %q", top.Title)
	}
	if !strings.Contains(top.Body, "Kỵ Sĩ II") || !strings.Contains(top.Body, "Bá Tước") {
		t.Fatalf("season letter body missing ranks: %q", top.Body)
	}
	// Idempotent: touching again must not duplicate the letter.
	_ = profileOf(t, acc, "Mua")
	if got := acc.LettersOf("Mua"); len(got) != 2 {
		t.Fatalf("letters after second touch = %d, want 2", len(got))
	}
}

// ------------------------------------------------------------ friends

func TestFriendsAddRemove(t *testing.T) {
	acc, _ := testAccounts(t)
	mustRegister(t, acc, "Chu", 0)
	mustRegister(t, acc, "Ban", 0)
	if err := acc.AddFriend("Chu", "KhongCo"); err != ErrFriendMissing {
		t.Fatalf("add ghost err = %v, want ErrFriendMissing", err)
	}
	if err := acc.AddFriend("Chu", "Chu"); err != ErrFriendSelf {
		t.Fatalf("add self err = %v, want ErrFriendSelf", err)
	}
	if err := acc.AddFriend("Chu", "Ban"); err != nil {
		t.Fatalf("add: %v", err)
	}
	if err := acc.AddFriend("Chu", "Ban"); err != ErrFriendDup {
		t.Fatalf("dup err = %v, want ErrFriendDup", err)
	}
	rows := acc.FriendsOf("Chu")
	if len(rows) != 1 || rows[0].User != "Ban" || rows[0].RankText == "" {
		t.Fatalf("friends = %+v", rows)
	}
	if err := acc.RemoveFriend("Chu", "Ban"); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if err := acc.RemoveFriend("Chu", "Ban"); err != ErrFriendAbsent {
		t.Fatalf("remove absent err = %v, want ErrFriendAbsent", err)
	}
	if rows := acc.FriendsOf("Chu"); len(rows) != 0 {
		t.Fatalf("friends after remove = %+v", rows)
	}
}

// ------------------------------------------------------------ leaderboard v2 + meta

func TestLeaderboardV2MeAndFriends(t *testing.T) {
	acc, _ := testAccounts(t)
	// 25 accounts on a strict ladder: U00 highest … U24 lowest.
	for i := 0; i < 25; i++ {
		name := fmt.Sprintf("U%02d", i)
		mustRegister(t, acc, name, 0)
		a, _ := acc.store.GetAccount(name)
		a.Rank = RankState{Tier: TierTanBinh, Division: 0, Stars: 0,
			Season: acc.CurrentSeason(), PeakTier: TierTanBinh}
		a.MMR = 3000 - i*40
		a.Wins = 25 - i
		a.Losses = i
		a.Matches = 25
		if err := acc.store.PutAccount(a); err != nil {
			t.Fatal(err)
		}
	}
	// Ranked board: U22 sits at position 23, outside the top 20.
	rows, mePos, meRow := acc.LeaderboardV2("ranked", "U22")
	if len(rows) != 20 {
		t.Fatalf("rows = %d, want 20", len(rows))
	}
	if mePos != 23 || meRow == nil || meRow.User != "U22" {
		t.Fatalf("me: pos=%d row=%v, want 23/U22", mePos, meRow)
	}
	if _, _, guest := acc.LeaderboardV2("ranked", ""); guest != nil {
		t.Fatal("guest must have no me row")
	}
	// Friends board: U22 + friends U03, U10 (positions within the
	// filtered ladder: U03=1, U10=2, U22=3).
	if err := acc.AddFriend("U22", "U03"); err != nil {
		t.Fatal(err)
	}
	if err := acc.AddFriend("U22", "U10"); err != nil {
		t.Fatal(err)
	}
	frows, fpos, fme := acc.LeaderboardV2("friends", "U22")
	if len(frows) != 3 || fpos != 3 || fme == nil || fme.User != "U22" {
		t.Fatalf("friends board: rows=%d pos=%d me=%v", len(frows), fpos, fme)
	}
	if frows[0].User != "U03" || frows[1].User != "U10" {
		t.Fatalf("friends order = %s, %s", frows[0].User, frows[1].User)
	}
	if rows, _, _ := acc.LeaderboardV2("friends", ""); len(rows) != 0 {
		t.Fatal("guest friends board must be empty")
	}
	// W/L board: U00 has the most wins (25), U24 the fewest (1).
	_, wpos, _ := acc.LeaderboardV2("wl", "U24")
	if wpos != 25 {
		t.Fatalf("wl pos for U24 = %d, want 25", wpos)
	}
}

func TestRankedMetaBankedIntoHistory(t *testing.T) {
	acc, _ := testAccounts(t)
	mustRegister(t, acc, "Meta1", 0)
	mustRegister(t, acc, "Meta2", 0)
	if _, _, err := acc.RecordRankedResultMeta("Meta1", "Meta2",
		"desert", "coast", 5432, "rp_test1"); err != nil {
		t.Fatalf("meta record: %v", err)
	}
	for _, u := range []string{"Meta1", "Meta2"} {
		h := acc.MatchHistory(u)
		if len(h) != 1 {
			t.Fatalf("%s history n=%d, want 1", u, len(h))
		}
		r := h[0]
		if r.Biome != "desert" || r.Layout != "coast" || r.DurationTicks != 5432 {
			t.Fatalf("%s record meta = %+v", u, r)
		}
		if r.ReplayID != "rp_test1" {
			t.Fatalf("%s record replay_id = %q", u, r.ReplayID)
		}
	}
}

// ------------------------------------------------------------ presence + wire

func TestPresenceRefcount(t *testing.T) {
	h := NewHub()
	h.SetOnline("Ai", true)
	h.SetOnline("Ai", true)
	if !h.IsOnline("Ai") {
		t.Fatal("should be online")
	}
	h.SetOnline("Ai", false)
	if !h.IsOnline("Ai") {
		t.Fatal("one session left, should still be online")
	}
	h.SetOnline("Ai", false)
	if h.IsOnline("Ai") {
		t.Fatal("both sessions gone, should be offline")
	}
	h.SetOnline("", true) // never panics / never registers
	if h.IsOnline("") {
		t.Fatal("empty user must not register")
	}
}

func TestWirePingFriendsHistory(t *testing.T) {
	acc, _ := testAccounts(t)
	hub := NewHub()
	hub.acc = acc
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgradeWS(w, r)
		if err != nil {
			http.Error(w, "upgrade failed", http.StatusBadRequest)
			return
		}
		s := &session{hub: hub, conn: conn, acc: acc}
		conn.onText = s.handle
		conn.onGone = s.gone
		go conn.readLoop()
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	url := srv.URL + "/ws"

	a := dialWS(t, url)
	defer a.conn.Close()
	a.send(t, map[string]any{"t": "register", "user": "WireA", "pass": "secret1"})
	a.recvUntil(t, "auth_ok")
	b := dialWS(t, url)
	defer b.conn.Close()
	b.send(t, map[string]any{"t": "register", "user": "WireB", "pass": "secret1"})
	b.recvUntil(t, "auth_ok")

	// Ping echoes the client ts.
	a.send(t, map[string]any{"t": "ping", "ts": 424242})
	pong := a.recvUntil(t, "pong")
	if int64(pong["ts"].(float64)) != 424242 {
		t.Fatalf("pong ts = %v", pong["ts"])
	}

	// A adds B: list shows B online while B's session lives.
	a.send(t, map[string]any{"t": "friend_add", "user": "WireB"})
	fr := a.recvUntil(t, "friends")
	rows, _ := fr["rows"].([]any)
	if len(rows) != 1 {
		t.Fatalf("friends rows = %v", fr["rows"])
	}
	row := rows[0].(map[string]any)
	if row["user"] != "WireB" || row["online"] != true || row["rank_text"] == "" {
		t.Fatalf("friend row = %v", row)
	}
	// Adding a ghost errors clearly.
	a.send(t, map[string]any{"t": "friend_add", "user": "Ghost"})
	fe := a.recvUntil(t, "friend_error")
	if fe["msg"] == "" || fe["msg"] == nil {
		t.Fatalf("friend_error missing msg: %v", fe)
	}
	// Mail: A has exactly the welcome letter unread.
	a.send(t, map[string]any{"t": "mail"})
	mail := a.recvUntil(t, "mail")
	if int(mail["unread"].(float64)) != 1 {
		t.Fatalf("mail unread = %v, want 1", mail["unread"])
	}
	a.send(t, map[string]any{"t": "mail_read", "id": 0})
	mail2 := a.recvUntil(t, "mail")
	if int(mail2["unread"].(float64)) != 0 {
		t.Fatalf("mail unread after read = %v, want 0", mail2["unread"])
	}
	// History is empty until a ranked result is banked; bank one
	// directly and re-ask.
	if _, _, err := acc.RecordRankedResultFull("WireA", "WireB"); err != nil {
		t.Fatalf("bank: %v", err)
	}
	a.send(t, map[string]any{"t": "history"})
	hist := a.recvUntil(t, "history")
	hrows, _ := hist["rows"].([]any)
	if len(hrows) != 1 {
		t.Fatalf("history rows = %v", hist["rows"])
	}
	h0 := hrows[0].(map[string]any)
	if h0["opponent"] != "WireB" || h0["won"] != true || h0["rank_to"] == "" {
		t.Fatalf("history row = %v", h0)
	}
	// B disconnects: presence drops after the server notices.
	b.conn.Close()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		a.send(t, map[string]any{"t": "friends"})
		fr = a.recvUntil(t, "friends")
		rows, _ = fr["rows"].([]any)
		if len(rows) == 1 && rows[0].(map[string]any)["online"] == false {
			return // presence correctly offline
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("friend still online after disconnect: %v", fr["rows"])
}

// ------------------------------------------------------------ 13m: close friends + last seen

func TestCloseFriendToggle(t *testing.T) {
	acc, _ := testAccounts(t)
	mustRegister(t, acc, "Chu", 0)
	mustRegister(t, acc, "Ban", 0)
	mustRegister(t, acc, "NguoiLa", 0)
	// Toggling someone who is not a friend is rejected.
	if err := acc.SetCloseFriend("Chu", "NguoiLa", true); err != ErrFriendAbsent {
		t.Fatalf("close non-friend err = %v, want ErrFriendAbsent", err)
	}
	if err := acc.AddFriend("Chu", "Ban"); err != nil {
		t.Fatal(err)
	}
	if err := acc.SetCloseFriend("Chu", "Ban", true); err != nil {
		t.Fatalf("set close: %v", err)
	}
	rows := acc.FriendsOf("Chu")
	if len(rows) != 1 || !rows[0].Close {
		t.Fatalf("rows after close = %+v, want Close=true", rows)
	}
	// Idempotent: setting the same state again succeeds silently.
	if err := acc.SetCloseFriend("Chu", "Ban", true); err != nil {
		t.Fatalf("re-set close: %v", err)
	}
	// The flag is per-owner: Ban's own list knows nothing of it.
	if err := acc.AddFriend("Ban", "Chu"); err != nil {
		t.Fatal(err)
	}
	if brows := acc.FriendsOf("Ban"); len(brows) != 1 || brows[0].Close {
		t.Fatalf("owner leak: Ban's rows = %+v, want Close=false", brows)
	}
	// Unflag.
	if err := acc.SetCloseFriend("Chu", "Ban", false); err != nil {
		t.Fatalf("unset close: %v", err)
	}
	if rows := acc.FriendsOf("Chu"); len(rows) != 1 || rows[0].Close {
		t.Fatalf("rows after unset = %+v, want Close=false", rows)
	}
	// Removing a close friend drops the flag for good: a re-add
	// comes back unflagged.
	if err := acc.SetCloseFriend("Chu", "Ban", true); err != nil {
		t.Fatal(err)
	}
	if err := acc.RemoveFriend("Chu", "Ban"); err != nil {
		t.Fatal(err)
	}
	if err := acc.AddFriend("Chu", "Ban"); err != nil {
		t.Fatal(err)
	}
	if rows := acc.FriendsOf("Chu"); len(rows) != 1 || rows[0].Close {
		t.Fatalf("rows after re-add = %+v, want Close=false", rows)
	}
}

func TestFriendsPayloadFields(t *testing.T) {
	acc, _ := testAccounts(t)
	mustRegister(t, acc, "Chu", 0)
	mustRegister(t, acc, "Ban", 0)
	// Ban: 25 matches, 10 wins -> XP = 10*25 + 20*10 = 450 -> Lv3
	// (thresholds 0 / 100 / 300 / 600).
	b, _ := acc.store.GetAccount("Ban")
	b.Matches, b.Wins, b.Losses = 25, 10, 15
	b.LastOnline = 1_700_000_000
	if err := acc.store.PutAccount(b); err != nil {
		t.Fatal(err)
	}
	// A custom avatar pick is carried; the default is ngan_ky.
	if _, err := acc.SetAvatar("Ban", "kim_hoa"); err != nil {
		t.Fatal(err)
	}
	if err := acc.AddFriend("Chu", "Ban"); err != nil {
		t.Fatal(err)
	}
	rows := acc.FriendsOf("Chu")
	if len(rows) != 1 {
		t.Fatalf("rows = %+v", rows)
	}
	r := rows[0]
	if r.Level != 3 {
		t.Fatalf("level = %d, want 3 (450 XP)", r.Level)
	}
	if r.AvatarID != "kim_hoa" {
		t.Fatalf("avatar = %q, want kim_hoa", r.AvatarID)
	}
	if r.LastOnline != 1_700_000_000 {
		t.Fatalf("last_online = %d, want 1700000000", r.LastOnline)
	}
	// Chu (no matches, default avatar): Lv1, ngan_ky, never stamped.
	if err := acc.AddFriend("Ban", "Chu"); err != nil {
		t.Fatal(err)
	}
	cr := acc.FriendsOf("Ban")[0]
	if cr.Level != 1 || cr.AvatarID != "ngan_ky" || cr.LastOnline != 0 {
		t.Fatalf("default row = %+v, want Lv1/ngan_ky/0", cr)
	}
}

func TestLastOnlineStampedWhenPresenceEnds(t *testing.T) {
	acc, _ := testAccounts(t)
	mustRegister(t, acc, "Aiko", 0)
	h := NewHub()
	h.acc = acc
	h.SetOnline("Aiko", true)
	h.SetOnline("Aiko", true)
	h.SetOnline("Aiko", false) // one session remains: no stamp yet
	if a, _ := acc.store.GetAccount("Aiko"); a.LastOnline != 0 {
		t.Fatalf("stamped early: last_online = %d", a.LastOnline)
	}
	before := time.Now().Unix()
	h.SetOnline("Aiko", false) // last session ends: stamp lands
	a, _ := acc.store.GetAccount("Aiko")
	if a.LastOnline < before || a.LastOnline > time.Now().Unix()+1 {
		t.Fatalf("last_online = %d, want ~now (%d)", a.LastOnline, before)
	}
	// A bare hub (no account service) must not panic.
	h2 := NewHub()
	h2.SetOnline("Aiko", true)
	h2.SetOnline("Aiko", false)
}

func TestWireFriendClose(t *testing.T) {
	acc, _ := testAccounts(t)
	hub := NewHub()
	hub.acc = acc
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgradeWS(w, r)
		if err != nil {
			http.Error(w, "upgrade failed", http.StatusBadRequest)
			return
		}
		s := &session{hub: hub, conn: conn, acc: acc}
		conn.onText = s.handle
		conn.onGone = s.gone
		go conn.readLoop()
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	url := srv.URL + "/ws"

	a := dialWS(t, url)
	defer a.conn.Close()
	a.send(t, map[string]any{"t": "register", "user": "WireC", "pass": "secret1"})
	a.recvUntil(t, "auth_ok")
	b := dialWS(t, url)
	defer b.conn.Close()
	b.send(t, map[string]any{"t": "register", "user": "WireD", "pass": "secret1"})
	b.recvUntil(t, "auth_ok")

	a.send(t, map[string]any{"t": "friend_add", "user": "WireD"})
	fr := a.recvUntil(t, "friends")
	row := fr["rows"].([]any)[0].(map[string]any)
	// New payload fields ride along from the first list.
	if row["close"] != false || row["avatar_id"] != "ngan_ky" ||
		int(row["level"].(float64)) != 1 || row["last_online"] == nil {
		t.Fatalf("initial friend row = %v", row)
	}
	// Toggle close over the wire.
	a.send(t, map[string]any{"t": "friend_close", "user": "WireD", "close": true})
	fr = a.recvUntil(t, "friends")
	row = fr["rows"].([]any)[0].(map[string]any)
	if row["close"] != true {
		t.Fatalf("row after close = %v, want close=true", row)
	}
	// B disconnects: last_online gets stamped server-side.
	b.conn.Close()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		a.send(t, map[string]any{"t": "friends"})
		fr = a.recvUntil(t, "friends")
		row = fr["rows"].([]any)[0].(map[string]any)
		if row["online"] == false && int64(row["last_online"].(float64)) > 0 {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("last_online never stamped: %v", row)
}
