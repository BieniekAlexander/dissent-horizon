class_name Command

static var command_class: bool = true

## COMMAND PRECONDITIONS
enum PreconditionFailureCause {
	NONE,
	NOT_ENOUGH_RESOURCES,
	TECHNOLOGY_NOT_AVAILABLE,
	INVALID_PLACEMENT,
	UNENUMERATED_FAILURE_CAUSE
}

static var precondition_message_map: Dictionary = {
	PreconditionFailureCause.NONE: "",
	PreconditionFailureCause.NOT_ENOUGH_RESOURCES: "Not enough resources",
	PreconditionFailureCause.TECHNOLOGY_NOT_AVAILABLE: "Technology not available",
	PreconditionFailureCause.INVALID_PLACEMENT: "Invalid Placement",
	PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE: "Unspecified failure"
}

static func tool_applies_to(command_tool_name: String, entity_type: Entity.Type):
	# TODO implement some means of checking if a given tool even applies for a given unit type, e.g. who can build what
	return false

static func requires_position() -> bool:
	## Indicates whether this command requires a specified position to be issued
	return true

## Checks whether the relevant command is allowable, given the situation
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	# examples:
	# - can the unit can perform this operation on the specified target?
	# - can the unit can place the specified building in the specified position?
	return PreconditionFailureCause.NONE


### STATE
var message: CommandMessage


### UTILS
# TODO: unused function
#func _target_is_in_range(a_actor: Commandable, range: float) -> bool:
#	return SU.unit_is_close_to_target(
#		a_actor,
#		message.target,
#		range**2
#	)


### STATE UPDATES
## Potentially return a new command based on a state check
func get_updated_state(a_commandable: Commandable):
	return self

## Check if the [Commandable] should move in response to the command
func should_move(a_commandable: Commandable) -> bool:
	return true

## Check if the [Commandable] is ready to [fulfill_action]
func can_act(a_commandable: Commandable) -> bool:
	return false

## Perform the characteristic action of this command and return whatever might be a follow-up [Command], or null otherwise
func fulfill_action(a_commandable: Commandable) -> Variant:
	push_error("no action should have been performed")
	return self

### NODE
func _init(a_message: CommandMessage) -> void:
	message = CommandMessage.deep_copy(a_message)

static func load_command_from_dictionary(a_dictionary: Dictionary, a_map: Map) -> Command:
	var command_class = {
		"move": Command,
		"attack_move": AttackMove,
		"defend": Defend
	}[a_dictionary["type"]]
	
	var pos: Vector3 = Vector3(a_dictionary["loc"][0], 10, a_dictionary["loc"][1])
	var command = command_class.new(
		CommandMessage.new(
			a_map,
			null,
			null,
			a_map.get_navmesh_line_hit(
				pos,
				pos+10*Vector3.DOWN
			)
		)
	)
	return command


## DEBUG
func _to_string() -> String:
	return "Command: %s" % message.position
