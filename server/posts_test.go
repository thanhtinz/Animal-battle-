package main

// Empire Age 17f tests: social posts — create validation,
// feed composition (friends only), like toggle semantics,
// delete permissions incl. alliance moderation, alliance
// scope isolation, the create rate budget — and the §5
// custom avatar (upload validation, fetch round-trip,
// persistence across a store reload, catalogue re-equip).

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func postsSetup(t *testing.T) (*Posts, *Accounts, *Alliances, Store) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc := NewAccounts(fs)
	allis := NewAlliances(fs, acc)
	acc.AllyTagOf = allis.TagOf
	return NewPosts(fs, acc), acc, allis, fs
}

func regUser(t *testing.T, acc *Accounts, user string) {
	t.Helper()
	if err := acc.Register(user, "secret1"); err != nil {
		t.Fatal(err)
	}
}

func TestPostCreateValidation(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	regUser(t, acc, "Poster")
	if _, err := ps.Create("Poster", "", "   ", ""); err != ErrPostEmpty {
		t.Fatalf("empty post: %v", err)
	}
	if _, err := ps.Create("Poster", "", "", "art:99"); err != ErrPostBadImage {
		t.Fatalf("bad art id: %v", err)
	}
	if _, err := ps.Create("Poster", "", "", "hero:nobody"); err != ErrPostBadImage {
		t.Fatalf("bad hero id: %v", err)
	}
	if _, err := ps.Create("Poster", "", strings.Repeat("a", PostTextMax+1), ""); err != ErrPostTooLong {
		t.Fatalf("too long: %v", err)
	}
	// Image-only and hero-image posts are valid.
	p, err := ps.Create("Poster", "", "", "art:07")
	if err != nil || p.Image != "art:07" {
		t.Fatalf("image-only post: %v %+v", err, p)
	}
	if _, err := ps.Create("Poster", "", "tướng mới", "hero:knight"); err != nil {
		t.Fatalf("hero image post: %v", err)
	}
	// Exactly at the cap is fine.
	if _, err := ps.Create("Poster", "", strings.Repeat("b", PostTextMax), ""); err != nil {
		t.Fatalf("at-cap post: %v", err)
	}
}

func TestPostFeedFriendsOnly(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	for _, u := range []string{"FeedA", "FeedB", "FeedC"} {
		regUser(t, acc, u)
	}
	// The game's friend list is one-directional (friend_add
	// appends to the caller's list): B has A in their list,
	// C is in nobody's list. The feed = my posts + the posts
	// of the accounts in MY friend list.
	if err := acc.AddFriend("FeedB", "FeedA"); err != nil {
		t.Fatal(err)
	}
	pa, _ := ps.Create("FeedA", "", "bài của A", "")
	pb, _ := ps.Create("FeedB", "", "bài của B", "")
	if _, err := ps.Create("FeedC", "", "bài của C", ""); err != nil {
		t.Fatal(err)
	}
	feedB := ps.FeedFor("FeedB")
	if len(feedB) != 2 {
		t.Fatalf("B feed = %d posts, want 2 (own + friend)", len(feedB))
	}
	// A does NOT have B in their list: A's feed is A only.
	if got := len(ps.FeedFor("FeedA")); got != 1 {
		t.Fatalf("A feed = %d, want 1 (directional list)", got)
	}
	// Newest first.
	if feedB[0].ID != pb.ID || feedB[1].ID != pa.ID {
		t.Fatalf("feed order wrong: %s then %s", feedB[0].ID, feedB[1].ID)
	}
	if got := len(ps.FeedFor("FeedC")); got != 1 {
		t.Fatalf("C feed = %d, want 1 (own only)", got)
	}
	// The wall is strictly the author's own posts.
	if got := len(ps.WallOf("FeedA")); got != 1 {
		t.Fatalf("A wall = %d, want 1", got)
	}
	// Wire rows resolve author identity + like state.
	w := ps.Wire(pa, "FeedB")
	if w["author_name"] == "" || w["avatar_id"] != AvatarDefaultID || w["liked"] != false {
		t.Fatalf("wire row: %v", w)
	}
}

func TestPostLikeToggle(t *testing.T) {
	ps, acc, _, _ := postsSetup(t)
	regUser(t, acc, "LikeA")
	regUser(t, acc, "LikeB")
	p, _ := ps.Create("LikeA", "", "thích đi", "")
	up, err := ps.ToggleLike(p.ID, "LikeB")
	if err != nil || len(up.Likes) != 1 {
		t.Fatalf("like: %v likes=%v", err, up.Likes)
	}
	// A second toggle by the same user UNLIKES — a user can
	// never hold two likes on one post.
	up, err = ps.ToggleLike(p.ID, "LikeB")
	if err != nil || len(up.Likes) != 0 {
		t.Fatalf("unlike: %v likes=%v", err, up.Likes)
	}
	if _, err := ps.ToggleLike("nope", "LikeB"); err != ErrPostNotFound {
		t.Fatalf("like missing post: %v", err)
	}
}

func TestPostDeletePermissions(t *testing.T) {
	ps, acc, allis, _ := postsSetup(t)
	for _, u := range []string{"DelLead", "DelDep", "DelMem", "DelOther"} {
		regUser(t, acc, u)
	}
	al, err := allis.Create("DelLead", "Hội Xoá Bài", "DEL", 1, 0, "open", "")
	if err != nil {
		t.Fatal(err)
	}
	// Join the others (open mode joins directly).
	for _, u := range []string{"DelDep", "DelMem"} {
		if err := allis.Apply(al.ID, u, ""); err != nil {
			t.Fatal(err)
		}
	}
	if err := allis.SetRole(al.ID, "DelLead", "DelDep", AllianceRoleDeputy); err != nil {
		t.Fatal(err)
	}
	p, _ := ps.Create("DelMem", al.ID, "bài của mem", "")
	// A plain member of ANOTHER context cannot delete it:
	// not the author, no moderation right.
	if err := ps.Delete(p.ID, "DelOther", false); err != ErrPostForbidden {
		t.Fatalf("outsider delete: %v", err)
	}
	// A fellow member without a role cannot either.
	own, _ := ps.Create("DelLead", al.ID, "bài của lead", "")
	if err := ps.Delete(own.ID, "DelMem", false); err != ErrPostForbidden {
		t.Fatalf("member delete of leader post: %v", err)
	}
	// Moderation (leader/deputy) deletes a member's post.
	if err := ps.Delete(p.ID, "DelDep", true); err != nil {
		t.Fatalf("deputy moderation delete: %v", err)
	}
	// The author deletes their own post anywhere.
	p2, _ := ps.Create("DelMem", "", "bài tường nhà", "")
	if err := ps.Delete(p2.ID, "DelMem", false); err != nil {
		t.Fatalf("author delete: %v", err)
	}
	if err := ps.Delete(p2.ID, "DelMem", false); err != ErrPostNotFound {
		t.Fatalf("double delete: %v", err)
	}
}

func TestPostAllianceScopeIsolation(t *testing.T) {
	ps, acc, allis, _ := postsSetup(t)
	for _, u := range []string{"IsoA", "IsoB"} {
		regUser(t, acc, u)
	}
	a1, err := allis.Create("IsoA", "Hội Một", "ISO1", 1, 0, "open", "")
	if err != nil {
		t.Fatal(err)
	}
	a2, err := allis.Create("IsoB", "Hội Hai", "ISO2", 2, 1, "open", "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ps.Create("IsoA", a1.ID, "chỉ hội một thấy", ""); err != nil {
		t.Fatal(err)
	}
	// Alliance posts are listed strictly per alliance id.
	if got := ps.AlliancePosts(a2.ID); len(got) != 0 {
		t.Fatalf("alliance 2 sees %d posts of alliance 1", len(got))
	}
	if got := ps.AlliancePosts(a1.ID); len(got) != 1 {
		t.Fatalf("alliance 1 posts = %d, want 1", len(got))
	}
	// …and never leak into any personal feed or wall.
	if got := ps.FeedFor("IsoB"); len(got) != 0 {
		t.Fatalf("alliance post leaked into feed: %d", len(got))
	}
	if got := ps.WallOf("IsoA"); len(got) != 0 {
		t.Fatalf("alliance post leaked onto wall: %d", len(got))
	}
}

// ------------------------------------------------------------ wire level

func postsWireSetup(t *testing.T) (*httptest.Server, *Accounts, *Alliances, *Posts) {
	t.Helper()
	acc, _ := testAccounts(t)
	hub := NewHub()
	hub.acc = acc
	hub.dms = NewDMs(acc.store)
	hub.allis = NewAlliances(acc.store, acc)
	hub.posts = NewPosts(acc.store, acc)
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgradeWS(w, r)
		if err != nil {
			http.Error(w, "upgrade failed", http.StatusBadRequest)
			return
		}
		s := &session{hub: hub, conn: conn, acc: acc}
		conn.onText = s.handle
		conn.onGone = s.gone
		go conn.readLoop()
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv, acc, hub.allis, hub.posts
}

func TestPostWireScopeAndModeration(t *testing.T) {
	srv, _, _, _ := postsWireSetup(t)
	url := srv.URL + "/ws"
	reg := func(user string) *wsTestClient {
		c := dialWS(t, url)
		c.send(t, map[string]any{"t": "register", "user": user, "pass": "secret1"})
		c.recvUntil(t, "auth_ok")
		return c
	}
	lead := reg("WireLead")
	defer lead.conn.Close()
	mem := reg("WireMem")
	defer mem.conn.Close()
	out := reg("WireOut")
	defer out.conn.Close()

	// Leader creates an open alliance; the member joins.
	lead.send(t, map[string]any{"t": "alliance_create", "name": "Hội Wire",
		"tag": "WIRE", "badge_icon": 1, "badge_color": 0, "mode": "open", "desc": ""})
	home := lead.recvUntil(t, "alliance_home")
	mine, _ := home["mine"].(map[string]any)
	allyID, _ := mine["id"].(string)
	if allyID == "" {
		t.Fatalf("no alliance id in home: %v", home)
	}
	mem.send(t, map[string]any{"t": "alliance_apply", "ally_id": allyID})
	mem.recvUntil(t, "alliance_home")

	// Member posts in the alliance; the member reads it back.
	mem.send(t, map[string]any{"t": "post_create", "scope": "alliance",
		"text": "chào hội", "image": "art:03"})
	created := mem.recvUntil(t, "post_created")
	post, _ := created["post"].(map[string]any)
	postID, _ := post["id"].(string)
	if postID == "" || post["scope"] != allyID {
		t.Fatalf("created post: %v", created)
	}
	mem.send(t, map[string]any{"t": "post_alliance"})
	rows := mem.recvUntil(t, "post_alliance")["rows"].([]any)
	if len(rows) != 1 {
		t.Fatalf("member alliance posts = %d, want 1", len(rows))
	}

	// The outsider's alliance feed is empty and their like on
	// the alliance post is refused (scope isolation).
	out.send(t, map[string]any{"t": "post_alliance"})
	orows := out.recvUntil(t, "post_alliance")["rows"].([]any)
	if len(orows) != 0 {
		t.Fatalf("outsider sees %d alliance posts", len(orows))
	}
	out.send(t, map[string]any{"t": "post_like", "post_id": postID})
	if e := out.recvUntil(t, "error"); !strings.Contains(e["msg"].(string), "quyền") {
		t.Fatalf("outsider like refusal: %v", e["msg"])
	}
	// The outsider cannot delete it either.
	out.send(t, map[string]any{"t": "post_delete", "post_id": postID})
	_ = out.recvUntil(t, "error")
	// …but the leader moderates: delete succeeds.
	lead.send(t, map[string]any{"t": "post_delete", "post_id": postID})
	if d := lead.recvUntil(t, "post_deleted"); d["post_id"] != postID {
		t.Fatalf("leader moderation delete: %v", d)
	}

	// Rate budget: rapid-fire creates eventually refuse.
	hitRate := false
	for i := 0; i < ChatRateCount+4; i++ {
		mem.send(t, map[string]any{"t": "post_create", "text": "dồn dập"})
	}
	// Drain replies: created lines then an error.
	for i := 0; i < ChatRateCount+4; i++ {
		m := mem.recv(t)
		if m["t"] == "error" && strings.Contains(m["msg"].(string), "quá nhanh") {
			hitRate = true
		}
	}
	if !hitRate {
		t.Fatal("post create rate limit never refused")
	}
	// Guests are refused outright.
	guest := dialWS(t, url)
	defer guest.conn.Close()
	guest.send(t, map[string]any{"t": "post_feed"})
	if e := guest.recvUntil(t, "error"); e["msg"] == "" {
		t.Fatal("guest post_feed must error")
	}
}

// ------------------------------------------------------------ §5 avatar

func testJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{uint8(x % 251), uint8(y % 241), 128, 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85}); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestCustomAvatarUploadValidation(t *testing.T) {
	_, acc, _, _ := postsSetup(t)
	regUser(t, acc, "Photo")
	good := testJPEG(t, CustomAvatarSize, CustomAvatarSize)
	// Not a JPEG at all.
	if _, err := acc.UploadCustomAvatar("Photo", []byte("PNG fake")); err != ErrBadCustomAvatar {
		t.Fatalf("non-jpeg: %v", err)
	}
	// A JPEG of the wrong size.
	if _, err := acc.UploadCustomAvatar("Photo", testJPEG(t, 128, 128)); err != ErrBadCustomAvatar {
		t.Fatalf("wrong size: %v", err)
	}
	// Over the byte cap (checked before decoding).
	big := make([]byte, CustomAvatarMaxBytes+1)
	if _, err := acc.UploadCustomAvatar("Photo", big); err != ErrCustomAvatarBig {
		t.Fatalf("oversize: %v", err)
	}
	// The good photo stores, equips, and round-trips.
	prof, err := acc.UploadCustomAvatar("Photo", good)
	if err != nil {
		t.Fatal(err)
	}
	if prof.AvatarID != AvatarCustomID {
		t.Fatalf("profile avatar after upload = %q", prof.AvatarID)
	}
	if got := acc.CustomAvatarOf("Photo"); !bytes.Equal(got, good) {
		t.Fatalf("round-trip bytes differ (%d vs %d)", len(got), len(good))
	}
	if acc.AvatarOf("Photo") != AvatarCustomID {
		t.Fatalf("AvatarOf = %q, want custom", acc.AvatarOf("Photo"))
	}
	// Choosing a catalogue avatar keeps the photo stored;
	// re-equipping "custom" restores it.
	if _, err := acc.SetAvatar("Photo", "art:05"); err != nil {
		t.Fatal(err)
	}
	if acc.AvatarOf("Photo") != "art:05" || !acc.HasCustomAvatar("Photo") {
		t.Fatal("catalogue pick must keep the stored photo")
	}
	if _, err := acc.SetAvatar("Photo", AvatarCustomID); err != nil {
		t.Fatalf("re-equip custom: %v", err)
	}
	if acc.AvatarOf("Photo") != AvatarCustomID {
		t.Fatal("custom re-equip lost")
	}
	// An account with NO photo cannot equip "custom".
	regUser(t, acc, "NoPhoto")
	if _, err := acc.SetAvatar("NoPhoto", AvatarCustomID); err != ErrBadAvatar {
		t.Fatalf("custom without photo: %v", err)
	}
}

func TestCustomAvatarPersistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "accounts.json")
	fs, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc := NewAccounts(fs)
	regUser(t, acc, "Persist")
	good := testJPEG(t, CustomAvatarSize, CustomAvatarSize)
	if _, err := acc.UploadCustomAvatar("Persist", good); err != nil {
		t.Fatal(err)
	}
	// Reload the store from disk: the photo survives (base64
	// in the JSON file) and is still equipped.
	fs2, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	acc2 := NewAccounts(fs2)
	if got := acc2.CustomAvatarOf("Persist"); !bytes.Equal(got, good) {
		t.Fatalf("persisted photo differs (%d bytes)", len(got))
	}
	if acc2.AvatarOf("Persist") != AvatarCustomID {
		t.Fatal("persisted equip lost")
	}
	// …and the base64 really is in the file (the store format).
	b64 := base64.StdEncoding.EncodeToString(good)
	data, err := os.ReadFile(path)
	if err != nil || !strings.Contains(string(data), b64[:32]) {
		t.Fatalf("store file does not embed the photo: %v", err)
	}
}
