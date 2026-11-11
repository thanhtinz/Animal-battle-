class_name TeamColors
extends RefCounted
## Canonical per-SLOT team-colour table (Tín's rule, 2026-11-09:
## "Trận 4 đội thì phải 4 màu nha nhân vật giống nhau hết nhưng phải
## chia màu" — every faction renders from the SAME base sprites;
## identity is the slot colour dyed onto the faction-bearing parts
## only: cloth/tunic, shield faces, capes, plumes, building flags /
## banners / red roofs).
##
## Colour is keyed by PLAYER SLOT, never by faction team: a 4-player
## match shows 4 colours even in 2v2 (slots 0+1 share a team but not
## a colour). In SP the player is slot 0 (red) and the AI slot 1
## (blue), exactly as before this pass.
##
##   slot 0  ĐỎ          canonical art (assets/)
##   slot 1  XANH DƯƠNG  assets/enemy/      (the P3 recolor set)
##   slot 2  XANH LÁ     assets/team2/
##   slot 3  VÀNG        assets/team3/
##   slot 4  TÍM         assets/team4/      (13z, Tín approved)
##   slot 5  CAM         assets/team5/
##   slot 6  XANH NGỌC   assets/team6/
##   slot 7  HỒNG        assets/team7/
##
## All coloured sets are generated from the slot-0 art by
## tools/recolor_teams.py: only the red hue band rotates — skin,
## hair, armour metal, weapons and wood/stone stay pixel-identical
## across colours.
##
## PRESENTATION ONLY: nothing in this file feeds the sim, the
## lockstep checksum (net_id/position/HP/wallets/ages only) or
## snapshots, so every client can render independently.

const SLOT_COUNT := 8
const NAMES: Array[String] = ["Đỏ", "Xanh dương", "Xanh lá", "Vàng",
		"Tím", "Cam", "Xanh ngọc", "Hồng"]

## Bright identity colours: HP-bar fills, selection rings, name
## labels, lobby name tags.
const UI_COLORS: Array[Color] = [
	Color(0.90, 0.26, 0.20), # slot 0 — Roman red
	Color(0.35, 0.58, 1.00), # slot 1 — deep blue
	Color(0.32, 0.82, 0.36), # slot 2 — forest green
	Color(1.00, 0.76, 0.20), # slot 3 — amber yellow
	Color(0.66, 0.40, 0.95), # slot 4 — purple
	Color(1.00, 0.55, 0.15), # slot 5 — orange
	Color(0.15, 0.85, 0.75), # slot 6 — teal
	Color(1.00, 0.45, 0.75), # slot 7 — pink
]

const _ROOTS: Array[String] = [
	"res://assets/",
	"res://assets/enemy/",
	"res://assets/team2/",
	"res://assets/team3/",
	"res://assets/team4/",
	"res://assets/team5/",
	"res://assets/team6/",
	"res://assets/team7/",
]


static func slot_of(owner: int) -> int:
	return clampi(owner, 0, SLOT_COUNT - 1)


static func color_name(owner: int) -> String:
	return NAMES[slot_of(owner)]


static func ui_color(owner: int) -> Color:
	return UI_COLORS[slot_of(owner)]


## Minimap entity colours per slot: buildings a shade deeper than
## the identity colour, units at identity, ships a shade lighter.
## (Minimap privacy law is unchanged — other teams are never drawn;
## this only picks WHICH colour own-team entities get.)
static func minimap_color(owner: int, kind: String) -> Color:
	var c := ui_color(owner)
	match kind:
		"building":
			return c.darkened(0.18)
		"ship":
			return c.lightened(0.22)
		_:
			return c


## VFX palette key for a slot (see vfx.gd PALETTE_SPARK/SMOKE).
static func vfx_palette(owner: int) -> String:
	return "slot" + str(slot_of(owner))


## Asset directory holding this slot's coloured set.
static func set_root(owner: int) -> String:
	return _ROOTS[slot_of(owner)]


## [sheet png, frames json] for a unit type in this slot's colours.
static func unit_sheet(owner: int, unit_type: String) -> Array:
	var root := set_root(owner)
	return [root + unit_type + ".png", root + unit_type + "_frames.json"]


## Full path of a tiered building texture ("<stem>_tN") in this
## slot's set — meaningful only for the faction-coloured stems
## (Building.COLORED_STEMS); other buildings share one art.
static func building_path(owner: int, key: String) -> String:
	return set_root(owner) + "buildings/" + key + ".png"


## Directory holding this slot's ship hulls.
static func ship_dir(owner: int) -> String:
	return set_root(owner) + "ships/"


## The King portrait/sprite in this slot's colours (cape + shield).
## Asset only — the King is not integrated into gameplay yet.
static func king_path(owner: int) -> String:
	return set_root(owner) + "king.png"
