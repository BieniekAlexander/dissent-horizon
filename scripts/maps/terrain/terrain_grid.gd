class_name TerrainGrid
extends Node

## Tracks the navigability state of every grid cell on the map.
##
## The HeightMapShape3D is the authoritative source for terrain extent.
## A HeightMapShape3D with map_width W and map_depth D defines a grid of
## (W-1) × (D-1) navigable cells — one quad per pair of adjacent corners.
## Cell (gx, gz) spans the four heightmap corners
## (gx, gz), (gx+1, gz), (gx+1, gz+1), (gx, gz+1).
##
## Passability is held in ONE structure: `_cell_state`, a cell-indexed byte grid
## where each byte is a bitmask of the reasons the cell is impassable (steep,
## building-occupied, blocked, submerged). A cell is passable iff its byte is 0. Every source
## of impassability flips its own bit, so checking passability is a single byte
## read, and clearing one reason (removing a building, unblocking) leaves the cell
## impassable if any other reason still applies — no separate maps to keep in sync.

#region Constants
## The lowest the camera may look down on the ground, in degrees below the horizontal. A slope
## steeper than the camera's pitch is hidden when it faces away, and one equal to it is seen
## edge-on, so every walkable slope must be gentler than this from any yaw (Alex, 2026-10-02).
## The camera stays above it (test_ViewPitchFloor); the walkable limit derives from it.
const MIN_VIEW_PITCH_DEGREES: float = 30.0

## Maximum heightmap-unit spread across a cell's four corners before the cell is considered too
## steep to traverse. The spread bounds the steepest slope over the cell, so this keeps every
## walkable slope at or under MIN_VIEW_PITCH_DEGREES, per cell (Map.CELL_SIZE is 1). Raw map_data
## units (multiply by terrain_body.scale.y to convert to world-space metres).
const MAX_SLOPE_DIFF: float = tan(deg_to_rad(MIN_VIEW_PITCH_DEGREES))

## Impassability reasons OR-ed into each cell's `_cell_state` byte.
const _STEEP: int = 1 << 0  ## corner-height spread exceeds MAX_SLOPE_DIFF (static)
const _BUILDING: int = 1 << 1  ## a structure occupies the cell
const _BLOCKED: int = 1 << 2  ## non-height no-go: tile type, out of play, scripted
## Submerged past WaterBasin.WADE_DEPTH by some water body — the chasm a lake is.
##
## Its OWN bit rather than a second writer of _BLOCKED, for the same reason _STEEP is not
## _BLOCKED: the reasons are independent and are cleared independently. A water body's cells
## are republished as a whole whenever any body changes, and the tile-type/out-of-play mask
## must survive that untouched (and vice versa). A movement class that one day ignores water
## but not cliffs also needs to be able to tell them apart.
const _SUBMERGED: int = 1 << 3

## Where the distance and clearance fields saturate, in cells. Capping them is what lets a
## change be absorbed LOCALLY: a cell further than this from every changed cell cannot see its
## capped value move, so only the changed rectangle grown by the cap is recomputed. It must be
## at least the largest value any reader compares against — the erosion rings and corridor
## tiers (NavAgentClass, at most 3) and the bot's placement corridor cap (4); 8 leaves room for
## a wider class without a second look.
const FIELD_CAP_CELLS: int = 8
#endregion

#region Signals
signal cells_changed(cells: Array)
#endregion

#region Properties
## The heightmap resource that defines terrain extent and corner heights.
## Set by Map._ready() from Map.height_map.
var height_map: HeightMapShape3D

## StaticBody3D retained for NavManager's global_transform reference until the
## coordinate frame is fully migrated off the physics body.
@export var terrain_body: StaticBody3D

## The single source of truth for passability: one byte per cell (index =
## z*grid_width()+x), each byte a bitmask of impassability reasons. 0 == passable.
var _cell_state: PackedByteArray = PackedByteArray()

## building -> Array[Vector2i] it occupies. Kept so a building can free exactly
## the cells it claimed on removal; this is ownership bookkeeping, not passability.
var _building_footprints: Dictionary = {}

## Per-cell fields used to bake space-eroded per-size-class nav-meshes (see
## NavAgentClass / gdd/systems/terrain-and-navigation/agent-size-classes.md). Recomputed lazily, and
## only around what changed (see _ensure_fields); both saturate at FIELD_CAP_CELLS:
##   _clearance: anchored largest-square fit — side of the largest all-passable
##               square whose TOP-LEFT corner is this cell (the covering gate).
##   _dist:      Chebyshev distance, in cells, to the nearest impassable / out-of-
##               bounds cell (a passable cell touching an obstacle has dist 1).
##   _component: index of the 4-connected passable region the cell belongs to, or -1
##               for an impassable / out-of-bounds cell. This is the field that makes an
##               "does this placement wall anything off" question O(1) per cell instead of
##               a flood fill per candidate -- see NavPlacement.
var _clearance: PackedInt32Array = PackedInt32Array()
var _dist: PackedInt32Array = PackedInt32Array()
var _component: PackedInt32Array = PackedInt32Array()
## Cell count per component id, index-aligned with the ids in _component.
var _component_sizes: PackedInt32Array = PackedInt32Array()
## True when the fields must be rebuilt over the WHOLE grid (only before the first read);
## after that, a change widens _dirty_rect and only that is recomputed.
var _fields_dirty: bool = true
## Bounding box of every cell changed since the fields were last brought up to date. Only
## meaningful while _has_dirty_rect.
var _dirty_rect: Rect2i = Rect2i()
var _has_dirty_rect: bool = false
## The region labels get their OWN dirty flag rather than riding _fields_dirty, because the
## two have different customers. Clearance and distance are rebuilt for every navmesh bake;
## labels are only ever asked for by a placement check, which happens in bursts. Sharing one
## flag would make every bake pay for a relabel nothing was going to read.
var _components_dirty: bool = true
#endregion


#region Lifecycle
func _ready() -> void:
	assert(height_map != null, "TerrainGrid: height_map must be set before adding to tree")
	assert(terrain_body != null, "TerrainGrid: terrain_body must be set before adding to tree")
	_cell_state.resize(grid_width() * grid_depth())  # zero-initialised → all passable
	_mark_steep_cells()


#endregion


#region Shape accessors
func height_shape() -> HeightMapShape3D:
	return height_map


## Total number of height-sample columns (X direction).
func map_width() -> int:
	return height_shape().map_width


## Total number of height-sample rows (Z direction).
func map_depth() -> int:
	return height_shape().map_depth


## Number of navigable cell columns  (= map_width  - 1).
func grid_width() -> int:
	return map_width() - 1


## Number of navigable cell rows (= map_depth - 1).
func grid_depth() -> int:
	return map_depth() - 1


## Height (Y in terrain-body local space) at corner (cx, cz).
func get_corner_height(a_cx: int, a_cz: int) -> float:
	return height_shape().map_data[a_cz * map_width() + a_cx]


#endregion


#region Cell queries
func is_in_bounds(a_cell: Vector2i) -> bool:
	return a_cell.x >= 0 and a_cell.x < grid_width() and a_cell.y >= 0 and a_cell.y < grid_depth()


## Flat index into _cell_state for an in-bounds cell.
func _index(a_cell: Vector2i) -> int:
	return a_cell.y * grid_width() + a_cell.x


func is_building_at(a_cell: Vector2i) -> bool:
	return is_in_bounds(a_cell) and (_cell_state[_index(a_cell)] & _BUILDING) != 0


func is_too_steep(a_cell: Vector2i) -> bool:
	return is_in_bounds(a_cell) and (_cell_state[_index(a_cell)] & _STEEP) != 0


## True when the cell is marked impassable by the blocked mask (water, rubble,
## scripted no-go, …), independent of its terrain height.
func is_blocked(a_cell: Vector2i) -> bool:
	return is_in_bounds(a_cell) and (_cell_state[_index(a_cell)] & _BLOCKED) != 0


## True iff all four corner heights of the cell are identical (zero spread).
## Used by structure placement to enforce that buildings may only be placed on
## perfectly flat ground — stricter than is_too_steep, which allows a small slope.
func is_flat(a_cell: Vector2i) -> bool:
	if not is_in_bounds(a_cell):
		return false
	var w := height_map.map_width
	var h00 := height_map.map_data[a_cell.y * w + a_cell.x]
	var h10 := height_map.map_data[a_cell.y * w + a_cell.x + 1]
	var h01 := height_map.map_data[(a_cell.y + 1) * w + a_cell.x]
	var h11 := height_map.map_data[(a_cell.y + 1) * w + a_cell.x + 1]
	return h00 == h10 and h10 == h01 and h01 == h11


## A cell is passable iff it is in-bounds and no impassability reason is set.
func is_passable(a_cell: Vector2i) -> bool:
	return is_in_bounds(a_cell) and _cell_state[_index(a_cell)] == 0


## Returns all passable cells.  This is the set NavManager uses to build the NavigationMesh.
func get_all_passable_cells() -> Array:
	var result: Array = []
	for x in range(grid_width()):
		for z in range(grid_depth()):
			var cell := Vector2i(x, z)
			if is_passable(cell):
				result.append(cell)
	return result


## Returns [min: Vector2i, max: Vector2i] inclusive cell-index bounds.
func get_bounds() -> Array:
	return [Vector2i.ZERO, Vector2i(grid_width() - 1, grid_depth() - 1)]


## True iff occupying `footprint` (an Array of cells) does NOT split the passable
## surface into MORE pieces than it's already in — i.e. it doesn't wall off a region
## and strand units (e.g. a builder ending up in a pocket it can't leave). Compares
## the connected-component count of the passable cells before vs. after the
## hypothetical placement (4-neighbour, matching how the navmesh stitches adjacent
## cells); safe iff the count doesn't increase. The before/after comparison (rather
## than "is it all one component") tolerates maps that are already fragmented by
## terrain — it only forbids the placement from adding a new split.
func placement_preserves_connectivity(a_footprint: Array) -> bool:
	var blocked: Dictionary = {}
	for c: Vector2i in a_footprint:
		blocked[c] = true
	return _passable_component_count(blocked) <= _passable_component_count({})


## Number of 4-connected components among passable cells, excluding any cell in
## `extra_blocked` (a Set: Vector2i -> true) as if it were occupied.
func _passable_component_count(a_extra_blocked: Dictionary) -> int:
	var cells: Dictionary = {}
	for c: Vector2i in get_all_passable_cells():
		if not a_extra_blocked.has(c):
			cells[c] = true
	var neighbours: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var seen: Dictionary = {}
	var count: int = 0
	for start: Vector2i in cells:
		if seen.has(start):
			continue
		count += 1
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			for d: Vector2i in neighbours:
				var nb: Vector2i = cell + d
				if cells.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
	return count


#endregion


#region Space-erosion fields
## Cells navigable by an agent of a given size class, expressed as the two
## space-erosion parameters NavAgentClass derives from its radius:
##   rings   — whole-cell layers to strip around obstacles (keeps big units off
##             obstacles; pass 0 for no ring erosion).
##   admit_k — minimum corridor width in cells (drops passages too narrow to fit).
## A cell is included iff it is passable, sits MORE than `rings` cells from the
## nearest obstacle/out-of-bounds, AND can be covered by an admit_k x admit_k block
## of passable cells. Returned as a Set (Vector2i -> true) so NavManager can test
## membership of neighbouring cells cheaply while insetting boundary vertices.
func get_navigable_cells(a_rings: int, a_admit_k: int) -> Dictionary:
	var gw: int = grid_width()
	var mask: PackedByteArray = navigable_mask(get_bounds_rect(), a_rings, a_admit_k)
	var result: Dictionary = {}
	for idx: int in mask.size():
		if mask[idx] != 0:
			result[Vector2i(idx % gw, idx / gw)] = true
	return result


## The whole grid as a cell rectangle.
func get_bounds_rect() -> Rect2i:
	return Rect2i(0, 0, grid_width(), grid_depth())


## is_navigable_for over every cell of `a_rect` at once: one byte per cell, row-major over
## the rect, non-zero where the cell survives the erosion. The bulk form exists because the
## navmesh asks this of tens of thousands of cells and a call per cell was most of what a
## rebuild cost. It must select EXACTLY what is_navigable_for selects — Movement's string-pull
## asks the single-cell form, and the two drifting apart would steer units through ground their
## navmesh excluded; tests/test_StringPullNavigability.gd pins them together.
func navigable_mask(a_rect: Rect2i, a_rings: int, a_admit_k: int) -> PackedByteArray:
	assert(get_bounds_rect().encloses(a_rect), "TerrainGrid.navigable_mask: rect outside the grid")
	_ensure_fields()
	var gw: int = grid_width()
	var gh: int = grid_depth()
	var mask := PackedByteArray()
	mask.resize(a_rect.size.x * a_rect.size.y)
	var out: int = 0
	# Hot loop: one pass per chunk rebuild over every cell in it, so the rule is inlined over the
	# packed fields rather than calling is_navigable_for.
	for z: int in range(a_rect.position.y, a_rect.end.y):
		for x: int in range(a_rect.position.x, a_rect.end.x):
			var idx: int = z * gw + x
			var ok: bool = _cell_state[idx] == 0 and (a_rings <= 0 or _dist[idx] > a_rings)
			if ok and a_admit_k > 1:
				ok = false
				for az: int in range(maxi(0, z - a_admit_k + 1), mini(z + 1, gh - a_admit_k + 1)):
					for ax: int in range(
						maxi(0, x - a_admit_k + 1), mini(x + 1, gw - a_admit_k + 1)
					):
						if _clearance[az * gw + ax] >= a_admit_k:
							ok = true
							break
					if ok:
						break
			mask[out] = 1 if ok else 0
			out += 1
	return mask


## Whether ONE cell survives the erosion for an agent class — passable, clear of the
## ring-erosion band, and inside an admit_k x admit_k passable block.
##
## Split out of get_navigable_cells so the rule has exactly one definition: NavManager bakes a
## mesh from the whole set, while Movement's string-pull asks the same question of the handful
## of cells under one line segment (see Movement._line_is_navigable). Those two must agree, or
## a unit steers straight through ground its own navmesh excluded.
func is_navigable_for(a_cell: Vector2i, a_rings: int, a_admit_k: int) -> bool:
	if not is_in_bounds(a_cell):
		return false
	_ensure_fields()
	if _cell_state[_index(a_cell)] != 0:
		return false  # impassable
	if a_rings > 0 and _dist[_index(a_cell)] <= a_rings:
		return false  # stripped by ring-erosion
	if a_admit_k > 1 and not _coverable(a_cell, a_admit_k):
		return false  # no admit_k block fits here
	return true


## Whether every cell the straight segment `a_from` → `a_to` crosses is navigable for this
## class (is_navigable_for), with both ends in continuous grid coordinates
## (Map.world_to_grid_point). Walks exactly the crossed cells, once each (Amanatides–Woo), and
## stops at the first refusal. Where the segment passes exactly through a cell corner, both
## side cells are tested too, so a diagonal cannot slip between two blocked cells.
## Hot loop: the path-straightening line test for every moving unit.
func is_segment_navigable_for(a_from: Vector2, a_to: Vector2, a_rings: int, a_admit_k: int) -> bool:
	var cell := Vector2i(floori(a_from.x), floori(a_from.y))
	var end := Vector2i(floori(a_to.x), floori(a_to.y))
	var delta: Vector2 = a_to - a_from
	var step := Vector2i(1 if delta.x > 0.0 else -1, 1 if delta.y > 0.0 else -1)
	# Parameter t along the segment (0..1) at which it next crosses a vertical / horizontal
	# cell boundary, and how much t one whole cell advances. INF on an axis it does not move on.
	var t_next := Vector2(INF, INF)
	var t_cell := Vector2(INF, INF)
	if delta.x != 0.0:
		t_next.x = (float(cell.x + (1 if step.x > 0 else 0)) - a_from.x) / delta.x
		t_cell.x = absf(1.0 / delta.x)
	if delta.y != 0.0:
		t_next.y = (float(cell.y + (1 if step.y > 0 else 0)) - a_from.y) / delta.y
		t_cell.y = absf(1.0 / delta.y)
	# Every crossing moves one axis one cell, so the walk is at most this long; the bound also
	# ends it if float error ever carried it past `end`.
	var crossings: int = absi(end.x - cell.x) + absi(end.y - cell.y)
	for i: int in crossings + 1:
		if not is_navigable_for(cell, a_rings, a_admit_k):
			return false
		if cell == end:
			return true
		if is_equal_approx(t_next.x, t_next.y):
			if (
				not is_navigable_for(cell + Vector2i(step.x, 0), a_rings, a_admit_k)
				or not is_navigable_for(cell + Vector2i(0, step.y), a_rings, a_admit_k)
			):
				return false
			cell += step
			t_next += t_cell
		elif t_next.x < t_next.y:
			cell.x += step.x
			t_next.x += t_cell.x
		else:
			cell.y += step.y
			t_next.y += t_cell.y
	# Only reachable if float error walked the line off `end`: refuse, which only costs the
	# caller a straighter path, never a unit steered through something.
	return false


## Anchored largest-square clearance at a cell (side of the largest all-passable
## square with this cell as its top-left corner), saturating at FIELD_CAP_CELLS.
func clearance_at(a_cell: Vector2i) -> int:
	if not is_in_bounds(a_cell):
		return 0
	_ensure_fields()
	return _clearance[_index(a_cell)]


## Chebyshev distance in cells from a passable cell to the nearest obstacle /
## out-of-bounds cell (0 if the cell itself is impassable), saturating at FIELD_CAP_CELLS.
func distance_to_obstacle(a_cell: Vector2i) -> int:
	if not is_in_bounds(a_cell):
		return 0
	_ensure_fields()
	return _dist[_index(a_cell)]


## True iff some admit_k x admit_k block of in-bounds passable cells contains `cell`.
## Such a block exists iff one of the candidate top-left anchors in the k x k window
## ending at `cell` has anchored clearance >= admit_k.
func _coverable(a_cell: Vector2i, a_admit_k: int) -> bool:
	var gw: int = grid_width()
	var gh: int = grid_depth()
	for az: int in range(maxi(0, a_cell.y - a_admit_k + 1), a_cell.y + 1):
		if az + a_admit_k > gh:
			continue
		for ax: int in range(maxi(0, a_cell.x - a_admit_k + 1), a_cell.x + 1):
			if ax + a_admit_k > gw:
				continue
			if _clearance[az * gw + ax] >= a_admit_k:
				return true
	return false


## Bring _clearance and _dist up to date: the whole grid before the first read, afterwards only
## the changed rectangle grown by FIELD_CAP_CELLS — nothing further out can see its capped
## value move.
func _ensure_fields() -> void:
	var area: Rect2i
	if _fields_dirty:
		area = get_bounds_rect()
		_clearance.resize(grid_width() * grid_depth())
		_dist.resize(grid_width() * grid_depth())
	elif _has_dirty_rect:
		area = _dirty_rect.grow(FIELD_CAP_CELLS).intersection(get_bounds_rect())
	else:
		return
	_fields_dirty = false
	_has_dirty_rect = false
	_recompute_clearance(area)
	_recompute_distance(area)


## Record that `a_cells` changed state: the fields are stale around them, the labels everywhere.
func _mark_changed(a_cells: Array) -> void:
	_components_dirty = true
	if a_cells.is_empty():
		return
	var lo: Vector2i = a_cells[0]
	var hi: Vector2i = a_cells[0]
	for cell: Vector2i in a_cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	var changed := Rect2i(lo, hi - lo + Vector2i.ONE)
	_dirty_rect = _dirty_rect.merge(changed) if _has_dirty_rect else changed
	_has_dirty_rect = true


## Recompute the region labels if a cell changed since they were last built.
func _ensure_components() -> void:
	if not _components_dirty:
		return
	_components_dirty = false
	_recompute_components()


## Anchored largest-square clearance (top-left corner), capped at FIELD_CAP_CELLS, over
## `a_area`. Standard bottom-up DP: clearance(c) = 0 if impassable, else
## 1 + min(right, down, down-right). Neighbours outside `a_area` are read as already stored,
## which is exact because the caller grew the area past everything the change can reach.
func _recompute_clearance(a_area: Rect2i) -> void:
	var gw: int = grid_width()
	var gh: int = grid_depth()
	for z: int in range(a_area.end.y - 1, a_area.position.y - 1, -1):
		for x: int in range(a_area.end.x - 1, a_area.position.x - 1, -1):
			var idx: int = z * gw + x
			if _cell_state[idx] != 0:
				_clearance[idx] = 0
				continue
			var right: int = _clearance[idx + 1] if x + 1 < gw else 0
			var down: int = _clearance[idx + gw] if z + 1 < gh else 0
			var diag: int = _clearance[(z + 1) * gw + (x + 1)] if (x + 1 < gw and z + 1 < gh) else 0
			_clearance[idx] = mini(FIELD_CAP_CELLS, 1 + mini(right, mini(down, diag)))


## Which 4-connected passable region `cell` belongs to, or -1 when it is impassable or
## out of bounds. Region ids are opaque and are renumbered on every cells_changed; they are
## only ever compared for equality, never stored across a rebuild.
##
## THIS IS WHAT MAKES A CONNECTIVITY QUESTION CHEAP. `placement_preserves_connectivity` used
## to flood-fill the whole passable set TWICE per candidate cell (measured at 67-133 ms, one
## of only 13 ticks in 29,432 that blew the 33 ms budget). The labels are recomputed once per
## cells_changed alongside the clearance and distance fields the navmesh already pays for, so
## asking which region a cell is in costs one array read. See NavPlacement.
func component_at(a_cell: Vector2i) -> int:
	if not is_in_bounds(a_cell):
		return -1
	_ensure_components()
	return _component[_index(a_cell)]


## How many cells share `a_component`, or 0 for an unknown id.
func component_size(a_component: int) -> int:
	_ensure_components()
	if a_component < 0 or a_component >= _component_sizes.size():
		return 0
	return _component_sizes[a_component]


## Number of 4-connected passable regions on the map right now.
func component_count() -> int:
	_ensure_components()
	return _component_sizes.size()


## The id of the biggest passable region, or -1 when nothing is passable. What a caller with
## no better reference point (a placement validator with no owner) means by "the navmesh".
func largest_component() -> int:
	_ensure_components()
	var best: int = -1
	var best_size: int = 0
	for i: int in _component_sizes.size():
		if _component_sizes[i] > best_size:
			best_size = _component_sizes[i]
			best = i
	return best


## Label every passable cell with the id of its 4-connected region. 4-neighbour, matching how
## the navmesh stitches adjacent cells and how _passable_component_count counted.
func _recompute_components() -> void:
	var gw: int = grid_width()
	var gh: int = grid_depth()
	_component.resize(gw * gh)
	_component_sizes = PackedInt32Array()
	for i: int in gw * gh:
		_component[i] = -1 if _cell_state[i] != 0 else -2  # -2 == passable, not yet labelled
	var queue: PackedInt32Array = PackedInt32Array()
	for start: int in gw * gh:
		if _component[start] != -2:
			continue
		var id: int = _component_sizes.size()
		_component_sizes.append(0)
		var size: int = 0
		queue.clear()
		queue.append(start)
		_component[start] = id
		var head: int = 0
		while head < queue.size():
			var idx: int = queue[head]
			head += 1
			size += 1
			var x: int = idx % gw
			if x > 0 and _component[idx - 1] == -2:
				_component[idx - 1] = id
				queue.append(idx - 1)
			if x + 1 < gw and _component[idx + 1] == -2:
				_component[idx + 1] = id
				queue.append(idx + 1)
			if idx - gw >= 0 and _component[idx - gw] == -2:
				_component[idx - gw] = id
				queue.append(idx - gw)
			if idx + gw < gw * gh and _component[idx + gw] == -2:
				_component[idx + gw] = id
				queue.append(idx + gw)
		_component_sizes[id] = size


## Chebyshev distance transform to the nearest impassable / out-of-bounds cell, capped at
## FIELD_CAP_CELLS, over `a_area`. Two passes (forward then backward); out-of-bounds
## neighbours count as obstacles (distance 0), so map-edge cells erode like building-edge
## cells. A neighbour outside `a_area` but on the grid is read as already stored: the true
## distance of a cell inside is either to an obstacle inside, or through some cell on the
## area's rim, whose stored value the change could not have moved.
func _recompute_distance(a_area: Rect2i) -> void:
	var gw: int = grid_width()
	var gh: int = grid_depth()
	for z: int in range(a_area.position.y, a_area.end.y):
		for x: int in range(a_area.position.x, a_area.end.x):
			var idx: int = z * gw + x
			if _cell_state[idx] != 0:
				_dist[idx] = 0
			else:
				_dist[idx] = FIELD_CAP_CELLS
	# Forward pass: up, left, and the two upper diagonals (+1 each).
	for z: int in range(a_area.position.y, a_area.end.y):
		for x: int in range(a_area.position.x, a_area.end.x):
			var idx: int = z * gw + x
			if _dist[idx] == 0:
				continue
			var best: int = _dist[idx]
			best = mini(best, (_dist[idx - 1] if x > 0 else 0) + 1)
			best = mini(best, (_dist[idx - gw] if z > 0 else 0) + 1)
			best = mini(best, (_dist[idx - gw - 1] if (x > 0 and z > 0) else 0) + 1)
			best = mini(best, (_dist[idx - gw + 1] if (x + 1 < gw and z > 0) else 0) + 1)
			_dist[idx] = best
	# Backward pass: down, right, and the two lower diagonals.
	for z: int in range(a_area.end.y - 1, a_area.position.y - 1, -1):
		for x: int in range(a_area.end.x - 1, a_area.position.x - 1, -1):
			var idx: int = z * gw + x
			if _dist[idx] == 0:
				continue
			var best: int = _dist[idx]
			best = mini(best, (_dist[idx + 1] if x + 1 < gw else 0) + 1)
			best = mini(best, (_dist[idx + gw] if z + 1 < gh else 0) + 1)
			best = mini(best, (_dist[idx + gw + 1] if (x + 1 < gw and z + 1 < gh) else 0) + 1)
			best = mini(best, (_dist[idx + gw - 1] if (x > 0 and z + 1 < gh) else 0) + 1)
			_dist[idx] = best


#endregion


#region Building management
## Mark `cells` as occupied by `building` and emit cells_changed.
func place_building(a_cells: Array, a_building: Object) -> void:
	_building_footprints[a_building] = a_cells
	for cell: Vector2i in a_cells:
		assert(
			not is_building_at(cell),
			"TerrainGrid: cell %s is already occupied — cannot place %s" % [cell, a_building]
		)
		_cell_state[_index(cell)] |= _BUILDING
	_mark_changed(a_cells)
	cells_changed.emit(a_cells)


## Free all cells occupied by `building` and emit cells_changed.
## No-op if `building` was never registered.
func remove_building(a_building: Object) -> void:
	if not _building_footprints.has(a_building):
		return
	var freed: Array = _building_footprints[a_building]
	for cell: Vector2i in freed:
		_cell_state[_index(cell)] &= ~_BUILDING
	_building_footprints.erase(a_building)
	_mark_changed(freed)
	cells_changed.emit(freed)


## Returns the cells registered for `building`, or [] if unknown.
func get_building_cells(a_building: Object) -> Array:
	return _building_footprints.get(a_building, [])


## Every building registered on the grid.
func buildings() -> Array:
	return _building_footprints.keys()


#endregion


#region Blocked mask
## Replace the whole blocked state from `mask` (cell-indexed, index = z*grid_width()+x;
## a non-zero entry blocks the cell). Pass an empty array to clear all blocks. Only
## the BLOCKED bit is touched (steep/building reasons are preserved). Emits
## cells_changed for every cell whose passability flipped, so NavManager rebuilds.
func set_blocked_mask(a_mask: PackedByteArray) -> void:
	_set_reason_mask(_BLOCKED, a_mask, "blocked")


## True when the cell is submerged past wading depth by a water body. Independent of
## is_blocked: a cell can be under a lake AND out of play, and clearing either leaves the
## other standing.
func is_submerged(a_cell: Vector2i) -> bool:
	return is_in_bounds(a_cell) and (_cell_state[_index(a_cell)] & _SUBMERGED) != 0


## Replace the whole submerged state from `mask` — same cell-indexed shape as the blocked
## mask. Published as a WHOLE by Map.refresh_water() because the grid sees the union over
## every water body, not one body at a time.
func set_submerged_mask(a_mask: PackedByteArray) -> void:
	_set_reason_mask(_SUBMERGED, a_mask, "submerged")


## Replace one impassability reason across the whole grid from a cell-indexed mask (index =
## z*grid_width()+x; non-zero sets the bit, an empty mask clears the reason everywhere).
## Only `a_bit` is touched — every other reason on the cell is preserved — and cells_changed
## carries exactly the cells whose bit flipped, so NavManager rebuilds no more than it must.
func _set_reason_mask(a_bit: int, a_mask: PackedByteArray, a_name: String) -> void:
	var gw: int = grid_width()
	var gh: int = grid_depth()
	assert(
		a_mask.is_empty() or a_mask.size() == gw * gh,
		"TerrainGrid: %s mask must be empty or size grid_width*grid_depth (%d)" % [a_name, gw * gh]
	)

	var changed: Array = []
	for z: int in gh:
		for x: int in gw:
			var idx: int = z * gw + x
			var was: bool = (_cell_state[idx] & a_bit) != 0
			var now: bool = not a_mask.is_empty() and a_mask[idx] != 0
			if was != now:
				_cell_state[idx] = (
					(_cell_state[idx] | a_bit) if now else (_cell_state[idx] & ~a_bit)
				)
				changed.append(Vector2i(x, z))

	if not changed.is_empty():
		_mark_changed(changed)
		cells_changed.emit(changed)


## Block or unblock a single cell.
func set_blocked(a_cell: Vector2i, a_value: bool) -> void:
	if not is_in_bounds(a_cell):
		return
	var idx: int = _index(a_cell)
	if ((_cell_state[idx] & _BLOCKED) != 0) == a_value:
		return
	_cell_state[idx] = (_cell_state[idx] | _BLOCKED) if a_value else (_cell_state[idx] & ~_BLOCKED)
	_mark_changed([a_cell])
	cells_changed.emit([a_cell])


## Remove all blocks.
func clear_blocked_mask() -> void:
	set_blocked_mask(PackedByteArray())


#endregion


#region Private helpers
## Set the STEEP bit on cells whose corner-height spread exceeds MAX_SLOPE_DIFF.
## Called once at _ready() since the heightmap does not change at runtime.
func _mark_steep_cells() -> void:
	var hs := height_map
	var w := hs.map_width
	var gw := grid_width()
	for z in range(grid_depth()):
		for x in range(gw):
			var h00 := hs.map_data[z * w + x]
			var h10 := hs.map_data[z * w + x + 1]
			var h01 := hs.map_data[(z + 1) * w + x]
			var h11 := hs.map_data[(z + 1) * w + x + 1]
			var spread := (
				maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))
			)
			if spread > MAX_SLOPE_DIFF:
				_cell_state[z * gw + x] |= _STEEP
#endregion
