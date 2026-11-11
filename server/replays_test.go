package main

// Stage 13h replay tests: recording completeness (every relayed
// command, in order, with its stamped tick), header fidelity,
// retention cap, and the fetch access rules over the wire.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestReplayRecordingComplete(t *testing.T) {
	h := NewHub()
	h.replays = NewMemReplayStore()
	host := &fakeSender{}
	guest := &fakeSender{}
	r := h.CreateRoom(host, "Host", "desert", "coast")
	_, p, err := h.JoinRoom(guest, r.Code, "Guest")
	if err != nil {
		t.Fatal(err)
	}
	h.SetReady(r.Code, 0, true)
	h.SetReady(r.Code, p.Slot, true)
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatal(err)
	}
	// Relay a known command sequence from both slots.
	cmds := []struct {
		slot int
		body string
	}{
		{0, `{"kind":"move","ids":[1],"tx":10,"ty":10}`},
		{p.Slot, `{"kind":"move","ids":[7],"tx":4,"ty":9}`},
		{0, `{"kind":"train","building":3,"unit":"militia"}`},
		{p.Slot, `{"kind":"build","btype":"house","cx":8,"cy":8}`},
		{0, `{"kind":"move","ids":[1,2],"tx":12,"ty":3}`},
	}
	for _, c := range cmds {
		if err := h.RelayCmd(r.Code, c.slot, json.RawMessage(c.body)); err != nil {
			t.Fatalf("relay: %v", err)
		}
	}
	if _, err := h.RecordMatchResult(r.Code, 0, 0, nil); err != nil {
		t.Fatal(err)
	}
	id := h.RoomReplayID(r.Code)
	if id == "" {
		t.Fatal("no replay id sealed")
	}
	rp, ok := h.replays.Get(id)
	if !ok {
		t.Fatal("replay not in store")
	}
	// Header fidelity.
	if rp.Seed == 0 || rp.Biome != "desert" || rp.Layout != "coast" || rp.Room != r.Code {
		t.Fatalf("header = %+v", rp)
	}
	if rp.Ranked || rp.WinnerTeam != 0 || rp.GameVersion != GameVersion || rp.V != 1 {
		t.Fatalf("header meta = %+v", rp)
	}
	if len(rp.Players) != 2 || rp.Players[0].Name != "Host" || rp.Players[1].Name != "Guest" {
		t.Fatalf("players = %+v", rp.Players)
	}
	// Completeness: every command, in relay order, exec tick =
	// relay tick (0) + input delay.
	if len(rp.Cmds) != len(cmds) {
		t.Fatalf("recorded %d cmds, want %d", len(rp.Cmds), len(cmds))
	}
	for i, c := range cmds {
		got := rp.Cmds[i]
		if got.From != c.slot || got.Tick != InputDelayTicks || string(got.Cmd) != c.body {
			t.Fatalf("cmd %d = %+v, want from=%d tick=%d %s", i, got, c.slot, InputDelayTicks, c.body)
		}
	}
	// A second result seals nothing new.
	if _, err := h.RecordMatchResult(r.Code, 0, 0, nil); err == nil {
		t.Fatal("double result should error")
	}
	if h.replays.Count() != 1 {
		t.Fatalf("store count = %d, want 1", h.replays.Count())
	}
}

// 14a: the elimination sidecar — validated, sealed into the
// recording, and dropped (never fatal) when inconsistent.
func TestReplayEventsSidecar(t *testing.T) {
	start := func(t *testing.T) (*Hub, *Room, int) {
		h := NewHub()
		h.replays = NewMemReplayStore()
		r := h.CreateRoom(&fakeSender{}, "Host", "grassland", "plains")
		_, p, err := h.JoinRoom(&fakeSender{}, r.Code, "Guest")
		if err != nil {
			t.Fatal(err)
		}
		if err := h.SetReady(r.Code, 0, true); err != nil {
			t.Fatal(err)
		}
		if err := h.SetReady(r.Code, p.Slot, true); err != nil {
			t.Fatal(err)
		}
		if err := h.Start(r.Code, 0); err != nil {
			t.Fatal(err)
		}
		h.mu.Lock()
		r.Tick = 900
		h.mu.Unlock()
		return h, r, p.Slot
	}

	// Valid: the guest fell at tick 450, the host never fell.
	h, r, gs := start(t)
	ticks := []int64{-1, -1}
	ticks[gs] = 450
	if _, err := h.RecordMatchResult(r.Code, 0, 0, ticks); err != nil {
		t.Fatal(err)
	}
	rp, ok := h.replays.Get(h.RoomReplayID(r.Code))
	if !ok {
		t.Fatal("replay not sealed")
	}
	if len(rp.Events) != 1 || rp.Events[0].Tick != 450 ||
		rp.Events[0].Kind != "elim" || rp.Events[0].Slot != gs {
		t.Fatalf("events = %+v, want one elim of slot %d @450", rp.Events, gs)
	}

	// Garbage (tick beyond the match): banking still succeeds,
	// the replay still seals — only the sidecar is dropped.
	h2, r2, gs2 := start(t)
	ticks2 := []int64{-1, -1}
	ticks2[gs2] = 99999
	if _, err := h2.RecordMatchResult(r2.Code, 0, 0, ticks2); err != nil {
		t.Fatal(err)
	}
	rp2, ok := h2.replays.Get(h2.RoomReplayID(r2.Code))
	if !ok {
		t.Fatal("replay not sealed (garbage sidecar)")
	}
	if len(rp2.Events) != 0 {
		t.Fatalf("garbage events sealed: %+v", rp2.Events)
	}
}

// 14a: placement consistency of the sidecar on the referee path —
// the winner may not carry an elimination tick, everyone else
// must carry one.
func TestReplayEventsPlacementConsistency(t *testing.T) {
	setup := func(t *testing.T) (*Hub, *Room) {
		h := NewHub()
		h.replays = NewMemReplayStore()
		acc := rankedAccounts(t)
		h.acc = acc
		mustRegister(t, acc, "Alpha", 0)
		mustRegister(t, acc, "Bravo", 0)
		r := rankedRoomFixture(t, h, "tok")
		// The hand-built room never passed startMatchLocked, so
		// open its recording the way a real match start would.
		h.mu.Lock()
		h.startMatchLocked(r)
		r.Tick = 900
		h.mu.Unlock()
		return h, r
	}

	// Valid: Alpha (slot 0) wins, Bravo fell at 450.
	h, _ := setup(t)
	if _, _, err := h.RecordRefereePlacements("RANK1",
		[]int{0, 1}, nil, []int64{-1, 450}); err != nil {
		t.Fatal(err)
	}
	rp, ok := h.replays.Get(h.RoomReplayID("RANK1"))
	if !ok || len(rp.Events) != 1 || rp.Events[0].Slot != 1 {
		t.Fatalf("events = %+v ok=%v", rp, ok)
	}

	// Winner carrying a tick: sidecar dropped, banking fine.
	h2, _ := setup(t)
	if _, _, err := h2.RecordRefereePlacements("RANK1",
		[]int{0, 1}, nil, []int64{100, 450}); err != nil {
		t.Fatal(err)
	}
	rp2, _ := h2.replays.Get(h2.RoomReplayID("RANK1"))
	if rp2 == nil || len(rp2.Events) != 0 {
		t.Fatalf("winner-tick events sealed: %+v", rp2)
	}

	// A non-winner WITHOUT a tick: also dropped.
	h3, _ := setup(t)
	if _, _, err := h3.RecordRefereePlacements("RANK1",
		[]int{0, 1}, nil, []int64{-1, -1}); err != nil {
		t.Fatal(err)
	}
	rp3, _ := h3.replays.Get(h3.RoomReplayID("RANK1"))
	if rp3 == nil || len(rp3.Events) != 0 {
		t.Fatalf("missing-tick events sealed: %+v", rp3)
	}
}

func TestReplayRetentionCap(t *testing.T) {
	s := NewMemReplayStore()
	for i := 0; i < ReplayCap+5; i++ {
		rp := &Replay{ID: fmt.Sprintf("rp_%03d", i), FinishedAt: int64(i)}
		if err := s.Put(rp); err != nil {
			t.Fatal(err)
		}
	}
	if s.Count() != ReplayCap {
		t.Fatalf("count = %d, want cap %d", s.Count(), ReplayCap)
	}
	if _, ok := s.Get("rp_000"); ok {
		t.Fatal("oldest replay should be evicted")
	}
	if _, ok := s.Get(fmt.Sprintf("rp_%03d", ReplayCap+4)); !ok {
		t.Fatal("newest replay missing")
	}
}

func TestReplayAccessRules(t *testing.T) {
	acc, _ := testAccounts(t)
	hub := NewHub()
	hub.acc = acc
	hub.replays = NewMemReplayStore()
	// One ranked replay (public to logged-in accounts) and one
	// custom replay (participants Chi + Pho only).
	if err := hub.replays.Put(&Replay{ID: "rp_ranked", Ranked: true,
		Players: []ReplayPlayer{{Slot: 0, User: "Chi"}, {Slot: 1, User: "Pho"}}}); err != nil {
		t.Fatal(err)
	}
	if err := hub.replays.Put(&Replay{ID: "rp_custom", Ranked: false,
		Players: []ReplayPlayer{{Slot: 0, User: "Chi"}, {Slot: 1, User: "Pho"}}}); err != nil {
		t.Fatal(err)
	}
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

	login := func(name string) *wsTestClient {
		c := dialWS(t, url)
		c.send(t, map[string]any{"t": "register", "user": name, "pass": "secret1"})
		c.recvUntil(t, "auth_ok")
		return c
	}
	chi := login("Chi")
	defer chi.conn.Close()
	third := login("Ngoai")
	defer third.conn.Close()
	guestC := dialWS(t, url)
	defer guestC.conn.Close()

	// Ranked: any logged-in account may fetch.
	third.send(t, map[string]any{"t": "replay", "replay_id": "rp_ranked"})
	d := third.recvUntil(t, "replay_data")
	if rep, _ := d["replay"].(map[string]any); rep["id"] != "rp_ranked" {
		t.Fatalf("ranked fetch = %v", d)
	}
	// Custom: a non-participant is refused…
	third.send(t, map[string]any{"t": "replay", "replay_id": "rp_custom"})
	e := third.recvUntil(t, "replay_error")
	if e["msg"] == "" || e["msg"] == nil {
		t.Fatalf("expected refusal, got %v", e)
	}
	// …a participant is served…
	chi.send(t, map[string]any{"t": "replay", "replay_id": "rp_custom"})
	d2 := chi.recvUntil(t, "replay_data")
	if rep, _ := d2["replay"].(map[string]any); rep["id"] != "rp_custom" {
		t.Fatalf("participant fetch = %v", d2)
	}
	// …and a guest is told to log in (even for ranked).
	guestC.send(t, map[string]any{"t": "replay", "replay_id": "rp_ranked"})
	e2 := guestC.recvUntil(t, "replay_error")
	if e2["msg"] == "" || e2["msg"] == nil {
		t.Fatalf("expected guest refusal, got %v", e2)
	}
	// Unknown id.
	chi.send(t, map[string]any{"t": "replay", "replay_id": "rp_nope"})
	e3 := chi.recvUntil(t, "replay_error")
	if e3["msg"] == "" || e3["msg"] == nil {
		t.Fatalf("expected not-found, got %v", e3)
	}
}
