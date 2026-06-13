class_name EventRevealRegion
extends ScenarioEvent

## World-space XZ centre of the area to permanently uncover.
@export var center_xz: Vector2 = Vector2.ZERO
## World-space radius to reveal (in the same units as Map.CELL_SIZE).
@export var radius: float = 5.0

func execute(manager: ScenarioEventManager) -> void:
	var fog := manager.get_fog()
	if fog == null:
		return
	fog.reveal_region(center_xz, radius)
