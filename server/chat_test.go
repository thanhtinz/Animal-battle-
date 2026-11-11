package main

import (
	"strings"
	"testing"
)

// startRoom builds a started room with n players and returns the hub,
// the room and the senders in slot order (sender[i] is slot i).
func startRoom(t *testing.T, h *Hub, n int) (*Room, []*fakeSender) {
	t.Helper()
	host := &fakeSender{}
	r := h.CreateRoom(host, "H", "grassland", "plains")
	senders := []*fakeSender{host}
	senders = append(senders, joinN(t, h, r.Code, n-1)...)
	for slot := 0; slot < n; slot++ {
		h.SetReady(r.Code, slot, true)
	}
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	t.Cleanup(func() {
		for slot := 0; slot < n; slot++ {
			h.Disconnect(r.Code, slot)
		}
	})
	return r, senders
}

func TestChatBroadcastAndSender(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 2)
	if err := h.RelayChat(r.Code, 1, "match", "gl hf"); err != nil {
		t.Fatal(err)
	}
	for i, fs := range s {
		msgs := fs.ofType("chat")
		if len(msgs) != 1 {
			t.Fatalf("slot %d got %d chat msgs, want 1", i, len(msgs))
		}
		m := msgs[0]
		if int(m["from"].(float64)) != 1 || m["name"] != "P2" || m["text"] != "gl hf" || m["scope"] != "match" {
			t.Fatalf("chat msg = %v", m)
		}
	}
}

func TestChatTeamScopeOnlyTeammates(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 4) // teams [0 0 1 1]
	if err := h.RelayChat(r.Code, 0, "team", "rush B"); err != nil {
		t.Fatal(err)
	}
	want := []int{1, 1, 0, 0} // slots 0,1 are team 0
	for i, fs := range s {
		if got := len(fs.ofType("chat")); got != want[i] {
			t.Fatalf("slot %d got %d team chats, want %d", i, got, want[i])
		}
	}
	// FFA (3 players): every slot is its own team — a team message
	// reaches only the sender.
	h2 := NewHub()
	r2, s2 := startRoom(t, h2, 3)
	if err := h2.RelayChat(r2.Code, 2, "team", "solo"); err != nil {
		t.Fatal(err)
	}
	for i, fs := range s2 {
		wantN := 0
		if i == 2 {
			wantN = 1
		}
		if got := len(fs.ofType("chat")); got != wantN {
			t.Fatalf("ffa slot %d got %d team chats, want %d", i, got, wantN)
		}
	}
}

func TestChatTruncatesTo200(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 2)
	long := strings.Repeat("a", 250)
	if err := h.RelayChat(r.Code, 0, "lobby", long); err != nil {
		t.Fatal(err)
	}
	msgs := s[1].ofType("chat")
	if len(msgs) != 1 {
		t.Fatalf("got %d msgs", len(msgs))
	}
	if got := len([]rune(msgs[0]["text"].(string))); got != ChatMaxLen {
		t.Fatalf("text runes = %d, want %d", got, ChatMaxLen)
	}
}

func TestChatRateLimitDrops(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 2)
	for i := 0; i < ChatRateCount+3; i++ {
		if err := h.RelayChat(r.Code, 0, "match", "spam"); err != nil {
			t.Fatal(err)
		}
	}
	if got := len(s[1].ofType("chat")); got != ChatRateCount {
		t.Fatalf("peer got %d chats, want exactly %d (rest dropped)", got, ChatRateCount)
	}
	// The other player is unaffected by the sender's limit.
	if err := h.RelayChat(r.Code, 1, "match", "still fine"); err != nil {
		t.Fatal(err)
	}
	fromPeer := 0
	for _, m := range s[0].ofType("chat") {
		if int(m["from"].(float64)) == 1 {
			fromPeer++
		}
	}
	if fromPeer != 1 {
		t.Fatalf("host got %d chats from peer, want 1", fromPeer)
	}
}
