class_name TerrainGrid
extends Node

## Tracks the navigability state of every grid cell on the map.
##
## The HeightMapShape3D is the authoritative source for terrain extent.
## A HeightMapShape3D with map_width W and map_depth D defines a grid of
## (W-1) × (D-1) navigable cells — one quad per pair of adjacent corners.
## A cell is passable when it is in-bounds, unoccupied by a building, and
## its four corner heights span no more than MAX_SLOPE_DIFF.
##
## Cell (gx, gz) spans the four heightmap corners
## (gx, gz), (gx+1, gz), (gx+1, gz+1), (gx, gz+1).

## Maximum heightmap-unit spread across a cell's four corners before the cell
## is considered too steep to traverse.  Raw map_data units (multiply by
## terrain_body.scale.y to convert to world-space metres).
const MAX_SLOPE_DIFF: float = 0.5

## The heightmap resource that defines terrain extent and corner heights.
## Set by Map._ready() from Map.height_map.
var height_map: HeightMapShape3D

## StaticBody3D retained for NavManager's global_transform reference until the
## coordinate frame is fully migrated off the physics body.
@export var terrain_body: StaticBody3D

var _building_footprints: Dictionary = {}  # Object  -> Array[Vector2i]
var _building_cells:      Dictionary = {}  # Vector2i -> Object
var _steep_cells:         Dictionary = {}  # Vector2i -> true, precomputed at _ready()

signal cells_changed(cells: Array)


func _ready() -> void:
	assert(height_map  != null, "TerrainGrid: height_map must be set before adding to tree")
	assert(terrain_body != null, "TerrainGrid: terrain_body must be set before adding to tree")
	_compute_steep_cells()


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

func is_building_at(cell: Vector2i) -> bool:
	return _building_cells.has(cell)

func is_too_steep(cell: Vector2i) -> bool:
	return _steep_cells.has(cell)

## A cell is passable when it is within the heightmap extent, no building
## occupies it, and its corner-height spread does not exceed MAX_SLOPE_DIFF.
func is_passable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not is_building_at(cell) and not is_too_steep(cell)

## Returns all passable cells.  This is the set NavManager uses to build the NavigationMesh.
func get_all_passable_cells() -> Array:
	var result: Array = []
	for x in range(grid_width()):
		for z in range(grid_depth()):
			var cell := Vector2i(x, z)
			if is_passable(cell):
				result.append(cell)
	return result

## Precompute steep cells from the heightmap.  Called once at _ready() since
## the heightmap does not change at runtime.
func _compute_steep_cells() -> void:
	_steep_cells = {}
	var hs := height_map
	var w  := hs.map_width
	for z in range(grid_depth()):
		for x in range(grid_width()):
			var h00 := hs.map_data[ z      * w + x    ]
			var h10 := hs.map_data[ z      * w + x + 1]
			var h01 := hs.map_data[(z + 1) * w + x    ]
			var h11 := hs.map_data[(z + 1) * w + x + 1]
			var spread := maxf(maxf(h00, h10), maxf(h01, h11)) \
						- minf(minf(h00, h10), minf(h01, h11))
			if spread > MAX_SLOPE_DIFF:
				_steep_cells[Vector2i(x, z)] = true

## Returns [min: Vector2i, max: Vector2i] inclusive cell-index bounds.
func get_bounds() -> Array:
	return [Vector2i.ZERO, Vector2i(grid_width() - 1, grid_depth() - 1)]


# --- Runtime building management -------------------------------------------

## Mark `cells` as occupied by `building` and emit cells_changed.
func place_building(cells: Array, building: Object) -> void:
	_building_footprints[building] = cells
	for cell: Vector2i in cells:
		assert(
			not _building_cells.has(cell),
			"TerrainGrid: cell %s is already occupied by %s — cannot place %s" % [cell, _building_cells.get(cell), building]
		)
		_building_cells[cell] = building
	cells_changed.emit(cells)

## Free all cells occupied by `building` and emit cells_changed.
## No-op if `building` was never registered.
func remove_building(building: Object) -> void:
	if not _building_footprints.has(building):
		return
	var freed: Array = _building_footprints[building]
	for cell: Vector2i in freed:
		_building_cells.erase(cell)
	_building_footprints.erase(building)
	cells_changed.emit(freed)

## Returns the cells registered for `building`, or [] if unknown.
func get_building_cells(building: Object) -> Array:
	return _building_footprints.get(building, [])
