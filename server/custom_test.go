package main

// 15a custom-match expansion: room password, room browser,
// observers, host kick/transfer. Hub-level tests use fakeSender
// like hub_test.go; one wire test at the end exercises the whole
// flow through real sessions.

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func startTwoPlayerMatch(t *testing.T, h *Hub, opts RoomCreateOptions) (*Room, *fakeSender, *fakeSender) {
	t.Helper()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains", opts)
	guest := &fakeSender{}
	if _, _, err := h.JoinRoomEx(guest, r.Code, "Guest", opts.Password, ""); err != nil {
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
	t.Cleanup(func() {
		h.Disconnect(r.Code, 0)
		h.Disconnect(r.Code, 1)
	})
	return r, host, guest
}

func TestRoomPasswordAcceptReject(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoomEx(host, "Host", "grassland", "plains",
		RoomCreateOptions{Password: "matkhau1"})
	// The plaintext password must never ride a broadcast.
	for _, raw := range host.raw {
		if strings.Contains(string(raw), "matkhau1") {
			t.Fatalf("password leaked in broadcast: %s", raw)
		}
	}
	// Room state advertises only the flag.
	if got := host.lastRoom()["has_password"]; got != true {
		t.Fatalf("has_password = %v, want true", got)
	}
	if _, _, err := h.JoinRoomEx(&fakeSender{}, r.Code, "NoPass", "", ""); err != ErrBadPassword {
		t.Fatalf("no-password join err = %v, want ErrBadPassword", err)
	}
	if _, _, err := h.JoinRoomEx(&fakeSender{}, r.Code, "Wrong", "sai-roi", ""); err != ErrBadPassword {
		t.Fatalf("wrong-password join err = %v, want ErrBadPassword", err)
	}
	p, _, err := h.JoinRoomEx(&fakeSender{}, r.Code, "Right", "matkhau1", "")
	if err != nil {
		t.Fatalf("right-password join: %v", err)
	}
	_ = p
	// Clearing the password via host config opens the room.
	if err := h.SetConfigEx(r.Code, 0, RoomConfigUpdate{SetPassword: true, Password: ""}); err != nil {
		t.Fatalf("clear password: %v", err)
	}
	if _, _, err := h.JoinRoomEx(&fakeSender{}, r.Code, "Open", "", ""); err != nil {
		t.Fatalf("join after clear: %v", err)
	}
}

func TestRoomBrowserVisibility(t *testing.T) {
	h := NewHub()
	base := time.Unix(1_700_000_000, 0)
	now := base
	h.mmNow = func() time.Time { return now }
	pub := h.CreateRoomEx(&fakeSender{}, "An", "grassland", "plains",
		RoomCreateOptions{Public: true, Name: "Phòng vui vẻ", Password: "x", AllowObs: true})
	h.CreateRoomEx(&fakeSender{}, "Binh", "desert", "river",
		RoomCreateOptions{Public: false, Name: "Phòng kín"})
	now = base.Add(95 * time.Second)
	rows := h.ListPublicRooms()
	if len(rows) != 1 {
		t.Fatalf("browser rows = %d, want 1 (public only)", len(rows))
	}
	row := rows[0]
	if row["code"] != pub.Code || row["name"] != "Phòng vui vẻ" || row["host"] != "An" {
		t.Fatalf("browser row identity = %v", row)
	}
	if row["players"] != 1 || row["max"] != MaxPlayersPerRoom ||
		row["has_password"] != true || row["allow_obs"] != true {
		t.Fatalf("browser row flags = %v", row)
	}
	if row["age_sec"] != int64(95) {
		t.Fatalf("age_sec = %v, want 95", row["age_sec"])
	}
	// A running match leaves the browser.
	if _, _, err := h.JoinRoomEx(&fakeSender{}, pub.Code, "Guest", "x", ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	h.SetReady(pub.Code, 0, true)
	h.SetReady(pub.Code, 1, true)
	if err := h.Start(pub.Code, 0); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer func() {
		h.Disconnect(pub.Code, 0)
		h.Disconnect(pub.Code, 1)
	}()
	if rows := h.ListPublicRooms(); len(rows) != 0 {
		t.Fatalf("browser rows after start = %d, want 0", len(rows))
	}
	// A queue-flagged room is never listed even if marked public.
	qr := h.CreateRoomEx(&fakeSender{}, "Q", "grassland", "plains",
		RoomCreateOptions{Public: true})
	h.mu.Lock()
	qr.Queued = true
	h.mu.Unlock()
	if rows := h.ListPublicRooms(); len(rows) != 0 {
		t.Fatalf("browser rows with queued room = %d, want 0", len(rows))
	}
}

func TestKickAndBan(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "Host", "grassland", "plains")
	guest := &fakeSender{}
	_, gp, err := h.JoinRoomEx(guest, r.Code, "Kicked", "", "acc_kicked")
	if err != nil {
		t.Fatalf("join: %v", err)
	}
	// Only the host kicks.
	if err := h.KickPlayer(r.Code, gp.Slot, 0); err != ErrNotHost {
		t.Fatalf("guest kick err = %v, want ErrNotHost", err)
	}
	if err := h.KickPlayer(r.Code, 0, gp.Slot); err != nil {
		t.Fatalf("host kick: %v", err)
	}
	if got := guest.ofType("kicked"); len(got) == 0 {
		t.Fatal("kicked player never received the kicked notice")
	}
	// The slot is gone and both identities are banned: the guest
	// name AND the account, even under a fresh guest name.
	if _, _, err := h.JoinRoomEx(&fakeSender{}, r.Code, "Kicked", "", ""); err != ErrBanned {
		t.Fatalf("rejoin by name err = %v, want ErrBanned", err)
	}
	if _, _, err := h.JoinRoomEx(&fakeSender{}, r.Code, "TenKhac", "", "acc_kicked"); err != ErrBanned {
		t.Fatalf("rejoin by account err = %v, want ErrBanned", err)
	}
	// A genuinely different guest is unaffected.
	if _, _, err := h.JoinRoomEx(&fakeSender{}, r.Code, "NguoiMoi", "", ""); err != nil {
		t.Fatalf("fresh guest join: %v", err)
	}
}

func TestKickMidMatchKeepsSlots(t *testing.T) {
	h := NewHub()
	r, host, guest := startTwoPlayerMatch(t, h, RoomCreateOptions{})
	_ = host
	if err := h.KickPlayer(r.Code, 0, 1); err != nil {
		t.Fatalf("mid-match kick: %v", err)
	}
	// The kicked slot stays in the room, marked disconnected —
	// the same accounting as a dropout.
	p := r.Players[1]
	if p == nil || p.Connected {
		t.Fatalf("kicked slot state = %+v, want present + disconnected", p)
	}
	if got := host.ofType("player_left"); len(got) == 0 {
		t.Fatal("host never saw player_left for the kicked slot")
	}
	_ = guest
}

func TestHostTransferAndAutoTransfer(t *testing.T) {
	h := NewHub()
	host := &fakeSender{}
	r := h.CreateRoom(host, "Host", "grassland", "plains")
	_, p2, _ := h.JoinRoom(&fakeSender{}, r.Code, "Hai")
	_, p3, _ := h.JoinRoom(&fakeSender{}, r.Code, "Ba")
	// Explicit transfer is host-only and lands in the broadcast.
	if err := h.TransferHost(r.Code, p2.Slot, p3.Slot); err != ErrNotHost {
		t.Fatalf("non-host transfer err = %v, want ErrNotHost", err)
	}
	if err := h.TransferHost(r.Code, 0, p2.Slot); err != nil {
		t.Fatalf("transfer: %v", err)
	}
	if r.Host != p2.Slot {
		t.Fatalf("host = %d, want %d", r.Host, p2.Slot)
	}
	if got := host.lastRoom()["host"]; got != float64(p2.Slot) {
		t.Fatalf("broadcast host = %v, want %d", got, p2.Slot)
	}
	// Transfer back, then exercise leave order: P2 leaves and
	// REJOINS (fresh, larger Seq, slot 1 again). When the host
	// then leaves, the role must go to P3 — present longer than
	// the rejoined P2 despite the higher slot number.
	if err := h.TransferHost(r.Code, p2.Slot, 0); err != nil {
		t.Fatalf("transfer back: %v", err)
	}
	h.Disconnect(r.Code, p2.Slot)
	_, p2b, err := h.JoinRoom(&fakeSender{}, r.Code, "Hai")
	if err != nil {
		t.Fatalf("rejoin: %v", err)
	}
	if p2b.Slot != p2.Slot {
		t.Fatalf("rejoin slot = %d, want recycled %d", p2b.Slot, p2.Slot)
	}
	h.Disconnect(r.Code, 0)
	if r.Host != p3.Slot {
		t.Fatalf("auto host = %d, want longest-present %d", r.Host, p3.Slot)
	}
}

func TestHostAutoTransferMidMatch(t *testing.T) {
	h := NewHub()
	r, _, _ := startTwoPlayerMatch(t, h, RoomCreateOptions{})
	h.Disconnect(r.Code, 0)
	if r.Host != 1 {
		t.Fatalf("mid-match host = %d, want 1 (connected reporter)", r.Host)
	}
	// The new host can bank the result through the usual path.
	if _, err := h.RecordMatchResult(r.Code, 1, 1, nil); err != nil {
		t.Fatalf("new host result report: %v", err)
	}
}

func TestObserverRules(t *testing.T) {
	h := NewHub()
	// Observers refused when the toggle is off.
	plain := h.CreateRoom(&fakeSender{}, "Host", "grassland", "plains")
	if _, _, err := h.JoinObserver(&fakeSender{}, plain.Code, "Watch", "", ""); err != ErrObsDenied {
		t.Fatalf("observe closed room err = %v, want ErrObsDenied", err)
	}
	r, host, guest := startTwoPlayerMatch(t, h, RoomCreateOptions{AllowObs: true})
	_ = guest
	// Mid-match join: the observer gets match_start at once, but
	// the host is asked for a snapshot only once the observer's
	// scene reports ready (a snapshot served during the boot
	// would be lost).
	obs := &fakeSender{}
	_, oc, err := h.JoinObserver(obs, r.Code, "Watch", "", "")
	if err != nil {
		t.Fatalf("observe running match: %v", err)
	}
	if got := obs.ofType("match_start"); len(got) == 0 {
		t.Fatal("mid-match observer never received match_start")
	}
	if got := obs.ofType("obs_sync_pending"); len(got) == 0 {
		t.Fatal("mid-match observer never received obs_sync_pending")
	}
	if got := host.ofType("obs_snapshot_request"); len(got) != 0 {
		t.Fatal("host was asked for a snapshot before the observer was ready")
	}
	h.ObserverReady(r.Code, oc)
	if got := host.ofType("obs_snapshot_request"); len(got) != 1 {
		t.Fatal("host never received obs_snapshot_request after obs_ready")
	}
	h.ObserverReady(r.Code, oc) // a duplicate ready must not re-ask
	if got := host.ofType("obs_snapshot_request"); len(got) != 1 {
		t.Fatal("duplicate obs_ready re-asked the host")
	}
	// A non-host snapshot is ignored; the host's is relayed.
	state := json.RawMessage(`{"v":1,"tick":42}`)
	if err := h.RelayObsSnapshot(r.Code, 1, 42, state); err != nil {
		t.Fatalf("relay from guest: %v", err)
	}
	if got := obs.ofType("snapshot"); len(got) != 0 {
		t.Fatal("guest-served snapshot was relayed")
	}
	if err := h.RelayObsSnapshot(r.Code, 0, 42, state); err != nil {
		t.Fatalf("relay from host: %v", err)
	}
	snaps := obs.ofType("snapshot")
	if len(snaps) != 1 || int(snaps[0]["tick"].(float64)) != 42 {
		t.Fatalf("observer snapshots = %v", snaps)
	}
	// The room stream reaches observers: a relayed command and a
	// tick both land in the observer's inbox.
	cmd := json.RawMessage(`{"kind":"order","units":[1],"x":5,"y":6}`)
	if err := h.RelayCmd(r.Code, 1, cmd); err != nil {
		t.Fatalf("relay cmd: %v", err)
	}
	if got := obs.ofType("cmd"); len(got) == 0 {
		t.Fatal("observer never received the command stream")
	}
	// Observer chat: all-channel works, team scope is refused.
	if err := h.RelayObserverChat(r.Code, oc, "team", "bí mật"); err != ErrObserverCmd {
		t.Fatalf("observer team chat err = %v, want ErrObserverCmd", err)
	}
	if err := h.RelayObserverChat(r.Code, oc, "match", "Hay quá!"); err != nil {
		t.Fatalf("observer match chat: %v", err)
	}
	chats := guest.ofType("chat")
	found := false
	for _, c := range chats {
		if c["observer"] == true && c["text"] == "Hay quá!" &&
			int(c["from"].(float64)) == ObserverSlot {
			found = true
		}
	}
	if !found {
		t.Fatalf("players never received observer chat: %v", chats)
	}
	// Leaving shrinks the roster in the room broadcast.
	h.LeaveObserver(r.Code, oc)
	room := guest.lastRoom()
	if obsList, _ := room["observers"].([]any); len(obsList) != 0 {
		t.Fatalf("observers after leave = %v", obsList)
	}
}

func TestObserverCapAndPassword(t *testing.T) {
	h := NewHub()
	r := h.CreateRoomEx(&fakeSender{}, "Host", "grassland", "plains",
		RoomCreateOptions{AllowObs: true, Password: "pw"})
	if _, _, err := h.JoinObserver(&fakeSender{}, r.Code, "W", "bad", ""); err != ErrBadPassword {
		t.Fatalf("observer wrong password err = %v, want ErrBadPassword", err)
	}
	for i := 0; i < MaxObserversPerRoom; i++ {
		if _, _, err := h.JoinObserver(&fakeSender{}, r.Code, "W", "pw", ""); err != nil {
			t.Fatalf("observer %d join: %v", i, err)
		}
	}
	if _, _, err := h.JoinObserver(&fakeSender{}, r.Code, "W", "pw", ""); err != ErrObsFull {
		t.Fatalf("observer over cap err = %v, want ErrObsFull", err)
	}
}

// TestWireCustomExpansion runs the 15a flow end to end over real
// websockets: create (public + password + observers) -> browse ->
// wrong/right password -> observe -> observer command rejected ->
// host transfer -> the new host kicks the old one.
func TestWireCustomExpansion(t *testing.T) {
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
	a.send(t, map[string]any{"t": "create", "name": "ChuPhong",
		"biome": "grassland", "layout": "plains",
		"room_name": "Phòng Test", "public": true,
		"room_pass": "pw123", "allow_obs": true})
	created := a.recvUntil(t, "created")
	code, _ := created["code"].(string)
	if len(code) != 5 {
		t.Fatalf("created code = %v", created["code"])
	}

	b := dialWS(t, wsURL)
	defer b.conn.Close()
	b.send(t, map[string]any{"t": "list_rooms"})
	list := b.recvUntil(t, "room_list")
	rooms, _ := list["rooms"].([]any)
	if len(rooms) != 1 {
		t.Fatalf("room_list = %v, want the one public room", list["rooms"])
	}
	row, _ := rooms[0].(map[string]any)
	if row["code"] != code || row["name"] != "Phòng Test" ||
		row["has_password"] != true || row["allow_obs"] != true {
		t.Fatalf("room_list row = %v", row)
	}
	// Wrong password is a clear error; the right one joins.
	b.send(t, map[string]any{"t": "join", "code": code, "name": "Khach", "room_pass": "sai"})
	errMsg := b.recvUntil(t, "error")
	if errMsg["msg"] != ErrBadPassword.Error() {
		t.Fatalf("wrong-password error = %v", errMsg["msg"])
	}
	b.send(t, map[string]any{"t": "join", "code": code, "name": "Khach", "room_pass": "pw123"})
	joined := b.recvUntil(t, "joined")
	if int(joined["slot"].(float64)) != 1 {
		t.Fatalf("joined slot = %v, want 1", joined["slot"])
	}
	a.recvUntil(t, "room")

	// Observer attaches with the password; its command is
	// rejected at the relay with an explicit error.
	o := dialWS(t, wsURL)
	defer o.conn.Close()
	o.send(t, map[string]any{"t": "observe", "code": code, "name": "NguoiXem", "room_pass": "pw123"})
	o.recvUntil(t, "observing")
	o.send(t, map[string]any{"t": "cmd", "cmd": map[string]any{"kind": "order"}})
	rej := o.recvUntil(t, "error")
	if rej["msg"] != ErrObserverCmd.Error() {
		t.Fatalf("observer cmd rejection = %v", rej["msg"])
	}

	// Host transfer over the wire: A hands the room to B, then B
	// (the new host) kicks A, who receives the kicked notice.
	a.send(t, map[string]any{"t": "transfer_host", "slot": 1})
	// Earlier room broadcasts (the observer's attach) may still
	// be queued for A; read until the host field actually moves.
	hostMoved := false
	for i := 0; i < 10 && !hostMoved; i++ {
		roomA := a.recvUntil(t, "room")
		hostMoved = int(roomA["host"].(float64)) == 1
	}
	if !hostMoved {
		t.Fatal("room host never moved to slot 1 after transfer")
	}
	b.send(t, map[string]any{"t": "kick", "slot": 0})
	a.recvUntil(t, "kicked")
	// A rejoining under the same name is banned now.
	a.send(t, map[string]any{"t": "leave"})
	a.send(t, map[string]any{"t": "join", "code": code, "name": "ChuPhong", "room_pass": "pw123"})
	banMsg := a.recvUntil(t, "error")
	if banMsg["msg"] != ErrBanned.Error() {
		t.Fatalf("rejoin after kick error = %v, want banned", banMsg["msg"])
	}
}

func TestHostPowersRefusedInQueueRooms(t *testing.T) {
	h := NewHub()
	r := h.CreateRoom(&fakeSender{}, "Host", "grassland", "plains")
	h.JoinRoom(&fakeSender{}, r.Code, "Guest")
	h.mu.Lock()
	r.Queued = true
	h.mu.Unlock()
	if err := h.KickPlayer(r.Code, 0, 1); err != ErrQueuedRoom {
		t.Fatalf("kick in queue room err = %v, want ErrQueuedRoom", err)
	}
	if err := h.TransferHost(r.Code, 0, 1); err != ErrQueuedRoom {
		t.Fatalf("transfer in queue room err = %v, want ErrQueuedRoom", err)
	}
	if _, _, err := h.JoinObserver(&fakeSender{}, r.Code, "W", "", ""); err != ErrObsDenied {
		t.Fatalf("observe queue room err = %v, want ErrObsDenied", err)
	}
}
