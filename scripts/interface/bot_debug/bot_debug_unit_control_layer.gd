class_name BotDebugUnitControlLayer
extends BotDebugLayer

## UNIT CONTROL: which manager owns each of the bot's units (BotClaims), and how firmly.
##
## A ring on every claimed unit in its owner's colour, one ring per priority step, so an errand
## reads thicker than a scouting claim. An unclaimed unit, which the army may take, gets a faint
## grey ring. Each unit's active command is already labelled by the debug view itself.

const RING_RADIUS: float = 0.7
## The gap between a claim's nested rings, one per priority step.
const RING_STEP: float = 0.15
## By owner (each manager's CLAIM_OWNER); an owner not named here draws COLOR_OTHER.
const OWNER_COLORS: Dictionary = {
	BotEconomy.CLAIM_OWNER: Color(0.3, 0.9, 1.0),
	BotTargeting.CLAIM_OWNER: Color(1.0, 0.25, 0.2),
	BotScout.CLAIM_OWNER: Color(0.3, 1.0, 0.4),
	BotKamikaze.CLAIM_OWNER: Color(1.0, 0.3, 0.9),
	BotOpportunist.CLAIM_OWNER: Color(1.0, 0.85, 0.2),
	BotAbilities.CLAIM_OWNER: Color(0.7, 0.5, 1.0),
}
const COLOR_OTHER: Color = Color(1.0, 1.0, 1.0)
const COLOR_UNCLAIMED: Color = Color(0.6, 0.6, 0.6, 0.35)


func draw(a_bot: Bot, a_pen: BotDebugPen) -> void:
	var brain: BotBrain = brain_of(a_bot)
	if brain == null:
		return
	for unit: Actor in a_bot.get_units():
		if not unit.is_inside_tree():
			continue
		var owner: StringName = brain.claims.owner_of(unit)
		if owner == &"":
			a_pen.ring(unit.global_position, RING_RADIUS, COLOR_UNCLAIMED)
			continue
		var color: Color = owner_color(owner)
		for step: int in brain.claims.priority_of(unit):
			a_pen.ring(unit.global_position, RING_RADIUS + RING_STEP * step, color)


func readout(a_bot: Bot) -> PackedStringArray:
	var brain: BotBrain = brain_of(a_bot)
	if brain == null:
		return PackedStringArray(["no brain"])
	var counts: Dictionary = {}
	for unit: Actor in a_bot.get_units():
		var owner: StringName = brain.claims.owner_of(unit)
		counts[owner] = int(counts.get(owner, 0)) + 1
	var lines: PackedStringArray = PackedStringArray(["units: %d" % a_bot.get_units().size()])
	var owners: Array = counts.keys()
	owners.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	for owner: StringName in owners:
		lines.append(
			"  %s: %d" % [owner if owner != &"" else "unclaimed (the army's)", counts[owner]]
		)
	lines.append("priority: one ring per step — scout 1, combat 2, errand 3, exclusive 4")
	return lines


static func owner_color(owner: StringName) -> Color:
	return OWNER_COLORS.get(owner, COLOR_OTHER)
