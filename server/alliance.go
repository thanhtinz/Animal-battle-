package main

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

// Alliances (17a) — the guild system the lobby's Liên minh tab
// and the profile's Liên minh row open. State lives behind the
// Store interface like tournaments (file-JSON, atomic writes).
//
// OWNER-APPROVED SHAPE (mock B, 2026-11-12); the numbers below
// are Bé's defaults pending the owner's confirmation (flagged
// in KE-HOACH-MVP.md §17a):
//
//   - member cap 30; creation FREE; accounts only (guests can
//     neither create, join nor apply — lobby gates it too);
//   - alliance name unique case-insensitively, 3–24 characters;
//   - badge = one shield colour from a fixed set, no uploads;
//   - roles: Hội trưởng (exactly 1) · Phó (max 3) · Thành viên.
//     Deputy: approve/reject requests, invite, kick members.
//     Leader adds: settings (badge / join mode / description),
//     promote/demote, transfer leadership, disband;
//   - join modes: "open" (vào ngay) or "request" (xin vào →
//     duyệt). A player belongs to AT MOST ONE alliance; joining
//     one withdraws their requests/invites everywhere else;
//   - XP: every BANKED match result also accrues its match XP
//     (10, +20 on a win — see Accounts.MatchHook) as the
//     member's weekly contribution AND the alliance's XP.
//     Weekly contribution resets Monday 00:00 server-local
//     (lazy: each member row carries its week key);
//   - the leaderboard's Liên minh tab ranks alliances by weekly
//     points (sum of member contributions), tie → total XP →
//     name;
//   - alliance chat is lobby traffic routed by the hub to the
//     members' live sessions — NEVER part of any match sim;
//   - the activity log is the audit trail (created / joined /
//     left / kicked / promoted / approved / …), capped like
//     the tournament log.

const (
	AllianceCap         = 30
	AllianceMaxDeputies = 3
	AllianceNameMin     = 3
	AllianceNameMax     = 24
	AllianceDescMax     = 120
	AllianceReqMsgMax   = 80
	AllianceLogCap      = 60

	AllianceModeOpen    = "open"
	AllianceModeRequest = "request"

	AllianceRoleLeader = "leader"
	AllianceRoleDeputy = "deputy"
	AllianceRoleMember = "member"

	// allianceLevelBase: reaching level L costs a cumulative
	// 250·L·(L−1) alliance XP (L2 = 500, L3 = 1500, L4 = 3000,
	// L5 = 5000 …); each new level costs 500·L more than the
	// last. Simple on purpose — one formula, documented here.
	allianceLevelBase = 250
)

// AllianceBadges is the fixed shield-colour set (ids); the
// client maps each id to the mock's fill colour.
var AllianceBadges = []string{"red", "blue", "teal", "green", "gold", "purple"}

func validAllianceBadge(b string) bool {
	for _, x := range AllianceBadges {
		if x == b {
			return true
		}
	}
	return false
}

var (
	ErrAllyLogin       = errors.New("Đăng nhập để dùng Liên minh")
	ErrAllyBadName     = errors.New("Tên liên minh phải có 3–24 ký tự (chữ, số, khoảng trắng, _)")
	ErrAllyNameTaken   = errors.New("Tên liên minh đã có người dùng")
	ErrAllyBadBadge    = errors.New("Màu khiên không hợp lệ")
	ErrAllyBadMode     = errors.New("Chế độ tuyển thành viên không hợp lệ")
	ErrAllyNotFound    = errors.New("Không tìm thấy liên minh")
	ErrAllyAlreadyIn   = errors.New("Bạn đã thuộc một liên minh rồi")
	ErrAllyTargetIn    = errors.New("Người chơi đã thuộc một liên minh khác")
	ErrAllyFull        = errors.New("Liên minh đã đầy (30/30 thành viên)")
	ErrAllyNotMember   = errors.New("Bạn chưa thuộc liên minh này")
	ErrAllyNoRequest   = errors.New("Không có đơn xin vào nào")
	ErrAllyNoInvite    = errors.New("Không có lời mời nào")
	ErrAllyNoPerm      = errors.New("Bạn không có quyền thực hiện thao tác này")
	ErrAllyDeputyCap   = errors.New("Đã đủ 3 Phó — hạ bớt một Phó trước")
	ErrAllyLeaderLeave = errors.New("Hội trưởng phải chuyển quyền hoặc giải tán liên minh trước khi rời")
	ErrAllyNoTarget    = errors.New("Không tìm thấy người chơi này")
	ErrAllySelf        = errors.New("Không thể thao tác lên chính mình")
)

// AllianceMember is one member row: role, join time and the
// weekly contribution (WeekKey = the Monday of the week the
// points belong to, "2006-01-02" server-local; a stale key
// reads as 0 — the lazy weekly reset).
type AllianceMember struct {
	User     string `json:"user"`
	Role     string `json:"role"`
	JoinedAt int64  `json:"joined_at"`
	WeekKey  string `json:"week_key,omitempty"`
	WeekPts  int    `json:"week_pts"`
}

// AllianceRequest is one pending join application.
type AllianceRequest struct {
	User string `json:"user"`
	Msg  string `json:"msg,omitempty"`
	At   int64  `json:"at"`
}

// AllianceInvite is one pending invitation (invitee username).
type AllianceInvite struct {
	User string `json:"user"`
	By   string `json:"by"`
	At   int64  `json:"at"`
}

// AllianceEvent is one activity-log line.
type AllianceEvent struct {
	At   int64  `json:"at"`
	Text string `json:"text"`
}

// Alliance is the whole guild state.
type Alliance struct {
	ID        string            `json:"id"`
	Name      string            `json:"name"`
	Badge     string            `json:"badge"`
	Mode      string            `json:"mode"`
	Desc      string            `json:"desc,omitempty"`
	Leader    string            `json:"leader"`
	XP        int               `json:"xp"`
	CreatedAt int64             `json:"created_at"`
	Members   []AllianceMember  `json:"members"`
	Requests  []AllianceRequest `json:"requests,omitempty"`
	Invites   []AllianceInvite  `json:"invites,omitempty"`
	Log       []AllianceEvent   `json:"log,omitempty"`
}

func copyAlliance(a *Alliance) *Alliance {
	if a == nil {
		return nil
	}
	c := *a
	c.Members = append([]AllianceMember(nil), a.Members...)
	c.Requests = append([]AllianceRequest(nil), a.Requests...)
	c.Invites = append([]AllianceInvite(nil), a.Invites...)
	c.Log = append([]AllianceEvent(nil), a.Log...)
	return &c
}

func newAllianceID(store Store) string {
	for {
		b := make([]byte, 6)
		for i := range b {
			n, err := rand.Int(rand.Reader, big.NewInt(int64(len(codeAlphabet))))
			if err != nil {
				b[i] = codeAlphabet[i%len(codeAlphabet)]
			} else {
				b[i] = codeAlphabet[n.Int64()]
			}
		}
		id := "A" + string(b)
		if _, ok := store.GetAlliance(id); !ok {
			return id
		}
	}
}

// allianceCumXP is the cumulative alliance XP at which a
// level begins.
func allianceCumXP(level int) int {
	if level < 1 {
		level = 1
	}
	return allianceLevelBase * level * (level - 1)
}

// AllianceLevelForXP splits cumulative alliance XP into
// (level, XP into the level, XP the level spans).
func AllianceLevelForXP(xp int) (level, into, forNext int) {
	level = 1
	for xp >= allianceCumXP(level+1) {
		level++
	}
	into = xp - allianceCumXP(level)
	forNext = allianceCumXP(level+1) - allianceCumXP(level)
	return level, into, forNext
}

// weekKeyOf returns the Monday (00:00 server-local) of t's
// week formatted "2006-01-02" — the weekly-reset key.
func weekKeyOf(t time.Time) string {
	d := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
	offset := (int(d.Weekday()) + 6) % 7 // Monday = 0
	return d.AddDate(0, 0, -offset).Format("2006-01-02")
}

// Alliances is the alliance service: store + accounts lookups.
type Alliances struct {
	mu    sync.Mutex
	store Store
	acc   *Accounts
	now   func() time.Time // test seam
}

func NewAlliances(store Store, acc *Accounts) *Alliances {
	return &Alliances{store: store, acc: acc, now: time.Now}
}

// ---- internal helpers (as.mu held by callers) -----------

func (as *Alliances) all() []*Alliance { return as.store.Alliances() }

func (as *Alliances) get(id string) (*Alliance, bool) {
	return as.store.GetAlliance(id)
}

func (as *Alliances) save(a *Alliance) {
	_ = as.store.PutAlliance(a) // file store: flush error has nowhere better to go
}

func memberOf(a *Alliance, user string) *AllianceMember {
	for i := range a.Members {
		if a.Members[i].User == user {
			return &a.Members[i]
		}
	}
	return nil
}

func (as *Alliances) ofUser(user string) *Alliance {
	if user == "" {
		return nil
	}
	for _, a := range as.all() {
		if memberOf(a, user) != nil {
			return a
		}
	}
	return nil
}

// touchWeek applies the lazy weekly reset to a's member rows
// (in memory; persisted on the next save of that alliance).
func (as *Alliances) touchWeek(a *Alliance) {
	key := weekKeyOf(as.now())
	for i := range a.Members {
		if a.Members[i].WeekKey != key {
			a.Members[i].WeekKey = key
			a.Members[i].WeekPts = 0
		}
	}
}

// weekPoints is a's total contribution in the current week.
func (as *Alliances) weekPoints(a *Alliance) int {
	key := weekKeyOf(as.now())
	sum := 0
	for _, m := range a.Members {
		if m.WeekKey == key {
			sum += m.WeekPts
		}
	}
	return sum
}

func (as *Alliances) logf(a *Alliance, format string, args ...any) {
	a.Log = append(a.Log, AllianceEvent{At: as.now().Unix(), Text: fmt.Sprintf(format, args...)})
	if len(a.Log) > AllianceLogCap {
		a.Log = a.Log[len(a.Log)-AllianceLogCap:]
	}
}

func (as *Alliances) nameOf(user string) string { return as.acc.DisplayNameOf(user) }

// ranked returns every alliance in leaderboard order: weekly
// points desc, total XP desc, name asc. The returned copies
// have the lazy week reset applied (not persisted).
func (as *Alliances) ranked() []*Alliance {
	out := as.all()
	for _, a := range out {
		as.touchWeek(a)
	}
	sort.Slice(out, func(i, j int) bool {
		wi, wj := as.weekPoints(out[i]), as.weekPoints(out[j])
		if wi != wj {
			return wi > wj
		}
		if out[i].XP != out[j].XP {
			return out[i].XP > out[j].XP
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out
}

func (as *Alliances) rankOf(id string) int {
	for i, a := range as.ranked() {
		if a.ID == id {
			return i + 1
		}
	}
	return 0
}

// cleanupUserRefs withdraws user's pending requests and
// invites from every alliance except keepID — called whenever
// the user joins one, so no stale paperwork survives.
func (as *Alliances) cleanupUserRefs(user, keepID string) {
	for _, a := range as.all() {
		if a.ID == keepID {
			continue
		}
		changed := false
		reqs := a.Requests[:0]
		for _, r := range a.Requests {
			if r.User == user {
				changed = true
				continue
			}
			reqs = append(reqs, r)
		}
		a.Requests = reqs
		invs := a.Invites[:0]
		for _, iv := range a.Invites {
			if iv.User == user {
				changed = true
				continue
			}
			invs = append(invs, iv)
		}
		a.Invites = invs
		if changed {
			as.save(a)
		}
	}
}

// joinLocked adds user to a as a plain member (cap + one-
// alliance rules enforced by callers where noted) and logs it.
func (as *Alliances) joinLocked(a *Alliance, user string) error {
	if len(a.Members) >= AllianceCap {
		return ErrAllyFull
	}
	a.Members = append(a.Members, AllianceMember{
		User: user, Role: AllianceRoleMember,
		JoinedAt: as.now().Unix(), WeekKey: weekKeyOf(as.now()),
	})
	// Their own paperwork in THIS alliance is settled by joining.
	reqs := a.Requests[:0]
	for _, r := range a.Requests {
		if r.User != user {
			reqs = append(reqs, r)
		}
	}
	a.Requests = reqs
	invs := a.Invites[:0]
	for _, iv := range a.Invites {
		if iv.User != user {
			invs = append(invs, iv)
		}
	}
	a.Invites = invs
	as.logf(a, "%s đã gia nhập liên minh", as.nameOf(user))
	as.save(a)
	as.cleanupUserRefs(user, a.ID)
	return nil
}

func validAllianceName(name string) bool {
	n := utf8.RuneCountInString(name)
	if n < AllianceNameMin || n > AllianceNameMax {
		return false
	}
	for _, r := range name {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' || r == '_' {
			continue
		}
		return false
	}
	return true
}

// ---- operations ------------------------------------------

// Create founds a new alliance with creator as its leader.
func (as *Alliances) Create(creator, name, badge, mode, desc string) (*Alliance, error) {
	as.mu.Lock()
	defer as.mu.Unlock()
	name = strings.TrimSpace(name)
	if creator == "" {
		return nil, ErrAllyNotMember
	}
	if !validAllianceName(name) {
		return nil, ErrAllyBadName
	}
	if !validAllianceBadge(badge) {
		return nil, ErrAllyBadBadge
	}
	if mode != AllianceModeOpen && mode != AllianceModeRequest {
		return nil, ErrAllyBadMode
	}
	if as.ofUser(creator) != nil {
		return nil, ErrAllyAlreadyIn
	}
	for _, a := range as.all() {
		if strings.EqualFold(a.Name, name) {
			return nil, ErrAllyNameTaken
		}
	}
	if rs := []rune(strings.TrimSpace(desc)); len(rs) > AllianceDescMax {
		desc = string(rs[:AllianceDescMax])
	} else {
		desc = string(rs)
	}
	a := &Alliance{
		ID: newAllianceID(as.store), Name: name, Badge: badge,
		Mode: mode, Desc: desc, Leader: creator,
		CreatedAt: as.now().Unix(),
		Members: []AllianceMember{{
			User: creator, Role: AllianceRoleLeader,
			JoinedAt: as.now().Unix(), WeekKey: weekKeyOf(as.now()),
		}},
	}
	as.logf(a, "%s đã lập liên minh", as.nameOf(creator))
	as.save(a)
	as.cleanupUserRefs(creator, a.ID)
	return a, nil
}

// OfUser returns the alliance user belongs to (copy), or nil.
func (as *Alliances) OfUser(user string) *Alliance {
	as.mu.Lock()
	defer as.mu.Unlock()
	return as.ofUser(user)
}

// Apply files a join request — or joins immediately when the
// alliance's mode is "open".
func (as *Alliances) Apply(id, user, msg string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	if user == "" {
		return ErrAllyNotMember
	}
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	if as.ofUser(user) != nil {
		return ErrAllyAlreadyIn
	}
	as.touchWeek(a)
	if a.Mode == AllianceModeOpen {
		return as.joinLocked(a, user)
	}
	for _, r := range a.Requests {
		if r.User == user {
			return nil // already filed — idempotent
		}
	}
	if rs := []rune(strings.TrimSpace(msg)); len(rs) > AllianceReqMsgMax {
		msg = string(rs[:AllianceReqMsgMax])
	} else {
		msg = string(rs)
	}
	a.Requests = append(a.Requests, AllianceRequest{User: user, Msg: msg, At: as.now().Unix()})
	as.logf(a, "%s đã xin gia nhập liên minh", as.nameOf(user))
	as.save(a)
	return nil
}

// CancelRequest withdraws the user's own pending application.
func (as *Alliances) CancelRequest(id, user string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	found := false
	reqs := a.Requests[:0]
	for _, r := range a.Requests {
		if r.User == user {
			found = true
			continue
		}
		reqs = append(reqs, r)
	}
	if !found {
		return ErrAllyNoRequest
	}
	a.Requests = reqs
	as.save(a)
	return nil
}

func (as *Alliances) canModerate(a *Alliance, actor string) bool {
	m := memberOf(a, actor)
	return m != nil && (m.Role == AllianceRoleLeader || m.Role == AllianceRoleDeputy)
}

// Approve accepts a pending request (leader/deputy).
func (as *Alliances) Approve(id, actor, target string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	if !as.canModerate(a, actor) {
		return ErrAllyNoPerm
	}
	idx := -1
	for i, r := range a.Requests {
		if r.User == target {
			idx = i
			break
		}
	}
	if idx < 0 {
		return ErrAllyNoRequest
	}
	if as.ofUser(target) != nil {
		// They joined elsewhere meanwhile — drop the stale paper.
		a.Requests = append(a.Requests[:idx], a.Requests[idx+1:]...)
		as.save(a)
		return ErrAllyTargetIn
	}
	a.Requests = append(a.Requests[:idx], a.Requests[idx+1:]...)
	as.touchWeek(a)
	if err := as.joinLocked(a, target); err != nil {
		return err
	}
	as.logf(a, "%s đã duyệt đơn của %s", as.nameOf(actor), as.nameOf(target))
	as.save(a)
	return nil
}

// Reject declines a pending request (leader/deputy).
func (as *Alliances) Reject(id, actor, target string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	if !as.canModerate(a, actor) {
		return ErrAllyNoPerm
	}
	idx := -1
	for i, r := range a.Requests {
		if r.User == target {
			idx = i
			break
		}
	}
	if idx < 0 {
		return ErrAllyNoRequest
	}
	a.Requests = append(a.Requests[:idx], a.Requests[idx+1:]...)
	as.logf(a, "%s đã từ chối đơn của %s", as.nameOf(actor), as.nameOf(target))
	as.save(a)
	return nil
}

// resolvePlayer finds an account by username or display name
// (both case-insensitive; username wins on a clash).
func (as *Alliances) resolvePlayer(name string) (string, bool) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", false
	}
	accs := as.acc.store.Accounts()
	for _, a := range accs {
		if strings.EqualFold(a.User, name) {
			return a.User, true
		}
	}
	for _, a := range accs {
		if strings.EqualFold(EffectiveDisplayName(a), name) {
			return a.User, true
		}
	}
	return "", false
}

// Invite invites a player by name (leader/deputy). The
// invitee accepts/declines on their own alliance screen.
func (as *Alliances) Invite(id, actor, targetName string) (string, error) {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return "", ErrAllyNotFound
	}
	if !as.canModerate(a, actor) {
		return "", ErrAllyNoPerm
	}
	target, found := as.resolvePlayer(targetName)
	if !found {
		return "", ErrAllyNoTarget
	}
	if target == actor {
		return "", ErrAllySelf
	}
	if memberOf(a, target) != nil {
		return "", ErrAllyAlreadyIn
	}
	if as.ofUser(target) != nil {
		return "", ErrAllyTargetIn
	}
	for _, iv := range a.Invites {
		if iv.User == target {
			return target, nil // already invited — idempotent
		}
	}
	for _, r := range a.Requests {
		if r.User == target {
			return "", errors.New("Người chơi đã gửi đơn — hãy duyệt ở tab Yêu cầu")
		}
	}
	a.Invites = append(a.Invites, AllianceInvite{User: target, By: actor, At: as.now().Unix()})
	as.logf(a, "%s đã mời %s vào liên minh", as.nameOf(actor), as.nameOf(target))
	as.save(a)
	return target, nil
}

// AcceptInvite joins the alliance that invited the user.
func (as *Alliances) AcceptInvite(user, id string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	found := false
	for _, iv := range a.Invites {
		if iv.User == user {
			found = true
		}
	}
	if !found {
		return ErrAllyNoInvite
	}
	if as.ofUser(user) != nil {
		return ErrAllyAlreadyIn
	}
	as.touchWeek(a)
	return as.joinLocked(a, user)
}

// DeclineInvite drops the user's invitation from one alliance.
func (as *Alliances) DeclineInvite(user, id string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	found := false
	invs := a.Invites[:0]
	for _, iv := range a.Invites {
		if iv.User == user {
			found = true
			continue
		}
		invs = append(invs, iv)
	}
	if !found {
		return ErrAllyNoInvite
	}
	a.Invites = invs
	as.save(a)
	return nil
}

// InvitesFor lists the alliances holding a pending invite for
// user (copies, oldest first).
func (as *Alliances) InvitesFor(user string) []*Alliance {
	as.mu.Lock()
	defer as.mu.Unlock()
	out := []*Alliance{}
	for _, a := range as.all() {
		for _, iv := range a.Invites {
			if iv.User == user {
				out = append(out, a)
				break
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt < out[j].CreatedAt })
	return out
}

// Leave removes a member. The leader must transfer first —
// unless they are the LAST member, in which case leaving
// dissolves the now-empty alliance.
func (as *Alliances) Leave(id, user string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	m := memberOf(a, user)
	if m == nil {
		return ErrAllyNotMember
	}
	if m.Role == AllianceRoleLeader {
		if len(a.Members) > 1 {
			return ErrAllyLeaderLeave
		}
		return as.store.DeleteAlliance(id)
	}
	members := a.Members[:0]
	for _, mm := range a.Members {
		if mm.User != user {
			members = append(members, mm)
		}
	}
	a.Members = members
	as.logf(a, "%s đã rời liên minh", as.nameOf(user))
	as.save(a)
	return nil
}

// Kick removes target from the alliance. Leader kicks anyone
// below them; a deputy kicks plain members only.
func (as *Alliances) Kick(id, actor, target string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	am := memberOf(a, actor)
	tm := memberOf(a, target)
	if am == nil || tm == nil {
		return ErrAllyNotMember
	}
	if actor == target {
		return ErrAllySelf
	}
	switch {
	case am.Role == AllianceRoleLeader:
		// any non-leader target is fine (target can't be leader:
		// only one leader exists and it is the actor here)
	case am.Role == AllianceRoleDeputy && tm.Role == AllianceRoleMember:
		// ok
	default:
		return ErrAllyNoPerm
	}
	members := a.Members[:0]
	for _, mm := range a.Members {
		if mm.User != target {
			members = append(members, mm)
		}
	}
	a.Members = members
	as.logf(a, "%s đã mời %s ra khỏi liên minh", as.nameOf(actor), as.nameOf(target))
	as.save(a)
	return nil
}

// SetRole promotes a member to deputy or demotes a deputy
// (leader only; deputy cap 3).
func (as *Alliances) SetRole(id, actor, target, role string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	am := memberOf(a, actor)
	if am == nil || am.Role != AllianceRoleLeader {
		return ErrAllyNoPerm
	}
	tm := memberOf(a, target)
	if tm == nil {
		return ErrAllyNotMember
	}
	if actor == target {
		return ErrAllySelf
	}
	if role != AllianceRoleDeputy && role != AllianceRoleMember {
		return ErrAllyNoPerm
	}
	if tm.Role == role {
		return nil // already there — idempotent
	}
	if role == AllianceRoleDeputy {
		n := 0
		for _, m := range a.Members {
			if m.Role == AllianceRoleDeputy {
				n++
			}
		}
		if n >= AllianceMaxDeputies {
			return ErrAllyDeputyCap
		}
	}
	tm.Role = role
	if role == AllianceRoleDeputy {
		as.logf(a, "%s đã phong %s làm Phó", as.nameOf(actor), as.nameOf(target))
	} else {
		as.logf(a, "%s đã hạ %s xuống Thành viên", as.nameOf(actor), as.nameOf(target))
	}
	as.save(a)
	return nil
}

// Transfer hands leadership to another member (leader only).
// The old leader steps down to a plain member.
func (as *Alliances) Transfer(id, actor, target string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	am := memberOf(a, actor)
	if am == nil || am.Role != AllianceRoleLeader {
		return ErrAllyNoPerm
	}
	tm := memberOf(a, target)
	if tm == nil {
		return ErrAllyNotMember
	}
	if actor == target {
		return ErrAllySelf
	}
	am.Role = AllianceRoleMember
	tm.Role = AllianceRoleLeader
	a.Leader = target
	as.logf(a, "%s đã chuyển quyền Hội trưởng cho %s", as.nameOf(actor), as.nameOf(target))
	as.save(a)
	return nil
}

// UpdateSettings edits badge / join mode / description
// (leader only).
func (as *Alliances) UpdateSettings(id, actor, badge, mode, desc string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	am := memberOf(a, actor)
	if am == nil || am.Role != AllianceRoleLeader {
		return ErrAllyNoPerm
	}
	if !validAllianceBadge(badge) {
		return ErrAllyBadBadge
	}
	if mode != AllianceModeOpen && mode != AllianceModeRequest {
		return ErrAllyBadMode
	}
	if rs := []rune(strings.TrimSpace(desc)); len(rs) > AllianceDescMax {
		desc = string(rs[:AllianceDescMax])
	} else {
		desc = string(rs)
	}
	a.Badge, a.Mode, a.Desc = badge, mode, desc
	as.logf(a, "%s đã cập nhật cài đặt liên minh", as.nameOf(actor))
	as.save(a)
	return nil
}

// Disband deletes the alliance outright (leader only); every
// member simply becomes unaffiliated.
func (as *Alliances) Disband(id, actor string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	am := memberOf(a, actor)
	if am == nil || am.Role != AllianceRoleLeader {
		return ErrAllyNoPerm
	}
	return as.store.DeleteAlliance(id)
}

// Accrue is the Accounts.MatchHook target: one banked match's
// XP delta lands as the member's weekly contribution and the
// alliance's XP. Non-members and zero deltas are no-ops;
// totals never go negative (a dispute revert un-accrues).
func (as *Alliances) Accrue(user string, delta int) {
	if user == "" || delta == 0 {
		return
	}
	as.mu.Lock()
	defer as.mu.Unlock()
	a := as.ofUser(user)
	if a == nil {
		return
	}
	as.touchWeek(a)
	m := memberOf(a, user)
	if m == nil {
		return
	}
	m.WeekPts += delta
	if m.WeekPts < 0 {
		m.WeekPts = 0
	}
	a.XP += delta
	if a.XP < 0 {
		a.XP = 0
	}
	as.save(a)
}

// MemberUsers returns the member username list (chat fan-out).
func (as *Alliances) MemberUsers(id string) []string {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(a.Members))
	for _, m := range a.Members {
		out = append(out, m.User)
	}
	return out
}

// ---- wire payloads ----------------------------------------

// memberWire is one member row for the client.
func (as *Alliances) memberWire(m AllianceMember, online func(string) bool) map[string]any {
	name, avatar, level, seen := m.User, "knight", 1, int64(0)
	if acc, ok := as.acc.store.GetAccount(m.User); ok {
		name = EffectiveDisplayName(acc)
		avatar = EffectiveAvatar(acc)
		lvl, _, _ := LevelForXP(XPFor(acc.Matches, acc.Wins))
		level = lvl
		seen = acc.LastOnline
	}
	on := false
	if online != nil {
		on = online(m.User)
	}
	return map[string]any{
		"user": m.User, "name": name, "avatar": avatar, "level": level,
		"role": m.Role, "week": m.WeekPts, "online": on, "seen": seen,
		"joined_at": m.JoinedAt,
	}
}

// View builds the joined-state payload for one alliance as
// seen by viewer (requests included only for leader/deputy).
func (as *Alliances) View(a *Alliance, viewer string, online func(string) bool) map[string]any {
	as.touchWeek(a)
	level, into, forNext := AllianceLevelForXP(a.XP)
	me := memberOf(a, viewer)
	myRole := ""
	if me != nil {
		myRole = me.Role
	}
	// Members: leader first, then deputies, then by weekly
	// contribution desc, then join order.
	members := append([]AllianceMember(nil), a.Members...)
	roleRank := map[string]int{AllianceRoleLeader: 0, AllianceRoleDeputy: 1, AllianceRoleMember: 2}
	sort.SliceStable(members, func(i, j int) bool {
		if roleRank[members[i].Role] != roleRank[members[j].Role] {
			return roleRank[members[i].Role] < roleRank[members[j].Role]
		}
		if members[i].WeekPts != members[j].WeekPts {
			return members[i].WeekPts > members[j].WeekPts
		}
		return members[i].JoinedAt < members[j].JoinedAt
	})
	mrows := make([]map[string]any, 0, len(members))
	for _, m := range members {
		mrows = append(mrows, as.memberWire(m, online))
	}
	out := map[string]any{
		"id": a.ID, "name": a.Name, "badge": a.Badge, "mode": a.Mode,
		"desc": a.Desc, "level": level, "xp": a.XP, "xp_into": into,
		"xp_next": forNext, "week": as.weekPoints(a),
		"rank": as.rankOf(a.ID), "members_count": len(a.Members),
		"cap": AllianceCap, "created_at": a.CreatedAt,
		"leader": a.Leader, "leader_name": as.nameOf(a.Leader),
		"my_role": myRole, "members": mrows,
	}
	if me != nil && (me.Role == AllianceRoleLeader || me.Role == AllianceRoleDeputy) {
		reqs := make([]map[string]any, 0, len(a.Requests))
		for _, r := range a.Requests {
			name, avatar, lvl := r.User, "knight", 1
			if acc, ok := as.acc.store.GetAccount(r.User); ok {
				name = EffectiveDisplayName(acc)
				avatar = EffectiveAvatar(acc)
				l, _, _ := LevelForXP(XPFor(acc.Matches, acc.Wins))
				lvl = l
			}
			reqs = append(reqs, map[string]any{
				"user": r.User, "name": name, "avatar": avatar,
				"level": lvl, "msg": r.Msg, "at": r.At,
			})
		}
		out["requests"] = reqs
		out["requests_count"] = len(a.Requests)
	} else {
		out["requests_count"] = 0
	}
	log := make([]map[string]any, 0, len(a.Log))
	for i := len(a.Log) - 1; i >= 0; i-- {
		log = append(log, map[string]any{"at": a.Log[i].At, "text": a.Log[i].Text})
	}
	out["log"] = log
	return out
}

// HomeFor builds the alliance_home payload pieces for a user:
// their alliance view (nil when unaffiliated) and the summary
// rows of alliances holding an invite for them.
func (as *Alliances) HomeFor(user string, online func(string) bool) (map[string]any, []map[string]any) {
	as.mu.Lock()
	defer as.mu.Unlock()
	var mine map[string]any
	if a := as.ofUser(user); a != nil {
		mine = as.View(a, user, online)
	}
	invites := []map[string]any{}
	for _, a := range as.all() {
		for _, iv := range a.Invites {
			if iv.User == user {
				level, _, _ := AllianceLevelForXP(a.XP)
				invites = append(invites, map[string]any{
					"id": a.ID, "name": a.Name, "badge": a.Badge,
					"level": level, "members": len(a.Members),
					"by_name": as.nameOf(iv.By), "at": iv.At,
				})
			}
		}
	}
	return mine, invites
}

// ListWire builds the not-joined browser rows: every alliance
// (optionally name-filtered), best first (level, then member
// count, then name), each tagged with the viewer's state.
func (as *Alliances) ListWire(user, search string) []map[string]any {
	as.mu.Lock()
	defer as.mu.Unlock()
	search = strings.ToLower(strings.TrimSpace(search))
	out := []*Alliance{}
	for _, a := range as.all() {
		if search != "" && !strings.Contains(strings.ToLower(a.Name), search) {
			continue
		}
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool {
		li, _, _ := AllianceLevelForXP(out[i].XP)
		lj, _, _ := AllianceLevelForXP(out[j].XP)
		if li != lj {
			return li > lj
		}
		if len(out[i].Members) != len(out[j].Members) {
			return len(out[i].Members) > len(out[j].Members)
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	rows := make([]map[string]any, 0, len(out))
	for _, a := range out {
		level, _, _ := AllianceLevelForXP(a.XP)
		requested := false
		for _, r := range a.Requests {
			if r.User == user {
				requested = true
			}
		}
		rows = append(rows, map[string]any{
			"id": a.ID, "name": a.Name, "badge": a.Badge, "mode": a.Mode,
			"level": level, "members": len(a.Members), "cap": AllianceCap,
			"leader_name": as.nameOf(a.Leader), "requested": requested,
			"full": len(a.Members) >= AllianceCap,
		})
	}
	return rows
}

// RankingWire builds the leaderboard's Liên minh tab: ranked
// rows plus the viewer's own alliance row (with its position)
// when they have one.
func (as *Alliances) RankingWire(user string) ([]map[string]any, map[string]any) {
	as.mu.Lock()
	defer as.mu.Unlock()
	ranked := as.ranked()
	rows := make([]map[string]any, 0, len(ranked))
	var me map[string]any
	for i, a := range ranked {
		level, _, _ := AllianceLevelForXP(a.XP)
		row := map[string]any{
			"alliance": true, "id": a.ID, "name": a.Name, "badge": a.Badge,
			"level": level, "members": len(a.Members), "cap": AllianceCap,
			"week": as.weekPoints(a), "xp": a.XP,
			"leader_name": as.nameOf(a.Leader), "pos": i + 1,
		}
		rows = append(rows, row)
		if memberOf(a, user) != nil {
			me = row
		}
	}
	return rows, me
}
