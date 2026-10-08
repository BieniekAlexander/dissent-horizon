extends GutTest

## Tests for MinimapLayer — the minimap's per-cell map layer and how fog shows it. Pure: the
## layer is built from synthetic cells here, never from a scene.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MinimapLayer.gd \
##     -gdir=res://tests/none -gexit

const _WIDTH: int = 12
const _DEPTH: int = 10


## Every cell in play except column 0.
func _in_play() -> PackedByteArray:
	var in_play := PackedByteArray()
	in_play.resize(_WIDTH * _DEPTH)
	for z: int in _DEPTH:
		for x: int in _WIDTH:
			in_play[z * _WIDTH + x] = 0 if x == 0 else 1
	return in_play


func _at(a_layer: PackedColorArray, a_cell: Vector2i) -> Color:
	return a_layer[a_cell.y * _WIDTH + a_cell.x]


func _build(
	a_ponds: Array[Dictionary], a_fixtures: Array[Dictionary], a_starts: Array[Dictionary]
) -> PackedColorArray:
	return MinimapLayer.build(_WIDTH, _DEPTH, _in_play(), a_ponds, a_fixtures, a_starts)


func test_ground_in_play_and_nothing_outside() -> void:
	var none: Array[Dictionary] = []
	var layer: PackedColorArray = _build(none, none, none)
	assert_eq(_at(layer, Vector2i(5, 5)), MinimapLayer.GROUND)
	assert_eq(_at(layer, Vector2i(0, 5)), MinimapLayer.OUT_OF_PLAY)


func test_a_pond_has_water_and_a_rim_around_it() -> void:
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	var ponds: Array[Dictionary] = [{cells = cells, color = MinimapLayer.POND_RICH}]
	var none: Array[Dictionary] = []
	var layer: PackedColorArray = _build(ponds, none, none)
	assert_true(_at(layer, Vector2i(5, 5)).is_equal_approx(MinimapLayer.POND_RICH))
	assert_eq(_at(layer, Vector2i(4, 4)), MinimapLayer.RIM)
	assert_eq(_at(layer, Vector2i(7, 6)), MinimapLayer.RIM)
	assert_eq(_at(layer, Vector2i(9, 9)), MinimapLayer.GROUND)


func test_fixtures_take_their_kind_colour() -> void:
	var none: Array[Dictionary] = []
	var site_cells: Array[Vector2i] = [Vector2i(2, 2)]
	var shelter_cells: Array[Vector2i] = [Vector2i(8, 8)]
	var fixtures: Array[Dictionary] = [
		{cells = site_cells, kind = MinimapLayer.Fixture.SITE},
		{cells = shelter_cells, kind = MinimapLayer.Fixture.SHELTER},
	]
	var layer: PackedColorArray = _build(none, fixtures, none)
	assert_eq(_at(layer, Vector2i(2, 2)), MinimapLayer.FIXTURE_COLORS[MinimapLayer.Fixture.SITE])
	assert_eq(_at(layer, Vector2i(8, 8)), MinimapLayer.FIXTURE_COLORS[MinimapLayer.Fixture.SHELTER])


func test_a_start_tints_its_square_toward_its_colour() -> void:
	var none: Array[Dictionary] = []
	var starts: Array[Dictionary] = [{center = Vector2(5, 5), half = 2.0, color = Color.RED}]
	var layer: PackedColorArray = _build(none, none, starts)
	var tinted: Color = _at(layer, Vector2i(4, 4))
	assert_ne(tinted, MinimapLayer.GROUND)
	assert_gt(tinted.r, MinimapLayer.GROUND.r)
	assert_eq(_at(layer, Vector2i(8, 8)), MinimapLayer.GROUND)


func test_nothing_paints_outside_the_play_area() -> void:
	var cells: Array[Vector2i] = [Vector2i(1, 5)]
	var ponds: Array[Dictionary] = [{cells = cells, color = MinimapLayer.POND_RICH}]
	var none: Array[Dictionary] = []
	var layer: PackedColorArray = _build(ponds, none, none)
	assert_eq(_at(layer, Vector2i(0, 5)), MinimapLayer.OUT_OF_PLAY)


func test_pond_shade_follows_richness() -> void:
	var poor: Color = MinimapLayer.pond_color(roundi(30 * MinimapLayer.POOR_ENERGY_PER_CELL), 30)
	var rich: Color = MinimapLayer.pond_color(roundi(30 * MinimapLayer.RICH_ENERGY_PER_CELL), 30)
	assert_true(poor.is_equal_approx(MinimapLayer.POND_POOR))
	assert_true(rich.is_equal_approx(MinimapLayer.POND_RICH))
	assert_eq(MinimapLayer.pond_color(0, 30), MinimapLayer.PLAIN_WATER)


func test_fog_darkens_explored_and_hides_unseen() -> void:
	var color: Color = MinimapLayer.GROUND
	assert_eq(MinimapLayer.fogged(color, Fog.TerrainVisibility.IN_SIGHT), color)
	assert_lt(MinimapLayer.fogged(color, Fog.TerrainVisibility.EXPLORED).v, color.v)
	assert_eq(MinimapLayer.fogged(color, Fog.TerrainVisibility.UNSEEN), MinimapLayer.OUT_OF_PLAY)


## Ground no unit can cross draws as a barrier; deep water keeps its pond's shade, darkened.
func _impassable(a_cells: Array[Vector2i]) -> PackedByteArray:
	var marks := PackedByteArray()
	marks.resize(_WIDTH * _DEPTH)
	for cell: Vector2i in a_cells:
		marks[cell.y * _WIDTH + cell.x] = 1
	return marks


func test_impassable_ground_draws_as_a_barrier() -> void:
	var none: Array[Dictionary] = []
	var cliff: Array[Vector2i] = [Vector2i(3, 3), Vector2i(0, 3)]
	var layer: PackedColorArray = MinimapLayer.build(
		_WIDTH, _DEPTH, _in_play(), none, none, none, _impassable(cliff)
	)
	assert_eq(_at(layer, Vector2i(3, 3)), MinimapLayer.IMPASSABLE)
	assert_eq(_at(layer, Vector2i(4, 3)), MinimapLayer.GROUND, "its neighbour is plain ground")
	assert_eq(_at(layer, Vector2i(0, 3)), MinimapLayer.OUT_OF_PLAY, "out of play stays black")


func test_deep_water_is_its_pond_darkened() -> void:
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	var deep: Array[Vector2i] = [Vector2i(6, 5)]
	var ponds: Array[Dictionary] = [{cells = cells, color = MinimapLayer.POND_RICH}]
	var none: Array[Dictionary] = []
	var layer: PackedColorArray = MinimapLayer.build(
		_WIDTH, _DEPTH, _in_play(), ponds, none, none, _impassable(deep)
	)
	assert_true(_at(layer, Vector2i(5, 5)).is_equal_approx(MinimapLayer.POND_RICH), "shallow")
	assert_true(
		_at(layer, Vector2i(6, 5)).is_equal_approx(
			MinimapLayer.POND_RICH.darkened(MinimapLayer.DEEP_WATER_DARKEN)
		),
		"deep"
	)
