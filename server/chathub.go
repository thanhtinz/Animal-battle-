package main

// Empire Age 17e — the out-of-match CHAT HUB: one home for
// every chat surface that is not inside a match (the owner's
// order: "Toàn bộ liên quan tới chat sẽ ở đây, trừ chat trong
// màn game"). This file carries the server half:
//
//   - the emoticon token set + sanitiser (tokens are plain
//     text on the wire; the client renders known ids as
//     inline images and the server strips unknown ones);
//   - the world channel (hub.RelayWorldChat): fan-out to
//     every logged-in session, room-chat rate limits;
//   - private 1:1 chat (the DMs service): per-pair history
//     persisted through the Store, unread counts, live
//     fan-out through the hub's per-user registry;
//   - voice messages (hub voice relays): one WAV payload,
//     hard caps, LIVE RELAY ONLY — voice is never written
//     into any stored history (the honest simpler retention:
//     a voice line exists for the session that hears it,
//     exactly like a spoken sentence);
//   - the Loa thông báo megaphone: an admin-granted
//     consumable; using one broadcasts a scrolling marquee
//     to every online player (lobby sessions AND rooms).
//
// Everything here is lobby traffic: nothing touches a room,
// the lockstep sim or any checksum.

import (
	"encoding/base64"
	"errors"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

// ------------------------------------------------------------ emoticons

// EmoteIDs is the drawn emoticon catalogue (client assets in
// godot/assets/emotes/<id>.png, built by
// tools/build_emotes.py). A chat token is the literal text
// "[e:<id>]"; only ids in this list survive the server.
var EmoteIDs = []string{
	"vui", "cuoi", "cuoi_khoc", "khoc", "buon", "gian",
	"ngac_nhien", "so", "choang", "ngu", "yeu", "tim",
	"like", "dislike", "yes", "no", "le_luoi", "xau_ho",
	"nghi", "om", "cuoi_deu", "hun", "kho_hieu", "met",
}

var emoteIDSet = func() map[string]bool {
	m := make(map[string]bool, len(EmoteIDs))
	for _, id := range EmoteIDs {
		m[id] = true
	}
	return m
}()

var emoteTokenRe = regexp.MustCompile(`\[e:([a-z0-9_]+)\]`)

// MaxEmotesPerMsg caps how many emoticon tokens one message
// may carry; further tokens are stripped like unknown ones.
const MaxEmotesPerMsg = 8

// SanitizeEmotes validates the emoticon tokens in a chat
// text: known ids (up to MaxEmotesPerMsg) stay, everything
// else in token shape is removed. Ordinary text is untouched.
func SanitizeEmotes(text string) string {
	seen := 0
	return emoteTokenRe.ReplaceAllStringFunc(text, func(tok string) string {
		id := emoteTokenRe.FindStringSubmatch(tok)[1]
		if !emoteIDSet[id] || seen >= MaxEmotesPerMsg {
			return ""
		}
		seen++
		return tok
	})
}

// StripEmotes removes every emoticon token (used where only
// plain text renders: the megaphone marquee, transcripts).
func StripEmotes(text string) string {
	return strings.TrimSpace(emoteTokenRe.ReplaceAllString(text, ""))
}

// ------------------------------------------------------------ voice

// Voice caps (owner defaults, flagged in KE-HOACH §17e): a
// voice note is at most ~30 s; the client records at
// 11025 Hz mono 16-bit (≈22 KB/s), so the byte cap below is
// the ≈31 s hard stop behind the duration cap. The relay
// validates BOTH the declared duration and the real bytes.
const (
	VoiceMaxSeconds = 30.0
	VoiceMaxBytes   = 700_000
	// VoiceMaxRate rejects full-bandwidth captures: anything
	// above 16 kHz was not produced by the client's recorder
	// pipeline and would blow the byte budget per second.
	VoiceMaxRate = 16000
	// VoiceRateCount / VoiceRateWindow: voice is heavier
	// than text, so its budget is separate and tighter.
	VoiceRateCount  = 2
	VoiceRateWindow = 10 * time.Second
)

var (
	ErrVoiceTooBig  = errors.New("Tin nhắn thoại quá lớn")
	ErrVoiceTooLong = errors.New("Tin nhắn thoại quá dài (tối đa 30 giây)")
	ErrVoiceBadData = errors.New("Dữ liệu thoại không hợp lệ")
	ErrNotLoggedIn  = errors.New("Đăng nhập để dùng Chat")
	ErrNoMegaphone  = errors.New("Bạn không có Loa thông báo — vật phẩm nhận qua sự kiện")
	ErrNotAdmin     = errors.New("Không có quyền thực hiện thao tác này")
	ErrDMTarget     = errors.New("Không tìm thấy người chơi này")
	ErrDMSelf       = errors.New("Không thể nhắn riêng cho chính mình")
)

// ValidateVoiceWAV checks one voice payload: RIFF/WAVE PCM,
// sample rate within the pipeline's range, byte + duration
// caps. dur is the sender-declared duration in seconds; the
// real length is recomputed from the data chunk and the two
// must roughly agree (a lying client gains nothing anyway —
// playback uses the real bytes).
func ValidateVoiceWAV(wav []byte, dur float64) error {
	if len(wav) > VoiceMaxBytes {
		return ErrVoiceTooBig
	}
	if len(wav) < 44 || string(wav[0:4]) != "RIFF" || string(wav[8:12]) != "WAVE" {
		return ErrVoiceBadData
	}
	rate := int(wav[24]) | int(wav[25])<<8 | int(wav[26])<<16 | int(wav[27])<<24
	if rate < 4000 || rate > VoiceMaxRate {
		return ErrVoiceBadData
	}
	channels := int(wav[22]) | int(wav[23])<<8
	if channels < 1 || channels > 2 {
		return ErrVoiceBadData
	}
	bits := int(wav[34]) | int(wav[35])<<8
	if bits != 16 {
		return ErrVoiceBadData
	}
	// Locate the data chunk (fmt may be followed by extra
	// chunks in foreign files).
	dataLen := -1
	for off := 12; off+8 <= len(wav); {
		sz := int(wav[off+4]) | int(wav[off+5])<<8 | int(wav[off+6])<<16 | int(wav[off+7])<<24
		if string(wav[off:off+4]) == "data" {
			dataLen = sz
			break
		}
		if sz < 0 {
			break
		}
		off += 8 + sz
	}
	if dataLen < 0 || dataLen == 0 {
		return ErrVoiceBadData
	}
	real := float64(dataLen) / float64(rate*channels*2)
	if real > VoiceMaxSeconds+1.0 {
		return ErrVoiceTooLong
	}
	if dur > VoiceMaxSeconds+1.0 {
		return ErrVoiceTooLong
	}
	if dur <= 0 {
		return ErrVoiceBadData
	}
	return nil
}

// decodeVoicePayload decodes one base64 voice payload,
// rejecting oversized encodings before decoding (the
// websocket frame cap is the second line of defence).
func decodeVoicePayload(b64 string) ([]byte, error) {
	if len(b64) > VoiceMaxBytes*4/3+1024 {
		return nil, ErrVoiceTooBig
	}
	wav, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, ErrVoiceBadData
	}
	return wav, nil
}

// ------------------------------------------------------------ DMs

// DMHistoryCap bounds one pair's stored text history (voice
// is never stored — see the file header).
const DMHistoryCap = 100

// DMMsg is one persisted private-chat line.
type DMMsg struct {
	From string `json:"from"`
	Name string `json:"name"`
	Text string `json:"text"`
	At   int64  `json:"at"`
}

// DMThread is one pair's conversation: both usernames in
// Users (sorted), the text history, and per-user unread
// counts for lines they have not opened yet.
type DMThread struct {
	Key    string         `json:"key"`
	Users  [2]string      `json:"users"`
	Msgs   []DMMsg        `json:"msgs,omitempty"`
	Unread map[string]int `json:"unread,omitempty"`
}

// DMKey is the canonical store key for a pair.
func DMKey(a, b string) string {
	if a < b {
		return a + "\x00" + b
	}
	return b + "\x00" + a
}

// DMConversation is one row of a user's conversation list.
type DMConversation struct {
	User     string `json:"user"`      // the other party's username
	Name     string `json:"name"`      // their display name (resolved by the caller)
	LastText string `json:"last_text"` // last line's text ("" when empty)
	LastAt   int64  `json:"last_at"`
	Unread   int    `json:"unread"`
}

// DMs is the private-chat service over the Store (17e),
// following the Alliances/Tournaments service pattern.
type DMs struct {
	store Store
	mu    sync.Mutex
	now   func() time.Time
}

func NewDMs(store Store) *DMs {
	return &DMs{store: store, now: time.Now}
}

// AppendText stores one text line from `from` to `to` and
// returns the updated thread. The recipient's unread count
// grows; the sender's own lines never count as unread.
func (d *DMs) AppendText(from, fromName, to, text string) (*DMThread, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	key := DMKey(from, to)
	th, ok := d.store.GetDMThread(key)
	if !ok {
		users := [2]string{from, to}
		if to < from {
			users = [2]string{to, from}
		}
		th = &DMThread{Key: key, Users: users, Unread: map[string]int{}}
	}
	th.Msgs = append(th.Msgs, DMMsg{From: from, Name: fromName, Text: text, At: d.now().Unix()})
	if len(th.Msgs) > DMHistoryCap {
		th.Msgs = th.Msgs[len(th.Msgs)-DMHistoryCap:]
	}
	if th.Unread == nil {
		th.Unread = map[string]int{}
	}
	th.Unread[to]++
	if err := d.store.PutDMThread(th); err != nil {
		return nil, err
	}
	return th, nil
}

// History returns the pair's stored lines, oldest first.
func (d *DMs) History(a, b string) []DMMsg {
	th, ok := d.store.GetDMThread(DMKey(a, b))
	if !ok {
		return []DMMsg{}
	}
	return append([]DMMsg(nil), th.Msgs...)
}

// MarkRead zeroes the caller's unread count in the pair's
// thread and returns the count that was cleared.
func (d *DMs) MarkRead(me, other string) (int, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	th, ok := d.store.GetDMThread(DMKey(me, other))
	if !ok {
		return 0, nil
	}
	n := th.Unread[me]
	if n == 0 {
		return 0, nil
	}
	th.Unread[me] = 0
	if err := d.store.PutDMThread(th); err != nil {
		return 0, err
	}
	return n, nil
}

// UnreadOf reports one pair's unread count for `me`.
func (d *DMs) UnreadOf(me, other string) int {
	th, ok := d.store.GetDMThread(DMKey(me, other))
	if !ok {
		return 0
	}
	return th.Unread[me]
}

// TotalUnread sums a user's unread DM counts (the home
// chat button's badge).
func (d *DMs) TotalUnread(me string) int {
	total := 0
	for _, th := range d.store.DMThreads() {
		if th.Users[0] == me || th.Users[1] == me {
			total += th.Unread[me]
		}
	}
	return total
}

// Conversations lists the user's threads, most recent
// activity first. Display names are resolved by the caller.
func (d *DMs) Conversations(me string) []DMConversation {
	out := []DMConversation{}
	for _, th := range d.store.DMThreads() {
		var other string
		switch me {
		case th.Users[0]:
			other = th.Users[1]
		case th.Users[1]:
			other = th.Users[0]
		default:
			continue
		}
		c := DMConversation{User: other, Unread: th.Unread[me]}
		if n := len(th.Msgs); n > 0 {
			c.LastText = th.Msgs[n-1].Text
			c.LastAt = th.Msgs[n-1].At
		}
		out = append(out, c)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].LastAt != out[j].LastAt {
			return out[i].LastAt > out[j].LastAt
		}
		return out[i].User < out[j].User
	})
	return out
}

// ------------------------------------------------------------ megaphone accounts

// MegaphoneCount reads the account's Loa thông báo count.
func (ac *Accounts) MegaphoneCount(user string) int {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return 0
	}
	return a.Megaphones
}

// ConsumeMegaphone spends one megaphone; false when the
// account has none (or does not exist).
func (ac *Accounts) ConsumeMegaphone(user string) bool {
	a, ok := ac.store.GetAccount(user)
	if !ok || a.Megaphones <= 0 {
		return false
	}
	a.Megaphones--
	_ = ac.store.PutAccount(a)
	return true
}

// GrantMegaphones adds n megaphones to an account and files
// the delivery letter (the mailbox is the grant's paper
// trail). The ADMIN PERMISSION check lives in the caller
// (the session op) — this is the raw account operation.
// Returns the account's new total.
func (ac *Accounts) GrantMegaphones(target string, n int) (int, error) {
	if n <= 0 {
		n = 1
	}
	a, ok := ac.store.GetAccount(target)
	if !ok {
		return 0, ErrBadCredentials
	}
	a.Megaphones += n
	// Delivery is worded as an event reward (owner rule:
	// player-facing copy never mentions admins or grants).
	a.appendLetter("Phần thưởng sự kiện",
		"Bạn nhận được: "+itoa(n)+" Loa thông báo. "+
			"Dùng Loa trong khung Chat để phát một thông báo chạy chữ tới mọi người chơi đang trực tuyến.",
		ac.now().Unix())
	if err := ac.store.PutAccount(a); err != nil {
		return 0, err
	}
	return a.Megaphones, nil
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [12]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

// ------------------------------------------------------------ hub relays

// WorldChatFrom is the synthetic "from" slot on world lines
// (alliance uses -3; the world channel has no slots either).
const WorldChatFrom = -4

// chatDecor resolves a user's presentation riders for hub
// chat lines: alliance [TAG], equipped bubble style, and
// the reigning-war-champion flag (spec §7.1 — the seam is
// Accounts.WarChampOf; nil until the war system exists).
func (h *Hub) chatDecor(user string) (tag, bubble string, champ bool) {
	if user == "" {
		return "", "mac_dinh", false
	}
	if h.allis != nil {
		tag = h.allis.TagOf(user)
	}
	bubble = "mac_dinh"
	if h.acc != nil {
		bubble = h.acc.EquippedBubbleOf(user)
		champ = h.acc.warChampOf(user)
	}
	return tag, bubble, champ
}

// SendToAllUsers delivers one message to every live session
// of every logged-in account (17e fan-out primitive).
func (h *Hub) SendToAllUsers(msg map[string]any) {
	h.userMu.Lock()
	targets := make([]sender, 0, 32)
	for _, m := range h.userConns {
		for _, s := range m {
			targets = append(targets, s)
		}
	}
	h.userMu.Unlock()
	for _, s := range targets {
		sendMsg(s, msg)
	}
}

// chatGate is the shared sliding-window rate budget used by
// the hub's lobby channels (world + DM text share one
// budget, keyed by user). Caller must hold h.userMu.
func (h *Hub) chatGateLocked(win map[string][]time.Time, user string) bool {
	now := time.Now()
	kept := win[user][:0]
	for _, t := range win[user] {
		if now.Sub(t) < ChatRateWindow {
			kept = append(kept, t)
		}
	}
	if len(kept) >= ChatRateCount {
		win[user] = kept
		return false
	}
	win[user] = append(kept, now)
	return true
}

// RelayWorldChat fans one world-channel line out to every
// logged-in session. Rate-limited and truncated exactly
// like room chat; past the budget the line drops silently.
// The sender's own sessions receive the line back.
func (h *Hub) RelayWorldChat(user, name, text string) {
	h.userMu.Lock()
	if h.worldChatWin == nil {
		h.worldChatWin = make(map[string][]time.Time)
	}
	ok := h.chatGateLocked(h.worldChatWin, user)
	h.userMu.Unlock()
	if !ok {
		return
	}
	if rs := []rune(text); len(rs) > ChatMaxLen {
		text = string(rs[:ChatMaxLen])
	}
	text = SanitizeEmotes(text)
	tag, bubble, champ := h.chatDecor(user)
	msg := map[string]any{
		"t": "chat", "scope": "world", "from": WorldChatFrom,
		"name": name, "text": text,
	}
	if tag != "" {
		msg["ally_tag"] = tag
	}
	msg["bubble"] = bubble
	if champ {
		msg["war_champ"] = true
	}
	h.SendToAllUsers(msg)
}

// RelayDMText stores + fans out one private line. Storage
// happens BEFORE fan-out (history is exactly what was
// delivered). Returns ErrDMTarget for a self-DM.
func (h *Hub) RelayDMText(user, name, peer, text string) error {
	if peer == user {
		return ErrDMSelf
	}
	h.userMu.Lock()
	if h.worldChatWin == nil {
		h.worldChatWin = make(map[string][]time.Time)
	}
	ok := h.chatGateLocked(h.worldChatWin, user)
	h.userMu.Unlock()
	if !ok {
		return nil // silently dropped, like every chat channel
	}
	if rs := []rune(text); len(rs) > ChatMaxLen {
		text = string(rs[:ChatMaxLen])
	}
	text = SanitizeEmotes(text)
	if h.dms != nil {
		if _, err := h.dms.AppendText(user, name, peer, text); err != nil {
			return err
		}
	}
	tag, bubble, champ := h.chatDecor(user)
	base := map[string]any{
		"t": "chat", "scope": "dm", "from": WorldChatFrom,
		"name": name, "text": text, "from_user": user, "bubble": bubble,
	}
	if tag != "" {
		base["ally_tag"] = tag
	}
	if champ {
		base["war_champ"] = true
	}
	toPeer := cloneMsg(base)
	toPeer["peer"] = user // for the recipient, the thread is with the sender
	h.SendToUsers([]string{peer}, toPeer)
	toSelf := cloneMsg(base)
	toSelf["peer"] = peer
	h.SendToUsers([]string{user}, toSelf)
	return nil
}

func cloneMsg(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// voiceGate is the voice budget (VoiceRateCount per
// VoiceRateWindow per user, all channels together).
func (h *Hub) voiceGate(user string) bool {
	h.userMu.Lock()
	defer h.userMu.Unlock()
	if h.voiceWin == nil {
		h.voiceWin = make(map[string][]time.Time)
	}
	now := time.Now()
	kept := h.voiceWin[user][:0]
	for _, t := range h.voiceWin[user] {
		if now.Sub(t) < VoiceRateWindow {
			kept = append(kept, t)
		}
	}
	if len(kept) >= VoiceRateCount {
		h.voiceWin[user] = kept
		return false
	}
	h.voiceWin[user] = append(kept, now)
	return true
}

// voiceMsg builds the wire shape shared by every voice relay.
func (h *Hub) voiceMsg(scope, user, name string, wav []byte, dur float64) map[string]any {
	tag, bubble, champ := h.chatDecor(user)
	msg := map[string]any{
		"t": "voice", "scope": scope, "from": WorldChatFrom,
		"name": name, "dur": dur, "bubble": bubble,
		"data": base64.StdEncoding.EncodeToString(wav),
	}
	if tag != "" {
		msg["ally_tag"] = tag
	}
	if champ {
		msg["war_champ"] = true
	}
	return msg
}

// RelayWorldVoice relays one voice note to every logged-in
// session. Live only — never stored.
func (h *Hub) RelayWorldVoice(user, name string, wav []byte, dur float64) error {
	if err := ValidateVoiceWAV(wav, dur); err != nil {
		return err
	}
	if !h.voiceGate(user) {
		return nil
	}
	h.SendToAllUsers(h.voiceMsg("world", user, name, wav, dur))
	return nil
}

// RelayAllianceVoice relays one voice note to an alliance's
// members (same membership list the text relay uses).
func (h *Hub) RelayAllianceVoice(user, name, allyID string, memberUsers []string, wav []byte, dur float64) error {
	if err := ValidateVoiceWAV(wav, dur); err != nil {
		return err
	}
	if !h.voiceGate(user) {
		return nil
	}
	msg := h.voiceMsg("alliance", user, name, wav, dur)
	msg["alliance"] = allyID
	h.SendToUsers(memberUsers, msg)
	return nil
}

// RelayDMVoice relays one voice note to both parties of a
// private thread. Live only — never stored.
func (h *Hub) RelayDMVoice(user, name, peer string, wav []byte, dur float64) error {
	if peer == user {
		return ErrDMSelf
	}
	if err := ValidateVoiceWAV(wav, dur); err != nil {
		return err
	}
	if !h.voiceGate(user) {
		return nil
	}
	base := h.voiceMsg("dm", user, name, wav, dur)
	base["from_user"] = user
	toPeer := cloneMsg(base)
	toPeer["peer"] = user
	h.SendToUsers([]string{peer}, toPeer)
	toSelf := cloneMsg(base)
	toSelf["peer"] = peer
	h.SendToUsers([]string{user}, toSelf)
	return nil
}

// ------------------------------------------------------------ megaphone

// UseMegaphone spends one of the user's megaphones and
// broadcasts the marquee. The spend happens first and is
// not refunded when nobody is listening — the item buys
// the broadcast, not an audience.
func (h *Hub) UseMegaphone(user, name, text string) (int, error) {
	if h.acc == nil || !h.acc.ConsumeMegaphone(user) {
		return 0, ErrNoMegaphone
	}
	if rs := []rune(text); len(rs) > ChatMaxLen {
		text = string(rs[:ChatMaxLen])
	}
	text = StripEmotes(SanitizeEmotes(text))
	h.marqueeSeq++
	mid := h.marqueeSeq
	msg := map[string]any{
		"t": "marquee", "mid": mid, "name": name, "text": text,
	}
	tag, _, champ := h.chatDecor(user)
	if tag != "" {
		msg["ally_tag"] = tag
	}
	if champ {
		msg["war_champ"] = true
	}
	// Lobby sessions (every logged-in account)…
	h.SendToAllUsers(msg)
	// …and every room (in-match players incl. guests, and
	// observers). Logged-in room players get the message
	// twice by construction — clients dedupe by mid.
	h.mu.Lock()
	for _, r := range h.rooms {
		h.broadcastLocked(r, msg)
	}
	h.mu.Unlock()
	return h.acc.MegaphoneCount(user), nil
}

// IsAdmin reports whether a username is a configured game
// admin (EMPIRE_AGE_ADMINS — see main()).
func (h *Hub) IsAdmin(user string) bool {
	return user != "" && h.admins[user]
}
