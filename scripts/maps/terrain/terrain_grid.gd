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
## building-occupied, blocked). A cell is passable iff its byte is 0. Every source
## of impassability flips its own bit, so checking passability is a single byte
## read, and clearing one reason (removing a building, unblocking) leaves the cell
## impassable if any other reason still applies — no separate maps to keep in sync.

## Maximum heightmap-unit spread across a cell's four corners before the cell
## is considered too steep to traverse.  Raw map_data units (multiply by
## terrain_body.scale.y to convert to world-space metres).
const MAX_SLOPE_DIFF: float = 0.5

## Impassability reasons OR-ed into each cell's `_cell_state` byte.
const _STEEP: int = 1 << 0      ## corner-height spread exceeds MAX_SLOPE_DIFF (static)
const _BUILDING: int = 1 << 1   ## a structure occupies the cell
const _BLOCKED: int = 1 << 2    ## non-height no-go: water, rubble, hazard, scripted

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

signal cells_changed(cells: Array)


func _ready() -> void:
	assert(height_map  != null, "TerrainGrid: height_map must be set before adding to tree")
	assert(terrain_body != null, "TerrainGrid: terrain_body must be set before adding to tree")
	_cell_state.resize(grid_width() * grid_depth())  # zero-initialised → all passable
	_mark_steep_cells()


# --- Shape accessors -------------------------------------------------------

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
func get_corner_height(cx: int, cz: int) -> float:
	return height_shape().map_data[cz * map_width() + cx]


# --- Cell queries ----------------------------------------------------------

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width() \
		and cell.y >= 0 and cell.y < grid_depth()

## Flat index into _cell_state for an in-bounds cell.
func _index(cell: Vector2i) -> int:
	return cell.y * grid_width() + cell.x

func is_building_at(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and (_cell_state[_index(cell)] & _BUILDING) != 0

func is_too_steep(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and (_cell_state[_index(cell)] & _STEEP) != 0

## True when the cell is marked impassable by the blocked mask (water, rubble,
## scripted no-go, …), independent of its terrain height.
func is_blocked(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and (_cell_state[_index(cell)] & _BLOCKED) != 0

## True iff all four corner heights of the cell are identical (zero spread).
## Used by structure placement to enforce that buildings may only be placed on
## perfectly flat ground — stricter than is_too_steep, which allows a small slope.
func is_flat(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var w := height_map.map_width
	var h00 := height_map.map_data[ cell.y      * w + cell.x    ]
	var h10 := height_map.map_data[ cell.y      * w + cell.x + 1]
	var h01 := height_map.map_data[(cell.y + 1) * w + cell.x    ]
	var h11 := height_map.map_data[(cell.y + 1) * w + cell.x + 1]
	return h00 == h10 and h10 == h01 and h01 == h11

## A cell is passable iff it is in-bounds and no impassability reason is set.
func is_passable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and _cell_state[_index(cell)] == 0

## Returns all passable cells.  This is the set NavManager uses to build the NavigationMesh.
func get_all_passable_cells() -> Array:
	var result: Array = []
	for x in range(grid_width()):
		for z in range(grid_depth()):
			var cell := Vector2i(x, z)
			if is_passable(cell):
				result.append(cell)
	return result

## Set the STEEP bit on cells whose corner-height spread exceeds MAX_SLOPE_DIFF.
## Called once at _ready() since the heightmap does not change at runtime.
func _mark_steep_cells() -> void:
	var hs := height_map
	var w  := hs.map_width
	var gw := grid_width()
	for z in range(grid_depth()):
		for x in range(gw):
			var h00 := hs.map_data[ z      * w + x    ]
			var h10 := hs.map_data[ z      * w + x + 1]
			var h01 := hs.map_data[(z + 1) * w + x    ]
			var h11 := hs.map_data[(z + 1) * w + x + 1]
			var spread := maxf(maxf(h00, h10), maxf(h01, h11)) \
						- minf(minf(h00, h10), minf(h01, h11))
			if spread > MAX_SLOPE_DIFF:
				_cell_state[z * gw + x] |= _STEEP

## Returns [min: Vector2i, max: Vector2i] inclusive cell-index bounds.
func get_bounds() -> Array:
	return [Vector2i.ZERO, Vector2i(grid_width() - 1, grid_depth() - 1)]


# --- Runtime building management -------------------------------------------

## Mark `cells` as occupied by `building` and emit cells_changed.
func place_building(cells: Array, building: Object) -> void:
	_building_footprints[building] = cells
	for cell: Vector2i in cells:
		assert(
			not is_building_at(cell),
			"TerrainGrid: cell %s is already occupied — cannot place %s" % [cell, building]
		)
		_cell_state[_index(cell)] |= _BUILDING
	cells_changed.emit(cells)

## Free all cells occupied by `building` and emit cells_changed.
## No-op if `building` was never registered.
func remove_building(building: Object) -> void:
	if not _building_footprints.has(building):
		return
	var freed: Array = _building_footprints[building]
	for cell: Vector2i in freed:
		_cell_state[_index(cell)] &= ~_BUILDING
	_building_footprints.erase(building)
	cells_changed.emit(freed)

## Returns the cells registered for `building`, or [] if unknown.
func get_building_cells(building: Object) -> Array:
	return _building_footprints.get(building, [])


# --- Blocked mask (non-height impassability) -------------------------------

## Replace the whole blocked state from `mask` (cell-indexed, index = z*grid_width()+x;
## a non-zero entry blocks the cell). Pass an empty array to clear all blocks. Only
## the BLOCKED bit is touched (steep/building reasons are preserved). Emits
## cells_changed for every cell whose passability flipped, so NavManager rebuilds.
func set_blocked_mask(mask: PackedByteArray) -> void:
	var gw: int = grid_width()
	var gh: int = grid_depth()
	assert(mask.is_empty() or mask.size() == gw * gh,
		"TerrainGrid: blocked mask must be empty or size grid_width*grid_depth (%d)" % (gw * gh))

	var changed: Array = []
	for z: int in gh:
		for x: int in gw:
			var idx: int = z * gw + x
			var was: bool = (_cell_state[idx] & _BLOCKED) != 0
			var now: bool = not mask.is_empty() and mask[idx] != 0
			if was != now:
				_cell_state[idx] = (_cell_state[idx] | _BLOCKED) if now else (_cell_state[idx] & ~_BLOCKED)
				changed.append(Vector2i(x, z))

	if not changed.is_empty():
		cells_changed.emit(changed)

## Block or unblock a single cell.
func set_blocked(cell: Vector2i, value: bool) -> void:
	if not is_in_bounds(cell):
		return
	var idx: int = _index(cell)
	if ((_cell_state[idx] & _BLOCKED) != 0) == value:
		return
	_cell_state[idx] = (_cell_state[idx] | _BLOCKED) if value else (_cell_state[idx] & ~_BLOCKED)
	cells_changed.emit([cell])

## Remove all blocks.
func clear_blocked_mask() -> void:
	set_blocked_mask(PackedByteArray())
