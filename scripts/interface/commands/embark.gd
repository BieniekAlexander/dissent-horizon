class_name Embark
extends MoveCommand

## The HOST side of a garrison order: "you there, get in".
##
## The player selects a commandable that owns a [Garrison], right-clicks a friendly unit it
## would admit, and the order is issued in TWO halves at once — this one to the host, and an
## [Occupy] to the unit being called. Occupy is still the only thing that puts a unit inside
## a garrison; this command hands one out and then gets out of the way.
##
## The host's own half is a FOLLOW, so the two meet in the middle instead of making the
## passenger do all the travelling: a plain move at a friendly unit is already a follow
## (CommandReceiver._follow_target), and this inherits that unchanged. An IMMOBILE host —
## a bunker — simply stands still, and the order is then nothing but the Occupy it handed
## out, which is exactly what it is for.
##
## It ends when the unit it was calling becomes unavailable: boarded (the occupant leaves
## the scene tree), or dead. That is the only end condition, and it is the same one a
## follow has.
##
## EXACTLY ONE HOST CARRIES THIS per order, settled at issue time — see nearest_host, and
## bystanders_move for what the rest of the selection gets.


#region Preconditions
static func requires_position() -> bool:
	return true


## Valid when the actor's garrison would take the hovered unit AND has room for it right
## now. The masks half is Occupy's rule, asked through Occupy.host_admits so the two sides
## of the mechanic cannot disagree; the ROOM half is this command's own, because a player
## hovering a unit is asking whether calling it in would achieve anything, and calling one
## into a full hold would not.
static func meets_precondition(
	actor: Actor, message: CommandMessage
) -> PreconditionFailureCause:
	if actor == null or not is_instance_valid(actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not is_instance_valid(message.target) or not (message.target is Actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var occupant := message.target as Actor
	var garrison := actor.get_node_or_null("Garrison") as Garrison
	if garrison == null or not garrison.has_room_for(occupant):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not Occupy.host_admits(occupant, actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## The one host that takes this order out of `a_hosts`: the applicable one NEAREST the unit
## being called. Returned as a list so the caller's per-actor loop needs no special case.
##
## An order to a group of transports is an order to COLLECT that unit, and collecting it
## twice is not a thing — so the group does not all converge on one passenger. Everything
## else selected still moves to the same place (bystanders_move); it just does not try to
## load anybody.
##
## Static and message-only so the rule can be pinned without a scene tree.
static func nearest_host(hosts: Array, message: CommandMessage) -> Array:
	var best: Actor = null
	var best_distance: float = 0.0
	for node: Node in hosts:
		var host := node as Actor
		if host == null or not is_instance_valid(host):
			continue
		var distance: float = host.xz_position.distance_to(message.xz_position)
		if best == null or distance < best_distance:
			best = host
			best_distance = distance
	return [] if best == null else [best]


## The rest of the selection follows the unit too, rather than being skipped the way an
## incapable actor normally is. Right-clicking a friendly unit with a transport and four
## soldiers selected means "everyone go there, and you pick him up" — dropping the soldiers'
## half of it would leave four units standing still for an order the player plainly gave.
##
## This is the narrow form of a rule the control matrix wants everywhere (an actor that
## cannot carry out the resolved command falls back to a move at the same target); it is
## turned on for this command alone until that redesign lands.
static func bystanders_move() -> bool:
	return true


#endregion

#region Properties
## Whether the Occupy half has been handed out. Framework-imposed state in the sense §1.1
## allows: the order has a one-off effect and a per-tick body, and the tick is the only
## place with an actor to issue it from.
var _occupant_ordered: bool = false
#endregion


#region State updates
## Hands the Occupy out on the first tick — not at construction — so a QUEUED Embark does
## not order the passenger aboard while the host is still busy with something else. The
## occupant's own orders are REPLACED, matching a right-click: being called into a
## transport is an order like any other.
func get_updated_state(a_actor: Actor) -> Variant:
	var occupant := message.target as Actor
	# is_instance_valid() still reports true for a unit that has GARRISONED — entering a
	# garrison orphans the node without freeing it — so tree membership is what says the
	# order is finished. The dead case reads the same way and wants the same answer.
	if occupant == null or not is_instance_valid(occupant) or not occupant.is_inside_tree():
		return null
	if not _occupant_ordered:
		_occupant_ordered = true
		_order_occupant(a_actor, occupant)
	return self


## The passenger it called in. The host side of the same exemption Occupy states: the two are
## driving at each other on purpose, so neither may steer around the other.
func avoidance_exception(_a_actor: Actor) -> Actor:
	return message.target as Actor if is_instance_valid(message.target) else null


## Only a host that can actually walk goes anywhere. A bunker's whole half of this order is
## the Occupy it already handed out, and driving it would be nonsense.
func should_move(a_actor: Actor) -> bool:
	return a_actor.can_move()


## Meeting the passenger is not the end of the order — boarding is — so arriving must not
## drop it. (A follow keeps its command on arrival anyway; stating it here means an
## immobile host, which never follows, behaves the same way.)
func ends_on_arrival() -> bool:
	return false


## Never acts: everything this command does to the world it does through the Occupy it
## issued, and the boarding itself is that command's fulfil_action.
func can_act(_a_actor: Actor) -> bool:
	return false


#endregion


#region Private helpers
func _order_occupant(a_host: Actor, a_occupant: Actor) -> void:
	var order := CommandMessage.new(message.map)
	order.target = a_host
	order.world_position = a_host.global_position
	a_occupant.update_commands(Occupy.new(order))


#endregion


#region Debug
func _to_string() -> String:
	return "Embark: %s" % message.position
#endregion
