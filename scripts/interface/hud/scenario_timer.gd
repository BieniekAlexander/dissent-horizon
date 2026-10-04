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
## The simulation clock, read for a debug playback pause. Null when the session has none.
var _clock: SimulationClock = null


func _ready() -> void:
	add_to_group(GROUP)
	# HUD: it must keep reading while the clock holds the world, or a pause could never show.
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(a_scenario: Scenario, a_clock: SimulationClock) -> void:
	_scenario = a_scenario
	_clock = a_clock


## Scenario.tick only advances in _physics_process, which a SimulationClock hold suspends along
## with the rest of the simulation — so ticks / tick-rate is already elapsed RUNTIME excluding
## paused time, with no separate accumulator needed.
func _process(_a_delta: float) -> void:
	if _scenario == null:
		return
	text = (
		format_time(int(TimeUtils.seconds_from_ticks(_scenario.tick)))
		+ playback_suffix(
			PlaybackSpeed.multiplier(),
			PlaybackSpeed.is_uncapped(),
			_clock != null and _clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE)
		)
	)


## "m:ss" under an hour, "h:mm:ss" from then on.
static func format_time(total_seconds: int) -> String:
	var hours: int = total_seconds / SECONDS_PER_HOUR
	var minutes: int = (total_seconds / SECONDS_PER_MINUTE) % SECONDS_PER_MINUTE
	var seconds: int = total_seconds % SECONDS_PER_MINUTE
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%d:%02d" % [minutes, seconds]


## What follows the time when playback is not plain real time — the speed, and a debug pause —
## so a spectator can tell a stopped or racing clock from a broken one. Empty at normal speed.
static func playback_suffix(multiplier: float, is_uncapped: bool, is_paused: bool) -> String:
	var parts: PackedStringArray = []
	if is_uncapped or not is_equal_approx(multiplier, PlaybackSpeed.NORMAL_MULTIPLIER):
		parts.append(PlaybackSpeed.label_for(multiplier, is_uncapped))
	if is_paused:
		parts.append("paused")
	return "" if parts.is_empty() else "  " + " ".join(parts)
