extends GutTest

## ImplosionParticles: the flakes hang while the gathering phase runs, entering the phase it
## names as `collapse_phase` pulls them into the centre hard enough that a flake starting at the
## field's edge arrives as that phase ends, and entering `burst_phase` throws them back out.
## Driven on a fake emission's real phase sequence.
## Rules: gdd/factions/colonial/sanctions/cryogenic_implosion.md §Mechanic.
##
## Run with:
##   python3 tools/gut_shards/gut_shards.py ImplosionParticles

const GATHER_SECONDS: float = 0.2
const COLLAPSE_SECONDS: float = 0.5
const BURST_SECONDS: float = 0.3
const FIELD_RADIUS: float = 4.0
## Ticks of headroom past a phase boundary before a wait gives up.
const SLACK_TICKS: int = 10


## A motionless emission: gather, collapse, burst — the particles naming the last two.
func _emission() -> Entity:
	var host := Entity.new()
	var ownership := Ownership.new()
	ownership.name = "Ownership"
	host.add_child(ownership)
	var flakes := ImplosionParticles.new()
	flakes.name = "Flakes"
	flakes.process_material = ParticleProcessMaterial.new()
	flakes.radius = FIELD_RADIUS
	flakes.collapse_phase = NodePath("Collapse")
	flakes.burst_phase = NodePath("Burst")
	host.add_child(flakes)
	for spec: Array in [
		["Gather", GATHER_SECONDS], ["Collapse", COLLAPSE_SECONDS], ["Burst", BURST_SECONDS]
	]:
		var phase := EmissionPhase.new()
		phase.name = spec[0]
		phase.ends_on_arrival = false
		phase.lifespan_seconds = spec[1]
		host.add_child(phase)
	var locomotion := PhasedLocomotion.new()
	locomotion.name = "Locomotion"
	host.add_child(locomotion)
	return host


func _flakes(a_host: Entity) -> ImplosionParticles:
	return a_host.get_node("Flakes") as ImplosionParticles


func _wait_for_phase(a_host: Entity, a_name: String) -> void:
	var phased := a_host.get_node("Locomotion") as PhasedLocomotion
	var total: float = GATHER_SECONDS + COLLAPSE_SECONDS + BURST_SECONDS
	var budget: int = roundi(total * TimeUtils.ticks_per_second())
	for _i: int in budget + SLACK_TICKS:
		var phase: EmissionPhase = phased.current_phase()
		if phase != null and phase.name == a_name:
			return
		await get_tree().physics_frame


func _launched() -> Entity:
	var host: Entity = _emission()
	add_child_autofree(host)
	Emitter.launch(host, null, Vector3.ZERO)
	return host


func test_flakes_hang_while_the_field_gathers() -> void:
	var host: Entity = _launched()
	await _wait_for_phase(host, "Gather")
	assert_false(_flakes(host).is_collapsing())


func test_entering_the_collapse_phase_pulls_every_flake_to_the_centre() -> void:
	var host: Entity = _launched()
	await _wait_for_phase(host, "Collapse")
	var material := _flakes(host).process_material as ParticleProcessMaterial
	assert_true(_flakes(host).is_collapsing())
	# From rest, radius = ½·a·t²: the pull that lands an edge flake as the phase ends.
	var expected: float = 2.0 * FIELD_RADIUS / (COLLAPSE_SECONDS * COLLAPSE_SECONDS)
	assert_almost_eq(-material.radial_accel_max, expected, 0.001)
	assert_false(_flakes(host).emitting, "no new flakes appear once it collapses")


func test_entering_the_burst_phase_throws_the_flakes_back_out() -> void:
	var host: Entity = _launched()
	await _wait_for_phase(host, "Burst")
	assert_true(_flakes(host).is_bursting())
	assert_false(_flakes(host).is_collapsing())


func test_each_field_collapses_its_own_material() -> void:
	var shared := ParticleProcessMaterial.new()
	var first: Entity = _emission()
	var second: Entity = _emission()
	_flakes(first).process_material = shared
	_flakes(second).process_material = shared
	add_child_autofree(first)
	add_child_autofree(second)
	_flakes(first).collapse(COLLAPSE_SECONDS)
	assert_false(_flakes(second).is_collapsing(), "a field's collapse is its own")
