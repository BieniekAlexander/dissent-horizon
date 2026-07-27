extends GutTest

## ONLY AN OBSTRUCTION IS COVER, AND ONLY BETWEEN TWO GROUND PIECES.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_LineOfFire.gd -gexit
##
## A finished obstruction on the line between two ground pieces stops the shot; an
## occupant-only fixture, which units walk across, does not; and nothing stops a shot to or
## from an air target. Why: gdd/systems/combat/target-acquisition.md §Line of fire.
##
## PATHS, not preloads (see CLAUDE.md). Every scene is a HARNESS: the building's obstruction
## flag and every position are set here.

const SOLDIER: String = "res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn"
const AIRCRAFT: String = "res://scenes/entities/units/cl/cl_aircraftMedium_antiMech.tscn"
const BUILDING: String = "res://scenes/entities/structures/nt/nt_building.tscn"

## Far enough apart that the building sits squarely between them, with room either side.
const SPAN: float = 8.0


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _piece(a_scene: String, a_commander: Commander, a_at: Vector3) -> Commandable:
	var piece := (load(a_scene) as PackedScene).instantiate() as Commandable
	add_child_autofree(piece)
	piece.ownership.commander = a_commander
	piece.global_position = a_at
	return piece


## A finished building halfway between two points on the line, which is an obstruction
## unless `a_is_obstruction` says otherwise.
func _building_between(a_is_obstruction: bool = true) -> Commandable:
	var building: Commandable = _piece(BUILDING, _commander(0), Vector3.ZERO)
	(building.get_node("Structure") as Structure).is_obstruction = a_is_obstruction
	building._apply_targetable_layers()
	return building


func test_an_obstruction_blocks_a_shot_between_two_ground_pieces() -> void:
	var building: Commandable = _building_between()
	var shooter: Commandable = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Commandable = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(building.blocks_line_of_fire(), "guards the fixture: a finished obstruction")
	assert_true(Attack._obstruction_on_line(shooter, target))


func test_an_occupant_only_fixture_is_not_cover() -> void:
	var building: Commandable = _building_between(false)
	var shooter: Commandable = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Commandable = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_false(building.blocks_line_of_fire())
	assert_false(Attack._obstruction_on_line(shooter, target))


func test_an_obstruction_does_not_block_a_shot_at_an_air_target() -> void:
	_building_between()
	var shooter: Commandable = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Commandable = _piece(AIRCRAFT, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(target.is_air_target(), "guards the fixture: the aircraft is airborne")
	assert_false(Attack._obstruction_on_line(shooter, target))


func test_an_obstruction_does_not_block_a_shot_from_an_air_target() -> void:
	_building_between()
	var shooter: Commandable = _piece(AIRCRAFT, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Commandable = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(shooter.is_air_target(), "guards the fixture: the aircraft is airborne")
	assert_false(Attack._obstruction_on_line(shooter, target))
