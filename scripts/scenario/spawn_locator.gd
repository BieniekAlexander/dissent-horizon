@tool
class_name SpawnLocator
extends Resource

## Strategy for choosing where an EntityTrigger's event is anchored, given the entity the
## trigger fired on. The base returns the source entity's own position; subclasses
## override resolve() for "nearest structure", a fixed offset, etc. Assign one to
## EntityTrigger.spawn_locator (null = this base behaviour).
func resolve(a_source: Entity, _a_manager: ScenarioTriggerManager) -> Vector3:
	return a_source.global_position if a_source != null else Vector3.ZERO
