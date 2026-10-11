@tool
class_name EventSetBotJobs
extends AbstractEvent

## Switch named BotBrain jobs on or off for one commander, from now on: the runtime form of
## PlayerSlot.disabled_bot_jobs. A mission hands the army to its own tactics by switching
## `military` off, and gives it back by switching it on again. It never sets what a job reads —
## an authored value inside a scored decision is the merge the Bot/mission boundary forbids
## (gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders).

## The commander whose bot is switched.
@export var commander_id: int = 2
## BotBrain.JOB_NAMES entries; an unknown name is reported, and the rest still switch.
@export var jobs: Array[StringName] = []
## On or off.
@export var enabled: bool = false


func execute(a_manager: ScenarioTriggerManager) -> void:
	var bot := a_manager.get_commander(commander_id) as Bot
	var brain: BotBrain = bot.brain() if bot != null else null
	if brain == null:
		push_error("EventSetBotJobs: commander %d has no bot brain to switch." % commander_id)
		return
	for job: StringName in jobs:
		if not brain.set_job_enabled(job, enabled):
			push_error("EventSetBotJobs: no bot job is named '%s'; ignoring it." % job)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for job: StringName in jobs:
		if not BotBrain.JOB_NAMES.has(job):
			warnings.append(
				"No bot job is named '%s'. Jobs: %s" % [job, ", ".join(BotBrain.JOB_NAMES)]
			)
	return warnings
