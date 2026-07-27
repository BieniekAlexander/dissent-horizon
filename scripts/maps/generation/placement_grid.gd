@tool
class_name PlacementGrid
extends RefCounted

## Which cells the generator may still put something on. A cell is free when it is in play and
## nothing has reserved it. Reservations are what keep features apart, so a feature reserves
## its footprint DILATED by the gap it wants kept around it.
##
## Mutable by design: placement is sequential, each feature narrowing where the next may go,
## and recomputing occupancy from the feature list per candidate would multiply the pass's
## cost by the feature count.

#region Properties
var width: int = 0
var depth: int = 0
## Per cell: 1 when unavailable (out of play or reserved). Index z * width + x.
var _blocked: PackedByteArray = PackedByteArray()
#endregion


static func for_terrain(terrain: TerrainData) -> PlacementGrid:
	var grid := PlacementGrid.new()
	grid.width = terrain.grid_width()
	grid.depth = terrain.grid_depth()
	grid._blocked.resize(grid.width * grid.depth)
	for z: int in grid.depth:
		for x: int in grid.width:
			if not terrain.is_cell_in_play(Vector2i(x, z)):
				grid._blocked[z * grid.width + x] = 1
	return grid


func is_free(a_cell: Vector2i) -> bool:
	if a_cell.x < 0 or a_cell.y < 0 or a_cell.x >= width or a_cell.y >= depth:
		return false
	return _blocked[a_cell.y * width + a_cell.x] == 0


## Whether every cell of the `dims` rectangle at `origin` is free.
func is_rect_free(a_origin: Vector2i, a_dims: Vector2i) -> bool:
	for dx: int in a_dims.x:
		for dz: int in a_dims.y:
			if not is_free(a_origin + Vector2i(dx, dz)):
				return false
	return true


## Reserve `cells` and everything within `margin` cells of them (Chebyshev).
func reserve(a_cells: Array[Vector2i], a_margin: int) -> void:
	for cell: Vector2i in a_cells:
		for dx: int in range(-a_margin, a_margin + 1):
			for dz: int in range(-a_margin, a_margin + 1):
				var at: Vector2i = cell + Vector2i(dx, dz)
				if at.x >= 0 and at.y >= 0 and at.x < width and at.y < depth:
					_blocked[at.y * width + at.x] = 1


static func rect_cells(origin: Vector2i, dims: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx: int in dims.x:
		for dz: int in dims.y:
			cells.append(origin + Vector2i(dx, dz))
	return cells
