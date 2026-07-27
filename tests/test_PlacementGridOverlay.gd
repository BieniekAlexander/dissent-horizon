extends GutTest

## The placement grid's region arithmetic: the margin around a footprint and the falloff rings
## past it. Synthetic cell sets only.


func _cells(a_cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in a_cells:
		out[cell] = true
	return out


func test_a_margin_reaches_diagonally_as_well() -> void:
	var grown: Dictionary = PlacementGridOverlay.dilate(_cells([Vector2i.ZERO]), 1)
	assert_eq(grown.size(), 9, "one cell grows to a 3x3 block")
	assert_true(grown.has(Vector2i(1, 1)))


func test_the_margin_surrounds_a_footprint() -> void:
	var footprint: Dictionary = _cells(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])
	var lit: Dictionary = PlacementGridOverlay.dilate(footprint, PlacementGridOverlay.MARGIN_CELLS)
	var side: int = 2 + 2 * PlacementGridOverlay.MARGIN_CELLS
	assert_eq(lit.size(), side * side)


func test_falloff_rings_are_disjoint_and_grow_outward() -> void:
	var region: Dictionary = _cells([Vector2i.ZERO])
	var rings: Array[Dictionary] = PlacementGridOverlay.falloff_rings(region, 2)
	assert_eq(rings.size(), 2)
	assert_eq(rings[0].size(), 8, "the first ring is the 8 neighbours")
	assert_eq(rings[1].size(), 16, "the second is the 5x5 border")
	for cell: Vector2i in rings[1]:
		assert_false(rings[0].has(cell) or region.has(cell), "%s repeats an inner cell" % cell)
