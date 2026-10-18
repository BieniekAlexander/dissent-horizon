@tool
class_name EventEndReveal
extends AbstractEvent

## Takes down a standing reveal: frees every vision source an EventRevealRegion placed under
## `reveal_label`, so the fog closes over what it showed. The fog withdraws a vision source the
## tick it leaves the "los" group (FogRaster.update_sight), so nothing else needs telling.
##
## The way a mission lets a fight it has been showing the player go dark once the story moves
## on — a reveal with a fixed `lifespan_seconds` would have to guess when that is.

#region Properties
## The label of the reveal to end (EventRevealRegion.reveal_label).
@export var reveal_label: StringName = &""
#endregion


#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	if reveal_label.is_empty():
		push_error("EventEndReveal: no reveal_label, so there is nothing to end")
		return
	for node: Node in a_manager.get_tree().get_nodes_in_group(reveal_label):
		if node is Entity and not node.is_queued_for_deletion():
			node.queue_free()
#endregion
