class_name EmissionParticles
extends GPUParticles3D

## A particle system in an emission's visuals that starts a moment after its phase does: a
## rocket's smoke trail, which would otherwise begin on the launch frame, inside the unit that
## fired it, and out of nothing. EmissionPhase.show_visuals starts and stops it through
## set_phase_emitting rather than writing `emitting` directly.
## → gdd/systems/combat/projectiles.md §Visuals

## How long after its phase begins this starts emitting, in seconds.
@export var start_delay_seconds: float = 0.0

## Framework-imposed state: bumped on every start and stop, so a delayed start that a stop
## overtook does nothing when its timer fires.
var _generation: int = 0


func set_phase_emitting(a_on: bool) -> void:
	_generation += 1
	if not a_on or start_delay_seconds <= 0.0 or not is_inside_tree():
		emitting = a_on
		return
	var started: int = _generation
	# Pausable, like the particles themselves: a paused game does not advance the delay.
	get_tree().create_timer(start_delay_seconds, false).timeout.connect(func() -> void:
		if is_instance_valid(self) and _generation == started:
			emitting = true)
