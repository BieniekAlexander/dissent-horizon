class_name Deployable
extends Node

## A unit that can plant itself: DEPLOY stops it where it stands for a timed transition, after
## which it holds a stronger stance until it is ordered to UNDEPLOY. The doc key that creates
## it is `deploys:`. The rules — what a deployed unit gains, which orders it takes during and
## after a transition, and why it is an obstacle rather than a fixture — are
## gdd/systems/commands/deploying.md.
##
## NOT the two-form transformer (Entity.deploy / set_deployed), which trades a unit for a
## structure on a validated footprint. A deployed unit stays a unit and claims no grid cells.

enum Stance { MOBILE, DEPLOYING, DEPLOYED, UNDEPLOYING }

## How long each transition takes. Authored in seconds by the doc and converted at import.
@export var deploy_ticks: int = 90
@export var undeploy_ticks: int = 30
## Whether a relocating order (a plain move or an attack-move) given WITHOUT the additive
## modifier abandons a deploy still in progress. False: the deploy finishes regardless.
@export var is_cancellable: bool = false

var stance: Stance = Stance.MOBILE
## Ticks spent in the current transition; meaningless while settled.
var _progress_ticks: int = 0
## Whether the host is planted: locomotion off, obstacle on the standing channel. True from
## the start of a deploy to the end of an undeploy.
var _is_standing: bool = false
## The obstacle's own avoidance layers, held while it broadcasts on the standing channel.
var _mobile_obstacle_layers: int = 0

signal stance_changed(a_stance: Stance)


## The orders whose whole point is to go somewhere, which a planted unit cannot carry out.
## Named rather than derived from capability because the form an order will meet is the
## PROJECTED one (see admit), which the actor's live components do not yet show.
static func _is_relocating(a_order: MoveCommand) -> bool:
	var script: Script = a_order.get_script()
	return (
		script == MoveCommand
		or script == AttackMove
		or script == Patrol
		or script == Defend
		or script == Occupy
	)


static func of(a_entity: Node) -> Deployable:
	return a_entity.get_node_or_null("Deployable") as Deployable if a_entity != null else null


#region Queries
func is_deployed() -> bool:
	return stance == Stance.DEPLOYED


func is_transitioning() -> bool:
	return stance == Stance.DEPLOYING or stance == Stance.UNDEPLOYING


## Whether this unit's weapons may be used: never mid-transition.
func can_use_weapons() -> bool:
	return not is_transitioning()


## Whether the unit stands planted once its current transition, if any, is through.
func settles_deployed() -> bool:
	return stance == Stance.DEPLOYED or stance == Stance.DEPLOYING


## Progress through the current transition, 0..1; 1 while settled.
func transition_fraction() -> float:
	var total: int = deploy_ticks if stance == Stance.DEPLOYING else undeploy_ticks
	if not is_transitioning() or total <= 0:
		return 1.0
	return clampf(float(_progress_ticks) / total, 0.0, 1.0)


#endregion


#region Order admission
## The orders the host should actually take, from `a_orders` given with the additive
## modifier or not. Called at the one point every order enters a Commandable
## (Commandable.update_commands), and returns what the host takes plus how:
##   { "orders": Array[MoveCommand], "add_to_queue": bool, "keep_active": bool }
## `keep_active` asks the host to clear the queue but leave the running transition alone.
##
## Side effect: a cancellable deploy is abandoned here when the first order cancels it.
func admit(
	a_orders: Array[MoveCommand], a_add_to_queue: bool, a_chain: Array[MoveCommand]
) -> Dictionary:
	var add_to_queue: bool = a_add_to_queue
	var keep_active: bool = false
	var projected_deployed: bool
	if not add_to_queue and _cancelled_by(a_orders):
		abandon_transition()
		projected_deployed = false
	elif not add_to_queue and is_transitioning():
		# A transition is never interrupted by an order; the new orders replace whatever was
		# queued BEHIND it, and are judged against the form the transition ends in.
		keep_active = true
		add_to_queue = true
		projected_deployed = settles_deployed()
	elif add_to_queue:
		projected_deployed = _projected_after(a_chain, settles_deployed())
	else:
		projected_deployed = settles_deployed()
	var kept: Array[MoveCommand] = []
	for order: MoveCommand in a_orders:
		if projected_deployed and _is_relocating(order):
			continue
		if order is Deploy:
			if projected_deployed:
				continue
			projected_deployed = true
		elif order is Undeploy:
			if not projected_deployed:
				continue
			projected_deployed = false
		kept.append(order)
	return {"orders": kept, "add_to_queue": add_to_queue, "keep_active": keep_active}


func _cancelled_by(a_orders: Array[MoveCommand]) -> bool:
	if not is_cancellable or stance != Stance.DEPLOYING or a_orders.is_empty():
		return false
	var script: Script = a_orders[0].get_script()
	return script == MoveCommand or script == AttackMove


## Whether the unit stands planted after `a_chain` has run, starting from `a_deployed`.
static func _projected_after(a_chain: Array[MoveCommand], a_deployed: bool) -> bool:
	var deployed: bool = a_deployed
	for order: MoveCommand in a_chain:
		if order is Deploy:
			deployed = true
		elif order is Undeploy:
			deployed = false
	return deployed


#endregion


#region Ownership
## Record the obstacle layers the host's commander gives it. While standing they are held
## for later rather than applied, so a change of owner does not lift the standing broadcast.
## False when not standing, and the caller applies them itself.
func hold_obstacle_layers(a_layers: int) -> bool:
	if not _is_standing:
		return false
	_mobile_obstacle_layers = a_layers
	return true


#endregion


#region Transitions
## Start deploying where the unit stands. False, and nothing changed, unless it is MOBILE.
func begin_deploy() -> bool:
	if stance != Stance.MOBILE:
		return false
	_progress_ticks = 0
	_stand(true)
	_set_stance(Stance.DEPLOYING)
	return true


## Start undeploying. False, and nothing changed, unless it is DEPLOYED. The armour bonus is
## given up at once: it is paid for by being planted, and an undeploying unit is leaving.
func begin_undeploy() -> bool:
	if stance != Stance.DEPLOYED:
		return false
	_progress_ticks = 0
	_step_armour(-1)
	_set_stance(Stance.UNDEPLOYING)
	return true


## One tick of the current transition. True once it has finished (and on any settled stance).
func advance() -> bool:
	if not is_transitioning():
		return true
	_progress_ticks += 1
	var total: int = deploy_ticks if stance == Stance.DEPLOYING else undeploy_ticks
	if _progress_ticks < total:
		return false
	if stance == Stance.DEPLOYING:
		_step_armour(1)
		_set_stance(Stance.DEPLOYED)
	else:
		_stand(false)
		_set_stance(Stance.MOBILE)
	return true


## Give up a transition that has not finished: a deploy goes back to MOBILE, an undeploy
## back to DEPLOYED (with its armour). No-op while settled.
func abandon_transition() -> void:
	if stance == Stance.DEPLOYING:
		_stand(false)
		_set_stance(Stance.MOBILE)
	elif stance == Stance.UNDEPLOYING:
		_step_armour(1)
		_set_stance(Stance.DEPLOYED)
	_progress_ticks = 0


func _set_stance(a_stance: Stance) -> void:
	stance = a_stance
	stance_changed.emit(a_stance)


## Move the host's armour class `a_steps` along Defense.ArmourType, clamped to its ends.
## TODO: stepping armour is a placeholder for what deploying gains, which is to be decided
## per unit — see gdd/systems/commands/deploying.md §What a deployed unit gains.
func _step_armour(a_steps: int) -> void:
	var defense := get_parent().get_node_or_null("Defense") as Defense
	if defense == null:
		return
	var top: int = Defense.ArmourType.size() - 1
	defense.armour_type = clampi(int(defense.armour_type) + a_steps, 0, top) as Defense.ArmourType


## Plant the host (switch its locomotion off and broadcast it as a standing obstacle that
## every team steers round) or free it again.
func _stand(a_standing: bool) -> void:
	var host := get_parent() as Entity
	var movement := host.get_node_or_null("Locomotion") as Movement if host != null else null
	if movement == null or a_standing == _is_standing:
		return
	_is_standing = a_standing
	var commander_id: int = host.commander_id if host.ownership != null else 0
	var obstacle: NavigationObstacle3D = movement.avoidance_obstacle
	if a_standing:
		movement.stop()
		movement.set_active(false, commander_id)
		if obstacle != null:
			_mobile_obstacle_layers = obstacle.avoidance_layers
			obstacle.avoidance_layers = AvoidanceAgent3D.STANDING_OBSTACLE_BIT
			obstacle.avoidance_enabled = true
	else:
		if obstacle != null:
			obstacle.avoidance_layers = _mobile_obstacle_layers
		movement.set_active(true, commander_id)
	host.refresh_movement_collision()
#endregion
