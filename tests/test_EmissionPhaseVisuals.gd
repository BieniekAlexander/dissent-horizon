extends GutTest

## How a phase shows its visuals: a particle effect is switched by `emitting` alone, so what it
## emitted lives out after its phase ends; a mesh is shown and hidden. And a phase that does not
## move stands its emission upright. See gdd/systems/combat/projectiles.md §Visuals.

const TOLERANCE: float = 0.001

var _emission: Node3D


func before_each() -> void:
	_emission = Node3D.new()
	add_child_autofree(_emission)


func _phase_showing(a_names: Array[String]) -> EmissionPhase:
	var phase: EmissionPhase = EmissionPhase.new()
	autofree(phase)
	var paths: Array[NodePath] = []
	for n: String in a_names:
		paths.append(NodePath(n))
	phase.visuals = paths
	return phase


func _effect(a_name: String) -> GPUParticles3D:
	# An effect scene's shape: a plain root holding its particle systems.
	var root: Node3D = Node3D.new()
	root.name = a_name
	_emission.add_child(root)
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	root.add_child(particles)
	return particles


func test_a_particle_effect_is_switched_by_emitting_and_never_hidden() -> void:
	var particles: GPUParticles3D = _effect("Trail")
	var phase: EmissionPhase = _phase_showing(["Trail"])
	phase.show_visuals(_emission, true)
	assert_true(particles.emitting)
	phase.show_visuals(_emission, false)
	assert_false(particles.emitting, "it stops making more")
	assert_true(
		(_emission.get_node("Trail") as Node3D).visible,
		"but what it already emitted stays on screen"
	)
	assert_true(particles.visible)


func test_a_mesh_is_shown_and_hidden() -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Model"
	_emission.add_child(mesh)
	var phase: EmissionPhase = _phase_showing(["Model"])
	phase.show_visuals(_emission, false)
	assert_false(mesh.visible)
	phase.show_visuals(_emission, true)
	assert_true(mesh.visible)


func test_only_a_phase_that_goes_nowhere_is_motionless() -> void:
	var phase: EmissionPhase = EmissionPhase.new()
	autofree(phase)
	assert_true(phase.is_motionless())
	phase.speed = 10.0
	assert_false(phase.is_motionless())
	phase.speed = 0.0
	phase.gravity_mps2 = 4.5
	assert_false(phase.is_motionless(), "a falling phase is carried by gravity")


func test_levelling_keeps_the_heading_and_drops_the_pitch() -> void:
	# Pointing down and to the east, as a shell arriving on a slant would.
	_emission.look_at(_emission.global_position + Vector3(1, -2, 0), Vector3.UP)
	PhasedLocomotion._level(_emission)
	assert_almost_eq(_emission.global_basis.y, Vector3.UP, Vector3.ONE * TOLERANCE, "upright")
	assert_almost_eq(
		-_emission.global_basis.z, Vector3.RIGHT, Vector3.ONE * TOLERANCE, "still facing east"
	)


func test_levelling_a_straight_drop_falls_back_to_the_world_frame() -> void:
	_emission.look_at(_emission.global_position + Vector3.DOWN, Vector3.FORWARD)
	PhasedLocomotion._level(_emission)
	assert_true(_emission.global_basis.is_equal_approx(Basis.IDENTITY))


## Comfortably past a delay short enough for a test to wait out.
const SHORT_DELAY_SECONDS: float = 0.05
const PAST_DELAY_SECONDS: float = 0.15


func _delayed(a_name: String) -> EmissionParticles:
	var particles: EmissionParticles = EmissionParticles.new()
	particles.name = a_name
	particles.emitting = false
	particles.start_delay_seconds = SHORT_DELAY_SECONDS
	_emission.add_child(particles)
	return particles


func test_a_delayed_system_starts_a_moment_after_its_phase() -> void:
	var smoke: EmissionParticles = _delayed("Smoke")
	_phase_showing(["Smoke"]).show_visuals(_emission, true)
	assert_false(smoke.emitting, "not on the launch frame")
	await get_tree().create_timer(PAST_DELAY_SECONDS).timeout
	assert_true(smoke.emitting)


func test_a_stop_before_the_delay_cancels_the_start() -> void:
	var smoke: EmissionParticles = _delayed("Smoke")
	var phase: EmissionPhase = _phase_showing(["Smoke"])
	phase.show_visuals(_emission, true)
	phase.show_visuals(_emission, false)
	await get_tree().create_timer(PAST_DELAY_SECONDS).timeout
	assert_false(smoke.emitting, "a phase that already ended never starts it")


## Two flight stages sharing a mesh, and a burst with its own: whichever phase is live, the visuals
## it names are up — a later phase naming the same mesh must not hide it during an earlier one.
func _staged_emission() -> Entity:
	var emission: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	emission.add_child(ownership)
	for mesh_name: String in ["InFlightMesh", "PostImpactMesh"]:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = mesh_name
		emission.add_child(mesh)
	var flight: Array[NodePath] = [NodePath("InFlightMesh")]
	var burst: Array[NodePath] = [NodePath("PostImpactMesh")]
	for visuals: Array[NodePath] in [flight, flight, burst]:
		var phase: EmissionPhase = EmissionPhase.new()
		phase.speed = 10.0
		phase.lifespan_seconds = 1.0
		phase.visuals = visuals
		emission.add_child(phase)
	var locomotion: PhasedLocomotion = PhasedLocomotion.new()
	locomotion.name = "Locomotion"
	emission.add_child(locomotion)
	add_child_autofree(emission)
	return emission


func test_a_mesh_shared_by_two_stages_shows_through_both() -> void:
	var emission: Entity = _staged_emission()
	var locomotion: PhasedLocomotion = emission.get_node("Locomotion") as PhasedLocomotion
	var flight_mesh: Node3D = emission.get_node("InFlightMesh") as Node3D
	var burst_mesh: Node3D = emission.get_node("PostImpactMesh") as Node3D
	locomotion._show_visuals_of(0)
	assert_true(flight_mesh.visible, "the first stage shows it, though the second names it too")
	assert_false(burst_mesh.visible)
	locomotion._show_visuals_of(1)
	assert_true(flight_mesh.visible, "still up in the second stage")
	locomotion._show_visuals_of(2)
	assert_false(flight_mesh.visible, "hidden at the burst")
	assert_true(burst_mesh.visible)
