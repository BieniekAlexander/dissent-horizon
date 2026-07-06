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
func execute(_manager: ScenarioTriggerManager) -> void:
	pass
#endregion
