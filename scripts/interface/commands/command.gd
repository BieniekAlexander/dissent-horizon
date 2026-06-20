class_name Command

#region Constants
static var command_class: bool = true

enum PreconditionFailureCause {
	NONE,
	NOT_ENOUGH_ORE,
	NOT_ENOUGH_POPULATION,
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
	PreconditionFailureCause.NOT_ENOUGH_POPULATION: "Not enough population",
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
	TechnologySpec.UnmetNeed.NOT_ENOUGH_POPULATION: PreconditionFailureCause.NOT_ENOUGH_POPULATION,
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
#endregion

#region State updates
## Potentially return a new command based on a state check
func get_updated_state(_a_commandable: Commandable) -> Command:
	return self

## Check if the [Commandable] should move in response to the command
func should_move(_a_commandable: Commandable) -> bool:
	return true

## Check if the [Commandable] is ready to [fulfill_action]
func can_act(_a_commandable: Commandable) -> bool:
	return false

## Perform the characteristic action of this command and return whatever might be a follow-up [Command], or null otherwise
func fulfill_action(_a_commandable: Commandable) -> Variant:
	push_error("no action should have been performed")
	return self
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	message = a_message
	message.retain()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and message != null:
		message.release()
#endregion

#region Debug
func _to_string() -> String:
	return "Command: %s" % message.position
#endregion
