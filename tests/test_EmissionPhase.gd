extends GutTest

## One emission phase's motion maths and period conversions, on a bare EmissionPhase: the
## launch solve, the per-tick steering and gravity, and the arrival test each motion uses.
## See gdd/systems/combat/projectiles.md §Phases.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_EmissionPhase.gd -gdir=res://tests/none -gexit

const ORIGIN: Vector3 = Vector3(0.0, 1.0, 0.0)
const DESTINATION: Vector3 = Vector3(12.0, 0.0, 5.0)
## Far more ticks than any flight here needs; a flight still going after this has failed.
const MAX_FLIGHT_TICKS: int = 2000
const FLOAT_TOLERANCE: float = 0.001


func _phase(a_values: Dictionary) -> EmissionPhase:
	var phase: EmissionPhase = EmissionPhase.new()
	for key: String in a_values:
		phase.set(key, a_values[key])
	autofree(phase)
	return phase


func _preset_phase(a_preset: String, a_speed: float) -> EmissionPhase:
	var values: Dictionary = {"speed": a_speed}
	var names: Dictionary = {
		"gravity": "gravity_mps2",
		"launch_pitch": "launch_pitch_degrees",
		"turn_rate": "turn_rate_degrees_per_second",
		"launch_speed_ratio": "launch_speed_ratio",
		"acceleration": "acceleration_mps2",
		"min_speed": "min_speed"
	}
	var preset: Dictionary = EmissionPhase.PRESETS[a_preset]
	for key: String in preset:
		values[names[key]] = preset[key]
	return _phase(values)


## A bare entity standing at `a_position`, in the tree so it has a global position.
func _target_at(a_position: Vector3) -> Entity:
	var entity: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	entity.add_child(ownership)
	add_child_autofree(entity)
	entity.global_position = a_position
	return entity


## Flies `a_phase` from ORIGIN at DESTINATION until it arrives; returns where and when.
func _fly(a_phase: EmissionPhase, a_target: Entity = null) -> Dictionary:
	var position: Vector3 = ORIGIN
	var velocity: Vector3 = a_phase.launch_velocity(ORIGIN, DESTINATION)
	for tick: int in MAX_FLIGHT_TICKS:
		if a_phase.has_arrived(position, velocity, DESTINATION, a_target):
			return {"position": position, "ticks": tick, "arrived": true}
		velocity = a_phase.steered_velocity(velocity, position, a_target)
		position += velocity
		velocity = a_phase.fallen_velocity(velocity)
	return {"position": position, "ticks": MAX_FLIGHT_TICKS, "arrived": false}


func test_the_defaults_are_a_straight_constant_speed_flight() -> void:
	var phase: EmissionPhase = _phase({"speed": 30.0})
	var launch: Vector3 = phase.launch_velocity(ORIGIN, DESTINATION)
	assert_almost_eq(
		launch.length(),
		30.0 / TimeUtils.ticks_per_second(),
		FLOAT_TOLERANCE,
		"launches at full speed, per tick"
	)
	assert_almost_eq(
		launch.normalized().dot(ORIGIN.direction_to(DESTINATION)),
		1.0,
		FLOAT_TOLERANCE,
		"straight at the destination"
	)
	assert_eq(phase.fallen_velocity(launch), launch, "no gravity")
	assert_eq(phase.steered_velocity(launch, ORIGIN, null), launch, "no steering")
	assert_true(phase.is_straight())
	var flight: Dictionary = _fly(phase)
	assert_true(flight["arrived"], "arrives")
	assert_almost_eq(
		flight["position"].distance_to(DESTINATION),
		0.0,
		30.0 / TimeUtils.ticks_per_second(),
		"within one step of the destination"
	)


func test_a_ballistic_arc_lands_on_its_destination() -> void:
	var flight: Dictionary = _fly(_preset_phase("BALLISTIC", 9.0))
	assert_true(flight["arrived"], "lands")
	var landed: Vector3 = flight["position"]
	assert_almost_eq(
		Vector2(landed.x, landed.z).distance_to(Vector2(DESTINATION.x, DESTINATION.z)),
		0.0,
		9.0 / TimeUtils.ticks_per_second(),
		"over the destination"
	)
	assert_lt(landed.y, DESTINATION.y + FLOAT_TOLERANCE, "at or below its height")


func test_a_ballistic_shot_at_its_own_position_lands_next_tick() -> void:
	# Zero ticks to target used to divide by zero and fly a NaN forever.
	var phase: EmissionPhase = _preset_phase("BALLISTIC", 9.0)
	var launch: Vector3 = phase.launch_velocity(ORIGIN, ORIGIN)
	assert_false(is_nan(launch.y), "a finite launch")


func test_a_lob_leaves_at_its_pitch_and_lands_on_its_destination() -> void:
	var phase: EmissionPhase = _preset_phase("LOFTED", 9.0)
	var launch: Vector3 = phase.launch_velocity(ORIGIN, DESTINATION)
	# The first tick's fall is folded into the launch; take it back out to read the pitch.
	var fall: float = phase.gravity_mps2 / float(TimeUtils.ticks_per_second() ** 2)
	var rise: float = launch.y + fall
	var pitch: float = rad_to_deg(atan2(rise, Vector2(launch.x, launch.z).length()))
	assert_gt(pitch, EmissionPhase.LOFTED_PITCH_DEGREES - 5.0, "steep, near its pitch")
	var flight: Dictionary = _fly(phase)
	assert_true(flight["arrived"], "lands")
	var landed: Vector3 = flight["position"]
	assert_lt(
		Vector2(landed.x, landed.z).distance_to(Vector2(DESTINATION.x, DESTINATION.z)),
		0.5,
		"over the destination"
	)


func test_a_lob_too_steep_for_its_target_falls_back_to_an_arc() -> void:
	var phase: EmissionPhase = _preset_phase("LOFTED", 9.0)
	phase.launch_pitch_degrees = 1.0
	var high: Vector3 = Vector3(12.0, 40.0, 5.0)
	var launch: Vector3 = phase.launch_velocity(ORIGIN, high)
	assert_almost_eq(
		Vector2(launch.x, launch.z).length(),
		9.0 / TimeUtils.ticks_per_second(),
		FLOAT_TOLERANCE,
		"flown at its authored speed instead"
	)


func test_a_homer_launches_slow_and_speeds_up_while_facing_its_target() -> void:
	var phase: EmissionPhase = _preset_phase("HOMING", 24.0)
	var entity: Entity = _target_at(DESTINATION)
	var launch: Vector3 = phase.launch_velocity(ORIGIN, DESTINATION)
	var full: float = 24.0 / TimeUtils.ticks_per_second()
	assert_almost_eq(launch.length(), full * 0.5, FLOAT_TOLERANCE, "half speed at launch")
	# A target straight ahead: steering only accelerates.
	var steered: Vector3 = phase.steered_velocity(launch, ORIGIN, entity)
	assert_gt(steered.length(), launch.length(), "gains speed while facing")
	assert_lt(steered.length(), full + FLOAT_TOLERANCE, "never past full speed")


func test_a_homer_turns_at_most_its_turn_rate_per_tick() -> void:
	var phase: EmissionPhase = _preset_phase("HOMING", 24.0)
	var entity: Entity = _target_at(Vector3(0.0, 1.0, 10.0))
	var heading: Vector3 = Vector3(0.1, 0.0, 0.0)
	var steered: Vector3 = phase.steered_velocity(heading, ORIGIN, entity)
	var turned: float = rad_to_deg(heading.angle_to(steered))
	assert_almost_eq(
		turned,
		phase.turn_rate_degrees_per_second / TimeUtils.ticks_per_second(),
		FLOAT_TOLERANCE,
		"one tick of turn"
	)


func test_a_homer_without_a_target_never_arrives() -> void:
	var phase: EmissionPhase = _preset_phase("HOMING", 24.0)
	assert_false(
		phase.has_arrived(DESTINATION, Vector3.ZERO, DESTINATION, null),
		"its lifespan ends it instead"
	)


func test_periods_convert_to_ticks_with_a_one_tick_floor() -> void:
	var phase: EmissionPhase = _phase({})
	assert_eq(phase.duration_ticks(), -1, "INF is unbounded")
	phase.lifespan_seconds = 0.0
	assert_eq(phase.duration_ticks(), 1, "a phase always runs a tick")
	phase.lifespan_seconds = 1.0
	assert_eq(phase.duration_ticks(), TimeUtils.ticks_per_second())
	phase.payload_period_seconds = 0.5
	assert_eq(phase.payload_period_ticks(), TimeUtils.ticks_per_second() / 2)


# --- Burn-out ----------------------------------------------------------------------------


func test_a_phase_flies_at_full_speed_until_it_burns_out() -> void:
	var phase: EmissionPhase = _phase({"speed": 15.0, "burn_seconds": 0.5, "coast_speed": 6.0})
	var velocity: Vector3 = Vector3(15.0 / TimeUtils.ticks_per_second(), 0.0, 0.0)
	assert_eq(phase.burnt_velocity(velocity, 0.4), velocity, "still burning")


func test_a_burnt_out_phase_is_held_to_its_coast_speed() -> void:
	var phase: EmissionPhase = _phase({"speed": 15.0, "burn_seconds": 0.5, "coast_speed": 6.0})
	var velocity: Vector3 = Vector3(0.0, 0.0, 15.0 / TimeUtils.ticks_per_second())
	var burnt: Vector3 = phase.burnt_velocity(velocity, 0.5)
	assert_almost_eq(
		burnt.length(), 6.0 / TimeUtils.ticks_per_second(), FLOAT_TOLERANCE, "coast speed"
	)
	assert_almost_eq(burnt.normalized(), velocity.normalized(), Vector3.ONE * FLOAT_TOLERANCE)


func test_burning_out_never_speeds_a_slow_emission_up() -> void:
	var phase: EmissionPhase = _phase({"speed": 15.0, "burn_seconds": 0.5, "coast_speed": 6.0})
	var slow: Vector3 = Vector3(2.0 / TimeUtils.ticks_per_second(), 0.0, 0.0)
	assert_eq(phase.burnt_velocity(slow, 1.0), slow)


func test_a_phase_without_a_burn_never_burns_out() -> void:
	var phase: EmissionPhase = _phase({"speed": 15.0})
	var velocity: Vector3 = Vector3(15.0 / TimeUtils.ticks_per_second(), 0.0, 0.0)
	assert_eq(phase.burnt_velocity(velocity, 99.0), velocity)


# --- Turn bleed and lead -----------------------------------------------------------------


func _bleeding_phase() -> EmissionPhase:
	return _phase(
		{
			"speed": 15.0,
			"turn_rate_degrees_per_second": 90.0,
			"acceleration_mps2": 10.0,
			"min_speed": 2.0,
			"turn_bleed_mps2_per_radian": 30.0
		}
	)


func test_a_bleeding_phase_gains_speed_on_a_straight_run() -> void:
	var phase: EmissionPhase = _bleeding_phase()
	var velocity: Vector3 = Vector3(8.0 / TimeUtils.ticks_per_second(), 0.0, 0.0)
	var steered: Vector3 = phase.steered_toward(velocity, ORIGIN, ORIGIN + Vector3(10, 0, 0))
	assert_almost_eq(
		steered.length() - velocity.length(),
		10.0 / (TimeUtils.ticks_per_second() * TimeUtils.ticks_per_second()),
		FLOAT_TOLERANCE,
		"the full acceleration: nothing off the nose to bleed"
	)


func test_a_bleeding_phase_sheds_speed_in_a_hard_turn() -> void:
	var phase: EmissionPhase = _bleeding_phase()
	var tps: int = TimeUtils.ticks_per_second()
	var velocity: Vector3 = Vector3(8.0 / tps, 0.0, 0.0)
	# The goal square off the nose: 10 - 30·(π/2) ≈ -37 u/s² this tick.
	var steered: Vector3 = phase.steered_toward(velocity, ORIGIN, ORIGIN + Vector3(0, 0, 10))
	assert_almost_eq(
		steered.length() - velocity.length(),
		(10.0 - 30.0 * PI / 2.0) / (tps * tps),
		FLOAT_TOLERANCE,
		"bled in proportion to the angle"
	)


func test_a_bleeding_phase_never_falls_below_its_floor_or_passes_its_speed() -> void:
	var phase: EmissionPhase = _bleeding_phase()
	var tps: int = TimeUtils.ticks_per_second()
	var slow: Vector3 = Vector3(2.0 / tps, 0.0, 0.0)
	var behind: Vector3 = phase.steered_toward(slow, ORIGIN, ORIGIN - Vector3(10, 0, 0))
	assert_almost_eq(behind.length(), 2.0 / tps, FLOAT_TOLERANCE, "held at min_speed")
	var fast: Vector3 = Vector3(15.0 / tps, 0.0, 0.0)
	var ahead: Vector3 = phase.steered_toward(fast, ORIGIN, ORIGIN + Vector3(10, 0, 0))
	assert_almost_eq(ahead.length(), 15.0 / tps, FLOAT_TOLERANCE, "held at speed")


func test_a_full_lead_meets_a_target_holding_its_course() -> void:
	var phase: EmissionPhase = _phase(
		{"speed": 12.0, "turn_rate_degrees_per_second": 90.0, "lead_fraction": 1.0}
	)
	var tps: int = TimeUtils.ticks_per_second()
	var target: Vector3 = ORIGIN + Vector3(10.0, 0.0, 0.0)
	var step: Vector3 = Vector3(0.0, 0.0, 4.0 / tps)
	var aim: Vector3 = phase.intercept_point(ORIGIN, target, step)
	# Both arrive at the aim point at the same tick.
	var own_ticks: float = ORIGIN.distance_to(aim) / (12.0 / tps)
	var target_ticks: float = target.distance_to(aim) / step.length()
	assert_almost_eq(own_ticks, target_ticks, 0.01, "an intercept, not just a point ahead")
	assert_gt(aim.z, target.z, "ahead of the target, along its course")


func test_a_partial_lead_aims_that_fraction_of_the_way() -> void:
	var full: EmissionPhase = _phase(
		{"speed": 12.0, "turn_rate_degrees_per_second": 90.0, "lead_fraction": 1.0}
	)
	var half: EmissionPhase = _phase(
		{"speed": 12.0, "turn_rate_degrees_per_second": 90.0, "lead_fraction": 0.5}
	)
	var target: Vector3 = ORIGIN + Vector3(10.0, 0.0, 0.0)
	var step: Vector3 = Vector3(0.0, 0.0, 0.1)
	var full_offset: Vector3 = full.intercept_point(ORIGIN, target, step) - target
	var half_offset: Vector3 = half.intercept_point(ORIGIN, target, step) - target
	assert_almost_eq(half_offset, full_offset * 0.5, Vector3.ONE * FLOAT_TOLERANCE)


func test_a_target_too_fast_to_intercept_is_still_led() -> void:
	var phase: EmissionPhase = _phase(
		{"speed": 3.0, "turn_rate_degrees_per_second": 90.0, "lead_fraction": 1.0}
	)
	var target: Vector3 = ORIGIN + Vector3(10.0, 0.0, 0.0)
	var aim: Vector3 = phase.intercept_point(ORIGIN, target, Vector3(0.5, 0.0, 0.0))
	assert_true(aim.is_finite(), "a point, not a NaN")
	assert_gt(aim.x, target.x, "ahead of where it is")


func test_only_a_steered_phase_leads() -> void:
	assert_false(_phase({"speed": 12.0, "lead_fraction": 1.0}).leads())
	assert_true(
		_phase({"speed": 12.0, "turn_rate_degrees_per_second": 90.0, "lead_fraction": 1.0}).leads()
	)


# --- Losing the lock ----------------------------------------------------------------------


func _locking_phase(a_cone: float, a_range: float) -> EmissionPhase:
	return _phase(
		{
			"speed": 12.0,
			"turn_rate_degrees_per_second": 90.0,
			"lock_cone_degrees": a_cone,
			"lock_range": a_range
		}
	)


func test_a_target_beyond_the_lock_range_is_lost() -> void:
	var phase: EmissionPhase = _locking_phase(0.0, 5.0)
	var heading: Vector3 = Vector3(1.0, 0.0, 0.0)
	assert_false(phase.loses_lock(heading, Vector3.ZERO, Vector3(4.0, 0.0, 0.0)), "in range")
	assert_true(phase.loses_lock(heading, Vector3.ZERO, Vector3(6.0, 0.0, 0.0)), "out of it")


func test_a_target_outside_the_lock_cone_is_lost() -> void:
	var phase: EmissionPhase = _locking_phase(150.0, 0.0)
	var heading: Vector3 = Vector3(1.0, 0.0, 0.0)
	assert_false(phase.loses_lock(heading, Vector3.ZERO, Vector3(0.0, 0.0, 5.0)), "abeam: held")
	assert_true(
		phase.loses_lock(heading, Vector3.ZERO, Vector3(-5.0, 0.0, 0.5)), "nearly astern: lost"
	)


func test_without_lock_knobs_nothing_is_lost() -> void:
	var phase: EmissionPhase = _locking_phase(0.0, 0.0)
	assert_false(phase.loses_lock(Vector3(1, 0, 0), Vector3.ZERO, Vector3(-500, 0, 0)))


func test_an_unsteered_phase_has_no_lock_to_lose() -> void:
	var phase: EmissionPhase = _phase({"speed": 12.0, "lock_range": 1.0})
	assert_false(phase.loses_lock(Vector3(1, 0, 0), Vector3.ZERO, Vector3(50, 0, 0)))
