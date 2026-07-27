extends GutTest

## TerrainGrid recomputes its distance and clearance fields only in the rectangle around what
## changed (grown by FIELD_CAP_CELLS). These tests pin that the local update always lands on
## exactly what a from-scratch computation of the same grid would give, through a random
## sequence of placements, removals and blocks.

const W: int = 31  # 31x31 corners -> 30x30 cells
const STEPS: int = 40
const SEED: int = 20260926
const MAX_FOOTPRINT_CELLS: int = 4


func _make_grid() -> TerrainGrid:
	var shape := HeightMapShape3D.new()
	shape.map_width = W
	shape.map_depth = W
	var data := PackedFloat32Array()
	data.resize(W * W)
	shape.map_data = data
	var body := StaticBody3D.new()
	add_child_autofree(body)
	var grid := TerrainGrid.new()
	grid.height_map = shape
	grid.terrain_body = body
	add_child_autofree(grid)
	return grid


## A fresh grid with the same impassable cells as `a_grid`, whose fields are computed whole.
func _fresh_copy(a_grid: TerrainGrid) -> TerrainGrid:
	var copy := _make_grid()
	var mask := PackedByteArray()
	mask.resize(a_grid.grid_width() * a_grid.grid_depth())
	for z: int in a_grid.grid_depth():
		for x: int in a_grid.grid_width():
			if not a_grid.is_passable(Vector2i(x, z)):
				mask[z * a_grid.grid_width() + x] = 1
	copy.set_blocked_mask(mask)
	return copy


func _field_mismatches(a_grid: TerrainGrid, a_reference: TerrainGrid) -> int:
	var mismatches: int = 0
	for z: int in a_grid.grid_depth():
		for x: int in a_grid.grid_width():
			var cell := Vector2i(x, z)
			if a_grid.distance_to_obstacle(cell) != a_reference.distance_to_obstacle(cell) \
					or a_grid.clearance_at(cell) != a_reference.clearance_at(cell):
				mismatches += 1
	return mismatches


func test_local_updates_match_a_full_recompute() -> void:
	var grid := _make_grid()
	grid.clearance_at(Vector2i.ZERO)  # the first read computes the whole grid
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var owners: Array[Node] = []
	for step: int in STEPS:
		var roll: int = rng.randi_range(0, 2)
		if roll == 0 or owners.is_empty():
			var origin := Vector2i(rng.randi_range(0, grid.grid_width() - 1),
				rng.randi_range(0, grid.grid_depth() - 1))
			var cells: Array = []
			for dz: int in rng.randi_range(1, MAX_FOOTPRINT_CELLS):
				for dx: int in rng.randi_range(1, MAX_FOOTPRINT_CELLS):
					var cell: Vector2i = origin + Vector2i(dx, dz)
					if grid.is_passable(cell):
						cells.append(cell)
			if cells.is_empty():
				continue
			var owner: Node = autofree(Node.new())
			grid.place_building(cells, owner)
			owners.append(owner)
		elif roll == 1:
			grid.remove_building(owners.pop_at(rng.randi_range(0, owners.size() - 1)))
		else:
			var cell := Vector2i(rng.randi_range(0, grid.grid_width() - 1),
				rng.randi_range(0, grid.grid_depth() - 1))
			grid.set_blocked(cell, not grid.is_blocked(cell))
		assert_eq(_field_mismatches(grid, _fresh_copy(grid)), 0, "step %d" % step)


## Several changes before one read are merged into one rectangle, far apart included.
func test_changes_batched_before_a_read_are_all_absorbed() -> void:
	var grid := _make_grid()
	grid.clearance_at(Vector2i.ZERO)
	grid.place_building([Vector2i(2, 2), Vector2i(3, 2)], autofree(Node.new()))
	grid.set_blocked(Vector2i(27, 26), true)
	assert_eq(_field_mismatches(grid, _fresh_copy(grid)), 0)


func test_fields_saturate_at_the_cap() -> void:
	var grid := _make_grid()
	var middle := Vector2i(15, 15)
	assert_eq(grid.distance_to_obstacle(middle), TerrainGrid.FIELD_CAP_CELLS,
		"open ground further than the cap from any edge reads as the cap")
	assert_eq(grid.clearance_at(Vector2i.ZERO), TerrainGrid.FIELD_CAP_CELLS)
