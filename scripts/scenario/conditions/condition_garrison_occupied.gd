@tool
class_name ConditionGarrisonOccupied
extends Condition

## True while a named host holds at least `count` of a commander's units in its Garrison — "the
## player has taken cover in the farmhouse". Added for prologue mission 1 (Alex, 2026-10-18),
## whose next beat starts when the player garrisons a building.
##
## A PULL condition. The host is found by NAME in the "piece" group, as ConditionEntityKilled
## finds its entity: a placed piece is reparented under its commander at runtime, and a building
## a player occupies changes commander, so a NodePath would not survive either. A host that is
## gone holds nobody.

#region Properties
## Node name of the host to watch.
@export var host_name: String = ""
## Whose units count: a commander id, or -1 for anyone's.
@export var commander_id: int = 1
## How many of them it takes.
@export var count: int = 1

var _host: Node = null
var _resolved: bool = false
#endregion


#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	_resolve(a_manager)
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return false
	var garrison := (_host as Actor).garrison if _host is Actor else null
	if garrison == null:
		return false
	var held: int = 0
	for unit: Actor in garrison.occupants():
		if is_instance_valid(unit) and (commander_id < 0 or unit.commander_id == commander_id):
			held += 1
	return held >= count


func reset() -> void:
	super.reset()
	_host = null
	_resolved = false


#endregion


#region Private helpers
func _resolve(a_manager: ScenarioTriggerManager) -> void:
	if _resolved:
		return
	_resolved = true
	for node: Node in a_manager.get_tree().get_nodes_in_group("piece"):
		if node.name == host_name:
			_host = node
			return
	push_warning(
		(
			"ConditionGarrisonOccupied: no piece named '%s'. " % host_name
			+ "This check can never become true; did the node get renamed?"
		)
	)
#endregion
