class_name BotDebugArmyLayer
extends BotDebugLayer

## ARMY: what the military is doing with the army, and why.
##
## The objective: a ring in the posture's colour (red attack, blue defend, green mass), with an
## outline on the structure behind it. Each squad (main, reserve, guard): a ring on every member
## in the squad's colour, a filled square at its centroid, and a line from there to the point
## its policy holds, outlined. The production rally point: a yellow stick. An abandoned
## objective: a grey X until it expires. Each unit in a fight (BotTargeting): a line to its
## target.

const OBJECTIVE_RING_RADIUS: float = 2.0
const OBJECTIVE_STICK_HEIGHT: float = 3.0
const OBJECTIVE_ENTITY_HALF: float = 1.4
const POSTURE_COLORS: Dictionary = {
	BotMilitary.Posture.MASS: Color(0.3, 1.0, 0.4),
	BotMilitary.Posture.ATTACK: Color(1.0, 0.25, 0.2),
	BotMilitary.Posture.DEFEND: Color(0.3, 0.6, 1.0),
}
const MEMBER_RING_RADIUS: float = 0.6
const CENTROID_HALF: float = 0.4
const POINT_HALF: float = 0.8
## By squad name; a squad not named here (a mission's) draws in SQUAD_COLOR_OTHER.
const SQUAD_COLORS: Dictionary = {
	&"main": Color(1.0, 0.55, 0.15),
	&"reserve": Color(1.0, 0.95, 0.3),
	&"guard": Color(0.4, 0.9, 1.0),
}
const SQUAD_COLOR_OTHER: Color = Color(0.85, 0.85, 0.85)
const RALLY_STICK_HEIGHT: float = 2.0
const COLOR_RALLY: Color = Color(1.0, 0.95, 0.3)
const ABANDONED_HALF: float = 1.2
const COLOR_ABANDONED: Color = Color(0.6, 0.6, 0.6, 0.8)
const COLOR_ENGAGEMENT: Color = Color(1.0, 0.3, 0.3, 0.7)


func draw(a_bot: Bot, a_pen: BotDebugPen) -> void:
	var military: BotMilitary = _military_of(a_bot)
	if military == null:
		return
	var state: Dictionary = military.debug_state()
	var objective: Variant = military.current_objective()
	if objective != null:
		var color: Color = POSTURE_COLORS[military.current_posture()]
		a_pen.ring(objective, OBJECTIVE_RING_RADIUS, color)
		a_pen.stick(objective, OBJECTIVE_STICK_HEIGHT, color)
		var entity: Variant = state["objective_entity"]
		if is_instance_valid(entity):
			a_pen.square((entity as Node3D).global_position, OBJECTIVE_ENTITY_HALF, color)
	for squad: Squad in military.squads():
		_draw_squad(squad, a_pen)
	if state["rally"] != null:
		a_pen.stick(state["rally"], RALLY_STICK_HEIGHT, COLOR_RALLY)
	for entry: Dictionary in state["abandoned_objectives"]:
		if float(entry["until"]) > a_bot.seconds_elapsed():
			a_pen.cross(entry["position"], ABANDONED_HALF, COLOR_ABANDONED)
	var targeting: BotTargeting = _targeting_of(a_bot)
	if targeting != null:
		for e: Dictionary in targeting.engagements():
			a_pen.line(
				(e["unit"] as Node3D).global_position,
				(e["target"] as Node3D).global_position,
				COLOR_ENGAGEMENT
			)


func _draw_squad(a_squad: Squad, a_pen: BotDebugPen) -> void:
	var members: Array = a_squad.fielded()
	if members.is_empty():
		return
	var color: Color = SQUAD_COLORS.get(a_squad.name, SQUAD_COLOR_OTHER)
	for unit: Node3D in members:
		a_pen.ring(unit.global_position, MEMBER_RING_RADIUS, color)
	var centroid: Vector3 = a_squad.centroid()
	a_pen.quad(centroid, CENTROID_HALF, color)
	var point: Variant = policy_point(a_squad.policy)
	if point != null:
		a_pen.line(centroid, point, color)
		a_pen.square(point, POINT_HALF, color)


func readout(a_bot: Bot) -> PackedStringArray:
	var military: BotMilitary = _military_of(a_bot)
	if military == null:
		return PackedStringArray(["no military manager yet"])
	var state: Dictionary = military.debug_state()
	var own: float = a_bot.army_resource_value()
	var objective: Variant = military.current_objective()
	var lines: PackedStringArray = PackedStringArray(
		[
			(
				"posture: %s, %s"
				% [
					BotMilitary.Posture.keys()[military.current_posture()],
					(
						"on objective %ds" % roundi(state["on_objective"])
						if objective != null
						else "no objective"
					)
				]
			),
			_wave_line(military, state),
			(
				"attack ratio %.2f, needs %.2f (stalemate %ds)"
				% [
					military.attack_ratio(own),
					military.required_attack_ratio(),
					roundi(state["stalemate"])
				]
			),
			(
				"army %d energy; enemy estimate %d (believed now %d)"
				% [
					roundi(own),
					roundi(state["enemy_estimate"]),
					roundi(a_bot.believed_enemy_army_value())
				]
			),
		]
	)
	var momentum: BotMomentum = brain_of(a_bot).get_momentum()
	if momentum != null:
		lines.append(
			(
				"momentum %+.1f/s, losing %.1f%%/s%s"
				% [
					momentum.value_slope_per_second(),
					momentum.loss_rate() * 100.0,
					" — LOSING" if momentum.is_losing() else ""
				]
			)
		)
	for squad: Squad in military.squads():
		lines.append(
			(
				"  %s: %d (%s)"
				% [
					squad.name,
					squad.size(),
					squad.policy.kind() if squad.policy != null else "none"
				]
			)
		)
	var targeting: BotTargeting = _targeting_of(a_bot)
	if targeting != null:
		lines.append("in a fight: %d" % targeting.engagements().size())
	return lines


static func _wave_line(military: BotMilitary, state: Dictionary) -> String:
	if state["wave_active"]:
		var launched: float = state["wave_launch_value"]
		return (
			"wave: %d of %d launched (spent at %d, retreat below %d)"
			% [
				roundi(state["wave_value"]),
				roundi(launched),
				roundi(launched * BotMilitary.WAVE_SPENT_FRACTION),
				roundi(launched * military.wave_abort_fraction),
			]
		)
	if float(state["regroup_left"]) > 0.0:
		return "wave: regrouping, %ds left" % roundi(state["regroup_left"])
	return "wave: none"


## The point `policy` keeps its squad at, or null for a policy with none (or no policy).
static func policy_point(policy: SquadPolicy) -> Variant:
	if policy == null or not ("point" in policy):
		return null
	return policy.get("point")


static func _military_of(bot: Bot) -> BotMilitary:
	var brain: BotBrain = brain_of(bot)
	return brain.get_military() if brain != null else null


static func _targeting_of(bot: Bot) -> BotTargeting:
	var brain: BotBrain = brain_of(bot)
	return brain.get_targeting() if brain != null else null
