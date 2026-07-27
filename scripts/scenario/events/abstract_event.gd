@tool
class_name AbstractEvent
extends EditorMarkerSprite3D

## Base class for scenario events. Events are positioned Node3Ds: an event's
## global_position is its anchor (e.g. EventSpawnUnits spawns at that point), and
## child nodes (see EventCommandPoint) describe follow-up behaviour. A GlobalTrigger
## holds references to the event nodes it fires when its conditions are met.
##
## Subclasses override execute() for runtime behaviour. Extends EditorMarkerSprite3D so
## each event shows a clickable, draggable marker in the 3D editor (hidden at runtime) —
## the old hand-drawn _process/ImmediateMesh gizmos have been retired in favour of it.

#region Public API
## Called when an owning GlobalTrigger fires. Implement effects in subclasses.
func execute(_a_manager: ScenarioTriggerManager) -> void:
	pass


## The GlobalTrigger this event ultimately belongs to, or null when it has none (an
## EntityTrigger reaction, a starting event parked under a commandable — see the three ways
## an event runs). Walks ANCESTORS rather than reading get_parent(), because events nest:
## an EventSpawnEntities under another EventSpawnEntities, an EventCommandTarget under an
## EventIssueCommand. Only the top of that chain is parented to the trigger.
func owning_trigger() -> GlobalTrigger:
	var node: Node = get_parent()
	while node != null:
		var trigger := node as GlobalTrigger
		if trigger != null:
			return trigger
		node = node.get_parent()
	return null


## How many times the owning trigger has already fired — the `fires` input for authored
## expressions. 0 when this event has no owning trigger.
func owner_fire_count() -> int:
	var trigger: GlobalTrigger = owning_trigger()
	return trigger.fire_count if trigger != null else 0


## The ScenarioTriggerManager this event sits under, or null for an event that runs outside
## one (a starting event parked under a commandable). Same ancestor walk as owning_trigger,
## so an event can reach the session without every execute() signature having to pass it on.
func owning_manager() -> ScenarioTriggerManager:
	var node: Node = get_parent()
	while node != null:
		var manager := node as ScenarioTriggerManager
		if manager != null:
			return manager
		node = node.get_parent()
	return null
#endregion
