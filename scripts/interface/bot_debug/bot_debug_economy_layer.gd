class_name BotDebugEconomyLayer
extends BotDebugLayer

## ECONOMY: what the bot is saving for, what it would train, and where it will not build.
##
## World marks are the build spots the economy steers away from: a grey X where it wrote a spot
## off, an orange ring where an armed enemy contested one (fading as the cooldown runs out), and
## a cyan outline where an in-flight construction job is aimed. The readout carries the rest:
## the savings goal and every proposal, the game phase and dominion demand, the composition
## value of each unit the bot could train now, and the latest scored decisions.

const ABANDONED_HALF: float = 1.0
const COLOR_ABANDONED: Color = Color(0.6, 0.6, 0.6, 0.9)
const COLOR_CONTESTED: Color = Color(1.0, 0.55, 0.1)
const CLAIMED_HALF: float = 1.0
const CLAIMED_STICK_HEIGHT: float = 1.5
const COLOR_CLAIMED: Color = Color(0.3, 0.9, 1.0)
const PHASE_LABELS: PackedStringArray = ["early", "mid", "late"]
## How many trainable units the readout lists, best first.
const TRAINABLE_SHOWN: int = 6


func draw(a_bot: Bot, a_pen: BotDebugPen) -> void:
	var economy: BotEconomy = _economy_of(a_bot)
	if economy == null:
		return
	var spots: Dictionary = economy.debug_spots()
	for spot: Vector3 in spots["abandoned"]:
		a_pen.cross(spot, ABANDONED_HALF, COLOR_ABANDONED)
	var now: float = a_bot.seconds_elapsed()
	for entry: Dictionary in spots["contested"]:
		var left: float = float(entry["until"]) - now
		if left <= 0.0:
			continue
		var color: Color = COLOR_CONTESTED
		color.a = clampf(left / BotEconomy.CONTESTED_SPOT_SECONDS, 0.0, 1.0)
		a_pen.ring(entry["position"], BotEconomy.CONTESTED_SPOT_RADIUS, color)
	for spot: Vector3 in spots["claimed"]:
		a_pen.square(spot, CLAIMED_HALF, COLOR_CLAIMED)
		a_pen.stick(spot, CLAIMED_STICK_HEIGHT, COLOR_CLAIMED)


func readout(a_bot: Bot) -> PackedStringArray:
	var economy: BotEconomy = _economy_of(a_bot)
	if economy == null:
		return PackedStringArray(["no economy manager yet"])
	var phase: int = a_bot.game_phase()
	var lines: PackedStringArray = PackedStringArray(
		[
			(
				"energy %d (reserve %d); phase %s; dominion demand %d"
				% [
					a_bot.energy,
					economy.reserve,
					PHASE_LABELS[clampi(phase, 0, PHASE_LABELS.size() - 1)],
					a_bot.dominion_demand()
				]
			),
		]
	)
	lines.append_array(savings_lines(a_bot.savings))
	lines.append("trainable now, value per energy vs believed enemy:")
	var values: Dictionary = trainable_values(a_bot)
	var types: Array = values.keys()
	types.sort_custom(func(a, b) -> bool: return values[a] > values[b])
	if types.is_empty():
		lines.append("  nothing")
	for type in types.slice(0, TRAINABLE_SHOWN):
		lines.append("  %s  %.2f" % [type, values[type]])
	var brain: BotBrain = brain_of(a_bot)
	var actuator: BotActuator = brain.get_actuator() if brain != null else null
	if actuator != null:
		lines.append("recent decisions:")
		lines.append_array(decision_lines(actuator.usage.recent_choices()))
	return lines


## The savings goal, whether its claim on the bank is held, and every manager's proposal.
static func savings_lines(savings: BotSavings) -> PackedStringArray:
	var goal: StringName = savings.goal()
	var lines: PackedStringArray = PackedStringArray(
		[
			(
				"saving for: %s%s"
				% [
					goal if goal != &"" else "nothing",
					"" if savings.held or goal == &"" else " (claim lifted: base under threat)"
				]
			)
		]
	)
	var proposals: Dictionary = savings.proposals()
	for source: StringName in proposals:
		var p: Dictionary = proposals[source]
		lines.append("  %s wants %s: %.2f for %d" % [source, p["type"], p["value"], p["cost"]])
	return lines


## Latest first: "domain: chosen (score) over runner-up (score)".
static func decision_lines(recent: Array[Dictionary]) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for i: int in range(recent.size() - 1, -1, -1):
		var d: Dictionary = recent[i]
		var line: String = (
			"  %s: %s (%.2f)"
			% [d["domain"], d["chosen"] if d["chosen"] != "" else "nothing", d["chosen_score"]]
		)
		if d["runner_up"] != "":
			line += " over %s (%.2f)" % [d["runner_up"], d["runner_up_score"]]
		lines.append(line)
	if lines.is_empty():
		lines.append("  none yet")
	return lines


## Each unit type a finished production structure could train now, by its composition value
## against the enemy the bot believes in.
static func trainable_values(bot: Bot) -> Dictionary:
	var demand: Dictionary = bot.enemy_demand_map()
	var out: Dictionary = {}
	for s: Actor in bot.get_production_structures():
		for type in bot.considered_producible_types(s.production):
			if not out.has(type) and bot.has_tech_for(type):
				out[type] = bot.unit_composition_value(type, demand)
	return out


static func _economy_of(bot: Bot) -> BotEconomy:
	var brain: BotBrain = brain_of(bot)
	return brain.get_economy() if brain != null else null
