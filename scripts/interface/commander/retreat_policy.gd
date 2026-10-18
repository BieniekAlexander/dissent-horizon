class_name RetreatPolicy
extends SquadPolicy

## Get out of the fight: take cover in the nearest garrison that admits the unit, else WALK —
## a plain move, never an attack-move, so nothing en route turns it back — to the retreat
## point, or to the nearest own structure when there is none. One definition of retreating,
## shared by the bot's preservation (a hurt unit in a hopeless fight) and a mission's tactic
## rule (gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders).
## An arrived member is left standing, as a post's is (PostPolicy).

## Where to fall back to, or null for each member's nearest own structure (the bot's base, when
## it has none).
var point: Variant
var _act: BotActuator
var _bot: Bot


func _init(a_bot: Bot, a_act: BotActuator, a_point: Variant = null) -> void:
	_bot = a_bot
	_act = a_act
	point = a_point


func issue(a_members: Array) -> void:
	for unit: Actor in a_members:
		var host: Actor = _bot.nearest_garrison_for(unit)
		if host != null and _act.garrison_into(unit, host):
			continue
		var to: Vector3 = destination_for(unit)
		if unit.global_position.distance_to(to) > PostPolicy.HOLD_RADIUS:
			_act.move([unit], to)


## Where `a_unit` falls back to when no cover takes it.
func destination_for(a_unit: Actor) -> Vector3:
	if point != null:
		return point
	var nearest: Actor = _bot.nearest_own_structure(a_unit.global_position)
	return nearest.global_position if nearest != null else _bot.home_centroid()


func same_as(a_other: SquadPolicy) -> bool:
	return a_other is RetreatPolicy and (a_other as RetreatPolicy).point == point


func kind() -> StringName:
	return &"retreat"


func destination() -> Variant:
	return point
