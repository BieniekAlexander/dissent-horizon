class_name MoveCommand

#region Constants
static var command_class: bool = true

enum PreconditionFailureCause {
	NONE,
	NOT_ENOUGH_ENERGY,
	NOT_ENOUGH_INFRASTRUCTURE,
	NOT_ENOUGH_DOMINION,
	MISSING_STRUCTURE,
	INVALID_PLACEMENT,
	# The ability has no charges available right now (still reloading).
	ABILITY_NO_CHARGES,
	UNENUMERATED_FAILURE_CAUSE,
	# Not a failure: the command is entered but still waiting on the player to
	# pick the tool/option it needs (e.g. Build with no structure chosen yet).
	COMMAND_PENDING_TOOL,
	## Aimed at ground nobody on this side is spotting — the Colonial bombardment gate.
	## Its own cause rather than INVALID_PLACEMENT, which is about a STRUCTURE's footprint
	## and drives the build-preview ghost: sharing it would tint a preview that isn't there
	## and, worse, tell the player their placement is bad when the problem is that they have
	## no eyes on the target.
	TARGET_NOT_SPOTTED,
	## Every docking pad on the producing airfield is already spoken for, so an aircraft
	## trained here would have nowhere to stand. Its own cause rather than a resource one:
	## the remedy is a building or a sortie, not money, and unlike the resource causes it is
	## never deferred by the additive modifier — waiting will not conjure a pad.
	NO_FREE_PAD,
	## The caster is a structure its commander cannot power: infrastructure upkeep exceeds
	## capacity, so the building is dark (see Commandable.is_unpowered). Its own cause rather
	## than ABILITY_NO_CHARGES, whose remedy is only time — this one is cleared by building an
	## infrastructure provider, and never by waiting.
	UNPOWERED,
	## A cast that acts on one unit, pointed at nothing it may act on. Its own cause because
	## the remedy is WHERE the player points, which no other cause says. Never deferred.
	NO_VALID_TARGET,
	## A structure's footprint overlaps a site this side has already planned a building on —
	## the ground is free, but something has claimed it. Its own cause so the refusal says so;
	## it reddens the placement ghost exactly as INVALID_PLACEMENT does (see is_placement_refusal).
	SITE_PLANNED,
	## A producer with no whole side left on walkable ground: a unit finishing training here
	## would have nowhere to appear. Placement can no longer create this (NavPlacement, asked
	## by Build.meets_precondition), so reaching it takes terrain changing under a standing
	## structure or one authored into a pocket — rare, but the training order still has to
	## refuse rather than spawn a unit into a sealed room. Its own cause rather than
	## NO_FREE_PAD, whose remedy is the same shape (nowhere for the trained thing to go) but a
	## different fact (a full airfield, not a walled-in building).
	NO_NAVMESH_ACCESS,
	## An upgrade the commander already owns or is already researching. Its own cause because
	## nothing clears it: an upgrade is bought once (see Commander.is_research_taken).
	ALREADY_RESEARCHED,
}

## The causes a player can clear BY MOVING THE POINTER — the order is fine, this spot is not.
##
## The distinction the cursor draws (see RTSController._cursor_for_precondition) and the only
## question a player actually asks of a refusal: keep looking for a better spot, or give up on
## the order? A positional cause answers "keep looking"; every other cause answers "give up" —
## no amount of aiming conjures energy, a prerequisite structure, a charge or a free pad.
##
## COMMAND_PENDING_TOOL is deliberately absent: it is not a failure at all, and the caller
## handles it before asking.
const POSITIONAL_FAILURE_CAUSES: Array = [
	PreconditionFailureCause.INVALID_PLACEMENT,
	PreconditionFailureCause.SITE_PLANNED,
	PreconditionFailureCause.TARGET_NOT_SPOTTED,
	PreconditionFailureCause.NO_VALID_TARGET,
]


## Whether `a_cause` is one the player clears by aiming somewhere else.
static func is_positional_failure(cause: PreconditionFailureCause) -> bool:
	return POSITIONAL_FAILURE_CAUSES.has(cause)


## Whether `a_cause` refuses a structure's FOOTPRINT — what reddens the placement ghost and grid.
static func is_placement_refusal(cause: PreconditionFailureCause) -> bool:
	return (
		cause == PreconditionFailureCause.INVALID_PLACEMENT
		or cause == PreconditionFailureCause.SITE_PLANNED
	)


static var precondition_message_map: Dictionary = {
	PreconditionFailureCause.NONE: "",
	PreconditionFailureCause.NOT_ENOUGH_ENERGY: "Not enough energy",
	PreconditionFailureCause.NO_FREE_PAD: "No free pad",
	PreconditionFailureCause.NOT_ENOUGH_INFRASTRUCTURE: "Not enough infrastructure",
	PreconditionFailureCause.NOT_ENOUGH_DOMINION: "Not enough dominion",
	PreconditionFailureCause.MISSING_STRUCTURE: "Required structure missing",
	PreconditionFailureCause.INVALID_PLACEMENT: "Invalid Placement",
	PreconditionFailureCause.ABILITY_NO_CHARGES: "Ability recharging",
	PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE: "Unspecified failure",
	PreconditionFailureCause.COMMAND_PENDING_TOOL: "Select an Option",
	PreconditionFailureCause.TARGET_NOT_SPOTTED: "No eyes on that ground",
	PreconditionFailureCause.UNPOWERED: "Not enough infrastructure to power it",
	PreconditionFailureCause.NO_VALID_TARGET: "No valid target",
	PreconditionFailureCause.SITE_PLANNED: "Already planned there",
	PreconditionFailureCause.NO_NAVMESH_ACCESS: "Nowhere for the unit to appear",
	PreconditionFailureCause.ALREADY_RESEARCHED: "Already researched",
}

static var unmet_need_to_precondition: Dictionary = {
	TechnologySpec.UnmetNeed.NONE: PreconditionFailureCause.NONE,
	TechnologySpec.UnmetNeed.NOT_ENOUGH_ENERGY: PreconditionFailureCause.NOT_ENOUGH_ENERGY,
	TechnologySpec.UnmetNeed.NOT_ENOUGH_INFRASTRUCTURE:
	PreconditionFailureCause.NOT_ENOUGH_INFRASTRUCTURE,
	TechnologySpec.UnmetNeed.NOT_ENOUGH_DOMINION: PreconditionFailureCause.NOT_ENOUGH_DOMINION,
	TechnologySpec.UnmetNeed.MISSING_STRUCTURE: PreconditionFailureCause.MISSING_STRUCTURE,
	TechnologySpec.UnmetNeed.ALREADY_RESEARCHED: PreconditionFailureCause.ALREADY_RESEARCHED,
}
#endregion


#region Preconditions
static func tool_applies_to(_command_tool_name: String, _entity: Entity) -> bool:
	return false


static func requires_position() -> bool:
	## Indicates whether this command requires a specified position to be issued
	return true


## Whether `a_actor` is temporarily unable to perform this command for a reason that will
## resolve ON ITS OWN — a cooldown, a spent charge — as opposed to one needing the player
## to do something about it.
##
## Deliberately separate from `meets_precondition`, and asked of the ACTOR alone with no
## message: those are two different questions with two different answers. A recharging
## ability must still be ORDERABLE (the actor holds the order and acts the moment it is
## ready, which is what makes "fire as soon as you can" expressible), so a cooldown must
## not fail the precondition. But the button has to say so, or the player is left clicking
## something that appears to do nothing. This is what the HUD greys on.
static func actor_is_recharging(_actor: Commandable) -> bool:
	return false


## Whether `a_message` is out of `a_range` for an actor that CANNOT CLOSE THE DISTANCE.
##
## A mobile actor walks into range, so a far-off target is just a longer order. An immobile
## one — a structure, a grounded emplacement — would sit on an order it can never fulfil,
## which reads as the ability being broken. Refusing at order time says so immediately.
##
## Only commands with a reach call this: a global-range ability (Bombard) has no distance
## to be out of.
static func unreachable_for_immobile(
	actor: Commandable, message: CommandMessage, range: float
) -> bool:
	if actor == null or message == null or actor.can_move():
		return false
	return actor.hull().distance_to_point(message.xz_position) > range


## Whether the members of the selection that do NOT receive this order should be given a
## plain move to the same target instead of being skipped. Defaults FALSE — Embark is the one
## command that opts in today.
## Why an order aimed at a PLACE wants the other answer:
## gdd/systems/commands/the-click-ladder.md §What the members that do NOT receive the order do.
static func bystanders_move() -> bool:
	return false


#region Cast arity
## HOW MANY OF THE SELECTED ACTORS CARRY THIS ORDER OUT when no modifier is held.
##
## The modifiers were always absolute — `modifier_narrow` yields one actor,
## `modifier_broaden` yields all — and the matrix note has said so since they were written:
## "whichever way the command's own default falls". This is that default, which until now
## every command shared. See gdd/systems/ux/ui/control-matrices.md §Cast arity.
##
##   ALL     the order is for everyone who can take it. Every ordinary verb: a move, an
##           attack, a stop. Telling a squad to advance and having one of them go would be
##           absurd.
##   SINGLE  the order is a JOB, and giving it to the whole selection wastes the rest.
##           Build is the shipped case — five builders answering one placement is four
##           builders not building anything else — and it is the default for an ABILITY,
##           where the whole selection firing at one point spends every charge on it.
enum CastArity { SINGLE, ALL }


## The arity of this command for `a_message`.
##
## Takes the MESSAGE because arity is not always a fact about the command class: every
## ability is the same `Ability` command, and whether it is cast by one piece or by all of
## them is authored per ABILITY (`cast_by:` on its doc). A command whose answer is fixed
## ignores the argument.
static func default_cast_arity(_message: CommandMessage) -> CastArity:
	return CastArity.ALL


## Whether `actor` is FREE to take this order when it is narrowed to one actor: free ones are
## preferred over busy ones however far away, and only then does distance decide.
##
## Idle, for an ordinary verb narrowed by `modifier_narrow`. A command that goes to ONE actor
## by default — a job — overrides it with `holds_none_of`: free unless already holding an
## order of that job, current or queued, so a spare worker is taken before a farther idle one
## and one already on the job is passed over. Every such command answers the same way.
## Rules: gdd/systems/ux/ui/selection-and-input.md §The narrow modifier picks the nearest IDLE
## actor.
static func is_free_to_take(actor: Commandable) -> bool:
	return actor.current_command() == null


## Whether no order in `actor`'s chain, current or queued, is one of `commands`.
static func holds_none_of(actor: Commandable, commands: Array[Script]) -> bool:
	return not actor.get_command_chain().any(
		func(held: MoveCommand) -> bool:
			return commands.any(func(command: Script) -> bool: return is_instance_of(held, command))
	)


#endregion


## Checks whether the relevant command is allowable, given the situation
static func meets_precondition(
	_actor: Commandable, _message: CommandMessage
) -> PreconditionFailureCause:
	# examples:
	# - can the unit can perform this operation on the specified target?
	# - can the unit can place the specified building in the specified position?
	return PreconditionFailureCause.NONE


#endregion

#region Properties
var message: CommandMessage

## Whether this command has ever been its receiver's ACTIVE command. Set by the receiver. A
## command that only ever waited in the queue has held nothing on the world's behalf, so it is
## dropped without on_released (see CommandReceiver._release_dropped).
var has_been_active: bool = false

## Counts down toward the next per-second destination-swap check (see
## _resolve_destination_swap). Only meaningful for a plain MoveCommand instance,
## since subclasses (Patrol, Attack, Defend, ...) override get_updated_state()
## without calling super and so never run this check.
var _swap_cooldown: float = 0.0

#endregion


#region State updates
## Potentially return a new command based on a state check. A plain MoveCommand
## never reactively retargets on its own — it always returns self. Aggro-based
## retargeting (chasing down a nearby enemy) is opt-in per subclass (see
## AttackMove, Patrol, Defend), not a base-class behavior every command inherits.
func get_updated_state(a_commandable: Commandable) -> Variant:
	_swap_cooldown -= 1.0 / TimeUtils.ticks_per_second()
	if _swap_cooldown <= 0.0:
		_swap_cooldown = 1.0
		_resolve_destination_swap(a_commandable)
	return self


## Once a second, check every sibling unit sharing this exact multi-unit move
## order (same CommandMessage.origin — see RTSController.assign_command_to_units)
## for a beneficial destination swap: if trading destinations would shorten both
## units' remaining paths, swap them and retarget both units' Movement immediately.
## This corrects crossing paths that develop after the angular-sort assignment at
## issue time — e.g. once RVO avoidance nudges a unit off its straight-line course.
## Whether two command messages came from the SAME player order — the only condition
## under which their units may trade destinations. Identity of the order's token, not
## equality of anything in it: two separate orders that happen to look alike are still
## separate orders. An untagged message (null origin) is nobody's sibling, including
## its own, so single-unit and script-issued commands never swap.
static func is_same_order(mine: CommandMessage, other: CommandMessage) -> bool:
	if mine == null or other == null or mine.origin == null:
		return false
	return is_same(mine.origin, other.origin)


func _resolve_destination_swap(a_commandable: Commandable) -> void:
	if message.origin == null or message.target != null:
		return
	if a_commandable.movement == null or a_commandable.movement.is_navigation_finished():
		return
	if a_commandable.commander == null:
		return

	var my_dest: Vector3 = message.position
	for other in a_commandable.commander.get_children():
		if not (other is Commandable) or other == a_commandable:
			continue
		var other_unit: Commandable = other as Commandable
		var other_cmd: MoveCommand = other_unit.current_command()
		if other_cmd == null or not is_same_order(message, other_cmd.message):
			continue
		if other_cmd.message.target != null:
			continue
		if other_unit.movement == null or other_unit.movement.is_navigation_finished():
			continue

		var other_dest: Vector3 = other_cmd.message.position
		var my_dist: float = a_commandable.global_position.distance_to(my_dest)
		var other_dist: float = other_unit.global_position.distance_to(other_dest)
		var swap_my_dist: float = a_commandable.global_position.distance_to(other_dest)
		var swap_other_dist: float = other_unit.global_position.distance_to(my_dest)

		if swap_my_dist + swap_other_dist < my_dist + other_dist:
			message.world_position = other_dest
			other_cmd.message.world_position = my_dest
			a_commandable.locomotion.set_goal(message.position)
			other_unit.locomotion.set_goal(other_cmd.message.position)
			my_dest = other_cmd.message.position


## An independent copy of this command, for handing to a DIFFERENT actor than the one it was
## built for — a rally order replayed onto each newly trained unit. The message is deep-copied
## and `origin` is dropped, so inheritors are not treated as siblings of the order that set
## the rally. A subclass whose `_init` takes more than a lone CommandMessage (Patrol) must
## override this. Why: gdd/systems/commands/construction.md §Rally / release destinations.
func duplicated() -> MoveCommand:
	var copy_message: CommandMessage = CommandMessage.deep_copy(message)
	copy_message.origin = null
	return (get_script() as GDScript).new(copy_message)


## Whether this command's characteristic action is suppressed while the actor is
## staggered (recently damaged). Default false: most actions ignore stagger. A command
## representing a channeled / vulnerable action (Build, Repair, and some Interactions)
## overrides this to opt in — the actor still moves into range but waits, not completing
## the action, until the stagger wears off. Enforced in CommandReceiver._process_commands.
func blocked_by_stagger(_a_commandable: Commandable) -> bool:
	return false


## Check if the [Commandable] should move in response to the command
func should_move(_a_commandable: Commandable) -> bool:
	return true


## Whether issuing this order INTERRUPTS what the actor was doing rather than replacing it.
##
## An ordinary order given without the additive modifier clears the queue: the player has said
## "forget that, do this". A few orders are not a change of plan at all but a thing to do ON
## THE WAY, and for those the queue should survive — the order takes over now, whatever was
## running goes to the FRONT of the queue, and the actor picks it back up when this one ends.
##
## `Evacuate` is the case that prompted it: a transport with a route queued, told to turn its
## garrison out, should do that and then carry on along the route. Losing the route means
## re-issuing it every time you drop off a squad.
##
## Defaults FALSE, so every existing order keeps the standing "replace" behaviour; only the
## ones that are an aside opt in. It changes nothing while `modifier_additive` is held — that
## already appends, which is what an interrupt is a non-additive version of.
static func is_interrupt() -> bool:
	return false


## Whether this order is pointless without ammunition — i.e. it exists in order to shoot.
##
## Deliberately NOT true of a plain move: an order that ASSUMES it will attack is stood down,
## an order that merely goes somewhere is kept and obeyed. Only meaningful for a CHARGED
## loadout, the one kind that can be observed empty with no way to refill itself.
## Why: gdd/systems/combat/aerial-operations/rearm-and-resupply.md §Breaking off and resuming.
func requires_ammo() -> bool:
	return false


## A destination this command names for itself, overriding the usual resolution from
## message.target / message.position, or null to use that. Lets an order fly somewhere its
## target is not — a Rearm heads for its runway's final-approach fix rather than the
## airfield's origin, because joining the centreline is the point of having a runway.
func movement_destination(_a_actor: Commandable) -> Variant:
	return null


## The commandable this order's actor should IGNORE in RVO avoidance while it runs, or null
## for none. Null is the ordinary answer: only an order whose whole point is to close with
## another unit has one.
##
## Why it exists: gdd/systems/combat/garrison-and-transport.md §Meeting in the middle.
func avoidance_exception(_a_actor: Commandable) -> Commandable:
	return null


## Whether the actor is standing its ground to act — in reach and firing — and so should
## refuse to step aside for friendly units in RVO. False for anything still travelling.
##
## Why: gdd/systems/terrain-and-navigation/navigation-and-pathing.md §Avoidance priority.
func holds_ground(_a_actor: Commandable) -> bool:
	return false


## Where an actor that cannot stop — a fixed wing — circles once this order has acted or ended
## without driving it: the order's own position, or null to keep the circuit it is flying.
func orbit_anchor(_a_actor: Commandable) -> Variant:
	return message.position


## Whether receiving this order lifts the actor's hold fire (Commandable.is_holding_fire).
## True only for the orders whose point is to shoot: Attack, Attack-move, Force Fire
## (FocusFire) and Defend.
func releases_hold_fire() -> bool:
	return false


## Whether REACHING the destination completes this command.
##
## True for a plain move, whose entire purpose is arrival. False for any command that travels
## in order to then DO something in range (Build, Assemble, Repair, Rearm): for those,
## arriving is the setup, and `can_act` — not the navigation agent — decides when it is done.
##
## Defaults TRUE so every existing command keeps its behaviour; only the ones that act on
## arrival opt out. What a missing override cost: CLAUDE.md §Command system.
func ends_on_arrival() -> bool:
	return true


## Check if the [Commandable] is ready to [fulfill_action]
func can_act(_a_commandable: Commandable) -> bool:
	return false


## What the actor is doing on a tick this command acts — read BEFORE fulfill_action, so a
## command that finishes on the tick still reports it. For its animation and action badge.
func acting_action(_a_actor: Commandable) -> ActionTracker.Action:
	return ActionTracker.Action.ACTING


## Perform the characteristic action of this command and return whatever might be a follow-up
## [MoveCommand], or null otherwise
func fulfill_action(_a_commandable: Commandable) -> Variant:
	push_error("no action should have been performed")
	return self


## Called once this command has genuinely LEFT its receiver — completed, replaced by a new
## order, or cleared, whether it was active or displaced into the queue by an interrupt — but
## NOT when it is merely displaced, since it will resume. A command that never became active
## is not called. Override to release anything the command was holding on the world's behalf.
##
## Deliberately not `_notification(PREDELETE)`: a destructor runs whenever the last
## reference happens to drop, which for a unit that dies mid-command is DURING its own
## teardown, where reading the actor's components dereferences freed memory (see
## CommandReceiver._release_speed_cap for the segfault that taught us). This hook fires
## from the receiver instead, at a moment when `a_actor` is known to be alive.
func on_released(_a_actor: Commandable) -> void:
	pass


#endregion


#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	message = a_message
	message.retain()
	# A purchase-backed command (a Build) counts as a live holder of that purchase. The
	# count spans the WHOLE order — every builder's snapshot shares one transaction — so
	# the reserved cost is refunded only once the last of them is gone. Handled here
	# rather than in Build so it applies uniformly however the command was constructed.
	if message.transaction != null:
		message.transaction.retain_holder()


## Reference-count bookkeeping ONLY. Everything here must be safe to run at an arbitrary
## moment, because a RefCounted's destructor fires whenever its last reference happens to
## drop — for a unit that dies mid-command, that is inside its own teardown.
##
## IT MUST NOT REACH INTO THE ACTOR, and `is_instance_valid()` cannot make it safe to: the
## ObjectDB entry outlives the destructor while the script instance behind a component read
## does not. Why, and the segfault that taught it:
## gdd/systems/combat/bombardment.md §on_released.
func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE:
		if message != null:
			if message.transaction != null:
				message.transaction.release_holder()
			message.release()


#endregion


#region Debug
func _to_string() -> String:
	return "MoveCommand: %s" % message.position
#endregion
