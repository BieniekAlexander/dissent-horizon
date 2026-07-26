class_name ConditionUnitHasCommand
extends Condition

## True when a commander's unit(s) currently hold a command of a given kind — e.g. "the
## bot's kamikaze has an Attack command". A pull condition: it reads live command state
## each poll.
##
## `command_name` matches the MoveCommand subclass by its class_name (e.g. "Attack",
## "AttackMove", "MoveCommand"). `quantifier` decides whether ANY matching unit suffices or ALL of
## them must hold it. With `unit_type` = UNDEFINED every unit the commander owns is
## considered.

#region Properties
enum Quantifier { ANY, ALL }

## Which commander's units to inspect.
@export var commander_id: int = 1
## UNDEFINED matches units of any type.
@export var unit_type: StringName = &""
## The MoveCommand subclass name to look for (its class_name), e.g. "Attack".
@export var command_name: String = "Attack"
## ANY: at least one matching unit holds the command. ALL: every matching unit does.
@export var quantifier: Quantifier = Quantifier.ANY
#endregion

#region Public API
func evaluate(manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	var units: Array = commander.get_children().filter(
		func(n: Node) -> bool:
			return n is Commandable and (n as Commandable).is_in_group("unit") \
				and (unit_type == &"" or (n as Commandable).id == unit_type)
	)
	if units.is_empty():
		return false
	var holds_command := func(u: Commandable) -> bool:
		var c: MoveCommand = u.current_command()
		return c != null and _command_class_name(c) == command_name
	if quantifier == Quantifier.ALL:
		return units.all(holds_command)
	return units.any(holds_command)
#endregion

#region Internal
## The runtime class_name of a MoveCommand instance (e.g. "Attack"), or "" if unavailable.
func _command_class_name(command: MoveCommand) -> String:
	var script: Script = command.get_script()
	return String(script.get_global_name()) if script != null else ""
#endregion
