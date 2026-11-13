package main

// Empire Age 17e tests: the chat hub — emoticon token
// validation, world-channel fan-out + rate limits, DM
// routing/history/unread, voice payload caps, and the
// megaphone economy (consume, marquee broadcast, and the
// admin-only grant permission over the wire).

import (
	"encoding/base64"
	"encoding/binary"
	"math"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

// testWAV builds a minimal valid PCM16 WAV (mono sine).
func testWAV(rate int, seconds float64) []byte {
	n := int(float64(rate) * seconds)
	data := make([]byte, n*2)
	for i := 0; i < n; i++ {
		v := int16(6000 * math.Sin(2*math.Pi*440*float64(i)/float64(rate)))
		binary.LittleEndian.PutUint16(data[i*2:], uint16(v))
	}
	out := make([]byte, 0, 44+len(data))
	out = append(out, []byte("RIFF")...)
	out = appendUint32(out, uint32(36+len(data)))
	out = append(out, []byte("WAVEfmt ")...)
	out = appendUint32(out, 16)
	out = appendUint16(out, 1) // PCM
	out = appendUint16(out, 1) // mono
	out = appendUint32(out, uint32(rate))
	out = appendUint32(out, uint32(rate*2))
	out = appendUint16(out, 2)
	out = appendUint16(out, 16)
	out = append(out, []byte("data")...)
	out = appendUint32(out, uint32(len(data)))
	out = append(out, data...)
	return out
}

func appendUint32(b []byte, v uint32) []byte {
	var tmp [4]byte
	binary.LittleEndian.PutUint32(tmp[:], v)
	return append(b, tmp[:]...)
}

func appendUint16(b []byte, v uint16) []byte {
	var tmp [2]byte
	binary.LittleEndian.PutUint16(tmp[:], v)
	return append(b, tmp[:]...)
}

func hubChatSetup(t *testing.T) (*Hub, *Accounts, *DMs) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc := NewAccounts(fs)
	hub := NewHub()
	hub.acc = acc
	hub.dms = NewDMs(fs)
	hub.allis = NewAlliances(fs, acc)
	return hub, acc, hub.dms
}

func TestEmoteSanitize(t *testing.T) {
	if got := SanitizeEmotes("chào [e:vui] bạn"); got != "chào [e:vui] bạn" {
		t.Fatalf("known token must survive: %q", got)
	}
	if got := SanitizeEmotes("hack [e:khongco] nè"); strings.Contains(got, "khongco") {
		t.Fatalf("unknown token must be stripped: %q", got)
	}
	// Cap: only MaxEmotesPerMsg tokens survive.
	many := strings.Repeat("[e:vui] ", MaxEmotesPerMsg+4)
	if n := strings.Count(SanitizeEmotes(many), "[e:"); n != MaxEmotesPerMsg {
		t.Fatalf("token cap: got %d tokens, want %d", n, MaxEmotesPerMsg)
	}
	// Non-token brackets are ordinary text.
	if got := SanitizeEmotes("mảng [1,2] và [e]"); got != "mảng [1,2] và [e]" {
		t.Fatalf("plain text changed: %q", got)
	}
	if got := StripEmotes("loa [e:tim] to"); got != "loa  to" && got != "loa to" {
		t.Fatalf("strip: %q", got)
	}
}

func TestWorldChatFanoutAndRateLimit(t *testing.T) {
	hub, acc, _ := hubChatSetup(t)
	for _, u := range []string{"WChatA", "WChatB"} {
		if err := acc.Register(u, "secret1"); err != nil {
			t.Fatal(err)
		}
	}
	aFS, bFS := &fakeSender{}, &fakeSender{}
	hub.RegisterUserConn("WChatA", aFS)
	hub.RegisterUserConn("WChatB", bFS)

	hub.RelayWorldChat("WChatA", "WChatA", "xin chào [e:vui] [e:fake]")
	for name, fs := range map[string]*fakeSender{"a": aFS, "b": bFS} {
		chats := fs.ofType("chat")
		if len(chats) != 1 || chats[0]["scope"] != "world" {
			t.Fatalf("%s world chats: %v", name, chats)
		}
		if txt, _ := chats[0]["text"].(string); txt != "xin chào [e:vui] " {
			t.Fatalf("%s text not sanitised as expected: %q", name, txt)
		}
	}
	// Rate limit: the shared budget drops past ChatRateCount
	// lines inside the window.
	for i := 0; i < ChatRateCount+3; i++ {
		hub.RelayWorldChat("WChatA", "WChatA", "spam")
	}
	if got := len(bFS.ofType("chat")); got != ChatRateCount {
		t.Fatalf("world fan-out after rate limit = %d, want %d (the first line already spent one budget slot)", got, ChatRateCount)
	}
	// An unregistered account's sessions get nothing new:
	// world fan-out only reaches live user connections.
	hub.RelayWorldChat("WChatB", "WChatB", "từ B")
	if got := len(aFS.ofType("chat")); got != ChatRateCount+1 {
		t.Fatalf("a world chats = %d, want %d (own budget's worth + B's one)", got, ChatRateCount+1)
	}
}

func TestDMRoutingHistoryUnread(t *testing.T) {
	hub, acc, dms := hubChatSetup(t)
	for _, u := range []string{"DmAn", "DmBinh"} {
		if err := acc.Register(u, "secret1"); err != nil {
			t.Fatal(err)
		}
	}
	aFS, bFS := &fakeSender{}, &fakeSender{}
	hub.RegisterUserConn("DmAn", aFS)
	hub.RegisterUserConn("DmBinh", bFS)

	if err := hub.RelayDMText("DmAn", "DmAn", "DmBinh", "chào B [e:tim]"); err != nil {
		t.Fatal(err)
	}
	bChats := bFS.ofType("chat")
	if len(bChats) != 1 || bChats[0]["scope"] != "dm" || bChats[0]["peer"] != "DmAn" {
		t.Fatalf("b dm chats: %v", bChats)
	}
	aChats := aFS.ofType("chat")
	if len(aChats) != 1 || aChats[0]["peer"] != "DmBinh" {
		t.Fatalf("a dm echo: %v", aChats)
	}
	if got := dms.UnreadOf("DmBinh", "DmAn"); got != 1 {
		t.Fatalf("b unread = %d, want 1", got)
	}
	if got := dms.TotalUnread("DmBinh"); got != 1 {
		t.Fatalf("b total unread = %d, want 1", got)
	}
	if err := hub.RelayDMText("DmBinh", "DmBinh", "DmAn", "chào lại"); err != nil {
		t.Fatal(err)
	}
	// Mark read clears only the reader's side.
	if _, err := dms.MarkRead("DmBinh", "DmAn"); err != nil {
		t.Fatal(err)
	}
	if got := dms.UnreadOf("DmBinh", "DmAn"); got != 0 {
		t.Fatalf("b unread after read = %d, want 0", got)
	}
	if got := dms.UnreadOf("DmAn", "DmBinh"); got != 1 {
		t.Fatalf("a unread = %d, want 1", got)
	}
	// Self-DM is refused.
	if err := hub.RelayDMText("DmAn", "DmAn", "DmAn", "tự nói"); err != ErrDMSelf {
		t.Fatalf("self dm err = %v", err)
	}
	// History survives a fresh service over the same store —
	// i.e. a relog sees the conversation.
	fresh := NewDMs(acc.store)
	hist := fresh.History("DmAn", "DmBinh")
	if len(hist) != 2 || hist[0].Text != "chào B [e:tim]" || hist[1].From != "DmBinh" {
		t.Fatalf("persisted history: %+v", hist)
	}
	convs := fresh.Conversations("DmAn")
	if len(convs) != 1 || convs[0].User != "DmBinh" || convs[0].Unread != 1 {
		t.Fatalf("conversations: %+v", convs)
	}
}

func TestVoiceValidationAndRelay(t *testing.T) {
	good := testWAV(11025, 0.5)
	if err := ValidateVoiceWAV(good, 0.5); err != nil {
		t.Fatalf("valid wav rejected: %v", err)
	}
	if err := ValidateVoiceWAV([]byte("not a wav at all........"), 0.5); err != ErrVoiceBadData {
		t.Fatalf("garbage err = %v", err)
	}
	if err := ValidateVoiceWAV(testWAV(44100, 0.5), 0.5); err != ErrVoiceBadData {
		t.Fatalf("44.1k err = %v, want bad data (rate cap)", err)
	}
	if err := ValidateVoiceWAV(testWAV(4000, 45), 45); err != ErrVoiceTooLong {
		t.Fatalf("45s err = %v, want too long", err)
	}
	big := make([]byte, VoiceMaxBytes+1)
	copy(big, good)
	if err := ValidateVoiceWAV(big, 0.5); err != ErrVoiceTooBig {
		t.Fatalf("oversized err = %v", err)
	}
	if _, err := decodeVoicePayload(strings.Repeat("A", VoiceMaxBytes*2)); err != ErrVoiceTooBig {
		t.Fatalf("oversized b64 err = %v", err)
	}
	if _, err := decodeVoicePayload("!!!not-base64!!!"); err != ErrVoiceBadData {
		t.Fatalf("bad b64 err = %v", err)
	}

	hub, acc, _ := hubChatSetup(t)
	for _, u := range []string{"VoAn", "VoBinh"} {
		if err := acc.Register(u, "secret1"); err != nil {
			t.Fatal(err)
		}
	}
	aFS, bFS := &fakeSender{}, &fakeSender{}
	hub.RegisterUserConn("VoAn", aFS)
	hub.RegisterUserConn("VoBinh", bFS)
	if err := hub.RelayWorldVoice("VoAn", "VoAn", good, 0.5); err != nil {
		t.Fatal(err)
	}
	vs := bFS.ofType("voice")
	if len(vs) != 1 || vs[0]["scope"] != "world" {
		t.Fatalf("b voice msgs: %v", vs)
	}
	raw, err := base64.StdEncoding.DecodeString(vs[0]["data"].(string))
	if err != nil || len(raw) != len(good) {
		t.Fatalf("voice payload roundtrip: err=%v len=%d want %d", err, len(raw), len(good))
	}
	// Voice budget: VoiceRateCount per window, then drops.
	for i := 0; i < VoiceRateCount+2; i++ {
		if err := hub.RelayWorldVoice("VoBinh", "VoBinh", good, 0.5); err != nil {
			t.Fatal(err)
		}
	}
	if got := len(aFS.ofType("voice")); got != 1+VoiceRateCount {
		t.Fatalf("a voice count = %d, want %d", got, 1+VoiceRateCount)
	}
	// DM voice reaches both parties and is never persisted.
	if err := hub.RelayDMVoice("VA", "VoAn", "VoBinh", good, 0.5); err != nil {
		t.Fatal(err)
	}
	if got := len(hub.dms.History("VoAn", "VoBinh")); got != 0 {
		t.Fatalf("voice leaked into DM history: %d msgs", got)
	}
}

func TestMegaphoneConsumeAndBroadcast(t *testing.T) {
	hub, acc, _ := hubChatSetup(t)
	for _, u := range []string{"MgAn", "MgBinh"} {
		if err := acc.Register(u, "secret1"); err != nil {
			t.Fatal(err)
		}
	}
	// A bystander in a room (guest — no account session) must
	// still hear the marquee: rooms are the second fan-out.
	host := &fakeSender{}
	r := hub.CreateRoom(host, "Chủ phòng", "plains", "plains")
	if r == nil {
		t.Fatal("room not created")
	}
	aFS := &fakeSender{}
	hub.RegisterUserConn("MgAn", aFS)

	// No item → refusal, count untouched.
	if _, err := hub.UseMegaphone("MgAn", "MgAn", "alo alo"); err != ErrNoMegaphone {
		t.Fatalf("empty megaphone err = %v", err)
	}
	if got := len(host.ofType("marquee")); got != 0 {
		t.Fatalf("marquee broadcast without an item: %v", got)
	}
	// Grant at the account layer, then use: count decrements
	// and both audiences receive the marquee.
	total, err := acc.GrantMegaphones("MgAn", 2)
	if err != nil || total != 2 {
		t.Fatalf("grant: total=%d err=%v", total, err)
	}
	left, err := hub.UseMegaphone("MgAn", "MgAn", "Tập trung 20h [e:tim] nhé")
	if err != nil || left != 1 {
		t.Fatalf("use: left=%d err=%v", left, err)
	}
	mq := host.ofType("marquee")
	if len(mq) != 1 || mq[0]["text"] != "Tập trung 20h  nhé" && mq[0]["text"] != "Tập trung 20h nhé" {
		t.Fatalf("room marquee (tokens must be stripped): %v", mq)
	}
	if got := aFS.ofType("marquee"); len(got) != 1 || got[0]["mid"] != mq[0]["mid"] {
		t.Fatalf("lobby marquee / dedupe mid: %v vs %v", got, mq)
	}
	if p, ok := acc.Profile("MgAn"); !ok || p.Megaphones != 1 {
		t.Fatalf("profile megaphones = %v", p.Megaphones)
	}
	// The grant filed its paper trail in the mailbox.
	if p, ok := acc.Profile("MgAn"); !ok || p.UnreadMail == 0 {
		t.Fatalf("grant letter missing: unread=%v", p.UnreadMail)
	}
}

// TestAdminGrantItemWire drives the cosmetic item grant op
// (17d rule change): a non-admin CANNOT grant items; an
// admin's grant lands with the event-reward note, a profile
// refresh, and the delivery letter — and only then can the
// target equip the item.
func TestAdminGrantItemWire(t *testing.T) {
	acc, _ := testAccounts(t)
	hub := NewHub()
	hub.acc = acc
	hub.dms = NewDMs(acc.store)
	hub.admins["Boss"] = true
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
	reg := func(user string) *wsTestClient {
		c := dialWS(t, url)
		c.send(t, map[string]any{"t": "register", "user": user, "pass": "secret1"})
		c.recvUntil(t, "auth_ok")
		return c
	}
	boss := reg("Boss")
	defer boss.conn.Close()
	target := reg("Target")
	defer target.conn.Close()
	plain := reg("Plain")
	defer plain.conn.Close()

	// The target cannot equip the frame before any grant.
	target.send(t, map[string]any{"t": "set_frame", "frame": "frame_01"})
	fe := target.recvUntil(t, "error")
	if !strings.Contains(fe["msg"].(string), "chưa sở hữu") {
		t.Fatalf("pre-grant equip refusal = %v", fe["msg"])
	}
	// A non-admin grant attempt is refused and changes nothing.
	plain.send(t, map[string]any{"t": "admin_grant_item", "user": "Target", "kind": "frame", "item": "frame_01"})
	e := plain.recvUntil(t, "error")
	if !strings.Contains(e["msg"].(string), "Không có quyền") {
		t.Fatalf("non-admin item grant refusal = %v", e["msg"])
	}
	if a, _ := acc.store.GetAccount("Target"); len(a.GrantedFrames) != 0 {
		t.Fatalf("non-admin grant changed the account: %v", a.GrantedFrames)
	}
	// The admin grant lands: reply to the admin, note +
	// profile refresh to the target, letter in the mailbox.
	boss.send(t, map[string]any{"t": "admin_grant_item", "user": "Target", "kind": "frame", "item": "frame_01"})
	g := boss.recvUntil(t, "item_granted")
	if g["fresh"] != true || !strings.Contains(g["name"].(string), "Dây Dâu Tây") {
		t.Fatalf("item_granted reply = %v", g)
	}
	note := target.recvUntil(t, "system_msg")
	if !strings.Contains(note["text"].(string), "Bạn nhận được") ||
		strings.Contains(note["text"].(string), "admin") || strings.Contains(note["text"].(string), "quản trị") {
		t.Fatalf("target grant note = %v (must read as an event reward)", note["text"])
	}
	pu := target.recvUntil(t, "profile_update")
	frames, _ := pu["profile"].(map[string]any)["owned_frames"].([]any)
	if len(frames) != 1 || frames[0] != "frame_01" {
		t.Fatalf("profile after grant frames = %v", frames)
	}
	if p, ok := acc.Profile("Target"); !ok || p.UnreadMail == 0 {
		t.Fatalf("grant letter missing: unread=%v", p.UnreadMail)
	}
	// And now the equip works over the wire too.
	target.send(t, map[string]any{"t": "set_frame", "frame": "frame_01"})
	pu2 := target.recvUntil(t, "profile_update")
	if pu2["profile"].(map[string]any)["frame_id"] != "frame_01" {
		t.Fatalf("equip after grant = %v", pu2["profile"])
	}
}

// TestMegaphoneGrantPermissionWire drives the real session
// ops: a non-admin (and a guest) CANNOT grant; an admin can,
// and the grant lands on the target with its pushes.
func TestMegaphoneGrantPermissionWire(t *testing.T) {
	acc, _ := testAccounts(t)
	hub := NewHub()
	hub.acc = acc
	hub.dms = NewDMs(acc.store)
	hub.admins["Boss"] = true
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

	reg := func(user string) *wsTestClient {
		c := dialWS(t, url)
		c.send(t, map[string]any{"t": "register", "user": user, "pass": "secret1"})
		c.recvUntil(t, "auth_ok")
		return c
	}
	boss := reg("Boss")
	defer boss.conn.Close()
	target := reg("Target")
	defer target.conn.Close()
	plain := reg("Plain")
	defer plain.conn.Close()

	// A non-admin grant attempt is refused and changes nothing.
	plain.send(t, map[string]any{"t": "admin_grant_megaphone", "user": "Target", "count": 5})
	e := plain.recvUntil(t, "error")
	if !strings.Contains(e["msg"].(string), "Không có quyền") {
		t.Fatalf("non-admin refusal msg = %v", e["msg"])
	}
	if got := acc.MegaphoneCount("Target"); got != 0 {
		t.Fatalf("non-admin grant changed the count: %d", got)
	}
	// A guest cannot even use the world channel.
	guest := dialWS(t, url)
	defer guest.conn.Close()
	guest.send(t, map[string]any{"t": "world_chat", "text": "khách nói"})
	ge := guest.recvUntil(t, "error")
	if !strings.Contains(ge["msg"].(string), "Đăng nhập") {
		t.Fatalf("guest world refusal = %v", ge["msg"])
	}
	// The admin grant lands: reply to the admin, count +
	// system note pushed to the target.
	boss.send(t, map[string]any{"t": "admin_grant_megaphone", "user": "Target", "count": 3})
	g := boss.recvUntil(t, "megaphone_granted")
	if int(g["count"].(float64)) != 3 {
		t.Fatalf("granted reply = %v", g)
	}
	if got := acc.MegaphoneCount("Target"); got != 3 {
		t.Fatalf("target count = %d, want 3", got)
	}
	note := target.recvUntil(t, "system_msg")
	if !strings.Contains(note["text"].(string), "Loa thông báo") {
		t.Fatalf("target system note = %v", note["text"])
	}
	cnt := target.recvUntil(t, "megaphones")
	if int(cnt["count"].(float64)) != 3 {
		t.Fatalf("target count push = %v", cnt)
	}
	// And the target can spend one: the marquee reaches a
	// bystander session (the admin's).
	target.send(t, map[string]any{"t": "megaphone_use", "text": "Thông báo toàn server"})
	mq := boss.recvUntil(t, "marquee")
	if mq["text"] != "Thông báo toàn server" || mq["name"] == "" {
		t.Fatalf("bystander marquee = %v", mq)
	}
	left := target.recvUntil(t, "megaphones")
	if int(left["count"].(float64)) != 2 {
		t.Fatalf("count after use = %v", left)
	}
}
