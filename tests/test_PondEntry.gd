extends GutTest

## A pond is a resource only if units can walk into it, so the generator rejects a map with a
## pond whose every edge is too steep (MapGenerator.is_walkable_into).

const _PLAY := Vector2i(20, 20)
const _GROUND: float = 4.0
## A square pan in the middle of the play area, in cells.
const _PAN_ORIGIN := Vector2i(16, 16)
const _PAN_SIZE: int = 4


## Flat ground with a pan sunk `a_sink` below it, flooded to just above its floor.
func _pond(a_sink: float) -> TerrainData:
	var td := TerrainData.new()
	td.play_size = _PLAY
	var heights := PackedFloat32Array()
	heights.resize(td.map_width() * td.map_depth())
	heights.fill(_GROUND)
	for corner: Vector2i in PlacementGrid.rect_cells(_PAN_ORIGIN, Vector2i.ONE * (_PAN_SIZE + 1)):
		heights[corner.y * td.map_width() + corner.x] = _GROUND - a_sink
	td.heights = heights
	return td


func _level(a_sink: float) -> float:
	return _GROUND - a_sink * (1.0 - FeaturePlacer.POND_LEVEL_FRACTION)


func test_a_pond_sunk_as_the_generator_sinks_one_can_be_walked_into() -> void:
	var sink: float = FeaturePlacer.POND_SINK
	assert_true(MapGenerator.is_walkable_into(_pond(sink), _PAN_ORIGIN, _level(sink)))


func test_a_pond_sunk_past_the_walkable_limit_cannot() -> void:
	var sink: float = TerrainGrid.MAX_SLOPE_DIFF * 2.0
	assert_false(MapGenerator.is_walkable_into(_pond(sink), _PAN_ORIGIN, _level(sink)))
