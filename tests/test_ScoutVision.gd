extends GutTest

## A Scout — a non-Commandable Entity carrying a VisionRange — counts as one of its
## commander's vision sources.
##
## That is ALL this file pins now. It used to assert a geometric vision model through
## `Commander.has_vision_at`, which no longer exists: has_vision_at delegates to `Fog`, and a
## Fog binds to `get_tree().current_scene`, which GUT never sets — so a Fog built in a unit
## test is permanently inert and every such assertion was answering "no Fog" rather than
## anything about a Scout. Those three tests are deleted rather than propped up.
##
## The Scout's REAL fog contribution is covered end to end by
## `scenes/scenarios/test/test_scout_coverage.tscn` ("every scout point seen at least once
## within 3000 ticks"), run from tools/simulation/run_scenarios.gd.

var _cmdr: Commander


func before_each() -> void:
	_cmdr = Commander.new()
	add_child_autofree(_cmdr)  # in-tree so child Entities' @onready shapes resolve


func _add_scout_at(a_world_xz: Vector2) -> Commandable:
	var scout: Commandable = FakePieces.unit({"vision": 12.0})
	_cmdr.add_child(scout)
	scout.global_position = Vector3(a_world_xz.x, 0.0, a_world_xz.y)
	return scout


func test_scout_is_an_owned_vision_source() -> void:
	var scout := _add_scout_at(Vector2.ZERO)
	assert_true(
		scout.grants_vision(),
		"a Scout child should count as a vision source (it has a VisionRange)"
	)
