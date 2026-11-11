package main

// Accounts for the Empire Age relay: registration, login, session
// tokens, match W/L records and the leaderboard.
//
// Persistence goes through the Store interface; the implementation
// shipped today is FileStore (one JSON file, atomic temp+rename
// writes). The Master document's endgame is PostgreSQL — that only
// needs a second Store implementation (an external driver), the
// account logic below does not change.
//
// Passwords are NEVER stored in plaintext: PBKDF2-HMAC-SHA256
// (implemented here from crypto/hmac + crypto/sha256 — the module
// stays dependency-free) with a per-user random salt and 120k
// iterations. Session tokens are 32 random bytes (hex); only their
// SHA-256 hash is stored, with a 30-day expiry.

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"
)

const (
	PBKDF2Iterations = 120_000
	SaltLen          = 16
	KeyLen           = 32
	TokenBytes       = 32
	TokenTTL         = 30 * 24 * time.Hour
)

// ------------------------------------------------------------- PBKDF2

// pbkdf2SHA256 is PBKDF2 (RFC 2898) with HMAC-SHA256 as the PRF.
func pbkdf2SHA256(password, salt []byte, iter, keyLen int) []byte {
	prf := hmac.New(sha256.New, password)
	hashLen := prf.Size()
	numBlocks := (keyLen + hashLen - 1) / hashLen
	var dk []byte
	for block := 1; block <= numBlocks; block++ {
		prf.Reset()
		prf.Write(salt)
		prf.Write([]byte{byte(block >> 24), byte(block >> 16), byte(block >> 8), byte(block)})
		u := prf.Sum(nil)
		t := make([]byte, len(u))
		copy(t, u)
		for i := 1; i < iter; i++ {
			prf.Reset()
			prf.Write(u)
			u = prf.Sum(nil)
			for j := range t {
				t[j] ^= u[j]
			}
		}
		dk = append(dk, t...)
	}
	return dk[:keyLen]
}

func hashPassword(password string, salt []byte) []byte {
	return pbkdf2SHA256([]byte(password), salt, PBKDF2Iterations, KeyLen)
}

// ------------------------------------------------------------- records

type Account struct {
	User string `json:"user"`
	// ID is the account's immutable numeric id (13l): assigned
	// sequentially at registration; accounts that predate the
	// field were backfilled in registration order (see
	// migrateAccounts). 0 = not yet assigned.
	ID      int    `json:"id,omitempty"`
	Salt    string `json:"salt"` // hex
	Hash    string `json:"hash"` // hex PBKDF2 output
	Wins    int    `json:"wins"`
	Losses  int    `json:"losses"`
	Matches int    `json:"matches"`
	// Credit is the account's reputation score ("Uy tín", 13l):
	// starts at 100, −5 for a ranked loss by disconnect, +1 per
	// completed ranked match, clamped 0–100. CreditSet separates
	// "never initialised" (pre-13l accounts → treated as 100 and
	// backfilled) from a real score of 0.
	Credit    int  `json:"credit,omitempty"`
	CreditSet bool `json:"credit_set,omitempty"`
	// SeasonStars counts the stars EARNED this season (gross:
	// every positive star delta from ranked wins, streak/daily
	// bonuses included). Reset to 0 by the season rollover; the
	// finished total is archived on the SeasonRecord.
	SeasonStars int   `json:"season_stars,omitempty"`
	MMR         int   `json:"mmr"`         // 0 = never played ranked (effective: MMRStart)
	LastPlayed  int64 `json:"last_played"` // unix seconds, 0 = never
	Created     int64 `json:"created"`
	// Seasonal rank ladder (rank.go). Rank.Season == 0 marks an
	// account created before the ladder existed: it initialises
	// in place at Tân Binh III on first touch, no reset applied.
	Rank    RankState      `json:"rank"`
	History []SeasonRecord `json:"history,omitempty"`
	// DailyBonusDay is the server-local calendar date (YYYY-MM-DD)
	// of this account's latest first-ranked-win-of-the-day bonus
	// claim (13i); "" = never claimed.
	DailyBonusDay string `json:"daily_bonus_day,omitempty"`
	// AvatarID is the account's profile-avatar pick (13j final
	// model): one of the four main characters' portraits, chosen
	// freely and DECOUPLED from the per-match character draw.
	// "" (older accounts) means the default portrait.
	AvatarID string `json:"avatar_id,omitempty"`
	// DisplayName is the player's public in-game name (13r),
	// chosen once via the "Đặt Tên Nhân Vật" panel after
	// registering. "" = not chosen yet (clients then fall back
	// to the username everywhere a name is shown, and the entry
	// flow asks for one). Unique across accounts, case-insensitive.
	DisplayName string `json:"display_name,omitempty"`
	// OwnedSkins lists the cosmetic appearance skins the account
	// owns (future shop). EMPTY for every account today — the
	// three wuxia skins ship locked. Skins are appearance-only:
	// they never enter the character draw and carry no kit.
	OwnedSkins []string `json:"owned_skins,omitempty"`
	// ActiveSkin is the owned cosmetic skin the player has set
	// active ("" = none). Validated against OwnedSkins wherever
	// it is read; with an empty OwnedSkins it can never be set.
	ActiveSkin string `json:"active_skin,omitempty"`
	// MatchHistory is the rolling record of this account's latest
	// ranked results (stage 13g home lobby "Lịch Sử"), oldest
	// first, capped at MatchHistoryCap entries.
	MatchHistory []MatchRecord `json:"match_history,omitempty"`
	// Friends is the account's friend list (usernames, add order).
	Friends []string `json:"friends,omitempty"`
	// CloseFriends is the subset of Friends this account has
	// flagged as "bạn thân" (13m): the home screen's right rail
	// shows these friends' portraits. Per-owner: the flag lives
	// only on the flagger's record, never on the friend's.
	CloseFriends []string `json:"close_friends,omitempty"`
	// LastOnline is when this account's last live session ended
	// (unix seconds; 13m), stamped by the hub when its presence
	// refcount reaches zero. 0 = never recorded (the account has
	// not logged out through the hub since the field existed).
	LastOnline int64 `json:"last_online,omitempty"`
	// Letters is the account's system mailbox (stage 13g "Thư"),
	// oldest first, capped at LetterCap entries.
	Letters   []Letter `json:"letters,omitempty"`
	LetterSeq int      `json:"letter_seq,omitempty"`
}

// Letter is one server-generated system letter: a welcome note at
// registration, a congratulation on every ladder promotion, and
// a season summary whenever a season reset lands.
type Letter struct {
	ID    int64  `json:"id"`
	Title string `json:"title"`
	Body  string `json:"body"`
	At    int64  `json:"at"` // unix seconds
	Read  bool   `json:"read"`
}

// LetterCap bounds one mailbox; the oldest letters drop off.
const LetterCap = 50

// appendLetter files one letter on the account.
func (a *Account) appendLetter(title, body string, at int64) {
	a.LetterSeq++
	a.Letters = append(a.Letters, Letter{
		ID: int64(a.LetterSeq), Title: title, Body: body, At: at,
	})
	if len(a.Letters) > LetterCap {
		a.Letters = a.Letters[len(a.Letters)-LetterCap:]
	}
}

// MatchRecord is one banked ranked result from the account's own
// point of view: who the opponent was, whether this account won,
// and how its ladder position + MMR moved.
type MatchRecord struct {
	Opponent  string `json:"opponent"`
	Won       bool   `json:"won"`
	RankFrom  string `json:"rank_from"` // rank BEFORE the match, e.g. "Kỵ Sĩ II · 1 sao"
	RankTo    string `json:"rank_to"`   // rank AFTER the match, e.g. "Kỵ Sĩ II · 2 sao"
	StarDelta int    `json:"star_delta"`
	// What StarDelta is made of (13i) so the history panel can
	// label it truthfully: a plain +1 win has both false; a
	// streak win and/or a first-win-of-the-day win set theirs.
	StarBonus  bool  `json:"star_bonus,omitempty"`
	DailyBonus bool  `json:"daily_bonus,omitempty"`
	MMRBefore  int   `json:"mmr_before"`
	MMRAfter   int   `json:"mmr_after"`
	At         int64 `json:"at"` // unix seconds the result was banked
	// Match context for the history panel (map cell + details):
	// the room's biome/layout keys and the referee-reported match
	// length in lockstep ticks (10 ticks = 1 s).
	Biome         string `json:"biome,omitempty"`
	Layout        string `json:"layout,omitempty"`
	DurationTicks int    `json:"duration_ticks,omitempty"`
	// ReplayID keys the server-side match recording (13h); the
	// history panel's play button fetches it. "" = not recorded.
	ReplayID string `json:"replay_id,omitempty"`
	// Placement is the free-for-all finishing position (13z,
	// 1 = won the match) for queue matches; 0 = a 1v1-era record
	// where only Won carries the result.
	Placement int `json:"placement,omitempty"`
}

// MatchHistoryCap is how many ranked results each account keeps.
const MatchHistoryCap = 20

// appendMatchHistory appends one record, dropping the oldest
// entries beyond MatchHistoryCap.
func appendMatchHistory(h []MatchRecord, rec MatchRecord) []MatchRecord {
	h = append(h, rec)
	if len(h) > MatchHistoryCap {
		h = h[len(h)-MatchHistoryCap:]
	}
	return h
}

type tokenRec struct {
	User    string `json:"user"`
	Expires int64  `json:"expires"` // unix seconds
}

type Profile struct {
	User string `json:"user"`
	// ID + progression (13l): the immutable numeric account id
	// and the level derived from recorded results — XP is
	// 10 per recorded match + 20 per win (ranked + reported
	// customs; offline SP matches are never recorded, so they
	// never count). Level thresholds are cumulative:
	// 100·L·(L−1)/2 XP for level L.
	ID        int `json:"id"`
	Level     int `json:"level"`
	XP        int `json:"xp"`
	XPInto    int `json:"xp_into_level"`
	XPForNext int `json:"xp_for_next"`
	// Credit is the effective reputation score (0–100).
	Credit int `json:"credit"`
	// SeasonStars: stars earned so far this season (gross).
	SeasonStars int `json:"season_stars"`
	// PrevRank is the previous season's FINAL ladder position
	// (nil when no season has been archived); PrevSeasonStars
	// is that season's gross earned-star total.
	PrevRank        *RankView `json:"prev_rank,omitempty"`
	PrevSeason      int       `json:"prev_season,omitempty"`
	PrevSeasonStars int       `json:"prev_season_stars,omitempty"`
	Wins            int       `json:"wins"`
	Losses          int       `json:"losses"`
	Matches         int       `json:"matches"`
	MMR             int       `json:"mmr"` // effective rating (MMRStart when unrated)
	Rank            RankView  `json:"rank"`
	UnreadMail      int       `json:"unread_mail"` // home-lobby mail badge
	// DailyBonusClaimed reports whether the account has already
	// banked today's first-win bonus star (13i); it is derived
	// from DailyBonusDay vs the server-local date at render time
	// (profileOf), never stored on the Profile itself.
	DailyBonusClaimed bool `json:"daily_bonus_claimed"`
	// SeasonEnd is the unix time the CURRENT ranked season ends
	// (epoch + season × season length), resolved by profileOf;
	// the entry screens' notices panel shows it. 0 = unknown.
	SeasonEnd int64 `json:"season_end"`
	// AvatarID is the account's effective profile avatar (13j):
	// the stored pick, normalised — never empty on the wire.
	AvatarID string `json:"avatar_id"`
	// DisplayName is the account's RAW stored display name
	// (13r): "" means the player has not picked one yet — the
	// entry flow routes them to the name panel. Consumers that
	// just need a label use the effective name (DisplayName
	// when set, else User); rows carry that resolved value.
	DisplayName string `json:"display_name"`
	// OwnedSkins mirrors the account's cosmetic skins (empty
	// until the shop exists); ActiveSkin the validated active
	// one ("" = none).
	OwnedSkins []string `json:"owned_skins"`
	ActiveSkin string   `json:"active_skin"`
}

// Character + cosmetic-skin registry ids (mirror of the client's
// Characters registry). Presentation data only — the sim and the
// referee never read them; a hero's KIT comes from its drawn
// character, never from a skin.
const CharDefault = "ngan_ky"

var mainCharIDs = map[string]bool{
	"ngan_ky": true, "kim_hoa": true, "lam_bao": true, "bach_sa": true,
	// 14c: the four Temple Masters join the roster.
	"loi_chan": true, "xich_diem": true, "phong_linh": true, "thach_son": true,
}

// MainChars is the character DRAW POOL: every player owns the
// eight mains; the draw at match start picks among these only.
var MainChars = []string{"ngan_ky", "kim_hoa", "lam_bao", "bach_sa",
	"loi_chan", "xich_diem", "phong_linh", "thach_son"}

var premiumSkinIDs = map[string]bool{
	"vo_hiep": true, "bach_y": true, "tu_y": true,
}

var (
	ErrBadAvatar    = errors.New("avatar không hợp lệ")
	ErrSkinNotOwned = errors.New("chưa sở hữu skin này")
	ErrBadSkin      = errors.New("skin không hợp lệ")
)

// NormalizeCharID maps any value to a main-character id.
func NormalizeCharID(id string) string {
	if mainCharIDs[id] {
		return id
	}
	return CharDefault
}

// NormalizeSkinID maps any value to a cosmetic-skin id ("" if
// the value names no skin).
func NormalizeSkinID(id string) string {
	if premiumSkinIDs[id] {
		return id
	}
	return ""
}

// EffectiveAvatar is the account's avatar pick, normalised.
func EffectiveAvatar(a *Account) string {
	return NormalizeCharID(a.AvatarID)
}

// EffectiveActiveSkin is the account's active cosmetic skin —
// only honoured while the account actually owns it.
func EffectiveActiveSkin(a *Account) string {
	id := NormalizeSkinID(a.ActiveSkin)
	if id == "" {
		return ""
	}
	for _, owned := range a.OwnedSkins {
		if owned == id {
			return id
		}
	}
	return ""
}

// ------------------------------------------------------------- progression (13l)

// XPFor derives an account's XP from its recorded results:
// 10 XP per recorded match + 20 XP per win. Only server-recorded
// matches count (ranked + host-reported customs) — offline SP
// matches are never recorded and never grant XP.
func XPFor(matches, wins int) int {
	return 10*matches + 20*wins
}

// LevelThreshold is the cumulative XP at which `level` begins:
// 100·L·(L−1)/2 (Lv1 at 0, Lv2 at 100, Lv3 at 300, Lv4 at 600…).
func LevelThreshold(level int) int {
	if level < 1 {
		level = 1
	}
	return 100 * level * (level - 1) / 2
}

// LevelForXP resolves an XP total to (level, xp into that level,
// xp needed to go from this level to the next).
func LevelForXP(xp int) (level, into, forNext int) {
	level = 1
	for xp >= LevelThreshold(level+1) {
		level++
	}
	into = xp - LevelThreshold(level)
	forNext = LevelThreshold(level+1) - LevelThreshold(level)
	return level, into, forNext
}

// EffectiveCredit resolves the reputation score: accounts that
// predate the field (CreditSet false) sit at the 100 start.
func EffectiveCredit(a *Account) int {
	if a == nil || !a.CreditSet {
		return 100
	}
	if a.Credit < 0 {
		return 0
	}
	if a.Credit > 100 {
		return 100
	}
	return a.Credit
}

// applyCredit moves the reputation score by delta, initialising
// pre-13l accounts at the 100 start and clamping to 0–100.
func (a *Account) applyCredit(delta int) {
	c := EffectiveCredit(a) + delta
	if c < 0 {
		c = 0
	}
	if c > 100 {
		c = 100
	}
	a.Credit = c
	a.CreditSet = true
}

func (a *Account) profile() Profile {
	unread := 0
	for _, l := range a.Letters {
		if !l.Read {
			unread++
		}
	}
	owned := a.OwnedSkins
	if owned == nil {
		owned = []string{}
	}
	xp := XPFor(a.Matches, a.Wins)
	level, into, forNext := LevelForXP(xp)
	p := Profile{User: a.User, Wins: a.Wins, Losses: a.Losses,
		Matches: a.Matches, MMR: EffectiveMMR(a), Rank: rankViewOf(a, false),
		UnreadMail: unread, AvatarID: EffectiveAvatar(a), DisplayName: a.DisplayName,
		OwnedSkins: owned, ActiveSkin: EffectiveActiveSkin(a),
		ID: a.ID, Level: level, XP: xp, XPInto: into, XPForNext: forNext,
		Credit: EffectiveCredit(a), SeasonStars: a.SeasonStars}
	if n := len(a.History); n > 0 {
		last := a.History[n-1]
		final := RankState{Tier: last.FinalTier, Division: last.FinalDivision,
			Stars: last.FinalStars}
		v := rankViewFromState(final, last.Emperor)
		p.PrevRank = &v
		p.PrevSeason = last.Season
		p.PrevSeasonStars = last.TotalStars
	}
	return p
}

// profileOf renders a profile with the Hoàng Đế status resolved
// against the whole account base.
func (ac *Accounts) profileOf(a *Account) Profile {
	p := a.profile()
	p.Rank = rankViewOf(a, ac.emperorSet()[a.User])
	p.DailyBonusClaimed = ac.dailyBonusClaimed(a)
	p.SeasonEnd = ac.SeasonEndUnix()
	return p
}

// SeasonEndUnix returns when the season containing "now" ends:
// season N spans [epoch+(N-1)·len, epoch+N·len).
func (ac *Accounts) SeasonEndUnix() int64 {
	epoch := ac.seasonEpoch()
	return epoch + int64(ac.CurrentSeason())*int64(ac.seasonLength()/time.Second)
}

// dayKey renders the daily-bonus day boundary: the SERVER's local
// calendar date. "Today" for the first-win bonus (13i) is whatever
// date the host machine is on — run the server in the timezone
// you want the bonus to reset in.
func dayKey(t time.Time) string {
	return t.Format("2006-01-02")
}

// dailyBonusClaimed reports whether account a has already banked
// today's first-win bonus star.
func (ac *Accounts) dailyBonusClaimed(a *Account) bool {
	return a.DailyBonusDay != "" && a.DailyBonusDay == dayKey(ac.now())
}

// ------------------------------------------------------------- store

// Store is the persistence seam for accounts + tokens. FileStore
// below is the current implementation; a PostgreSQL implementation
// can replace it without touching the account logic.
type Store interface {
	GetAccount(user string) (*Account, bool)
	PutAccount(a *Account) error
	Accounts() []*Account
	GetToken(hash string) (user string, expires int64, ok bool)
	PutToken(hash, user string, expires int64) error
	DeleteToken(hash string) error
	// Meta holds small server-level values (the season epoch).
	GetMeta(key string) (string, bool)
	PutMeta(key, value string) error
}

type storeData struct {
	Accounts map[string]*Account  `json:"accounts"`
	Tokens   map[string]*tokenRec `json:"tokens"`
	Meta     map[string]string    `json:"meta,omitempty"`
}

type FileStore struct {
	mu   sync.Mutex
	path string
	data storeData
}

// NewFileStore loads the store file (a missing file means an empty
// store). Every mutation is flushed atomically (temp file + rename)
// so a crash cannot corrupt the previous state.
func NewFileStore(path string) (*FileStore, error) {
	fs := &FileStore{path: path}
	fs.data.Accounts = make(map[string]*Account)
	fs.data.Tokens = make(map[string]*tokenRec)
	fs.data.Meta = make(map[string]string)
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return fs, nil
		}
		return nil, err
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &fs.data); err != nil {
			return nil, err
		}
		if fs.data.Accounts == nil {
			fs.data.Accounts = make(map[string]*Account)
		}
		if fs.data.Tokens == nil {
			fs.data.Tokens = make(map[string]*tokenRec)
		}
		if fs.data.Meta == nil {
			fs.data.Meta = make(map[string]string)
		}
	}
	return fs, nil
}

func (fs *FileStore) flushLocked() error {
	raw, err := json.MarshalIndent(fs.data, "", " ")
	if err != nil {
		return err
	}
	tmp := fs.path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	if dir := filepath.Dir(fs.path); dir != "" {
		_ = os.Chmod(tmp, 0o600)
	}
	return os.Rename(tmp, fs.path)
}

func (fs *FileStore) GetAccount(user string) (*Account, bool) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	a, ok := fs.data.Accounts[user]
	if !ok {
		return nil, false
	}
	cp := *a
	return &cp, true
}

func (fs *FileStore) PutAccount(a *Account) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	cp := *a
	fs.data.Accounts[a.User] = &cp
	return fs.flushLocked()
}

func (fs *FileStore) Accounts() []*Account {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	out := make([]*Account, 0, len(fs.data.Accounts))
	for _, a := range fs.data.Accounts {
		cp := *a
		out = append(out, &cp)
	}
	return out
}

func (fs *FileStore) GetToken(hash string) (string, int64, bool) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	rec, ok := fs.data.Tokens[hash]
	if !ok {
		return "", 0, false
	}
	return rec.User, rec.Expires, true
}

func (fs *FileStore) PutToken(hash, user string, expires int64) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	fs.data.Tokens[hash] = &tokenRec{User: user, Expires: expires}
	return fs.flushLocked()
}

func (fs *FileStore) DeleteToken(hash string) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	delete(fs.data.Tokens, hash)
	return fs.flushLocked()
}

func (fs *FileStore) GetMeta(key string) (string, bool) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	v, ok := fs.data.Meta[key]
	return v, ok
}

func (fs *FileStore) PutMeta(key, value string) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	fs.data.Meta[key] = value
	return fs.flushLocked()
}

// ------------------------------------------------------------- service

var (
	ErrUserExists     = errors.New("Tên đăng nhập đã tồn tại")
	ErrBadCredentials = errors.New("Sai tên đăng nhập hoặc mật khẩu")
	ErrInvalidUser    = errors.New("Tên đăng nhập phải có 3–20 ký tự (chữ, số, _)")
	ErrWeakPassword   = errors.New("Mật khẩu phải có ít nhất 6 ký tự")
	ErrInvalidName    = errors.New("Tên phải từ 3 – 16 ký tự (chữ, số và _)")
	ErrNameTaken      = errors.New("Tên này đã có người dùng")
)

type Accounts struct {
	store Store
	now   func() time.Time // test seam
	mu    sync.Mutex       // serialises match banking (two-account updates)
	// SeasonDays is the season length (the -season-days flag);
	// values <= 0 fall back to DefaultSeasonDays.
	SeasonDays int
}

func NewAccounts(store Store) *Accounts {
	ac := &Accounts{store: store, now: time.Now}
	ac.migrateAccounts()
	return ac
}

// MetaAccountIDSeq is the store-meta key holding the NEXT numeric
// account id to hand out (13l).
const MetaAccountIDSeq = "account_id_seq"

// migrateAccounts backfills the 13l account fields on stores that
// predate them: numeric ids for accounts that have none — in
// registration order (Created, then username as the tiebreak) —
// and the reputation default for accounts that never had the
// field initialised. Idempotent: a second run changes nothing.
// Best effort like touch(): persistence errors are ignored so a
// read-only store cannot block boot.
func (ac *Accounts) migrateAccounts() {
	all := ac.store.Accounts()
	next := 1
	if raw, ok := ac.store.GetMeta(MetaAccountIDSeq); ok {
		var v int
		if _, err := fmt.Sscanf(raw, "%d", &v); err == nil && v > next {
			next = v
		}
	}
	for _, a := range all {
		if a.ID >= next {
			next = a.ID + 1
		}
	}
	var missing []*Account
	for _, a := range all {
		if a.ID <= 0 {
			missing = append(missing, a)
		}
	}
	sort.Slice(missing, func(i, j int) bool {
		if missing[i].Created != missing[j].Created {
			return missing[i].Created < missing[j].Created
		}
		return missing[i].User < missing[j].User
	})
	for _, a := range missing {
		a.ID = next
		next++
		_ = ac.store.PutAccount(a)
	}
	for _, a := range all {
		if !a.CreditSet {
			a.Credit = 100
			a.CreditSet = true
			_ = ac.store.PutAccount(a)
		}
	}
	_ = ac.store.PutMeta(MetaAccountIDSeq, fmt.Sprintf("%d", next))
}

// nextAccountID hands out the next sequential account id,
// guarding against ids already present in the store (e.g. a
// store file seeded externally after boot). Callers hold ac.mu.
func (ac *Accounts) nextAccountID() int {
	next := 1
	if raw, ok := ac.store.GetMeta(MetaAccountIDSeq); ok {
		var v int
		if _, err := fmt.Sscanf(raw, "%d", &v); err == nil && v > next {
			next = v
		}
	}
	for _, a := range ac.store.Accounts() {
		if a.ID >= next {
			next = a.ID + 1
		}
	}
	_ = ac.store.PutMeta(MetaAccountIDSeq, fmt.Sprintf("%d", next+1))
	return next
}

func validUsername(user string) bool {
	rs := []rune(user)
	if len(rs) < 3 || len(rs) > 20 {
		return false
	}
	for _, r := range rs {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' {
			return false
		}
	}
	return true
}

func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// Register creates an account. The returned error is specific (a
// registration must say why it failed); LOGIN errors never are.
func (ac *Accounts) Register(user, pass string) error {
	user = strings.TrimSpace(user)
	if !validUsername(user) {
		return ErrInvalidUser
	}
	if len([]rune(pass)) < 6 {
		return ErrWeakPassword
	}
	if _, exists := ac.store.GetAccount(user); exists {
		return ErrUserExists
	}
	salt := make([]byte, SaltLen)
	if _, err := rand.Read(salt); err != nil {
		return err
	}
	// The numeric id is handed out under the same lock that
	// serialises match banking, so concurrent registrations can
	// never draw the same id.
	ac.mu.Lock()
	defer ac.mu.Unlock()
	a := &Account{
		User:      user,
		ID:        ac.nextAccountID(),
		Salt:      hex.EncodeToString(salt),
		Hash:      hex.EncodeToString(hashPassword(pass, salt)),
		Created:   ac.now().Unix(),
		Credit:    100,
		CreditSet: true,
	}
	// Welcome letter: the first thing in every new mailbox.
	a.appendLetter("Chào mừng đến với Empire Age",
		"Chào "+user+"! Tài khoản của bạn đã sẵn sàng.\n\n"+
			"Vào Đấu Thường để chơi nhanh hoặc lập phòng cùng bạn bè. "+
			"Khi muốn leo hạng, hãy vào Đấu Hạng: thắng trận để gom sao, "+
			"thăng qua các bậc Tân Binh, Chiến Binh, Kỵ Sĩ… cho tới Hoàng Đế.\n\n"+
			"Chúc bạn xây dựng một đế chế hùng mạnh!",
		a.Created)
	return ac.store.PutAccount(a)
}

// Login verifies credentials and issues a fresh session token.
// The error is always ErrBadCredentials — it never reveals whether
// the username exists.
func (ac *Accounts) Login(user, pass string) (string, Profile, error) {
	user = strings.TrimSpace(user)
	a, ok := ac.store.GetAccount(user)
	if !ok {
		// Burn the same KDF work so timing does not leak existence.
		hashPassword(pass, []byte("empire-age-dummy-salt"))
		return "", Profile{}, ErrBadCredentials
	}
	salt, err := hex.DecodeString(a.Salt)
	if err != nil {
		return "", Profile{}, ErrBadCredentials
	}
	want, err := hex.DecodeString(a.Hash)
	if err != nil {
		return "", Profile{}, ErrBadCredentials
	}
	got := hashPassword(pass, salt)
	if subtle.ConstantTimeCompare(got, want) != 1 {
		return "", Profile{}, ErrBadCredentials
	}
	ac.touch(a)
	raw := make([]byte, TokenBytes)
	if _, err := rand.Read(raw); err != nil {
		return "", Profile{}, err
	}
	token := hex.EncodeToString(raw)
	expires := ac.now().Add(TokenTTL).Unix()
	if err := ac.store.PutToken(tokenHash(token), user, expires); err != nil {
		return "", Profile{}, err
	}
	return token, ac.profileOf(a), nil
}

// Authenticate resolves a session token to its account profile.
func (ac *Accounts) Authenticate(token string) (Profile, bool) {
	if token == "" {
		return Profile{}, false
	}
	user, expires, ok := ac.store.GetToken(tokenHash(token))
	if !ok {
		return Profile{}, false
	}
	if ac.now().Unix() > expires {
		ac.store.DeleteToken(tokenHash(token))
		return Profile{}, false
	}
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, false
	}
	ac.touch(a)
	return ac.profileOf(a), true
}

func (ac *Accounts) Logout(token string) {
	if token != "" {
		ac.store.DeleteToken(tokenHash(token))
	}
}

// Profile looks up one account's public profile.
func (ac *Accounts) Profile(user string) (Profile, bool) {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, false
	}
	ac.touch(a)
	return ac.profileOf(a), true
}

// MatchHistory returns the account's recorded ranked results,
// NEWEST first (the store keeps them oldest first). Unknown
// accounts get an empty list.
func (ac *Accounts) MatchHistory(user string) []MatchRecord {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return nil
	}
	ac.touch(a)
	out := make([]MatchRecord, 0, len(a.MatchHistory))
	for i := len(a.MatchHistory) - 1; i >= 0; i-- {
		out = append(out, a.MatchHistory[i])
	}
	return out
}

// ------------------------------------------------------------- friends + mail (13g)

var (
	ErrFriendSelf    = errors.New("Không thể kết bạn với chính mình")
	ErrFriendMissing = errors.New("Không tìm thấy người chơi này")
	ErrFriendDup     = errors.New("Người này đã có trong danh sách bạn bè")
	ErrFriendAbsent  = errors.New("Người này không có trong danh sách bạn bè")
)

// FriendEntry is one friend-list row: identity + ladder position.
// Online is filled by the session handler from hub presence.
// Level/AvatarID/Close/LastOnline (13m) feed the redesigned
// friends panel and the home rail: the friend's account level,
// their chosen profile-avatar portrait, whether the OWNER has
// flagged them "bạn thân", and when they were last online
// (unix seconds; 0 = never recorded).
type FriendEntry struct {
	User string `json:"user"`
	// DisplayName is the friend's effective public name (13r):
	// their chosen display name, else their username.
	DisplayName string `json:"display_name"`
	RankText    string `json:"rank_text"`
	RankTier    int    `json:"rank_tier"`
	Emperor     bool   `json:"emperor"`
	Online      bool   `json:"online"`
	Level       int    `json:"level"`
	AvatarID    string `json:"avatar_id"`
	Close       bool   `json:"close"`
	LastOnline  int64  `json:"last_online"`
}

// AddFriend appends `other` to `me`'s friend list. Both accounts
// must exist; self-adds and duplicates are rejected.
func (ac *Accounts) AddFriend(me, other string) error {
	other = strings.TrimSpace(other)
	if other == me {
		return ErrFriendSelf
	}
	a, ok := ac.store.GetAccount(me)
	if !ok {
		return ErrBadCredentials
	}
	ac.touch(a)
	if _, ok := ac.store.GetAccount(other); !ok {
		return ErrFriendMissing
	}
	for _, f := range a.Friends {
		if f == other {
			return ErrFriendDup
		}
	}
	a.Friends = append(a.Friends, other)
	return ac.store.PutAccount(a)
}

// RemoveFriend drops `other` from `me`'s friend list (and from
// the close-friend subset, if it was flagged).
func (ac *Accounts) RemoveFriend(me, other string) error {
	a, ok := ac.store.GetAccount(me)
	if !ok {
		return ErrBadCredentials
	}
	ac.touch(a)
	for i, f := range a.Friends {
		if f == other {
			a.Friends = append(a.Friends[:i], a.Friends[i+1:]...)
			for j, c := range a.CloseFriends {
				if c == other {
					a.CloseFriends = append(a.CloseFriends[:j], a.CloseFriends[j+1:]...)
					break
				}
			}
			return ac.store.PutAccount(a)
		}
	}
	return ErrFriendAbsent
}

var ErrNotCloseFriend = errors.New("Người này chưa được đánh dấu bạn thân")

// SetCloseFriend flags or unflags `other` as one of `me`'s close
// friends ("bạn thân", 13m). The flag is per-owner and lives on
// `me`'s record only; `other` must already be in `me`'s friend
// list (ErrFriendAbsent otherwise). Idempotent: setting the
// state the friendship already has is a no-op success.
func (ac *Accounts) SetCloseFriend(me, other string, close bool) error {
	a, ok := ac.store.GetAccount(me)
	if !ok {
		return ErrBadCredentials
	}
	ac.touch(a)
	isFriend := false
	for _, f := range a.Friends {
		if f == other {
			isFriend = true
			break
		}
	}
	if !isFriend {
		return ErrFriendAbsent
	}
	idx := -1
	for i, c := range a.CloseFriends {
		if c == other {
			idx = i
			break
		}
	}
	switch {
	case close && idx < 0:
		a.CloseFriends = append(a.CloseFriends, other)
	case !close && idx >= 0:
		a.CloseFriends = append(a.CloseFriends[:idx], a.CloseFriends[idx+1:]...)
	default:
		return nil // already in the requested state
	}
	return ac.store.PutAccount(a)
}

// MarkOffline stamps the account's last-online time (13m): the
// hub calls it when the account's live-session refcount reaches
// zero. Best effort like touch() — persistence errors are
// ignored so presence bookkeeping can never break a session.
func (ac *Accounts) MarkOffline(user string) {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return
	}
	a.LastOnline = ac.now().Unix()
	_ = ac.store.PutAccount(a)
}

// SetAvatar stores the account's profile-avatar pick (13j).
// Only the four mains have portraits — anything else (including
// cosmetic-skin ids) is rejected.
func (ac *Accounts) SetAvatar(user, id string) (Profile, error) {
	if !mainCharIDs[id] {
		return Profile{}, ErrBadAvatar
	}
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, ErrBadCredentials
	}
	ac.touch(a)
	a.AvatarID = id
	if err := ac.store.PutAccount(a); err != nil {
		return Profile{}, err
	}
	return ac.profileOf(a), nil
}

// EffectiveDisplayName is the label other players see: the
// chosen display name when one is set, else the username.
func EffectiveDisplayName(a *Account) string {
	if a == nil {
		return ""
	}
	if a.DisplayName != "" {
		return a.DisplayName
	}
	return a.User
}

// DisplayNameOf resolves a username to its effective display
// name (the username itself when the account is unknown).
func (ac *Accounts) DisplayNameOf(user string) string {
	if a, ok := ac.store.GetAccount(user); ok {
		return EffectiveDisplayName(a)
	}
	return user
}

// validDisplayName enforces the name panel's caption rules:
// 3–16 characters, Unicode letters + digits + underscore only.
func validDisplayName(name string) bool {
	rs := []rune(name)
	if len(rs) < 3 || len(rs) > 16 {
		return false
	}
	for _, r := range rs {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' {
			return false
		}
	}
	return true
}

// SetDisplayName stores the account's public display name (13r).
// The name must satisfy the caption rules and be unique across
// accounts, case-insensitively: no other account may already use
// it as its display name, and it may not shadow another account's
// username (nobody should be able to impersonate a login name).
// Matching one's OWN username is fine.
func (ac *Accounts) SetDisplayName(user, name string) (Profile, error) {
	name = strings.TrimSpace(name)
	if !validDisplayName(name) {
		return Profile{}, ErrInvalidName
	}
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, ErrBadCredentials
	}
	ac.mu.Lock()
	defer ac.mu.Unlock()
	for _, other := range ac.store.Accounts() {
		if other.User == user {
			continue
		}
		if strings.EqualFold(other.DisplayName, name) && other.DisplayName != "" {
			return Profile{}, ErrNameTaken
		}
		if strings.EqualFold(other.User, name) {
			return Profile{}, ErrNameTaken
		}
	}
	ac.touch(a)
	a.DisplayName = name
	if err := ac.store.PutAccount(a); err != nil {
		return Profile{}, err
	}
	return ac.profileOf(a), nil
}

// SetActiveSkin sets (or with "" clears) the account's active
// cosmetic skin. The skin must be OWNED — with today's empty
// ownership (no shop yet) every activation attempt is rejected,
// which is exactly the dormant state the launch ships in.
func (ac *Accounts) SetActiveSkin(user, id string) (Profile, error) {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, ErrBadCredentials
	}
	ac.touch(a)
	if id == "" {
		a.ActiveSkin = ""
		if err := ac.store.PutAccount(a); err != nil {
			return Profile{}, err
		}
		return ac.profileOf(a), nil
	}
	if !premiumSkinIDs[id] {
		return Profile{}, ErrBadSkin
	}
	owned := false
	for _, o := range a.OwnedSkins {
		if o == id {
			owned = true
		}
	}
	if !owned {
		return Profile{}, ErrSkinNotOwned
	}
	a.ActiveSkin = id
	if err := ac.store.PutAccount(a); err != nil {
		return Profile{}, err
	}
	return ac.profileOf(a), nil
}

// FriendsOf lists `me`'s friends with their ladder positions
// (Hoàng Đế resolved across the account base). Deleted accounts
// are skipped silently.
func (ac *Accounts) FriendsOf(me string) []FriendEntry {
	a, ok := ac.store.GetAccount(me)
	if !ok {
		return nil
	}
	ac.touch(a)
	emp := ac.emperorSet()
	closeSet := make(map[string]bool, len(a.CloseFriends))
	for _, c := range a.CloseFriends {
		closeSet[c] = true
	}
	out := make([]FriendEntry, 0, len(a.Friends))
	for _, name := range a.Friends {
		fa, ok := ac.store.GetAccount(name)
		if !ok {
			continue
		}
		v := rankViewOf(fa, emp[name])
		level, _, _ := LevelForXP(XPFor(fa.Matches, fa.Wins))
		out = append(out, FriendEntry{
			User: fa.User, DisplayName: EffectiveDisplayName(fa), RankText: v.RankText,
			RankTier: fa.Rank.Tier, Emperor: emp[name],
			Level: level, AvatarID: EffectiveAvatar(fa),
			Close: closeSet[name], LastOnline: fa.LastOnline,
		})
	}
	return out
}

// LettersOf returns the account's mailbox, NEWEST first.
func (ac *Accounts) LettersOf(user string) []Letter {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return nil
	}
	ac.touch(a)
	out := make([]Letter, 0, len(a.Letters))
	for i := len(a.Letters) - 1; i >= 0; i-- {
		out = append(out, a.Letters[i])
	}
	return out
}

// MarkMailRead marks one letter (id > 0) or the whole mailbox
// (id == 0) read, then returns the remaining unread count.
func (ac *Accounts) MarkMailRead(user string, id int64) (int, error) {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return 0, ErrBadCredentials
	}
	changed := false
	for i := range a.Letters {
		if !a.Letters[i].Read && (id == 0 || a.Letters[i].ID == id) {
			a.Letters[i].Read = true
			changed = true
		}
	}
	if changed {
		if err := ac.store.PutAccount(a); err != nil {
			return 0, err
		}
	}
	unread := 0
	for _, l := range a.Letters {
		if !l.Read {
			unread++
		}
	}
	return unread, nil
}

// RecordMatch banks one finished match for an account.
func (ac *Accounts) RecordMatch(user string, won bool) error {
	ac.mu.Lock()
	defer ac.mu.Unlock()
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return nil // account vanished; nothing to bank
	}
	a.Matches++
	if won {
		a.Wins++
	} else {
		a.Losses++
	}
	a.LastPlayed = ac.now().Unix()
	return ac.store.PutAccount(a)
}

type LeaderRow struct {
	User string `json:"user"`
	// DisplayName is the row account's effective public name (13r).
	DisplayName string `json:"display_name"`
	Wins        int    `json:"wins"`
	Losses      int    `json:"losses"`
	Matches     int    `json:"matches"`
	MMR         int    `json:"mmr"` // effective rating
	// Seasonal ladder view of the row's account (rank.go).
	RankTier  int    `json:"rank_tier"`
	RankText  string `json:"rank_text"`
	RankShort string `json:"rank_short"`
	RankStars int    `json:"rank_stars"`
	StarCap   int    `json:"rank_star_cap"`
	Emperor   bool   `json:"emperor"`
}

func leaderRowOf(a *Account, emperor bool) LeaderRow {
	v := rankViewOf(a, emperor)
	return LeaderRow{
		User: a.User, DisplayName: EffectiveDisplayName(a), Wins: a.Wins, Losses: a.Losses,
		Matches: a.Matches, MMR: EffectiveMMR(a),
		RankTier: a.Rank.Tier, RankText: v.RankText, RankShort: v.ShortText,
		RankStars: a.Rank.Stars, StarCap: v.StarCap, Emperor: emperor,
	}
}

// touchedAccounts returns copies of every account with pending
// season transitions applied (and persisted).
func (ac *Accounts) touchedAccounts() []*Account {
	all := ac.store.Accounts()
	for _, a := range all {
		ac.touch(a)
	}
	return all
}

// Leaderboard: top 20 by wins, then winrate, then name.
// wlRows: the FULL wins ordering (wins, then winrate, then name).
func (ac *Accounts) wlRows() []LeaderRow {
	all := ac.touchedAccounts()
	emp := EmperorSet(all)
	rows := make([]LeaderRow, 0, len(all))
	for _, a := range all {
		rows = append(rows, leaderRowOf(a, emp[a.User]))
	}
	winrate := func(r LeaderRow) float64 {
		if r.Matches == 0 {
			return 0
		}
		return float64(r.Wins) / float64(r.Matches)
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Wins != rows[j].Wins {
			return rows[i].Wins > rows[j].Wins
		}
		if wi, wj := winrate(rows[i]), winrate(rows[j]); wi != wj {
			return wi > wj
		}
		return rows[i].User < rows[j].User
	})
	return rows
}

func (ac *Accounts) Leaderboard() []LeaderRow {
	rows := ac.wlRows()
	if len(rows) > 20 {
		rows = rows[:20]
	}
	return rows
}

// ------------------------------------------------------------- MMR (ranked)

const (
	MMRStart      = 1000 // rating of an account that never played ranked
	MMRFloor      = 100  // ratings never drop below this
	EloKDefault   = 32   // K-factor below the high-rating threshold
	EloKHigh      = 16   // K-factor at/above the threshold
	EloKThreshold = 2000
)

// EffectiveMMR resolves the stored rating: the zero value means
// "unrated" and plays as MMRStart (accounts created before ranked
// existed carry no mmr field at all).
func EffectiveMMR(a *Account) int {
	if a == nil || a.MMR == 0 {
		return MMRStart
	}
	return a.MMR
}

func eloK(mmr int) int {
	if mmr >= EloKThreshold {
		return EloKHigh
	}
	return EloKDefault
}

// eloExpected is the classic Elo expectation of `me` beating `opp`.
func eloExpected(me, opp int) float64 {
	return 1.0 / (1.0 + math.Pow(10, float64(opp-me)/400.0))
}

// eloDelta is the rating change for one player: K*(score-expected),
// K taken from the player's OWN pre-match rating, rounded to the
// nearest integer.
func eloDelta(myMMR, oppMMR int, score float64) int {
	return int(math.Round(float64(eloK(myMMR)) * (score - eloExpected(myMMR, oppMMR))))
}

// eloDeltaFFA generalises Elo to a free-for-all field (13z): the
// actual score of a placement is (field − placement)/(field − 1)
// — 1st scores 1, last scores 0, the middle spreads linearly —
// and the expected score is the average of the pairwise Elo
// expectations against every other player, all from PRE-match
// ratings. K follows the same per-player rule as 1v1.
func eloDeltaFFA(myMMR int, oppMMRs []int, placement, field int) int {
	if field < 2 || len(oppMMRs) == 0 {
		return 0
	}
	actual := float64(field-placement) / float64(field-1)
	expected := 0.0
	for _, opp := range oppMMRs {
		expected += eloExpected(myMMR, opp)
	}
	expected /= float64(len(oppMMRs))
	return int(math.Round(float64(eloK(myMMR)) * (actual - expected)))
}

// RankedOutcome is one player's full movement from a ranked
// result: MMR before/after plus the ladder outcome (rank.go) —
// it feeds the per-player rank_result payload (end panel).
type RankedOutcome struct {
	User      string
	Won       bool
	MMRBefore int
	MMRAfter  int
	Rank      RankOutcome
	// Placement is the free-for-all finishing position (13z;
	// 1 = won the match). 0 for 1v1-era results.
	Placement int
}

// RecordRankedResultFull banks one finished RANKED match: W/L,
// Elo AND ladder movement for both accounts, atomically in one
// serialised operation (the caller is the room's referee — see
// the trust model in README). Rank and MMR evolve independently
// from the same result.
func (ac *Accounts) RecordRankedResultFull(winner, loser string) (RankedOutcome, RankedOutcome, error) {
	return ac.RecordRankedResultMeta(winner, loser, "", "", 0, "")
}

// RecordRankedResultMeta is RecordRankedResultFull plus the
// match context (map + referee-reported duration) the history
// panel displays.
func (ac *Accounts) RecordRankedResultMeta(winner, loser, biome, layout string, durationTicks int, replayID string) (RankedOutcome, RankedOutcome, error) {
	return ac.recordRankedResult(winner, loser, biome, layout, durationTicks, replayID, "")
}

// RecordRankedResultReason is RecordRankedResultMeta plus the
// referee's result reason ("elimination" | "disconnect"). The
// reason drives the reputation score (13l): both players gain
// +1 credit for a completed ranked match; a loss by DISCONNECT
// costs the loser an extra −5.
func (ac *Accounts) RecordRankedResultReason(winner, loser, biome, layout string, durationTicks int, replayID, reason string) (RankedOutcome, RankedOutcome, error) {
	return ac.recordRankedResult(winner, loser, biome, layout, durationTicks, replayID, reason)
}

func (ac *Accounts) recordRankedResult(winner, loser, biome, layout string, durationTicks int, replayID, reason string) (RankedOutcome, RankedOutcome, error) {
	ac.mu.Lock()
	defer ac.mu.Unlock()
	w, okW := ac.store.GetAccount(winner)
	l, okL := ac.store.GetAccount(loser)
	if !okW || !okL {
		return RankedOutcome{}, RankedOutcome{}, ErrBadCredentials // an account vanished mid-match
	}
	// A result banked after a season rollover lands in the NEW
	// season: apply pending resets before the star math.
	ac.seasonTouch(w)
	ac.seasonTouch(l)
	wMMR, lMMR := EffectiveMMR(w), EffectiveMMR(l)
	wNew := wMMR + eloDelta(wMMR, lMMR, 1)
	lNew := lMMR + eloDelta(lMMR, wMMR, 0)
	if wNew < MMRFloor {
		wNew = MMRFloor
	}
	if lNew < MMRFloor {
		lNew = MMRFloor
	}
	now := ac.now().Unix()
	var wRank, lRank RankOutcome
	w.Rank, wRank = applyRankWin(w.Rank)
	l.Rank, lRank = applyRankLoss(l.Rank)
	// Daily bonus (13i): the winner's FIRST ranked win of the
	// server-local day earns one extra star, stacked on top of the
	// normal (and any streak) star — granted inside this same
	// atomic banking operation so a result can never be recorded
	// without it or with it twice. A loss never claims the day.
	if !ac.dailyBonusClaimed(w) {
		pre := w.Rank
		w.Rank.addStar()
		w.Rank.updatePeak()
		wRank.StarDelta++
		wRank.DailyBonus = true
		if compareRank(w.Rank, pre) > 0 &&
			(w.Rank.Tier != pre.Tier || w.Rank.Division != pre.Division) {
			wRank.Promoted = true
		}
		wRank.After = w.Rank
		w.DailyBonusDay = dayKey(ac.now())
	}
	// Rolling per-account match history for the home lobby
	// (13g): each side records the match from its own viewpoint.
	w.MatchHistory = appendMatchHistory(w.MatchHistory, MatchRecord{
		Opponent: EffectiveDisplayName(l), Won: true,
		RankFrom:  rankViewFromState(wRank.Before, false).RankText,
		RankTo:    rankViewFromState(wRank.After, false).RankText,
		StarDelta: wRank.StarDelta,
		StarBonus: wRank.Bonus, DailyBonus: wRank.DailyBonus,
		MMRBefore: wMMR, MMRAfter: wNew, At: now,
		Biome: biome, Layout: layout, DurationTicks: durationTicks,
		ReplayID: replayID,
	})
	l.MatchHistory = appendMatchHistory(l.MatchHistory, MatchRecord{
		Opponent: EffectiveDisplayName(w), Won: false,
		RankFrom:  rankViewFromState(lRank.Before, false).RankText,
		RankTo:    rankViewFromState(lRank.After, false).RankText,
		StarDelta: lRank.StarDelta,
		MMRBefore: lMMR, MMRAfter: lNew, At: now,
		Biome: biome, Layout: layout, DurationTicks: durationTicks,
		ReplayID: replayID,
	})
	// A promotion earns the winner a system letter.
	if wRank.Promoted {
		after := rankViewFromState(wRank.After, false)
		before := rankViewFromState(wRank.Before, false)
		w.appendLetter("Lên hạng "+after.ShortText,
			fmt.Sprintf("Chúc mừng! Chiến thắng trước %s đã đưa bạn từ %s lên %s (Mùa %d).\n\nGiữ vững chuỗi thắng để nhận sao thưởng và tiếp tục leo hạng!",
				loser, before.RankText, after.RankText, w.Rank.Season), now)
	}
	// Gross earned stars this season (13l): every star the winner
	// gained (base + streak bonus + daily bonus) counts.
	if wRank.StarDelta > 0 {
		w.SeasonStars += wRank.StarDelta
	}
	// Reputation (13l): +1 per completed ranked match for both
	// sides; the disconnect-forfeit loser pays −5 on top.
	w.applyCredit(+1)
	l.applyCredit(+1)
	if reason == "disconnect" {
		l.applyCredit(-5)
	}
	w.Matches++
	w.Wins++
	w.MMR = wNew
	w.LastPlayed = now
	l.Matches++
	l.Losses++
	l.MMR = lNew
	l.LastPlayed = now
	if err := ac.store.PutAccount(w); err != nil {
		return RankedOutcome{}, RankedOutcome{}, err
	}
	if err := ac.store.PutAccount(l); err != nil {
		return RankedOutcome{}, RankedOutcome{}, err
	}
	return RankedOutcome{User: winner, Won: true, MMRBefore: wMMR, MMRAfter: wNew, Rank: wRank},
		RankedOutcome{User: loser, Won: false, MMRBefore: lMMR, MMRAfter: lNew, Rank: lRank}, nil
}

// RecordRankedPlacements banks one finished RANKED free-for-all
// match (13z) for the whole field at once: users are ordered
// 1st -> last. Per player, atomically: FFA Elo (eloDeltaFFA from
// pre-match ratings), the placement star table (applyRankPlacement
// — 1st composes as a win with streak + the daily first-win star),
// W/L (1st = win, everyone else = loss), a history record carrying
// the placement, reputation (+1 for completing; −5 extra for a
// player whose elimination was a disconnect) and the promotion
// letter. Returns one RankedOutcome per user, in input order.
func (ac *Accounts) RecordRankedPlacements(users []string, biome, layout string, durationTicks int, replayID string, disconnects map[string]bool) ([]RankedOutcome, error) {
	field := len(users)
	if field < 2 {
		return nil, ErrBadCredentials
	}
	ac.mu.Lock()
	defer ac.mu.Unlock()
	accs := make([]*Account, field)
	preMMR := make([]int, field)
	for i, user := range users {
		a, ok := ac.store.GetAccount(user)
		if !ok {
			return nil, ErrBadCredentials // an account vanished mid-match
		}
		ac.seasonTouch(a)
		accs[i] = a
		preMMR[i] = EffectiveMMR(a)
	}
	now := ac.now().Unix()
	outcomes := make([]RankedOutcome, field)
	for i, a := range accs {
		placement := i + 1
		opps := make([]int, 0, field-1)
		for j, m := range preMMR {
			if j != i {
				opps = append(opps, m)
			}
		}
		newMMR := preMMR[i] + eloDeltaFFA(preMMR[i], opps, placement, field)
		if newMMR < MMRFloor {
			newMMR = MMRFloor
		}
		a.Rank, outcomes[i].Rank = applyRankPlacement(a.Rank, placement, field)
		rk := &outcomes[i].Rank
		// Daily bonus (13i rule, placement form): the day's first
		// 1st-place finish earns one extra star, folded in here so
		// it can never be granted twice or skipped.
		if placement == 1 && !ac.dailyBonusClaimed(a) {
			pre := a.Rank
			a.Rank.addStar()
			a.Rank.updatePeak()
			rk.StarDelta++
			rk.DailyBonus = true
			if compareRank(a.Rank, pre) > 0 &&
				(a.Rank.Tier != pre.Tier || a.Rank.Division != pre.Division) {
				rk.Promoted = true
			}
			rk.After = a.Rank
			a.DailyBonusDay = dayKey(ac.now())
		}
		a.MatchHistory = appendMatchHistory(a.MatchHistory, MatchRecord{
			Opponent: fmt.Sprintf("Đấu tự do · %d người", field),
			Won:      placement == 1, Placement: placement,
			RankFrom:  rankViewFromState(rk.Before, false).RankText,
			RankTo:    rankViewFromState(rk.After, false).RankText,
			StarDelta: rk.StarDelta,
			StarBonus: rk.Bonus, DailyBonus: rk.DailyBonus,
			MMRBefore: preMMR[i], MMRAfter: newMMR, At: now,
			Biome: biome, Layout: layout, DurationTicks: durationTicks,
			ReplayID: replayID,
		})
		if rk.Promoted {
			after := rankViewFromState(rk.After, false)
			before := rankViewFromState(rk.Before, false)
			a.appendLetter("Lên hạng "+after.ShortText,
				fmt.Sprintf("Chúc mừng! Vị trí %d/%d trong trận đấu tự do đã đưa bạn từ %s lên %s (Mùa %d).\n\nGiữ vững phong độ để nhận sao thưởng và tiếp tục leo hạng!",
					placement, field, before.RankText, after.RankText, a.Rank.Season), now)
		}
		if rk.StarDelta > 0 {
			a.SeasonStars += rk.StarDelta
		}
		// Reputation (13l): +1 for a completed ranked match; a
		// disconnect elimination costs −5 on top.
		a.applyCredit(+1)
		if disconnects[a.User] {
			a.applyCredit(-5)
		}
		a.Matches++
		if placement == 1 {
			a.Wins++
		} else {
			a.Losses++
		}
		a.MMR = newMMR
		a.LastPlayed = now
		outcomes[i].User = a.User
		outcomes[i].Won = placement == 1
		outcomes[i].MMRBefore = preMMR[i]
		outcomes[i].MMRAfter = newMMR
		outcomes[i].Placement = placement
	}
	for _, a := range accs {
		if err := ac.store.PutAccount(a); err != nil {
			return nil, err
		}
	}
	return outcomes, nil
}

// RecordRankedResult banks one finished RANKED match: W/L for both
// accounts plus their Elo updates, as one serialised operation (the
// caller is the room's referee — see the trust model in README).
// Returns the two new ratings.
func (ac *Accounts) RecordRankedResult(winner, loser string) (int, int, error) {
	wo, lo, err := ac.RecordRankedResultFull(winner, loser)
	if err != nil {
		return 0, 0, err
	}
	return wo.MMRAfter, lo.MMRAfter, nil
}

// ladderRows: the FULL seasonal ladder, sorted — top by ladder
// position (tier, division, stars), then MMR, then name. Hoàng Đế
// flags are computed across the whole account base (top 50 Công
// Tước), not just within any shown window.
func (ac *Accounts) ladderRows() []LeaderRow {
	all := ac.touchedAccounts()
	emp := EmperorSet(all)
	byUser := make(map[string]*Account, len(all))
	rows := make([]LeaderRow, 0, len(all))
	for _, a := range all {
		byUser[a.User] = a
		rows = append(rows, leaderRowOf(a, emp[a.User]))
	}
	sort.Slice(rows, func(i, j int) bool {
		if c := compareRank(byUser[rows[i].User].Rank, byUser[rows[j].User].Rank); c != 0 {
			return c > 0
		}
		if rows[i].MMR != rows[j].MMR {
			return rows[i].MMR > rows[j].MMR
		}
		return rows[i].User < rows[j].User
	})
	return rows
}

// RankedLeaderboard: the "Xếp hạng" board — top 20 of the ladder.
func (ac *Accounts) RankedLeaderboard() []LeaderRow {
	rows := ac.ladderRows()
	if len(rows) > 20 {
		rows = rows[:20]
	}
	return rows
}

// LeaderboardV2 serves the restyled board (13g addendum): the top
// 20 rows of the requested ordering PLUS the caller's own position
// and row — computed over the FULL ordering, so the sticky
// "Hạng của tôi" footer is truthful even outside the top 20.
// Modes: "ranked" (full ladder), "friends" (ladder filtered to
// the caller + their friend list; guests get nothing), "wl"
// (wins leaderboard). mePos is 1-based; meRow is nil for guests
// or unknown callers.
func (ac *Accounts) LeaderboardV2(mode, user string) (rows []LeaderRow, mePos int, meRow *LeaderRow) {
	var full []LeaderRow
	switch mode {
	case "friends":
		if user == "" {
			return nil, 0, nil
		}
		me, ok := ac.store.GetAccount(user)
		if !ok {
			return nil, 0, nil
		}
		keep := map[string]bool{user: true}
		for _, f := range me.Friends {
			keep[f] = true
		}
		for _, r := range ac.ladderRows() {
			if keep[r.User] {
				full = append(full, r)
			}
		}
	case "wl":
		full = ac.wlRows()
	default: // "ranked"
		full = ac.ladderRows()
	}
	rows = full
	if len(rows) > 20 {
		rows = rows[:20]
	}
	if user != "" {
		for i, r := range full {
			if r.User == user {
				mePos = i + 1
				row := r
				meRow = &row
				break
			}
		}
	}
	return rows, mePos, meRow
}

// ------------------------------------------------------------- seasons

// DefaultSeasonDays is the season length when -season-days is not
// given (or is not positive).
const DefaultSeasonDays = 90

// MetaSeasonEpoch is the store-meta key holding the unix time at
// which season 1 started (written once, at first touch).
const MetaSeasonEpoch = "season_epoch"

func (ac *Accounts) seasonLength() time.Duration {
	d := ac.SeasonDays
	if d <= 0 {
		d = DefaultSeasonDays
	}
	return time.Duration(d) * 24 * time.Hour
}

// seasonEpoch returns when season 1 began, initialising the meta
// value on first use (the server's first boot with the ladder).
func (ac *Accounts) seasonEpoch() int64 {
	if raw, ok := ac.store.GetMeta(MetaSeasonEpoch); ok {
		var v int64
		if _, err := fmt.Sscanf(raw, "%d", &v); err == nil && v > 0 {
			return v
		}
	}
	epoch := ac.now().Unix()
	_ = ac.store.PutMeta(MetaSeasonEpoch, fmt.Sprintf("%d", epoch))
	return epoch
}

// CurrentSeason is the 1-based season containing "now": season 1
// starts at the stored epoch, each season lasts SeasonDays.
func (ac *Accounts) CurrentSeason() int {
	epoch := ac.seasonEpoch()
	now := ac.now().Unix()
	if now <= epoch {
		return 1
	}
	return 1 + int((now-epoch)/int64(ac.seasonLength()/time.Second))
}

// seasonTouch applies the pending season transition to an account
// COPY: pre-ladder accounts initialise in place (no reset, no
// history); accounts behind the current season archive their
// finished season and take the soft reset (ladder per
// seasonResetRank, MMR halved toward MMRStart). Reports whether
// the account changed and should be persisted. Idempotent: a
// second touch in the same season changes nothing.
func (ac *Accounts) seasonTouch(a *Account) bool {
	cur := ac.CurrentSeason()
	if a.Rank.Season == cur {
		return false
	}
	if a.Rank.Season > cur {
		return false // clock moved backwards; leave the state alone
	}
	if a.Rank.Season <= 0 {
		a.Rank.Season = cur
		a.Rank.PeakTier = a.Rank.Tier
		a.Rank.PeakDivision = a.Rank.Division
		return true
	}
	finishedSeason := a.Rank.Season
	finalView := rankViewFromState(a.Rank, false)
	peak := RankState{Tier: a.Rank.PeakTier, Division: a.Rank.PeakDivision}
	a.History = append(a.History, SeasonRecord{
		Season:        a.Rank.Season,
		FinalTier:     a.Rank.Tier,
		FinalDivision: a.Rank.Division,
		FinalStars:    a.Rank.Stars,
		PeakTier:      a.Rank.PeakTier,
		PeakDivision:  a.Rank.PeakDivision,
		TotalStars:    a.SeasonStars,
		Emperor:       ac.emperorSet()[a.User],
	})
	a.SeasonStars = 0
	a.Rank = seasonResetRank(a.Rank)
	// Season-summary letter: where the account ended the season
	// and where the soft reset places it for the new one.
	a.appendLetter(fmt.Sprintf("Tổng kết Mùa %d", finishedSeason),
		fmt.Sprintf("Mùa %d đã kết thúc. Bạn khép lại mùa ở %s, đỉnh mùa đạt %s.\n\nMùa %d bắt đầu: hạng của bạn được đặt lại mềm về %s và MMR được nén về giữa. Chúc bạn leo hạng cao hơn ở mùa mới!",
			finishedSeason, finalView.RankText, peak.ShortText(), cur,
			rankViewFromState(a.Rank, false).ShortText),
		ac.now().Unix())
	a.Rank.Season = cur
	if a.MMR != 0 {
		a.MMR = MMRStart + (a.MMR-MMRStart)/2
		if a.MMR < MMRFloor {
			a.MMR = MMRFloor
		}
	}
	return true
}

// touch applies a pending season transition to an account copy and
// persists it when anything changed.
func (ac *Accounts) touch(a *Account) {
	if ac.seasonTouch(a) {
		_ = ac.store.PutAccount(a)
	}
}

// emperorSet resolves the current Hoàng Đế holders (rank.go).
func (ac *Accounts) emperorSet() map[string]bool {
	return EmperorSet(ac.store.Accounts())
}
