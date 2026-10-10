class_name PostPolicy
extends SquadPolicy

## Stand at a point: attack-move there, then stand. The shared half of StagePolicy and
## HoldPolicy, which differ in what the decision side means by them — a reserve waiting to be
## released, an army with nowhere to go — and not in the order given. Both leave an arrived
## member IDLE on purpose: an idle unit is what BotOpportunist sends into a bunker near it,
## and what the next policy picks up.
##
## TODO: the design table names `Defend` posts for Hold — a leashed guard that chases an
## intruder and returns. A Defend order never goes idle (it IS the standing order), so it
## would blind the bunker opportunity and the idle sweep to every held unit; the cover rule
## (squads-and-relations.md §Cover) has to move onto the policy first.

## A member this close to its post (world units) has ARRIVED and is left standing rather than
## re-ordered every think. Arriving is a navigation radius, not a point, and a unit told to
## walk to where it stands swirls — which, re-issued every combat period to a whole army, is
## the swarm around a point that was reported.
const HOLD_RADIUS: float = 4.0

var point: Vector3
## How far the post may move and still be the same post.
var epsilon: float
var _act: BotActuator


func _init(a_act: BotActuator, a_point: Vector3, a_epsilon: float) -> void:
	_act = a_act
	point = a_point
	epsilon = a_epsilon


func issue(a_members: Array) -> void:
	var to_send: Array = a_members.filter(
		func(unit: Actor) -> bool:
			return unit.global_position.distance_to(point) > HOLD_RADIUS
	)
	if not to_send.is_empty():
		_act.attack_move(to_send, point)


func same_as(a_other: SquadPolicy) -> bool:
	return (
		a_other.get_script() == get_script()
		and (a_other as PostPolicy).point.distance_to(point) <= epsilon
	)


func destination() -> Variant:
	return point
