class_name ScenarioTimer
extends Label

## The elapsed-time readout at the top right. Owned by the SCENARIO rather than the player rig,
## so a spectator session with no human seat shows it too. Layout is authored in
## scenes/interface/scenario_timer.tscn.

## Lets the debug panel, which stands in for the top-right HUD, find this without a path.
const GROUP: StringName = &"scenario_timer"
const SECONDS_PER_MINUTE: int = 60
const SECONDS_PER_HOUR: int = 3600

## The session whose clock this reads. Null until bound, and the label then shows nothing new.
var _scenario: Scenario = null


func _ready() -> void:
	add_to_group(GROUP)


func bind(a_scenario: Scenario) -> void:
	_scenario = a_scenario


## Scenario.tick only advances in _physics_process, which a SimulationClock hold suspends along
## with the rest of the simulation — so ticks / tick-rate is already elapsed RUNTIME excluding
## paused time, with no separate accumulator needed.
func _process(_a_delta: float) -> void:
	if _scenario == null:
		return
	text = format_time(int(TimeUtils.seconds_from_ticks(_scenario.tick)))


## "m:ss" under an hour, "h:mm:ss" from then on.
static func format_time(total_seconds: int) -> String:
	var hours: int = total_seconds / SECONDS_PER_HOUR
	var minutes: int = (total_seconds / SECONDS_PER_MINUTE) % SECONDS_PER_MINUTE
	var seconds: int = total_seconds % SECONDS_PER_MINUTE
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%d:%02d" % [minutes, seconds]
