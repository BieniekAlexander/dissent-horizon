extends GutTest

## Two reported selection bugs.
##
## 1. **Cursor picking prefers a UNIT to a structure.** The camera looks down at an angle and
##    structure selection shapes are tall, so a structure routinely covers units standing
##    behind it and the nearest-hit rule made those units unclickable. The reverse (a
##    structure buried behind units) is accepted as unreachable in practice and is NOT handled
##    — the tests pin that asymmetry so nobody "fixes" it later.
## 2. **A freed entry in `selection` must not be touched.** `entity is Actor` on a freed
##    instance raises "Left operand of 'is' is a previously freed instance" — the reported
##    crash — because the type check ran BEFORE the validity guard. Order is the fix.
##
## The picking rule is tested through `preferred_cursor_entity`, which takes candidates in ray
## order, rather than through the raycast: the ray needs a physics server and the RULE is what
## broke. `load()` INSIDE each test, never at file scope (CLAUDE.md §A file-scope preload…).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_CursorPickingAndPrune.gd -gexit

const UNIT_SCENE: Dictionary = FakePieces.BUILDER
const STRUCTURE_SCENE: Dictionary = FakePieces.BUILDING


func _controller() -> RTSController:
	return autofree(RTSController.new()) as RTSController


func _unit() -> Entity:
	var unit := FakePieces.make(UNIT_SCENE) as Entity
	add_child_autofree(unit)
	return unit


func _structure() -> Entity:
	var structure := FakePieces.make(STRUCTURE_SCENE) as Entity
	add_child_autofree(structure)
	return structure


#region The picking rule
## The bug as reported: the structure is nearer the camera and still loses.
func test_a_unit_behind_a_structure_is_what_the_cursor_picks() -> void:
	var structure: Entity = _structure()
	var unit: Entity = _unit()
	var picked: Entity = RTSController.preferred_cursor_entity([structure, unit] as Array[Entity])
	assert_eq(picked, unit, "the unit wins even though the structure is hit first")


func test_a_unit_in_front_of_a_structure_still_wins() -> void:
	var unit: Entity = _unit()
	var structure: Entity = _structure()
	var picked: Entity = RTSController.preferred_cursor_entity([unit, structure] as Array[Entity])
	assert_eq(picked, unit, "ray order does not matter when a unit is present at all")


## The accepted asymmetry: with no unit among the candidates the nearest hit wins, so a
## structure is still pickable whenever nothing is standing over it.
func test_the_nearest_structure_wins_when_no_unit_is_hit() -> void:
	var near: Entity = _structure()
	var far: Entity = _structure()
	var picked: Entity = RTSController.preferred_cursor_entity([near, far] as Array[Entity])
	assert_eq(picked, near, "nearest-first still decides among structures")


## The FIRST unit in ray order wins, not merely any unit — two units stacked resolve to the
## one in front, which is the behaviour the old nearest-hit rule already had.
func test_the_nearest_unit_wins_among_units() -> void:
	var near: Entity = _unit()
	var far: Entity = _unit()
	var picked: Entity = RTSController.preferred_cursor_entity([near, far] as Array[Entity])
	assert_eq(picked, near, "nearest-first decides among units")


func test_nothing_hit_resolves_to_nothing() -> void:
	assert_null(
		RTSController.preferred_cursor_entity([] as Array[Entity]),
		"an empty candidate list means the caller falls through to the terrain hit"
	)


#endregion


#region The freed-entry prune
## The reported crash. A freed entry must be dropped without the loop touching it — and
## `is_instance_valid` is the only question that may be asked of it.
func test_a_freed_entry_is_dropped_without_touching_it() -> void:
	var controller: RTSController = _controller()
	var doomed := Node3D.new()
	controller.selection.append(doomed)
	doomed.free()

	var pruned: bool = controller.prune_selection()

	assert_true(pruned, "the prune reports that it removed something")
	assert_eq(controller.selection.size(), 0, "the freed entry is gone")


## A freed entry beside a live one: the live one survives and the loop does not abort.
func test_a_freed_entry_does_not_take_the_live_selection_with_it() -> void:
	var controller: RTSController = _controller()
	var doomed := Node3D.new()
	var survivor: Entity = _unit()
	controller.selection.append(doomed)
	controller.selection.append(survivor)
	doomed.free()

	controller.prune_selection()

	assert_eq(controller.selection, [survivor] as Array[Node], "only the freed entry went")


func test_a_live_selection_is_left_alone() -> void:
	var controller: RTSController = _controller()
	var unit: Entity = _unit()
	controller.selection.append(unit)

	var pruned: bool = controller.prune_selection()

	assert_false(pruned, "nothing to prune reports no change")
	assert_eq(controller.selection.size(), 1, "the live entry stays")
#endregion
