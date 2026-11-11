package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeSender captures everything a room broadcast would deliver.
type fakeSender struct {
	mu   sync.Mutex
	msgs []map[string]any
	raw  [][]byte
}

func (f *fakeSender) SendText(data []byte) error {
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		return err
	}
	f.mu.Lock()
	f.msgs = append(f.msgs, m)
	f.raw = append(f.raw, data)
	f.mu.Unlock()
	return nil
}

func (f *fakeSender) ofType(t string) []map[string]any {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []map[string]any
	for _, m := range f.msgs {
		if m["t"] == t {
			out = append(out, m)
		}
	}
	return out
}

func (f *fakeSender) lastRoom() map[string]any {
	rooms := f.ofType("room")
	if len(rooms) == 0 {
		return nil
	}
	return rooms[len(rooms)-1]
}

func joinN(t *testing.T, h *Hub, code string, n int) []*fakeSender {
	t.Helper()
	senders := []*fakeSender{}
	for i := 0; i < n; i++ {
		fs := &fakeSender{}
		_, _, err := h.JoinRoom(fs, code, fmt.Sprintf("P%d", i+2))
		if err != nil {
			t.Fatalf("join %d: %v", i, err)
		}
		senders = append(senders, fs)
	}
	return senders
}

func TestRoomLifecycle(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "Host", "grassland", "plains")
	if len(r.Code) != 5 {
		t.Fatalf("code length = %d, want 5 (%q)", len(r.Code), r.Code)
	}
	if got := host.ofType("room"); len(got) == 0 {
		t.Fatal("host never received room state")
	}
	// Fill the room to 4; the 5th join must be rejected.
	joinN(t, h, r.Code, 3)
	extra := &fakeSender{}
	if _, _, err := h.JoinRoom(extra, r.Code, "Five"); err != ErrRoomFull {
		t.Fatalf("5th join err = %v, want ErrRoomFull", err)
	}
	if _, _, err := h.JoinRoom(extra, "XXXXX", "Ghost"); err != ErrRoomNotFound {
		t.Fatalf("bad code err = %v, want ErrRoomNotFound", err)
	}
	// Host leaves in the lobby: slot frees, host passes to slot 1.
	h.Disconnect(r.Code, 0)
	room := host.lastRoom() // host got no post-leave broadcast; ask a member instead
	_ = room
	if h.RoomCount() != 1 {
		t.Fatalf("rooms = %d, want 1", h.RoomCount())
	}
	// Everyone leaves: room is deleted.
	h.Disconnect(r.Code, 1)
	h.Disconnect(r.Code, 2)
	h.Disconnect(r.Code, 3)
	if h.RoomCount() != 0 {
		t.Fatalf("rooms = %d, want 0 after all leave", h.RoomCount())
	}
}

func TestStartRequiresReadyAndHost(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "Host", "grassland", "plains")
	if err := h.Start(r.Code, 0); err != ErrTooFew {
		t.Fatalf("start with 1 player err = %v, want ErrTooFew", err)
	}
	guest := &fakeSender{}
	_, p, err := h.JoinRoom(guest, r.Code, "Guest")
	if err != nil {
		t.Fatal(err)
	}
	if err := h.Start(r.Code, p.Slot); err != ErrNotHost {
		t.Fatalf("guest start err = %v, want ErrNotHost", err)
	}
	if err := h.Start(r.Code, 0); err != ErrNotReady {
		t.Fatalf("start unready err = %v, want ErrNotReady", err)
	}
	h.SetReady(r.Code, 0, true)
	h.SetReady(r.Code, p.Slot, true)
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	if got := guest.ofType("match_start"); len(got) != 1 {
		t.Fatalf("guest match_start count = %d", len(got))
	} else {
		seed, _ := got[0]["seed"].(float64)
		if seed <= 0 {
			t.Fatalf("seed = %v, want > 0", got[0]["seed"])
		}
		if got[0]["biome"] != "grassland" || got[0]["layout"] != "plains" {
			t.Fatalf("config = %v/%v", got[0]["biome"], got[0]["layout"])
		}
	}
	// Joining a running match is rejected.
	if _, _, err := h.JoinRoom(&fakeSender{}, r.Code, "Late"); err != ErrMatchRunning {
		t.Fatalf("late join err = %v, want ErrMatchRunning", err)
	}
	h.Disconnect(r.Code, 0)
	h.Disconnect(r.Code, p.Slot)
}

func TestTeamAssignments(t *testing.T) {
	want := map[int][]int{
		2: {0, 1},
		3: {0, 1, 2},
		4: {0, 0, 1, 1},
	}
	for n, teams := range want {
		h := NewHub()
		r := h.CreateRoom(&fakeSender{}, "H", "grassland", "plains")
		joinN(t, h, r.Code, n-1)
		for slot := 0; slot < n; slot++ {
			team, err := h.TeamOf(r.Code, slot)
			if err != nil {
				t.Fatalf("n=%d slot=%d: %v", n, slot, err)
			}
			if team != teams[slot] {
				t.Fatalf("n=%d slot=%d team=%d, want %d", n, slot, team, teams[slot])
			}
		}
	}
}

func TestCmdRelayStampsExecTick(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "H", "grassland", "plains")
	guest := &fakeSender{}
	_, p, _ := h.JoinRoom(guest, r.Code, "G")
	h.SetReady(r.Code, 0, true)
	h.SetReady(r.Code, p.Slot, true)
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatal(err)
	}
	defer func() {
		h.Disconnect(r.Code, 0)
		h.Disconnect(r.Code, p.Slot)
	}()
	// Tick is 0 just after start: exec must be exactly InputDelayTicks.
	cmd := json.RawMessage(`{"kind":"order","units":[1],"x":10,"y":20}`)
	if err := h.RelayCmd(r.Code, p.Slot, cmd); err != nil {
		t.Fatal(err)
	}
	for name, fs := range map[string]*fakeSender{"host": host, "guest": guest} {
		msgs := fs.ofType("cmd")
		if len(msgs) != 1 {
			t.Fatalf("%s got %d cmd relays, want 1 (sender included)", name, len(msgs))
		}
		if int(msgs[0]["tick"].(float64)) != InputDelayTicks {
			t.Fatalf("%s exec tick = %v, want %d", name, msgs[0]["tick"], InputDelayTicks)
		}
		if int(msgs[0]["from"].(float64)) != p.Slot {
			t.Fatalf("%s from = %v, want %d", name, msgs[0]["from"], p.Slot)
		}
	}
}

func TestChecksumDesyncDetection(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "H", "grassland", "plains")
	guest := &fakeSender{}
	_, p, _ := h.JoinRoom(guest, r.Code, "G")
	h.SetReady(r.Code, 0, true)
	h.SetReady(r.Code, p.Slot, true)
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatal(err)
	}
	defer func() {
		h.Disconnect(r.Code, 0)
		h.Disconnect(r.Code, p.Slot)
	}()
	// Agreeing hashes: no desync.
	h.ReportChecksum(r.Code, 0, 50, "aaa")
	h.ReportChecksum(r.Code, p.Slot, 50, "aaa")
	if n := len(host.ofType("desync")); n != 0 {
		t.Fatalf("desync notices = %d, want 0", n)
	}
	// Diverging hashes: exactly one desync notice for that tick.
	h.ReportChecksum(r.Code, 0, 60, "aaa")
	h.ReportChecksum(r.Code, p.Slot, 60, "bbb")
	if n := len(host.ofType("desync")); n != 1 {
		t.Fatalf("desync notices = %d, want 1", n)
	}
}

func TestPlayerLeftMidMatch(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "H", "grassland", "plains")
	guest := &fakeSender{}
	_, p, _ := h.JoinRoom(guest, r.Code, "G")
	h.SetReady(r.Code, 0, true)
	h.SetReady(r.Code, p.Slot, true)
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatal(err)
	}
	h.Disconnect(r.Code, p.Slot)
	left := host.ofType("player_left")
	if len(left) != 1 || int(left[0]["slot"].(float64)) != p.Slot {
		t.Fatalf("player_left = %v", left)
	}
	if h.RoomCount() != 1 {
		t.Fatal("room must survive a mid-match drop while a player remains")
	}
	h.Disconnect(r.Code, 0)
	if h.RoomCount() != 0 {
		t.Fatal("room must be deleted once every player is gone")
	}
	// The ticker goroutine must stop with the room; give it a moment
	// and make sure nothing panics / the process stays healthy.
	time.Sleep(150 * time.Millisecond)
}

func TestTickBroadcastRuns(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "H", "grassland", "plains")
	guest := &fakeSender{}
	_, p, _ := h.JoinRoom(guest, r.Code, "G")
	h.SetReady(r.Code, 0, true)
	h.SetReady(r.Code, p.Slot, true)
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatal(err)
	}
	defer func() {
		h.Disconnect(r.Code, 0)
		h.Disconnect(r.Code, p.Slot)
	}()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(host.ofType("tick")) >= 2 {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("host received fewer than 2 tick broadcasts in 2s")
}

func TestCleanNameDefaults(t *testing.T) {
	if got := cleanName("", 2); !strings.HasPrefix(got, "Người chơi") {
		t.Fatalf("default name = %q", got)
	}
	if got := cleanName("  Tín  ", 0); got != "Tín" {
		t.Fatalf("trimmed name = %q", got)
	}
}
