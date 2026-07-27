class_name Repair
extends MoveCommand

## Restore hp to a damaged friendly MECHANICAL entity — a unit or a structure alike.
##
## This used to be the FINISH-CONSTRUCTION command (now Assemble). The two were one
## command because a half-built structure and a battered tank both want "a worker walks
## over and a number goes up", but they answer "may I be worked on?" differently and are
## offered by different units, so the split is at the precondition and everything below
## it follows.
##
## WHO may repair is the actor's `Repairs` component, and presence is the entire check —
## see Repairs for why the capability is a node rather than a bool. WHAT may be repaired
## is stated once, in `repairable_cause` below, so the resolution ladder, the HUD and
## can_act can never disagree about it.

#region Preconditions
## Only MECH-framed things can be repaired. Frame, not armour: this codebase's armour
## axis is LIGHT/MEDIUM/STRONG (how hard you are to hurt) while the frame axis is
## BIO/MECH (what you are made of), and "a mechanic mends machines" is the second.
## Biological units are mended by HealAOE instead.
const REPAIRABLE_FRAME: Defense.FrameType = Defense.FrameType.MECH

## Why `a_message.target` cannot be repaired by `a_actor` right now, or NONE when it can.
##
## The single statement of the rule. Everything that asks — the precondition,
## CommandContextParser's button, RTSController's right-click ladder, can_act — comes
## through here, so a target the cursor offers is a target the command will accept.
##
## UNENUMERATED_FAILURE_CAUSE for every rejection: the failure causes are a HUD
## vocabulary about resources and placement, and none of them says "wrong target".
static func repairable_cause(
	actor: Commandable,
	target: Variant
) -> MoveCommand.PreconditionFailureCause:
	if actor == null or actor.get_node_or_null("Repairs") == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not (target is Commandable) or not is_instance_valid(target):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var subject: Commandable = target as Commandable
	# Repair is also how a planted charge is got rid of: a charge on the ground is repaired away
	# outright, by an opponent or by its owner, and an enemy beacon or charge riding on your own
	# piece comes off when it is mended — however whole the piece is. See
	# gdd/systems/combat/planted-explosives.md §Defusing.
	if _defuses(actor, subject):
		return PreconditionFailureCause.NONE
	# Friendly only, and specifically SAME-COMMANDER rather than merely non-hostile:
	# a neutral (commander 0) building is nobody's to mend.
	if subject.commander_id != actor.commander_id or subject.commander_id <= 0:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# A blueprint isn't damaged, it is unbuilt; an unfinished structure is Assemble's job.
	# Both would otherwise read as "hp below max" and be silently repaired to completion.
	if subject.is_planned or not subject.is_built:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var defense: Defense = subject.get_node_or_null("Defense") as Defense
	if defense == null or defense.frame_type != REPAIRABLE_FRAME:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# Undamaged targets are refused so a right-click on an intact friendly falls through
	# the ladder to a plain move (or to Occupy, for a transport) instead of issuing an
	# order with nothing to do.
	if defense.hp >= defense.hp_max:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE

## Whether repairing `a_subject` would take a marker out of play: it is a charge standing on
## the ground (anyone's but a neutral's), or `a_actor`'s own piece with an enemy beacon or
## charge riding on it.
static func _defuses(actor: Commandable, subject: Commandable) -> bool:
	if PlantedCharge.of(subject) != null:
		return not PlantedCharge.is_riding(subject) and (actor.is_enemy_of(subject)
			or subject.commander_id == actor.commander_id)
	return subject.commander_id == actor.commander_id and subject.has_hostile_markers()

## True when `a_actor` could repair `a_target` right now. The predicate form of
## repairable_cause, for the readers that only want a yes/no.
static func can_repair(actor: Commandable, subject: Variant) -> bool:
	return repairable_cause(actor, subject) == PreconditionFailureCause.NONE

static func meets_precondition(
	actor: Commandable,
	message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	return repairable_cause(actor, message.target)
#endregion

#region State updates
## Repairing is a channeled action, like the construction it was split from: a hit
## staggers the worker, pausing the mend until the stagger wears off.
func blocked_by_stagger(_a_actor: Commandable) -> bool:
	return true

## Drop the order the moment there is nothing left to do: the patient died (a freed
## subject crashes every check that touches it), or it is back to full hp. Re-asking
## repairable_cause each tick also covers the subject changing hands or being demolished
## and rebuilt under us.
func get_updated_state(a_actor: Commandable) -> Variant:
	if not is_instance_valid(message.target):
		return null
	if not can_repair(a_actor, message.target):
		return null
	return self

func acting_action(_a_actor: Commandable) -> ActionTracker.Action:
	return ActionTracker.Action.REPAIRING

func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_target(a_actor, message.target)

## Arriving next to the patient is where the work STARTS, so arrival must not end the
## command — the same reason Build and Assemble opt out. can_act decides when to work,
## and get_updated_state decides when there is nothing left to do.
func ends_on_arrival() -> bool:
	return false

func fulfill_action(a_actor: Commandable) -> Variant:
	var subject := message.target as Commandable
	# Reaching a charge is defusing it: the first touch of a mend takes it out of play.
	var charge: PlantedCharge = PlantedCharge.of(subject)
	if charge != null:
		charge.remove()
		return null
	var repairs: Repairs = a_actor.get_node_or_null("Repairs") as Repairs
	var defense: Defense = (message.target as Commandable).get_node_or_null("Defense") as Defense
	if repairs == null or defense == null:
		return null
	# Each repairer applies its own rate every tick — no builder-style crowding penalty
	# (see Repairs.repair_rate).
	if defense.restore(repairs.repair_amount(a_actor.get_physics_process_delta_time())):
		return null
	return self
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	super(a_message)
#endregion
