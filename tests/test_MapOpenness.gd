extends GutTest

## Tests for MapOpenness: clearance and the chokes between open areas, measured on a traversable
## mask (gdd/systems/terrain-and-navigation/map-generation.md §Openness). Every mask is built here.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapOpenness.gd \
##     -gdir=res://tests/none -gexit

const _SIZE: Vector2i = Vector2i(100, 50)
## Two rooms, each wide enough to be open ground by a clear margin.
const _LEFT_ROOM: Rect2i = Rect2i(2, 5, 40, 40)
const _RIGHT_ROOM: Rect2i = Rect2i(58, 5, 40, 40)


func _mask(a_rects: Array[Rect2i]) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(_SIZE.x * _SIZE.y)
	for rect: Rect2i in a_rects:
		for z: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				mask[z * _SIZE.x + x] = 1
	return mask


## Two rooms joined by a straight corridor `a_width` cells wide, centred on the rooms.
func _rooms_joined_by(a_width: int) -> PackedByteArray:
	var top: int = 25 - a_width / 2
	return _mask([_LEFT_ROOM, _RIGHT_ROOM, Rect2i(42, top, 16, a_width)])


func test_clearance_is_the_distance_to_the_nearest_blocked_cell() -> void:
	var openness: MapOpenness = MapOpenness.measure(_mask([Rect2i(10, 10, 9, 9)]), _SIZE.x, _SIZE.y)
	assert_almost_eq(openness.clearance[14 * _SIZE.x + 14], 5.0, 1e-4, "the middle of a 9-wide box")
	assert_almost_eq(openness.clearance[10 * _SIZE.x + 10], 1.0, 1e-4, "a corner cell")
	assert_eq(openness.clearance[0], 0.0, "a blocked cell")


func test_a_corridor_between_two_rooms_is_one_choke_its_own_width() -> void:
	for width: int in [3, 5, 9]:
		var openness: MapOpenness = MapOpenness.measure(_rooms_joined_by(width), _SIZE.x, _SIZE.y)
		assert_eq(openness.chokes.size(), 1, "corridor %d" % width)
		assert_almost_eq(float(openness.chokes[0].width), float(width), 1.0, "corridor %d" % width)


func test_one_open_field_has_no_choke() -> void:
	var openness: MapOpenness = MapOpenness.measure(_mask([Rect2i(2, 2, 96, 46)]), _SIZE.x, _SIZE.y)
	assert_eq(openness.chokes.size(), 0)


## A waist that is not markedly narrower than the rooms either side is one field, not a choke.
func test_a_wide_opening_is_not_a_choke() -> void:
	var openness: MapOpenness = MapOpenness.measure(_rooms_joined_by(36), _SIZE.x, _SIZE.y)
	assert_eq(openness.chokes.size(), 0)


## A passage into an alcove too small to be open ground is a dead end, not a choke.
func test_a_passage_into_an_alcove_is_not_a_choke() -> void:
	var alcove := Rect2i(58, 20, 8, 8)
	var openness: MapOpenness = MapOpenness.measure(
		_mask([_LEFT_ROOM, alcove, Rect2i(42, 22, 16, 4)]), _SIZE.x, _SIZE.y
	)
	assert_eq(openness.chokes.size(), 0)


func test_chokes_narrower_than_filters_by_width() -> void:
	var openness: MapOpenness = MapOpenness.measure(_rooms_joined_by(5), _SIZE.x, _SIZE.y)
	assert_eq(openness.chokes_narrower_than(6.0).size(), 1)
	assert_eq(openness.chokes_narrower_than(4.0).size(), 0)


## The corridor is walkable but no disc of radius 5 fits in it, so it falls outside the opening;
## the rooms are almost all inside it, short of their four corners.
func test_open_share_leaves_out_ground_no_wide_disc_fits() -> void:
	var openness: MapOpenness = MapOpenness.measure(_rooms_joined_by(3), _SIZE.x, _SIZE.y)
	var corridor_cells: float = 16.0 * 3.0
	var share: float = openness.open_share(5.0)
	assert_lt(share, 1.0 - corridor_cells / openness.traversable_cells + 1e-4)
	assert_gt(share, 0.95)
