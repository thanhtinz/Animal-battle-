package main

// Empire Age 17g — SOCIAL POST INTERACTIONS on top of the
// 17f posts service: reports, Facebook-style two-level
// comments, and shares (to my wall / to my alliance).
//
//   - REPORT: one report per account per post, recorded on
//     the post record and stored server-side ONLY (no admin
//     UI in this pass). The wire exposes just the viewer's
//     own state (reported_by_me).
//   - COMMENTS: a comment belongs to a post; replies attach
//     to a TOP-LEVEL comment only. Replying to a reply is
//     resolved to that reply's root and the stored text is
//     prefixed "@<display name> " — Facebook's two-level
//     shape. Visibility follows the post's scope exactly:
//     only a user who can SEE the post may read or write
//     its comments (session.canSeePost).
//   - SHARE: creates a NEW post in the target scope with a
//     ShareRef to the (ultimate) original; text/image are
//     resolved at read time (Posts.Wire), so a deleted
//     original renders as a tombstone. An alliance-scoped
//     original can only be shared inside its own alliance
//     (never out to a personal wall — no scope leak).

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	// CommentTextMax caps one comment, in runes.
	CommentTextMax = 200
	// PostCommentCap caps the TOTAL comments (top-level +
	// replies) kept per post; past it, new comments are
	// refused with ErrCommentFull.
	PostCommentCap = 300
)

var (
	ErrCommentEmpty     = errors.New("Bình luận trống")
	ErrCommentTooLong   = errors.New("Bình luận quá dài (tối đa 200 ký tự)")
	ErrCommentFull      = errors.New("Bình luận đã đầy")
	ErrCommentNotFound  = errors.New("Không tìm thấy bình luận")
	ErrCommentBadParent = errors.New("Bình luận gốc không hợp lệ")
	ErrCommentRate      = errors.New("Bình luận quá nhanh — chờ một chút")
	ErrShareNoAlly      = errors.New("Chưa có liên minh")
)

// PostComment is one persisted comment on a social post.
// ParentID is "" for a top-level comment, else the id of a
// TOP-LEVEL comment of the same post (replies never nest
// deeper — see the file header). Image (17h) is an optional
// attached photo: base64 JPEG under the SAME contract as
// chat photos (ValidateChatImage) — the store persists it
// with the comment like any other field.
type PostComment struct {
	ID       string `json:"id"` // "c" prefix
	PostID   string `json:"post_id"`
	ParentID string `json:"parent_id,omitempty"`
	Author   string `json:"author"` // username
	Text     string `json:"text"`
	Image    string `json:"image,omitempty"` // base64 JPEG (17h)
	At       int64  `json:"at"`              // unix seconds
	Seq      int64  `json:"seq"`             // service-monotonic ordering
}

// ------------------------------------------------------------ reports

// Report records the caller's report on a post. One report
// per account per post — repeat calls are no-op successes.
// Reporting your own post is also a no-op (the client never
// offers it). Returns the updated post for the wire reply.
func (ps *Posts) Report(id, user string) (*Post, error) {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	p, ok := ps.store.GetPost(id)
	if !ok {
		return nil, ErrPostNotFound
	}
	if p.Author == user {
		return p, nil
	}
	for _, u := range p.Reports {
		if u == user {
			return p, nil
		}
	}
	p.Reports = append(p.Reports, user)
	if err := ps.store.PutPost(p); err != nil {
		return nil, err
	}
	return p, nil
}

// ------------------------------------------------------------ comments

// commentsOfLocked returns one post's comments in creation
// order (oldest first — conversation order). Caller holds
// ps.mu (read paths take it too, for a consistent view).
func (ps *Posts) commentsOfLocked(postID string) []*PostComment {
	out := []*PostComment{}
	for _, c := range ps.store.PostComments() {
		if c.PostID == postID {
			out = append(out, c)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].At != out[j].At {
			return out[i].At < out[j].At
		}
		return out[i].Seq < out[j].Seq
	})
	return out
}

// GetComment returns one comment by id.
func (ps *Posts) GetComment(id string) (*PostComment, bool) {
	return ps.store.GetPostComment(id)
}

// CommentsOf returns one post's comments, oldest first.
func (ps *Posts) CommentsOf(postID string) []*PostComment {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	return ps.commentsOfLocked(postID)
}

// CommentCount counts ALL comments (incl. replies) on a post.
func (ps *Posts) CommentCount(postID string) int {
	n := 0
	for _, c := range ps.store.PostComments() {
		if c.PostID == postID {
			n++
		}
	}
	return n
}

// AddComment stores one comment on post p. parentID may be
// "" (top level), a top-level comment id, or a REPLY id — a
// reply parent resolves to its top-level root and the text
// gains the "@<display name> " mention prefix (unless it is
// already there). image (17h) is an optional base64 JPEG
// validated by the chat-photo gate (ValidateChatImage);
// an IMAGE-ONLY comment (empty text + valid image) is
// accepted, exactly like a chat photo line.
func (ps *Posts) AddComment(p *Post, author, parentID, text, image string) (*PostComment, error) {
	text = strings.TrimSpace(text)
	if text == "" && image == "" {
		return nil, ErrCommentEmpty
	}
	if utf8.RuneCountInString(text) > CommentTextMax {
		return nil, ErrCommentTooLong
	}
	if image != "" {
		raw, err := base64.StdEncoding.DecodeString(image)
		if err != nil {
			return nil, ErrBadChatImage
		}
		if err := ValidateChatImage(raw); err != nil {
			return nil, err
		}
	}
	ps.mu.Lock()
	defer ps.mu.Unlock()
	if len(ps.commentsOfLocked(p.ID)) >= PostCommentCap {
		return nil, ErrCommentFull
	}
	rootID := ""
	if parentID != "" {
		parent, ok := ps.store.GetPostComment(parentID)
		if !ok || parent.PostID != p.ID {
			return nil, ErrCommentBadParent
		}
		if parent.ParentID == "" {
			rootID = parent.ID
		} else {
			rootID = parent.ParentID
			name := parent.Author
			if ps.acc != nil {
				name = ps.acc.DisplayNameOf(parent.Author)
			}
			prefix := "@" + name + " "
			if !strings.HasPrefix(text, prefix) {
				text = prefix + text
			}
		}
	}
	text = SanitizeEmotes(text)
	ps.seq++
	var rnd [6]byte
	_, _ = rand.Read(rnd[:])
	c := &PostComment{
		ID:       "c" + hex.EncodeToString(rnd[:]) + "-" + author,
		PostID:   p.ID,
		ParentID: rootID,
		Author:   author,
		Text:     text,
		Image:    image,
		At:       ps.now().Unix(),
		Seq:      ps.seq,
	}
	if err := ps.store.PutPostComment(c); err != nil {
		return nil, err
	}
	return c, nil
}

// DeleteComment removes one comment. Allowed for the
// comment's author, the POST's author, or a moderator of
// the post's alliance scope (canModerate, resolved by the
// handler). Deleting a top-level comment deletes its
// replies with it. Returns the owning post's id.
func (ps *Posts) DeleteComment(commentID, actor string, canModerate bool) (string, error) {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	c, ok := ps.store.GetPostComment(commentID)
	if !ok {
		return "", ErrCommentNotFound
	}
	p, pok := ps.store.GetPost(c.PostID)
	if !pok {
		// Orphaned comment (post pruned): only its author
		// may clean it up.
		if c.Author != actor {
			return "", ErrPostForbidden
		}
		_ = ps.store.DeletePostComment(c.ID)
		return c.PostID, nil
	}
	if c.Author != actor && p.Author != actor && !canModerate {
		return "", ErrPostForbidden
	}
	if c.ParentID == "" {
		for _, r := range ps.commentsOfLocked(c.PostID) {
			if r.ParentID == c.ID {
				_ = ps.store.DeletePostComment(r.ID)
			}
		}
	}
	if err := ps.store.DeletePostComment(c.ID); err != nil {
		return "", err
	}
	return c.PostID, nil
}

// purgeCommentsLocked drops every comment of a post (the
// post itself is going away). Caller holds ps.mu.
func (ps *Posts) purgeCommentsLocked(postID string) {
	for _, c := range ps.store.PostComments() {
		if c.PostID == postID {
			_ = ps.store.DeletePostComment(c.ID)
		}
	}
}

// WireComment renders one comment for a viewer: identity
// resolved server-side exactly like post rows, plus the
// viewer's delete right (already resolved by the handler:
// comment author / post author / alliance moderator).
func (ps *Posts) WireComment(c *PostComment, viewer string, canDelete bool) map[string]any {
	name := c.Author
	avatar, frame, tag := AvatarDefaultID, "", ""
	if ps.acc != nil {
		name = ps.acc.DisplayNameOf(c.Author)
		avatar = ps.acc.AvatarOf(c.Author)
		frame = ps.acc.EquippedFrameOf(c.Author)
		if ps.acc.AllyTagOf != nil {
			tag = ps.acc.AllyTagOf(c.Author)
		}
	}
	w := map[string]any{
		"id": c.ID, "post_id": c.PostID, "parent_id": c.ParentID,
		"author": c.Author, "author_name": name,
		"avatar_id": avatar, "frame_id": frame, "ally_tag": tag,
		"text": c.Text, "at": c.At,
		"mine": c.Author == viewer, "can_delete": canDelete,
	}
	if c.Image != "" {
		w["image"] = c.Image
	}
	return w
}

// WireComments renders a post's whole thread for a viewer.
// canModerate is the viewer's alliance-moderation right on
// the post's scope (false for personal posts).
func (ps *Posts) WireComments(p *Post, viewer string, canModerate bool) []map[string]any {
	rows := ps.CommentsOf(p.ID)
	out := make([]map[string]any, 0, len(rows))
	for _, c := range rows {
		canDel := c.Author == viewer || p.Author == viewer || canModerate
		out = append(out, ps.WireComment(c, viewer, canDel))
	}
	return out
}

// ------------------------------------------------------------ shares

// SharePost creates the sharer's share of src in
// targetScope ("" = the sharer's wall, else an alliance
// id). Sharing a share points the new ShareRef at the
// ULTIMATE original (one-level resolution at share time),
// so the embedded card never chains.
func (ps *Posts) SharePost(src *Post, sharer, targetScope string) (*Post, error) {
	ref := &ShareRef{
		OrigPostID: src.ID,
		OrigAuthor: src.Author,
		OrigScope:  src.Scope,
	}
	if ps.acc != nil {
		ref.OrigAuthorName = ps.acc.DisplayNameOf(src.Author)
	} else {
		ref.OrigAuthorName = src.Author
	}
	if src.SharedFrom != nil {
		ref.OrigPostID = src.SharedFrom.OrigPostID
		ref.OrigAuthor = src.SharedFrom.OrigAuthor
		ref.OrigAuthorName = src.SharedFrom.OrigAuthorName
		ref.OrigScope = src.SharedFrom.OrigScope
		if orig, ok := ps.store.GetPost(ref.OrigPostID); ok {
			ref.OrigAuthor = orig.Author
			ref.OrigScope = orig.Scope
			if ps.acc != nil {
				ref.OrigAuthorName = ps.acc.DisplayNameOf(orig.Author)
			}
		}
	}
	ps.mu.Lock()
	defer ps.mu.Unlock()
	ps.seq++
	var rnd [6]byte
	_, _ = rand.Read(rnd[:])
	p := &Post{
		ID:         hex.EncodeToString(rnd[:]) + "-" + sharer,
		Author:     sharer,
		Scope:      targetScope,
		At:         ps.now().Unix(),
		Seq:        ps.seq,
		SharedFrom: ref,
	}
	if err := ps.store.PutPost(p); err != nil {
		return nil, err
	}
	ps.pruneLocked(targetScope, sharer)
	return p, nil
}

// ------------------------------------------------------------ rate gate

// GateComment spends one slot of the caller's CHAT budget
// (the shared world/DM sliding window) — comments are chat
// paced, on purpose (17g brief). False = over budget.
func (h *Hub) GateComment(user string) bool {
	h.userMu.Lock()
	defer h.userMu.Unlock()
	if h.worldChatWin == nil {
		h.worldChatWin = make(map[string][]time.Time)
	}
	return h.chatGateLocked(h.worldChatWin, user)
}

// ------------------------------------------------------------ handlers

// canSeePost reports whether the caller may see a post at
// all — the one visibility rule comments/reports/shares
// all follow: alliance posts → current members only;
// personal posts → the author, or anyone who has the
// author in THEIR friend list (the feed rule).
func (s *session) canSeePost(p *Post) bool {
	if p.Scope != PostScopePersonal {
		return s.postScopeMember(p.Scope)
	}
	if p.Author == s.user {
		return true
	}
	if s.acc == nil {
		return false
	}
	for _, f := range s.acc.FriendsOf(s.user) {
		if f.User == p.Author {
			return true
		}
	}
	return false
}

// sendThread pushes a post's full comment thread to the
// caller (the one reply shape of every comment op).
func (s *session) sendThread(p *Post) {
	mod := p.Scope != PostScopePersonal && s.postScopeModerator(p.Scope)
	s.sendJSON(map[string]any{"t": "post_comments", "post_id": p.ID,
		"rows": s.hub.posts.WireComments(p, s.user, mod)})
}

// handlePostSocial serves the 17g ops (dispatch has already
// checked login + a live posts service).
func (s *session) handlePostSocial(m clientMsg) {
	ps := s.hub.posts
	switch m.T {
	case "post_report":
		p, ok := ps.Get(m.PostID)
		if !ok {
			s.sendErr(ErrPostNotFound)
			return
		}
		if !s.canSeePost(p) {
			s.sendErr(ErrPostForbidden)
			return
		}
		up, err := ps.Report(m.PostID, s.user)
		if err != nil {
			s.sendErr(err)
			return
		}
		s.sendJSON(map[string]any{"t": "post_report", "post": ps.Wire(up, s.user)})
	case "post_comments":
		p, ok := ps.Get(m.PostID)
		if !ok {
			s.sendErr(ErrPostNotFound)
			return
		}
		if !s.canSeePost(p) {
			s.sendErr(ErrPostForbidden)
			return
		}
		s.sendThread(p)
	case "post_comment":
		p, ok := ps.Get(m.PostID)
		if !ok {
			s.sendErr(ErrPostNotFound)
			return
		}
		if !s.canSeePost(p) {
			s.sendErr(ErrPostForbidden)
			return
		}
		if !s.hub.GateComment(s.user) {
			s.sendErr(ErrCommentRate)
			return
		}
		if _, err := ps.AddComment(p, s.user, m.ParentID, m.Text, m.Jpg); err != nil {
			s.sendErr(err)
			return
		}
		s.sendThread(p)
	case "post_comment_delete":
		c, ok := ps.GetComment(m.CommentID)
		if !ok {
			s.sendErr(ErrCommentNotFound)
			return
		}
		p, pok := ps.Get(c.PostID)
		if !pok {
			// Orphan: the service still lets the author
			// clean up; visibility no longer applies.
			if _, err := ps.DeleteComment(m.CommentID, s.user, false); err != nil {
				s.sendErr(err)
				return
			}
			s.sendJSON(map[string]any{"t": "post_comments",
				"post_id": c.PostID, "rows": []map[string]any{}})
			return
		}
		mod := p.Scope != PostScopePersonal && s.postScopeModerator(p.Scope)
		if _, err := ps.DeleteComment(m.CommentID, s.user, mod); err != nil {
			s.sendErr(err)
			return
		}
		s.sendThread(p)
	case "post_share":
		p, ok := ps.Get(m.PostID)
		if !ok {
			s.sendErr(ErrPostNotFound)
			return
		}
		if !s.canSeePost(p) {
			s.sendErr(ErrPostForbidden)
			return
		}
		scope := PostScopePersonal
		switch m.Target {
		case "wall":
			// Alliance content never leaves its alliance.
			if p.Scope != PostScopePersonal {
				s.sendErr(ErrPostForbidden)
				return
			}
		case "alliance":
			id := postAllianceID(s)
			if id == "" {
				s.sendErr(ErrShareNoAlly)
				return
			}
			// An alliance post may only be re-shared
			// inside its OWN alliance.
			if p.Scope != PostScopePersonal && p.Scope != id {
				s.sendErr(ErrPostForbidden)
				return
			}
			scope = id
		default:
			s.sendErr(ErrPostForbidden)
			return
		}
		if !s.hub.GatePostCreate(s.user) {
			s.sendErr(ErrPostRate)
			return
		}
		np, err := ps.SharePost(p, s.user, scope)
		if err != nil {
			s.sendErr(err)
			return
		}
		s.sendJSON(map[string]any{"t": "post_created", "post": ps.Wire(np, s.user)})
	}
}
