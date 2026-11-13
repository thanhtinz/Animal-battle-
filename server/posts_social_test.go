package main

// Empire Age 17g tests: post reports (once/idempotent +
// wire state), two-level comments (nesting, reply-to-reply
// root resolution + @prefix, delete permissions, cap +
// validation), scope visibility at the wire, and shares
// (wall + alliance, snapshot payload, deleted original,
// share of a share).

import (
	"strings"
	"testing"
)

func TestPostReportIdempotent(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	regUser(t, acc, "RepA")
	regUser(t, acc, "RepB")
	p, _ := ps.Create("RepA", "", "bài bị báo cáo", "")
	up, err := ps.Report(p.ID, "RepB")
	if err != nil || len(up.Reports) != 1 {
		t.Fatalf("first report: %v reports=%v", err, up.Reports)
	}
	// A second report by the same account is a no-op success.
	up, err = ps.Report(p.ID, "RepB")
	if err != nil || len(up.Reports) != 1 {
		t.Fatalf("repeat report: %v reports=%v", err, up.Reports)
	}
	// Reporting your own post records nothing.
	up, err = ps.Report(p.ID, "RepA")
	if err != nil || len(up.Reports) != 1 {
		t.Fatalf("own report: %v reports=%v", err, up.Reports)
	}
	// The wire carries the viewer's own state only.
	if w := ps.Wire(up, "RepB"); w["reported_by_me"] != true {
		t.Fatalf("reporter wire: %v", w)
	}
	if w := ps.Wire(up, "RepA"); w["reported_by_me"] != false {
		t.Fatalf("author wire: %v", w)
	}
	if _, err := ps.Report("nope", "RepB"); err != ErrPostNotFound {
		t.Fatalf("report missing post: %v", err)
	}
	// Reports persist across a service reload (same store).
	ps2 := NewPosts(ps.store, acc)
	got, ok := ps2.Get(p.ID)
	if !ok || len(got.Reports) != 1 {
		t.Fatalf("persisted reports: %v %+v", ok, got)
	}
}

func TestCommentThreadingAndReplyResolution(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	for _, u := range []string{"CmA", "CmB", "CmC"} {
		regUser(t, acc, u)
	}
	p, _ := ps.Create("CmA", "", "bài có bình luận", "")
	top, err := ps.AddComment(p, "CmB", "", "Bình luận đầu tiên")
	if err != nil || top.ParentID != "" || !strings.HasPrefix(top.ID, "c") {
		t.Fatalf("top comment: %v %+v", err, top)
	}
	// A reply to the top-level comment attaches to it,
	// with NO mention prefix (direct parent).
	rep, err := ps.AddComment(p, "CmA", top.ID, "Cảm ơn bạn")
	if err != nil || rep.ParentID != top.ID || rep.Text != "Cảm ơn bạn" {
		t.Fatalf("reply: %v %+v", err, rep)
	}
	// A reply to a REPLY resolves to the same root and the
	// stored text gains the "@<display name> " prefix.
	rep2, err := ps.AddComment(p, "CmC", rep.ID, "Mình cũng vậy")
	if err != nil {
		t.Fatal(err)
	}
	wantPrefix := "@" + acc.DisplayNameOf("CmA") + " "
	if rep2.ParentID != top.ID {
		t.Fatalf("reply-to-reply parent = %q, want root %q", rep2.ParentID, top.ID)
	}
	if !strings.HasPrefix(rep2.Text, wantPrefix) {
		t.Fatalf("reply-to-reply text = %q, want prefix %q", rep2.Text, wantPrefix)
	}
	// The flat list comes back in creation order and the
	// wire nests via parent_id; count includes replies.
	rows := ps.WireComments(p, "CmB", false)
	if len(rows) != 3 {
		t.Fatalf("thread rows = %d, want 3", len(rows))
	}
	if rows[0]["id"] != top.ID || rows[1]["id"] != rep.ID || rows[2]["id"] != rep2.ID {
		t.Fatalf("thread order: %v %v %v", rows[0]["id"], rows[1]["id"], rows[2]["id"])
	}
	if w := ps.Wire(p, "CmB"); w["comments"] != 3 {
		t.Fatalf("post wire comment count: %v", w)
	}
	// The comment author can delete their own; the post
	// author can delete anyone's (thread moderation).
	if rows[0]["can_delete"] != true { // CmB views own top comment
		t.Fatalf("own comment can_delete: %v", rows[0])
	}
	rowsA := ps.WireComments(p, "CmA", false)
	if rowsA[0]["can_delete"] != true {
		t.Fatalf("post author can_delete: %v", rowsA[0])
	}
}

func TestCommentValidation(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	regUser(t, acc, "ValA")
	regUser(t, acc, "ValB")
	p, _ := ps.Create("ValA", "", "bài kiểm tra", "")
	other, _ := ps.Create("ValA", "", "bài khác", "")
	if _, err := ps.AddComment(p, "ValB", "", "   "); err != ErrCommentEmpty {
		t.Fatalf("empty comment: %v", err)
	}
	if _, err := ps.AddComment(p, "ValB", "", strings.Repeat("x", CommentTextMax+1)); err != ErrCommentTooLong {
		t.Fatalf("long comment: %v", err)
	}
	if _, err := ps.AddComment(p, "ValB", "", strings.Repeat("y", CommentTextMax)); err != nil {
		t.Fatalf("at-cap comment: %v", err)
	}
	if _, err := ps.AddComment(p, "ValB", "c-khong-co", "chào"); err != ErrCommentBadParent {
		t.Fatalf("unknown parent: %v", err)
	}
	// A parent from ANOTHER post is refused.
	oc, _ := ps.AddComment(other, "ValB", "", "bình luận bài khác")
	if _, err := ps.AddComment(p, "ValB", oc.ID, "nhầm bài"); err != ErrCommentBadParent {
		t.Fatalf("cross-post parent: %v", err)
	}
}

func TestCommentCap(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	regUser(t, acc, "CapA")
	p, _ := ps.Create("CapA", "", "bài đông khách", "")
	for i := 0; i < PostCommentCap; i++ {
		if _, err := ps.AddComment(p, "CapA", "", "c"); err != nil {
			t.Fatalf("comment %d: %v", i, err)
		}
	}
	if _, err := ps.AddComment(p, "CapA", "", "quá tải"); err != ErrCommentFull {
		t.Fatalf("past-cap comment: %v", err)
	}
	// Deleting the post purges its comments.
	if err := ps.Delete(p.ID, "CapA", false); err != nil {
		t.Fatal(err)
	}
	if got := ps.CommentCount(p.ID); got != 0 {
		t.Fatalf("comments after post delete = %d, want 0", got)
	}
}

func TestCommentDeletePermissions(t *testing.T) {
	ps, acc, allis, _ := postsSetup(t)
	for _, u := range []string{"CdLead", "CdDep", "CdMem", "CdStranger"} {
		regUser(t, acc, u)
	}
	al, err := allis.Create("CdLead", "Hội Bình Luận", "CDBL", 1, 0, "open", "")
	if err != nil {
		t.Fatal(err)
	}
	for _, u := range []string{"CdDep", "CdMem"} {
		if err := allis.Apply(al.ID, u, ""); err != nil {
			t.Fatal(err)
		}
	}
	if err := allis.SetRole(al.ID, "CdLead", "CdDep", AllianceRoleDeputy); err != nil {
		t.Fatal(err)
	}
	// Personal post: a stranger may NOT delete a comment;
	// the comment author and the post author may.
	p, _ := ps.Create("CdMem", "", "tường nhà", "")
	cm, _ := ps.AddComment(p, "CdLead", "", "ghé thăm")
	if _, err := ps.DeleteComment(cm.ID, "CdStranger", false); err != ErrPostForbidden {
		t.Fatalf("stranger comment delete: %v", err)
	}
	if _, err := ps.DeleteComment(cm.ID, "CdMem", false); err != nil {
		t.Fatalf("post author comment delete: %v", err)
	}
	// Alliance post: a deputy moderates comments.
	ap, _ := ps.Create("CdMem", al.ID, "bài trong hội", "")
	ac1, _ := ps.AddComment(ap, "CdLead", "", "lãnh đạo nói")
	ac2, _ := ps.AddComment(ap, "CdMem", ac1.ID, "thành viên đáp")
	if _, err := ps.DeleteComment(ac1.ID, "CdDep", true); err != nil {
		t.Fatalf("deputy comment delete: %v", err)
	}
	// …and deleting the top-level took its reply along.
	if got := ps.CommentCount(ap.ID); got != 0 {
		t.Fatalf("comments after cascade delete = %d, want 0 (reply %v gone)", got, ac2.ID)
	}
	if _, err := ps.DeleteComment("c-khong-co", "CdLead", false); err != ErrCommentNotFound {
		t.Fatalf("delete missing comment: %v", err)
	}
}

// ------------------------------------------------------------ shares

func TestSharePostSnapshotAndGone(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	regUser(t, acc, "ShA")
	regUser(t, acc, "ShB")
	orig, _ := ps.Create("ShA", "", "Nội dung gốc [e:vui]", "art:07")
	sh, err := ps.SharePost(orig, "ShB", "")
	if err != nil {
		t.Fatal(err)
	}
	if sh.Author != "ShB" || sh.SharedFrom == nil ||
		sh.SharedFrom.OrigPostID != orig.ID || sh.Text != "" {
		t.Fatalf("share record: %+v", sh)
	}
	// The wire embeds the original's CURRENT content.
	w := ps.Wire(sh, "ShB")
	if w["shared"] != true || w["orig_gone"] != false ||
		w["orig_text"] != orig.Text || w["orig_image"] != "art:07" ||
		w["orig_author"] != "ShA" || w["orig_author_name"] == "" {
		t.Fatalf("share wire: %v", w)
	}
	// The share shows on the sharer's wall.
	if got := ps.WallOf("ShB"); len(got) != 1 || got[0].ID != sh.ID {
		t.Fatalf("sharer wall: %v", got)
	}
	// Deleting the original flips the share to orig_gone,
	// keeping the snapshot identity.
	if err := ps.Delete(orig.ID, "ShA", false); err != nil {
		t.Fatal(err)
	}
	w = ps.Wire(sh, "ShB")
	if w["orig_gone"] != true || w["orig_author"] != "ShA" {
		t.Fatalf("gone share wire: %v", w)
	}
}

func TestShareOfShareResolvesToOriginal(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	for _, u := range []string{"SsA", "SsB", "SsC"} {
		regUser(t, acc, u)
	}
	orig, _ := ps.Create("SsA", "", "gốc", "")
	sh1, err := ps.SharePost(orig, "SsB", "")
	if err != nil {
		t.Fatal(err)
	}
	sh2, err := ps.SharePost(sh1, "SsC", "")
	if err != nil {
		t.Fatal(err)
	}
	if sh2.SharedFrom.OrigPostID != orig.ID || sh2.SharedFrom.OrigAuthor != "SsA" {
		t.Fatalf("share-of-share ref: %+v", sh2.SharedFrom)
	}
	if w := ps.Wire(sh2, "SsC"); w["orig_text"] != "gốc" || w["orig_gone"] != false {
		t.Fatalf("share-of-share wire: %v", w)
	}
}

// ------------------------------------------------------------ wire level

func TestPostSocialWireVisibility(t *testing.T) {
	srv, acc, allis, _ := postsWireSetup(t)
	url := srv.URL + "/ws"
	reg := func(user string) *wsTestClient {
		c := dialWS(t, url)
		c.send(t, map[string]any{"t": "register", "user": user, "pass": "secret1"})
		c.recvUntil(t, "auth_ok")
		return c
	}
	a := reg("SocPoster")
	defer a.conn.Close()
	b := reg("SocFriend")
	defer b.conn.Close()
	c := reg("SocStranger")
	defer c.conn.Close()
	// B has A in B's friend list → B can see A's wall posts.
	// C has nobody → C sees nothing of A's.
	if err := acc.AddFriend("SocFriend", "SocPoster"); err != nil {
		t.Fatal(err)
	}

	a.send(t, map[string]any{"t": "post_create", "text": "bài để bình luận"})
	created := a.recvUntil(t, "post_created")
	post, _ := created["post"].(map[string]any)
	postID, _ := post["id"].(string)
	if postID == "" {
		t.Fatalf("created: %v", created)
	}

	// The stranger is refused on every interaction.
	c.send(t, map[string]any{"t": "post_comments", "post_id": postID})
	if e := c.recvUntil(t, "error"); !strings.Contains(e["msg"].(string), "quyền") {
		t.Fatalf("stranger comments read: %v", e)
	}
	c.send(t, map[string]any{"t": "post_comment", "post_id": postID, "text": "ké"})
	_ = c.recvUntil(t, "error")
	c.send(t, map[string]any{"t": "post_report", "post_id": postID})
	_ = c.recvUntil(t, "error")
	c.send(t, map[string]any{"t": "post_share", "post_id": postID, "target": "wall"})
	_ = c.recvUntil(t, "error")

	// The friend reads, comments, replies, reports (twice —
	// idempotent), and shares to their wall.
	b.send(t, map[string]any{"t": "post_comments", "post_id": postID})
	if rows := b.recvUntil(t, "post_comments")["rows"].([]any); len(rows) != 0 {
		t.Fatalf("fresh thread rows = %d", len(rows))
	}
	b.send(t, map[string]any{"t": "post_comment", "post_id": postID, "text": "Bạn B đây"})
	rows := b.recvUntil(t, "post_comments")["rows"].([]any)
	if len(rows) != 1 {
		t.Fatalf("thread after comment = %d rows", len(rows))
	}
	topID, _ := rows[0].(map[string]any)["id"].(string)
	a.send(t, map[string]any{"t": "post_comment", "post_id": postID,
		"parent_id": topID, "text": "Chủ bài đáp"})
	rows = a.recvUntil(t, "post_comments")["rows"].([]any)
	if len(rows) != 2 || rows[1].(map[string]any)["parent_id"] != topID {
		t.Fatalf("thread after reply: %v", rows)
	}
	b.send(t, map[string]any{"t": "post_report", "post_id": postID})
	rep := b.recvUntil(t, "post_report")["post"].(map[string]any)
	if rep["reported_by_me"] != true {
		t.Fatalf("report wire: %v", rep)
	}
	b.send(t, map[string]any{"t": "post_report", "post_id": postID})
	rep = b.recvUntil(t, "post_report")["post"].(map[string]any)
	if rep["reported_by_me"] != true {
		t.Fatalf("repeat report wire: %v", rep)
	}
	b.send(t, map[string]any{"t": "post_share", "post_id": postID, "target": "wall"})
	shared := b.recvUntil(t, "post_created")["post"].(map[string]any)
	if shared["shared"] != true || shared["orig_author"] != "SocPoster" ||
		shared["orig_text"] != "bài để bình luận" {
		t.Fatalf("friend share wire: %v", shared)
	}
	// Sharing into an alliance without one is refused.
	b.send(t, map[string]any{"t": "post_share", "post_id": postID, "target": "alliance"})
	if e := b.recvUntil(t, "error"); !strings.Contains(e["msg"].(string), "liên minh") {
		t.Fatalf("share without alliance: %v", e)
	}

	// Alliance scope: A leads an alliance, B joins; an
	// alliance post can be shared INSIDE the alliance but
	// never OUT to a wall.
	al, err := allis.Create("SocPoster", "Hội Chia Sẻ", "HCS", 1, 0, "open", "")
	if err != nil {
		t.Fatal(err)
	}
	if err := allis.Apply(al.ID, "SocFriend", ""); err != nil {
		t.Fatal(err)
	}
	a.send(t, map[string]any{"t": "post_create", "scope": "alliance", "text": "bài trong hội"})
	apost := a.recvUntil(t, "post_created")["post"].(map[string]any)
	allyPostID, _ := apost["id"].(string)
	b.send(t, map[string]any{"t": "post_share", "post_id": allyPostID, "target": "wall"})
	if e := b.recvUntil(t, "error"); !strings.Contains(e["msg"].(string), "quyền") {
		t.Fatalf("alliance post shared to wall: %v", e)
	}
	b.send(t, map[string]any{"t": "post_share", "post_id": allyPostID, "target": "alliance"})
	ash := b.recvUntil(t, "post_created")["post"].(map[string]any)
	if ash["shared"] != true || ash["scope"] != al.ID {
		t.Fatalf("alliance share wire: %v", ash)
	}
	// The stranger cannot even read the alliance thread.
	c.send(t, map[string]any{"t": "post_comments", "post_id": allyPostID})
	if e := c.recvUntil(t, "error"); !strings.Contains(e["msg"].(string), "quyền") {
		t.Fatalf("stranger alliance thread: %v", e)
	}
}
