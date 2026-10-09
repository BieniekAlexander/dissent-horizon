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
## Passability, and the clearance, obstacle-distance and region fields derived from it, live in
## a native TerrainCells (native/src/terrain_cells.h): one byte per cell, a bitmask of the
## reasons the cell is impassable (steep, building-occupied, blocked, submerged). A cell is
## passable iff its byte is 0, and clearing one reason leaves the cell impassable if any other
## still applies. This node keeps what the scene needs: the heightmap, the cells_changed signal,
## and which building claimed which cells.

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

## Per-cell passability and the fields derived from it (see the class comment).
var _cells: TerrainCells = TerrainCells.new()

## building -> Array[Vector2i] it occupies. Kept so a building can free exactly
## the cells it claimed on removal; this is ownership bookkeeping, not passability.
var _building_footprints: Dictionary = {}
#endregion


#region Lifecycle
func _ready() -> void:
	assert(height_map != null, "TerrainGrid: height_map must be set before adding to tree")
	assert(terrain_body != null, "TerrainGrid: terrain_body must be set before adding to tree")
	_cells.setup(grid_width(), grid_depth())  # all passable
	_cells.mark_steep(height_map.map_data, MAX_SLOPE_DIFF)


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
	return _cells.is_in_bounds(a_cell)


func is_building_at(a_cell: Vector2i) -> bool:
	return _cells.has_reason(a_cell, TerrainCells.BUILDING)


func is_too_steep(a_cell: Vector2i) -> bool:
	return _cells.has_reason(a_cell, TerrainCells.STEEP)


## True when the cell is marked impassable by the blocked mask (water, rubble,
## scripted no-go, …), independent of its terrain height.
func is_blocked(a_cell: Vector2i) -> bool:
	return _cells.has_reason(a_cell, TerrainCells.BLOCKED)


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
	return _cells.is_passable(a_cell)


## Returns all passable cells, x-major. The set NavManager uses to build the NavigationMesh.
func get_all_passable_cells() -> Array:
	return _cells.passable_cells()


## One byte per cell (index = z*grid_width()+x), 1 where the cell is impassable for a reason other
## than a building standing on it: steep, blocked or submerged. What the minimap draws as ground
## no unit can cross.
func terrain_impassable_mask() -> PackedByteArray:
	return _cells.reason_mask(TerrainCells.STEEP | TerrainCells.BLOCKED | TerrainCells.SUBMERGED)


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
	return _cells.preserves_connectivity(a_footprint)


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
## navmesh asks this of tens of thousands of cells. Both forms share one native rule, so the
## navmesh and Movement's string-pull cannot disagree; tests/test_StringPullNavigability.gd pins
## them together.
func navigable_mask(a_rect: Rect2i, a_rings: int, a_admit_k: int) -> PackedByteArray:
	assert(get_bounds_rect().encloses(a_rect), "TerrainGrid.navigable_mask: rect outside the grid")
	return _cells.navigable_mask(a_rect, a_rings, a_admit_k)


## Whether ONE cell survives the erosion for an agent class — passable, clear of the
## ring-erosion band, and inside an admit_k x admit_k passable block. NavManager bakes a mesh
## from the whole set, while Movement's string-pull asks the same question of the handful of
## cells under one line segment (see Movement._line_is_navigable).
func is_navigable_for(a_cell: Vector2i, a_rings: int, a_admit_k: int) -> bool:
	return _cells.is_navigable_for(a_cell, a_rings, a_admit_k)


## Whether every cell the straight segment `a_from` → `a_to` crosses is navigable for this
## class (is_navigable_for), with both ends in continuous grid coordinates
## (Map.world_to_grid_point). Walks exactly the crossed cells, once each (Amanatides–Woo), and
## stops at the first refusal. Where the segment passes exactly through a cell corner, both
## side cells are tested too, so a diagonal cannot slip between two blocked cells.
func is_segment_navigable_for(a_from: Vector2, a_to: Vector2, a_rings: int, a_admit_k: int) -> bool:
	return _cells.is_segment_navigable_for(a_from, a_to, a_rings, a_admit_k)


## Anchored largest-square clearance at a cell (side of the largest all-passable
## square with this cell as its top-left corner), saturating at TerrainCells.FIELD_CAP_CELLS.
func clearance_at(a_cell: Vector2i) -> int:
	return _cells.clearance_at(a_cell)


## Chebyshev distance in cells from a passable cell to the nearest obstacle /
## out-of-bounds cell (0 if the cell itself is impassable), saturating at
## TerrainCells.FIELD_CAP_CELLS.
func distance_to_obstacle(a_cell: Vector2i) -> int:
	return _cells.distance_to_obstacle(a_cell)


## Which 4-connected passable region `cell` belongs to, or -1 when it is impassable or
## out of bounds. Region ids are opaque and are renumbered on every cells_changed; they are
## only ever compared for equality, never stored across a rebuild.
##
## THIS IS WHAT MAKES A CONNECTIVITY QUESTION CHEAP: the labels are recomputed once per
## cells_changed, so asking which region a cell is in costs one array read. See NavPlacement.
func component_at(a_cell: Vector2i) -> int:
	return _cells.component_at(a_cell)


## How many cells share `a_component`, or 0 for an unknown id.
func component_size(a_component: int) -> int:
	return _cells.component_size(a_component)


## Number of 4-connected passable regions on the map right now.
func component_count() -> int:
	return _cells.component_count()


## The id of the biggest passable region, or -1 when nothing is passable. What a caller with
## no better reference point (a placement validator with no owner) means by "the navmesh".
func largest_component() -> int:
	return _cells.largest_component()


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
		_cells.set_reason(cell, TerrainCells.BUILDING, true)
	_cells.mark_changed(a_cells)
	cells_changed.emit(a_cells)


## Free all cells occupied by `building` and emit cells_changed.
## No-op if `building` was never registered.
func remove_building(a_building: Object) -> void:
	if not _building_footprints.has(a_building):
		return
	var freed: Array = _building_footprints[a_building]
	for cell: Vector2i in freed:
		_cells.set_reason(cell, TerrainCells.BUILDING, false)
	_building_footprints.erase(a_building)
	_cells.mark_changed(freed)
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
	_set_reason_mask(TerrainCells.BLOCKED, a_mask, "blocked")


## True when the cell is submerged past wading depth by a water body. Independent of
## is_blocked: a cell can be under a lake AND out of play, and clearing either leaves the
## other standing.
func is_submerged(a_cell: Vector2i) -> bool:
	return _cells.has_reason(a_cell, TerrainCells.SUBMERGED)


## Replace the whole submerged state from `mask` — same cell-indexed shape as the blocked
## mask. Published as a WHOLE by Map.refresh_water() because the grid sees the union over
## every water body, not one body at a time.
func set_submerged_mask(a_mask: PackedByteArray) -> void:
	_set_reason_mask(TerrainCells.SUBMERGED, a_mask, "submerged")


## Replace one impassability reason across the whole grid from a cell-indexed mask (index =
## z*grid_width()+x; non-zero sets the bit, an empty mask clears the reason everywhere).
## Only `a_reason` is touched — every other reason on the cell is preserved — and cells_changed
## carries exactly the cells whose bit flipped, so NavManager rebuilds no more than it must.
func _set_reason_mask(a_reason: int, a_mask: PackedByteArray, a_name: String) -> void:
	var cell_count: int = grid_width() * grid_depth()
	assert(
		a_mask.is_empty() or a_mask.size() == cell_count,
		(
			"TerrainGrid: %s mask must be empty or size grid_width*grid_depth (%d)"
			% [a_name, cell_count]
		)
	)
	var changed: Array = _cells.set_reason_mask(a_reason, a_mask)
	if not changed.is_empty():
		_cells.mark_changed(changed)
		cells_changed.emit(changed)


## Block or unblock a single cell.
func set_blocked(a_cell: Vector2i, a_value: bool) -> void:
	if not is_in_bounds(a_cell) or is_blocked(a_cell) == a_value:
		return
	_cells.set_reason(a_cell, TerrainCells.BLOCKED, a_value)
	_cells.mark_changed([a_cell])
	cells_changed.emit([a_cell])


## Remove all blocks.
func clear_blocked_mask() -> void:
	set_blocked_mask(PackedByteArray())
#endregion
