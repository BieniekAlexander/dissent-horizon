extends GutTest

## Tests for map generation pass 7, the cosmetic layer (scripts/maps/decoration): the planner's
## placement rules, its determinism, and that a generated map and the same map loaded as a
## scene decorate identically. Pure where it can be — synthetic TerrainData fixtures sculpted
## here, never a shipped map (CLAUDE.md §A unit test does not assert facts about authored
## content).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapDecoration.gd \
##     -gdir=res://tests/none -gexit

## 41 x 41 cells, comfortably larger than every planner radius.
const _PLAY: Vector2i = Vector2i(20, 20)
const _GROUND: float = 2.0
## A ridge this tall over one cell is steep (well past TerrainGrid.MAX_SLOPE_DIFF).
const _RIDGE_RISE: float = 2.0
const _SEED: int = 4242


#region Fixtures
func _flat() -> TerrainData:
	var td := TerrainData.new()
	td.play_size = _PLAY
	var heights := PackedFloat32Array()
	heights.resize(td.map_width() * td.map_depth())
	heights.fill(_GROUND)
	td.heights = heights
	return td


## A wall of raised corners along column `x` from z0 to z1: the cells either side are steep.
func _ridge(a_td: TerrainData, a_x: int, a_z0: int, a_z1: int) -> void:
	var heights: PackedFloat32Array = a_td.heights
	for z: int in range(a_z0, a_z1 + 1):
		heights[z * a_td.map_width() + a_x] = _GROUND + _RIDGE_RISE
	a_td.heights = heights


func _decoration_input(a_td: TerrainData, a_fixtures: Array[Dictionary] = []) -> MapDecorationInput:
	var input := MapDecorationInput.new()
	input.terrain = a_td
	input.fixtures = a_fixtures
	input.rng_seed = MapDecorationInput.decoration_seed(a_td)
	return input


func _building(a_origin: Vector2i, a_size: Vector2i) -> Dictionary:
	return {
		"kind": MapDecorationInput.FixtureKind.BUILDING,
		"cells": MapDecorationInput.footprint(a_origin, a_size)
	}


func _ridged() -> TerrainData:
	var td: TerrainData = _flat()
	_ridge(td, 20, 8, 32)
	return td


#endregion


#region Placement rules
func test_tall_props_are_never_admissible_on_walkable_ground() -> void:
	var walkable: int = MapDecorationPlanner._IN_PLAY
	var steep: int = MapDecorationPlanner._IN_PLAY | MapDecorationPlanner._STEEP
	for kind: DoodadLibrary.Kind in DoodadLibrary.all_kinds():
		assert_eq(
			MapDecorationPlanner.is_admissible(kind, walkable),
			DoodadLibrary.is_low(kind),
			"%s on walkable ground" % DoodadLibrary.Kind.keys()[kind]
		)
		assert_true(
			MapDecorationPlanner.is_admissible(kind, steep),
			"anything may stand where no unit walks"
		)


func test_nothing_stands_on_a_fixture_trail_or_deep_water() -> void:
	for flag: int in [
		MapDecorationPlanner._FIXTURE, MapDecorationPlanner._TRAIL, MapDecorationPlanner._DEEP
	]:
		assert_false(
			MapDecorationPlanner.is_admissible(
				DoodadLibrary.Kind.GRASS_TUFT, MapDecorationPlanner._IN_PLAY | flag
			)
		)


func test_every_planned_prop_obeys_the_height_rule() -> void:
	var td: TerrainData = _ridged()
	var planned: MapDecoration = MapDecorationPlanner.plan(_decoration_input(td))
	assert_gt(planned.doodads.size(), 0, "a ridged field gets some props")
	for doodad: DoodadPlacement in planned.doodads:
		if not DoodadLibrary.is_low(doodad.kind):
			assert_gt(
				td.cell_height_spread(doodad.cell),
				TerrainGrid.MAX_SLOPE_DIFF,
				"a tall prop at %s stands on walkable ground" % doodad.cell
			)


func test_no_prop_stands_on_or_beside_a_fixture() -> void:
	var td: TerrainData = _flat()
	var fixtures: Array[Dictionary] = [_building(Vector2i(10, 10), Vector2i(4, 4))]
	var planned: MapDecoration = MapDecorationPlanner.plan(_decoration_input(td, fixtures))
	for doodad: DoodadPlacement in planned.doodads:
		var inside: bool = (
			doodad.cell.x >= 9
			and doodad.cell.x <= 14
			and doodad.cell.y >= 9
			and doodad.cell.y <= 14
		)
		assert_false(inside, "prop at %s is on the footprint or its margin" % doodad.cell)


func test_props_sit_on_the_ground() -> void:
	var td: TerrainData = _ridged()
	for doodad: DoodadPlacement in MapDecorationPlanner.plan(_decoration_input(td)).doodads:
		var lo: float = minf(
			td.corner_height(doodad.cell), td.corner_height(doodad.cell + Vector2i.ONE)
		)
		assert_between(doodad.position.y, _GROUND - 0.01, _GROUND + _RIDGE_RISE + 0.01)
		assert_true(doodad.position.y >= lo - _RIDGE_RISE, "not buried")


#endregion


#region Trails and paint
func test_a_trail_joins_two_settlements_over_walkable_ground() -> void:
	var td: TerrainData = _ridged()
	var fixtures: Array[Dictionary] = [
		_building(Vector2i(8, 18), Vector2i(3, 3)), _building(Vector2i(30, 18), Vector2i(3, 3))
	]
	var planned: MapDecoration = MapDecorationPlanner.plan(_decoration_input(td, fixtures))
	assert_eq(planned.trails.size(), 1, "two settlements, one edge of the tree")
	var trail: PackedVector2Array = planned.trails[0]
	assert_lt(trail[0].distance_to(Vector2(9.5, 19.5)), 4.0, "starts at one settlement")
	assert_lt(trail[trail.size() - 1].distance_to(Vector2(31.5, 19.5)), 4.0, "ends at the other")
	for point: Vector2 in trail:
		assert_true(
			td.cell_height_spread(Vector2i(point)) <= TerrainGrid.MAX_SLOPE_DIFF,
			"trail crosses the ridge at %s instead of going round" % point
		)


func test_buildings_close_together_are_one_settlement() -> void:
	var td: TerrainData = _flat()
	var fixtures: Array[Dictionary] = [
		_building(Vector2i(10, 10), Vector2i(2, 2)), _building(Vector2i(14, 10), Vector2i(2, 2))
	]
	assert_eq(MapDecorationPlanner.plan(_decoration_input(td, fixtures)).trails.size(), 0)


func test_the_ground_paint_covers_the_grid_and_marks_trails() -> void:
	var td: TerrainData = _flat()
	var fixtures: Array[Dictionary] = [
		_building(Vector2i(5, 18), Vector2i(2, 2)), _building(Vector2i(33, 18), Vector2i(2, 2))
	]
	var planned: MapDecoration = MapDecorationPlanner.plan(_decoration_input(td, fixtures))
	assert_eq(planned.ground_overlay.get_size(), Vector2i(td.grid_width(), td.grid_depth()))
	var on_trail := Vector2i(planned.trails[0][planned.trails[0].size() / 2])
	assert_eq(planned.ground_overlay.get_pixelv(on_trail).g, 1.0, "trail strength in G")


#endregion


#region Facets
func test_a_ridge_has_cliff_faces_on_both_sides() -> void:
	var planned: MapDecoration = MapDecorationPlanner.plan(_decoration_input(_ridged()))
	var faces: Array = planned.facets[MapDecoration.Facet.CLIFF_FACE]
	assert_true(
		faces.has(Vector2i(19, 20)) and faces.has(Vector2i(20, 20)),
		"both cells sharing the raised corners face walkable ground"
	)


#endregion


#region Determinism and agreement
func test_the_same_map_always_decorates_the_same_way() -> void:
	var first: MapDecoration = MapDecorationPlanner.plan(_decoration_input(_ridged()))
	var second: MapDecoration = MapDecorationPlanner.plan(_decoration_input(_ridged()))
	assert_eq(first.doodads.size(), second.doodads.size())
	assert_eq(first.ground_overlay.get_data(), second.ground_overlay.get_data())
	for i: int in first.doodads.size():
		assert_eq(first.doodads[i].position, second.doodads[i].position)


func test_an_edit_to_the_terrain_rerolls_the_seed() -> void:
	var td: TerrainData = _flat()
	var before: int = MapDecorationInput.decoration_seed(td)
	_ridge(td, 5, 5, 6)
	assert_ne(MapDecorationInput.decoration_seed(td), before)


## The rule the whole design rests on: decoration is derived, so the generator's own result and
## the map scene written from it must derive the SAME decoration.
func test_a_generated_map_and_its_scene_decorate_identically() -> void:
	var writer := GeneratedMapWriter.new()
	var params: MapGenerationParams = writer.default_params(2)
	params.last_pass = MapGenerationParams.Pass.RESOURCES
	params.play_size_min = 70
	params.play_size_max = 80
	params.energy_value_per_player = 12000.0
	params.target_traversable_fraction = 1.0
	params.traversable_tolerance = 1.0
	params.obstruction_tolerance = 1.0
	var generated: GeneratedMap = MapGenerator.generate(params, _SEED)
	assert_true(generated.is_valid(), str(generated.errors))
	var from_generator: MapDecoration = MapDecorationPlanner.plan(
		MapDecorationInput.from_generated(generated)
	)
	var terrain_path: String = "user://test_decoration_terrain.tres"
	var map: Map = writer.build_map(generated, terrain_path)
	var from_scene: MapDecoration = MapDecorationPlanner.plan(MapDecorationInput.from_map(map))
	map.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(terrain_path))
	assert_gt(from_generator.doodads.size(), 0)
	assert_eq(from_scene.doodads.size(), from_generator.doodads.size())
	assert_eq(from_scene.trails.size(), from_generator.trails.size())
	assert_eq(from_scene.ground_overlay.get_data(), from_generator.ground_overlay.get_data())
#endregion
