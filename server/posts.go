package main

// Empire Age 17f — SOCIAL POSTS: the profile page's MXH
// column (Bảng tin / Tường nhà / Album ảnh) and the alliance
// screen's Bài viết tab run on this one service.
//
// A post is a short text (≤ PostTextMax runes) with an
// optional attached image from the game's own art gallery
// ("art:NN" anime avatars, "hero:<id>" hero portraits — no
// user uploads here; the only user picture in the system is
// the §5 avatar photo). Scope decides the audience:
//
//   - Scope "" (personal): the author's wall. Visible in the
//     author's own wall AND in the newsfeed of the author and
//     their FRIENDS (the account Friends list) — nobody else.
//   - Scope = alliance id: an alliance post. Visible ONLY to
//     current members of that alliance (enforced again on
//     every read, so a player who left loses access at once).
//
// Likes are a per-post set of usernames with toggle
// semantics. Deletes: the author anywhere; in an alliance,
// the leader + deputies may also delete (moderation — the
// handler resolves the role and passes canModerate).
//
// Storage caps: PostWallCap personal posts per author and
// PostAllyCap per alliance are kept (oldest pruned on
// create). Feeds return at most PostFeedCap rows. All of
// this is lobby/social data — nothing here touches a room,
// the lockstep sim or any checksum.

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	PostTextMax = 300 // runes
	PostFeedCap = 50
	PostWallCap = 100
	PostAllyCap = 100
	// PostScopePersonal is the wire value for a wall post.
	PostScopePersonal = ""
)

var (
	ErrPostEmpty     = errors.New("Bài viết trống — hãy viết gì đó hoặc đính kèm ảnh")
	ErrPostTooLong   = errors.New("Bài viết quá dài (tối đa 300 ký tự)")
	ErrPostBadImage  = errors.New("Ảnh đính kèm không hợp lệ")
	ErrPostNotFound  = errors.New("Không tìm thấy bài viết")
	ErrPostForbidden = errors.New("Bạn không có quyền với bài viết này")
	ErrPostRate      = errors.New("Đăng bài quá nhanh — chờ một chút")
)

// Post is one persisted social post (see the file header).
type Post struct {
	ID     string   `json:"id"`
	Author string   `json:"author"` // username
	Scope  string   `json:"scope"`  // "" personal | alliance id
	Text   string   `json:"text"`
	Image  string   `json:"image,omitempty"` // "art:NN" | "hero:<id>"
	At     int64    `json:"at"`              // unix seconds
	Seq    int64    `json:"seq"`             // service-monotonic tiebreak
	Likes  []string `json:"likes,omitempty"` // usernames
}

// ValidPostImage validates an attached-image id against the
// game's gallery: the twenty anime avatars + the eight hero
// portraits. "" (no image) is always valid.
func ValidPostImage(id string) bool {
	if id == "" {
		return true
	}
	if avatarIDSet[id] {
		return true
	}
	if strings.HasPrefix(id, "hero:") {
		return mainCharIDs[strings.TrimPrefix(id, "hero:")]
	}
	return false
}

// Posts is the social-posts service over the Store,
// following the DMs/Alliances service pattern.
type Posts struct {
	store Store
	acc   *Accounts
	mu    sync.Mutex
	now   func() time.Time
	seq   int64
}

func NewPosts(store Store, acc *Accounts) *Posts {
	ps := &Posts{store: store, acc: acc, now: time.Now}
	// Seed the tiebreak counter past anything persisted so a
	// restart never reorders same-second posts backwards.
	for _, p := range store.Posts() {
		if p.Seq > ps.seq {
			ps.seq = p.Seq
		}
	}
	return ps
}

func sortPostsNewest(posts []*Post) {
	sort.SliceStable(posts, func(i, j int) bool {
		if posts[i].At != posts[j].At {
			return posts[i].At > posts[j].At
		}
		return posts[i].Seq > posts[j].Seq
	})
}

// Create stores one post. scope is PostScopePersonal or an
// alliance id (the handler has already verified membership
// for alliance scope). Text may be empty when an image is
// attached; both empty is rejected.
func (ps *Posts) Create(author, scope, text, image string) (*Post, error) {
	text = strings.TrimSpace(text)
	if !ValidPostImage(image) {
		return nil, ErrPostBadImage
	}
	if text == "" && image == "" {
		return nil, ErrPostEmpty
	}
	if utf8.RuneCountInString(text) > PostTextMax {
		return nil, ErrPostTooLong
	}
	text = SanitizeEmotes(text)
	ps.mu.Lock()
	defer ps.mu.Unlock()
	ps.seq++
	var rnd [6]byte
	_, _ = rand.Read(rnd[:])
	p := &Post{
		ID:     hex.EncodeToString(rnd[:]) + "-" + author,
		Author: author,
		Scope:  scope,
		Text:   text,
		Image:  image,
		At:     ps.now().Unix(),
		Seq:    ps.seq,
	}
	if err := ps.store.PutPost(p); err != nil {
		return nil, err
	}
	ps.pruneLocked(scope, author)
	return p, nil
}

// pruneLocked enforces the per-wall / per-alliance storage
// caps after a create (oldest posts drop first).
func (ps *Posts) pruneLocked(scope, author string) {
	var mine []*Post
	for _, p := range ps.store.Posts() {
		if p.Scope != scope {
			continue
		}
		if scope == PostScopePersonal && p.Author != author {
			continue
		}
		mine = append(mine, p)
	}
	capN := PostAllyCap
	if scope == PostScopePersonal {
		capN = PostWallCap
	}
	if len(mine) <= capN {
		return
	}
	sortPostsNewest(mine) // newest first; the tail is pruned
	for _, p := range mine[capN:] {
		_ = ps.store.DeletePost(p.ID)
	}
}

// WallOf returns one author's personal posts, newest first.
func (ps *Posts) WallOf(author string) []*Post {
	out := []*Post{}
	for _, p := range ps.store.Posts() {
		if p.Scope == PostScopePersonal && p.Author == author {
			out = append(out, p)
		}
	}
	sortPostsNewest(out)
	return out
}

// FeedFor returns the caller's newsfeed: their own personal
// posts + their friends' personal posts, newest first,
// capped at PostFeedCap. Alliance posts never appear here.
func (ps *Posts) FeedFor(user string) []*Post {
	authors := map[string]bool{user: true}
	if ps.acc != nil {
		for _, f := range ps.acc.FriendsOf(user) {
			authors[f.User] = true
		}
	}
	out := []*Post{}
	for _, p := range ps.store.Posts() {
		if p.Scope == PostScopePersonal && authors[p.Author] {
			out = append(out, p)
		}
	}
	sortPostsNewest(out)
	if len(out) > PostFeedCap {
		out = out[:PostFeedCap]
	}
	return out
}

// AlliancePosts returns one alliance's posts, newest first.
// Membership is the CALLER's job (the handler checks the
// reader belongs before asking) — scope isolation lives in
// the handler + in TestPostAllianceScopeIsolation.
func (ps *Posts) AlliancePosts(allyID string) []*Post {
	out := []*Post{}
	for _, p := range ps.store.Posts() {
		if p.Scope == allyID && allyID != "" {
			out = append(out, p)
		}
	}
	sortPostsNewest(out)
	if len(out) > PostAllyCap {
		out = out[:PostAllyCap]
	}
	return out
}

// Get returns one post by id.
func (ps *Posts) Get(id string) (*Post, bool) {
	return ps.store.GetPost(id)
}

// ToggleLike flips the caller's like on a post and returns
// the updated post. Toggling is idempotent per call pair:
// like → unlike → like …
func (ps *Posts) ToggleLike(id, user string) (*Post, error) {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	p, ok := ps.store.GetPost(id)
	if !ok {
		return nil, ErrPostNotFound
	}
	found := false
	likes := p.Likes[:0]
	for _, u := range p.Likes {
		if u == user {
			found = true
			continue
		}
		likes = append(likes, u)
	}
	if !found {
		likes = append(likes, user)
	}
	p.Likes = likes
	if err := ps.store.PutPost(p); err != nil {
		return nil, err
	}
	return p, nil
}

// Delete removes a post. The author may always delete;
// canModerate (resolved by the handler: alliance leader /
// deputy for alliance-scope posts) extends the right.
func (ps *Posts) Delete(id, actor string, canModerate bool) error {
	ps.mu.Lock()
	defer ps.mu.Unlock()
	p, ok := ps.store.GetPost(id)
	if !ok {
		return ErrPostNotFound
	}
	if p.Author != actor && !canModerate {
		return ErrPostForbidden
	}
	return ps.store.DeletePost(id)
}

// Wire renders one post for a viewer: author identity is
// resolved server-side (display name, effective avatar —
// "custom" included — effective frame, alliance tag), plus
// the like count and the viewer's own like state.
func (ps *Posts) Wire(p *Post, viewer string) map[string]any {
	name := p.Author
	avatar, frame, tag := AvatarDefaultID, "", ""
	if ps.acc != nil {
		name = ps.acc.DisplayNameOf(p.Author)
		avatar = ps.acc.AvatarOf(p.Author)
		frame = ps.acc.EquippedFrameOf(p.Author)
		if ps.acc.AllyTagOf != nil {
			tag = ps.acc.AllyTagOf(p.Author)
		}
	}
	liked := false
	for _, u := range p.Likes {
		if u == viewer {
			liked = true
			break
		}
	}
	return map[string]any{
		"id": p.ID, "author": p.Author, "author_name": name,
		"avatar_id": avatar, "frame_id": frame, "ally_tag": tag,
		"scope": p.Scope, "text": p.Text, "image": p.Image,
		"at": p.At, "likes": len(p.Likes), "liked": liked,
		"mine": p.Author == viewer,
	}
}

// WireList renders a page of posts for a viewer.
func (ps *Posts) WireList(posts []*Post, viewer string) []map[string]any {
	out := make([]map[string]any, 0, len(posts))
	for _, p := range posts {
		out = append(out, ps.Wire(p, viewer))
	}
	return out
}

// GatePostCreate spends one slot of the caller's post-create
// budget — the same sliding window shape as chat (ChatRate
// Count per ChatRateWindow), on its own window so posting
// never eats the chat budget. False = over budget; the
// handler answers with ErrPostRate instead of dropping
// silently (a post is a deliberate action, not a chat line).
func (h *Hub) GatePostCreate(user string) bool {
	h.userMu.Lock()
	defer h.userMu.Unlock()
	if h.postWin == nil {
		h.postWin = make(map[string][]time.Time)
	}
	return h.chatGateLocked(h.postWin, user)
}
