@tool
class_name TimeUtils

## THE TICK↔SECOND CONVERSION, expressed once for the whole project.
##
## Seconds are the authored unit everywhere a human reads or edits a value — gdd docs,
## config, exported properties (see CLAUDE.md and ~/.claude/CLAUDE.md §2.2). Ticks are the
## engine's, and the boundary between the two is here.
##
## The factor is DERIVED from the engine rather than typed, and that is the whole point: a
## hardcoded copy survives a change to the physics rate while the derived path adapts, so
## every value expressed in the copy is silently wrong with nothing to report it. The spec
## importer held four such copies (`* 30.0`), which is what this replaced.

## The project setting the simulation rate is authored in.
const _TICK_RATE_SETTING: String = "physics/common/physics_ticks_per_second"

## Memoized: read on every tick from movement and steering hot paths, and a ProjectSettings
## lookup is a string-keyed dictionary walk.
static var _ticks_per_second: int = ProjectSettings.get_setting(_TICK_RATE_SETTING)


#region Public API
## Simulation ticks in one GAME second. Not a `const` because the rate is a project setting
## the engine owns, and a const could only restate it — which is the failure this class exists
## to prevent.
##
## Read from the project setting, NOT from `Engine.physics_ticks_per_second`: playback speed
## (PlaybackSpeed) changes how many ticks run per REAL second, and must not change what a
## tick means. A game second is always this many ticks, at any playback speed.
static func ticks_per_second() -> int:
	return _ticks_per_second


## [a_seconds] as a whole number of physics ticks, rounded to the NEAREST rather than
## truncated: 0.35s at 30 tps is 10.499999 in float, and truncation turns an authored
## 10.5-tick value into 10 while rounding gives the 10 a designer would predict from the
## decimal they typed.
static func ticks_from_seconds(seconds: float) -> int:
	return int(roundf(seconds * ticks_per_second()))


## [a_ticks] back in seconds — the direction a display or a rate calculation wants.
static func seconds_from_ticks(ticks: int) -> float:
	return float(ticks) / float(ticks_per_second())
#endregion
