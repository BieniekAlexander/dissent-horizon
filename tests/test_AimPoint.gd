extends GutTest

## A piece's hitbox (TargetBody/TargetShape) stands ON its base rather than straddling it, and a
## steered weapon aims at that hitbox's centre (Entity.aim_point). Before 2026-10-03 every hitbox
## was centred on its piece's origin — its feet — so half of it was underground and a rocket
## steered at its centre dived into the terrain in front of a ground target.
## See gdd/systems/combat/projectiles.md §A rocket aims at the hitbox.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AimPoint.gd -gexit

const TOLERANCE: float = 0.001


func _unit_at(a_position: Vector3) -> Commandable:
	var unit: Commandable = FakePieces.unit()
	add_child_autofree(unit)
	unit.global_position = a_position
	return unit


func _target_shape(a_piece: Entity) -> CollisionShape3D:
	return a_piece.target_body.get_node("TargetShape") as CollisionShape3D


func test_a_hitbox_stands_on_its_piece_base() -> void:
	var unit: Commandable = _unit_at(Vector3(3.0, 0.0, 2.0))
	var shape: CollisionShape3D = _target_shape(unit)
	var half_height: float = RangeShapes.half_height_of(shape.shape)
	assert_gt(half_height, 0.0, "the fixture's hitbox has a height")
	assert_almost_eq(
		shape.global_position.y - half_height, unit.global_position.y, TOLERANCE, "bottom on base"
	)


func test_a_steered_weapon_aims_at_the_hitbox_centre() -> void:
	var unit: Commandable = _unit_at(Vector3(3.0, 0.0, 2.0))
	assert_eq(unit.aim_point(), _target_shape(unit).global_position)
	assert_gt(unit.aim_point().y, unit.global_position.y, "above the ground, not at the feet")


func test_a_hitbox_placed_higher_is_left_where_it_is() -> void:
	var unit: Commandable = FakePieces.unit()
	unit.get_node("TargetBody/TargetShape").position.y = 5.0
	add_child_autofree(unit)
	assert_almost_eq(_target_shape(unit).position.y, 5.0, TOLERANCE)


func test_a_piece_without_a_hitbox_is_aimed_at_its_origin() -> void:
	var marker: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	marker.add_child(ownership)
	add_child_autofree(marker)
	marker.global_position = Vector3(1.0, 2.0, 3.0)
	assert_eq(marker.aim_point(), marker.global_position)


func test_a_steered_phase_arrives_at_the_hitbox_centre_not_the_feet() -> void:
	var unit: Commandable = _unit_at(Vector3.ZERO)
	var phase: EmissionPhase = EmissionPhase.new()
	phase.speed = 12.0
	phase.turn_rate_degrees_per_second = 90.0
	autofree(phase)
	assert_true(phase.has_arrived(unit.aim_point(), Vector3.ZERO, Vector3.ZERO, unit))
	assert_false(
		phase.has_arrived(unit.global_position, Vector3.ZERO, Vector3.ZERO, unit),
		"the feet are a full half-height below where it aims"
	)
