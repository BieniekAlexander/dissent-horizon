class_name ConditionScoutCoverage
extends Condition

## True once a bot's scouting has had at least [member minimum_fraction] of its scout-grid
## points in line of sight at least once. A pull condition reading the bot's BotScout
## coverage live.
##
## "Seen" means a real line-of-sight observation (the scout's LOS raycast reached the
## point), not the optimistic stamp the scout uses to avoid re-selecting a waypoint — so
## this measures genuine map coverage. With minimum_fraction = 1.0 it requires the WHOLE
## grid to have been observed.

#region Properties
## The bot commander whose scouting to measure.
@export var commander_id: int = 1
## Fraction of scout-grid points that must have been seen (1.0 = all of them).
@export_range(0.0, 1.0) var minimum_fraction: float = 1.0
#endregion

#region Public API
func evaluate(manager: ScenarioTriggerManager) -> bool:
	var scout: BotScout = _resolve_scout(manager)
	if scout == null:
		return false
	return scout.observed_fraction() >= minimum_fraction
#endregion

#region Internal
## Walk commander → BotBrain → BotScout, or null if any link is missing (e.g. the brain
## hasn't built its managers yet, which happens before the first think).
func _resolve_scout(manager: ScenarioTriggerManager) -> BotScout:
	var bot: Bot = manager.get_commander(commander_id) as Bot
	if bot == null:
		return null
	var brain: BotBrain = bot.get_node_or_null("BotBrain") as BotBrain
	if brain == null:
		return null
	return brain.get_scout()
#endregion
