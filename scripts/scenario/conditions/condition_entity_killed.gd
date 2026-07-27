@tool
class_name ConditionEntityKilled
extends Condition

## True once a specific named entity has been destroyed — "the Compound is rubble".

#region Properties
## Node name of the entity to watch. Searched in the "piece" group on
## first evaluate() call. Using the name (not a NodePath) is reparent-safe —
## entities are reparented to their commander's subtree at runtime, so a fixed
## NodePath would break after initialization.
@export var entity_name: String = ""

var _entity_ref: Node = null
var _resolved: bool = false

## Whether _resolve() actually FOUND the entity, as opposed to having run and come up empty.
##
## This flag exists because `_entity_ref == null` cannot answer that question: in GDScript a
## FREED Object compares equal to null, so once the watched entity is destroyed the
## reference starts reporting itself as null — indistinguishable from "we never found it".
## Guarding on `_entity_ref == null` therefore swallowed exactly the state this condition
## exists to detect, and the check could never become true.
var _found: bool = false
#endregion

#region Private helpers
func _resolve(a_manager: ScenarioTriggerManager) -> void:
	if _resolved:
		return
	_resolved = true
	if entity_name.is_empty():
		push_warning(
			"ConditionEntityKilled: entity_name is empty, so this check can never become true."
		)
		return
	for node: Node in a_manager.get_tree().get_nodes_in_group("piece"):
		if node.name == entity_name:
			_entity_ref = node
			_found = true
			return
	# Nothing matched. The check then reports false forever and its trigger simply never
	# fires, with nothing in the log to say why — the same silent failure an unresolved
	# region causes (see RegionAwareCondition.warn_about_missing_region). The usual cause is
	# the watched node having been renamed since the trigger was authored.
	push_warning(
		"ConditionEntityKilled: no entity named '%s' in the \"piece\" group. " % entity_name
		+ "This check can never become true; did the node get renamed?"
	)


## Whether the watched entity is still standing. False both when it has been freed and when
## it has merely been pulled out of the tree (garrisoned units are removed but not freed —
## for a watched STRUCTURE, being out of the world is the same as being gone).
func _entity_is_alive() -> bool:
	return _found and is_instance_valid(_entity_ref) and _entity_ref.is_inside_tree()
#endregion

#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	_resolve(a_manager)
	# Never resolved: report false rather than "it's gone", so a typo'd entity_name fails
	# closed (the trigger never fires) instead of firing on the first tick.
	if not _found:
		return false
	return not _entity_is_alive()


func reset() -> void:
	super.reset()
	_entity_ref = null
	_resolved = false
	_found = false
#endregion

#region Player-facing description (highlights)
## Mark the watched entity while it is still alive — it is precisely the thing the player
## has to deal with, and the mark clears itself the moment the condition is met.
func highlight_entities(a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	_resolve(a_manager)
	if _entity_is_alive():
		var entity := _entity_ref as Entity
		if entity != null:
			result.append(entity)
	return result
#endregion
