class_name TerrainGrid
extends Node

## Tracks the navigability state of every grid cell on the map.
##
## The HeightMapShape3D is the authoritative source for terrain extent.
## A HeightMapShape3D with map_width W and map_depth D defines a grid of
## (W-1) × (D-1) navigable cells — one quad per pair of adjacent corners.
## All cells within that extent are passable by default; buildings are the
## only runtime source of blockage.
##
## Cell (gx, gz) spans the four heightmap corners
## (gx, gz), (gx+1, gz), (gx+1, gz+1), (gx, gz+1).

## The heightmap resource that defines terrain extent and corner heights.
## Set by Map._ready() from Map.height_map.
var height_map: HeightMapShape3D

## StaticBody3D retained for NavManager's global_transform reference until the
## coordinate frame is fully migrated off the physics body.
@export var terrain_body: StaticBody3D

var _building_footprints: Dictionary = {}  # Object  -> Array[Vector2i]
var _building_cells:      Dictionary = {}  # Vector2i -> Object

signal cells_changed(cells: Array)


func _ready() -> void:
	assert(height_map  != null, "TerrainGrid: height_map must be set before adding to tree")
	assert(terrain_body != null, "TerrainGrid: terrain_body must be set before adding to tree")


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

## A cell is passable when it is within the heightmap extent and no building
## occupies it.
func is_passable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not is_building_at(cell)

## Returns all cells that are not blocked by a building.
## This is the set NavManager uses to construct the NavigationMesh.
func get_all_passable_cells() -> Array:
	var result: Array = []
	for x in range(grid_width()):
		for z in range(grid_depth()):
			var cell := Vector2i(x, z)
			if not is_building_at(cell):
				result.append(cell)
	return result

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
