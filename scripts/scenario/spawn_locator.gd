@tool
class_name SpawnLocator
extends Resource

## Strategy for choosing where an EntityTrigger's event is anchored, given the entity the
## trigger fired on. The base returns the source entity's own position; subclasses
## override resolve() for "nearest structure", a fixed offset, etc. Assign one to
## EntityTrigger.spawn_locator (null = this base behaviour).
func resolve(source: Entity, _manager: ScenarioTriggerManager) -> Vector3:
	return source.global_position if source != null else Vector3.ZERO
