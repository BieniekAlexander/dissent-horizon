extends GutTest

## What of an objective's marks the watching player may see (HighlightSight), and the world
## painter drawing a region's edge only as far as it is in sight.


## A sight that sees the half-plane x >= 0, and remembers what `a_remembered` holds.
func _half_sight(a_remembered: Array = []) -> HighlightSight:
	var sight := HighlightSight.new()
	sight.point_in_sight = func(xz: Vector2) -> bool: return xz.x >= 0.0
	sight.snapshot_shown = func(entity: Entity) -> bool: return a_remembered.has(entity)
	return sight


# --- HighlightSight -------------------------------------------------------------


func test_with_no_fog_to_ask_everything_is_shown() -> void:
	var sight := HighlightSight.new()
	var piece: Entity = autofree(FakePieces.structure())
	piece.visible = false
	assert_true(sight.shows_point(Vector2(-50.0, 0.0)))
	assert_true(sight.shows_entity(piece))


func test_a_point_is_shown_only_in_sight() -> void:
	var sight: HighlightSight = _half_sight()
	assert_true(sight.shows_point(Vector2(1.0, 0.0)))
	assert_false(sight.shows_point(Vector2(-1.0, 0.0)))


func test_a_piece_is_shown_while_the_fog_shows_it() -> void:
	var piece: Entity = autofree(FakePieces.structure())
	piece.visible = true
	assert_true(_half_sight().shows_entity(piece))


func test_a_hidden_piece_is_shown_through_its_snapshot() -> void:
	var piece: Entity = autofree(FakePieces.structure())
	piece.visible = false
	assert_true(_half_sight([piece]).shows_entity(piece), "under the fog, remembered")
	assert_false(_half_sight().shows_entity(piece), "unexplored: no snapshot, no mark")


func test_no_snapshot_is_shown_for_a_piece_never_seen() -> void:
	var commander := Commander.new()
	autofree(commander)
	var blackboard := CommanderBlackboard.new(commander)
	var piece: Entity = autofree(FakePieces.structure())
	assert_false(blackboard.is_snapshot_shown(piece))


# --- ScenarioHighlight ----------------------------------------------------------


func test_an_outline_keeps_only_the_edges_in_sight() -> void:
	var painter := ScenarioHighlight.new()
	autofree(painter)
	var shape := HighlightShape.circle(Vector2.ZERO, 4.0)
	var all: Array[Vector2] = painter._outline_segments(shape, HighlightSight.new())
	var seen: Array[Vector2] = painter._outline_segments(shape, _half_sight())
	assert_eq(seen.size() % 2, 0, "endpoint pairs")
	assert_gt(all.size(), seen.size())
	for point: Vector2 in seen:
		assert_true(point.x >= 0.0)
