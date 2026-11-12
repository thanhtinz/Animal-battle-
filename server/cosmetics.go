package main

// Empire Age 17d — profile cosmetics: the account AVATAR
// catalogue, avatar FRAMES, chat-BUBBLE styles and the title
// catalogue, plus the rename cooldown. Everything here is
// presentation data: it never enters the sim, the checksum or
// any match record.
//
// Avatar catalogue (OWNER CORRECTION 2 + ADDITION, 2026-11-12):
// ONLY the twenty anime avatars the owner supplied (art_01..art_20
// in art_candidates/avatars_anime/, built into the client by
// tools/build_account_avatars.py). The zip fan-art set was
// dropped entirely, and the eight hero portraits are no longer
// account avatars — they remain only on hero surfaces
// (Collection, in-match hero UI). Every avatar is FREE for
// every account; the default is art:01, and any stored value
// outside the catalogue (e.g. a pre-17d hero id) normalises
// to the default, which is the migration path.
//
// Frames (Đại chiến spec §7.2A): the owner's eleven animated
// frames. Ownership is COMPUTED from live account data —
// level, recorded wins, peak rank tier, the tournament
// champion title, the account's CURRENT alliance level, and
// the reigning alliance-war champion seam — never stored, so
// a frame whose condition lapses (leaving a level-5 alliance,
// losing the war reign) stops being owned, and an equipped
// frame that stops being owned stops rendering (the profile
// falls back to no frame). Sources whose systems do not
// exist yet grant nothing and say so in their unlock text:
//   - frame_09 (alliance weekly quests, cumulative): the
//     per-account cumulative quest counter does not exist.
//   - frame_12 (reigning Đại chiến champion): the war system
//     itself does not exist yet; the WarChampOf seam below is
//     where it will plug in (nil today → nobody owns it).
//
// Bubble styles (spec §7.2B): default for everyone, a rank
// style at Kỵ Sĩ peak, and the war-champion style behind the
// same WarChampOf seam.

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// ------------------------------------------------------------- avatars

// AvatarDefaultID is the account avatar every account starts
// with and every unknown stored value falls back to.
const AvatarDefaultID = "art:01"

// AvatarIDs is the full selectable catalogue, in display
// order. Ids are namespaced ("art:NN") so a future set can
// never collide with these.
var AvatarIDs = func() []string {
	out := make([]string, 0, 20)
	for i := 1; i <= 20; i++ {
		out = append(out, fmt.Sprintf("art:%02d", i))
	}
	return out
}()

var avatarIDSet = func() map[string]bool {
	m := make(map[string]bool, len(AvatarIDs))
	for _, id := range AvatarIDs {
		m[id] = true
	}
	return m
}()

// NormalizeAvatarID maps any stored/picked value to a
// catalogue avatar: unknown values (including every pre-17d
// hero id) fall back to the default.
func NormalizeAvatarID(id string) string {
	if avatarIDSet[id] {
		return id
	}
	return AvatarDefaultID
}

// ------------------------------------------------------------- frames

// FrameIDs in display order ("" = no frame, the default).
var FrameIDs = []string{
	"frame_01", "frame_03", "frame_04", "frame_05", "frame_06",
	"frame_07", "frame_08", "frame_09", "frame_10", "frame_11",
	"frame_12",
}

// FrameNames are the display names from spec §7.2A.
var FrameNames = map[string]string{
	"frame_01": "Dây Dâu Tây",
	"frame_03": "Mặt Mèo",
	"frame_04": "Hoa Hồng Bướm Xanh",
	"frame_05": "Sân Khấu Trái Tim",
	"frame_06": "Sao Vàng",
	"frame_07": "Cột Hy Lạp",
	"frame_08": "Mây Anh Đào",
	"frame_09": "Rèm Sân Khấu",
	"frame_10": "Cửa Sổ Anh Đào",
	"frame_11": "Đá Rêu Nấm",
	"frame_12": "Ruy Băng Sao",
}

// FrameUnlockText is the honest unlock condition shown for an
// unowned frame. The two "chưa mở" entries name the missing
// system instead of promising a condition that cannot be met.
var FrameUnlockText = map[string]string{
	"frame_01": "Đạt cấp tài khoản 5",
	"frame_03": "Đạt cấp tài khoản 15",
	"frame_04": "Ở trong liên minh cấp 3 trở lên",
	"frame_05": "Thắng 50 trận (mọi chế độ ghi sổ)",
	"frame_06": "Đạt bậc Hầu Tước trong thang mùa Hạng",
	"frame_07": "Vô địch một giải đấu người chơi",
	"frame_08": "Đạt cấp tài khoản 25",
	"frame_09": "Nhiệm vụ tuần của liên minh — hệ thống đếm cộng dồn chưa mở",
	"frame_10": "Ở trong liên minh cấp 5 trở lên",
	"frame_11": "Thắng 150 trận (mọi chế độ ghi sổ)",
	"frame_12": "Liên minh vô địch Đại chiến tháng — giải Đại chiến chưa mở",
}

var frameIDSet = func() map[string]bool {
	m := make(map[string]bool, len(FrameIDs))
	for _, id := range FrameIDs {
		m[id] = true
	}
	return m
}()

// ------------------------------------------------------------- bubbles

// BubbleIDs in display order; BubbleDefault is free for all.
const BubbleDefault = "mac_dinh"

// Bubble style ids (17d).
const (
	BubbleRank     = "hang"
	BubbleWarChamp = "vo_dich"
)

var BubbleIDs = []string{"mac_dinh", "hang", "vo_dich"}

var BubbleNames = map[string]string{
	"mac_dinh": "Mặc định",
	"hang":     "Hạng",
	"vo_dich":  "Vô địch Đại chiến",
}

var BubbleUnlockText = map[string]string{
	"mac_dinh": "Có sẵn cho mọi tài khoản",
	"hang":     "Đạt bậc Kỵ Sĩ trong thang mùa Hạng",
	"vo_dich":  "Liên minh vô địch Đại chiến tháng — giải Đại chiến chưa mở",
}

var bubbleIDSet = func() map[string]bool {
	m := make(map[string]bool, len(BubbleIDs))
	for _, id := range BubbleIDs {
		m[id] = true
	}
	return m
}()

// NormalizeBubbleStyle maps a stored value to a known style.
func NormalizeBubbleStyle(id string) string {
	if bubbleIDSet[id] {
		return id
	}
	return BubbleDefault
}

// ------------------------------------------------------------- titles

// TitleRow is one catalogue line for the Danh hiệu panel:
// what the title is, how it is earned, whether this account
// owns it, and its thời hạn (expiry/reign wording).
type TitleRow struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	How      string `json:"how"`
	Owned    bool   `json:"owned"`
	Expiry   string `json:"expiry"`
	Equipped bool   `json:"equipped"`
}

// Title catalogue ids (the display names are the earned
// strings themselves: TitleChampion for the tournament title;
// the war title's name is the literal §7.1 string).
const (
	TitleIDChampion    = "champion"
	TitleIDWarChampion = "war_champion"
	TitleWarChampion   = "Liên minh vô địch"
)

// ------------------------------------------------------------- errors

var (
	ErrBadFrame       = errors.New("khung avatar không hợp lệ")
	ErrFrameNotOwned  = errors.New("chưa sở hữu khung này")
	ErrBadBubble      = errors.New("kiểu bong bóng không hợp lệ")
	ErrBubbleNotOwned = errors.New("chưa sở hữu kiểu bong bóng này")
	ErrTitleNotOwned  = errors.New("chưa sở hữu danh hiệu này")
)

// RenameCooldownError reports a rename attempted inside the
// 30-day cooldown; NextAt is the unix time the next rename
// becomes available.
type RenameCooldownError struct{ NextAt int64 }

func (e *RenameCooldownError) Error() string {
	return fmt.Sprintf("Đổi tên quá sớm — đổi lại được từ %s",
		time.Unix(e.NextAt, 0).Format("02/01/2006"))
}

// RenameCooldown is the owner's rule: one rename per month.
const RenameCooldown = 30 * 24 * time.Hour

// ------------------------------------------------------------- ownership

// peakTierOf is the highest ladder tier the account has ever
// reached: current state, its recorded peak, and every past
// season's final tier.
func peakTierOf(a *Account) int {
	peak := a.Rank.Tier
	if a.Rank.PeakTier > peak {
		peak = a.Rank.PeakTier
	}
	for _, h := range a.History {
		if h.FinalTier > peak {
			peak = h.FinalTier
		}
	}
	return peak
}

func (ac *Accounts) allyLevelOf(user string) int {
	if ac.AllyLevelOf == nil {
		return 0
	}
	return ac.AllyLevelOf(user)
}

func (ac *Accounts) warChampOf(user string) bool {
	if ac.WarChampOf == nil {
		return false
	}
	return ac.WarChampOf(user)
}

// frameOwned evaluates ONE frame's §7.2A condition against
// the account's live data.
func (ac *Accounts) frameOwned(a *Account, id string) bool {
	level, _, _ := LevelForXP(XPFor(a.Matches, a.Wins))
	switch id {
	case "frame_01":
		return level >= 5
	case "frame_03":
		return level >= 15
	case "frame_04":
		return ac.allyLevelOf(a.User) >= 3
	case "frame_05":
		return a.Wins >= 50
	case "frame_06":
		return peakTierOf(a) >= TierHauTuoc
	case "frame_07":
		for _, t := range a.Titles {
			if t == TitleChampion {
				return true
			}
		}
		return false
	case "frame_08":
		return level >= 25
	case "frame_09":
		// Cumulative alliance-weekly-quest completions are not
		// tracked per account yet — grants nothing (see the
		// unlock text).
		return false
	case "frame_10":
		return ac.allyLevelOf(a.User) >= 5
	case "frame_11":
		return a.Wins >= 150
	case "frame_12":
		return ac.warChampOf(a.User)
	}
	return false
}

// bubbleOwned evaluates ONE bubble style's condition.
func (ac *Accounts) bubbleOwned(a *Account, id string) bool {
	switch id {
	case "mac_dinh":
		return true
	case "hang":
		return peakTierOf(a) >= TierKySi
	case "vo_dich":
		return ac.warChampOf(a.User)
	}
	return false
}

// cosmeticsOf computes the account's full cosmetics state:
// owned frames/bubbles in catalogue order, the EFFECTIVE
// equipped values (an equipped item that is no longer owned
// resolves to the default), and the Danh hiệu catalogue rows.
func (ac *Accounts) cosmeticsOf(a *Account) (ownedFrames, ownedBubbles []string,
	effFrame, effBubble string, rows []TitleRow) {
	ownedFrames = []string{}
	for _, id := range FrameIDs {
		if ac.frameOwned(a, id) {
			ownedFrames = append(ownedFrames, id)
		}
	}
	ownedBubbles = []string{}
	for _, id := range BubbleIDs {
		if ac.bubbleOwned(a, id) {
			ownedBubbles = append(ownedBubbles, id)
		}
	}
	effFrame = ""
	if frameIDSet[a.FrameID] && ac.frameOwned(a, a.FrameID) {
		effFrame = a.FrameID
	}
	effBubble = BubbleDefault
	if bubbleIDSet[a.BubbleStyle] && ac.bubbleOwned(a, a.BubbleStyle) {
		effBubble = a.BubbleStyle
	}
	// Titles: the stored list (tournament champion today) plus
	// the war-champion title while the seam says the account
	// holds the reign.
	hasChamp := false
	for _, t := range a.Titles {
		if t == TitleChampion {
			hasChamp = true
		}
	}
	warOwned := ac.warChampOf(a.User)
	rows = []TitleRow{
		{ID: TitleIDChampion, Name: TitleChampion,
			How:   "Vô địch một giải đấu người chơi",
			Owned: hasChamp, Expiry: "Vĩnh viễn",
			Equipped: a.DisplayTitle == TitleChampion},
		{ID: TitleIDWarChampion, Name: TitleWarChampion,
			How:   "Thuộc liên minh thắng chung kết Đại chiến tháng (giữ ngôi)",
			Owned: warOwned, Expiry: "Khi đang giữ ngôi vô địch Đại chiến",
			Equipped: a.DisplayTitle == TitleWarChampion},
	}
	return ownedFrames, ownedBubbles, effFrame, effBubble, rows
}

// titleOwned reports whether the account may equip this
// display title ("" always allowed — it clears the slot).
func (ac *Accounts) titleOwned(a *Account, name string) bool {
	switch name {
	case "":
		return true
	case TitleChampion:
		for _, t := range a.Titles {
			if t == TitleChampion {
				return true
			}
		}
		return false
	case TitleWarChampion:
		return ac.warChampOf(a.User)
	}
	return false
}

// AvatarOf returns the user's effective (normalised) account
// avatar id for presentation payloads ("" for guests/unknown).
func (ac *Accounts) AvatarOf(user string) string {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return ""
	}
	return EffectiveAvatar(a)
}

// EquippedFrameOf resolves a user's EFFECTIVE equipped frame
// ("" = none) for cross-player payloads (room views, friend
// rows, leaderboard rows).
func (ac *Accounts) EquippedFrameOf(user string) string {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return ""
	}
	_, _, effFrame, _, _ := ac.cosmeticsOf(a)
	return effFrame
}

// EquippedBubbleOf resolves a user's EFFECTIVE equipped
// bubble style for chat relays.
func (ac *Accounts) EquippedBubbleOf(user string) string {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return BubbleDefault
	}
	_, _, _, effBubble, _ := ac.cosmeticsOf(a)
	return effBubble
}

// ------------------------------------------------------------- setters

// SetFrame equips (or with "" unequips) an avatar frame. The
// frame must exist and be OWNED by the computed rules.
func (ac *Accounts) SetFrame(user, id string) (Profile, error) {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, ErrBadCredentials
	}
	if id != "" {
		if !frameIDSet[id] {
			return Profile{}, ErrBadFrame
		}
		if !ac.frameOwned(a, id) {
			return Profile{}, ErrFrameNotOwned
		}
	}
	ac.touch(a)
	a.FrameID = id
	if err := ac.store.PutAccount(a); err != nil {
		return Profile{}, err
	}
	return ac.profileOf(a), nil
}

// SetBubbleStyle equips a chat-bubble style (owned only).
func (ac *Accounts) SetBubbleStyle(user, id string) (Profile, error) {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, ErrBadCredentials
	}
	if !bubbleIDSet[id] {
		return Profile{}, ErrBadBubble
	}
	if !ac.bubbleOwned(a, id) {
		return Profile{}, ErrBubbleNotOwned
	}
	ac.touch(a)
	a.BubbleStyle = id
	if err := ac.store.PutAccount(a); err != nil {
		return Profile{}, err
	}
	return ac.profileOf(a), nil
}

// SetDisplayTitle equips the title shown on the profile's
// Danh hiệu row ("" = none). The title must be owned. (The
// <Liên minh vô địch> CHAT suffix is automatic per spec §7.1
// and is not this equip.)
func (ac *Accounts) SetDisplayTitle(user, name string) (Profile, error) {
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, ErrBadCredentials
	}
	name = strings.TrimSpace(name)
	if !ac.titleOwned(a, name) {
		return Profile{}, ErrTitleNotOwned
	}
	ac.touch(a)
	a.DisplayTitle = name
	if err := ac.store.PutAccount(a); err != nil {
		return Profile{}, err
	}
	return ac.profileOf(a), nil
}

// ------------------------------------------------------------- rename

// RenameDisplayName is SetDisplayName plus the owner's
// cooldown rule (17d): renaming an EXISTING display name is
// allowed once per RenameCooldown (30 days). The FIRST name
// set (DisplayName == "") never consumes the cooldown, and
// neither does re-submitting the identical name. A rejected
// early rename returns *RenameCooldownError carrying the
// next available time.
func (ac *Accounts) RenameDisplayName(user, name string) (Profile, error) {
	name = strings.TrimSpace(name)
	if !validDisplayName(name) {
		return Profile{}, ErrInvalidName
	}
	a, ok := ac.store.GetAccount(user)
	if !ok {
		return Profile{}, ErrBadCredentials
	}
	if a.DisplayName == name {
		return ac.profileOf(a), nil // no-op: never consumes
	}
	renaming := a.DisplayName != ""
	if renaming && a.LastRenameAt > 0 {
		next := a.LastRenameAt + int64(RenameCooldown/time.Second)
		if ac.now().Unix() < next {
			return Profile{}, &RenameCooldownError{NextAt: next}
		}
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
	if renaming {
		a.LastRenameAt = ac.now().Unix()
	}
	if err := ac.store.PutAccount(a); err != nil {
		return Profile{}, err
	}
	return ac.profileOf(a), nil
}

// renameNextAt is when the account may rename again (0 =
// right now): derived from LastRenameAt + the cooldown.
func renameNextAt(a *Account) int64 {
	if a == nil || a.LastRenameAt <= 0 {
		return 0
	}
	return a.LastRenameAt + int64(RenameCooldown/time.Second)
}
