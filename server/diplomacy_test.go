package main

// 15b diplomacy (Custom rooms only): the room flag's flow from
// creation into the match_start payload, the shared-victory
// winner-set banking path, and the alliance team-chat routing.
// The stance sim itself lives in the clients' lockstep world and
// is covered by the Godot suite + diplomacy smoke; the server
// only carries the opt-in flag, the chat routing hint and the
// result, so that is what is tested here.

import (
	"testing"
)

func TestDiplomacyFlagFlows(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{Diplomacy: true})
	if got := host.lastRoom()["diplomacy"]; got != true {
		t.Fatalf("room broadcast diplomacy=%v, want true", got)
	}
	// The host can still change its mind in the lobby.
	if err := h.SetConfigEx(r.Code, 0, RoomConfigUpdate{Diplomacy: false, TouchAccess: true}); err != nil {
		t.Fatalf("config diplomacy off: %v", err)
	}
	if got := host.lastRoom()["diplomacy"]; got != false {
		t.Fatalf("after config diplomacy=%v, want false", got)
	}
	if err := h.SetConfigEx(r.Code, 0, RoomConfigUpdate{Diplomacy: true, TouchAccess: true}); err != nil {
		t.Fatalf("config diplomacy on: %v", err)
	}
	// Default rooms never carry the flag.
	plain := &fakeSender{}
	h.CreateRoomEx(plain, "Plain", "grassland", "plains", RoomCreateOptions{})
	if got := plain.lastRoom()["diplomacy"]; got != false {
		t.Fatalf("default room diplomacy=%v, want false", got)
	}
	// The flag rides match_start so every client arms (or does
	// not arm) the same sim rules.
	guest := &fakeSender{}
	if _, _, err := h.JoinRoomEx(guest, r.Code, "Guest", "", ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	if err := h.SetReady(r.Code, 0, true); err != nil {
		t.Fatalf("ready host: %v", err)
	}
	if err := h.SetReady(r.Code, 1, true); err != nil {
		t.Fatalf("ready guest: %v", err)
	}
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	starts := guest.ofType("match_start")
	if len(starts) == 0 {
		t.Fatal("guest never got match_start")
	}
	if got := starts[len(starts)-1]["diplomacy"]; got != true {
		t.Fatalf("match_start diplomacy=%v, want true", got)
	}
	// In-match config edits are inert (the lobby-only contract):
	// the flag must not flip mid-match.
	if err := h.SetConfigEx(r.Code, 0, RoomConfigUpdate{Diplomacy: false, TouchAccess: true}); err != nil {
		t.Fatalf("in-match config: %v", err)
	}
	h.mu.Lock()
	dip := r.Diplomacy
	h.mu.Unlock()
	if !dip {
		t.Fatal("diplomacy flag flipped mid-match")
	}
	h.Disconnect(r.Code, 0)
	h.Disconnect(r.Code, 1)
}

func TestDiplomacyWinnerSlotsBanking(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{Diplomacy: true})
	g1 := &fakeSender{}
	if _, _, err := h.JoinRoomEx(g1, r.Code, "Guest1", "", ""); err != nil {
		t.Fatalf("join 1: %v", err)
	}
	g2 := &fakeSender{}
	if _, _, err := h.JoinRoomEx(g2, r.Code, "Guest2", "", ""); err != nil {
		t.Fatalf("join 2: %v", err)
	}
	// Bind accounts so banking has users to write to.
	for slot, user := range map[int]string{0: "hostAcc", 1: "g1Acc", 2: "g2Acc"} {
		if err := h.AttachAccount(r.Code, slot, user); err != nil {
			t.Fatalf("attach %d: %v", slot, err)
		}
	}
	for s := 0; s < 3; s++ {
		if err := h.SetReady(r.Code, s, true); err != nil {
			t.Fatalf("ready %d: %v", s, err)
		}
	}
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer func() {
		h.Disconnect(r.Code, 0)
		h.Disconnect(r.Code, 1)
		h.Disconnect(r.Code, 2)
	}()
	// Only the host may report.
	if _, err := h.RecordMatchResultSlots(r.Code, 1, []int{0, 1}, nil); err != ErrNotHost {
		t.Fatalf("non-host report err = %v, want ErrNotHost", err)
	}
	// The set must be non-empty and name only room slots.
	if _, err := h.RecordMatchResultSlots(r.Code, 0, nil, nil); err != ErrBadWinners {
		t.Fatalf("empty set err = %v, want ErrBadWinners", err)
	}
	if _, err := h.RecordMatchResultSlots(r.Code, 0, []int{0, 7}, nil); err != ErrBadWinners {
		t.Fatalf("foreign slot err = %v, want ErrBadWinners", err)
	}
	// Slots 0 and 2 end mutually allied: both bank a win, the
	// eliminated slot 1 banks the loss.
	out, err := h.RecordMatchResultSlots(r.Code, 0, []int{0, 2}, nil)
	if err != nil {
		t.Fatalf("report: %v", err)
	}
	want := map[string]bool{"hostAcc": true, "g1Acc": false, "g2Acc": true}
	if len(out) != len(want) {
		t.Fatalf("banked %v, want %v", out, want)
	}
	for user, won := range want {
		if out[user] != won {
			t.Fatalf("banked[%s] = %v, want %v (all: %v)", user, out[user], won, out)
		}
	}
	// Once per room, like every other result path.
	if _, err := h.RecordMatchResultSlots(r.Code, 0, []int{0, 2}, nil); err != ErrResultRecorded {
		t.Fatalf("second report err = %v, want ErrResultRecorded", err)
	}
}

func TestDiplomacyWinnerSlotsRefusedInQueueRooms(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{Diplomacy: true})
	guest := &fakeSender{}
	if _, _, err := h.JoinRoomEx(guest, r.Code, "Guest", "", ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	if err := h.SetReady(r.Code, 0, true); err != nil {
		t.Fatalf("ready host: %v", err)
	}
	if err := h.SetReady(r.Code, 1, true); err != nil {
		t.Fatalf("ready guest: %v", err)
	}
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer func() {
		h.Disconnect(r.Code, 0)
		h.Disconnect(r.Code, 1)
	}()
	// Queue rooms never take a winner set (their results are the
	// placement/referee paths). The flags are flipped directly —
	// a queued room is exactly a room whose Queued/Ranked flag the
	// matchmaker set at creation.
	h.mu.Lock()
	r.Queued = true
	h.mu.Unlock()
	if _, err := h.RecordMatchResultSlots(r.Code, 0, []int{0}, nil); err != ErrQueuedRoom {
		t.Fatalf("queued room err = %v, want ErrQueuedRoom", err)
	}
	h.mu.Lock()
	r.Queued = false
	r.Ranked = true
	h.mu.Unlock()
	if _, err := h.RecordMatchResultSlots(r.Code, 0, []int{0}, nil); err != ErrRankedRoom {
		t.Fatalf("ranked room err = %v, want ErrRankedRoom", err)
	}
}

func TestDiplomacyTeamChatFollowsAllies(t *testing.T) {
	h2 := NewHub()
	host := &fakeSender{}
	r2 := h2.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{Diplomacy: true})
	s1 := &fakeSender{}
	if _, _, err := h2.JoinRoomEx(s1, r2.Code, "One", "", ""); err != nil {
		t.Fatalf("join 1: %v", err)
	}
	s2 := &fakeSender{}
	if _, _, err := h2.JoinRoomEx(s2, r2.Code, "Two", "", ""); err != nil {
		t.Fatalf("join 2: %v", err)
	}
	for s := 0; s < 3; s++ {
		if err := h2.SetReady(r2.Code, s, true); err != nil {
			t.Fatalf("ready %d: %v", s, err)
		}
	}
	if err := h2.Start(r2.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer func() {
		h2.Disconnect(r2.Code, 0)
		h2.Disconnect(r2.Code, 1)
		h2.Disconnect(r2.Code, 2)
	}()
	count := func(f *fakeSender) int {
		n := 0
		for _, m := range f.ofType("chat") {
			if m["text"] == "ke hoach bi mat" {
				n++
			}
		}
		return n
	}
	// Slot 0 declares slot 1 as its only current ally: the team
	// line reaches 0 (echo) and 1, never 2.
	if err := h2.RelayChatEx(r2.Code, 0, "team", "ke hoach bi mat", []int{1}); err != nil {
		t.Fatalf("relay: %v", err)
	}
	if count(host) != 1 || count(s1) != 1 || count(s2) != 0 {
		t.Fatalf("alliance routing: host=%d s1=%d s2=%d, want 1/1/0",
			count(host), count(s1), count(s2))
	}
	// The plain RelayChat wrapper (no targets) in the SAME
	// diplomacy room keeps the legacy fixed-team routing — in a
	// 3-player room the fixed teams are solo, so nobody else
	// receives it. (Clients in diplomacy matches always send
	// their ally list; this pins the fallback's safety.)
	if err := h2.RelayChat(r2.Code, 0, "team", "ke hoach bi mat"); err != nil {
		t.Fatalf("relay legacy: %v", err)
	}
	if count(host) != 2 || count(s1) != 1 || count(s2) != 0 {
		t.Fatalf("legacy fallback routing: host=%d s1=%d s2=%d, want 2/1/0",
			count(host), count(s1), count(s2))
	}
}
