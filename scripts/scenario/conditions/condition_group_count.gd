@tool
class_name ConditionGroupCount
extends Condition

## Counts the nodes in a scene-tree group and compares that against a threshold — "the ambush
## wave is dead", "three of the escort are still standing".
##
## Groups are the loosest way to say WHICH things a check is about. The other count conditions
## select by what a thing IS (a commander's units, a structure type); this one selects by
## whatever the author decided to label, so a check can name one specific wave, one escort,
## one set of reinforcements, without any of that identity existing in the game's data model.
## EventSpawnEntities.spawn_groups is the other half: it stamps a label onto everything one
## event spawns, and this reads it back.
##
## Deliberately counts NODES rather than Entities — a group may hold anything, and this needs
## no opinion about what. The highlight path narrows to Entities, because only those have a
## position to mark.

#region Properties
enum Comparison { AT_LEAST, AT_MOST, EXACTLY }

## The scene-tree group to count. Nothing matches while this is unset.
@export var group: StringName = &""
@export var comparison: Comparison = Comparison.AT_LEAST
@export var count: int = 1
#endregion


#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	# An unset group would otherwise count zero, which makes AT_MOST true on the first tick —
	# an un-authored check that fires immediately is worse than one that never does.
	if group.is_empty():
		return false
	var n: int = matching_nodes(a_manager).size()
	match comparison:
		Comparison.AT_LEAST:
			return n >= count
		Comparison.AT_MOST:
			return n <= count
		Comparison.EXACTLY:
			return n == count
	return false


#endregion


#region Player-facing description (highlights)
## Same rule as the other count conditions: AT_MOST is the "get rid of these" shape, so the
## members ARE the task and get marked, and the marks vanish as they die. AT_LEAST / EXACTLY
## are waiting on things that don't exist yet, so there is nothing to point at.
##
## Narrowed to Entity because a marker needs a world position; a group holding plain Nodes
## contributes nothing here rather than erroring.
func highlight_entities(a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	if comparison != Comparison.AT_MOST:
		return result
	for node: Node in matching_nodes(a_manager):
		var entity := node as Entity
		if entity != null:
			result.append(entity)
	return result


#endregion


#region Internal
## The group's live members — the set both evaluate() counts and highlight_entities() marks,
## so what the player sees marked can never drift from what the check is measuring.
##
## get_nodes_in_group only returns nodes currently in the tree, but a node killed this frame
## lingers there until the end of it. Dropping the ones already queued for deletion lets a
## "wipe out the wave" check resolve on the tick the last one dies rather than the tick after.
func matching_nodes(a_manager: ScenarioTriggerManager) -> Array[Node]:
	var result: Array[Node] = []
	if group.is_empty() or a_manager == null or a_manager.get_tree() == null:
		return result
	for node: Node in a_manager.get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			result.append(node)
	return result
#endregion
