extends GutTest

## A crowd is never truncated: the nearby-enemy query counts every targetable body in its radius,
## own pieces included, and at its old ceiling of ten it silently dropped enemies in plain view
## in any real fight. The live symptom, measured by a self-play probe on 2026-10-07: a third of
## the enemies a bot could see were missing from its senses, and a unit killed in sight was
## believed alive for the blackboard's whole expiry window.

## Bodies packed into one radius: more than the old ceiling, fewer than the new one.
const CROWD: int = 24
const RADIUS: float = 6.0


func test_every_body_in_a_crowd_is_returned() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	for i: int in CROWD:
		var piece: Actor = FakePieces.unit()
		root.add_child(piece)
		piece.global_position = Vector3(i % 5, 0.0, i / 5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var found: Array = SU.get_nearby_entities(
		root.get_world_3d(),
		Vector3(2.0, 0.0, 2.0),
		RADIUS,
		CollisionLayers.TARGETABLE_ANY,
		Commander.NEARBY_MAX_RESULTS
	)
	var distinct: Dictionary = {}
	for e: Entity in found:
		distinct[e] = true
	assert_eq(distinct.size(), CROWD)
	assert_gt(Commander.NEARBY_MAX_RESULTS, CROWD)
