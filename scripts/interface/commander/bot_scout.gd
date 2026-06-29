class_name BotScout
extends RefCounted

## BotScout — maintains a fog-of-uncertainty grid and tasks one fast unit to
## visit unseen / stale grid points continuously.
##
## The scout grid divides the map into SCOUT_GRID_SIZE-world-unit intervals.
## Each point carries a timestamp (Bot.seconds_elapsed()) of when it was last
## in line-of-sight of an owned unit. A point is "expired" once that timestamp
## is more than SCOUT_EXPIRATION_TIMER seconds in the past.
##
## One unit (_scout_unit) is assigned to reach the nearest expired point; if the
## military re-tasks it the module releases it and picks the next-fastest free unit.

## World units between scout grid columns/rows.
const SCOUT_GRID_SIZE: int = 5
## Seconds before a scouted point is considered expired and worth revisiting.
const SCOUT_EXPIRATION_TIMER: float = 60.0

var _bot: Bot
var _act: BotActuator

## Vector2i → float: seconds_elapsed() when the point was last observed.
## All points start at -(SCOUT_EXPIRATION_TIMER + 1.0) — treated as never scouted.
var _scout_grid: Dictionary = {}

## Vector2i → true for every point that has been in real line of sight at least once
## (set only on a genuine LOS hit, never by the optimistic waypoint stamp). Drives the
## coverage query so a scenario can assert the whole map was actually scouted.
var _ever_seen: Dictionary = {}

## Precomputed world-space position (with terrain Y) for each grid index.
## Built once in _init; avoids recomputing per tick.
var _scout_grid_positions: Dictionary = {}

## Map half-extents in local space, cached for _grid_world_pos.
var _map_half_w: float = 0.0
var _map_half_d: float = 0.0
## Full local-space extents (= world-space extents when Map scale = 1).
var _map_W: float = 0.0
var _map_D: float = 0.0

## The single unit assigned to scout (or null).
var _scout_unit: Commandable = null


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act
	_build_scout_grid()


## Called by BotBrain.think() on the brain's throttled cadence.
func tick() -> void:
	_update_scout_grid()
	_update_scout_unit()


# ─── COVERAGE QUERY (used by scenario tests / debug) ─────────────────────────

## Number of scout-grid points that have been in real line of sight at least once.
func observed_point_count() -> int:
	return _ever_seen.size()

## Total number of scout-grid points.
func total_point_count() -> int:
	return _scout_grid.size()

## Fraction (0–1) of scout-grid points seen at least once; 0 when the grid is empty.
func observed_fraction() -> float:
	if _scout_grid.is_empty():
		return 0.0
	return float(_ever_seen.size()) / float(_scout_grid.size())

## True once every scout-grid point has been in line of sight at least once.
func all_points_seen() -> bool:
	return not _scout_grid.is_empty() and _ever_seen.size() >= _scout_grid.size()

## Per scout-grid point, for debug visualisation: its world position, the seconds_elapsed()
## time it was last observed (negative sentinel until first seen), and whether it has ever
## been in real line of sight. The expiry window is SCOUT_EXPIRATION_TIMER.
func debug_points() -> Array:
	var out: Array = []
	for idx: Vector2i in _scout_grid:
		out.append({
			"position": _scout_grid_positions[idx],
			"last_seen": _scout_grid[idx],
			"ever_seen": _ever_seen.has(idx),
		})
	return out


# ─── GRID CONSTRUCTION ───────────────────────────────────────────────────────

func _build_scout_grid() -> void:
	if _bot.map == null or _bot.map.height_map == null:
		return
	var hs: HeightMapShape3D = _bot.map.height_map
	_map_W = float(hs.map_width - 1)
	_map_D = float(hs.map_depth - 1)
	_map_half_w = _map_W * 0.5
	_map_half_d = _map_D * 0.5

	var max_i: int = ceili(_map_W / float(SCOUT_GRID_SIZE))
	var max_j: int = ceili(_map_D / float(SCOUT_GRID_SIZE))
	var init_ts: float = -(SCOUT_EXPIRATION_TIMER + 1.0)

	for i: int in range(max_i + 1):
		for j: int in range(max_j + 1):
			var idx := Vector2i(i, j)
			_scout_grid[idx] = init_ts
			var world_pos: Vector3 = _grid_world_pos(idx)
			world_pos.y = _bot.map.terrain_height_at(VU.inXZ(world_pos))
			_scout_grid_positions[idx] = world_pos


## World-space position of grid index (i, j). The map's global_transform handles
## any translation or scale so this is correct even when the map is not at origin.
func _grid_world_pos(idx: Vector2i) -> Vector3:
	var local := Vector3(
		-_map_half_w + min(float(idx.x) * SCOUT_GRID_SIZE, _map_W),
		0.0,
		-_map_half_d + min(float(idx.y) * SCOUT_GRID_SIZE, _map_D)
	)
	return _bot.map.global_transform * local


# ─── LOS UPDATE ──────────────────────────────────────────────────────────────

## Raycast from each owned unit to nearby grid points; mark visible ones current.
func _update_scout_grid() -> void:
	if _bot.map == null:
		return
	var now: float = _bot.seconds_elapsed()
	var space_state: PhysicsDirectSpaceState3D = _bot.map.get_world_3d().direct_space_state
	var los_mask: int = CollisionLayers.Mask.TERRAIN | CollisionLayers.Mask.STRUCTURE_BLOCKER

	for unit: Commandable in _bot.get_units():
		# Gate on the unit's ACTUAL vision radius — the same shape the fog of war reveals
		# with — so a point is only marked scouted once it's genuinely in sight (and thus
		# fog-cleared), not merely near the unit.
		var vision: float = _bot.vision_radius(unit)
		if vision <= 0.0:
			continue
		var radius_sq: float = vision * vision
		var unit_from: Vector3 = unit.global_position + Vector3.UP * 0.1
		var unit_xz: Vector2 = VU.inXZ(unit.global_position)
		for idx: Vector2i in _scout_grid_positions:
			var pt: Vector3 = _scout_grid_positions[idx]
			if unit_xz.distance_squared_to(VU.inXZ(pt)) > radius_sq:
				continue
			var query := PhysicsRayQueryParameters3D.create(
				unit_from, pt + Vector3.UP * 0.1, los_mask
			)
			query.collide_with_bodies = true
			if space_state.intersect_ray(query).is_empty():
				_scout_grid[idx] = now
				_ever_seen[idx] = true


# ─── SCOUT UNIT ASSIGNMENT ───────────────────────────────────────────────────

## Each think: validate the current scout, replace if re-tasked, and issue the
## next waypoint when idle or just (re)assigned. Runs every think so the scout
## can claim an idle unit in the same tick it goes idle — before the military's
## idle-sweep can issue it an AttackMove instead.
func _update_scout_unit() -> void:
	var now: float = _bot.seconds_elapsed()

	if not is_instance_valid(_scout_unit):
		_scout_unit = null

	if _scout_unit != null and _scout_was_retasked():
		_scout_unit = null

	var just_assigned: bool = false
	if _scout_unit == null:
		_scout_unit = _pick_fastest_available()
		just_assigned = _scout_unit != null

	# Send to the next point when freshly assigned (redirect whatever command the
	# unit had) or when idle after reaching the last waypoint. Optimistically stamp
	# the target as visited so _next_scout_point() never re-selects the same cell
	# if the LOS raycast is blocked right at the unit's feet.
	if _scout_unit != null and (just_assigned or not _scout_unit.has_command()):
		var next_idx: Variant = _next_scout_point()
		if next_idx != null:
			_scout_grid[next_idx] = now
			_act.move([_scout_unit], _scout_grid_positions[next_idx])


## True when the assigned scout's command is no longer a plain move — the
## military or another system has re-tasked it with something active.
func _scout_was_retasked() -> bool:
	if not _scout_unit.has_command():
		return false  # idle after reaching a waypoint, still ours
	var c: Command = _scout_unit.current_command()
	return c is Attack or c is AttackMove or c is Build or c is Repair \
		or c is Occupy or c is Capture or c is Land or c is Interact


## Among all owned units that are free to scout, return the fastest. Null when none.
func _pick_fastest_available() -> Variant:
	var best: Commandable = null
	var best_speed: float = -1.0
	for u: Commandable in _bot.get_units():
		if u.movement == null:
			continue
		# AOE-suicide drones are reserved for BotKamikaze (which alone commits them to a
		# blast run or holds them back) — never spend one wandering as a scout, mirroring
		# how BotMilitary / BotTargeting exclude them.
		if _bot.is_suicide_aoe_unit(u):
			continue
		if not _unit_is_available(u):
			continue
		if u.movement.speed > best_speed:
			best_speed = u.movement.speed
			best = u
	return best


## True when a unit is unoccupied and safe to draft as a scout.
func _unit_is_available(u: Commandable) -> bool:
	if not u.has_command():
		return true
	var c: Command = u.current_command()
	return not (c is Attack or c is AttackMove or c is Build or c is Repair \
		or c is Occupy or c is Capture or c is Land or c is Interact)


## The grid index of the expired/unscouted point closest (XZ) to the scout unit.
## Returns null when all points are fresh or no scout unit is assigned.
func _next_scout_point() -> Variant:
	if not is_instance_valid(_scout_unit):
		return null
	var expiry_threshold: float = _bot.seconds_elapsed() - SCOUT_EXPIRATION_TIMER
	var unit_xz: Vector2 = VU.inXZ(_scout_unit.global_position)
	var best_idx: Variant = null
	var best_dist_sq: float = INF
	for idx: Vector2i in _scout_grid:
		if _scout_grid[idx] >= expiry_threshold:
			continue
		var dist_sq: float = unit_xz.distance_squared_to(VU.inXZ(_scout_grid_positions[idx]))
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_idx = idx
	return best_idx
