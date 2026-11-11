package main

// 15e spectator: the anti-cheat observer delay (server-side
// buffering), the delayed mid-match snapshot join, the
// observer kick, and the delay's public surfaces (room
// broadcast + browser rows + config edits). The buffer tests
// drive flushObsDelayLocked with a synthetic clock at the
// PRODUCTION delay (60s) — no test-only delay value anywhere.

import (
	"encoding/json"
	"testing"
	"time"
)

func specMsgCount(f *fakeSender) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.msgs)
}

// specMsgIndex returns the index of the first message of type
// typ at or after `from`, or -1.
func specMsgIndex(f *fakeSender, from int, typ string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	for i := from; i < len(f.msgs); i++ {
		if f.msgs[i]["t"] == typ {
			return i
		}
	}
	return -1
}

func specFlush(h *Hub, r *Room, ahead time.Duration) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.flushObsDelayLocked(r, time.Now().Add(ahead))
}

// A delayed room: lobby traffic flows, then from match_start on
// the observer receives NOTHING until the delay elapses — while
// the players get everything instantly. After the delay the
// observer's stream arrives in the original broadcast order.
func TestObsDelayBuffersMatchTraffic(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{Public: true, AllowObs: true, ObsDelaySec: 60})
	obs := &fakeSender{}
	if _, _, err := h.JoinObserver(obs, r.Code, "Watch", "", ""); err != nil {
		t.Fatalf("observe: %v", err)
	}
	guest := &fakeSender{}
	if _, _, err := h.JoinRoomEx(guest, r.Code, "Guest", "", ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	// Lobby-phase room state reached the observer immediately:
	// the delay covers live match state, never the lobby.
	if len(obs.ofType("room")) == 0 {
		t.Fatal("observer got no lobby room broadcast")
	}
	if err := h.SetReady(r.Code, 0, true); err != nil {
		t.Fatal(err)
	}
	if err := h.SetReady(r.Code, 1, true); err != nil {
		t.Fatal(err)
	}
	mark := specMsgCount(obs)
	if err := h.Start(r.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	t.Cleanup(func() {
		h.Disconnect(r.Code, 0)
		h.Disconnect(r.Code, 1)
	})
	// Even match_start itself waits out the delay.
	if n := len(obs.ofType("match_start")); n != 0 {
		t.Fatalf("observer received match_start before the delay (%d)", n)
	}
	cmd := json.RawMessage(`{"kind":"order","units":[1],"x":5,"y":5}`)
	if err := h.RelayCmd(r.Code, 0, cmd); err != nil {
		t.Fatal(err)
	}
	if err := h.RelayChat(r.Code, 1, "match", "đánh thôi"); err != nil {
		t.Fatal(err)
	}
	// Players are never delayed.
	if len(guest.ofType("cmd")) == 0 || len(host.ofType("chat")) == 0 {
		t.Fatal("players did not receive live traffic instantly")
	}
	// Observer chat stays realtime even in a delayed room.
	h.mu.Lock()
	oc := r.Observers[0]
	h.mu.Unlock()
	if err := h.RelayObserverChat(r.Code, oc, "match", "hay quá"); err != nil {
		t.Fatal(err)
	}
	if specMsgIndex(obs, mark, "chat") < 0 {
		t.Fatal("observer's own chat was delayed")
	}
	// One second before the delay: still nothing of the match.
	specFlush(h, r, 59*time.Second)
	if specMsgIndex(obs, mark, "match_start") >= 0 ||
		specMsgIndex(obs, mark, "cmd") >= 0 {
		t.Fatal("delayed traffic leaked before 60s")
	}
	// After the delay: the whole stream, in broadcast order.
	specFlush(h, r, 61*time.Second)
	iStart := specMsgIndex(obs, mark, "match_start")
	iCmd := specMsgIndex(obs, mark, "cmd")
	iChat := -1
	obs.mu.Lock()
	for i := mark; i < len(obs.msgs); i++ {
		if obs.msgs[i]["t"] == "chat" {
			if txt, _ := obs.msgs[i]["text"].(string); txt == "đánh thôi" {
				iChat = i
			}
		}
	}
	obs.mu.Unlock()
	if iStart < 0 || iCmd < 0 || iChat < 0 {
		t.Fatalf("delayed stream incomplete: start=%d cmd=%d chat=%d", iStart, iCmd, iChat)
	}
	if !(iStart < iCmd && iCmd < iChat) {
		t.Fatalf("delayed stream out of order: start=%d cmd=%d chat=%d", iStart, iCmd, iChat)
	}
}

// A mid-match join into a delayed room: the host-served
// snapshot joins the SAME delay queue, so the observer applies
// a snapshot that is exactly the delay old, with pre-snapshot
// commands banked before it and post-snapshot commands after.
func TestObsDelaySnapshotJoin(t *testing.T) {
	h := NewHub()
	r, host, _ := startTwoPlayerMatch(t, h,
		RoomCreateOptions{AllowObs: true, ObsDelaySec: 60})
	obs := &fakeSender{}
	_, oc, err := h.JoinObserver(obs, r.Code, "Late", "", "")
	if err != nil {
		t.Fatalf("observe mid-match: %v", err)
	}
	// Session-control messages are NOT delayed: the joiner must
	// be able to boot its (frozen) match scene right away.
	if len(obs.ofType("obs_sync_pending")) != 1 || len(obs.ofType("match_start")) != 1 {
		t.Fatal("mid-match join control messages were delayed")
	}
	cmdA := json.RawMessage(`{"kind":"order","units":[2],"x":1,"y":1}`)
	if err := h.RelayCmd(r.Code, 0, cmdA); err != nil {
		t.Fatal(err)
	}
	h.ObserverReady(r.Code, oc)
	if len(host.ofType("obs_snapshot_request")) == 0 {
		t.Fatal("host was not asked for the observer snapshot")
	}
	state := json.RawMessage(`{"units":[],"buildings":[]}`)
	if err := h.RelayObsSnapshot(r.Code, 0, 42, state); err != nil {
		t.Fatal(err)
	}
	cmdB := json.RawMessage(`{"kind":"order","units":[3],"x":2,"y":2}`)
	if err := h.RelayCmd(r.Code, 1, cmdB); err != nil {
		t.Fatal(err)
	}
	if len(obs.ofType("snapshot")) != 0 || len(obs.ofType("cmd")) != 0 {
		t.Fatal("delayed joiner received match traffic before the delay")
	}
	specFlush(h, r, 59*time.Second)
	if len(obs.ofType("snapshot")) != 0 {
		t.Fatal("snapshot leaked before the delay")
	}
	specFlush(h, r, 61*time.Second)
	iSnap := specMsgIndex(obs, 0, "snapshot")
	iA := specMsgIndex(obs, 0, "cmd")
	iB := -1
	obs.mu.Lock()
	nCmd := 0
	for i, m := range obs.msgs {
		if m["t"] == "cmd" {
			nCmd++
			if nCmd == 2 {
				iB = i
			}
		}
	}
	obs.mu.Unlock()
	if iSnap < 0 || iA < 0 || iB < 0 {
		t.Fatalf("delayed join stream incomplete: cmdA=%d snap=%d cmdB=%d", iA, iSnap, iB)
	}
	if !(iA < iSnap && iSnap < iB) {
		t.Fatalf("snapshot out of stream order: cmdA=%d snap=%d cmdB=%d", iA, iSnap, iB)
	}
}

// The observer kick (missing in 15a): host-only, sends the
// kicked notice, removes the observer and bans their return.
func TestKickObserver(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{AllowObs: true})
	guest := &fakeSender{}
	if _, _, err := h.JoinRoomEx(guest, r.Code, "Guest", "", ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	obs := &fakeSender{}
	if _, _, err := h.JoinObserver(obs, r.Code, "Watch", "", ""); err != nil {
		t.Fatalf("observe: %v", err)
	}
	if err := h.KickObserver(r.Code, 1, "Watch"); err != ErrNotHost {
		t.Fatalf("non-host kick err = %v, want ErrNotHost", err)
	}
	if err := h.KickObserver(r.Code, 0, "Nobody"); err != ErrNotInRoom {
		t.Fatalf("unknown observer kick err = %v, want ErrNotInRoom", err)
	}
	if err := h.KickObserver(r.Code, 0, "Watch"); err != nil {
		t.Fatalf("host kick: %v", err)
	}
	if len(obs.ofType("kicked")) != 1 {
		t.Fatal("kicked observer got no kicked notice")
	}
	h.mu.Lock()
	n := len(r.Observers)
	h.mu.Unlock()
	if n != 0 {
		t.Fatalf("observer still in roster after kick (%d)", n)
	}
	if _, _, err := h.JoinObserver(&fakeSender{}, r.Code, "Watch", "", ""); err != ErrBanned {
		t.Fatalf("kicked observer rejoin err = %v, want ErrBanned", err)
	}
}

// The delay is visible before joining: room broadcast, browser
// rows, and host config edits all carry it (and clamp it).
func TestObsDelaySurfacesAndConfig(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{Public: true, AllowObs: true, ObsDelaySec: 60})
	if got := host.lastRoom()["obs_delay"]; got != float64(60) {
		t.Fatalf("room broadcast obs_delay = %v, want 60", got)
	}
	rows := h.ListPublicRooms()
	found := false
	for _, row := range rows {
		if row["code"] == r.Code {
			found = true
			if row["obs_delay"] != 60 {
				t.Fatalf("browser row obs_delay = %v, want 60", row["obs_delay"])
			}
		}
	}
	if !found {
		t.Fatal("delayed room missing from the browser")
	}
	if err := h.SetConfigEx(r.Code, 0, RoomConfigUpdate{
		TouchAccess: true, Public: true, AllowObs: true, ObsDelaySec: 120,
	}); err != nil {
		t.Fatal(err)
	}
	if r.ObsDelaySec != 120 || host.lastRoom()["obs_delay"] != float64(120) {
		t.Fatalf("config edit did not move the delay (room=%d)", r.ObsDelaySec)
	}
	if err := h.SetConfigEx(r.Code, 0, RoomConfigUpdate{
		TouchAccess: true, ObsDelaySec: -5,
	}); err != nil {
		t.Fatal(err)
	}
	if r.ObsDelaySec != 0 {
		t.Fatalf("negative delay not clamped (room=%d)", r.ObsDelaySec)
	}
	// A default room advertises the key at 0 (live).
	plain := &fakeSender{}
	h.CreateRoomEx(plain, "Plain", "grassland", "plains", RoomCreateOptions{})
	if got, ok := plain.lastRoom()["obs_delay"]; !ok || got != float64(0) {
		t.Fatalf("default room obs_delay = %v (present=%v), want 0", got, ok)
	}
}

// Delay 0 keeps the 15a behaviour byte-for-byte: observers
// receive match traffic immediately, no queue involved.
func TestObsDelayZeroStaysLive(t *testing.T) {
	h := NewHub()
	r, _, _ := startTwoPlayerMatch(t, h, RoomCreateOptions{AllowObs: true})
	obs := &fakeSender{}
	if _, _, err := h.JoinObserver(obs, r.Code, "Live", "", ""); err != nil {
		t.Fatalf("observe: %v", err)
	}
	cmd := json.RawMessage(`{"kind":"order","units":[1],"x":9,"y":9}`)
	if err := h.RelayCmd(r.Code, 0, cmd); err != nil {
		t.Fatal(err)
	}
	if len(obs.ofType("cmd")) == 0 {
		t.Fatal("live observer did not receive the command immediately")
	}
	h.mu.Lock()
	q := 0
	for _, o := range r.Observers {
		q += len(o.delayQ)
	}
	h.mu.Unlock()
	if q != 0 {
		t.Fatalf("live room queued %d messages", q)
	}
}
