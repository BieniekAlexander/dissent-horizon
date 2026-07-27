extends GutTest

## A rocket's wobble turns its heading, never its speed; it builds after launch, stays within
## its authored angle, and is absent from a phase without it. See
## gdd/systems/combat/projectiles.md §Jitter.

const MID_FLIGHT_SECONDS: float = 1.0
const VELOCITY: Vector3 = Vector3(0.5, 0.0, 0.2)

var _phase: EmissionPhase
var _jitter: EmissionJitter


func before_each() -> void:
	_phase = EmissionPhase.new()
	autofree(_phase)
	_phase.speed = 15.0
	_phase.jitter_degrees = 4.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	_jitter = EmissionJitter.new(rng)


func test_it_turns_the_heading_and_keeps_the_speed() -> void:
	for i: int in 60:
		var turned: Vector3 = _jitter.perturbed(_phase, MID_FLIGHT_SECONDS + i * 0.05, VELOCITY)
		assert_almost_eq(turned.length(), VELOCITY.length(), 0.00001)
		assert_lte(rad_to_deg(turned.angle_to(VELOCITY)), _phase.jitter_degrees * sqrt(2.0) + 0.001,
			"within the authored angle on each axis")


func test_a_shot_leaves_the_tube_clean() -> void:
	assert_eq(_jitter.perturbed(_phase, 0.0, VELOCITY), VELOCITY)


func test_it_actually_wobbles() -> void:
	assert_ne(_jitter.perturbed(_phase, MID_FLIGHT_SECONDS, VELOCITY),
		_jitter.perturbed(_phase, MID_FLIGHT_SECONDS + 0.2, VELOCITY))


func test_a_phase_without_jitter_flies_clean() -> void:
	_phase.jitter_degrees = 0.0
	assert_eq(_jitter.perturbed(_phase, MID_FLIGHT_SECONDS, VELOCITY), VELOCITY)
	_phase.jitter_degrees = 4.0
	_phase.speed = 0.0
	assert_eq(_jitter.perturbed(_phase, MID_FLIGHT_SECONDS, VELOCITY), VELOCITY,
		"a motionless phase does not wobble")
