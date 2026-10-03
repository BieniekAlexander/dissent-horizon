extends GutTest

## Whether an emission damages an AREA or only the thing it was aimed at: exactly when it
## carries a HitShape, which only a non-hitscan emission has. The importer removes a hitscan
## emission's HitShape, and the Payload reads presence alone (Payload.has_blast).
##
## The rule once had to be "hitscan wins, and a DISABLED shape counts as none", because every
## emission inherited a HitShape it could not remove — and before that, an assertion on the
## combination crashed the game the moment a hitscan emission fired. Both are covered below on
## fake emissions (tests/_fake_pieces.gd), not on any shipped piece.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ProjectileBlast.gd -gexit


func _payload_of(a_options: Dictionary) -> Payload:
	var emission: Entity = FakePieces.emission(a_options)
	add_child_autofree(emission)
	return Payload.of(emission)


func test_a_hitscan_emission_can_be_instantiated_and_has_no_blast() -> void:
	# Entering the tree runs _ready — the crash, reduced.
	var payload: Payload = _payload_of({"hitscan": true, "hit_shape": false})
	assert_true(payload.hitscan)
	assert_null(payload.hit_shape(), "it carries no HitShape")
	assert_false(payload.has_blast(), "so it resolves onto its target alone")


func test_a_non_hitscan_emission_with_a_shape_has_a_blast() -> void:
	var shell: Payload = _payload_of({"hitscan": false, "hit_shape": true})
	assert_false(shell.hitscan, "a shell is not hitscan")
	assert_true(shell.has_blast(), "so its shape is its blast")


#region The blast is measured at the contact
## A target that runs a fixed step every physics tick.
class Runner:
	extends Entity
	var step: Vector3 = Vector3.ZERO

	func _physics_process(_a_delta: float) -> void:
		global_position += step


func _runner(a_position: Vector3, a_speed: float) -> Runner:
	var runner: Runner = Runner.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	runner.add_child(ownership)
	var defense: Defense = Defense.new()
	defense.name = "Defense"
	defense.hp_max = 1000.0
	runner.add_child(defense)
	var body: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE
	body.shape = box
	runner.add_child(body)
	runner.collision_layer = CollisionLayers.Mask.TARGETABLE_GROUND
	add_child_autofree(runner)
	runner.global_position = a_position
	runner.step = Vector3(a_speed / TimeUtils.ticks_per_second(), 0.0, 0.0)
	return runner


## A straight free-flying rocket whose blast is far smaller than one tick of the runner's motion.
func _small_blast_rocket() -> Entity:
	var rocket: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	rocket.add_child(ownership)
	var hit: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.1
	hit.shape = sphere
	hit.name = "HitShape"
	rocket.add_child(hit)
	var flight: EmissionPhase = EmissionPhase.new()
	flight.speed = 30.0
	flight.lifespan_seconds = 2.0
	rocket.add_child(flight)
	var burst: EmissionPhase = EmissionPhase.new()
	burst.ends_on_arrival = false
	burst.lifespan_seconds = 0.0
	burst.applies_payload = true
	rocket.add_child(burst)
	var locomotion: PhasedLocomotion = PhasedLocomotion.new()
	locomotion.name = "Locomotion"
	rocket.add_child(locomotion)
	var payload: Payload = Payload.new()
	payload.name = "Payload"
	payload.base_damage = 50.0
	rocket.add_child(payload)
	return rocket


func test_a_target_struck_by_a_blast_takes_it_even_after_moving_out_of_it() -> void:
	# The runner moves 0.2 a tick, away from the rocket: by the tick the burst pays out it has
	# left a 0.1 blast centred where the rocket struck it. The contact's tick decides.
	var runner: Runner = _runner(Vector3(4.0, 0.0, 0.0), 6.0)
	await get_tree().physics_frame
	var rocket: Entity = _small_blast_rocket()
	add_child(rocket)
	rocket.global_position = Vector3.ZERO
	Emitter.launch(rocket, null, runner)
	var ticks: int = 0
	while is_instance_valid(rocket) and ticks < 120:
		await get_tree().physics_frame
		ticks += 1
	if is_instance_valid(rocket):
		rocket.queue_free()
	assert_lt(runner.defense.hp, runner.defense.hp_max, "the piece it struck took the blast")

#endregion
