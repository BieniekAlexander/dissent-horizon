@tool
class_name ConditionTimer
extends Condition

#region Properties
enum Mode {
	## True once total scenario physics frames >= seconds * 30.
	ELAPSED_SINCE_START,
	## True once N seconds have passed since this condition was first evaluated.
	## Countdown resets when the owning trigger resets (repeating triggers).
	COUNTDOWN
}

@export var mode: Mode = Mode.ELAPSED_SINCE_START

## How long this timer runs, in seconds — a plain number ("15"), or any expression (see
## ScenarioExpression). Blank means DEFAULT_SECONDS.
##
## Resolved ONCE per countdown rather than every frame, which is the whole point for a
## repeating wave: "15 + randi_range(0, 10)" picks one interval and counts down to it. Were
## it re-evaluated per frame the deadline would jitter every tick and the countdown would
## effectively never land. `fires` makes the interval a function of how many waves have
## already gone out — "20 - fires" tightens the screw each cycle.
##
## There is no separate numeric `seconds` field: "15" is already a valid expression, so a
## second export would only be a second place for the same number to live. Sub-resources
## authored before this are migrated by _set below.
@export_placeholder("60 — or e.g. 15 + randi_range(0, 10)") var seconds_expression: String = ""

## What a blank seconds_expression means, and the fallback when one doesn't evaluate. Matches
## the default of the `seconds` export this replaced.
const DEFAULT_SECONDS: float = 60.0

var _start_tick: int = -1
## The interval this cycle is counting to, in frames. -1 = not resolved yet.
var _target_ticks: int = -1
#endregion

#region Authoring
## Reported through the owning GlobalTrigger's configuration warnings (see Condition), so a
## mistyped interval shows up in the Scene dock instead of silently running for
## DEFAULT_SECONDS.
func configuration_warning() -> String:
	var problem: String = ScenarioExpression.validation_error(seconds_expression)
	if problem.is_empty():
		return ""
	return "Seconds Expression \"%s\" %s" % [seconds_expression, problem]
#endregion

#region Migration
## Migrate sub-resources authored against the old float `seconds` export — the same set()
## routing EventSpawnEntities uses for its `count`. An old "seconds = 15.0" becomes
## seconds_expression "15", and re-saving the scene writes only the new form.
func _set(a_property: StringName, a_value: Variant) -> bool:
	if a_property == &"seconds":
		if not ScenarioExpression.is_authored(seconds_expression):
			seconds_expression = str(a_value)
		return true
	return false
#endregion

#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	if mode == Mode.ELAPSED_SINCE_START:
		return a_manager.scenario.tick >= _resolve_target_ticks(a_manager)
	if _start_tick < 0:
		_start_tick = a_manager.scenario.tick
	return (a_manager.scenario.tick - _start_tick) >= _resolve_target_ticks(a_manager)


func reset() -> void:
	super.reset()
	_start_tick = -1
	# Drop the resolved interval too, so a repeating trigger re-rolls its expression for the
	# next cycle instead of reusing the first one forever.
	_target_ticks = -1


## This cycle's deadline in frames, resolved once and cached until reset().
func _resolve_target_ticks(a_manager: ScenarioTriggerManager) -> int:
	if _target_ticks < 0:
		var resolved: float = ScenarioExpression.evaluate_float(
			seconds_expression, DEFAULT_SECONDS, a_manager, owner_fire_count(), _where()
		)
		_target_ticks = TimeUtils.ticks_from_seconds(maxf(resolved, 0.0))
	return _target_ticks


## Label for warnings, naming the owning trigger so a bad expression is traceable to a node.
func _where() -> String:
	var trigger: GlobalTrigger = _trigger
	var owner_name: String = String(trigger.name) if is_instance_valid(trigger) else "<unowned>"
	return "ConditionTimer on %s (seconds_expression)" % owner_name
#endregion
