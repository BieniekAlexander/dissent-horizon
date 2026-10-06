extends GutTest

## A steered weapon aims at the centre of a piece's hurtbox (Entity.aim_point), which stands ON
## the piece's base — the importer fits it there (test_VisualDefaults), so its centre is above
## the feet rather than at them.
## See gdd/systems/combat/projectiles.md §A rocket aims at the hurtbox.
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
	return a_piece.hurtbox.get_node("HurtboxShape") as CollisionShape3D


func test_a_steered_weapon_aims_at_the_hurtbox_centre() -> void:
	var unit: Commandable = _unit_at(Vector3(3.0, 0.0, 2.0))
	assert_eq(unit.aim_point(), _target_shape(unit).global_position)
	assert_gt(unit.aim_point().y, unit.global_position.y, "above the ground, not at the feet")


func test_a_piece_without_a_hurtbox_is_aimed_at_its_origin() -> void:
	var marker: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	marker.add_child(ownership)
	add_child_autofree(marker)
	marker.global_position = Vector3(1.0, 2.0, 3.0)
	assert_eq(marker.aim_point(), marker.global_position)


func test_a_steered_phase_arrives_at_the_hurtbox_centre_not_the_feet() -> void:
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
