extends GutTest

## Unit tests for the Mine-on-Deposit placement rule (Mine.valid_placement).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Mine.gd
##
## Uses a lightweight Map stub (no heightmap/navmesh/scene) so the rule can be
## checked in isolation. The overlay binding at build time (mine references the
## deposit, deposit references the mine, mine not grid-registered) is exercised by
## the headless s1.tscn run; here we pin down WHEN a mine may be placed.


## A minimal Map: just enough of the API that Mine.valid_placement touches, with a
## hand-set cell_grid and integer-rounded world↔grid mapping.
class StubMap extends Map:
	func world_to_grid(world_xz: Vector2) -> Vector2i:
		return Vector2i(roundi(world_xz.x), roundi(world_xz.y))
	func grid_coordinates_in_bounds(coords: Vector2i) -> bool:
		return coords.x >= 0 and coords.x < cell_grid.size() \
			and coords.y >= 0 and coords.y < cell_grid[0].size()


func _make_map() -> StubMap:
	var map := StubMap.new()
	autofree(map)
	# 3×3 grid of empty cells.
	map.cell_grid = []
	for x in range(3):
		var col: Array = []
		for y in range(3):
			col.append(null)
		map.cell_grid.append(col)
	return map


func _msg(map: Map, cell: Vector2i) -> CommandMessage:
	# world_position whose XZ rounds back to `cell` via StubMap.world_to_grid.
	return CommandMessage.new(map, null, null, Vector3(cell.x, 0, cell.y))


func test_rejects_bare_ground() -> void:
	var map := _make_map()
	assert_false(Mine.valid_placement(_msg(map, Vector2i(1, 1)), Vector2i.ONE),
		"a mine may not be built on an empty cell")


func test_rejects_non_deposit_structure() -> void:
	var map := _make_map()
	var other := autofree(Commandable.new()) as Commandable
	map.cell_grid[1][1] = other
	assert_false(Mine.valid_placement(_msg(map, Vector2i(1, 1)), Vector2i.ONE),
		"a mine may not be built on a non-deposit structure")


func test_accepts_free_deposit() -> void:
	var map := _make_map()
	var dep := autofree(Deposit.new()) as Deposit
	map.cell_grid[1][1] = dep
	assert_true(Mine.valid_placement(_msg(map, Vector2i(1, 1)), Vector2i.ONE),
		"a mine may be built on a free deposit")


func test_rejects_already_mined_deposit() -> void:
	var map := _make_map()
	var dep := autofree(Deposit.new()) as Deposit
	dep.mine = autofree(Commandable.new()) as Commandable
	map.cell_grid[1][1] = dep
	assert_false(Mine.valid_placement(_msg(map, Vector2i(1, 1)), Vector2i.ONE),
		"no second mine on a deposit that already has one")


func test_rejects_out_of_bounds() -> void:
	var map := _make_map()
	assert_false(Mine.valid_placement(_msg(map, Vector2i(9, 9)), Vector2i.ONE),
		"a mine may not be built off the grid")
