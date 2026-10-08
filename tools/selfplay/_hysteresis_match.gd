extends "res://tools/selfplay/run_match.gd"

## TEMPORARY hysteresis probe (delete me). Same match as run_match, with a per-sample record
## of the three decisions that could thrash: the army's POSTURE, each unit's CURRENT TARGET,
## and what the production queue is holding. Sample at the think cadence
## (`sample_interval_seconds` = combat_period_seconds) to read the combat jobs.


func _brain_sample(a_brain: BotBrain) -> Dictionary:
	var base: Dictionary = super._brain_sample(a_brain)
	if a_brain == null or a_brain.bot == null:
		return base
	var bot: Bot = a_brain.bot
	var military: BotMilitary = a_brain._military
	if military != null:
		base["wave"] = military._wave_active
		base["objective"] = "%d,%d" % [int(military._objective.x), int(military._objective.z)]
	# unit instance id -> what it is presently doing: an enemy instance id for an Attack,
	# "AM" for an attack-move, "M" for a plain move, "-" for idle.
	var targets: Dictionary = {}
	for u: Actor in bot.get_units():
		var key: String = str(u.get_instance_id())
		if not u.has_command():
			targets[key] = "-"
			continue
		var cmd: MoveCommand = u.current_command()
		if cmd is Attack:
			var t: Variant = cmd.message.target
			targets[key] = str(t.get_instance_id()) if is_instance_valid(t) else "?"
		elif cmd is AttackMove:
			targets[key] = "AM"
		else:
			targets[key] = "M"
	base["targets"] = targets
	var queued: Array = []
	for t: PurchaseTransaction in bot.production_queue.pending():
		queued.append(String(t.type))
	queued.sort()
	base["queue"] = queued
	return base
