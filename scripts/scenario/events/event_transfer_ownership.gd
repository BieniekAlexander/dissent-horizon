@tool
class_name EventTransferOwnership
extends AbstractEvent

## Hands every piece labelled `group` to commander `commander_id` — "the transports are yours
## once the SAM sites are down". Added for prologue mission 1 (Alex, 2026-10-18), whose ally
## gives the player its landed transports when the air defence falls.
##
## Pieces are named by a LABEL (EventSpawnEntities.spawn_groups), as ConditionGroupCount reads
## them, so the event names one specific set and not a type. Each is handed over through its
## Ownership (Entity.commander), which reparents it under its new commander as any change of
## hands does. A piece held inside a garrison is skipped: it is out of the world, and its host's
## rules decide whose it is.

#region Properties
## The label whose pieces change hands.
@export var group: StringName = &""
## Who they go to.
@export var commander_id: int = 1
#endregion


#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	if group.is_empty():
		push_error("EventTransferOwnership '%s': no group" % name)
		return
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		push_error("EventTransferOwnership '%s': no commander %d" % [name, commander_id])
		return
	for node: Node in a_manager.get_tree().get_nodes_in_group(group):
		var piece := node as Entity
		if piece == null or not piece.is_inside_tree() or piece.is_queued_for_deletion():
			continue
		if piece.commander != commander:
			piece.commander = commander
#endregion
