class_name MoveCommand

#region Constants
static var command_class: bool = true

enum PreconditionFailureCause {
	NONE,
	NOT_ENOUGH_ORE,
	NOT_ENOUGH_VIGOR,
	NOT_ENOUGH_DOMINION,
	MISSING_STRUCTURE,
	INVALID_PLACEMENT,
	# The ability has no charges available right now (still reloading).
	ABILITY_NO_CHARGES,
	UNENUMERATED_FAILURE_CAUSE,
	# Not a failure: the command is entered but still waiting on the player to
	# pick the tool/option it needs (e.g. Build with no structure chosen yet).
	COMMAND_PENDING_TOOL
}

static var precondition_message_map: Dictionary = {
	PreconditionFailureCause.NONE: "",
	PreconditionFailureCause.NOT_ENOUGH_ORE: "Not enough ore",
	PreconditionFailureCause.NOT_ENOUGH_VIGOR: "Not enough vigor",
	PreconditionFailureCause.NOT_ENOUGH_DOMINION: "Not enough dominion",
	PreconditionFailureCause.MISSING_STRUCTURE: "Required structure missing",
	PreconditionFailureCause.INVALID_PLACEMENT: "Invalid Placement",
	PreconditionFailureCause.ABILITY_NO_CHARGES: "Ability recharging",
	PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE: "Unspecified failure",
	PreconditionFailureCause.COMMAND_PENDING_TOOL: "Select an Option"
}

static var unmet_need_to_precondition: Dictionary = {
	TechnologySpec.UnmetNeed.NONE: PreconditionFailureCause.NONE,
	TechnologySpec.UnmetNeed.NOT_ENOUGH_ORE: PreconditionFailureCause.NOT_ENOUGH_ORE,
	TechnologySpec.UnmetNeed.NOT_ENOUGH_VIGOR: PreconditionFailureCause.NOT_ENOUGH_VIGOR,
	TechnologySpec.UnmetNeed.NOT_ENOUGH_DOMINION: PreconditionFailureCause.NOT_ENOUGH_DOMINION,
	TechnologySpec.UnmetNeed.MISSING_STRUCTURE: PreconditionFailureCause.MISSING_STRUCTURE,
}
#endregion

#region Preconditions
static func tool_applies_to(_command_tool_name: String, _a_entity: Entity) -> bool:
	return false

static func requires_position() -> bool:
	## Indicates whether this command requires a specified position to be issued
	return true

## Checks whether the relevant command is allowable, given the situation
static func meets_precondition(
	_a_actor: Commandable,
	_a_message: CommandMessage
) -> PreconditionFailureCause:
	# examples:
	# - can the unit can perform this operation on the specified target?
	# - can the unit can place the specified building in the specified position?
	return PreconditionFailureCause.NONE
#endregion

#region Properties
var message: CommandMessage

## Counts down toward the next per-second destination-swap check (see
## _resolve_destination_swap). Only meaningful for a plain MoveCommand instance,
## since subclasses (Patrol, Attack, Defend, ...) override get_updated_state()
## without calling super and so never run this check.
var _swap_cooldown: float = 0.0

## The actor this command is running for. Stamped every tick by
## CommandReceiver._process_commands() — not captured here, since most subclasses
## override get_updated_state() without calling super and a base-class capture
## would miss them. Used only to reset a group-move Movement.speed_cap (see
## RTSController.assign_command_to_units) once this command is destroyed —
## completed, cancelled, or replaced by another command.
var _actor: Commandable = null
#endregion

#region State updates
## Potentially return a new command based on a state check. A plain MoveCommand
## never reactively retargets on its own — it always returns self. Aggro-based
## retargeting (chasing down a nearby enemy) is opt-in per subclass (see
## AttackMove, Patrol, Defend), not a base-class behavior every command inherits.
func get_updated_state(a_commandable: Commandable) -> Variant:
	_swap_cooldown -= 1.0 / Engine.get_physics_ticks_per_second()
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
		if other_cmd == null or not is_same(other_cmd.message.origin, message.origin):
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
			a_commandable.movement.set_target_position(message.position)
			other_unit.movement.set_target_position(other_cmd.message.position)
			my_dest = other_cmd.message.position

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

## Check if the [Commandable] is ready to [fulfill_action]
func can_act(_a_commandable: Commandable) -> bool:
	return false

## Perform the characteristic action of this command and return whatever might be a follow-up [MoveCommand], or null otherwise
func fulfill_action(_a_commandable: Commandable) -> Variant:
	push_error("no action should have been performed")
	return self
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	message = a_message
	message.retain()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if message != null:
			message.release()
		# Validate movement too, not just _actor: during scene teardown the actor's child
		# Movement node is freed BEFORE the actor itself, so a command that outlives its
		# fulfillment (e.g. one held while its actor was staggered) can run this PREDELETE
		# with _actor still valid but _actor.movement a dangling reference — touching it
		# then crashes. is_instance_valid covers both the null and freed cases.
		if _actor != null and is_instance_valid(_actor) and is_instance_valid(_actor.movement):
			_actor.movement.speed_cap = 0.0
#endregion

#region Debug
func _to_string() -> String:
	return "MoveCommand: %s" % message.position
#endregion
