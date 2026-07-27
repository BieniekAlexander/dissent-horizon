class_name Bombard
extends Ability

## Drop a shell on ground the commander's side is SPOTTING — the Colonial artillery
## strike, ordered onto a point rather than onto a target.
##
## AN ABILITY WHOSE REACH IS NOT A DISTANCE, which is the whole design. A Bombard can hit
## anywhere on the map; what limits it is not range but whether anyone of its side can see
## where the shell is going (see [BombardTargeting]). So the gun is worth nothing on its own
## and everything beside a spotter, and the counter to a battery is to kill whatever is
## spotting for it rather than to out-range it.
##
## THAT IS ALL THIS CLASS SAYS. It was once a sibling of [Ability] rather than a subclass,
## duplicating the whole charge/precondition/emission shape, because Ability hardcoded one
## reach for every ability and there was no way to substitute a different question. Reach is
## now overridable, so the difference is three small overrides and the beacon it burns.
##
## The Bombard has NO weapon and no aggro shape, which is what makes this a command and
## not a Weapon: a Weapon brings an AttackRange, an aggro pickup and automatic firing with
## it, and all three are wrong here. Every shot this piece takes is one the player asked
## for, at a point the player chose.

## The ability this command spends. Hand-written code names abilities through this rather
## than by literal, the same way it names pieces through EntityIds.
const ABILITY_ID: StringName = &"bombard"

#region Reach
## Spotted, not near. Asked of the commander's side rather than of this gun, which is what
## "vision by proxy" means.
static func is_in_range(actor: Commandable, message: CommandMessage) -> bool:
	return actor != null and message != null and actor.commander != null \
		and BombardTargeting.is_spotted(actor.commander, message.position)


## No amount of driving makes an unspotted point spotted — and the gun is a structure that
## could not drive anyway. Being false here is also what keeps `should_move` false.
static func range_closes_by_moving() -> bool:
	return false


## An unspotted point is not bad PLACEMENT; it has its own cursor and its own refusal.
static func out_of_range_cause() -> PreconditionFailureCause:
	return PreconditionFailureCause.TARGET_NOT_SPOTTED
#endregion

#region Preconditions
## The shared ability precondition — granted, charged, in reach — plus the one thing that is
## this piece's alone: an unfinished gun does not fire.
static func meets_precondition(
	actor: Commandable,
	message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	if actor == null or not actor.is_built:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return precondition_for(Bombard, actor, message)


static func requires_position() -> bool:
	return true


## This command IS one ability, so it names it rather than waiting for a caller to write it
## onto every message.
static func _ability_of(_message: CommandMessage) -> StringName:
	return ABILITY_ID
#endregion

#region State updates
func can_act(a_actor: Commandable) -> bool:
	return a_actor.is_built and super(a_actor)


## Re-check the firing solution at FIRING time, not just at ordering time: the spotter may
## have died, or its beacon been claimed by another battery, in the ticks since the order was
## given. One order, one shell — the null return ends the command, so a Bombard does not sit
## re-firing at a point the player asked about once.
##
## The shell FOLLOWS ITS SOLUTION. Fired on a beacon, it pursues the beacon — which moves
## with the unit it is attached to — and lands where the beacon last was if the beacon leaves
## play first. Fired on ground a BeaconRange covers, it lands on the point: area spotting
## places no beacon, so there is nothing to follow.
##
## The beacon is resolved BEFORE the charge is spent and MARKED used rather than dismissed:
## it has to stand for the whole flight, so it is dismissed when the shell lands
## (Beacon.dismiss_on_landing). Being used is what stops a second battery spending it.
func fulfill_action(a_actor: Commandable) -> Variant:
	if not is_in_range(a_actor, message):
		return null
	var solution: Beacon = BombardTargeting.source_at(a_actor.commander, message.position)
	if not consume(a_actor, ABILITY_ID):
		return null
	if solution == null:
		launch_emission(a_actor, ABILITY_ID, message.position)
		return null
	solution.mark_used()
	solution.dismiss_on_landing(launch_emission(a_actor, ABILITY_ID, solution.host()))
	return null
#endregion
