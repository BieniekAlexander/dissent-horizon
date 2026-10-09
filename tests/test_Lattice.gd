extends GutTest

## THE LATTICE IS MIRROR-SYMMETRIC BY CONSTRUCTION. `Lattice.covering` lays its cells out from
## the map's centre, so a point and its reflection through the centre fall in cells that are
## each other's `reflected` partner — the property the old scout grid lacked, and the one every
## lattice channel inherits by indexing through this object
## (gdd/systems/ai/world-model/lattice-and-topology.md §Determinism).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Lattice.gd -gexit


func test_a_square_map_is_covered_from_its_centre() -> void:
	var lattice: Lattice = Lattice.covering(Rect2(-10.0, -10.0, 20.0, 20.0), 5.0)
	assert_eq(lattice.width, 4)
	assert_eq(lattice.depth, 4)
	assert_eq(lattice.origin, Vector2(-10.0, -10.0))
	assert_eq(lattice.centre_of(Vector2i(0, 0)), Vector2(-7.5, -7.5))
	assert_eq(lattice.index_at(Vector2(-7.5, -7.5)), Vector2i(0, 0))
	assert_eq(lattice.index_at(Vector2(9.9, 9.9)), Vector2i(3, 3))
	assert_eq(lattice.rect_of(Vector2i(3, 0)), Rect2(5.0, -10.0, 5.0, 5.0))
	assert_eq(lattice.cell_count(), 16)
	assert_eq(lattice.cell_of(lattice.index_of(Vector2i(2, 3))), Vector2i(2, 3))


func test_an_odd_remainder_is_split_over_both_edges() -> void:
	# 22 wide at pitch 5 needs 5 cells (25): the extra 1.5 hangs over each edge equally, so
	# the cell boundaries stay symmetric about the centre.
	var lattice: Lattice = Lattice.covering(Rect2(-11.0, -3.0, 22.0, 6.0), 5.0)
	assert_eq(lattice.width, 5)
	assert_eq(lattice.depth, 2)
	assert_eq(lattice.origin, Vector2(-12.5, -5.0))
	assert_eq(lattice.centre(), Vector2.ZERO)
	assert_true(lattice.is_in_bounds(Vector2i(4, 1)))
	assert_false(lattice.is_in_bounds(Vector2i(5, 0)))
	assert_false(lattice.is_in_bounds(Vector2i(0, -1)))


func test_a_point_and_its_reflection_land_in_partner_cells() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for bounds: Rect2 in [
		Rect2(-10.0, -10.0, 20.0, 20.0),
		Rect2(-11.0, -3.0, 22.0, 6.0),
		Rect2(3.0, -40.0, 221.0, 221.0),
	]:
		var lattice: Lattice = Lattice.covering(bounds, 5.0)
		var centre: Vector2 = bounds.get_center()
		for _i: int in 300:
			var p := Vector2(
				rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)
			)
			var mirror: Vector2 = centre * 2.0 - p
			assert_eq(
				lattice.index_at(mirror),
				lattice.reflected(lattice.index_at(p)),
				"%s reflects to %s" % [p, mirror]
			)


func test_an_anchored_lattice_indexes_a_synthetic_grid() -> void:
	# Origin half a pitch back, so points at multiples of the pitch sit on cell centres and
	# index_at rounds to the nearest multiple — what a hand-written test grid expects.
	var lattice: Lattice = Lattice.anchored(Vector2(-2.5, -2.5), 5.0)
	assert_eq(lattice.index_at(Vector2(10.0, 0.0)), Vector2i(2, 0))
	assert_eq(lattice.index_at(Vector2(12.4, 0.0)), Vector2i(2, 0))
	assert_eq(lattice.index_at(Vector2(12.6, 0.0)), Vector2i(3, 0))
	assert_eq(lattice.index_at(Vector2(-7.4, -7.4)), Vector2i(-1, -1))
	assert_false(lattice.is_in_bounds(Vector2i(0, 0)))
	assert_eq(lattice.cell_count(), 0)
