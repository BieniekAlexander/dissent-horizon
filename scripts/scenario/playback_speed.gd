class_name PlaybackSpeed

## How fast the simulation runs against the wall clock — a debug control, raised from the
## pause menu while the scenario has `debug_allowed`.
##
## A TICK NEVER CHANGES MEANING. The simulation is 30 ticks per game second
## (TimeUtils.ticks_per_second) at every speed; what changes is how many of them run per REAL
## second. Two engine settings move together to do that:
##
## - `Engine.physics_ticks_per_second` = base × multiplier: how often the engine steps.
## - `Engine.time_scale` = the same ratio, so the delta handed to each step
##   (physics step × time_scale) is still exactly one base tick. move_and_slide, the physics
##   server and every `_physics_process(delta)` therefore integrate the same distance per tick
##   at any speed, and a seed replays identically whether watched at 0.25× or uncapped.
##
## The engine rate is a whole number, so the multiplier is quantised to n / base: 0.25× at a
## base of 30 is 7.5 ticks a second, which rounds up to 8 (≈0.27×). See
## gdd/systems/ux/ui/debug-mode.md §Playback speed.
##
## Pausing is not here: it is a SimulationClock hold (REASON_PLAYBACK_PAUSE), so it composes
## with every other reason the world may be stopped.
##
## Static, and so global state, because the two settings it drives are the engine's own
## globals; Scenario resets it on exit so a speed never leaks into the next session.

#region Constants
const NORMAL_MULTIPLIER: float = 1.0
## The range the player may pick from, as multiples of the base rate.
const MIN_MULTIPLIER: float = 0.25
const MAX_MULTIPLIER: float = 4.0

## "As fast as possible": an engine rate no frame can keep up with, so the per-frame step cap
## below — not this number — is what bounds the run. Any value far past a reachable rate would
## do; it only has to stay ahead of what the machine can simulate.
const UNCAPPED_MULTIPLIER: float = 1000.0
## Steps the engine may run before it must draw a frame, while uncapped. Higher simulates more
## per frame drawn, at the cost of a less responsive screen; with vsync at 60 Hz, this caps an
## uncapped run at 60 × this many ticks a second (64× at a base of 30).
const UNCAPPED_STEPS_PER_FRAME: int = 32

const _STEPS_PER_FRAME_SETTING: String = "physics/common/max_physics_steps_per_frame"
#endregion


#region Public API
## Run at `a_multiplier` × the base rate, clamped to [MIN_MULTIPLIER, MAX_MULTIPLIER] and
## quantised to a whole engine rate. Returns the multiplier actually applied.
static func set_multiplier(a_multiplier: float) -> float:
	_apply(engine_ticks_for(a_multiplier, TimeUtils.ticks_per_second()), _default_steps())
	return multiplier()


## Run as fast as the machine allows.
static func set_uncapped() -> void:
	_apply(roundi(TimeUtils.ticks_per_second() * UNCAPPED_MULTIPLIER), UNCAPPED_STEPS_PER_FRAME)


## Back to real time.
static func reset() -> void:
	_apply(TimeUtils.ticks_per_second(), _default_steps())


## Game seconds per real second, as currently applied.
static func multiplier() -> float:
	return Engine.time_scale


static func is_uncapped() -> bool:
	return multiplier() > MAX_MULTIPLIER


## `a_delta`, a scaled frame delta, back in real seconds — for what moves at the player's pace
## rather than the game's, like the camera.
static func real_seconds(a_delta: float) -> float:
	return a_delta / Engine.time_scale if Engine.time_scale > 0.0 else a_delta


## How a speed reads on screen: "×0.27", "×1.00", "max".
static func label_for(multiplier: float, is_uncapped: bool) -> String:
	return "max" if is_uncapped else "×%.2f" % multiplier


## The engine tick rate that runs `multiplier` × `base` game ticks per real second, within
## the allowed range. A rate is whole, so the range's ends round INWARD.
static func engine_ticks_for(multiplier: float, base: int) -> int:
	return clampi(roundi(base * multiplier), min_engine_ticks(base), max_engine_ticks(base))


static func min_engine_ticks(base: int) -> int:
	return ceili(base * MIN_MULTIPLIER)


static func max_engine_ticks(base: int) -> int:
	return floori(base * MAX_MULTIPLIER)


#endregion


#region Private helpers
static func _apply(a_engine_ticks: int, a_steps_per_frame: int) -> void:
	Engine.physics_ticks_per_second = a_engine_ticks
	Engine.max_physics_steps_per_frame = a_steps_per_frame
	Engine.time_scale = float(a_engine_ticks) / float(TimeUtils.ticks_per_second())


static func _default_steps() -> int:
	return ProjectSettings.get_setting(_STEPS_PER_FRAME_SETTING)
#endregion
