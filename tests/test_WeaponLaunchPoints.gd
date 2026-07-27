extends GutTest

## Where a weapon's emissions leave from: its Marker3D launch points walked as a ring, or its
## own position; a turret's weapon in the turret's frame. See
## gdd/systems/combat/projectiles.md §Where an emission leaves from.

const TOLERANCE: Vector3 = Vector3.ONE * 0.001
const CARRIER_AT: Vector3 = Vector3(10, 0, 5)
const WEAPON_AT: Vector3 = Vector3(0, 0.5, 0.3)

var _carrier: Node3D
var _weapon: Weapon


func before_each() -> void:
	_carrier = Node3D.new()
	add_child_autofree(_carrier)
	_carrier.position = CARRIER_AT
	_weapon = Weapon.new()
	_weapon.position = WEAPON_AT
	_carrier.add_child(_weapon)


func _marker(a_at: Vector3) -> Marker3D:
	var marker: Marker3D = Marker3D.new()
	marker.position = a_at
	_weapon.add_child(marker)
	return marker


func test_without_launch_points_the_weapon_itself_launches() -> void:
	assert_almost_eq(_weapon.next_launch_position(), CARRIER_AT + WEAPON_AT, TOLERANCE)
	assert_almost_eq(_weapon.next_launch_position(), CARRIER_AT + WEAPON_AT, TOLERANCE,
		"every time")


func test_launch_points_are_walked_as_a_ring() -> void:
	var offsets: Array[Vector3] = [Vector3(-0.2, 0, 0), Vector3(0, 0, 0.1), Vector3(0.2, 0, 0)]
	for offset: Vector3 in offsets:
		_marker(offset)
	var seen: Array[Vector3] = []
	for i: int in offsets.size() + 1:
		seen.append(_weapon.next_launch_position())
	for i: int in offsets.size():
		assert_almost_eq(seen[i], CARRIER_AT + WEAPON_AT + offsets[i], TOLERANCE)
	assert_almost_eq(seen[offsets.size()], seen[0], TOLERANCE, "and wraps round")


func test_only_markers_are_launch_points() -> void:
	var range_shape: CollisionShape3D = CollisionShape3D.new()
	range_shape.name = "AttackRange"
	_weapon.add_child(range_shape)
	assert_true(_weapon.launch_points().is_empty(), "a range shape is not a tube")


func test_launch_points_turn_with_the_carrier() -> void:
	_carrier.rotation.y = PI / 2.0
	# Forward is +Z; a quarter turn about Y carries +Z onto +X.
	assert_almost_eq(_weapon.next_launch_position(),
		CARRIER_AT + Vector3(WEAPON_AT.z, WEAPON_AT.y, 0.0), TOLERANCE)


func test_a_scaled_weapon_places_its_points_in_world_units() -> void:
	# A weapon's basis carries its range shapes' scale; its launch points ignore it.
	_weapon.scale = Vector3(0.2, 2.5, 0.5)
	_marker(Vector3(0.3, 0, 0))
	assert_almost_eq(_weapon.next_launch_position(),
		CARRIER_AT + WEAPON_AT + Vector3(0.3, 0, 0), TOLERANCE)


func test_a_turret_without_a_model_turns_its_weapon_by_its_yaw() -> void:
	_weapon.turret = true
	_weapon.turret_yaw = PI / 2.0
	assert_almost_eq(_weapon.next_launch_position(),
		CARRIER_AT + Vector3(WEAPON_AT.z, WEAPON_AT.y, 0.0), TOLERANCE)


func test_a_turret_model_is_the_frame() -> void:
	var turret_model: Node3D = Node3D.new()
	_carrier.add_child(turret_model)
	turret_model.position = Vector3(0, 0.4, 0)
	turret_model.scale = Vector3.ONE * 0.45
	turret_model.rotation.y = PI / 2.0
	_weapon._turret_visual = turret_model
	assert_almost_eq(_weapon.next_launch_position(),
		CARRIER_AT + Vector3(0, 0.4, 0) + Vector3(WEAPON_AT.z, WEAPON_AT.y, 0.0), TOLERANCE,
		"the barrel's frame, in world units")


func test_launching_from_the_origin_is_detected() -> void:
	assert_false(_weapon.launches_from_origin())
	_weapon.position = Vector3.ZERO
	assert_true(_weapon.launches_from_origin())
	_marker(Vector3(0, 0.5, 0))
	assert_false(_weapon.launches_from_origin(), "launch points supply the offset")
	_marker(Vector3.ZERO)
	assert_true(_weapon.launches_from_origin(), "unless one of them sits on the origin too")
