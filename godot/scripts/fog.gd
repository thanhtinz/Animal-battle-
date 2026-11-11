class_name Fog
extends Node2D
## Empire Age P3 — Fog of War from the PLAYER team's perspective.
##
## Per-tile state: 0 = unexplored (solid black), 1 = explored but not
## currently seen (dimmed; terrain + last-seen enemy buildings),
## 2 = visible (drawn clear). Recomputed ~2x per second from the
## sight radii of player units (Stats) and player buildings.
##
## Entity rules: enemy UNITS render only on currently-visible tiles;
## enemy BUILDINGS render once any of their footprint tiles has been
## explored (last-seen silhouettes — their HP/combat state still
## resolves normally, the player just can't watch it change).
## Player entities always render.

const UPDATE_INTERVAL := 0.5
const BUILDING_SIGHT := {"town_center": 6, "tower": 8}

var game = null # Main (duck-typed)
var world = null # World (duck-typed)

## Whose eyes the fog is computed for (P4 MP: the local player's
## faction team; Main sets it before setup — 0 in SP, unchanged).
var local_team: int = 0

## Spectator mode (13h replay): everything is visible, nothing
## is drawn — the whole map is the audience's.
var observer: bool = false

## 14a replay follow: while true (Main enables it for replay
## playback ONLY — live matches never pay for it), every team's
## fog is maintained in parallel and the DRAWN state switches
## between them: following a player shows exactly what that
## player's team sees, explored-memory included.
var track_teams: bool = false
var _team_states: Dictionary = {} # team -> PackedByteArray
var _view_team: int = -1 # -1 = observer (full vision)

var state: PackedByteArray = PackedByteArray()
var _accum := 0.0


func setup(p_game, p_world) -> void:
	game = p_game
	world = p_world
	state.resize(World.MAP_W * World.MAP_H)
	update_fog()


func _idx(c: Vector2i) -> int:
	return c.y * World.MAP_W + c.x


func cell_state(c: Vector2i) -> int:
	if world == null or not world.in_bounds(c):
		return 0
	return int(state[_idx(c)])


func is_visible_cell(c: Vector2i) -> bool:
	return cell_state(c) == 2


func is_explored_cell(c: Vector2i) -> bool:
	return cell_state(c) >= 1


func _process(delta: float) -> void:
	if game != null and game.paused:
		return
	_accum += delta
	if _accum >= UPDATE_INTERVAL:
		_accum = 0.0
		update_fog()


## 15b: does this entity reveal fog for the viewer? Ordinarily
## only the viewer's own faction reveals. In a diplomacy match
## the fog UNIONS across current allies: an entity also reveals
## when its owner shares vision with the viewer's slot — Main
## derives that from the sim stance tables, and vision ends the
## moment a break is declared (so the union follows the
## declaration, not the not-yet-fallen stance).
func _reveals(e_team: int, e_owner: int, v_team: int, v_slot: int) -> bool:
	if e_team == v_team:
		return true
	if game != null and v_slot >= 0 \
			and bool(game.get("dip_enabled")):
		return game.dip_vision_shared(v_slot, e_owner)
	return false


func _viewer_slot() -> int:
	if game == null:
		return -1
	var ls = game.get("local_slot")
	return int(ls) if ls != null else -1


func _slot_for_team(team: int) -> int:
	if game == null or not game.has_method("team_of_slot"):
		return -1
	for slot in range(game.slot_count()):
		if game.team_of_slot(slot) == team:
			return slot
	return -1


func update_fog() -> void:
	if game == null or world == null:
		return
	if track_teams:
		_track_update()
		return
	if observer:
		for i in range(state.size()):
			state[i] = 2
		apply_entity_visibility()
		queue_redraw()
		return
	var visible: Dictionary = {}
	var reveal := func(c: Vector2i, radius: int) -> void:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius + radius:
					continue
				var n := c + Vector2i(dx, dy)
				if world.in_bounds(n):
					visible[n] = true
	var vslot := _viewer_slot()
	for u in game.units:
		if _reveals(u.team, u.owner_id, local_team, vslot) and not u.is_dead():
			reveal.call(world.world_to_cell(u.global_position),
					int(Stats.unit_stat(u.unit_type, "sight")))
	if game.get("ships") != null:
		for s in game.ships:
			if _reveals(s.team, s.owner_id, local_team, vslot) and not s.is_dead():
				reveal.call(world.world_to_cell(s.global_position),
						int(Stats.ship_stat(s.ship_type, "sight")))
	for b in game.buildings:
		if _reveals(b.team, b.owner_id, local_team, vslot) and not b.destroyed:
			var centre = b.origin_cell + Vector2i(b.size.x / 2, b.size.y / 2)
			reveal.call(centre, int(BUILDING_SIGHT.get(b.btype, 5)))
	for y in range(World.MAP_H):
		for x in range(World.MAP_W):
			var c := Vector2i(x, y)
			var i := _idx(c)
			if visible.has(c):
				state[i] = 2
			elif state[i] == 2:
				state[i] = 1
	apply_entity_visibility()
	queue_redraw()


## The set of cells a team currently sees (same reveal rules as
## the live single-team path in update_fog).
func _vision_for(team: int) -> Dictionary:
	var visible: Dictionary = {}
	var reveal := func(c: Vector2i, radius: int) -> void:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius + radius:
					continue
				var n := c + Vector2i(dx, dy)
				if world.in_bounds(n):
					visible[n] = true
	var vslot := _slot_for_team(team)
	for u in game.units:
		if _reveals(u.team, u.owner_id, team, vslot) and not u.is_dead():
			reveal.call(world.world_to_cell(u.global_position),
					int(Stats.unit_stat(u.unit_type, "sight")))
	if game.get("ships") != null:
		for s in game.ships:
			if _reveals(s.team, s.owner_id, team, vslot) and not s.is_dead():
				reveal.call(world.world_to_cell(s.global_position),
						int(Stats.ship_stat(s.ship_type, "sight")))
	for b in game.buildings:
		if _reveals(b.team, b.owner_id, team, vslot) and not b.destroyed:
			var centre = b.origin_cell + Vector2i(b.size.x / 2, b.size.y / 2)
			reveal.call(centre, int(BUILDING_SIGHT.get(b.btype, 5)))
	return visible


func _ensure_team_states() -> void:
	if game == null:
		return
	var teams: Dictionary = {}
	for slot in range(game.slot_count()):
		teams[game.team_of_slot(slot)] = true
	for team in teams.keys():
		if not _team_states.has(team):
			var st := PackedByteArray()
			st.resize(World.MAP_W * World.MAP_H)
			_team_states[team] = st


func _track_update() -> void:
	_ensure_team_states()
	for team in _team_states.keys():
		var st: PackedByteArray = _team_states[team]
		var visible := _vision_for(int(team))
		for y in range(World.MAP_H):
			for x in range(World.MAP_W):
				var c := Vector2i(x, y)
				var i := _idx(c)
				if visible.has(c):
					st[i] = 2
				elif st[i] == 2:
					st[i] = 1
		_team_states[team] = st
	_apply_view_state()
	apply_entity_visibility()
	queue_redraw()


func _apply_view_state() -> void:
	if _view_team >= 0 and _team_states.has(_view_team):
		state = (_team_states[_view_team] as PackedByteArray).duplicate()
		return
	if state.size() != World.MAP_W * World.MAP_H:
		state.resize(World.MAP_W * World.MAP_H)
	for i in range(state.size()):
		state[i] = 2


## 14a replay follow: switch whose fog the view shows. A team of
## -1 (or one not in the match) restores full observer vision.
## The camera is untouched — only vision changes.
func set_view_team(team: int) -> void:
	_view_team = team
	if track_teams:
		_ensure_team_states()
	observer = team < 0 or not _team_states.has(team)
	if not observer:
		local_team = team
	_apply_view_state()
	apply_entity_visibility()
	queue_redraw()


## The team whose eyes the view currently uses (-1 = observer).
func view_team_now() -> int:
	return _view_team


func apply_entity_visibility() -> void:
	if game == null or world == null:
		return
	for u in game.units:
		if u.team != local_team:
			# A garrisoned (fled) villager stays hidden inside its
			# building regardless of fog.
			u.visible = is_visible_cell(world.world_to_cell(u.global_position)) and not u.garrisoned
	for b in game.buildings:
		if b.team != local_team:
			var seen := false
			for c in b.cells():
				if is_explored_cell(c):
					seen = true
					break
			b.visible = seen
	# Enemy ships behave like enemy units (only on visible tiles);
	# neutral beasts show only while their tile is currently seen.
	if game.get("ships") != null:
		for s in game.ships:
			if s.team != local_team:
				s.visible = is_visible_cell(world.world_to_cell(s.global_position))
	if world.get("beasts") != null:
		for bst in world.beasts:
			bst.visible = is_visible_cell(world.world_to_cell(bst.global_position))


func _draw() -> void:
	if world == null:
		return
	for y in range(World.MAP_H):
		for x in range(World.MAP_W):
			var s := int(state[y * World.MAP_W + x])
			if s == 2:
				continue
			var rect := Rect2(Vector2(x, y) * World.TILE, Vector2(World.TILE, World.TILE))
			if s == 0:
				draw_rect(rect, Color(0.01, 0.01, 0.02, 1.0))
			else:
				draw_rect(rect, Color(0.01, 0.01, 0.03, 0.48))
