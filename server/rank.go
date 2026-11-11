package main

// Seasonal rank ladder — Liên Quân (Arena of Valor) STRUCTURE with
// Empire Age medieval-empire display names (Tín's rename order:
// the metal names were only ever the skeleton).
//
// The ladder (low -> high):
//
//	Tân Binh · Chiến Binh · Kỵ Sĩ · Nam Tước · Bá Tước · Hầu Tước
//	· Công Tước · Hoàng Đế
//
//   - Tân Binh .. Bá Tước: divisions III -> II -> I, 3 stars each.
//   - Hầu Tước: divisions III -> II -> I, 5 stars each (harder).
//   - Công Tước: no divisions — a pure, unbounded star count.
//   - Hoàng Đế: NOT a stored tier — a computed status held by the
//     top 50 Công Tước accounts on the server (by stars, then MMR).
//
// Star math (per referee-reported ranked result):
//   - Win: +1 star. A win while the current win streak is >= 3
//     grants +1 BONUS star (at most one bonus per match).
//   - Gaining a star at a full division (stars == cap) converts it
//     into a promotion: the player moves up one division (or tier)
//     and lands with 1 star in the new division.
//   - Loss: -1 star; at 0 stars the loss demotes one division (or
//     tier) and lands at cap-1 stars there. Hard floor: Tân Binh
//     III at 0 stars cannot drop further (the loss costs nothing).
//
// Rank and MMR evolve from the same results but independently:
// rank is the visible ladder, MMR stays the hidden matchmaking
// number. Seasons (see accounts.go) soft-reset the ladder.

import (
	"fmt"
	"sort"
)

// Tier indices, low -> high. TierHoangDe is display/computation
// only — a RankState never stores it.
const (
	TierTanBinh = iota
	TierChienBinh
	TierKySi
	TierNamTuoc
	TierBaTuoc
	TierHauTuoc
	TierCongTuoc
	TierHoangDe
)

// RankTierSlugs are the stable internal keys; RankTierNames are
// the user-visible Vietnamese display names (medieval titles:
// soldier -> warrior -> knight -> baron -> count -> marquis ->
// duke -> emperor).
var RankTierSlugs = []string{
	"tan_binh", "chien_binh", "ky_si", "nam_tuoc",
	"ba_tuoc", "hau_tuoc", "cong_tuoc", "hoang_de",
}

var RankTierNames = []string{
	"Tân Binh", "Chiến Binh", "Kỵ Sĩ", "Nam Tước",
	"Bá Tước", "Hầu Tước", "Công Tước", "Hoàng Đế",
}

// RankDivisionNames maps the stored division index (0,1,2) to its
// display numeral: 0 = III (lowest), 2 = I (highest).
var RankDivisionNames = []string{"III", "II", "I"}

// RankStarCap is the star capacity of one division of a tier.
// 0 means unbounded (Công Tước — pure star count, no divisions).
func RankStarCap(tier int) int {
	switch {
	case tier >= TierCongTuoc:
		return 0
	case tier == TierHauTuoc:
		return 5
	default:
		return 3
	}
}

// RankState is one account's ladder position inside one season.
type RankState struct {
	Tier         int `json:"tier"`
	Division     int `json:"division"` // 0=III, 1=II, 2=I; unused for Công Tước
	Stars        int `json:"stars"`
	Streak       int `json:"streak"` // consecutive wins (streak-bonus source)
	Season       int `json:"season"` // season this state belongs to; 0 = pre-ladder
	PeakTier     int `json:"peak_tier"`
	PeakDivision int `json:"peak_division"`
}

// SeasonRecord archives one finished season on the account.
type SeasonRecord struct {
	Season        int `json:"season"`
	FinalTier     int `json:"final_tier"`
	FinalDivision int `json:"final_division"`
	FinalStars    int `json:"final_stars"`
	PeakTier      int `json:"peak_tier"`
	PeakDivision  int `json:"peak_division"`
	// TotalStars is the season's gross earned-star total (13l,
	// the profile screen's "Hạng mùa trước ★×N"); Emperor marks
	// that the account held the Hoàng Đế status at the reset.
	TotalStars int  `json:"total_stars,omitempty"`
	Emperor    bool `json:"emperor,omitempty"`
}

func rankTierName(tier int) string {
	if tier < 0 || tier >= len(RankTierNames) {
		return RankTierNames[TierTanBinh]
	}
	return RankTierNames[tier]
}

// ShortText is the rank without stars: "Kỵ Sĩ II", "Công Tước".
func (rs RankState) ShortText() string {
	if rs.Tier >= TierCongTuoc {
		return rankTierName(rs.Tier)
	}
	div := rs.Division
	if div < 0 || div >= len(RankDivisionNames) {
		div = 0
	}
	return fmt.Sprintf("%s %s", rankTierName(rs.Tier), RankDivisionNames[div])
}

// Text is the full display rank: "Kỵ Sĩ II · 2 sao", "Công Tước · 27 sao".
func (rs RankState) Text() string {
	return fmt.Sprintf("%s · %d sao", rs.ShortText(), rs.Stars)
}

// divWeight orders divisions across tiers: a Công Tước (no
// divisions) sits above every Hầu Tước division.
func divWeight(rs RankState) int {
	if rs.Tier >= TierCongTuoc {
		return len(RankDivisionNames) // 3, above I (2)
	}
	return rs.Division
}

// compareRank orders two ladder positions: tier, then division,
// then stars. Returns -1/0/+1 as a ranks below/equal/above b.
func compareRank(a, b RankState) int {
	if a.Tier != b.Tier {
		if a.Tier < b.Tier {
			return -1
		}
		return 1
	}
	if wa, wb := divWeight(a), divWeight(b); wa != wb {
		if wa < wb {
			return -1
		}
		return 1
	}
	if a.Stars != b.Stars {
		if a.Stars < b.Stars {
			return -1
		}
		return 1
	}
	return 0
}

// promoteOne moves up exactly one division step (III->II->I->next
// tier's III). Reports whether a step existed (Công Tước has none).
func (rs *RankState) promoteOne() bool {
	if rs.Tier >= TierCongTuoc {
		return false
	}
	if rs.Division < len(RankDivisionNames)-1 {
		rs.Division++
		return true
	}
	rs.Tier++
	rs.Division = 0
	return true
}

// demoteOne is promoteOne's inverse. Reports false at the ladder
// floor (Tân Binh III).
func (rs *RankState) demoteOne() bool {
	if rs.Tier >= TierCongTuoc {
		rs.Tier = TierHauTuoc
		rs.Division = len(RankDivisionNames) - 1 // Hầu Tước I
		return true
	}
	if rs.Division > 0 {
		rs.Division--
		return true
	}
	if rs.Tier > TierTanBinh {
		rs.Tier--
		rs.Division = len(RankDivisionNames) - 1
		return true
	}
	return false
}

// addStar grants one star, converting into a promotion when the
// division is already full (the promoting star lands as 1 star in
// the new division).
func (rs *RankState) addStar() {
	if rs.Tier >= TierCongTuoc {
		rs.Stars++
		return
	}
	if rs.Stars < RankStarCap(rs.Tier) {
		rs.Stars++
		return
	}
	if rs.promoteOne() {
		rs.Stars = 1
	}
}

// updatePeak records the highest (tier, division) reached this
// season (stars do not count toward the peak).
func (rs *RankState) updatePeak() {
	if rs.Tier > rs.PeakTier ||
		(rs.Tier == rs.PeakTier && divWeight(*rs) > rankPeakWeight(rs.PeakTier, rs.PeakDivision)) {
		rs.PeakTier = rs.Tier
		rs.PeakDivision = rs.Division
	}
}

func rankPeakWeight(tier, div int) int {
	if tier >= TierCongTuoc {
		return len(RankDivisionNames)
	}
	return div
}

// RankOutcome describes one player's ladder movement from a single
// ranked result (it feeds the end-panel display payload).
type RankOutcome struct {
	StarDelta int // stars granted or removed (-1); 0 = floored loss
	Bonus     bool // StarDelta includes the win-streak bonus star
	// DailyBonus: StarDelta also includes the first-ranked-win-of-
	// the-day bonus star (13i). Granted by the accounts layer —
	// applyRankWin/applyRankLoss never set it (they know nothing
	// of dates); RecordRankedResultMeta folds it in atomically.
	DailyBonus bool
	Promoted   bool
	Demoted    bool
	Before     RankState
	After      RankState
}

// WinStreakBonus is the streak length at which wins start paying
// a bonus star.
const WinStreakBonus = 3

// applyRankWin advances a ladder position for one victory.
func applyRankWin(rs RankState) (RankState, RankOutcome) {
	out := RankOutcome{Before: rs}
	beforePos := rs
	rs.Streak++
	gain := 1
	if rs.Streak >= WinStreakBonus {
		gain = 2
		out.Bonus = true
	}
	for i := 0; i < gain; i++ {
		rs.addStar()
	}
	out.StarDelta = gain
	out.Promoted = compareRank(rs, beforePos) > 0 &&
		(rs.Tier != beforePos.Tier || rs.Division != beforePos.Division)
	rs.updatePeak()
	out.After = rs
	return rs, out
}

// PlacementStars is Tín's star table for an 8-player free-for-all
// ranked match (13z): 1st +2, 2nd–3rd +1, 4th–5th 0, 6th–8th −1.
// For fields of another size the same shape generalises: the
// winner takes +2, the next two +1, the bottom three −1 and the
// middle 0 — with tiny fields the bands simply clip.
func PlacementStars(placement, field int) int {
	switch {
	case placement <= 1:
		return 2
	case placement <= 3:
		return 1
	case placement > field-3:
		return -1
	default:
		return 0
	}
}

// applyRankPlacement advances a ladder position for one
// free-for-all placement (13z). A 1st place composes as a WIN:
// the win streak grows, and at streak >= WinStreakBonus one bonus
// star stacks on the placement's +2 (the daily first-win star is
// folded in by the accounts layer, like recordRankedResult).
// Every other placement breaks the streak; 2nd–3rd still gain
// their table star; the −1 band reuses applyRankLoss wholesale
// (demotion + ladder floor included).
func applyRankPlacement(rs RankState, placement, field int) (RankState, RankOutcome) {
	stars := PlacementStars(placement, field)
	switch {
	case placement <= 1:
		out := RankOutcome{Before: rs}
		beforePos := rs
		rs.Streak++
		gain := stars
		if rs.Streak >= WinStreakBonus {
			gain++
			out.Bonus = true
		}
		for i := 0; i < gain; i++ {
			rs.addStar()
		}
		out.StarDelta = gain
		out.Promoted = compareRank(rs, beforePos) > 0 &&
			(rs.Tier != beforePos.Tier || rs.Division != beforePos.Division)
		rs.updatePeak()
		out.After = rs
		return rs, out
	case stars > 0:
		out := RankOutcome{Before: rs}
		beforePos := rs
		rs.Streak = 0
		for i := 0; i < stars; i++ {
			rs.addStar()
		}
		out.StarDelta = stars
		out.Promoted = compareRank(rs, beforePos) > 0 &&
			(rs.Tier != beforePos.Tier || rs.Division != beforePos.Division)
		rs.updatePeak()
		out.After = rs
		return rs, out
	case stars < 0:
		return applyRankLoss(rs)
	default:
		out := RankOutcome{Before: rs}
		rs.Streak = 0
		out.After = rs
		return rs, out
	}
}

// applyRankLoss retreats a ladder position for one defeat.
func applyRankLoss(rs RankState) (RankState, RankOutcome) {
	out := RankOutcome{Before: rs}
	rs.Streak = 0
	switch {
	case rs.Stars > 0:
		rs.Stars--
		out.StarDelta = -1
	case rs.demoteOne():
		// Land one star below the new division's cap.
		rs.Stars = RankStarCap(rs.Tier) - 1
		out.StarDelta = -1
		out.Demoted = true
	default:
		// Tân Binh III at 0 stars: the hard floor. Nothing is lost.
		out.StarDelta = 0
	}
	out.After = rs
	return rs, out
}

// seasonResetRank maps a season's FINAL ladder position to the
// next season's starting position (soft reset):
//
//	Hoàng Đế / Công Tước -> Bá Tước III
//	Hầu Tước             -> Nam Tước II
//	Bá Tước              -> Nam Tước III
//	Nam Tước             -> Kỵ Sĩ II
//	Kỵ Sĩ                -> Kỵ Sĩ III
//	Chiến Binh           -> Chiến Binh III
//	Tân Binh             -> Tân Binh III
func seasonResetRank(final RankState) RankState {
	var tier, div int
	switch {
	case final.Tier >= TierCongTuoc:
		tier, div = TierBaTuoc, 0
	case final.Tier == TierHauTuoc:
		tier, div = TierNamTuoc, 1
	case final.Tier == TierBaTuoc:
		tier, div = TierNamTuoc, 0
	case final.Tier == TierNamTuoc:
		tier, div = TierKySi, 1
	case final.Tier == TierKySi:
		tier, div = TierKySi, 0
	case final.Tier == TierChienBinh:
		tier, div = TierChienBinh, 0
	default:
		tier, div = TierTanBinh, 0
	}
	return RankState{
		Tier: tier, Division: div, Stars: 0,
		PeakTier: tier, PeakDivision: div,
	}
}

// EmperorLimit is how many Công Tước accounts hold the Hoàng Đế
// status at once.
const EmperorLimit = 50

// EmperorSet computes the Hoàng Đế holders from raw accounts:
// every Công Tước, best first (stars, then effective MMR, then
// name for stability), capped at EmperorLimit.
func EmperorSet(all []*Account) map[string]bool {
	dukes := make([]*Account, 0, len(all))
	for _, a := range all {
		if a.Rank.Tier >= TierCongTuoc {
			dukes = append(dukes, a)
		}
	}
	sort.Slice(dukes, func(i, j int) bool {
		if dukes[i].Rank.Stars != dukes[j].Rank.Stars {
			return dukes[i].Rank.Stars > dukes[j].Rank.Stars
		}
		if mi, mj := EffectiveMMR(dukes[i]), EffectiveMMR(dukes[j]); mi != mj {
			return mi > mj
		}
		return dukes[i].User < dukes[j].User
	})
	out := make(map[string]bool)
	for i, a := range dukes {
		if i >= EmperorLimit {
			break
		}
		out[a.User] = true
	}
	return out
}

// RankView is the wire/display form of an account's ladder state.
type RankView struct {
	Tier           int    `json:"tier"`
	TierSlug       string `json:"tier_slug"`
	TierName       string `json:"tier_name"`
	Division       int    `json:"division"` // -1 for Công Tước/Hoàng Đế
	DivisionName   string `json:"division_name"`
	Stars          int    `json:"stars"`
	StarCap        int    `json:"star_cap"` // 0 = unbounded
	Streak         int    `json:"streak"`
	Season         int    `json:"season"`
	Emperor        bool   `json:"emperor"`
	RankText       string `json:"rank_text"`  // "Kỵ Sĩ II · 2 sao" / "Hoàng Đế · 27 sao"
	ShortText      string `json:"short_text"` // "Kỵ Sĩ II" / "Hoàng Đế"
	PeakText       string `json:"peak_text"`  // season peak, e.g. "Bá Tước II"
	PrevSeason     int    `json:"prev_season"`
	PrevSeasonText string `json:"prev_season_text"` // last season's final rank, e.g. "Hầu Tước I"
}

// rankViewFromState renders one raw ladder position (no history).
func rankViewFromState(rs RankState, emperor bool) RankView {
	v := RankView{
		Tier: rs.Tier, Stars: rs.Stars, StarCap: RankStarCap(rs.Tier),
		Streak: rs.Streak, Season: rs.Season, Emperor: emperor,
	}
	if emperor {
		v.Tier = TierHoangDe
	}
	v.TierSlug = RankTierSlugs[v.Tier]
	v.TierName = RankTierNames[v.Tier]
	if rs.Tier >= TierCongTuoc {
		v.Division = -1
	} else {
		v.Division = rs.Division
		if rs.Division >= 0 && rs.Division < len(RankDivisionNames) {
			v.DivisionName = RankDivisionNames[rs.Division]
		}
	}
	if emperor {
		v.ShortText = RankTierNames[TierHoangDe]
		v.RankText = fmt.Sprintf("%s · %d sao", v.ShortText, rs.Stars)
	} else {
		v.ShortText = rs.ShortText()
		v.RankText = rs.Text()
	}
	peak := RankState{Tier: rs.PeakTier, Division: rs.PeakDivision}
	v.PeakText = peak.ShortText()
	return v
}

// rankViewOf renders an account's full ladder view, including the
// previous season's final rank when one is archived.
func rankViewOf(a *Account, emperor bool) RankView {
	v := rankViewFromState(a.Rank, emperor)
	if n := len(a.History); n > 0 {
		last := a.History[n-1]
		v.PrevSeason = last.Season
		final := RankState{Tier: last.FinalTier, Division: last.FinalDivision}
		v.PrevSeasonText = final.ShortText()
	}
	return v
}
