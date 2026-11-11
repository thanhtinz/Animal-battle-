package main

import (
	"encoding/json"
	"testing"
)

// Two players, no majority possible: the HOST's hash wins, the host
// becomes the snapshot source, the guest is told to resync.
func TestResyncHostHashWinsWithoutMajority(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 2)
	h.ReportChecksum(r.Code, 0, 60, "aaa")
	h.ReportChecksum(r.Code, 1, 60, "bbb")

	if got := s[0].ofType("snapshot_request"); len(got) != 1 {
		t.Fatalf("host snapshot_request = %d, want 1", len(got))
	} else if int(got[0]["tick"].(float64)) != 60 {
		t.Fatalf("snapshot_request tick = %v, want 60", got[0]["tick"])
	}
	if got := s[1].ofType("snapshot_request"); len(got) != 0 {
		t.Fatalf("guest snapshot_request = %d, want 0", len(got))
	}
	rs := s[1].ofType("resync")
	if len(rs) != 1 {
		t.Fatalf("guest resync = %d, want 1", len(rs))
	}
	if int(rs[0]["tick"].(float64)) != 60 || int(rs[0]["source"].(float64)) != 0 {
		t.Fatalf("resync msg = %v", rs[0])
	}
	if got := s[0].ofType("desync"); len(got) != 1 {
		t.Fatalf("desync notices = %d, want 1 (legacy broadcast kept)", len(got))
	}

	// A snapshot from the wrong slot is ignored.
	if err := h.RelaySnapshot(r.Code, 1, 62, json.RawMessage(`{"v":1}`)); err != nil {
		t.Fatal(err)
	}
	if got := s[1].ofType("snapshot"); len(got) != 0 {
		t.Fatalf("guest snapshot after wrong-slot relay = %d, want 0", len(got))
	}
	// The source's snapshot reaches the diverged client only.
	if err := h.RelaySnapshot(r.Code, 0, 62, json.RawMessage(`{"v":1,"tick":62}`)); err != nil {
		t.Fatal(err)
	}
	snaps := s[1].ofType("snapshot")
	if len(snaps) != 1 {
		t.Fatalf("guest snapshot = %d, want 1", len(snaps))
	}
	if int(snaps[0]["tick"].(float64)) != 62 {
		t.Fatalf("snapshot tick = %v, want 62", snaps[0]["tick"])
	}
	if got := s[0].ofType("snapshot"); len(got) != 0 {
		t.Fatalf("host snapshot = %d, want 0 (source never receives its own)", len(got))
	}
}

// Three players: a 2-of-3 majority wins even against the host.
func TestResyncMajorityBeatsHost(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 3)
	h.ReportChecksum(r.Code, 0, 30, "host-hash")
	h.ReportChecksum(r.Code, 1, 30, "majority")
	h.ReportChecksum(r.Code, 2, 30, "majority")

	// Source = lowest slot holding the majority hash (slot 1).
	if got := s[1].ofType("snapshot_request"); len(got) != 1 {
		t.Fatalf("slot1 snapshot_request = %d, want 1", len(got))
	}
	// The host diverged (it holds the odd hash): it must resync.
	if got := s[0].ofType("resync"); len(got) != 1 {
		t.Fatalf("host resync = %d, want 1", len(got))
	} else if int(got[0]["source"].(float64)) != 1 {
		t.Fatalf("resync source = %v, want 1", got[0]["source"])
	}
	// The other majority holder is only notified.
	notes := s[2].ofType("resync_notice")
	if len(notes) != 1 {
		t.Fatalf("slot2 resync_notice = %d, want 1", len(notes))
	}
	slots := notes[0]["slots"].([]any)
	if len(slots) != 1 || int(slots[0].(float64)) != 0 {
		t.Fatalf("resync_notice slots = %v, want [0]", slots)
	}
	if got := s[2].ofType("resync"); len(got) != 0 {
		t.Fatalf("slot2 resync = %d, want 0", len(got))
	}
}

// The retry/give-up clock: re-ask once, then release frozen clients.
func TestResyncRetryAndFail(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 2)
	h.ReportChecksum(r.Code, 0, 60, "aaa")
	h.ReportChecksum(r.Code, 1, 60, "bbb")
	if len(s[0].ofType("snapshot_request")) != 1 {
		t.Fatal("expected the initial snapshot_request")
	}
	maintain := func(tick int64) {
		h.mu.Lock()
		r.Tick = tick
		h.resyncMaintenanceLocked(r)
		h.mu.Unlock()
	}
	// Inside the retry window: nothing new.
	maintain(ResyncRetryTicks)
	if len(s[0].ofType("snapshot_request")) != 1 {
		t.Fatal("snapshot re-requested too early")
	}
	// Past the retry threshold: exactly one re-ask.
	maintain(ResyncRetryTicks + 1)
	maintain(ResyncRetryTicks + 2)
	if got := len(s[0].ofType("snapshot_request")); got != 2 {
		t.Fatalf("snapshot_request count = %d, want 2 (initial + one retry)", got)
	}
	// Past the fail threshold: the diverged client is released.
	maintain(ResyncFailTicks + 1)
	if got := s[1].ofType("resync_failed"); len(got) != 1 {
		t.Fatalf("guest resync_failed = %d, want 1", len(got))
	}
	// Cycle closed: a fresh divergence can open a new one.
	h.ReportChecksum(r.Code, 0, 90, "x")
	h.ReportChecksum(r.Code, 1, 90, "y")
	if got := len(s[0].ofType("snapshot_request")); got != 3 {
		t.Fatalf("snapshot_request after new divergence = %d, want 3", got)
	}
}

// If the snapshot source drops mid-cycle, frozen clients are
// released with resync_failed instead of waiting forever.
func TestResyncSourceDisconnectAborts(t *testing.T) {
	h := NewHub()
	r, s := startRoom(t, h, 2)
	h.ReportChecksum(r.Code, 0, 60, "aaa")
	h.ReportChecksum(r.Code, 1, 60, "bbb")
	if len(s[0].ofType("snapshot_request")) != 1 {
		t.Fatal("expected the initial snapshot_request")
	}
	h.Disconnect(r.Code, 0) // source (host) drops
	if got := s[1].ofType("resync_failed"); len(got) != 1 {
		t.Fatalf("guest resync_failed = %d, want 1", len(got))
	}
	h.Disconnect(r.Code, 1)
}
