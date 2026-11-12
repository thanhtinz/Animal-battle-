package main

// 17a alliance tests: creation rules + name uniqueness, guest
// refusal, join modes, the request approve/reject permission
// matrix, role permissions + deputy cap, the 30-member cap,
// one-alliance-per-account, transfer/disband rules, invites,
// contribution accrual from banked matches (the MatchHook)
// with weekly ranking order, and member-only chat fan-out.

import (
	"fmt"
	"path/filepath"
	"testing"
	"time"
)

type allyEnv struct {
	as    *Alliances
	acc   *Accounts
	hub   *Hub
	clock *time.Time
}

func allySetup(t *testing.T) *allyEnv {
	t.Helper()
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc := NewAccounts(fs)
	as := NewAlliances(fs, acc)
	// Wednesday 2026-11-11 noon UTC (week of Monday 2026-11-09).
	now := time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	clock := &now
	as.now = func() time.Time { return *clock }
	acc.MatchHook = as.Accrue // mirrors main()'s wiring
	hub := NewHub()
	hub.acc = acc
	hub.allis = as
	return &allyEnv{as: as, acc: acc, hub: hub, clock: clock}
}

func (e *allyEnv) reg(t *testing.T, users ...string) {
	t.Helper()
	for _, u := range users {
		if err := e.acc.Register(u, "secret1"); err != nil {
			t.Fatalf("register %s: %v", u, err)
		}
	}
}

func (e *allyEnv) seed(t *testing.T, users ...string) {
	t.Helper()
	for _, u := range users {
		if err := e.acc.store.PutAccount(&Account{User: u}); err != nil {
			t.Fatalf("seed %s: %v", u, err)
		}
	}
}

func (e *allyEnv) mustCreate(t *testing.T, creator, name, mode string) *Alliance {
	t.Helper()
	a, err := e.as.Create(creator, name, "red", mode, "")
	if err != nil {
		t.Fatalf("create %s: %v", name, err)
	}
	return a
}

func TestAllianceCreateRules(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "LeaderA", "LeaderB")

	if _, err := e.as.Create("", "Hội Rồng", "red", AllianceModeRequest, ""); err == nil {
		t.Fatal("guest create must fail")
	}
	if _, err := e.as.Create("LeaderA", "AB", "red", AllianceModeRequest, ""); err != ErrAllyBadName {
		t.Fatalf("short name: %v", err)
	}
	if _, err := e.as.Create("LeaderA", "Hội Rồng!", "red", AllianceModeRequest, ""); err != ErrAllyBadName {
		t.Fatalf("bad char name: %v", err)
	}
	if _, err := e.as.Create("LeaderA", "Hội Rồng", "pink", AllianceModeRequest, ""); err != ErrAllyBadBadge {
		t.Fatalf("bad badge: %v", err)
	}
	if _, err := e.as.Create("LeaderA", "Hội Rồng", "red", "closed", ""); err != ErrAllyBadMode {
		t.Fatalf("bad mode: %v", err)
	}
	a := e.mustCreate(t, "LeaderA", "Hội Rồng", AllianceModeRequest)
	if a.Leader != "LeaderA" || len(a.Members) != 1 || a.Members[0].Role != AllianceRoleLeader {
		t.Fatalf("fresh alliance wrong: %+v", a)
	}
	// Name uniqueness is case-insensitive.
	if _, err := e.as.Create("LeaderB", "hội rồng", "blue", AllianceModeOpen, ""); err != ErrAllyNameTaken {
		t.Fatalf("duplicate name: %v", err)
	}
	// The creator cannot found a second one.
	if _, err := e.as.Create("LeaderA", "Hội Khác", "blue", AllianceModeOpen, ""); err != ErrAllyAlreadyIn {
		t.Fatalf("second create: %v", err)
	}
}

func TestAllianceJoinModes(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Boss2", "Guest1", "Guest2")
	open := e.mustCreate(t, "Boss", "Hội Mở", AllianceModeOpen)
	// Open mode: apply = join immediately.
	if err := e.as.Apply(open.ID, "Guest1", ""); err != nil {
		t.Fatal(err)
	}
	if got := e.as.OfUser("Guest1"); got == nil || got.ID != open.ID {
		t.Fatal("open-mode apply did not join")
	}
	// Request mode: apply files paper only.
	req2 := e.mustCreate(t, "Boss2", "Hội Duyệt", AllianceModeRequest)
	if err := e.as.Apply(req2.ID, "Guest2", "cho mình vào"); err != nil {
		t.Fatal(err)
	}
	if got := e.as.OfUser("Guest2"); got != nil {
		t.Fatal("request-mode apply must not join before approval")
	}
	got, _ := e.as.get(req2.ID)
	if len(got.Requests) != 1 || got.Requests[0].User != "Guest2" {
		t.Fatalf("request not filed: %+v", got.Requests)
	}
	// Double-apply is idempotent, and cancel withdraws it.
	if err := e.as.Apply(req2.ID, "Guest2", ""); err != nil {
		t.Fatal(err)
	}
	if err := e.as.CancelRequest(req2.ID, "Guest2"); err != nil {
		t.Fatal(err)
	}
	got, _ = e.as.get(req2.ID)
	if len(got.Requests) != 0 {
		t.Fatal("cancel did not withdraw the request")
	}
	// Guests cannot apply at all.
	if err := e.as.Apply(open.ID, "", ""); err == nil {
		t.Fatal("guest apply must fail")
	}
}

func TestAllianceRequestPermissions(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Plain", "Hopeful", "Hopeful2")
	a := e.mustCreate(t, "Boss", "Hội Quyền", AllianceModeRequest)
	if err := e.as.Apply(a.ID, "Plain", ""); err != nil {
		t.Fatal(err)
	}
	// Nobody is a member yet except the leader: a pending
	// applicant cannot approve anyone (not even themselves).
	if err := e.as.Approve(a.ID, "Plain", "Plain"); err != ErrAllyNoPerm {
		t.Fatalf("applicant approve: %v", err)
	}
	if err := e.as.Approve(a.ID, "Boss", "Plain"); err != nil {
		t.Fatal(err)
	}
	if err := e.as.Apply(a.ID, "Hopeful", ""); err != nil {
		t.Fatal(err)
	}
	// A plain member cannot approve/reject.
	if err := e.as.Approve(a.ID, "Plain", "Hopeful"); err != ErrAllyNoPerm {
		t.Fatalf("member approve: %v", err)
	}
	if err := e.as.Reject(a.ID, "Plain", "Hopeful"); err != ErrAllyNoPerm {
		t.Fatalf("member reject: %v", err)
	}
	// Promote Plain to deputy: deputies CAN moderate.
	if err := e.as.SetRole(a.ID, "Boss", "Plain", AllianceRoleDeputy); err != nil {
		t.Fatal(err)
	}
	if err := e.as.Approve(a.ID, "Plain", "Hopeful"); err != nil {
		t.Fatalf("deputy approve: %v", err)
	}
	if got := e.as.OfUser("Hopeful"); got == nil {
		t.Fatal("approved user did not join")
	}
	// Reject path.
	if err := e.as.Apply(a.ID, "Hopeful2", ""); err != nil {
		t.Fatal(err)
	}
	if err := e.as.Reject(a.ID, "Plain", "Hopeful2"); err != nil {
		t.Fatalf("deputy reject: %v", err)
	}
	got, _ := e.as.get(a.ID)
	if len(got.Requests) != 0 {
		t.Fatal("rejected request still pending")
	}
}

func TestAllianceRoleMatrix(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Dep1", "Dep2", "Dep3", "Dep4", "Mem1", "Mem2")
	a := e.mustCreate(t, "Boss", "Hội Vai", AllianceModeOpen)
	for _, u := range []string{"Dep1", "Dep2", "Dep3", "Dep4", "Mem1", "Mem2"} {
		if err := e.as.Apply(a.ID, u, ""); err != nil {
			t.Fatal(err)
		}
	}
	// Deputy cap = 3.
	for _, u := range []string{"Dep1", "Dep2", "Dep3"} {
		if err := e.as.SetRole(a.ID, "Boss", u, AllianceRoleDeputy); err != nil {
			t.Fatal(err)
		}
	}
	if err := e.as.SetRole(a.ID, "Boss", "Dep4", AllianceRoleDeputy); err != ErrAllyDeputyCap {
		t.Fatalf("4th deputy: %v", err)
	}
	// Only the leader manages roles/settings/transfer/disband.
	if err := e.as.SetRole(a.ID, "Dep1", "Mem1", AllianceRoleDeputy); err != ErrAllyNoPerm {
		t.Fatalf("deputy setrole: %v", err)
	}
	if err := e.as.UpdateSettings(a.ID, "Dep1", "blue", AllianceModeOpen, ""); err != ErrAllyNoPerm {
		t.Fatalf("deputy settings: %v", err)
	}
	if err := e.as.Transfer(a.ID, "Dep1", "Mem1"); err != ErrAllyNoPerm {
		t.Fatalf("deputy transfer: %v", err)
	}
	if err := e.as.Disband(a.ID, "Dep1"); err != ErrAllyNoPerm {
		t.Fatalf("deputy disband: %v", err)
	}
	// Kick matrix: member cannot kick; deputy kicks members
	// only; leader kicks deputies too.
	if err := e.as.Kick(a.ID, "Mem1", "Mem2"); err != ErrAllyNoPerm {
		t.Fatalf("member kick: %v", err)
	}
	if err := e.as.Kick(a.ID, "Dep1", "Dep2"); err != ErrAllyNoPerm {
		t.Fatalf("deputy kicks deputy: %v", err)
	}
	if err := e.as.Kick(a.ID, "Dep1", "Mem2"); err != nil {
		t.Fatalf("deputy kicks member: %v", err)
	}
	if err := e.as.Kick(a.ID, "Boss", "Dep3"); err != nil {
		t.Fatalf("leader kicks deputy: %v", err)
	}
	// Demote frees a deputy slot.
	if err := e.as.SetRole(a.ID, "Boss", "Dep2", AllianceRoleMember); err != nil {
		t.Fatal(err)
	}
	if err := e.as.SetRole(a.ID, "Boss", "Dep4", AllianceRoleDeputy); err != nil {
		t.Fatalf("promote after demote: %v", err)
	}
	// Leader updates settings fine.
	if err := e.as.UpdateSettings(a.ID, "Boss", "gold", AllianceModeRequest, "Hội mạnh"); err != nil {
		t.Fatal(err)
	}
	got, _ := e.as.get(a.ID)
	if got.Badge != "gold" || got.Mode != AllianceModeRequest || got.Desc != "Hội mạnh" {
		t.Fatalf("settings not saved: %+v", got)
	}
}

func TestAllianceCap(t *testing.T) {
	e := allySetup(t)
	e.seed(t, "CapBoss")
	a := e.mustCreate(t, "CapBoss", "Hội Đông", AllianceModeOpen)
	users := make([]string, 0, 30)
	for i := 0; i < 30; i++ {
		users = append(users, fmt.Sprintf("Cap%02d", i))
	}
	e.seed(t, users...)
	for i := 0; i < AllianceCap-1; i++ {
		if err := e.as.Apply(a.ID, users[i], ""); err != nil {
			t.Fatalf("join %d: %v", i, err)
		}
	}
	got, _ := e.as.get(a.ID)
	if len(got.Members) != AllianceCap {
		t.Fatalf("members = %d, want %d", len(got.Members), AllianceCap)
	}
	if err := e.as.Apply(a.ID, users[AllianceCap-1], ""); err != ErrAllyFull {
		t.Fatalf("31st join: %v", err)
	}
}

func TestAllianceOnePerAccount(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "BossA", "BossB", "Joiner")
	a := e.mustCreate(t, "BossA", "Hội Một", AllianceModeOpen)
	b := e.mustCreate(t, "BossB", "Hội Hai", AllianceModeOpen)
	if err := e.as.Apply(a.ID, "Joiner", ""); err != nil {
		t.Fatal(err)
	}
	if err := e.as.Apply(b.ID, "Joiner", ""); err != ErrAllyAlreadyIn {
		t.Fatalf("apply to second: %v", err)
	}
	if _, err := e.as.Invite(b.ID, "BossB", "Joiner"); err != ErrAllyTargetIn {
		t.Fatalf("invite member of another: %v", err)
	}
	// Joining also withdraws paperwork elsewhere: file a
	// request with a third alliance first, then join A via
	// invite — the pending request must be withdrawn.
	e.reg(t, "BossB2", "Floater")
	reqB := e.mustCreate(t, "BossB2", "Hội Ba", AllianceModeRequest)
	if err := e.as.Apply(reqB.ID, "Floater", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := e.as.Invite(a.ID, "BossA", "Floater"); err != nil {
		t.Fatal(err)
	}
	if err := e.as.AcceptInvite("Floater", a.ID); err != nil {
		t.Fatal(err)
	}
	got, _ := e.as.get(reqB.ID)
	if len(got.Requests) != 0 {
		t.Fatal("stale request survived the join")
	}
}

func TestAllianceTransferAndDisband(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Heir", "Mate")
	a := e.mustCreate(t, "Boss", "Hội Kế", AllianceModeOpen)
	for _, u := range []string{"Heir", "Mate"} {
		if err := e.as.Apply(a.ID, u, ""); err != nil {
			t.Fatal(err)
		}
	}
	// Leader cannot simply leave while members remain.
	if err := e.as.Leave(a.ID, "Boss"); err != ErrAllyLeaderLeave {
		t.Fatalf("leader leave: %v", err)
	}
	// Transfer, then the old leader is a plain member and the
	// new leader holds the role.
	if err := e.as.Transfer(a.ID, "Boss", "Heir"); err != nil {
		t.Fatal(err)
	}
	got, _ := e.as.get(a.ID)
	if got.Leader != "Heir" || memberOf(got, "Heir").Role != AllianceRoleLeader ||
		memberOf(got, "Boss").Role != AllianceRoleMember {
		t.Fatalf("transfer wrong: leader=%s roles boss=%s heir=%s",
			got.Leader, memberOf(got, "Boss").Role, memberOf(got, "Heir").Role)
	}
	if err := e.as.Leave(a.ID, "Boss"); err != nil {
		t.Fatalf("old leader leave: %v", err)
	}
	// Disband is the (new) leader's alone; afterwards everyone
	// is unaffiliated and the alliance is gone.
	if err := e.as.Disband(a.ID, "Mate"); err != ErrAllyNoPerm {
		t.Fatalf("member disband: %v", err)
	}
	if err := e.as.Disband(a.ID, "Heir"); err != nil {
		t.Fatal(err)
	}
	if _, ok := e.as.get(a.ID); ok {
		t.Fatal("alliance still stored after disband")
	}
	if got := e.as.OfUser("Mate"); got != nil {
		t.Fatal("member still affiliated after disband")
	}
	// A sole leader leaving dissolves the empty alliance.
	solo := e.mustCreate(t, "Mate", "Hội Đơn", AllianceModeOpen)
	if err := e.as.Leave(solo.ID, "Mate"); err != nil {
		t.Fatal(err)
	}
	if _, ok := e.as.get(solo.ID); ok {
		t.Fatal("solo-leader leave should dissolve the alliance")
	}
}

func TestAllianceInvites(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Buddy", "Shy")
	a := e.mustCreate(t, "Boss", "Hội Mời", AllianceModeRequest)
	if _, err := e.as.Invite(a.ID, "Boss", "NoSuchUser"); err != ErrAllyNoTarget {
		t.Fatalf("invite ghost: %v", err)
	}
	// Invite resolves by username; accept joins even in
	// request mode (an invitation IS the approval).
	if _, err := e.as.Invite(a.ID, "Boss", "buddy"); err != nil {
		t.Fatal(err)
	}
	invites := e.as.InvitesFor("Buddy")
	if len(invites) != 1 || invites[0].ID != a.ID {
		t.Fatalf("invites for Buddy: %v", invites)
	}
	if err := e.as.AcceptInvite("Buddy", a.ID); err != nil {
		t.Fatal(err)
	}
	if got := e.as.OfUser("Buddy"); got == nil {
		t.Fatal("accepted invite did not join")
	}
	// Decline drops the invite without joining.
	if _, err := e.as.Invite(a.ID, "Boss", "Shy"); err != nil {
		t.Fatal(err)
	}
	if err := e.as.DeclineInvite("Shy", a.ID); err != nil {
		t.Fatal(err)
	}
	if len(e.as.InvitesFor("Shy")) != 0 {
		t.Fatal("declined invite still listed")
	}
	if got := e.as.OfUser("Shy"); got != nil {
		t.Fatal("declined invite joined anyway")
	}
}

func TestAllianceAccrualAndRanking(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "BossA", "BossB", "MemA", "MemB")

	// Previous week (Monday 2026-11-02): BossB's alliance
	// banks 50 XP that will NOT count in this week's points.
	*e.clock = time.Date(2026, 11, 4, 12, 0, 0, 0, time.UTC)
	b := e.mustCreate(t, "BossB", "Hội Bê", AllianceModeOpen)
	if err := e.as.Apply(b.ID, "MemB", ""); err != nil {
		t.Fatal(err)
	}
	e.as.Accrue("MemB", 50)

	// This week (Monday 2026-11-09): both alliances bank
	// through REAL recorded matches (Accounts.MatchHook).
	*e.clock = time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	a := e.mustCreate(t, "BossA", "Hội A", AllianceModeOpen)
	if err := e.as.Apply(a.ID, "MemA", ""); err != nil {
		t.Fatal(err)
	}
	if err := e.acc.RecordMatch("MemA", true); err != nil { // win = 30
		t.Fatal(err)
	}
	if err := e.acc.RecordMatch("MemB", true); err != nil { // win = 30
		t.Fatal(err)
	}
	if err := e.acc.RecordMatch("MemB", false); err != nil { // loss = 10
		t.Fatal(err)
	}
	ga, _ := e.as.get(a.ID)
	gb, _ := e.as.get(b.ID)
	if ga.XP != 30 || memberOf(ga, "MemA").WeekPts != 30 {
		t.Fatalf("A accrual: xp=%d week=%d", ga.XP, memberOf(ga, "MemA").WeekPts)
	}
	// B: 50 last week (XP only) + 40 this week.
	if gb.XP != 90 || memberOf(gb, "MemB").WeekPts != 40 {
		t.Fatalf("B accrual: xp=%d week=%d", gb.XP, memberOf(gb, "MemB").WeekPts)
	}
	// Weekly ranking: B (40) ahead of A (30).
	rows, meA := e.as.RankingWire("MemA")
	if len(rows) != 2 || rows[0]["id"] != b.ID || rows[1]["id"] != a.ID {
		t.Fatalf("ranking order: %v", rows)
	}
	if meA == nil || meA["pos"] != 2 {
		t.Fatalf("me row: %v", meA)
	}
	// Tie on weekly points → total XP breaks it: A banks up
	// to 40 too, B still leads on XP (90 > 40).
	if err := e.acc.RecordMatch("MemA", false); err != nil {
		t.Fatal(err)
	}
	rows, _ = e.as.RankingWire("MemA")
	if rows[0]["id"] != b.ID {
		t.Fatalf("tie-break by XP failed: %v", rows[0])
	}
	// One more A win flips the weekly lead outright.
	if err := e.acc.RecordMatch("MemA", true); err != nil {
		t.Fatal(err)
	}
	rows, _ = e.as.RankingWire("MemA")
	if rows[0]["id"] != a.ID {
		t.Fatalf("weekly lead flip failed: %v", rows[0])
	}
	// A dispute revert un-accrues (never negative).
	if err := e.acc.RecordMatchRevert("MemA", true); err != nil {
		t.Fatal(err)
	}
	ga, _ = e.as.get(a.ID)
	if ga.XP != 40 || memberOf(ga, "MemA").WeekPts != 40 {
		t.Fatalf("after revert: xp=%d week=%d", ga.XP, memberOf(ga, "MemA").WeekPts)
	}
	// Non-members accrue nothing anywhere.
	if err := e.acc.RecordMatch("BossA", true); err != nil { // BossA IS a member (leader)
		t.Fatal(err)
	}
	ga, _ = e.as.get(a.ID)
	if memberOf(ga, "BossA").WeekPts != 30 {
		t.Fatalf("leader accrual: %d", memberOf(ga, "BossA").WeekPts)
	}
	// Next Monday the weekly points read as 0 (lazy reset)
	// while the alliance XP total stands.
	*e.clock = time.Date(2026, 11, 16, 9, 0, 0, 0, time.UTC)
	mine, _ := e.as.HomeFor("MemA", nil)
	if mine == nil || mine["week"] != 0 || mine["xp"] != 70 {
		t.Fatalf("after rollover: week=%v xp=%v", mine["week"], mine["xp"])
	}
}

func TestAllianceChatMemberOnly(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Mate", "Outsider")
	a := e.mustCreate(t, "Boss", "Hội Chat", AllianceModeOpen)
	if err := e.as.Apply(a.ID, "Mate", ""); err != nil {
		t.Fatal(err)
	}
	bossFS, mateFS, outFS := &fakeSender{}, &fakeSender{}, &fakeSender{}
	e.hub.RegisterUserConn("Boss", bossFS)
	e.hub.RegisterUserConn("Mate", mateFS)
	e.hub.RegisterUserConn("Outsider", outFS)
	members := e.as.MemberUsers(a.ID)
	e.hub.RelayAllianceChat("Boss", "Boss", a.ID, members, "Xin chào liên minh")
	for name, fs := range map[string]*fakeSender{"boss": bossFS, "mate": mateFS} {
		chats := fs.ofType("chat")
		if len(chats) != 1 || chats[0]["scope"] != "alliance" || chats[0]["text"] != "Xin chào liên minh" {
			t.Fatalf("%s chats: %v", name, chats)
		}
	}
	if got := outFS.ofType("chat"); len(got) != 0 {
		t.Fatalf("outsider received alliance chat: %v", got)
	}
	// Rate limit: past ChatRateCount in the window, lines drop.
	for i := 0; i < ChatRateCount+3; i++ {
		e.hub.RelayAllianceChat("Mate", "Mate", a.ID, members, fmt.Sprintf("line %d", i))
	}
	if got := len(mateFS.ofType("chat")); got != 1+ChatRateCount {
		t.Fatalf("mate chat count = %d, want %d", got, 1+ChatRateCount)
	}
	// Unregistering one session stops its deliveries.
	id := e.hub.RegisterUserConn("Mate", mateFS)
	e.hub.UnregisterUserConn("Mate", id)
}

func TestAllianceHomeAndListWire(t *testing.T) {
	e := allySetup(t)
	e.reg(t, "Boss", "Seeker")
	a := e.mustCreate(t, "Boss", "Hội Tìm", AllianceModeRequest)
	mine, invites := e.as.HomeFor("Seeker", nil)
	if mine != nil || len(invites) != 0 {
		t.Fatalf("seeker home: mine=%v invites=%v", mine, invites)
	}
	rows := e.as.ListWire("Seeker", "")
	if len(rows) != 1 || rows[0]["id"] != a.ID || rows[0]["requested"] != false {
		t.Fatalf("list rows: %v", rows)
	}
	if err := e.as.Apply(a.ID, "Seeker", ""); err != nil {
		t.Fatal(err)
	}
	rows = e.as.ListWire("Seeker", "tìm")
	if len(rows) != 1 || rows[0]["requested"] != true {
		t.Fatalf("list after apply: %v", rows)
	}
	if rows := e.as.ListWire("Seeker", "không có"); len(rows) != 0 {
		t.Fatalf("search filter: %v", rows)
	}
	mine, _ = e.as.HomeFor("Boss", nil)
	if mine == nil || mine["my_role"] != AllianceRoleLeader || mine["requests_count"] != 1 {
		t.Fatalf("boss home: %v", mine)
	}
}
