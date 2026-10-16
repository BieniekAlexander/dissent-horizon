class_name CatchUpPolicy
extends RefCounted

## WHETHER THE ENGINE MAY CATCH UP ON MISSED TICKS — the pure half of CatchUpGovernor.
##
## When a tick costs more than its share of real time, Godot runs several ticks in the next
## frame to catch up (up to `max_physics_steps_per_frame`), so one slow stretch is drawn as a
## long freeze followed by a burst. While the simulation cannot keep up at all, catching up
## only makes every frame longer. This says when to stop trying: the game then runs slower
## than real time, smoothly, as C&C Generals does, and resumes catching up once it has room.
## A tick still means the same thing either way, so this changes timing only, never the match.
##
## Fed the real time each engine step took. It smooths that over about a second, so one slow
## tick (a navmesh rebuild) is still caught up on; and it lowers the cap above the budget but
## restores it only well below, so it does not flicker at the edge.

## Weight of the newest step in the running average: about a second's worth of steps at 30.
const SMOOTHING: float = 1.0 / 30.0
## Lower the cap once the average step takes longer than this fraction of its budget.
const LOWER_ABOVE: float = 1.0
## Restore it once the average step is back under this fraction.
const RESTORE_BELOW: float = 0.8

## The running average of a step's real cost, as a fraction of its budget.
var load_fraction: float = 0.0
## Whether catching up is off now.
var is_lowered: bool = false


## Take one engine step that cost `a_step_seconds` against a budget of `a_budget_seconds` (one
## engine tick of real time), and return whether catching up should be off.
func observe(a_step_seconds: float, a_budget_seconds: float) -> bool:
	if a_budget_seconds <= 0.0:
		return is_lowered
	var fraction: float = a_step_seconds / a_budget_seconds
	load_fraction += (fraction - load_fraction) * SMOOTHING
	if is_lowered:
		is_lowered = load_fraction >= RESTORE_BELOW
	else:
		is_lowered = load_fraction > LOWER_ABOVE
	return is_lowered


## How fast the game is running against real time while catching up is off: the share of its
## budget a step would need to fit, capped at full speed.
func speed_fraction() -> float:
	return minf(1.0, 1.0 / load_fraction) if load_fraction > 0.0 else 1.0
