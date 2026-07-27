extends GutTest

## A non-hitscan emission flies FREE: it stops only at the piece it was aimed at or at the
## ground, flies through anything else, can miss, and aims at the ground under a BIO target.
## See gdd/systems/combat/projectiles.md §Free flight.

const MAX_TICKS: int = 120
const LAUNCH: Vector3 = Vector3(0.0, 0.5, 0.0)
const TARGET_AT: Vector3 = Vector3(6.0, 0.0, 0.0)
const BYSTANDER_AT: Vector3 = Vector3(3.0, 0.0, 0.0)
const MOVED_TO: Vector3 = Vector3(6.0, 0.0, 5.0)
const SPEED_MPS: float = 30.0
const TOLERANCE: float = 0.6


## Records where each payout happened instead of applying it.
class RecordingPayload extends Payload:
	var hits: Array[Vector3] = []

	func apply() -> void:
		hits.append(host().global_position)


func _emission(a_jitter_degrees: float = 0.0) -> Entity:
	var emission: Entity = Entity.new()
	var payload: RecordingPayload = RecordingPayload.new()
	payload.name = "Payload"
	emission.add_child(payload)
	var blast: CollisionShape3D = CollisionShape3D.new()
	blast.name = "HitShape"
	blast.shape = SphereShape3D.new()
	emission.add_child(blast)
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	emission.add_child(ownership)
	var locomotion: PhasedLocomotion = PhasedLocomotion.new()
	locomotion.name = "Locomotion"
	emission.add_child(locomotion)
	var flight: EmissionPhase = EmissionPhase.new()
	flight.speed = SPEED_MPS
	flight.lifespan_seconds = 2.0
	flight.jitter_degrees = a_jitter_degrees
	emission.add_child(flight)
	var impact: EmissionPhase = EmissionPhase.new()
	impact.ends_on_arrival = false
	impact.lifespan_seconds = 0.0
	impact.applies_payload = true
	emission.add_child(impact)
	return emission


## A piece as the game builds one: an Entity whose targetable volume is a TargetBody child.
func _piece(a_at: Vector3, a_frame: Defense.FrameType = Defense.FrameType.MECH) -> Entity:
	var piece: Entity = Entity.new()
	piece.collision_layer = 0
	piece.position = a_at
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	piece.add_child(ownership)
	var defense: Defense = Defense.new()
	defense.name = "Defense"
	defense.frame_type = a_frame
	piece.add_child(defense)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TargetBody"
	body.collision_layer = CollisionLayers.Mask.TARGETABLE_GROUND
	body.add_child(_box(Vector3.ONE))
	piece.add_child(body)
	add_child_autofree(piece)
	return piece


## Move `a_piece` for the physics server too: a StaticBody3D child follows its parent's
## transform only at the next sync, so a test that moves a target reads the body directly.
static func _move(a_piece: Entity, a_to: Vector3) -> void:
	a_piece.global_position = a_to
	(a_piece.get_node("TargetBody") as StaticBody3D).global_position = a_to


func _ground() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = CollisionLayers.Mask.TERRAIN
	ground.add_child(_box(Vector3(40.0, 1.0, 40.0)))
	add_child_autofree(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)


static func _box(a_size: Vector3) -> CollisionShape3D:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = a_size
	shape.shape = box
	return shape


## Launches from LAUNCH at `a_target`, calls `a_after_launch` once, and returns where it paid out.
func _fly(a_emission: Entity, a_target: Variant, a_after_launch: Callable = Callable()) -> Array:
	var payload: RecordingPayload = a_emission.get_node("Payload")
	add_child(a_emission)
	a_emission.global_position = LAUNCH
	Emitter.launch(a_emission, null, a_target)
	if a_after_launch.is_valid():
		a_after_launch.call()
	var hits: Array[Vector3] = payload.hits
	var ticks: int = 0
	while is_instance_valid(a_emission) and ticks < MAX_TICKS:
		await get_tree().physics_frame
		ticks += 1
	if is_instance_valid(a_emission):
		a_emission.queue_free()
	return hits


func test_a_shot_at_a_piece_flies_through_bystanders_and_stops_at_it() -> void:
	_ground()
	_piece(BYSTANDER_AT)
	var target: Entity = _piece(TARGET_AT)
	await get_tree().physics_frame
	var hits: Array = await _fly(_emission(), target)
	assert_eq(hits.size(), 1)
	assert_almost_eq(hits[0].x, TARGET_AT.x, TOLERANCE, "at the target, not the bystander")


func test_a_shot_at_a_piece_that_moved_misses_and_lands_on_the_ground() -> void:
	_ground()
	var target: Entity = _piece(TARGET_AT)
	await get_tree().physics_frame
	var hits: Array = await _fly(_emission(), target, func() -> void:
		_move(target, MOVED_TO))
	assert_eq(hits.size(), 1, "it still bursts")
	assert_almost_eq(hits[0].z, 0.0, TOLERANCE,
		"unsteered, it lands where it was aimed, not on the target that left")
	assert_almost_eq(hits[0].y, 0.0, 0.05, "on the ground")


func test_a_shot_at_the_ground_ignores_every_piece() -> void:
	_ground()
	_piece(BYSTANDER_AT)
	await get_tree().physics_frame
	var hits: Array = await _fly(_emission(), TARGET_AT)
	assert_eq(hits.size(), 1)
	assert_almost_eq(hits[0].x, TARGET_AT.x, TOLERANCE, "flew through the piece in its way")


func test_a_bio_target_is_aimed_at_the_ground_under_it() -> void:
	var soldier: Entity = _piece(TARGET_AT, Defense.FrameType.BIO)
	var emission: Entity = _emission()
	(emission.get_node("Payload") as Payload).bio_ground_aim = true
	add_child_autofree(emission)
	emission.global_position = LAUNCH
	Emitter.launch(emission, null, soldier)
	var locomotion: PhasedLocomotion = emission.get_node("Locomotion")
	assert_null(locomotion.goal_entity(), "nothing is pursued")
	assert_almost_eq(locomotion.goal_position, TARGET_AT, Vector3.ONE * 0.001,
		"the spot it stood on")
	assert_null((emission.get_node("Payload") as Payload).target)


func test_a_mech_target_is_still_pursued() -> void:
	var tank: Entity = _piece(TARGET_AT, Defense.FrameType.MECH)
	var emission: Entity = _emission()
	(emission.get_node("Payload") as Payload).bio_ground_aim = true
	add_child_autofree(emission)
	emission.global_position = LAUNCH
	Emitter.launch(emission, null, tank)
	assert_eq((emission.get_node("Locomotion") as PhasedLocomotion).goal_entity(), tank)


func test_the_same_seed_flies_the_same_wobble() -> void:
	_ground()
	var paths: Array = []
	for attempt: int in 2:
		SU.rng.seed = 42
		paths.append(await _fly(_emission(6.0), TARGET_AT + Vector3(8.0, 0, 0)))
	assert_eq(paths[0], paths[1], "deterministic from the gameplay seed")
