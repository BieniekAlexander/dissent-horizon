@tool
class_name EventRevealRegion
extends ScenarioEvent

## World-space radius to reveal (in the same units as Map.CELL_SIZE). The centre
## is this node's global_position.
@export var radius: float = 5.0

func execute(manager: ScenarioEventManager) -> void:
	var fog := manager.get_fog()
	if fog == null:
		return
	fog.reveal_region(VU.inXZ(global_position), radius)


func _draw_editor_gizmo(verts: PackedVector3Array) -> void:
	_gizmo_ring(verts, Vector3.ZERO, radius)
