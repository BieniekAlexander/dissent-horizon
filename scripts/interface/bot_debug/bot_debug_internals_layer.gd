class_name BotDebugInternalsLayer
extends BotDebugLayer

## BOT INTERNALS: the bot itself rather than the game — the personality it drew for this match,
## what each of its jobs costs, and what the actuator has issued and been refused. Text only:
## none of it has a place on the map.

## A personality field counts as drawn away from its tier when it moved by more than this.
const DRAWN_EPSILON: float = 1.0e-4
## Drawn personality fields per readout line.
const FIELDS_PER_LINE: int = 2


func readout(a_bot: Bot) -> PackedStringArray:
	var brain: BotBrain = brain_of(a_bot)
	if brain == null:
		return PackedStringArray(["no brain"])
	var lines: PackedStringArray = PackedStringArray(
		[
			(
				"tier %s, spread %.2f%s"
				% [
					PlayerSlot.Difficulty.keys()[brain.difficulty],
					brain.config.personality_spread,
					"" if brain.active else " — INACTIVE"
				]
			),
		]
	)
	lines.append("jobs (work units, µs last run; ticks until due):")
	lines.append_array(job_lines(a_bot, brain))
	var actuator: BotActuator = brain.get_actuator()
	if actuator != null:
		lines.append("orders issued / refused:")
		lines.append_array(action_lines(actuator.usage.actions()))
	# Last: fixed for the match, and the longest, so it is what runs off a short screen.
	lines.append("personality, tier → drawn:")
	lines.append_array(personality_lines(brain.config, BotDifficulty.for_tier(brain.difficulty)))
	return lines


## Each field of `drawn` that differs from `tier`: "name tier → drawn", two to a line so the
## twenty-odd searched fields fit a screen.
static func personality_lines(drawn: BotDifficulty, tier: BotDifficulty) -> PackedStringArray:
	var moved: PackedStringArray = PackedStringArray()
	for field: String in BotDifficulty.SEARCH_RANGES:
		var was: float = float(tier.get(field))
		var now: float = float(drawn.get(field))
		if absf(now - was) > DRAWN_EPSILON:
			moved.append("%s %s → %s" % [field, _number(was), _number(now)])
	if moved.is_empty():
		return PackedStringArray(["  the tier exactly"])
	var lines: PackedStringArray = PackedStringArray()
	for i: int in range(0, moved.size(), FIELDS_PER_LINE):
		lines.append("  " + ";  ".join(moved.slice(i, i + FIELDS_PER_LINE)))
	return lines


static func job_lines(bot: Bot, brain: BotBrain) -> PackedStringArray:
	var scheduler: BotScheduler = (
		bot.get_tree().get_first_node_in_group(BotScheduler.GROUP) as BotScheduler
		if bot.is_inside_tree()
		else null
	)
	var lines: PackedStringArray = PackedStringArray()
	if scheduler == null:
		lines.append("  no scheduler")
		return lines
	var id: int = brain.get_instance_id()
	for job: Dictionary in scheduler.report():
		if job["brain"] == id:
			lines.append(
				(
					"  %s  %d, %dµs; %d"
					% [job["name"], job["units"], job["usec"], maxi(0, job["due_in"])]
				)
			)
	return lines


## Per order kind: how many were issued and how many refused, over the match.
static func action_lines(actions: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var kinds: Array = actions.keys()
	kinds.sort()
	for kind: String in kinds:
		var issued: int = 0
		var refused: int = 0
		for row: Dictionary in actions[kind].values():
			for outcome: String in row:
				if outcome == BotUsageLog.OUTCOME_ISSUED:
					issued += int(row[outcome])
				else:
					refused += int(row[outcome])
		lines.append("  %s  %d / %d" % [kind, issued, refused])
	if lines.is_empty():
		lines.append("  none yet")
	return lines


static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.3f" % value
