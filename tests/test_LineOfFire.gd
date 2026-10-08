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

const SOLDIER: Dictionary = {"speed": 2.0, "weapon": {"ground": 6.0}}
const AIRCRAFT: Dictionary = {"aerial": true, "weapon": {"ground": 6.0}}

## Far enough apart that the building sits squarely between them, with room either side.
const SPAN: float = 8.0


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _piece(a_options: Dictionary, a_commander: Commander, a_at: Vector3) -> Actor:
	var piece: Actor = FakePieces.unit(a_options)
	add_child_autofree(piece)
	piece.ownership.commander = a_commander
	piece.global_position = a_at
	return piece


## A finished building halfway between two points on the line, which is an obstruction
## unless `a_is_obstruction` says otherwise.
func _building_between(a_is_obstruction: bool = true) -> Actor:
	var building: Actor = FakePieces.structure({"dimensions": Vector2i(2, 2)})
	add_child_autofree(building)
	building.ownership.commander = _commander(0)
	(building.get_node("Fixture") as Fixture).is_obstruction = a_is_obstruction
	building._apply_targetable_layers()
	return building


func test_an_obstruction_blocks_a_shot_between_two_ground_pieces() -> void:
	var building: Actor = _building_between()
	var shooter: Actor = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(building.blocks_line_of_fire(), "guards the fixture: a finished obstruction")
	assert_true(Attack._obstruction_on_line(shooter, target))


func test_an_occupant_only_fixture_is_not_cover() -> void:
	var building: Actor = _building_between(false)
	var shooter: Actor = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_false(building.blocks_line_of_fire())
	assert_false(Attack._obstruction_on_line(shooter, target))


func test_an_obstruction_does_not_block_a_shot_at_an_air_target() -> void:
	_building_between()
	var shooter: Actor = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(AIRCRAFT, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(target.is_air_target(), "guards the fixture: the aircraft is airborne")
	assert_false(Attack._obstruction_on_line(shooter, target))


func test_an_obstruction_does_not_block_a_shot_from_an_air_target() -> void:
	_building_between()
	var shooter: Actor = _piece(AIRCRAFT, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(shooter.is_air_target(), "guards the fixture: the aircraft is airborne")
	assert_false(Attack._obstruction_on_line(shooter, target))


## A building's own blocker body is not cover against its own shots. Its ray starts at its own
## origin, inside or on that body, which once stopped every unordered shot a Watch Tower took.
func test_a_structure_is_not_cover_against_itself() -> void:
	var tower: Actor = FakePieces.structure(
		{"dimensions": Vector2i(1, 1), "weapon": {"ground": 12.0}}
	)
	add_child_autofree(tower)
	tower.ownership.commander = _commander(1)
	tower._apply_targetable_layers()
	var target: Actor = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(tower.blocks_line_of_fire(), "guards the fixture: the tower is an obstruction")
	assert_false(Attack._obstruction_on_line(tower, target))


#region Terrain
## TERRAIN BLOCKS A SHOT ONLY FOR A WEAPON SHORT OF ARTILLERY REACH. A hill is a box on the
## TERRAIN layer here (the harness for the baked surface body). Why:
## gdd/systems/combat/target-acquisition.md §Terrain on the line of fire.
func _hill_between() -> StaticBody3D:
	var hill := StaticBody3D.new()
	hill.collision_layer = CollisionLayers.Mask.TERRAIN
	hill.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 10, 6)
	shape.shape = box
	hill.add_child(shape)
	add_child_autofree(hill)
	return hill


func test_terrain_blocks_a_short_weapon() -> void:
	_hill_between()
	var shooter: Actor = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_true(Attack._obstruction_on_line(shooter, target))


func test_terrain_does_not_block_an_artillery_weapon() -> void:
	_hill_between()
	var gun: Dictionary = {"speed": 2.0, "weapon": {"ground": RangeShapes.artillery_reach()}}
	var shooter: Actor = _piece(gun, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_false(Attack._obstruction_on_line(shooter, target))


func test_terrain_off_the_line_does_not_block() -> void:
	_hill_between().position = Vector3(0, 0, 20)
	var shooter: Actor = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(SOLDIER, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_false(Attack._obstruction_on_line(shooter, target))


func test_terrain_does_not_block_a_shot_at_an_air_target() -> void:
	_hill_between()
	var shooter: Actor = _piece(SOLDIER, _commander(1), Vector3(-SPAN, 0, 0))
	var target: Actor = _piece(AIRCRAFT, _commander(2), Vector3(SPAN, 0, 0))
	await wait_physics_frames(2)
	assert_false(Attack._obstruction_on_line(shooter, target))


#endregion
