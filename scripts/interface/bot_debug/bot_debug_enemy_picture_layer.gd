class_name BotDebugEnemyPictureLayer
extends BotDebugLayer

## ENEMY PICTURE: what the bot believes is out there — its blackboard, not the truth.
##
## Each believed piece at its last-known position: a filled square for a unit, an outline for a
## structure. Red while in view; orange once remembered, a unit fading out over the belief's
## expiry window (a structure is believed until its spot is seen empty, so it does not fade). A
## stick marks a piece that can shoot.

const UNIT_HALF: float = 0.35
const STRUCTURE_HALF: float = 1.2
const ARMED_STICK_HEIGHT: float = 1.2
const COLOR_IN_VIEW: Color = Color(1.0, 0.15, 0.15, 0.85)
const COLOR_REMEMBERED: Color = Color(1.0, 0.6, 0.15)
## A remembered unit's alpha when freshly lost from view, and at the moment its belief lapses.
const REMEMBERED_ALPHA_FRESH: float = 0.75
const REMEMBERED_ALPHA_LAPSING: float = 0.15
const REMEMBERED_STRUCTURE_ALPHA: float = 0.6


func draw(a_bot: Bot, a_pen: BotDebugPen) -> void:
	var board: CommanderBlackboard = a_bot.blackboard
	if board == null:
		return
	var now: float = a_bot.seconds_elapsed()
	for entry: CommanderBlackboard.Entry in board.believed():
		var color: Color = belief_color(
			board.is_in_view(entry.instance_id), entry.is_structure, now - entry.last_seen_time
		)
		var at: Vector3 = entry.last_known_location
		if entry.is_structure:
			a_pen.square(at, STRUCTURE_HALF, color)
		else:
			a_pen.quad(at, UNIT_HALF, color)
		if a_bot.unit_can_attack(entry.type):
			var opaque: Color = color
			opaque.a = 1.0
			a_pen.stick(at, ARMED_STICK_HEIGHT, opaque)


func readout(a_bot: Bot) -> PackedStringArray:
	var board: CommanderBlackboard = a_bot.blackboard
	if board == null:
		return PackedStringArray(["no blackboard"])
	var units: Array = board.believed_units()
	var in_view: int = (
		units
		. filter(func(e: CommanderBlackboard.Entry) -> bool: return board.is_in_view(e.instance_id))
		. size()
	)
	var lines: PackedStringArray = PackedStringArray(
		[
			(
				"believed: %d units (%d in view), %d structures"
				% [units.size(), in_view, board.believed_structures().size()]
			),
			(
				"enemy army: %d energy believed, own %d"
				% [roundi(a_bot.believed_enemy_army_value()), roundi(a_bot.army_resource_value())]
			),
			"counter-demand:",
		]
	)
	var demand: Dictionary = a_bot.enemy_demand_map()
	var types: Array = demand.keys()
	types.sort_custom(func(a, b) -> bool: return demand[a]["demand"] > demand[b]["demand"])
	for type in types:
		lines.append("  %s  %.2f" % [type, demand[type]["demand"]])
	return lines


## Red in view; orange remembered — a unit fading over the expiry window, a structure steady.
static func belief_color(is_in_view: bool, is_structure: bool, age_seconds: float) -> Color:
	if is_in_view:
		return COLOR_IN_VIEW
	var color: Color = COLOR_REMEMBERED
	if is_structure:
		color.a = REMEMBERED_STRUCTURE_ALPHA
	else:
		var t: float = clampf(age_seconds / CommanderBlackboard.BLACKBOARD_EXPIRATION, 0.0, 1.0)
		color.a = lerpf(REMEMBERED_ALPHA_FRESH, REMEMBERED_ALPHA_LAPSING, t)
	return color
