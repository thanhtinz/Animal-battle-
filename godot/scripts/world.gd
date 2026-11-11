class_name World
extends Node2D
## Map generation, shared obstacle grid and AStarGrid2D pathfinding.
## One source of truth for "which tile is blocked": `solid`.

const MAP_W := 64
const MAP_H := 64
const TILE := 32

var astar: AStarGrid2D
var solid: Dictionary = {} # Vector2i -> bool
var water: Dictionary = {} # Vector2i -> bool
var nodes: Array = [] # ResourceNode
var fish_spots: Array = [] # FishSpot (on water cells)
var beasts: Array = [] # Beast (team-neutral hostiles)
var astar_water: AStarGrid2D = null # ships' grid: inverse of the land grid
var decors: Array = [] # Decor (ruins / flat rocks, blocking decoration)
var animals: Array = [] # Animal (wandering decoration)
var clouds: Array = [] # sky pairs {cloud, shadow} drifting over the map
var sky_layer: Node2D = null # world-view-only layer holding the clouds
var sky_active: bool = true # hidden while a full-screen modal is open

## Visible clouds (Tín's CraftPix cloud pack): counts per biome —
## desert skies are sparser/smaller, snow skies greyer and denser.
const CLOUD_COUNT := {"grassland": 8, "desert": 4, "snow": 10}
const CLOUD_SCALE := {"grassland": 1.0, "desert": 0.75, "snow": 1.05}
const CLOUD_DRIFT: float = 9.0 # px/s, one shared wind direction (+x)
const CLOUD_SHADOW_OFFSET := Vector2(120, 150) # sun from upper-left
const SKY_FADE := 0.9 # sky-layer alpha factor: pretty, never dominant
const CLOUD_MAX_W := 320.0 # hard cap on a cloud's display width (world px)
var tile_shade: Array = [] # float per tile, grass variation

var player_base := Vector2i(7, 55) # centre cell of player start
var enemy_base := Vector2i(56, 8) # centre cell of enemy start
## P4 MP: how many player bases generate() must support (2 = the
## classic SP pair; 3–4 add X-mirrored corner bases for slots 2/3).
var base_count: int = 2
## Every base centre on this map, in slot order (slot 0 = player_base,
## slot 1 = enemy_base; slots 2/3 are the mirrored corners). Filled by
## generate(); scatter guards measure distance to ALL of them, so with
## base_count == 2 every guard behaves exactly as before.
var base_centres: Array = []

# Terrain tileset (tools/extract_tiles.py -> assets/tiles/, then
# tools/make_seamless_tiles.py -> assets/tiles_seamless/). The raw sheet
# tiles are rounded "cushions" with a bevelled rim (bright top/left,
# dark bottom ~12%); placed raw they read as a quilted grid. The
# seamless set crops that rim off every tile (uniform 12% per side, so
# shore boundaries keep their relative position) and full tiles are
# drawn with checkerboard mirror flipping, so neighbours share edge
# columns and the ground reads as one continuous surface.
# The shore set in use is SAND: a bright beach rim reads clearly at
# 32 px and separates the lake from the grassland.
const SHORE_SET := "sand"
const GROUND_DIR := "res://assets/tiles_seamless/"

## Active biome (Biomes.DATA key). Main sets this from its match
## setting BEFORE generate(); the tile set, node/decor skins and
## oasis dressing all follow it. Tile FILENAMES are identical in
## every biome dir (the desert/snow sets are colour grades of the
## seamless grassland set — tools/make_biome_tiles.py), so the
## tile-key logic below never branches on biome.
var biome_id := "grassland"


func biome() -> Dictionary:
	return Biomes.data(biome_id)

## Map LAYOUTS — the second map choice, combining with any biome.
## "plains" is the original layout; "random" is resolved per match
## inside generate() (seeded, so a seed still fully decides a map).
const LAYOUTS: Array = ["plains", "river", "islands", "valley", "arena", "coast"]
const LAYOUT_NAMES := {
	"plains": "Đồng bằng", "river": "Sông đôi", "islands": "Quần đảo",
	"valley": "Thung lũng", "arena": "Đấu trường", "coast": "Bờ biển",
	"random": "Ngẫu nhiên",
}
var layout_id := "plains"
var resolved_layout := "plains"
## Water-feature registry filled by generate() (tests + VFX read it):
## ponds = Array of cell-Arrays; lake/river/sea = flat cell Arrays;
## waterfalls = Array of {cells: Array, foam: Vector2 (world pos)}.
var features: Dictionary = {"ponds": [], "lake": [], "river": [], "sea": [], "waterfalls": []}
var cliff_cells: Array = [] # Vector2i — drawn with the biome cliff tiles, blocking
var falls_cells: Array = [] # Vector2i — animated by FallsLayer, blocking
var cliff_tex: Array = [] # 3 cliff variants of the active biome


static func is_valid_layout(id: String) -> bool:
	return LAYOUTS.has(id) or id == "random"
# Full-surface tiles get mirror variants; shore tiles keep orientation.
const GROUND_FULL_TILES: Array = [
	"grass_0", "grass_1", "grass_2", "dirt",
	"water_0", "water_1", "water_2",
]
const GROUND_TILE_NAMES: Array = [
	"grass_0", "grass_1", "grass_2", "dirt",
	"water_0", "water_1", "water_2",
	"shore_sand_n", "shore_sand_e", "shore_sand_s", "shore_sand_w",
	"shore_sand_ne", "shore_sand_nw", "shore_sand_se", "shore_sand_sw",
]
var ground_tex: Dictionary = {} # tile name (+"#x"/"#y"/"#xy" mirrors) -> Texture2D

## Baked ground (rendering fix): the whole 64×64 ground is composed
## ONCE at generate() into a single texture — land from ALL native
## variants, tone-matched to one mean and randomly flipped per tile
## (uniform macro tone, native-crisp detail, no blur pass); water
## as ONE flat tone with large soft blotches; shore rim + foam
## derived from the SAME distance-field water mask as water itself,
## so bank and water can never drift apart. Accents (flower clumps
## / tufts / dirt blobs) live on top as soft-alpha decals.
var baked_ground: Texture2D = null
var baked_image: Image = null # kept so the minimap can sample it
## Water body tones per biome (bake only — Tín: "nước nó phải nổi
## bật hơn đất"): deep + saturated so water always stands out from
## land at a glance. Grassland/desert = rich mid-deep blue; snow =
## GLACIER blue, unmistakably blue against white snow (the old
## tile-average tones were washed out — snow ice vs snow land was
## nearly the same colour).
const WATER_TONES := {
	"grassland": Color(0.07, 0.32, 0.66),
	"desert": Color(0.06, 0.30, 0.64),
	"snow": Color(0.16, 0.47, 0.78),
}
var ground_decals: Array = [] # Sprite2D decals scattered on the base
const BAKE_PX := 3072 # bake resolution: 48 px per cell (1.5x TILE)
const BAKE_CELL := BAKE_PX / MAP_W # bake pixels per map cell (48)


func _ready() -> void:
	z_index = -100
	# The baked ground (3072px over 2048 world px) is minified at
	# every gameplay zoom: sample it through its mipmaps (13e).
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	load_ground_tiles()
	load_cliff_tiles()
	var falls := FallsLayer.new()
	falls.world = self
	add_child(falls)


## Cliff variants for the active biome (assets/tiles/cliff_* — the
## original tileset's cliff band, used by waterfalls).
func load_cliff_tiles() -> void:
	cliff_tex.clear()
	var base := String(biome()["cliff"])
	for i in range(3):
		var t: Texture2D = load("res://assets/tiles/%s_%d.png" % [base, i])
		if t != null:
			cliff_tex.append(t)


## (Re)load the ground textures from the active biome's tile dir.
## They are the BAKE sources now (single base variant per surface +
## accent tiles for decals + the shore tile for the rim colour).
## Called from _ready (default biome) and again from generate()
## once Main has picked the match biome.
func load_ground_tiles() -> void:
	ground_tex.clear()
	var dir := String(biome()["tiles_dir"])
	for tname in GROUND_TILE_NAMES:
		var tex: Texture2D = load(dir + tname + ".png")
		if tex != null:
			ground_tex[tname] = tex


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < MAP_W and c.y < MAP_H


func world_to_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	c.x = clampi(c.x, 0, MAP_W - 1)
	c.y = clampi(c.y, 0, MAP_H - 1)
	return c


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE * 0.5, TILE * 0.5)


func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	return solid.has(c)


func set_solid(c: Vector2i, v: bool) -> void:
	if v:
		solid[c] = true
	else:
		solid.erase(c)
	astar.set_point_solid(c, v)
	for t in astar_team:
		astar_team[t].set_point_solid(c, v and int(gate_team.get(c, -1)) != int(t))


## Gate cells (self-drawn pass): solid for everyone EXCEPT the owning
## team, whose units path through. Two extra A* grids mirror `solid`
## with the owner's gates opened; they are built lazily and kept in
## sync by set_solid / set_gate / clear_gate.
var gate_team: Dictionary = {} # Vector2i -> team int
var astar_team: Dictionary = {} # team int -> AStarGrid2D


func _team_grid(team: int) -> AStarGrid2D:
	if astar_team.has(team):
		return astar_team[team]
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, MAP_W, MAP_H)
	g.cell_size = Vector2(TILE, TILE)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	for c in solid:
		if int(gate_team.get(c, -1)) != team:
			g.set_point_solid(c, true)
	astar_team[team] = g
	return g


func set_gate(c: Vector2i, team: int) -> void:
	gate_team[c] = team
	for t in astar_team:
		astar_team[t].set_point_solid(c, solid.has(c) and int(gate_team.get(c, -1)) != int(t))


func clear_gate(c: Vector2i) -> void:
	gate_team.erase(c)
	for t in astar_team:
		astar_team[t].set_point_solid(c, solid.has(c))


func _nearest_walkable_grid(g: AStarGrid2D, c: Vector2i, max_r: int = 8) -> Vector2i:
	if in_bounds(c) and not g.is_point_solid(c):
		return c
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and not g.is_point_solid(n):
					return n
	return Vector2i(-1, -1)


func footprint_cells(origin: Vector2i, size: Vector2i) -> Array:
	var out: Array = []
	for y in range(size.y):
		for x in range(size.x):
			out.append(origin + Vector2i(x, y))
	return out


func can_place(origin: Vector2i, size: Vector2i) -> bool:
	for c in footprint_cells(origin, size):
		if not in_bounds(c) or is_solid(c):
			return false
	return true


## Walkable cells orthogonally/diagonally adjacent to any of `cells`, excluding the cells themselves.
func adjacent_walkable(cells: Array) -> Array:
	var inset: Dictionary = {}
	for c in cells:
		inset[c] = true
	var out: Array = []
	var seen: Dictionary = {}
	for c in cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if inset.has(n) or seen.has(n):
				continue
			if in_bounds(n) and not is_solid(n):
				seen[n] = true
				out.append(n)
	return out


func nearest_walkable(c: Vector2i, max_r: int = 8) -> Vector2i:
	if in_bounds(c) and not is_solid(c):
		return c
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and not is_solid(n):
					return n
	return Vector2i(-1, -1)


## A* path as an array of cells (start..goal). Empty if unreachable.
## With team >= 0 the path uses that team's gate-aware grid (own
## gates passable, enemy gates solid).
func get_path_cells(from_c: Vector2i, to_c: Vector2i, team: int = -1) -> Array:
	var grid := astar
	if team >= 0:
		grid = _team_grid(team)
		if grid.is_point_solid(from_c):
			from_c = _nearest_walkable_grid(grid, from_c)
		if grid.is_point_solid(to_c):
			to_c = _nearest_walkable_grid(grid, to_c)
	else:
		if is_solid(from_c):
			from_c = nearest_walkable(from_c)
		if is_solid(to_c):
			to_c = nearest_walkable(to_c)
	if from_c.x < 0 or to_c.x < 0:
		return []
	var packed := grid.get_id_path(from_c, to_c)
	var out: Array = []
	for c in packed:
		out.append(c)
	return out


func cells_to_points(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(cell_center(c))
	return out


# ---------------------------------------------------------------- water grid (ships)

## Frozen water (Snow biome) is NOT navigable: ships can be built at
## a Dock but cannot launch onto ice — the water grid treats every
## snow water cell as blocked.
func is_frozen_water(c: Vector2i) -> bool:
	return biome_id == "snow" and water.has(c)


func navigable(c: Vector2i) -> bool:
	return in_bounds(c) and water.has(c) and not is_frozen_water(c)


func build_water_grid() -> void:
	astar_water = AStarGrid2D.new()
	astar_water.region = Rect2i(0, 0, MAP_W, MAP_H)
	astar_water.cell_size = Vector2(TILE, TILE)
	astar_water.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_water.update()
	for y in range(MAP_H):
		for x in range(MAP_W):
			var c := Vector2i(x, y)
			astar_water.set_point_solid(c, not navigable(c))


func _nearest_navigable_grid(c: Vector2i, max_r: int = 12) -> Vector2i:
	if astar_water == null:
		return Vector2i(-1, -1)
	if in_bounds(c) and not astar_water.is_point_solid(c):
		return c
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n: Vector2i = c + Vector2i(dx, dy)
				if in_bounds(n) and not astar_water.is_point_solid(n):
					return n
	return Vector2i(-1, -1)


func nearest_navigable(c: Vector2i, max_r: int = 12) -> Vector2i:
	return _nearest_navigable_grid(c, max_r)


## A* over water cells only; endpoints snap to the nearest navigable
## cell, exactly like get_path_cells snaps on land. Empty = no route.
func get_water_path_cells(from_c: Vector2i, to_c: Vector2i) -> Array:
	if astar_water == null:
		return []
	if astar_water.is_point_solid(from_c):
		from_c = _nearest_navigable_grid(from_c)
	if astar_water.is_point_solid(to_c):
		to_c = _nearest_navigable_grid(to_c)
	if from_c.x < 0 or to_c.x < 0:
		return []
	var packed := astar_water.get_id_path(from_c, to_c)
	var out: Array = []
	for c in packed:
		out.append(c)
	return out


## Navigable water cells adjacent to a footprint (a Dock's sailing
## door): where ships spawn and where fishing boats dock.
func water_adjacent_to(cells: Array) -> Array:
	var out: Array = []
	for fc in cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = fc + d
			if navigable(n) and not out.has(n):
				out.append(n)
	return out


func fish_spot_at_cell(c: Vector2i) -> FishSpot:
	for s in fish_spots:
		if s.cell == c:
			return s
	return null


func nearest_fish_spot(pos: Vector2) -> FishSpot:
	var best: FishSpot = null
	var best_d := INF
	for s in fish_spots:
		if s.amount <= 0:
			continue
		var d := pos.distance_squared_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


## Fish spots: 2-4 per sizable water body (1 for a small pond),
## placed on deep cells (water on all four sides) when possible and
## kept apart, so a Fishing Boat always has open water to work.
func _spawn_fish_spots() -> void:
	var seen: Dictionary = {}
	for start in water.keys():
		if seen.has(start):
			continue
		var comp: Array = []
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if water.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		if comp.size() < 8:
			continue
		var n_spots := 1
		if comp.size() >= 20:
			n_spots = clampi(2 + comp.size() / 60, 2, 4)
		var deep: Array = []
		for c in comp:
			var ok := true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not water.has(c + d):
					ok = false
					break
			if ok:
				deep.append(c)
		var pool: Array = deep if not deep.is_empty() else comp
		# Greedy farthest-point spread: deterministic, and it still
		# finds the full count inside a small pond where a fixed
		# minimum separation would reject every second pick.
		var picked: Array = [pool[pool.size() / 2]]
		while picked.size() < n_spots:
			var best_c: Vector2i = Vector2i(-1, -1)
			var best_d := -1.0
			for cand in pool:
				if picked.has(cand):
					continue
				var md := INF
				for p in picked:
					md = minf(md, Vector2(cand - p).length())
				if md > best_d:
					best_d = md
					best_c = cand
			if best_c.x < 0:
				break
			picked.append(best_c)
		for c in picked:
			var s := FishSpot.new()
			s.cell = c
			s.position = cell_center(c)
			add_child(s)
			fish_spots.append(s)


## Path from `from_c` to the closest walkable tile adjacent to footprint `cells`.
func path_to_footprint(from_c: Vector2i, cells: Array, team: int = -1) -> Array:
	var adj := adjacent_walkable(cells)
	if adj.is_empty():
		return []
	if adj.has(from_c):
		return [from_c]
	var best: Array = []
	var best_len := 1 << 30
	for a in adj:
		var p := get_path_cells(from_c, a, team)
		if not p.is_empty() and p.size() < best_len:
			best_len = p.size()
			best = p
	return best


func nearest_node_of_type(pos: Vector2, rtype: String, exclude: ResourceNode = null) -> ResourceNode:
	var best: ResourceNode = null
	var best_d := INF
	for n in nodes:
		if n == exclude or n.rtype != rtype or n.amount <= 0:
			continue
		var d := pos.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## --- Water-feature primitives (shared by all layouts) ---

## Irregular ellipse of water; returns its cells.
func _carve_blob(centre: Vector2i, rx: float, ry: float, rng: RandomNumberGenerator) -> Array:
	var cells: Array = []
	for y in range(maxi(0, centre.y - int(ry) - 2), mini(MAP_H, centre.y + int(ry) + 3)):
		for x in range(maxi(0, centre.x - int(rx) - 2), mini(MAP_W, centre.x + int(rx) + 3)):
			var c := Vector2i(x, y)
			var e := Vector2(float(x - centre.x) / rx, float(y - centre.y) / ry)
			if e.length() < 1.0 and rng.randf() > 0.12:
				water[c] = true
				set_solid(c, true)
				cells.append(c)
	return cells


## Organic pond/lake shape: a union of 2–4 overlapping jittered
## ellipses (float centres, per-axis jittered radii), so the data
## outline itself has no straight runs and no right angles. Cells in
## the outer band of the union may be nibbled away for a ragged,
## natural shoreline; the interior is always solid water. Returns
## the newly carved water cells (registry stays truthful).
func _carve_organic(centre: Vector2i, rx: float, ry: float, rng: RandomNumberGenerator) -> Array:
	var lobes: Array = [[Vector2(centre), rx, ry]]
	var n := 3 if rx + ry >= 6.0 else 2
	if rng.randf() < 0.5:
		n += 1
	for i in range(n - 1):
		var lc := Vector2(centre) + Vector2(
				rng.randf_range(-0.5, 0.5) * rx,
				rng.randf_range(-0.5, 0.5) * ry)
		lobes.append([lc, rx * rng.randf_range(0.55, 0.9),
				ry * rng.randf_range(0.55, 0.9)])
	var cells: Array = []
	var reach := int(maxf(rx, ry) * 1.6) + 2
	for y in range(maxi(0, centre.y - reach), mini(MAP_H, centre.y + reach + 1)):
		for x in range(maxi(0, centre.x - reach), mini(MAP_W, centre.x + reach + 1)):
			var p := Vector2(x, y)
			var best := INF # smallest normalised ellipse distance
			for lobe in lobes:
				var lc: Vector2 = lobe[0]
				var d := Vector2((p.x - lc.x) / float(lobe[1]),
						(p.y - lc.y) / float(lobe[2]))
				best = minf(best, d.length())
			if best >= 1.0:
				continue
			# Ragged edge: only the outer band may lose cells.
			if best > 0.8 and rng.randf() < 0.4:
				continue
			var c := Vector2i(x, y)
			if not water.has(c):
				water[c] = true
				set_solid(c, true)
				cells.append(c)
	return cells


## Pond centres spread over the map, all far from both bases.
func _pond_picks(rng: RandomNumberGenerator, n: int) -> Array:
	var cands: Array = [Vector2i(20, 14), Vector2i(46, 44), Vector2i(16, 34),
			Vector2i(52, 30), Vector2i(36, 52)]
	var out: Array = []
	for i in range(mini(n, cands.size())):
		var pick := rng.randi_range(0, cands.size() - 1)
		out.append(cands[pick])
		cands.remove_at(pick)
	return out


## Horizontal river band; crossings = inclusive x-spans left as land.
func _carve_river_h(row: int, width: int, x_from: int, crossings: Array, _rng: RandomNumberGenerator) -> void:
	for x in range(x_from, MAP_W):
		var crossed := false
		for span in crossings:
			if x >= int(span[0]) and x <= int(span[1]):
				crossed = true
		if crossed:
			continue
		for dy in range(width):
			var c := Vector2i(x, row + dy)
			water[c] = true
			set_solid(c, true)
			features.river.append(c)


## Vertical river band; crossing_rows = y values left as land bridges.
func _carve_river_v(col: int, width: int, y0: int, y1: int, crossing_rows: Array, _rng: RandomNumberGenerator) -> void:
	for y in range(y0, y1 + 1):
		if crossing_rows.has(y):
			continue
		for dx in range(width):
			var c := Vector2i(col + dx, y)
			water[c] = true
			set_solid(c, true)
			features.river.append(c)


## Waterfall flowing SOUTH: small upper pond, a cliff band, animated
## falls cells, optional lower pond. All blocking.
func _place_waterfall_h(top_centre: Vector2i, falls_offsets: Array, with_lower_pond: bool, rng: RandomNumberGenerator) -> void:
	_carve_blob(top_centre, 2.0, 1.2, rng)
	var band_y := top_centre.y + 2
	var cells: Array = []
	for dx in range(-2, 3):
		var cc := Vector2i(top_centre.x + dx, band_y)
		if falls_offsets.has(dx):
			for f in [cc, cc + Vector2i(0, 1)]:
				falls_cells.append(f)
				cells.append(f)
				set_solid(f, true)
		else:
			# Two-row cliff face so the ledge reads as a real drop.
			for f in [cc, cc + Vector2i(0, 1)]:
				cliff_cells.append(f)
				set_solid(f, true)
	if with_lower_pond:
		_carve_blob(Vector2i(top_centre.x, band_y + 3), 2.0, 1.2, rng)
	var foam_cell := Vector2i(top_centre.x + int(falls_offsets[0]), band_y + 2)
	features.waterfalls.append({"cells": cells,
			"foam": cell_center(foam_cell) + Vector2(0, 6)})


## Waterfall flowing EAST (river source): pond at the west, cliff
## column, falls spilling into the river start.
func _place_waterfall_v(left_centre: Vector2i, rng: RandomNumberGenerator) -> void:
	_carve_blob(left_centre, 1.2, 2.0, rng)
	var band_x := left_centre.x + 2
	var cells: Array = []
	for dy in range(-2, 3):
		var cc := Vector2i(band_x, left_centre.y + dy)
		if dy == 0 or dy == 1:
			for f in [cc, cc + Vector2i(1, 0)]:
				falls_cells.append(f)
				cells.append(f)
				set_solid(f, true)
		else:
			for f in [cc, cc + Vector2i(1, 0)]:
				cliff_cells.append(f)
				set_solid(f, true)
	features.waterfalls.append({"cells": cells,
			"foam": cell_center(Vector2i(band_x + 2, left_centre.y)) + Vector2(6, 0)})


## Archipelago: everything is sea except island blobs (one per base,
## three resource islands); one mid island carries a pond.
func _sculpt_islands(rng: RandomNumberGenerator) -> void:
	var islands: Array = [
		[Vector2i(9, 52), 8.0, 7.0], [Vector2i(54, 11), 8.0, 7.0],
		[Vector2i(32, 20), 4.5, 4.0], [Vector2i(22, 38), 3.5, 3.0],
		[Vector2i(43, 33), 3.5, 3.0]]
	if base_count > 2:
		# MP slots 3/4 get their own islands (X-mirrors of the two
		# base islands), so every base still sits on its own island.
		islands.append([Vector2i(9, 11), 8.0, 7.0])
		islands.append([Vector2i(54, 52), 8.0, 7.0])
	for y in range(MAP_H):
		for x in range(MAP_W):
			var c := Vector2i(x, y)
			var land := false
			for isl in islands:
				var ctr: Vector2i = isl[0]
				var e := Vector2(float(x - ctr.x) / float(isl[1]),
						float(y - ctr.y) / float(isl[2]))
				if e.length() < 0.92 + rng.randf() * 0.12:
					land = true
					break
			if not land:
				water[c] = true
				set_solid(c, true)
				features.sea.append(c)
	features.ponds.append(_carve_organic(Vector2i(31, 19), 1.3, 1.1, rng))


## World positions where waterfall foam/mist should play (VFX hook).
func falls_foam_points() -> Array:
	var out: Array = []
	for wf in features.waterfalls:
		out.append(wf["foam"])
	return out


func generate(seed_value: int = 12345) -> void:
	load_ground_tiles()
	load_cliff_tiles()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, MAP_W, MAP_H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()

	# Grass shade variation.
	tile_shade.clear()
	for i in range(MAP_W * MAP_H):
		tile_shade.append(rng.randf())

	# --- Layout sculpting: water features per layout (river / sea /
	# ponds / lakes / waterfalls), all from shared primitives. Every
	# layout gets several water features; water stays non-walkable.
	features = {"ponds": [], "lake": [], "river": [], "sea": [], "waterfalls": []}
	cliff_cells.clear()
	falls_cells.clear()
	resolved_layout = layout_id
	if layout_id == "random":
		resolved_layout = LAYOUTS[rng.randi_range(0, LAYOUTS.size() - 1)]
	if resolved_layout == "coast":
		player_base = Vector2i(12, 44) # inland, sea along the south edge
		enemy_base = Vector2i(51, 17)
	else:
		player_base = Vector2i(7, 55)
		enemy_base = Vector2i(56, 8)
	# Slot order: 0 = player base, 1 = enemy base, 2/3 (MP only) are
	# the X-mirrored corners of the enemy/player bases.
	base_centres = [player_base, enemy_base]
	if base_count >= 3:
		base_centres.append(Vector2i(MAP_W - 1 - enemy_base.x, enemy_base.y))
	if base_count >= 4:
		base_centres.append(Vector2i(MAP_W - 1 - player_base.x, player_base.y))
	# 13z: queue matches seat EIGHT bases — the four corners plus
	# the four edge midpoints of the plains map (ring spread). The
	# water reclaim pass and the scatter guards below are already
	# generic over base_centres, so the ring centres get the same
	# treatment as slots 2/3. Only plains hosts the ring: the
	# queue map pool already resolves to plains, so queue matches
	# never ask another layout for 8 spawns; other layouts keep
	# the classic 2-4 bases untouched.
	if base_count >= 5 and resolved_layout == "plains":
		base_centres.append(Vector2i(31, 4))   # slot 4: north edge
		base_centres.append(Vector2i(31, 59))  # slot 5: south edge
		base_centres.append(Vector2i(4, 31))   # slot 6: west edge
		base_centres.append(Vector2i(59, 31))  # slot 7: east edge
	match resolved_layout:
		"river":
			_place_waterfall_v(Vector2i(2, 30), rng)
			_carve_river_h(30, 3, 6, [[19, 20], [43, 44]], rng)
			for pc in _pond_picks(rng, 2):
				features.ponds.append(_carve_organic(pc, 2.0, 1.6, rng))
		"islands":
			_sculpt_islands(rng)
		"valley":
			_place_waterfall_h(Vector2i(31, 9), [0, 1], false, rng)
			_carve_river_v(31, 2, 13, 50, [], rng)
			features.ponds.append(_carve_organic(Vector2i(14, 46), 2.0, 1.6, rng))
		"arena":
			features.ponds.append(_carve_organic(Vector2i(20, 20), 2.2, 1.8, rng))
			features.ponds.append(_carve_organic(Vector2i(43, 43), 2.2, 1.8, rng))
			_carve_organic(Vector2i(7, 7), 3.0, 2.6, rng) # corner mini-lakes
			_carve_organic(Vector2i(56, 56), 3.0, 2.6, rng)
		"coast":
			for y in range(54, MAP_H):
				for x in range(MAP_W):
					var sc := Vector2i(x, y)
					water[sc] = true
					set_solid(sc, true)
					features.sea.append(sc)
			features.lake = _carve_organic(Vector2i(30, 24), 5.0, 4.0, rng)
			_carve_river_v(30, 2, 28, 53, [38, 47], rng)
		_: # plains — the original layout: side lake + ponds + waterfall
			features.lake = _carve_organic(Vector2i(33, 30), 4.5, 3.2, rng)
			for pc in _pond_picks(rng, 2):
				features.ponds.append(_carve_organic(pc, 2.0, 1.6, rng))
			_place_waterfall_h(Vector2i(12, 5), [0], true, rng)

	# MP slots 3/4: reclaim a land clearing at the mirrored corner
	# bases — a sculpted feature (arena corner lake, coast sea) may
	# sit on those corners. Cliff/falls cells are left untouched.
	if base_count > 2:
		for bi in range(2, base_centres.size()):
			var bc: Vector2i = base_centres[bi]
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var c := bc + Vector2i(dx, dy)
					if not in_bounds(c) or cliff_cells.has(c) or falls_cells.has(c):
						continue
					if Vector2(dx, dy).length() <= 4.0 and water.has(c):
						water.erase(c)
						set_solid(c, false)

	var clear_of_bases := func(c: Vector2i) -> bool:
		for bc in base_centres:
			if Vector2(c - bc).length() <= 9.0:
				return false
		return true

	# Thung lũng: the single chokepoint corridor (the gap columns
	# through both decor bands + the river banks between them) must
	# stay clear of scattered nodes/decor — a forest cluster landing
	# there would seal the ONLY land route and break the layout's
	# contract. Scatter loops below all honour this guard.
	var corridor_blocked := func(c: Vector2i) -> bool:
		return resolved_layout == "valley" and c.x >= 28 and c.x <= 35 \
				and c.y >= 24 and c.y <= 40

	# Thung lũng: two 3-row decor bands wall off the map completely,
	# leaving ONE central valley (river + banks) as the only land
	# route. Middle row is trees, flanks are blocking decor.
	if resolved_layout == "valley":
		for band_y in [26, 38]:
			for x in range(0, MAP_W):
				if x >= 29 and x <= 34:
					continue
				for bdy in [-1, 0, 1]:
					var bc2 := Vector2i(x, band_y + bdy)
					if is_solid(bc2) or not clear_of_bases.call(bc2):
						continue
					if bdy == 0 and rng.randf() < 0.75:
						_add_node(bc2, "wood", 100)
					else:
						_add_decor(bc2, String(biome()["decor_kinds"][1]), 0)

	# Forest clusters (trees = wood nodes + obstacles). One guaranteed
	# forest near EACH base (mirrored through the map centre) so both
	# sides open with wood in reach, on every biome.
	var forest_centers: Array = [Vector2i(15, 49), Vector2i(48, 14)]
	if resolved_layout == "islands":
		forest_centers = [Vector2i(13, 50), Vector2i(50, 13)]
	for i in range(7):
		forest_centers.append(Vector2i(rng.randi_range(4, MAP_W - 5), rng.randi_range(4, MAP_H - 5)))
	for fc in forest_centers:
		var count := rng.randi_range(10, 18)
		for i in range(count):
			var c: Vector2i = fc + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			if not in_bounds(c) or is_solid(c) or not clear_of_bases.call(c) \
					or corridor_blocked.call(c):
				continue
			_add_node(c, "wood", 100)

	# Gold clusters.
	for i in range(2):
		var gc := Vector2i(rng.randi_range(8, MAP_W - 9), rng.randi_range(8, MAP_H - 9))
		for j in range(5):
			var c: Vector2i = gc + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-1, 1))
			if not in_bounds(c) or is_solid(c) or not clear_of_bases.call(c) \
					or corridor_blocked.call(c):
				continue
			_add_node(c, "gold", 300)

	# Stone clusters.
	for i in range(2):
		var sc := Vector2i(rng.randi_range(8, MAP_W - 9), rng.randi_range(8, MAP_H - 9))
		for j in range(4):
			var c: Vector2i = sc + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-1, 1))
			if not in_bounds(c) or is_solid(c) or not clear_of_bases.call(c) \
					or corridor_blocked.call(c):
				continue
			_add_node(c, "stone", 200)

	# Berry-bush clusters (food — the game's first Food source; before
	# this, Food only ever decreased through training). Guaranteed
	# patch near each base, mirrored like the forests.
	var bush_centers: Array = [Vector2i(19, 44), Vector2i(44, 19)]
	if resolved_layout == "islands":
		bush_centers = [Vector2i(12, 57), Vector2i(51, 6)]
	for i in range(2):
		bush_centers.append(Vector2i(rng.randi_range(6, MAP_W - 7), rng.randi_range(6, MAP_H - 7)))
	for bc in bush_centers:
		var count := rng.randi_range(4, 6)
		for i in range(count):
			var c: Vector2i = bc + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			if not in_bounds(c) or is_solid(c) or not clear_of_bases.call(c) \
					or corridor_blocked.call(c):
				continue
			_add_node(c, "food", 50)

	# Guaranteed gold + stone within reach of EACH base (mid-distance,
	# toward the map centre, mirrored) — biome tests assert both TCs
	# open with all four resources nearby on every map.
	var guar_specs: Array = [["gold", Vector2i(19, 52), 300], ["gold", Vector2i(44, 11), 300],
			["stone", Vector2i(13, 43), 200], ["stone", Vector2i(50, 20), 200]]
	if resolved_layout == "islands":
		guar_specs = [["gold", Vector2i(14, 55), 300], ["gold", Vector2i(49, 8), 300],
				["stone", Vector2i(4, 48), 200], ["stone", Vector2i(59, 15), 200]]
	for spec in guar_specs:
		var ctr: Vector2i = spec[1]
		for j in range(4):
			var c: Vector2i = ctr + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
			if not in_bounds(c) or is_solid(c) or corridor_blocked.call(c):
				continue
			_add_node(c, String(spec[0]), int(spec[2]))

	# MP slots 3/4: the same starting-resource set as the base each
	# one mirrors (slot 2 <- enemy set, slot 3 <- player set), with
	# every centre X-mirrored. Skipped entirely for 2-base maps, so
	# the seeded RNG stream of an SP map never changes.
	if base_count > 2:
		var sets: Array
		if resolved_layout == "islands":
			sets = [[Vector2i(50, 13), Vector2i(51, 6), Vector2i(49, 8), Vector2i(59, 15)],
					[Vector2i(13, 50), Vector2i(12, 57), Vector2i(14, 55), Vector2i(4, 48)]]
		else:
			sets = [[Vector2i(48, 14), Vector2i(44, 19), Vector2i(44, 11), Vector2i(50, 20)],
					[Vector2i(15, 49), Vector2i(19, 44), Vector2i(19, 52), Vector2i(13, 43)]]
		var src_sets: Array = [sets[0]]
		if base_count >= 4:
			src_sets.append(sets[1])
		for s in src_sets:
			_scatter_base_set(
					Vector2i(MAP_W - 1 - s[0].x, s[0].y), Vector2i(MAP_W - 1 - s[1].x, s[1].y),
					Vector2i(MAP_W - 1 - s[2].x, s[2].y), Vector2i(MAP_W - 1 - s[3].x, s[3].y),
					rng, clear_of_bases, corridor_blocked)

	# 13z ring bases (slots 4-7, plains): each edge-midpoint base
	# gets the same four-part starting set as the corner bases —
	# forest / berry bushes / gold / stone — centred ~10 cells from
	# the TC toward the map middle, so every spawn opens with the
	# same economy. Only runs when the ring was actually seated.
	if base_centres.size() >= 5:
		var ring_sets: Array = [
			[Vector2i(25, 13), Vector2i(37, 14), Vector2i(23, 10), Vector2i(39, 11)],  # slot 4 (31,4)
			[Vector2i(25, 50), Vector2i(37, 49), Vector2i(23, 53), Vector2i(39, 52)],  # slot 5 (31,59)
			[Vector2i(12, 25), Vector2i(13, 37), Vector2i(10, 23), Vector2i(11, 39)],  # slot 6 (4,31)
			[Vector2i(51, 25), Vector2i(50, 37), Vector2i(53, 23), Vector2i(52, 39)],  # slot 7 (59,31)
		]
		for s in ring_sets:
			_scatter_base_set(s[0], s[1], s[2], s[3],
					rng, clear_of_bases, corridor_blocked)

	# Đấu trường: a rich gold/stone ring around the open centre.
	if resolved_layout == "arena":
		for i in range(10):
			var ang := TAU * float(i) / 10.0
			var rc := Vector2i(32, 32) + Vector2i(roundi(cos(ang) * 6.0), roundi(sin(ang) * 6.0))
			if in_bounds(rc) and not is_solid(rc):
				_add_node(rc, "gold" if i % 2 == 0 else "stone", 400)

	# Desert dressing: a palm ring around the oasis (wood nodes on
	# the SECOND land ring from the water — the first shore ring
	# sits inside the bake's water feather, so trunks planted there
	# visibly grow out of the lake; Tín caught that in a capture).
	if biome_id == "desert":
		var shore_cells: Array = []
		for c in water:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if in_bounds(n) and not is_solid(n) and clear_of_bases.call(n) \
						and not corridor_blocked.call(n) and not shore_cells.has(n):
					shore_cells.append(n)
		var ring2_cells: Array = []
		for s in shore_cells:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n2: Vector2i = s + d
				if not in_bounds(n2) or is_solid(n2) or water.has(n2) \
						or not clear_of_bases.call(n2) or corridor_blocked.call(n2) \
						or ring2_cells.has(n2):
					continue
				var touches := false
				for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if water.has(n2 + d2):
						touches = true
				if not touches:
					ring2_cells.append(n2)
		if ring2_cells.is_empty():
			ring2_cells = shore_cells # tiny pond: fall back to ring 1
		# Pick with the seeded rng (Array.shuffle uses the global RNG
		# and would break same-seed determinism).
		for i in range(mini(9, ring2_cells.size())):
			var pick := rng.randi_range(0, ring2_cells.size() - 1)
			_add_node(ring2_cells[pick], "wood", 100)
			ring2_cells.remove_at(pick)

	# Decoration that blocks its cell: the biome's decor kinds
	# (grassland ruins + flat rocks; desert ruins + cacti; snow
	# snow-capped ruins + flat rocks).
	var decor_kinds: Array = biome()["decor_kinds"]
	var decor_spots: Array = []
	for i in range(7):
		decor_spots.append(Vector2i(rng.randi_range(4, MAP_W - 5), rng.randi_range(4, MAP_H - 5)))
	for i in range(decor_spots.size()):
		var c: Vector2i = decor_spots[i]
		if not in_bounds(c) or is_solid(c) or not clear_of_bases.call(c) \
				or corridor_blocked.call(c):
			continue
		_add_decor(c, String(decor_kinds[0]) if i < 3 else String(decor_kinds[1]), i % 2)

	# Wandering wild animals (decoration; hunting is P3).
	var animal_defs := [["deer", Vector2i(24, 40)], ["fox", Vector2i(40, 20)],
			["deer", Vector2i(30, 14)], ["fox", Vector2i(48, 44)]]
	for i in range(animal_defs.size()):
		var ac: Vector2i = nearest_walkable(animal_defs[i][1], 6)
		if ac.x >= 0:
			_add_animal(animal_defs[i][0], ac, i)

	# Ships' water grid + fish spots + wild beasts (all derived from
	# the finished water/node layout above).
	build_water_grid()
	_spawn_fish_spots()
	_spawn_beasts(rng)
	# Compose the ground into one baked texture (+ accent decals) now
	# that the water layout is final. Rendering-only; grids untouched.
	bake_ground(rng)
	# Dry-base guard: the bake feathers water ~0.38 tile onto land,
	# so a scatter placement on a shore cell can stand in PAINTED
	# water even though its grid cell is dry land. Validate every
	# node/decor against the baked texture and nudge or drop the
	# offenders (see _enforce_dry_placements).
	_enforce_dry_placements(clear_of_bases, corridor_blocked)

	# Visible clouds (Tín's CraftPix pack) drifting over the world,
	# each paired with its soft shadow offset on the ground. They sit
	# on their own sky layer: topmost world layer (below the HUD),
	# fog-free, and hidden while a full-screen modal menu is open.
	sky_layer = Node2D.new()
	sky_layer.name = "SkyLayer"
	sky_layer.z_index = 90
	add_child(sky_layer)
	var bid: String = biome_id
	var n_clouds: int = int(CLOUD_COUNT.get(bid, 8))
	var cscale: float = float(CLOUD_SCALE.get(bid, 1.0))
	for i in range(n_clouds):
		var shape: int = 1 + (i % 4)
		var grey: bool = bid == "snow"
		var cpath := "res://assets/env/cloud_%s%d.png" % ["g" if grey else "w", shape if not grey or shape <= 3 else 1]
		var ctex: Texture2D = load(cpath)
		var stex: Texture2D = load("res://assets/env/cloud_s%d.png" % shape)
		var pos := Vector2(rng.randf_range(0.0, MAP_W * TILE), rng.randf_range(0.0, MAP_H * TILE))
		# Width-based scale: every shape reads as a drifting cloud of
		# a similar size regardless of its canvas — hard-capped at
		# CLOUD_MAX_W so one formation never spans the screen.
		var target_w: float = minf((275.0 + 40.0 * float(i % 3)) * cscale, CLOUD_MAX_W)
		var sc: float = target_w / maxf(1.0, float(ctex.get_width()))
		var sh := Sprite2D.new()
		sh.texture = stex
		sh.modulate = Color(1, 1, 1, 0.26 * SKY_FADE)
		sh.scale = Vector2.ONE * sc
		sh.position = pos + CLOUD_SHADOW_OFFSET
		sh.z_index = -20 # shadow rides under the cloud inside the layer
		sky_layer.add_child(sh)
		var cs := Sprite2D.new()
		cs.texture = ctex
		cs.modulate = Color(1, 1, 1, (0.78 if not grey else 0.68) * SKY_FADE)
		cs.scale = Vector2.ONE * sc
		cs.position = pos
		sky_layer.add_child(cs)
		clouds.append({"cloud": cs, "shadow": sh})

	queue_redraw()


## Clouds belong to the world view only: Main calls this when a
## full-screen modal (the boot map-choice panel) opens or closes.
func set_sky_active(active: bool) -> void:
	sky_active = active
	if sky_layer != null:
		sky_layer.visible = active


func _process(delta: float) -> void:
	for pair in clouds:
		var cs: Sprite2D = pair["cloud"]
		cs.position.x += CLOUD_DRIFT * delta
		if cs.position.x > MAP_W * TILE + 420.0:
			cs.position.x = -420.0
		pair["shadow"].position = cs.position + CLOUD_SHADOW_OFFSET


## One base's starting-resource set (forest cluster, berry patch,
## guaranteed gold + stone) with the same counts/amounts as the
## canonical two-base scatter — used for MP slots 3/4 with mirrored
## centres (P4). Guards mirror the canonical loops.
func _scatter_base_set(forest_c: Vector2i, bush_c: Vector2i, gold_c: Vector2i,
		stone_c: Vector2i, rng: RandomNumberGenerator,
		clear_of_bases: Callable, corridor_blocked: Callable) -> void:
	var count := rng.randi_range(10, 18)
	for i in range(count):
		var c: Vector2i = forest_c + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
		if not in_bounds(c) or is_solid(c) or not clear_of_bases.call(c) \
				or corridor_blocked.call(c):
			continue
		_add_node(c, "wood", 100)
	var bn := rng.randi_range(4, 6)
	for i in range(bn):
		var c2: Vector2i = bush_c + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
		if not in_bounds(c2) or is_solid(c2) or not clear_of_bases.call(c2) \
				or corridor_blocked.call(c2):
			continue
		_add_node(c2, "food", 50)
	for spec in [[gold_c, "gold", 300], [stone_c, "stone", 200]]:
		var ctr: Vector2i = spec[0]
		for j in range(4):
			var c3: Vector2i = ctr + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
			if not in_bounds(c3) or is_solid(c3) or corridor_blocked.call(c3):
				continue
			_add_node(c3, String(spec[1]), int(spec[2]))


func _add_node(c: Vector2i, rtype: String, amount: int) -> void:
	var n := ResourceNode.new()
	n.cell = c
	n.rtype = rtype
	n.skin = String(biome()["node_skin"])
	n.amount = amount
	n.max_amount = amount
	# Deterministic artwork variant per cell (CraftPix variants).
	n.variant = absi(c.x * 31 + c.y * 17) % 5 if rtype == "wood" else absi(c.x * 31 + c.y * 17) % 3
	n.position = cell_center(c)
	add_child(n)
	nodes.append(n)
	set_solid(c, true)


func _add_decor(c: Vector2i, kind: String, variant: int) -> void:
	var d := Decor.new()
	d.kind = kind
	d.cell = c
	d.variant = variant
	d.position = cell_center(c)
	d.z_index = 5
	add_child(d)
	decors.append(d)
	set_solid(c, true)


func _add_animal(species: String, c: Vector2i, seed_idx: int) -> void:
	var a := Animal.new()
	a.species = species
	a.world = self
	a._seed = seed_idx * 17 + 3
	a.position = cell_center(c)
	add_child(a)
	animals.append(a)


func _add_beast(species: String, skin: String, c: Vector2i) -> Beast:
	var b := Beast.new()
	b.species = species
	b.skin = skin
	b.world = self
	b.anchor = cell_center(c)
	b.position = cell_center(c)
	add_child(b)
	beasts.append(b)
	return b


## Wild-beast distribution per biome (Master: beasts are neutral
## hostiles for BOTH teams, leashed to a territory away from the
## base clearings):
##   Grassland: wolf packs + bears + boars
##   Snow:      white wolves + bears
##   Desert:    sand wolves + boars
func _spawn_beasts(rng: RandomNumberGenerator) -> void:
	var wolf_skin := "wolf"
	if biome_id == "snow":
		wolf_skin = "wolf_snow"
	elif biome_id == "desert":
		wolf_skin = "wolf_desert"
	var clear := func(c: Vector2i) -> bool:
		if not in_bounds(c) or is_solid(c):
			return false
		for bc in base_centres:
			if Vector2(c - bc).length() <= 10.0:
				return false
		return true
	var taken: Array = []
	var find_spot := func(min_gap: float) -> Vector2i:
		for tries in range(60):
			var c := Vector2i(rng.randi_range(4, MAP_W - 5), rng.randi_range(4, MAP_H - 5))
			if not clear.call(c):
				continue
			var ok := true
			for t in taken:
				if Vector2(c - t).length() < min_gap:
					ok = false
					break
			if ok:
				return c
		return Vector2i(-1, -1)
	# Wolf dens: packs of 3-4 sharing one territory anchor.
	for d in range(2):
		var den: Vector2i = find_spot.call(8.0)
		if den.x < 0:
			continue
		taken.append(den)
		for i in range(rng.randi_range(3, 4)):
			var c: Vector2i = nearest_walkable(den + Vector2i(
					rng.randi_range(-1, 1), rng.randi_range(-1, 1)), 3)
			if c.x >= 0:
				var b := _add_beast("wolf", wolf_skin, c)
				b.anchor = cell_center(den)
	# Bears: solitary, near forests (anchor by a wood node when found).
	if biome_id != "desert":
		for i in range(2):
			var spot := Vector2i(-1, -1)
			var woods: Array = []
			for n in nodes:
				if n.rtype == "wood":
					woods.append(n.cell)
			if not woods.is_empty():
				for tries in range(40):
					var wc: Vector2i = woods[rng.randi_range(0, woods.size() - 1)]
					var c: Vector2i = wc + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
					var nc: Vector2i = nearest_walkable(c, 3)
					if nc.x >= 0 and clear.call(nc):
						spot = nc
						break
			if spot.x < 0:
				spot = find_spot.call(8.0)
			if spot.x >= 0:
				taken.append(spot)
				_add_beast("bear", "bear", spot)
	# Boars: neutral grazers scattered on their own.
	if biome_id != "snow":
		for i in range(3):
			var spot: Vector2i = find_spot.call(6.0)
			if spot.x >= 0:
				taken.append(spot)
				_add_beast("boar", "boar", spot)


## A dead beast leaves a meat node on its cell: the existing
## node/deposit loop, carrying Food (Unit maps "meat" -> "food").
func add_carcass(c: Vector2i, amount: int) -> void:
	if not in_bounds(c):
		return
	for n in nodes:
		if n.cell == c:
			return # cell already hosts a node; skip rather than stack
	_add_node(c, "meat", amount)


func remove_node(n: ResourceNode) -> void:
	nodes.erase(n)
	set_solid(n.cell, false)
	n.queue_free()


## Deterministic per-cell hash (stable for a given cell, independent of
## RNG call order) used to pick ground tile variants.
func _cell_hash(c: Vector2i) -> int:
	var h: int = c.x * 374761393 + c.y * 668265263
	h = (h ^ (h >> 13)) * 1103515245
	return absi(h ^ (h >> 16))


func _is_land(c: Vector2i) -> bool:
	return in_bounds(c) and not water.has(c)


## Which terrain tile a cell renders as. Water cells touching land use a
## shore tile on the water cell (land side toward the land neighbour);
## open water and grass pick variants by cell hash.
func ground_tile_key(c: Vector2i) -> String:
	if water.has(c):
		var dirs: Array = []
		if _is_land(c + Vector2i(0, -1)):
			dirs.append("n")
		if _is_land(c + Vector2i(1, 0)):
			dirs.append("e")
		if _is_land(c + Vector2i(0, 1)):
			dirs.append("s")
		if _is_land(c + Vector2i(-1, 0)):
			dirs.append("w")
		if dirs.size() == 1:
			return "shore_" + SHORE_SET + "_" + dirs[0]
		if dirs.size() == 2:
			# Corner names are compass-style: vertical letter first.
			if dirs.has("n") and dirs.has("e"):
				return "shore_" + SHORE_SET + "_ne"
			if dirs.has("s") and dirs.has("e"):
				return "shore_" + SHORE_SET + "_se"
			if dirs.has("s") and dirs.has("w"):
				return "shore_" + SHORE_SET + "_sw"
			if dirs.has("n") and dirs.has("w"):
				return "shore_" + SHORE_SET + "_nw"
			return "shore_" + SHORE_SET + "_" + dirs[0] # opposite sides: straight
		if dirs.size() > 2:
			return "shore_" + SHORE_SET + "_" + dirs[0]
		return "water_" + str(_cell_hash(c) % 3)
	var h := _cell_hash(c) % 100
	if h < 78:
		return "grass_0"
	if h < 92:
		return "grass_2"
	if h < 98:
		return "grass_1"
	# Rare dirt accents only on open ground (not hugging the bases).
	if Vector2(c - player_base).length() > 7.0 and Vector2(c - enemy_base).length() > 7.0:
		return "dirt"
	return "grass_0"


func ground_textures_loaded() -> bool:
	return ground_tex.has("grass_0") and ground_tex.has("water_0") \
		and ground_tex.has("shore_" + SHORE_SET + "_n") and ground_tex.size() >= 15


## ---- Baked ground ------------------------------------------------

## One tile source as a BAKE_CELL×BAKE_CELL RGBA image (the bake's
## cell size — 48px, so the ~115px source art is squeezed ~2.4x
## instead of ~3.6x and its motifs stay readable; see KE-HOACH 13e).
func _tile_image_bake(tname: String) -> Image:
	var tex: Texture2D = ground_tex.get(tname, null)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	img.resize(BAKE_CELL, BAKE_CELL, Image.INTERPOLATE_BILINEAR)
	return img


## Average colour of an image's opaque pixels.
func _avg_opaque(img: Image) -> Color:
	var acc := Color(0, 0, 0)
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p := img.get_pixel(x, y)
			if p.a > 0.8:
				acc += p
				n += 1
	return acc / float(maxi(1, n))


## The bright "sand" tone of the shore tile: average of its warmest
## opaque pixels (per biome this yields sand / pale ice correctly).
func _shore_rim_color() -> Color:
	var tex: Texture2D = ground_tex.get("shore_" + SHORE_SET + "_n", null)
	if tex == null:
		return Color(0.85, 0.76, 0.52)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var warm: Array = []
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p := img.get_pixel(x, y)
			if p.a > 0.8:
				warm.append([p.r + p.g, p])
	if warm.is_empty():
		return Color(0.85, 0.76, 0.52)
	warm.sort_custom(func(a, b): return a[0] > b[0])
	var n := maxi(1, int(warm.size() * 0.3))
	var acc := Color(0, 0, 0)
	for i in range(n):
		acc += warm[i][1]
	return acc / float(n)


## A soft radial stamp (shore colour, alpha peaking at the centre)
## used to feather the rim along every land/water boundary.
func _rim_stamp(col: Color, size: int, peak: float) -> Image:
	# The falloff is a smooth radial gradient: build it small and
	# upscale (bilinear keeps it identical) — the per-pixel build at
	# full size cost ~0.5M GDScript iterations per bake (13e perf).
	var bs := mini(size, 48)
	var img := Image.create(bs, bs, false, Image.FORMAT_RGBA8)
	var half := bs * 0.5
	for y in range(bs):
		for x in range(bs):
			var d := Vector2(x - half + 0.5, y - half + 0.5).length() / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a) # smoothstep
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * peak))
	if bs != size:
		img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return img


## Signed distance (in tiles) from each cell centre to the nearest
## water/land boundary: positive inside water, negative on land.
## Two-pass chamfer distance transform over the cell grid; bilinear
## upsampling at bake time turns it into a smooth field whose zero
## contour rounds every shoreline corner organically.
func _water_sdf() -> PackedFloat32Array:
	const FAR := 64.0
	var wet := PackedByteArray()
	wet.resize(MAP_W * MAP_H)
	for c in water:
		wet[c.y * MAP_W + c.x] = 1
	var d_land := PackedFloat32Array()
	d_land.resize(MAP_W * MAP_H)
	var d_water := PackedFloat32Array()
	d_water.resize(MAP_W * MAP_H)
	for i in range(MAP_W * MAP_H):
		d_land[i] = 0.0 if wet[i] == 0 else FAR
		d_water[i] = 0.0 if wet[i] == 1 else FAR
	_chamfer(d_land)
	_chamfer(d_water)
	var sdf := PackedFloat32Array()
	sdf.resize(MAP_W * MAP_H)
	for i in range(MAP_W * MAP_H):
		sdf[i] = (d_land[i] - 0.5) if wet[i] == 1 else (0.5 - d_water[i])
	# Boost: a tiny pond's deepest WATER cell must still reach a
	# solid core (sdf >= ~1.0), or the feather would wash it out.
	var bodies: Array = features.ponds.duplicate()
	if not features.lake.is_empty():
		bodies.append(features.lake)
	for body in bodies:
		var deep := Vector2i(-1, -1)
		var best := -1.0e9
		for c in body:
			var v: float = sdf[c.y * MAP_W + c.x]
			if v > best:
				best = v
				deep = c
		if deep.x < 0 or best >= 1.05:
			continue
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := deep + Vector2i(dx, dy)
				if not in_bounds(c):
					continue
				var i := c.y * MAP_W + c.x
				if wet[i] == 1:
					sdf[i] = maxf(sdf[i], 1.05 - 0.55 * Vector2(dx, dy).length())
	return sdf


## Two-pass chamfer distance transform, in place (weights 1, sqrt 2).
func _chamfer(d: PackedFloat32Array) -> void:
	const DIAG := 1.41421356
	for y in range(MAP_H):
		for x in range(MAP_W):
			var i := y * MAP_W + x
			if d[i] == 0.0:
				continue
			var m := d[i]
			if x > 0:
				m = minf(m, d[i - 1] + 1.0)
			if y > 0:
				m = minf(m, d[i - MAP_W] + 1.0)
			if x > 0 and y > 0:
				m = minf(m, d[i - MAP_W - 1] + DIAG)
			if x < MAP_W - 1 and y > 0:
				m = minf(m, d[i - MAP_W + 1] + DIAG)
			d[i] = m
	for y in range(MAP_H - 1, -1, -1):
		for x in range(MAP_W - 1, -1, -1):
			var i := y * MAP_W + x
			if d[i] == 0.0:
				continue
			var m := d[i]
			if x < MAP_W - 1:
				m = minf(m, d[i + 1] + 1.0)
			if y < MAP_H - 1:
				m = minf(m, d[i + MAP_W] + 1.0)
			if x < MAP_W - 1 and y < MAP_H - 1:
				m = minf(m, d[i + MAP_W + 1] + DIAG)
			if x > 0 and y < MAP_H - 1:
				m = minf(m, d[i + MAP_W - 1] + DIAG)
			d[i] = m


## The bake's water mask: alpha from the signed distance field,
## sampled bilinearly at 256² then upscaled to bake resolution
## (the field is smooth — 256² samples it faithfully, and the
## per-pixel loop is 4x cheaper than at 512²; 13e perf note).
## The alpha=0.5 contour sits ON the data boundary; alpha saturates
## 0.62 tiles INSIDE the water and 0.38 tiles onto the land, so the
## visible water rounds corners by ~1 tile of feather without ever
## overhanging walkable land by more than ~0.4 tile. Rim + foam
## bands derive from this same mask (see _paint_shore_bands).
func _water_mask() -> Image:
	const Q := 256
	const IN_REACH := 0.62
	const OUT_REACH := 0.38
	var sdf := _water_sdf()
	var small := Image.create(Q, Q, false, Image.FORMAT_RGBA8)
	var scale := float(MAP_W) / float(Q) # tiles per mask pixel
	for py in range(Q):
		var gy := (float(py) + 0.5) * scale - 0.5
		var y0 := clampi(int(floor(gy)), 0, MAP_H - 2)
		var fy := clampf(gy - float(y0), 0.0, 1.0)
		for px in range(Q):
			var gx := (float(px) + 0.5) * scale - 0.5
			var x0 := clampi(int(floor(gx)), 0, MAP_W - 2)
			var fx := clampf(gx - float(x0), 0.0, 1.0)
			var i00 := y0 * MAP_W + x0
			var top := lerpf(sdf[i00], sdf[i00 + 1], fx)
			var bot := lerpf(sdf[i00 + MAP_W], sdf[i00 + MAP_W + 1], fx)
			var d := lerpf(top, bot, fy)
			var a := 0.5 + d * (0.5 / IN_REACH) if d >= 0.0 \
					else 0.5 + d * (0.5 / OUT_REACH)
			small.set_pixel(px, py, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	small.resize(BAKE_PX, BAKE_PX, Image.INTERPOLATE_BILINEAR)
	return small


## The bake's water body tone for the active biome (WATER_TONES);
## falls back to the water tile's average for an unknown biome.
func _water_tone() -> Color:
	if WATER_TONES.has(biome_id):
		return WATER_TONES[biome_id]
	var sea := _tile_image_bake("water_0")
	return _avg_opaque(sea) if sea != null else Color(0.1, 0.35, 0.7)


var _tone_cache: Dictionary = {}

## True when the BAKED ground at a world position reads as water:
## the pixel sits closer (with a safety bias) to the biome's water
## tone than to its land tone. This is the exact test the dry-base
## placement guard and its invariant test share.
func baked_is_water_toned(wpos: Vector2) -> bool:
	if baked_image == null:
		return false
	if _tone_cache.is_empty():
		var li := _tile_image_bake("grass_0")
		_tone_cache = {"water": _water_tone(),
				"land": _avg_opaque(li) if li != null else Color(0.4, 0.5, 0.3)}
	var bs := float(BAKE_PX) / float(MAP_W * TILE) # bake px per world px
	var px := clampi(int(wpos.x * bs), 0, BAKE_PX - 1)
	var py := clampi(int(wpos.y * bs), 0, BAKE_PX - 1)
	var col := baked_image.get_pixel(px, py)
	var wt: Color = _tone_cache["water"]
	var lt: Color = _tone_cache["land"]
	var dw := (col.r - wt.r) * (col.r - wt.r) + (col.g - wt.g) * (col.g - wt.g) \
			+ (col.b - wt.b) * (col.b - wt.b)
	var dl := (col.r - lt.r) * (col.r - lt.r) + (col.g - lt.g) * (col.g - lt.g) \
			+ (col.b - lt.b) * (col.b - lt.b)
	return dw < dl * 1.21


## True when a placement at `cell` would stand on dry baked ground:
## samples the trunk/base pixels at the bottom of the cell.
func placement_base_dry(cell: Vector2i) -> bool:
	var base := cell_center(cell)
	for off in [Vector2(0, 13), Vector2(-9, 13), Vector2(9, 13), Vector2(0, 6)]:
		if baked_is_water_toned(base + off):
			return false
	return true


## Post-bake placement guard for EVERY scatter loop at once (forest
## trees, gold/stone/bush nodes, guaranteed sets, decor, the oasis
## palm ring): any node/decor whose base pixel is water-toned moves
## to the nearest compliant land cell (same base-clearing + corridor
## guards as placement, deterministic ring search), or is dropped
## when no dry cell exists within 3 cells. Runs once per generate()
## right after the bake; grids stay consistent via set_solid.
func _enforce_dry_placements(clear_fn: Callable, corridor_fn: Callable) -> void:
	if baked_image == null:
		return
	var items: Array = []
	items.append_array(nodes)
	items.append_array(decors)
	for item in items:
		if placement_base_dry(item.cell):
			continue
		var target := Vector2i(-1, -1)
		for r in range(1, 4):
			if target.x >= 0:
				break
			for dy in range(-r, r + 1):
				if target.x >= 0:
					break
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var c: Vector2i = item.cell + Vector2i(dx, dy)
					if not in_bounds(c) or water.has(c) or is_solid(c):
						continue
					if not clear_fn.call(c) or corridor_fn.call(c):
						continue
					if placement_base_dry(c):
						target = c
						break
		if target.x >= 0:
			set_solid(item.cell, false)
			item.cell = target
			item.position = cell_center(target)
			set_solid(target, true)
		else:
			set_solid(item.cell, false)
			if item is ResourceNode:
				nodes.erase(item)
			else:
				decors.erase(item)
			item.queue_free()


## Compose the whole ground into ONE texture and scatter the accent
## decals. Runs once per generate(); no per-frame cost afterwards.
func bake_ground(rng: RandomNumberGenerator) -> void:
	var sea := _tile_image_bake("water_0")
	if sea == null:
		return # a8 guards the textures; _draw falls back to flat colours
	# LAND (13e — Tín: "nền cỏ nó vẫn lem lem", measured, not
	# guessed): the old pool's motif (high-frequency) energy averaged
	# ~0.0014 per tile because (1) HALF the pool was 50% pair blends
	# — averaging two unrelated fleck motifs ghosts both and cuts
	# motif contrast to 25–50% of the stronger parent — and (2) the
	# base variant grass_0 is intrinsically a near-flat wash (motif
	# energy 0.00012, ~35x weaker than grass_1's 0.0043) yet filled
	# a third of the tiles and half of every blend. The render stage
	# and the source downscale were measured INNOCENT (render >=
	# bake sharpness at z1.0 and z0.55). Fixes: tiles compose at
	# 48px/cell (source squeezed ~2.4x, not ~3.6x); grass_0 now only
	# sets the TARGET MEAN (map colour unchanged) and never appears
	# as pixels; pair blends are FREQUENCY-SPLIT (low frequencies
	# averaged = anti-lattice tone variety, high frequencies taken
	# from ONE parent at full contrast = no ghosting).
	var base_land := _tile_image_bake("grass_0")
	if base_land == null:
		return
	var base_mean := _avg_opaque(base_land)
	var matched_vars: Array = []
	for vn in ["grass_1", "grass_2"]:
		var vi := _tile_image_bake(vn)
		if vi != null:
			matched_vars.append(_tone_match(vi, base_mean))
	if matched_vars.is_empty():
		return
	# Frequency-split pair blends: new macro-tone arrangements,
	# motif detail inherited whole from one parent (no dilution).
	var blends: Array = []
	for i in range(matched_vars.size()):
		var a: Image = matched_vars[i]
		var b: Image = matched_vars[(i + 1) % matched_vars.size()]
		if a == b:
			continue
		blends.append(_split_blend(a, b))
	var tile_pool: Array = []
	for v in matched_vars + blends:
		tile_pool.append_array(_eight_orientations(v))
	# Two full-map layers (land everywhere, water everywhere), then
	# a signed-distance-field water mask composites them: the
	# shoreline becomes a smooth, organically rounded curve
	# (~1 tile feather) instead of cell steps.
	# WATER keeps ONE flat base colour (the biome's WATER_TONES
	# entry — deep + saturated, never the pale tile average) whose
	# only variation is large soft blotches (radius >= 3 tiles) —
	# life comes from the animated sparkle/foam VFX on top.
	var land_full := Image.create(BAKE_PX, BAKE_PX, false, Image.FORMAT_RGBA8)
	for ty in range(MAP_H):
		for tx in range(MAP_W):
			land_full.blit_rect(tile_pool[rng.randi_range(0, tile_pool.size() - 1)],
					Rect2i(0, 0, BAKE_CELL, BAKE_CELL),
					Vector2i(tx * BAKE_CELL, ty * BAKE_CELL))
	var water_avg := _water_tone()
	# The sea is composed at QUARTER resolution and upscaled once:
	# its only content is the flat tone + huge soft blotches (6–10
	# tiles wide), which a 1024² canvas samples faithfully, while
	# stamping 56 soft blends at full bake res cost ~3s of generate
	# for zero visible gain (13e perf profile).
	var sea_full := Image.create(BAKE_PX / 4, BAKE_PX / 4, false,
			Image.FORMAT_RGBA8)
	sea_full.fill(Color(water_avg.r, water_avg.g, water_avg.b, 1.0))
	_blotch_water(sea_full, water_avg, rng)
	sea_full.resize(BAKE_PX, BAKE_PX, Image.INTERPOLATE_BILINEAR)
	# Water mask from the signed distance field (see _water_mask):
	# alpha follows true distance to the shore, so outlines round
	# organically while staying glued to the data grid's boundary.
	var mask := _water_mask()
	var img := land_full
	img.blend_rect_mask(sea_full, mask, Rect2i(0, 0, BAKE_PX, BAKE_PX), Vector2i.ZERO)
	# Shore rim + foam line are painted from the SAME blurred mask
	# that placed the water (rim = the mask's mid band, foam = a thin
	# band just inside the water edge), so the bank hugs the water
	# contour by construction — no per-tile shore geometry anywhere.
	_paint_shore_bands(img, mask)
	# NO global blur pass: the old downscale/upscale "soft pass"
	# melted the shore bands in but smeared ALL land pixel detail
	# with them (the lem-lem look). Shore softness comes from the
	# mask + band construction alone; land pixels ship native.
	baked_image = img
	# The texture gets its own mipmapped copy (baked_image stays
	# mip-free for the pixel samplers): at gameplay zoom the ground
	# is minified, and mipmaps make that a true area average of the
	# 48px/cell detail instead of point-sampled aliasing (13e).
	var tex_img := img.duplicate() as Image
	tex_img.generate_mipmaps()
	baked_ground = ImageTexture.create_from_image(tex_img)
	_scatter_decals(rng)


## Per-channel DC correction of a tile variant toward a target mean
## colour: every pixel is scaled by target/mean per channel, which
## matches the variant's overall tone while preserving its texture
## (the AC detail) exactly. Used so multiple land variants can mix
## per tile without reading as a patchwork quilt.
func _tone_match(img: Image, target: Color) -> Image:
	var mean := _avg_opaque(img)
	var kr := target.r / maxf(mean.r, 0.01)
	var kg := target.g / maxf(mean.g, 0.01)
	var kb := target.b / maxf(mean.b, 0.01)
	if absf(kr - 1.0) < 0.01 and absf(kg - 1.0) < 0.01 and absf(kb - 1.0) < 0.01:
		return img
	var out := img.duplicate() as Image
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var p := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(minf(p.r * kr, 1.0), minf(p.g * kg, 1.0),
					minf(p.b * kb, 1.0), p.a))
	return out


## Low-frequency component of a tile image: a hard downscale to
## BAKE_CELL/8 and back (bilinear both ways) keeps only blobs of
## ~8px and up — the macro tone — and discards the fleck motif.
func _lowpass(img: Image) -> Image:
	var s := maxi(2, BAKE_CELL / 8)
	var out := img.duplicate() as Image
	out.resize(s, s, Image.INTERPOLATE_BILINEAR)
	out.resize(BAKE_CELL, BAKE_CELL, Image.INTERPOLATE_BILINEAR)
	return out


## Frequency-split blend of two tone-matched variants: the result's
## LOW frequencies are the pair's average (new macro-tone shapes,
## so the lattice still dissolves) while its HIGH frequencies are
## parent a's own at full contrast — out = a + 0.5*(low(b)-low(a)).
## Replaces the old 50% pixel blend, which ghosted both motifs and
## quartered the stronger parent's motif energy (13e measurement).
func _split_blend(a: Image, b: Image) -> Image:
	var la := _lowpass(a)
	var lb := _lowpass(b)
	var out := a.duplicate() as Image
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var pa := a.get_pixel(x, y)
			var pla := la.get_pixel(x, y)
			var plb := lb.get_pixel(x, y)
			out.set_pixel(x, y, Color(
					clampf(pa.r + 0.5 * (plb.r - pla.r), 0.0, 1.0),
					clampf(pa.g + 0.5 * (plb.g - pla.g), 0.0, 1.0),
					clampf(pa.b + 0.5 * (plb.b - pla.b), 0.0, 1.0), pa.a))
	return out


## All eight orientations of a square tile image (4 rotations, each
## with and without an X mirror) — rotating a tile moves its motif
## (flower flecks, tuft clusters) to a different corner, which is
## what dissolves the visible repeat lattice when variants mix.
func _eight_orientations(img: Image) -> Array:
	var out: Array = []
	var cur := img
	for r in range(4):
		out.append(cur)
		var m := cur.duplicate() as Image
		m.flip_x()
		out.append(m)
		if r < 3:
			cur = _rot90(cur)
	return out


## Exact 90-degree clockwise rotation of a small tile image
## (per-pixel transpose — no resampling, detail preserved).
func _rot90(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(h, w, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			out.set_pixel(h - 1 - y, x, img.get_pixel(x, y))
	return out


## Large soft light/dark blotches over the flat water tone: the only
## tonal variation the bake allows on water (radius >= 3 tiles, low
## alpha), so open water reads calm instead of chessboarded. Stamps
## are built small and upscaled so the bake stays fast.
func _blotch_water(sea_full: Image, base: Color, rng: RandomNumberGenerator) -> void:
	# Runs on the quarter-resolution sea canvas (see bake_ground);
	# the rng draw pattern is unchanged (same calls, values scaled
	# by the canvas ratio) so generation streams stay identical.
	var q := sea_full.get_width()
	var tones: Array = [base.lightened(0.07), base.darkened(0.06),
			base.lightened(0.04), base.darkened(0.045)]
	for i in range(56):
		var col: Color = tones[rng.randi_range(0, tones.size() - 1)]
		var size_b := rng.randi_range(384, 640) # 6–10 tiles (bake px)
		var size := maxi(8, size_b * q / BAKE_PX)
		var stamp := _rim_stamp(col, 96, rng.randf_range(0.10, 0.17))
		stamp.resize(size, size, Image.INTERPOLATE_BILINEAR)
		sea_full.blend_rect(stamp, Rect2i(0, 0, size, size),
				Vector2i(rng.randi_range(-size_b / 2, BAKE_PX - size_b / 2) * q / BAKE_PX,
						rng.randi_range(-size_b / 2, BAKE_PX - size_b / 2) * q / BAKE_PX))


## Shore rim + wet contour + foam line derived from the SAME blurred
## water mask that composited the water, so all four share one
## geometry: rim = the mask's mid band (a feathered ring straddling
## the water contour), wet = a dark band just inside the water edge,
## foam = a thin bright band inside that.
## Band math runs at quarter resolution — the bands are soft anyway.
func _paint_shore_bands(img: Image, mask: Image) -> void:
	const Q := 512
	var m := mask.duplicate() as Image
	m.convert(Image.FORMAT_RGBA8)
	m.resize(Q, Q, Image.INTERPOLATE_BILINEAR)
	# Bank tone = the shore tile's AVERAGE colour (the warmest-pixel
	# pick read as a pale glowing halo); the rim band sits mostly on
	# the LAND side of the contour (centre 0.40), foam just inside.
	var shore_tex: Texture2D = ground_tex.get("shore_" + SHORE_SET + "_n", null)
	var rim_col := _shore_rim_color()
	if shore_tex != null:
		var simg := shore_tex.get_image()
		if simg != null:
			simg.convert(Image.FORMAT_RGBA8)
			rim_col = rim_col.lerp(_avg_opaque(simg), 0.55)
	const FOAM_COL := Color(0.93, 0.98, 1.0)
	# Wet contour: the water tone darkened, a band just INSIDE the
	# water edge (mask alpha ~0.64 ≈ 0.17 tiles in, ~0.25 tile wide).
	# Every water body gets a defined dark outline against the land;
	# the foam line (alpha ~0.87) stays inside it. Same mask, so the
	# contour can never drift off the shoreline.
	var wet_col := _water_tone().darkened(0.38)
	# The three bands are pre-composited into ONE overlay here
	# (alpha-over is associative, so the result over the ground is
	# identical to blending rim, wet, foam in sequence) — at the
	# full-res bake that saves two full-frame upscales + two full-frame
	# blends (~2.5s of generate time, 13e perf note). The overlay is
	# also CLIPPED to the water bounding box (+2 cells): bands only
	# exist near shores, so the loop, the upscale and the blend all
	# shrink to that region instead of the full bake frame.
	if water.is_empty():
		return
	var cmin := Vector2i(MAP_W, MAP_H)
	var cmax := Vector2i.ZERO
	for c in water:
		cmin = cmin.min(c)
		cmax = cmax.max(c)
	var qpc := Q / MAP_W # mask pixels per cell (8)
	var k := BAKE_PX / Q # bake px per mask pixel (8)
	var rx := maxi(0, (cmin.x - 2) * qpc)
	var ry := maxi(0, (cmin.y - 2) * qpc)
	var rw2 := mini(Q, (cmax.x + 3) * qpc) - rx
	var rh2 := mini(Q, (cmax.y + 3) * qpc) - ry
	var bands := Image.create(rw2, rh2, false, Image.FORMAT_RGBA8)
	for y in range(rh2):
		for x in range(rw2):
			var a := m.get_pixel(rx + x, ry + y).a
			var rw := clampf(1.0 - absf(a - 0.40) / 0.30, 0.0, 1.0)
			var ra := rw * rw * 0.8 if rw > 0.01 else 0.0
			var ww := clampf(1.0 - absf(a - 0.64) / 0.09, 0.0, 1.0)
			var wa := ww * 0.55 if ww > 0.01 else 0.0
			var fw := clampf(1.0 - absf(a - 0.87) / 0.06, 0.0, 1.0)
			var fa := fw * 0.45 if fw > 0.01 else 0.0
			if ra <= 0.0 and wa <= 0.0 and fa <= 0.0:
				continue
			# over: rim <- wet <- foam (premultiplied accumulate)
			var cr := rim_col.r * ra
			var cg := rim_col.g * ra
			var cb := rim_col.b * ra
			var ca := ra
			cr = wet_col.r * wa + cr * (1.0 - wa)
			cg = wet_col.g * wa + cg * (1.0 - wa)
			cb = wet_col.b * wa + cb * (1.0 - wa)
			ca = wa + ca * (1.0 - wa)
			cr = FOAM_COL.r * fa + cr * (1.0 - fa)
			cg = FOAM_COL.g * fa + cg * (1.0 - fa)
			cb = FOAM_COL.b * fa + cb * (1.0 - fa)
			ca = fa + ca * (1.0 - fa)
			if ca > 0.001:
				bands.set_pixel(x, y, Color(cr / ca, cg / ca, cb / ca, ca))
	bands.resize(rw2 * k, rh2 * k, Image.INTERPOLATE_BILINEAR)
	img.blend_rect(bands, Rect2i(0, 0, rw2 * k, rh2 * k),
			Vector2i(rx * k, ry * k))


func _smooth01(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Soft decal from an accent tile: alpha fades smoothly across the
## whole radius (no opaque core), so the patch melts into the base.
func _make_decal(tname: String) -> Texture2D:
	var tex: Texture2D = ground_tex.get(tname, null)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	img.resize(96, 96, Image.INTERPOLATE_BILINEAR)
	for y in range(96):
		for x in range(96):
			var d := Vector2(x - 47.5, y - 47.5).length() / 47.5
			var fall := 1.0 - _smooth01(clampf((d - 0.3) / 0.7, 0.0, 1.0))
			if fall < 1.0:
				var p := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(p.r, p.g, p.b, p.a * fall))
	return ImageTexture.create_from_image(img)


## Dirt-style decal as a soft irregular BLOB: the source tile's colour
## texture, but alpha falls smoothly to zero across the WHOLE radius
## and the edge radius wobbles with angle — no square (and no plain
## circle) outline can survive. `phase` varies the wobble per variant.
func _make_blob_decal(tname: String, phase: float) -> Texture2D:
	var tex: Texture2D = ground_tex.get(tname, null)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	img.resize(128, 128, Image.INTERPOLATE_BILINEAR)
	for y in range(128):
		for x in range(128):
			var v := Vector2(x - 63.5, y - 63.5)
			var d := v.length() / 63.5
			var p := img.get_pixel(x, y)
			if d >= 1.0:
				img.set_pixel(x, y, Color(p.r, p.g, p.b, 0.0))
				continue
			var ang := atan2(v.y, v.x)
			var edge := 0.74 + 0.17 * sin(ang * 3.0 + phase) + 0.09 * sin(ang * 7.0 + phase * 2.3)
			var t := clampf(d / maxf(edge, 0.1), 0.0, 1.0)
			var a := 1.0 - _smooth01(t)
			img.set_pixel(x, y, Color(p.r, p.g, p.b, p.a * a * 0.9))
	return ImageTexture.create_from_image(img)


## Tiny flower-sprinkle textures cut from the flower tile itself:
## crops centred on real blossom pixels (white petals / yellow
## hearts), edge-faded. Scattered in clumps they read as organic
## flower specks — never the whole-tile pattern (whose fixed blossom
## layout used to print plus/cross formations along the cell grid).
func _make_flower_sprites(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var tex: Texture2D = ground_tex.get("grass_1", null)
	if tex == null:
		return out
	var img := tex.get_image()
	if img == null:
		return out
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w < 32 or h < 32:
		return out
	var crop := maxi(24, mini(w, h) / 4)
	var half := crop / 2
	var spots: Array = []
	for y in range(half, h - half, 3):
		for x in range(half, w - half, 3):
			var p := img.get_pixel(x, y)
			if p.a < 0.8:
				continue
			var petal := minf(p.r, minf(p.g, p.b)) > 0.72
			var heart := p.r > 0.7 and p.g > 0.5 and p.b < 0.45
			if petal or heart:
				spots.append(Vector2i(x, y))
	# Shuffle, then greedily keep centres well apart so crops differ.
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var centres: Array = []
	for sp in spots:
		var far := true
		for c0 in centres:
			if Vector2(sp - c0).length() < mini(w, h) * 0.16:
				far = false
				break
		if far:
			centres.append(sp)
		if centres.size() >= 8:
			break
	if centres.size() < 2:
		# Fallback (biome grades without bright blossoms): plain crops.
		centres = [Vector2i(w / 3, h / 3), Vector2i(2 * w / 3, 2 * h / 3),
				Vector2i(w / 2, h / 2)]
	for c0 in centres:
		var piece := Image.create(crop, crop, false, Image.FORMAT_RGBA8)
		piece.blit_rect(img, Rect2i(c0.x - half, c0.y - half, crop, crop), Vector2i.ZERO)
		piece.resize(48, 48, Image.INTERPOLATE_BILINEAR)
		for y in range(48):
			for x in range(48):
				var d := Vector2(x - 23.5, y - 23.5).length() / 23.5
				if d > 0.45:
					var p := piece.get_pixel(x, y)
					var fall := 1.0 - _smooth01(clampf((d - 0.45) / 0.55, 0.0, 1.0))
					piece.set_pixel(x, y, Color(p.r, p.g, p.b, p.a * fall))
		out.append(ImageTexture.create_from_image(piece))
	return out


## A decal spot is valid on dry land with no water in the 3×3
## neighbourhood and clear of both base clearings.
func _decal_spot_ok(pos: Vector2) -> bool:
	var c := world_to_cell(pos)
	if not in_bounds(c) or water.has(c):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if water.has(c + Vector2i(dx, dy)):
				return false
	if Vector2(c - player_base).length() < 3.5 or Vector2(c - enemy_base).length() < 3.5:
		return false
	return true


func _scatter_decals(rng: RandomNumberGenerator) -> void:
	for d in ground_decals:
		d.queue_free()
	ground_decals.clear()
	var layer := Node2D.new()
	layer.name = "GroundDecals"
	layer.z_index = 1
	add_child(layer)
	var margin := 40.0
	var span := float(MAP_W * TILE) - 2.0 * margin
	var place := func(tex: Texture2D, pos: Vector2, scl: Vector2, alpha: float) -> void:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = pos
		s.rotation = rng.randf_range(0.0, TAU)
		s.scale = scl
		s.modulate = Color(1, 1, 1, alpha)
		layer.add_child(s)
		ground_decals.append(s)
	var rand_pos := func() -> Vector2:
		return Vector2(margin + rng.randf() * span, margin + rng.randf() * span)
	# Grass tufts: broad soft patches at continuous random positions
	# (never cell centres — the old near-grid placement banded them).
	var tuft := _make_decal("grass_2")
	if tuft != null:
		var placed := 0
		var guard := 0
		while placed < 80 and guard < 600:
			guard += 1
			var pos: Vector2 = rand_pos.call()
			if not _decal_spot_ok(pos):
				continue
			place.call(tuft, pos, Vector2.ONE * rng.randf_range(0.55, 1.2),
					rng.randf_range(0.38, 0.68))
			placed += 1
	# Dirt: irregular soft blobs, non-uniform scale of 0.7–1.6 tiles
	# per axis, lower alpha — smudges of earth, never brown squares.
	var blobs: Array = []
	for ph in [0.0, 2.1, 4.2]:
		var b := _make_blob_decal("dirt", ph)
		if b != null:
			blobs.append(b)
	if not blobs.is_empty():
		var placed := 0
		var guard := 0
		while placed < 24 and guard < 300:
			guard += 1
			var pos: Vector2 = rand_pos.call()
			if not _decal_spot_ok(pos):
				continue
			var scl := Vector2(rng.randf_range(0.7, 1.6), rng.randf_range(0.7, 1.6)) \
					* (float(TILE) / 128.0)
			place.call(blobs[rng.randi_range(0, blobs.size() - 1)], pos, scl,
					rng.randf_range(0.5, 0.78))
			placed += 1
	# Flowers: organic clumps — a random centre, then 3–7 tiny
	# blossom sprites sprinkled within ~1 tile with jitter. No rows,
	# no columns, no crosses.
	var flowers := _make_flower_sprites(rng)
	if not flowers.is_empty():
		var clumps := 0
		var guard := 0
		while clumps < 16 and guard < 300:
			guard += 1
			var centre: Vector2 = rand_pos.call()
			if not _decal_spot_ok(centre):
				continue
			clumps += 1
			var n := rng.randi_range(3, 7)
			for k in range(n):
				var off := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) \
						* sqrt(rng.randf()) * 30.0
				var pos := centre + off
				if water.has(world_to_cell(pos)):
					continue
				place.call(flowers[rng.randi_range(0, flowers.size() - 1)], pos,
						Vector2.ONE * rng.randf_range(0.5, 0.85),
						rng.randf_range(0.85, 1.0))


## Baked colour at a cell centre (tests + minimap sampling).
func baked_color_at(c: Vector2i) -> Color:
	if baked_image == null:
		return Color.TRANSPARENT
	var bs := float(BAKE_PX) / float(MAP_W * TILE) # bake px per world px
	return baked_image.get_pixel(
			clampi(int((c.x * TILE + TILE / 2) * bs), 0, BAKE_PX - 1),
			clampi(int((c.y * TILE + TILE / 2) * bs), 0, BAKE_PX - 1))


func _draw() -> void:
	if baked_ground != null:
		# The whole ground is ONE baked texture (see bake_ground).
		draw_texture_rect(baked_ground,
				Rect2(Vector2.ZERO, Vector2(MAP_W * TILE, MAP_H * TILE)), false)
	else:
		# Fallback (textures missing): flat biome colours only.
		var bdef := biome()
		var base_a: Color = bdef["fallback_land_a"]
		var base_b: Color = bdef["fallback_land_b"]
		var water_col: Color = bdef["fallback_water"]
		for y in range(MAP_H):
			for x in range(MAP_W):
				var c := Vector2i(x, y)
				var rect := Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
				if water.has(c):
					draw_rect(rect, water_col.lerp(water_col.lightened(0.15), tile_shade[y * MAP_W + x]))
				else:
					draw_rect(rect, base_a.lerp(base_b, tile_shade[y * MAP_W + x]))
	# Cliff band of each waterfall, drawn proud of the ground.
	for cc in cliff_cells:
		if cliff_tex.is_empty():
			break
		var ctex: Texture2D = cliff_tex[_cell_hash(cc) % cliff_tex.size()]
		draw_texture_rect(ctex, Rect2(Vector2(cc) * TILE + Vector2(0, -12),
				Vector2(TILE, TILE + 12)), false)
