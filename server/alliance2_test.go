package main

// 17b alliance tests: notice-board permissions, persisted
// chat history (cap + member-only), weekly quests fed by the
// real banking paths (incl. ranked-only counting, once-per-
// week rewards, revert behaviour, Monday reset), the weekly
// crown settlement + tie-breaks, tag validation/uniqueness +
// settings permissions, the mail-invite flow, and the member
// detail numbers (week games/wins).

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

func allyJoin(t *testing.T, e *allyEnv, id, user string) {
	t.Helper()
	if err := e.as.Apply(id, user, ""); err != nil {
		t.Fatalf("join %s: %v", user, err)
	}
}

func TestAllianceNoticePermissions(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Dep", "Mem")
	a := e.mustCreate(t, "Boss", "Hội Thông Báo", AllianceModeOpen)
	allyJoin(t, e, a.ID, "Dep")
	allyJoin(t, e, a.ID, "Mem")
	if err := e.as.SetRole(a.ID, "Boss", "Dep", AllianceRoleDeputy); err != nil {
		t.Fatal(err)
	}
	// Plain members cannot set the notice.
	if err := e.as.SetNotice(a.ID, "Mem", "Chào cả nhà"); err != ErrAllyNoPerm {
		t.Fatalf("member notice: %v", err)
	}
	// Non-members cannot either.
	if err := e.as.SetNotice(a.ID, "Ghost", "x"); err != ErrAllyNoPerm {
		t.Fatalf("outsider notice: %v", err)
	}
	// Deputy can; leader can; the payload carries text + setter.
	if err := e.as.SetNotice(a.ID, "Dep", "Tối nay 20h điểm danh"); err != nil {
		t.Fatalf("deputy notice: %v", err)
	}
	mine, _ := e.as.HomeFor("Mem", nil)
	if mine["notice"] != "Tối nay 20h điểm danh" || mine["notice_by"] != "Dep" {
		t.Fatalf("notice payload: %v / %v", mine["notice"], mine["notice_by"])
	}
	if err := e.as.SetNotice(a.ID, "Boss", "Đổi lịch: 21h"); err != nil {
		t.Fatalf("leader notice: %v", err)
	}
	// The 140-rune cap is enforced (Vietnamese text counts runes).
	long := strings.Repeat("à", AllianceNoticeMax+1)
	if err := e.as.SetNotice(a.ID, "Boss", long); err != ErrAllyNoticeLong {
		t.Fatalf("long notice: %v", err)
	}
	exact := strings.Repeat("à", AllianceNoticeMax)
	if err := e.as.SetNotice(a.ID, "Boss", exact); err != nil {
		t.Fatalf("140-rune notice must pass: %v", err)
	}
	ga, _ := e.as.get(a.ID)
	if ga.Notice != exact || ga.NoticeBy != "Boss" || ga.NoticeAt == 0 {
		t.Fatalf("stored notice: %q by %q at %d", ga.Notice, ga.NoticeBy, ga.NoticeAt)
	}
}

func TestAllianceChatHistoryPersisted(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Mate", "Outsider")
	a := e.mustCreate(t, "Boss", "Hội Lịch Sử", AllianceModeOpen)
	allyJoin(t, e, a.ID, "Mate")
	members := e.as.MemberUsers(a.ID)
	fs := &fakeSender{}
	e.hub.RegisterUserConn("Mate", fs)
	e.hub.RelayAllianceChat("Boss", "Boss", a.ID, members, "dòng đầu tiên")
	// 60 more lines from Mate (rate window is wall-clock; the
	// fake clock doesn't gate it, so batch in legal bursts:
	// each relay call is one line — the hub allows 5 per 2s.
	// Use AddChatMsg directly for the bulk to test the CAP,
	// and the relay for the member-only + persist path).
	for i := 0; i < 60; i++ {
		e.as.AddChatMsg(a.ID, "Mate", "Mate", fmt.Sprintf("bulk %02d", i))
	}
	hist := e.as.ChatHistory(a.ID)
	if len(hist) != AllianceChatCap {
		t.Fatalf("history len = %d, want cap %d", len(hist), AllianceChatCap)
	}
	// Oldest dropped: first stored line is no longer the very
	// first chat line; the newest is the last bulk line.
	if hist[0].Text == "dòng đầu tiên" {
		t.Fatalf("oldest line not dropped: %q", hist[0].Text)
	}
	if hist[len(hist)-1].Text != "bulk 59" {
		t.Fatalf("newest line = %q", hist[len(hist)-1].Text)
	}
	// The relayed line was persisted exactly once.
	found := 0
	for _, m := range hist {
		if m.Text == "dòng đầu tiên" {
			found++
		}
	}
	if found > 1 {
		t.Fatalf("relayed line persisted %d times", found)
	}
	// History ships in the member payload; outsiders get no
	// alliance view at all (member-only).
	mine, _ := e.as.HomeFor("Mate", nil)
	chat, _ := mine["chat"].([]map[string]any)
	if len(chat) != AllianceChatCap || chat[len(chat)-1]["text"] != "bulk 59" {
		t.Fatalf("payload chat: %d lines", len(chat))
	}
	outMine, _ := e.as.HomeFor("Outsider", nil)
	if outMine != nil {
		t.Fatalf("outsider has an alliance view: %v", outMine)
	}
	// Rate-limited lines are NOT persisted: blast past the
	// limit and confirm the history only grew by the legal
	// burst.
	before := len(e.as.ChatHistory(a.ID))
	for i := 0; i < ChatRateCount+4; i++ {
		e.hub.RelayAllianceChat("Boss", "Boss", a.ID, members, fmt.Sprintf("spam %d", i))
	}
	after := e.as.ChatHistory(a.ID)
	grew := 0
	for _, m := range after {
		if strings.HasPrefix(m.Text, "spam ") {
			grew++
		}
	}
	if grew > ChatRateCount {
		t.Fatalf("rate-limited lines persisted: %d (history %d -> %d)", grew, before, len(after))
	}
	_ = fs
}

func questRow(t *testing.T, mine map[string]any, key string) map[string]any {
	t.Helper()
	rows, _ := mine["quests"].([]map[string]any)
	for _, r := range rows {
		if r["key"] == key {
			return r
		}
	}
	t.Fatalf("quest %q missing in %v", key, mine["quests"])
	return nil
}

func TestAllianceQuestsFromBankedMatches(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Lead", "Mem", "Foe")
	a := e.mustCreate(t, "Lead", "Hội Nhiệm Vụ", AllianceModeOpen)
	allyJoin(t, e, a.ID, "Mem")

	bank := func(user string, won bool) {
		t.Helper()
		if err := e.acc.RecordMatch(user, won); err != nil {
			t.Fatal(err)
		}
	}
	// 39 collective matches (no quest done yet): 20 lead wins,
	// 19 member losses.
	for i := 0; i < 20; i++ {
		bank("Lead", true)
	}
	for i := 0; i < 19; i++ {
		bank("Mem", false)
	}
	mine, _ := e.as.HomeFor("Lead", nil)
	if r := questRow(t, mine, "matches"); r["prog"] != 39 || r["done"] != false {
		t.Fatalf("matches quest at 39: %v", r)
	}
	if r := questRow(t, mine, "wins"); r["prog"] != 20 || r["done"] != true {
		t.Fatalf("wins quest should be done at 20 wins: %v", r)
	}
	ga, _ := e.as.get(a.ID)
	// Wins quest granted exactly once: +200 XP, +40 bonus.
	// Match XP so far: 20*30 + 19*10 = 790; +200 quest = 990.
	if ga.XP != 990 || ga.WeekBonus != 40 {
		t.Fatalf("after wins quest: xp=%d bonus=%d", ga.XP, ga.WeekBonus)
	}
	// The 40th match completes the matches quest: +150/+30.
	bank("Mem", false)
	ga, _ = e.as.get(a.ID)
	if ga.XP != 990+10+150 || ga.WeekBonus != 70 {
		t.Fatalf("after matches quest: xp=%d bonus=%d", ga.XP, ga.WeekBonus)
	}
	// More matches never re-grant.
	bank("Lead", true)
	ga, _ = e.as.get(a.ID)
	if ga.XP != 990+10+150+30 || ga.WeekBonus != 70 {
		t.Fatalf("re-grant check: xp=%d bonus=%d", ga.XP, ga.WeekBonus)
	}
	// Weekly points include the bonus: member pts are
	// 21*30 + 20*10 = 830; +70 bonus = 900.
	if wp := e.as.weekPoints(ga); wp != 900 {
		t.Fatalf("weekPoints = %d, want 900 (830 + 70 bonus)", wp)
	}
	// A custom (non-ranked) win does NOT feed the ranked quest.
	mine, _ = e.as.HomeFor("Lead", nil)
	if r := questRow(t, mine, "ranked_wins"); r["prog"] != 0 {
		t.Fatalf("ranked quest fed by custom matches: %v", r)
	}
	// Ranked wins do — through the real ranked banking path.
	for i := 0; i < 5; i++ {
		if _, _, err := e.acc.RecordRankedResultMeta("Mem", "Foe", "", "", 0, ""); err != nil {
			t.Fatal(err)
		}
	}
	mine, _ = e.as.HomeFor("Lead", nil)
	if r := questRow(t, mine, "ranked_wins"); r["prog"] != 5 || r["done"] != true {
		t.Fatalf("ranked quest after 5 ranked wins: %v", r)
	}
	ga, _ = e.as.get(a.ID)
	if ga.WeekBonus != 70+50 {
		t.Fatalf("ranked quest bonus: %d, want 120", ga.WeekBonus)
	}
	// A dispute revert pulls progress back but the latched
	// reward is never un-granted and never re-granted.
	if err := e.acc.RecordMatchRevert("Mem", true); err != nil {
		t.Fatal(err)
	}
	ga, _ = e.as.get(a.ID)
	if ga.WeekBonus != 120 {
		t.Fatalf("revert touched bonus: %d", ga.WeekBonus)
	}
	mine, _ = e.as.HomeFor("Lead", nil)
	if r := questRow(t, mine, "wins"); r["done"] != true {
		t.Fatalf("revert un-latched the wins quest: %v", r)
	}
	// Monday reset: progress, counters and bonus all clear.
	*e.clock = time.Date(2026, 11, 18, 12, 0, 0, 0, time.UTC) // next week
	mine, _ = e.as.HomeFor("Lead", nil)
	if r := questRow(t, mine, "matches"); r["prog"] != 0 || r["done"] != false {
		t.Fatalf("quest not reset: %v", r)
	}
	ga, _ = e.as.get(a.ID)
	e.as.touchWeek(ga)
	if ga.WeekBonus != 0 {
		t.Fatalf("bonus not reset: %d", ga.WeekBonus)
	}
	for _, m := range mine["members"].([]map[string]any) {
		if m["user"] == "Mem" && (m["week_games"] != 0 || m["week_wins"] != 0) {
			t.Fatalf("member counters not reset: %v", m)
		}
	}
}

func TestAllianceCrownSettlement(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "LeadA", "LeadB", "MemA")
	a := e.mustCreate(t, "LeadA", "Hội Nhất", AllianceModeOpen)
	allyJoin(t, e, a.ID, "MemA")
	b := e.mustCreate(t, "LeadB", "Hội Nhì", AllianceModeOpen)
	// Week of Mon 2026-11-09 (clock starts Wed 11-11).
	e.as.Accrue("MemA", 70)
	e.as.Accrue("LeadA", 30) // A: 100
	e.as.Accrue("LeadB", 60) // B: 60
	// Next week: the first read settles last week's crown.
	*e.clock = time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC)
	rows, _ := e.as.RankingWire("LeadB")
	byID := map[string]map[string]any{}
	for _, r := range rows {
		byID[r["id"].(string)] = r
	}
	if byID[a.ID]["champion"] != true || byID[b.ID]["champion"] != false {
		t.Fatalf("crown markers: A=%v B=%v", byID[a.ID]["champion"], byID[b.ID]["champion"])
	}
	champs := e.as.champs()
	if len(champs) != 1 || champs[0].ID != a.ID || champs[0].Points != 100 ||
		champs[0].Week != "2026-11-09" || champs[0].Name != "Hội Nhất" {
		t.Fatalf("champions history: %+v", champs)
	}
	// The champion marker rides the alliance payload too, and
	// the history ships for the Hoạt động tab.
	mineA, _ := e.as.HomeFor("LeadA", nil)
	if mineA["champion"] != true {
		t.Fatalf("View champion flag: %v", mineA["champion"])
	}
	hist, _ := mineA["champions"].([]map[string]any)
	if len(hist) != 1 || hist[0]["points"] != 100 {
		t.Fatalf("View champions: %v", hist)
	}
	// Settlement is idempotent — more reads never duplicate.
	e.as.RankingWire("LeadA")
	e.as.HomeFor("LeadB", nil)
	if got := len(e.as.champs()); got != 1 {
		t.Fatalf("settlement duplicated: %d champs", got)
	}
	// A scoreless week crowns nobody but still advances.
	*e.clock = time.Date(2026, 11, 23, 9, 0, 0, 0, time.UTC)
	e.as.RankingWire("LeadA")
	if got := len(e.as.champs()); got != 1 {
		t.Fatalf("scoreless week crowned someone: %d champs", got)
	}
	if c, ok := e.as.champNow(); ok {
		t.Fatalf("stale crown still current: %+v", c)
	}
}

func TestAllianceCrownTieBreaks(t *testing.T) {
	// Equal weekly points → higher total XP wins (the
	// leaderboard's own rule).
	e := allySetup(t)
	e.reg(t, "LeadA", "LeadB")
	// Week of Mon 2026-11-02: B banks XP early (50).
	*e.clock = time.Date(2026, 11, 4, 12, 0, 0, 0, time.UTC)
	b := e.mustCreate(t, "LeadB", "Hội Bê", AllianceModeOpen)
	e.as.Accrue("LeadB", 50)
	// Week of Mon 2026-11-09: both reach 80 weekly points;
	// B's cumulative XP (130) beats A's (80).
	*e.clock = time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	a := e.mustCreate(t, "LeadA", "Hội A", AllianceModeOpen)
	e.as.Accrue("LeadA", 80)
	e.as.Accrue("LeadB", 80)
	*e.clock = time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC)
	e.as.RankingWire("LeadA")
	champs := e.as.champs()
	if len(champs) != 1 || champs[0].ID != b.ID || champs[0].Points != 80 {
		t.Fatalf("XP tie-break: %+v", champs)
	}
	_ = a

	// Equal points AND equal XP → name ascending wins.
	e2 := allySetup(t)
	e2.reg(t, "LeadC", "LeadD")
	y := e2.mustCreate(t, "LeadD", "Hội Yến", AllianceModeOpen)
	x := e2.mustCreate(t, "LeadC", "Hội An", AllianceModeOpen)
	e2.as.Accrue("LeadD", 55)
	e2.as.Accrue("LeadC", 55)
	*e2.clock = time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC)
	e2.as.RankingWire("LeadC")
	champs2 := e2.as.champs()
	if len(champs2) != 1 || champs2[0].ID != x.ID {
		t.Fatalf("name tie-break: %+v (want %s over %s)", champs2, x.ID, y.ID)
	}
}

func TestAllianceTagRules(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Lead", "Lead2", "Mem")
	for _, bad := range []string{"", "A", "ABCDEF", "A B", "A-B", "A_B", "!!"} {
		if _, err := e.as.Create("Lead", "Hội Tag", bad, "red", AllianceModeOpen, ""); err != ErrAllyBadTag {
			t.Fatalf("tag %q: %v", bad, err)
		}
	}
	a, err := e.as.Create("Lead", "Hội Tag", "HT99", "red", AllianceModeOpen, "")
	if err != nil {
		t.Fatal(err)
	}
	// Uniqueness is case-insensitive.
	if _, err := e.as.Create("Lead2", "Hội Khác", "ht99", "blue", AllianceModeOpen, ""); err != ErrAllyTagTaken {
		t.Fatalf("duplicate tag: %v", err)
	}
	// TagOf resolves members; guests/strangers get "".
	if got := e.as.TagOf("Lead"); got != "HT99" {
		t.Fatalf("TagOf = %q", got)
	}
	if got := e.as.TagOf("Mem"); got != "" {
		t.Fatalf("TagOf stranger = %q", got)
	}
	// The profile payload carries the tag (AllyTagOf seam).
	prof := e.acc.profileOf(mustAccount(t, e, "Lead"))
	if prof.AllyTag != "HT99" {
		t.Fatalf("profile ally_tag = %q", prof.AllyTag)
	}
	// Settings: only the leader edits; taken tags rejected;
	// own tag in another case is fine; a fresh tag sticks.
	b := e.mustCreate(t, "Lead2", "Hội Hai", AllianceModeOpen)
	_ = b
	allyJoin(t, e, a.ID, "Mem")
	if err := e.as.UpdateSettings(a.ID, "Mem", "NEW1", "red", AllianceModeOpen, ""); err != ErrAllyNoPerm {
		t.Fatalf("member tag edit: %v", err)
	}
	if err := e.as.UpdateSettings(a.ID, "Lead", "hT99", "red", AllianceModeOpen, ""); err != nil {
		t.Fatalf("own tag re-case: %v", err)
	}
	if err := e.as.UpdateSettings(a.ID, "Lead", "T01", "red", AllianceModeOpen, ""); err != ErrAllyTagTaken {
		t.Fatalf("settings to taken tag (mustCreate T01): %v", err)
	}
	if err := e.as.UpdateSettings(a.ID, "Lead", "SL1", "red", AllianceModeOpen, ""); err != nil {
		t.Fatalf("settings tag: %v", err)
	}
	if got := e.as.TagOf("Lead"); got != "SL1" {
		t.Fatalf("TagOf after settings = %q", got)
	}
	// Empty tag in settings keeps the current one.
	if err := e.as.UpdateSettings(a.ID, "Lead", "", "blue", AllianceModeOpen, ""); err != nil {
		t.Fatal(err)
	}
	if got := e.as.TagOf("Lead"); got != "SL1" {
		t.Fatalf("empty settings tag wiped the tag: %q", got)
	}
}

func mustAccount(t *testing.T, e *allyEnv, user string) *Account {
	t.Helper()
	a, ok := e.acc.store.GetAccount(user)
	if !ok {
		t.Fatalf("account %s missing", user)
	}
	return a
}

func TestAllianceInviteMail(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Lead", "Mem")
	a := e.mustCreate(t, "Lead", "Hội Thư", AllianceModeOpen)
	target, err := e.as.Invite(a.ID, "Lead", "Mem")
	if err != nil || target != "Mem" {
		t.Fatalf("invite: %v %q", err, target)
	}
	letters := e.acc.LettersOf("Mem")
	found := false
	for _, l := range letters {
		if strings.Contains(l.Title, "Hội Thư") {
			found = true
			// The letter is informational: it must point at
			// the alliance screen (mail has no action payload).
			if !strings.Contains(l.Body, "Mở trang Liên minh") {
				t.Fatalf("letter body lacks the deep-link text: %q", l.Body)
			}
		}
	}
	if !found {
		t.Fatalf("no invite letter in mailbox: %v", letters)
	}
	// Re-inviting is idempotent and sends no second letter.
	before := len(e.acc.LettersOf("Mem"))
	if _, err := e.as.Invite(a.ID, "Lead", "Mem"); err != nil {
		t.Fatal(err)
	}
	if got := len(e.acc.LettersOf("Mem")); got != before {
		t.Fatalf("duplicate invite letter: %d -> %d", before, got)
	}
	// The invite record stays the source of truth: accepting
	// through the normal op joins the alliance.
	if err := e.as.AcceptInvite("Mem", a.ID); err != nil {
		t.Fatal(err)
	}
	if got := e.as.OfUser("Mem"); got == nil || got.ID != a.ID {
		t.Fatalf("after accept: %v", got)
	}
}

func TestAllianceMemberDetailNumbers(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Lead", "Mem")
	a := e.mustCreate(t, "Lead", "Hội Chi Tiết", AllianceModeOpen)
	allyJoin(t, e, a.ID, "Mem")
	for i := 0; i < 2; i++ {
		if err := e.acc.RecordMatch("Mem", true); err != nil {
			t.Fatal(err)
		}
	}
	if err := e.acc.RecordMatch("Mem", false); err != nil {
		t.Fatal(err)
	}
	if _, _, err := e.acc.RecordRankedResultMeta("Mem", "Lead", "", "", 0, ""); err != nil {
		t.Fatal(err)
	}
	mine, _ := e.as.HomeFor("Lead", nil)
	var row map[string]any
	for _, m := range mine["members"].([]map[string]any) {
		if m["user"] == "Mem" {
			row = m
		}
	}
	if row == nil {
		t.Fatal("member row missing")
	}
	// 4 banked matches (3 custom + 1 ranked), 3 wins, week
	// contribution 3*30 + 10 = 100.
	if row["week_games"] != 4 || row["week_wins"] != 3 || row["week"] != 100 {
		t.Fatalf("member detail: games=%v wins=%v week=%v",
			row["week_games"], row["week_wins"], row["week"])
	}
	if row["joined_at"] == int64(0) || row["joined_at"] == 0 {
		t.Fatalf("joined_at missing: %v", row["joined_at"])
	}
}
