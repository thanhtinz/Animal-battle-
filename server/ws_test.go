package main

// End-to-end test: a real HTTP server + a minimal hand-rolled
// WebSocket client (stdlib only), exercising create -> join -> ready
// -> start -> cmd relay over the wire exactly as the Godot client
// will speak it.

import (
	"bufio"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type wsTestClient struct {
	conn   net.Conn
	reader *bufio.Reader
}

func dialWS(t *testing.T, url string) *wsTestClient {
	t.Helper()
	// url looks like http://127.0.0.1:PORT/ws
	addr := strings.TrimPrefix(strings.TrimSuffix(url, "/ws"), "http://")
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	keyBytes := make([]byte, 16)
	rand.Read(keyBytes)
	key := base64.StdEncoding.EncodeToString(keyBytes)
	req := fmt.Sprintf("GET /ws HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n", addr, key)
	if _, err := conn.Write([]byte(req)); err != nil {
		t.Fatalf("handshake write: %v", err)
	}
	br := bufio.NewReader(conn)
	status, err := br.ReadString('\n')
	if err != nil || !strings.Contains(status, "101") {
		t.Fatalf("handshake status = %q err=%v", status, err)
	}
	// Read headers; verify the accept value while doing so.
	expect := computeAcceptForTest(key)
	found := false
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			t.Fatalf("handshake headers: %v", err)
		}
		if line == "\r\n" {
			break
		}
		if strings.HasPrefix(strings.ToLower(line), "sec-websocket-accept:") &&
			strings.Contains(line, expect) {
			found = true
		}
	}
	if !found {
		t.Fatal("Sec-WebSocket-Accept missing/incorrect")
	}
	return &wsTestClient{conn: conn, reader: br}
}

func computeAcceptForTest(key string) string {
	h := sha1.New()
	io.WriteString(h, key+wsGUID)
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func (c *wsTestClient) send(t *testing.T, v map[string]any) {
	t.Helper()
	data, _ := json.Marshal(v)
	var frame []byte
	frame = append(frame, 0x81) // FIN + text
	maskKey := []byte{0x12, 0x34, 0x56, 0x78}
	switch {
	case len(data) < 126:
		frame = append(frame, 0x80|byte(len(data)))
	case len(data) < 65536:
		frame = append(frame, 0x80|126, byte(len(data)>>8), byte(len(data)))
	}
	frame = append(frame, maskKey...)
	for i, b := range data {
		frame = append(frame, b^maskKey[i%4])
	}
	if _, err := c.conn.Write(frame); err != nil {
		t.Fatalf("send: %v", err)
	}
}

func (c *wsTestClient) recv(t *testing.T) map[string]any {
	t.Helper()
	c.conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		var hdr [2]byte
		if _, err := io.ReadFull(c.reader, hdr[:]); err != nil {
			t.Fatalf("recv header: %v", err)
		}
		opcode := hdr[0] & 0x0F
		length := uint64(hdr[1] & 0x7F)
		switch length {
		case 126:
			var b [2]byte
			io.ReadFull(c.reader, b[:])
			length = uint64(binary.BigEndian.Uint16(b[:]))
		case 127:
			var b [8]byte
			io.ReadFull(c.reader, b[:])
			length = binary.BigEndian.Uint64(b[:])
		}
		payload := make([]byte, length)
		if _, err := io.ReadFull(c.reader, payload); err != nil {
			t.Fatalf("recv payload: %v", err)
		}
		if opcode == 0x9 { // ping: our test client ignores (server does not ping)
			continue
		}
		if opcode != 0x1 {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal(payload, &m); err != nil {
			t.Fatalf("recv json: %v (%s)", err, payload)
		}
		return m
	}
}

// recvUntil collects messages until one has type `want` (or fails).
func (c *wsTestClient) recvUntil(t *testing.T, want string) map[string]any {
	t.Helper()
	for i := 0; i < 30; i++ {
		m := c.recv(t)
		if m["t"] == want {
			return m
		}
	}
	t.Fatalf("never received %q", want)
	return nil
}

func TestWSEndToEnd(t *testing.T) {
	hub := NewHub()
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgradeWS(w, r)
		if err != nil {
			http.Error(w, "upgrade failed", http.StatusBadRequest)
			return
		}
		s := &session{hub: hub, conn: conn}
		conn.onText = s.handle
		conn.onGone = s.gone
		go conn.readLoop()
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	wsURL := srv.URL + "/ws"

	a := dialWS(t, wsURL)
	defer a.conn.Close()
	a.send(t, map[string]any{"t": "create", "name": "Alice", "biome": "desert", "layout": "river"})
	created := a.recvUntil(t, "created")
	code, _ := created["code"].(string)
	if len(code) != 5 {
		t.Fatalf("created code = %v", created["code"])
	}
	// (The room state broadcast precedes "created" on the wire, so A
	// already consumed it while waiting above.)

	b := dialWS(t, wsURL)
	defer b.conn.Close()
	b.send(t, map[string]any{"t": "join", "code": code, "name": "Bob"})
	joined := b.recvUntil(t, "joined")
	if int(joined["slot"].(float64)) != 1 {
		t.Fatalf("guest slot = %v, want 1", joined["slot"])
	}
	a.recvUntil(t, "room") // broadcast of the join reaches the host fresh
	// (B likewise already consumed its own room broadcast.)

	// B readies first and A waits for the room broadcast that
	// follows: without this sync A's "start" can race ahead of B's
	// "ready" (different connections, async handlers) and the hub
	// correctly rejects it with not-all-ready.
	b.send(t, map[string]any{"t": "ready", "ready": true})
	a.recvUntil(t, "room")
	a.send(t, map[string]any{"t": "ready", "ready": true})
	a.send(t, map[string]any{"t": "start"})
	start := a.recvUntil(t, "match_start")
	if start["biome"] != "desert" || start["layout"] != "river" {
		t.Fatalf("match_start config = %v/%v", start["biome"], start["layout"])
	}
	players, _ := start["players"].([]any)
	if len(players) != 2 {
		t.Fatalf("match_start players = %v", start["players"])
	}
	b.recvUntil(t, "match_start")

	// A command from B must come back to BOTH with an exec tick.
	b.send(t, map[string]any{"t": "cmd", "cmd": map[string]any{"kind": "order", "units": []int{7}, "x": 100, "y": 200}})
	relA := a.recvUntil(t, "cmd")
	relB := b.recvUntil(t, "cmd")
	if relA["tick"] != relB["tick"] {
		t.Fatalf("exec ticks differ: A=%v B=%v", relA["tick"], relB["tick"])
	}
	if int(relA["from"].(float64)) != 1 {
		t.Fatalf("cmd from = %v, want 1", relA["from"])
	}
	// Ticks flow.
	a.recvUntil(t, "tick")
	// Dropping B notifies A.
	b.conn.Close()
	left := a.recvUntil(t, "player_left")
	if int(left["slot"].(float64)) != 1 {
		t.Fatalf("player_left slot = %v, want 1", left["slot"])
	}
}
