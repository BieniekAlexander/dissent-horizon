extends GutTest

## Where an ability that is CALLED IN from beyond the play space starts, and when what it
## sent has left again — the shared entry rule behind the Mortar barrage and the Drop's
## transport (gdd/systems/macroeconomics/sanctions/off-map-abilities.md).
##
## Two layers, tested separately because they fail differently:
##   • PlayArea's perimeter geometry, which is pure and exercised on both an axis-aligned
##     rectangle and the rotated (screen-aligned) one every real map actually uses;
##   • OffMapArrival's rule on top of it — caster-keyed origin, the margin, the exit
##     point, and the fallbacks for a map with no play area at all.
##
## The Map is faked by overriding play_area() rather than building terrain: nothing here
## reads a height, and a real heightmap would make none of these assertions stronger.

class FakeMap extends Map:
	var area: PlayArea = null

	func play_area() -> PlayArea:
		return area


## Half-extents of the test rectangle, in world units. Asymmetric so an assertion cannot
## pass by picking the wrong axis.
const HALF: Vector2 = Vector2(20.0, 12.0)
const EPSILON: float = 0.001


func _axis_aligned() -> PlayArea:
	return PlayArea.axis_aligned(Vector2.ZERO, HALF)


## The frame TerrainData actually authors in: a 45°-rotated rectangle in world XZ. Its
## half-extents come out as half_st * cell_size / sqrt(2) (see PlayArea.screen_aligned).
func _screen_aligned() -> PlayArea:
	return PlayArea.screen_aligned(Vector2.ZERO, Vector2(30.0, 18.0), 1.0)


func _map_with(a_area: PlayArea) -> FakeMap:
	var map: FakeMap = autofree(FakeMap.new())
	map.area = a_area
	return map


#region PlayArea perimeter
func test_nearest_perimeter_leaves_by_the_closest_edge() -> void:
	var area: PlayArea = _axis_aligned()
	# Nearer the +Z edge (12 away) than the +X one (20 away), so it leaves by +Z.
	var edge: Vector2 = area.nearest_perimeter_point(Vector2(0.0, 6.0))
	assert_almost_eq(edge.y, HALF.y, EPSILON, "should leave by the near edge")
	assert_almost_eq(edge.x, 0.0, EPSILON, "should not slide along the edge")


func test_nearest_perimeter_of_an_outside_point_is_the_clamp() -> void:
	var area: PlayArea = _axis_aligned()
	var edge: Vector2 = area.nearest_perimeter_point(Vector2(50.0, 3.0))
	assert_almost_eq(edge.x, HALF.x, EPSILON, "x clamps to the boundary")
	assert_almost_eq(edge.y, 3.0, EPSILON, "y is already inside and is kept")


func test_nearest_perimeter_point_is_on_the_perimeter() -> void:
	# The invariant that matters, asserted on the ROTATED rectangle real maps use: the
	# answer is on the boundary in the area's OWN frame, which a world-space bounding box
	# would get wrong at exactly the four dead corners.
	var area: PlayArea = _screen_aligned()
	for probe: Vector2 in [Vector2(3.0, -4.0), Vector2(-9.0, 1.0), Vector2(40.0, 40.0)]:
		var local: Vector2 = area.to_local(area.nearest_perimeter_point(probe))
		var on_edge: bool = is_equal_approx(absf(local.x), area.half.x) \
			or is_equal_approx(absf(local.y), area.half.y)
		assert_true(on_edge, "%s should map onto the perimeter, got local %s" % [probe, local])


func test_exterior_point_clears_the_area_by_the_margin() -> void:
	var area: PlayArea = _axis_aligned()
	var caster: Vector2 = Vector2(0.0, 6.0)
	var outside: Vector2 = area.exterior_point(caster, 10.0)
	assert_almost_eq(outside.y, HALF.y + 10.0, EPSILON, "10 units past the near edge")
	assert_true(area.is_beyond(outside, 9.9), "should read as beyond at just under the margin")
	assert_false(area.is_beyond(outside, 10.1), "and not beyond at just over it")


func test_exterior_point_of_a_caster_on_the_perimeter_uses_the_edge_normal() -> void:
	# The degenerate ray: caster exactly on the boundary, which is where a player parks a
	# building. Without the normal fallback this would normalize a zero vector.
	var area: PlayArea = _axis_aligned()
	var outside: Vector2 = area.exterior_point(Vector2(0.0, HALF.y), 10.0)
	assert_almost_eq(outside.y, HALF.y + 10.0, EPSILON, "pushed out along the edge normal")
	assert_almost_eq(outside.x, 0.0, EPSILON, "and not sideways")
#endregion


#region OffMapArrival
func test_entry_point_is_keyed_to_the_caster_not_the_target() -> void:
	# The design rule: a caster near the -X edge sends its delivery in over -X, however far
	# across the map the target is. Keying it to the target would put both on +X.
	var map: FakeMap = _map_with(_axis_aligned())
	var entry: Vector2 = OffMapArrival.entry_xz(map, Vector2(-18.0, 0.0))
	assert_almost_eq(entry.x, -(HALF.x + OffMapArrival.EXTERIOR_MARGIN), EPSILON,
		"should enter over the caster's own edge")


func test_entry_point_has_left_the_map() -> void:
	# Entry and exit share one margin, so a piece is never judged to have left the tick it
	# spawns — it is exactly AT the threshold, and the test is strict.
	var map: FakeMap = _map_with(_axis_aligned())
	var entry: Vector2 = OffMapArrival.entry_xz(map, Vector2(0.0, 6.0))
	assert_false(OffMapArrival.has_left(map, entry),
		"a piece at its own entry point has not left yet")
	assert_true(OffMapArrival.has_left(map, entry + Vector2(0.0, 1.0)),
		"one unit further out, it has")


func test_a_point_inside_the_area_has_not_left() -> void:
	var map: FakeMap = _map_with(_axis_aligned())
	assert_false(OffMapArrival.has_left(map, Vector2(5.0, -2.0)))


func test_exit_point_is_beyond_the_area_along_the_heading() -> void:
	var map: FakeMap = _map_with(_axis_aligned())
	var heading: Vector2 = Vector2(1.0, 0.4).normalized()
	var exit_xz: Vector2 = OffMapArrival.exit_xz(map, Vector2(0.0, 0.0), heading)
	assert_true(OffMapArrival.has_left(map, exit_xz), "the fly-through destination is off the map")
	assert_almost_eq(
		Vector2(0.0, 0.0).direction_to(exit_xz).angle_to(heading), 0.0, EPSILON,
		"and lies on the heading, not merely somewhere outside"
	)


func test_exit_point_survives_a_zero_heading() -> void:
	# A transport released with no facing at all still has to be aimed somewhere off the
	# map rather than at its own position, or its egress leg never completes.
	var map: FakeMap = _map_with(_axis_aligned())
	var exit_xz: Vector2 = OffMapArrival.exit_xz(map, Vector2.ZERO, Vector2.ZERO)
	assert_true(OffMapArrival.has_left(map, exit_xz))
#endregion


#region No play area
## A map with no play rectangle — a bare harness, a scene with no heightmap. The ability
## degrades to firing from the caster rather than refusing, and nothing is ever judged to
## have left a map that has no edges.
func test_entry_falls_back_to_the_caster_without_a_play_area() -> void:
	var caster: Vector2 = Vector2(4.0, -7.0)
	assert_eq(OffMapArrival.entry_xz(_map_with(null), caster), caster)
	assert_eq(OffMapArrival.entry_xz(null, caster), caster)


func test_nothing_has_left_a_map_with_no_play_area() -> void:
	assert_false(OffMapArrival.has_left(_map_with(null), Vector2(9999.0, 9999.0)),
		"a piece that could never be judged gone must keep flying, not vanish")


func test_a_degenerate_play_area_counts_as_none() -> void:
	# PlayArea.is_valid() is false for zero half-extents (no heightmap resolved yet), and
	# taking it at face value would divide the entry rule by nothing.
	var map: FakeMap = _map_with(PlayArea.axis_aligned(Vector2.ZERO, Vector2.ZERO))
	assert_eq(OffMapArrival.entry_xz(map, Vector2(1.0, 2.0)), Vector2(1.0, 2.0))
#endregion


#region Mortar spread
## The barrage scatters its MUZZLES, at 1 + 2*randf() world units from the single origin.
func test_mortar_launch_offsets_stay_within_the_authored_spread() -> void:
	for _i: int in 50:
		var offset: Vector2 = EventMortarBarrage._launch_offset()
		var reach: float = offset.length()
		assert_between(reach,
			EventMortarBarrage.LAUNCH_SPREAD_MIN - EPSILON,
			EventMortarBarrage.LAUNCH_SPREAD_MIN + EventMortarBarrage.LAUNCH_SPREAD_RANGE + EPSILON,
			"launch offset should land inside the authored ring")
#endregion
