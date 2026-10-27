@tool
class_name ConditionGroupVisible
extends Condition

## Whether anything in a scene-tree group is in a commander's sight right now — "the player has
## spotted a Watch Tower". Sight is the test that decides whether that commander sees a piece at
## all (Entity.is_visible_to): its own fog and whatever vision its allies share with it, with a
## stealthed enemy unseen. A remembered silhouette under the fog does not count (Alex,
## 2026-10-26).

## The scene-tree group whose members are looked for. Nothing matches while this is unset.
@export var group: StringName = &""
## The commander whose sight is asked.
@export var commander_id: int = 1


func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	if group.is_empty() or a_manager == null or a_manager.get_tree() == null:
		return false
	for node: Node in a_manager.get_tree().get_nodes_in_group(group):
		var entity := node as Entity
		if entity != null and not entity.is_queued_for_deletion():
			if entity.is_visible_to(commander_id):
				return true
	return false
