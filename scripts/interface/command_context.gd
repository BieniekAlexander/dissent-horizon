## Represents the possible set of commands, given the context provided by the selected units
## The controller interface will decide which units will receive commands as defined in this object
class_name CommandContext

var evaluator: Array[Pattern] # TODO rename, this name is from old implementation
var state_maping: Dictionary
var tools: Array

func _init(
	a_evaluator: Array[Pattern],
	a_state_maping: Dictionary = {}
):
	evaluator = a_evaluator
	state_maping = a_state_maping

func requires_position() -> bool:
	# TODO this might vary depending on the state of the controller
	return evaluator[0].result.requires_position()

func evaluate_command(a_actor: Commandable, a_message: CommandMessage) -> Variant:
	# returns the Command type that is applicable for [a_actor], given [a_message]
	# e.g. if a_actor can shoot up and a_message points at a flying unit, return Attack; otherwise, return null
	return Pattern.eval(evaluator, [a_actor, a_message])

func get_new_context(a_input_event: String) -> Variant:
	## Returns a new command context if one is found; otherwise, returns itself (so as to maintain the existing context)
	return state_maping.get(a_input_event, self)

static func merge(a: CommandContext, b: CommandContext) -> CommandContext:
	return CommandContext.new(
		a.evaluator + b.evaluator,
		a.state_maping.merged(b.state_maping)
	)

func command_available(a_input_event: String, a_commandable: Entity) -> bool:
	# returns whether a given input event would be applicable in this command context
	return state_maping.has(a_input_event) or evaluator.any(
		func(p: Pattern): return p.result.tool_applies_to(a_input_event, a_commandable.type)
	)

static var NULL: CommandContext = CommandContext.new([])
