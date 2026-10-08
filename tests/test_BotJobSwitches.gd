extends GutTest

## A mission switches a bot's jobs off one at a time (PlayerSlot.disabled_bot_jobs), so it can
## run the bot's economy and production while it authors the army itself.
## gdd/systems/ai/squads-and-relations.md §Squads.


func _brain_with_managers() -> BotBrain:
	var bot := autofree(Bot.new()) as Bot
	bot.map = autofree(Map.new()) as Map
	var brain := autofree(BotBrain.new()) as BotBrain
	brain.bot = bot
	assert_true(brain._ensure_managers(), "a bot with a map builds its managers")
	return brain


func _names(a_jobs: Array[BotJob]) -> Array[StringName]:
	var names: Array[StringName] = []
	for job: BotJob in a_jobs:
		names.append(job.name)
	return names


## The names a slot may switch off are exactly the jobs a brain makes, so a typo is refused at
## boot rather than silently switching nothing off.
func test_the_switchable_names_are_the_jobs_a_brain_makes() -> void:
	assert_eq(_names(_brain_with_managers()._jobs), BotBrain.JOB_NAMES)


func test_a_switched_off_job_is_not_run() -> void:
	var brain: BotBrain = _brain_with_managers()
	brain.disabled_jobs = [&"military"]
	var enabled: Array[StringName] = _names(brain.enabled_jobs())
	assert_false(enabled.has(&"military"))
	assert_eq(enabled.size(), BotBrain.JOB_NAMES.size() - 1, "and every other job still is")


func test_a_switched_off_job_is_never_scheduled() -> void:
	var brain: BotBrain = _brain_with_managers()
	brain.disabled_jobs = [&"production", &"economy"]
	var scheduler := autofree(BotScheduler.new()) as BotScheduler
	brain.register_jobs(scheduler)
	var scheduled: Array[StringName] = []
	for job: BotJob in scheduler._jobs:
		scheduled.append(job.name)
	assert_false(scheduled.has(&"production"))
	assert_false(scheduled.has(&"economy"))
	assert_true(scheduled.has(&"military"))


func test_a_slot_naming_an_unknown_job_is_reported() -> void:
	var scenario := Scenario.new()
	var good := PlayerSlot.new()
	good.disabled_bot_jobs = [&"military"]
	var bad := PlayerSlot.new()
	bad.disabled_bot_jobs = [&"militray"]
	scenario.player_slots = [good, bad]
	var unknown: Dictionary = scenario._unknown_bot_job_slots()
	assert_eq(unknown.keys(), [2])
	assert_eq(unknown[2], [&"militray"])
	scenario.free()
