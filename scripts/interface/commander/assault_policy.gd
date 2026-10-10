class_name AssaultPolicy
extends SquadPolicy

## Attack-move on an objective, and raze what stands there: the wave. The objective is a
## point beside a believed structure (or where a unit was last seen), and the point lies
## OUTSIDE the aggro range a unit picks targets from on its own — so a member that has
## arrived and stands idle is ordered to Attack the remembered structure while the bot still
## believes it is standing. Waiting for a sizeable army is the commit gates' job and happens
## at home; once a wave is at the front, standing is never the plan
## (gdd/systems/ai/squads-and-relations.md §Cover, and a wave that finds nothing).

## A member counts as standing ON the objective within this of it: a few arrival radii, since
## a wave of many units spreads around the point rather than onto it.
const STALL_RADIUS: float = PostPolicy.HOLD_RADIUS * 3.0

var point: Vector3
## The remembered ENTITY behind the objective when it is a structure belief, or null. Untyped:
## a belief outlives the thing it remembers, and a freed object fails a typed field.
var target: Variant
## Its instance id, kept apart from the reference so the belief can be asked about after the
## node is freed (a freed object cannot answer get_instance_id).
var target_id: int
## How far the objective may drift and still be the same objective, moved.
var epsilon: float
var _act: BotActuator
var _bot: Bot


func _init(
	a_bot: Bot,
	a_act: BotActuator,
	a_point: Vector3,
	a_target: Variant,
	a_target_id: int,
	a_epsilon: float
) -> void:
	_bot = a_bot
	_act = a_act
	point = a_point
	target = a_target
	target_id = a_target_id
	epsilon = a_epsilon


func issue(a_members: Array) -> void:
	var arrived: Array = a_members.filter(
		func(unit: Actor) -> bool:
			return unit.global_position.distance_to(point) <= STALL_RADIUS
	)
	# The Attack order needs a live node to aim at; a believed structure whose node is already
	# gone gets no order, and the wave standing on its spot is what shows the fog it is gone
	# (the blackboard drops the belief on its next update). Knowing is the belief's job; the
	# validity test here is an actuation necessity and changes no decision.
	var razing: Array = []
	if not arrived.is_empty() and is_target_standing() and is_instance_valid(target):
		_act.attack(arrived, target as Entity)
		razing = arrived
	var to_send: Array = a_members.filter(
		func(unit: Actor) -> bool:
			return (
				unit.global_position.distance_to(point) > PostPolicy.HOLD_RADIUS
				and not razing.has(unit)
			)
	)
	if not to_send.is_empty():
		_act.attack_move(to_send, point)


## Whether the bot still BELIEVES the structure behind the objective is standing. Asked of the
## blackboard, never of the node: a wave that knew its target had fallen before any unit could
## see the spot was the fog leak world-model.md §The fog boundary lists third.
func is_target_standing() -> bool:
	return target_id != 0 and _bot.blackboard != null and _bot.blackboard.believes(target_id)


## The same objective, moved: a believed UNIT's last-known location is refreshed every
## blackboard update while it is in sight, and a drift within `epsilon` is pressed on to by
## the idle re-issue rather than re-launched (see BotMilitary.OBJECTIVE_EPSILON).
func same_as(a_other: SquadPolicy) -> bool:
	return (
		a_other is AssaultPolicy and (a_other as AssaultPolicy).point.distance_to(point) <= epsilon
	)


func kind() -> StringName:
	return &"assault"


func destination() -> Variant:
	return point
