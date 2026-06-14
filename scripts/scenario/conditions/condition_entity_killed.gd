class_name ConditionEntityKilled
extends Condition

#region Properties
## Node name of the entity to watch. Searched in the "commandable" group on
## first evaluate() call. Using the name (not a NodePath) is reparent-safe —
## entities are reparented to their commander's subtree at runtime, so a fixed
## NodePath would break after initialization.
@export var entity_name: String = ""

var _entity_ref: Node = null
var _resolved: bool = false
#endregion

#region Private helpers
func _resolve(manager: ScenarioEventManager) -> void:
	if _resolved:
		return
	_resolved = true
	if entity_name.is_empty():
		return
	for node: Node in manager.get_tree().get_nodes_in_group("commandable"):
		if node.name == entity_name:
			_entity_ref = node
			return
#endregion

#region Public API
func evaluate(manager: ScenarioEventManager) -> bool:
	_resolve(manager)
	if _entity_ref == null:
		return false
	return not is_instance_valid(_entity_ref) or not _entity_ref.is_inside_tree()

func reset() -> void:
	_entity_ref = null
	_resolved = false
#endregion
