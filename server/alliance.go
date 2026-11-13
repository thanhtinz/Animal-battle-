package main

import (
	"crypto/rand"
	"encoding/json"
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

	// 17b additions (Bé's defaults, flagged in KE-HOACH §17b):
	// the notice board is a single short line, chat history
	// keeps the last 50 lines server-side, tags are 2–5
	// letters/digits, and the past-champions list caps at 12.
	AllianceNoticeMax = 140
	AllianceChatCap   = 50
	AllianceTagMin    = 2
	AllianceTagMax    = 5
	AllianceChampCap  = 12

	// Meta keys for the weekly-race crown (17b): the settled
	// marker is the last week key a settlement ran for; the
	// champions value is a JSON list, newest first.
	metaAllyChampSettled = "alliance_champ_settled"
	metaAllyChampions    = "alliance_champions"

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

// AllianceBadges is the LEGACY 17a shield-colour list. It
// survives ONLY as the migration key for old records: its
// index becomes the new colour index (see migrateBadge).
var AllianceBadges = []string{"red", "blue", "teal", "green", "gold", "purple"}

// Badge model (17e addendum): an alliance badge is an ICON
// (1..10 — the owner's sheet, godot/assets/alliance_icons)
// plus a COLOUR index into the game's 8 slot colours
// (0 Đỏ · 1 Xanh dương · 2 Xanh lá · 3 Vàng · 4 Tím ·
// 5 Cam · 6 Xanh ngọc · 7 Hồng).
const (
	BadgeIconCount  = 10
	BadgeColorCount = 8
)

func validBadgeIconColor(icon, color int) bool {
	return icon >= 1 && icon <= BadgeIconCount &&
		color >= 0 && color < BadgeColorCount
}

// migrateBadge converts a pre-addendum record (string Badge,
// no icon) to the icon+colour model: icon defaults to 1
// (Sư Tử) and the old colour keeps its palette position
// (legacy index 0..5 → the same slot-colour index; an
// unknown legacy value lands on 0). Returns true when the
// record changed. Idempotent: a record with an icon set is
// only range-clamped.
func migrateBadge(a *Alliance) bool {
	changed := false
	if a.BadgeIcon == 0 {
		a.BadgeIcon = 1
		idx := -1
		for i, b := range AllianceBadges {
			if b == a.Badge {
				idx = i
				break
			}
		}
		if idx >= 0 {
			a.BadgeColor = idx
		} else {
			a.BadgeColor = 0
		}
		changed = true
	}
	if a.Badge != "" {
		a.Badge = ""
		changed = true
	}
	if a.BadgeIcon < 1 || a.BadgeIcon > BadgeIconCount {
		a.BadgeIcon = 1
		changed = true
	}
	if a.BadgeColor < 0 || a.BadgeColor >= BadgeColorCount {
		a.BadgeColor = 0
		changed = true
	}
	return changed
}

var (
	ErrAllyLogin       = errors.New("Đăng nhập để dùng Liên minh")
	ErrAllyBadName     = errors.New("Tên liên minh phải có 3–24 ký tự (chữ, số, khoảng trắng, _)")
	ErrAllyNameTaken   = errors.New("Tên liên minh đã có người dùng")
	ErrAllyBadBadge    = errors.New("Huy hiệu liên minh không hợp lệ")
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
	ErrAllyBadTag      = errors.New("Tag liên minh phải có 2–5 ký tự (chỉ chữ và số)")
	ErrAllyTagTaken    = errors.New("Tag liên minh đã có người dùng")
	ErrAllyNoticeLong  = errors.New("Thông báo tối đa 140 ký tự")
)

// AllianceMember is one member row: role, join time and the
// weekly contribution (WeekKey = the Monday of the week the
// points belong to, "2006-01-02" server-local; a stale key
// reads as 0 — the lazy weekly reset). WeekGames/WeekWins
// (17b) count the member's banked matches/wins in the same
// week — fed by the same MatchFeed as the quests, so the
// member detail panel needs no separate bookkeeping.
type AllianceMember struct {
	User      string `json:"user"`
	Role      string `json:"role"`
	JoinedAt  int64  `json:"joined_at"`
	WeekKey   string `json:"week_key,omitempty"`
	WeekPts   int    `json:"week_pts"`
	WeekGames int    `json:"week_games,omitempty"`
	WeekWins  int    `json:"week_wins,omitempty"`
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

// AllianceChatMsg is one persisted alliance-chat line (17b).
// User is the sender's username; Name their display name at
// send time (history reads the same after a rename).
type AllianceChatMsg struct {
	User string `json:"user"`
	Name string `json:"name"`
	Text string `json:"text"`
	At   int64  `json:"at"`
}

// AllianceQuests is one alliance's weekly-quest state (17b):
// progress counters for the three fixed templates, keyed by
// week like member contributions (lazy Monday reset). Done
// flags latch for the week — a dispute revert can pull
// progress back below a threshold but never un-grants (and
// never re-grants) the reward.
type AllianceQuests struct {
	Week        string `json:"week,omitempty"`
	Matches     int    `json:"matches"`
	Wins        int    `json:"wins"`
	RankedWins  int    `json:"ranked_wins"`
	DoneMatches bool   `json:"done_matches,omitempty"`
	DoneWins    bool   `json:"done_wins,omitempty"`
	DoneRanked  bool   `json:"done_ranked,omitempty"`
}

// AllianceChamp is one weekly-race champion record (17b),
// stored as a JSON list in the store meta (newest first).
type AllianceChamp struct {
	Week   string `json:"week"`
	ID     string `json:"id"`
	Name   string `json:"name"`
	Points int    `json:"points"`
}

// Alliance is the whole guild state.
type Alliance struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	// Badge is the LEGACY 17a shield-colour id, read only by
	// migrateBadge; new records never write it.
	Badge string `json:"badge,omitempty"`
	// BadgeIcon (1..10) + BadgeColor (0..7, slot colours) —
	// the 17e-addendum badge model.
	BadgeIcon  int               `json:"badge_icon"`
	BadgeColor int               `json:"badge_color"`
	Mode       string            `json:"mode"`
	Desc       string            `json:"desc,omitempty"`
	Leader     string            `json:"leader"`
	XP         int               `json:"xp"`
	CreatedAt  int64             `json:"created_at"`
	Members    []AllianceMember  `json:"members"`
	Requests   []AllianceRequest `json:"requests,omitempty"`
	Invites    []AllianceInvite  `json:"invites,omitempty"`
	Log        []AllianceEvent   `json:"log,omitempty"`
	// 17b: Tag is the short unique alliance tag shown as
	// [TAG] before members' names (presentation only — the
	// name is resolved server-side, never in any sim).
	Tag string `json:"tag,omitempty"`
	// 17b: the notice board (leader/deputy editable).
	Notice   string `json:"notice,omitempty"`
	NoticeBy string `json:"notice_by,omitempty"`
	NoticeAt int64  `json:"notice_at,omitempty"`
	// 17b: persisted chat history, oldest first, cap 50.
	Chat []AllianceChatMsg `json:"chat,omitempty"`
	// 17b: weekly quests + the weekly-points bonus they
	// grant (WeekBonus counts toward the weekly ranking
	// only while WeekBonusKey is the current week).
	Quests       AllianceQuests `json:"quests"`
	WeekBonus    int            `json:"week_bonus,omitempty"`
	WeekBonusKey string         `json:"week_bonus_key,omitempty"`
	// 17b: last week's final weekly-points snapshot, taken
	// by touchWeek before it zeroes the rows — the crown
	// settlement reads it (a week nobody touches until long
	// after still settles from this snapshot).
	PrevWeekKey string `json:"prev_week_key,omitempty"`
	PrevWeekPts int    `json:"prev_week_pts,omitempty"`
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
	c.Chat = append([]AllianceChatMsg(nil), a.Chat...)
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

// prevWeekKey is the week key of the last COMPLETED week
// (the Monday seven days before this week's Monday).
func prevWeekKey(t time.Time) string {
	return weekKeyOf(t.AddDate(0, 0, -7))
}

// Alliances is the alliance service: store + accounts lookups.
type Alliances struct {
	mu    sync.Mutex
	store Store
	acc   *Accounts
	now   func() time.Time // test seam
}

func NewAlliances(store Store, acc *Accounts) *Alliances {
	as := &Alliances{store: store, acc: acc, now: time.Now}
	// Badge migration (17e addendum): convert every stored
	// pre-addendum record once, at service start.
	for _, a := range store.Alliances() {
		if migrateBadge(a) {
			as.save(a)
		}
	}
	return as
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

// touchWeek applies the lazy weekly reset to a: member rows
// (points + 17b match/win counters), the quest state and the
// quest weekly-points bonus (in memory; persisted on the next
// save of that alliance). BEFORE zeroing, it snapshots the
// just-finished week's total into PrevWeek* (17b) so the
// crown settlement can crown last week's winner even when
// nobody touched the alliance during the new week.
func (as *Alliances) touchWeek(a *Alliance) {
	now := as.now()
	key := weekKeyOf(now)
	pw := prevWeekKey(now)
	// Snapshot last week's total once (the first touch in a
	// later week): member rows still carrying pw, plus the
	// quest bonus if it belongs to pw.
	if a.PrevWeekKey != pw {
		pts := 0
		found := false
		for _, m := range a.Members {
			if m.WeekKey == pw {
				pts += m.WeekPts
				found = true
			}
		}
		if a.WeekBonusKey == pw {
			pts += a.WeekBonus
			found = true
		}
		// Rows two+ weeks stale mean last week was never
		// played here — its total is genuinely 0.
		a.PrevWeekKey = pw
		if found {
			a.PrevWeekPts = pts
		} else {
			a.PrevWeekPts = 0
		}
	}
	for i := range a.Members {
		if a.Members[i].WeekKey != key {
			a.Members[i].WeekKey = key
			a.Members[i].WeekPts = 0
			a.Members[i].WeekGames = 0
			a.Members[i].WeekWins = 0
		}
	}
	if a.Quests.Week != key {
		a.Quests = AllianceQuests{Week: key}
	}
	if a.WeekBonusKey != key {
		a.WeekBonus = 0
		a.WeekBonusKey = key
	}
}

// weekPoints is a's total weekly points in the current week:
// member contributions + the quest bonus (17b).
func (as *Alliances) weekPoints(a *Alliance) int {
	return as.weekPointsFor(a, weekKeyOf(as.now()))
}

// weekPointsFor is a's weekly-points total for week wk: the
// live rows for the current week, the snapshot for last
// week, or a direct sum over stale rows for any other week.
func (as *Alliances) weekPointsFor(a *Alliance, wk string) int {
	if wk == a.PrevWeekKey {
		return a.PrevWeekPts
	}
	sum := 0
	for _, m := range a.Members {
		if m.WeekKey == wk {
			sum += m.WeekPts
		}
	}
	if a.WeekBonusKey == wk {
		sum += a.WeekBonus
	}
	return sum
}

// ---- 17b weekly quests ------------------------------------

// questDef is one fixed weekly-quest template. Targets and
// rewards are Bé's defaults — flagged in KE-HOACH §17b.
type questDef struct {
	key       string
	label     string
	target    int
	xpReward  int
	ptsReward int
}

var allianceQuestDefs = []questDef{
	{"matches", "Toàn liên minh đấu 40 trận", 40, 150, 30},
	{"wins", "Toàn liên minh thắng 15 trận", 15, 200, 40},
	{"ranked_wins", "Thắng 5 trận Đấu Hạng", 5, 250, 50},
}

func questProgress(q AllianceQuests, key string) int {
	switch key {
	case "matches":
		return q.Matches
	case "wins":
		return q.Wins
	case "ranked_wins":
		return q.RankedWins
	}
	return 0
}

func questDone(q AllianceQuests, key string) bool {
	switch key {
	case "matches":
		return q.DoneMatches
	case "wins":
		return q.DoneWins
	case "ranked_wins":
		return q.DoneRanked
	}
	return false
}

func questSetDone(q *AllianceQuests, key string) {
	switch key {
	case "matches":
		q.DoneMatches = true
	case "wins":
		q.DoneWins = true
	case "ranked_wins":
		q.DoneRanked = true
	}
}

// checkQuests grants any newly-completed quest's reward
// (alliance XP + weekly-points bonus), once per week.
// as.mu held; caller saves.
func (as *Alliances) checkQuests(a *Alliance) {
	for _, d := range allianceQuestDefs {
		if questDone(a.Quests, d.key) {
			continue
		}
		if questProgress(a.Quests, d.key) < d.target {
			continue
		}
		questSetDone(&a.Quests, d.key)
		a.XP += d.xpReward
		a.WeekBonus += d.ptsReward
		as.logf(a, "Hoàn thành nhiệm vụ tuần «%s» (+%d XP, +%d điểm tuần)",
			d.label, d.xpReward, d.ptsReward)
	}
}

// ---- 17b weekly-race crown --------------------------------

// champs reads the past-champions list from the store meta
// (newest first; corrupt/absent reads as empty).
func (as *Alliances) champs() []AllianceChamp {
	raw, ok := as.store.GetMeta(metaAllyChampions)
	if !ok || raw == "" {
		return nil
	}
	var list []AllianceChamp
	if err := json.Unmarshal([]byte(raw), &list); err != nil {
		return nil
	}
	return list
}

func (as *Alliances) saveChamps(list []AllianceChamp) {
	if len(list) > AllianceChampCap {
		list = list[:AllianceChampCap]
	}
	raw, err := json.Marshal(list)
	if err == nil {
		_ = as.store.PutMeta(metaAllyChampions, string(raw))
	}
}

// settleChamp records last week's champion the first time
// any read path runs in a new week (lazy, like every weekly
// reset here). The winner is picked with the leaderboard's
// own ordering — weekly points desc, total XP desc, name
// asc — and only crowned with points > 0. The settled
// marker advances even when nobody is crowned, and a week
// the whole server slept through is simply skipped.
// as.mu held by callers.
func (as *Alliances) settleChamp() {
	lastW := prevWeekKey(as.now())
	if settled, _ := as.store.GetMeta(metaAllyChampSettled); settled == lastW {
		return
	}
	var best *Alliance
	bestPts := 0
	for _, a := range as.all() {
		as.touchWeek(a)
		pts := as.weekPointsFor(a, lastW)
		switch {
		case best == nil:
			best, bestPts = a, pts
		case pts != bestPts:
			if pts > bestPts {
				best, bestPts = a, pts
			}
		case a.XP != best.XP:
			if a.XP > best.XP {
				best, bestPts = a, pts
			}
		case strings.ToLower(a.Name) < strings.ToLower(best.Name):
			best, bestPts = a, pts
		}
	}
	if best != nil && bestPts > 0 {
		list := as.champs()
		// Idempotence guard: never record the same week twice.
		dup := false
		for _, c := range list {
			if c.Week == lastW {
				dup = true
			}
		}
		if !dup {
			list = append([]AllianceChamp{
				{Week: lastW, ID: best.ID, Name: best.Name, Points: bestPts},
			}, list...)
			as.saveChamps(list)
		}
	}
	_ = as.store.PutMeta(metaAllyChampSettled, lastW)
}

// champNow returns the current crown holder: the champion
// recorded for the last completed week, if any.
func (as *Alliances) champNow() (AllianceChamp, bool) {
	list := as.champs()
	if len(list) == 0 || list[0].Week != prevWeekKey(as.now()) {
		return AllianceChamp{}, false
	}
	return list[0], true
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
// The tag (17b) is required and unique case-insensitively.
func (as *Alliances) Create(creator, name, tag string, icon, color int, mode, desc string) (*Alliance, error) {
	as.mu.Lock()
	defer as.mu.Unlock()
	name = strings.TrimSpace(name)
	tag = strings.TrimSpace(tag)
	if creator == "" {
		return nil, ErrAllyNotMember
	}
	if !validAllianceName(name) {
		return nil, ErrAllyBadName
	}
	if !validAllianceTag(tag) {
		return nil, ErrAllyBadTag
	}
	if !validBadgeIconColor(icon, color) {
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
	if as.tagTaken(tag, "") {
		return nil, ErrAllyTagTaken
	}
	if rs := []rune(strings.TrimSpace(desc)); len(rs) > AllianceDescMax {
		desc = string(rs[:AllianceDescMax])
	} else {
		desc = string(rs)
	}
	a := &Alliance{
		ID: newAllianceID(as.store), Name: name,
		BadgeIcon: icon, BadgeColor: color,
		Mode: mode, Desc: desc, Leader: creator, Tag: tag,
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

// LevelOf returns the level of the alliance the user belongs
// to (0 = no alliance). Wired into Accounts.AllyLevelOf (17d)
// for avatar-frame ownership.
func (as *Alliances) LevelOf(user string) int {
	a := as.OfUser(user)
	if a == nil {
		return 0
	}
	level, _, _ := AllianceLevelForXP(a.XP)
	return level
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
	// 17b: the invite ALSO lands as a mailbox letter. The
	// mail system carries no action payload, so the letter
	// is informational — it points at the alliance screen,
	// where the invite record (the source of truth) is
	// accepted/declined through the normal op. Best effort:
	// a failed letter never fails the invite.
	tag := ""
	if a.Tag != "" {
		tag = " [" + a.Tag + "]"
	}
	_ = as.acc.DeliverLetter(target,
		"Lời mời vào liên minh "+a.Name,
		fmt.Sprintf("%s đã mời bạn vào liên minh %s%s.\n\nMở trang Liên minh để trả lời: vào Bảng xếp hạng → tab Liên minh, hoặc bấm hàng Liên minh trong trang Hồ sơ, rồi chấp nhận hoặc từ chối ở mục Lời mời.",
			as.nameOf(actor), a.Name, tag))
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

// UpdateSettings edits tag / badge / join mode /
// description (leader only). An empty tag keeps the current
// one, so pre-17b clients (and alliances founded before
// tags existed) are never forced through tag validation.
func (as *Alliances) UpdateSettings(id, actor, tag string, icon, color int, mode, desc string) error {
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
	tag = strings.TrimSpace(tag)
	if tag != "" {
		if !validAllianceTag(tag) {
			return ErrAllyBadTag
		}
		if as.tagTaken(tag, a.ID) {
			return ErrAllyTagTaken
		}
	}
	if !validBadgeIconColor(icon, color) {
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
	if tag != "" {
		a.Tag = tag
	}
	a.BadgeIcon, a.BadgeColor, a.Mode, a.Desc = icon, color, mode, desc
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

// FeedMatch is the Accounts.MatchFeed target (17b): one
// banked match (delta +1) or one un-banked match (delta −1,
// a dispute revert) for a member — feeding the member's
// weekly match/win counters and the alliance's weekly
// quests from the SAME banking events as Accrue, so a match
// can never count twice. Ranked wins are told apart by the
// ranked flag the ranked banking paths pass. Quest rewards
// latch once per week (see AllianceQuests).
func (as *Alliances) FeedMatch(user string, won bool, ranked bool, delta int) {
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
	if delta > 0 {
		m.WeekGames++
		if won {
			m.WeekWins++
		}
		a.Quests.Matches++
		if won {
			a.Quests.Wins++
			if ranked {
				a.Quests.RankedWins++
			}
		}
		as.checkQuests(a)
	} else {
		// Un-banked: pull the counters back (never below 0);
		// a latched quest reward stays granted.
		if m.WeekGames > 0 {
			m.WeekGames--
		}
		if won && m.WeekWins > 0 {
			m.WeekWins--
		}
		if a.Quests.Matches > 0 {
			a.Quests.Matches--
		}
		if won {
			if a.Quests.Wins > 0 {
				a.Quests.Wins--
			}
			if ranked && a.Quests.RankedWins > 0 {
				a.Quests.RankedWins--
			}
		}
	}
	as.save(a)
}

// TagOf resolves a user's alliance tag for presentation
// ([TAG] prefixes in chat / friends / profile payloads).
// "" for guests and the unaffiliated. Presentation ONLY —
// never read by any sim or checksum path.
func (as *Alliances) TagOf(user string) string {
	if user == "" {
		return ""
	}
	as.mu.Lock()
	defer as.mu.Unlock()
	if a := as.ofUser(user); a != nil {
		return a.Tag
	}
	return ""
}

// validAllianceTag: 2–5 characters, letters/digits only
// (Unicode letters allowed, no spaces or punctuation).
func validAllianceTag(tag string) bool {
	n := utf8.RuneCountInString(tag)
	if n < AllianceTagMin || n > AllianceTagMax {
		return false
	}
	for _, r := range tag {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) {
			return false
		}
	}
	return true
}

// tagTaken reports whether another alliance already uses
// tag (case-insensitive), excluding alliance exceptID.
func (as *Alliances) tagTaken(tag, exceptID string) bool {
	for _, a := range as.all() {
		if a.ID != exceptID && a.Tag != "" && strings.EqualFold(a.Tag, tag) {
			return true
		}
	}
	return false
}

// SetNotice edits the notice board (leader + deputies).
// Live fan-out is the hub's job; this only persists.
func (as *Alliances) SetNotice(id, actor, text string) error {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return ErrAllyNotFound
	}
	if !as.canModerate(a, actor) {
		return ErrAllyNoPerm
	}
	text = strings.TrimSpace(text)
	if utf8.RuneCountInString(text) > AllianceNoticeMax {
		return ErrAllyNoticeLong
	}
	a.Notice = text
	a.NoticeBy = actor
	a.NoticeAt = as.now().Unix()
	as.logf(a, "%s đã cập nhật thông báo liên minh", as.nameOf(actor))
	as.save(a)
	return nil
}

// AddChatMsg persists one alliance-chat line (17b history,
// cap 50, oldest dropped). Called by the hub ONLY for lines
// that passed the rate limit and were actually relayed, so
// the history is exactly what members saw.
func (as *Alliances) AddChatMsg(id, user, name, text string) {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return
	}
	a.Chat = append(a.Chat, AllianceChatMsg{
		User: user, Name: name, Text: text, At: as.now().Unix(),
	})
	if len(a.Chat) > AllianceChatCap {
		a.Chat = a.Chat[len(a.Chat)-AllianceChatCap:]
	}
	as.save(a)
}

// ChatHistory returns a copy of the persisted chat lines
// (member-only: callers check membership first).
func (as *Alliances) ChatHistory(id string) []AllianceChatMsg {
	as.mu.Lock()
	defer as.mu.Unlock()
	a, ok := as.get(id)
	if !ok {
		return nil
	}
	return append([]AllianceChatMsg(nil), a.Chat...)
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
		// 17b member detail: this week's banked matches/wins.
		"week_games": m.WeekGames, "week_wins": m.WeekWins,
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
		"id": a.ID, "name": a.Name, "badge_icon": a.BadgeIcon, "badge_color": a.BadgeColor, "mode": a.Mode,
		"desc": a.Desc, "level": level, "xp": a.XP, "xp_into": into,
		"xp_next": forNext, "week": as.weekPoints(a),
		"rank": as.rankOf(a.ID), "members_count": len(a.Members),
		"cap": AllianceCap, "created_at": a.CreatedAt,
		"leader": a.Leader, "leader_name": as.nameOf(a.Leader),
		"my_role": myRole, "members": mrows,
	}
	// 17b payload: tag, notice board, chat history, weekly
	// quests, crown marker + past-champions history.
	out["tag"] = a.Tag
	out["notice"] = a.Notice
	out["notice_by"] = ""
	if a.NoticeBy != "" {
		out["notice_by"] = as.nameOf(a.NoticeBy)
	}
	out["notice_at"] = a.NoticeAt
	chat := make([]map[string]any, 0, len(a.Chat))
	for _, cm := range a.Chat {
		chat = append(chat, map[string]any{
			"user": cm.User, "name": cm.Name, "text": cm.Text, "at": cm.At,
		})
	}
	out["chat"] = chat
	qrows := make([]map[string]any, 0, len(allianceQuestDefs))
	for _, d := range allianceQuestDefs {
		qrows = append(qrows, map[string]any{
			"key": d.key, "label": d.label,
			"prog": questProgress(a.Quests, d.key), "target": d.target,
			"done": questDone(a.Quests, d.key),
			"xp":   d.xpReward, "pts": d.ptsReward,
		})
	}
	out["quests"] = qrows
	out["quest_week"] = a.Quests.Week
	champ, hasChamp := as.champNow()
	out["champion"] = hasChamp && champ.ID == a.ID
	hist := make([]map[string]any, 0)
	for _, c := range as.champs() {
		hist = append(hist, map[string]any{
			"week": c.Week, "id": c.ID, "name": c.Name, "points": c.Points,
		})
	}
	out["champions"] = hist
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
	as.settleChamp() // 17b: lazy weekly-crown settlement
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
					"id": a.ID, "name": a.Name, "badge_icon": a.BadgeIcon, "badge_color": a.BadgeColor,
					"level": level, "members": len(a.Members),
					"by_name": as.nameOf(iv.By), "at": iv.At,
					"tag": a.Tag,
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
			"id": a.ID, "name": a.Name, "badge_icon": a.BadgeIcon, "badge_color": a.BadgeColor, "mode": a.Mode,
			"level": level, "members": len(a.Members), "cap": AllianceCap,
			"leader_name": as.nameOf(a.Leader), "requested": requested,
			"full": len(a.Members) >= AllianceCap,
			"tag":  a.Tag,
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
	as.settleChamp() // 17b: lazy weekly-crown settlement
	champ, hasChamp := as.champNow()
	ranked := as.ranked()
	rows := make([]map[string]any, 0, len(ranked))
	var me map[string]any
	for i, a := range ranked {
		level, _, _ := AllianceLevelForXP(a.XP)
		row := map[string]any{
			"alliance": true, "id": a.ID, "name": a.Name, "badge_icon": a.BadgeIcon, "badge_color": a.BadgeColor,
			"level": level, "members": len(a.Members), "cap": AllianceCap,
			"week": as.weekPoints(a), "xp": a.XP,
			"leader_name": as.nameOf(a.Leader), "pos": i + 1,
			"tag": a.Tag, "champion": hasChamp && champ.ID == a.ID,
		}
		rows = append(rows, row)
		if memberOf(a, user) != nil {
			me = row
		}
	}
	return rows, me
}
