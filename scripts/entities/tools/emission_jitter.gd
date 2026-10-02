class_name EmissionJitter
extends RefCounted

## A rocket's wobble: a small, smooth deviation of its heading from where its motion is taking
## it, as two sine waves per axis (sideways and vertical) at unrelated rates, so it never
## visibly repeats. Real motion, not decoration — an unsteered shot drifts and can miss, a
## steered one corrects. Sine sums because they are cheap per tick and integrate to a bounded
## drift: a mean-zero weave cannot walk a shot arbitrarily far off line the way a random walk
## would. → gdd/systems/combat/projectiles.md §Jitter

## Seconds the wobble takes to build after launch, so a shot leaves the tube cleanly.
const RAMP_IN_SECONDS: float = 0.25
## The second wave's rate relative to the first: irrational-ish, so the sum never lines up.
const SECOND_WAVE_RATIO: float = 2.37
## How much of the amplitude each wave carries; they sum to one, so the deviation never
## exceeds the authored angle on either axis.
const FIRST_WAVE_SHARE: float = 0.65
const SECOND_WAVE_SHARE: float = 0.35

## Four phases in radians: first and second wave, sideways then vertical.
var _phases: PackedFloat32Array


## A wobble with phases drawn from `a_rng` — the seeded gameplay generator in play, so a
## scenario replays the same flights.
func _init(a_rng: RandomNumberGenerator) -> void:
	_phases = PackedFloat32Array(
		[a_rng.randf() * TAU, a_rng.randf() * TAU, a_rng.randf() * TAU, a_rng.randf() * TAU]
	)


## `velocity` turned by the wobble at `elapsed_seconds` into `phase`. Speed is kept; only the
## heading moves. Unchanged for a phase without jitter and for a standing emission.
func perturbed(phase: EmissionPhase, elapsed_seconds: float, velocity: Vector3) -> Vector3:
	if not phase.has_jitter() or velocity.length_squared() < 0.0000001:
		return velocity
	var amplitude: float = (
		deg_to_rad(phase.jitter_degrees) * clampf(elapsed_seconds / RAMP_IN_SECONDS, 0.0, 1.0)
	)
	if amplitude <= 0.0:
		return velocity
	var angle: float = TAU * phase.jitter_frequency_hz * elapsed_seconds
	var forward: Vector3 = velocity.normalized()
	var up_hint: Vector3 = Vector3.FORWARD if absf(forward.dot(Vector3.UP)) > 0.999 else Vector3.UP
	var right: Vector3 = forward.cross(up_hint).normalized()
	var up: Vector3 = right.cross(forward).normalized()
	return velocity.rotated(up, amplitude * _wave(angle, _phases[0], _phases[1])).rotated(
		right, amplitude * _wave(angle, _phases[2], _phases[3])
	)


static func _wave(angle: float, first_phase: float, second_phase: float) -> float:
	return (
		FIRST_WAVE_SHARE * sin(angle + first_phase)
		+ SECOND_WAVE_SHARE * sin(angle * SECOND_WAVE_RATIO + second_phase)
	)
