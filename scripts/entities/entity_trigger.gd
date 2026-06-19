@tool
class_name EntityTrigger
extends Resource

## One entry in an Entity's `entity_triggers`: pairs a lifecycle occurrence with the
## AbstractEvent scene to run when that occurrence happens on the entity (see
## Entity.EntityOccurrence and ScenarioTriggerManager.dispatch_event_scene).
##
## The reactive counterpart to GlobalTrigger: a GlobalTrigger is armed and fires when its
## Conditions hold, whereas an EntityTrigger fires the moment its `occurrence` is emitted
## on the owning entity. The occurrence alone is the trigger (no extra conditions).
##
## The event is a PackedScene (the entity has no inline scene context the way a
## GlobalTrigger does), instantiated and placed by `spawn_locator` when it fires — by
## default at the source entity's position. Assign a SpawnLocator subclass to anchor it
## elsewhere (e.g. the nearest structure).
##
## Authored as an array element in the inspector. The `occurrence` field renders as a
## named dropdown, and the element's header mirrors the chosen occurrence via
## resource_name — so the array reads "ON_DEATH" / "ON_RECEIVE_DAMAGE" rather than
## bare numeric indices.

## Which lifecycle occurrence on the owning entity fires this reaction.
@export var occurrence: Entity.EntityOccurrence = Entity.EntityOccurrence.ON_DEATH:
	set(value):
		occurrence = value
		# Mirror the chosen occurrence onto the resource name so the inspector's array
		# element header reads e.g. "ON_DEATH" instead of a bare index.
		resource_name = Entity.EntityOccurrence.find_key(value)

## Path to the AbstractEvent scene (.tscn) run when `occurrence` fires on the owning
## entity. Stored as a file path, NOT a PackedScene reference, on purpose: assigning a
## PackedScene value to a custom Resource field crashes the Godot 4.5 editor — confirmed
## via crash logging: our setter completes, then the engine's inspector rebuild/preview
## for the PackedScene faults (no GDScript runs after). A path field sidesteps that
## picker. Drag a .tscn from the FileSystem dock onto this field, or use its browse
## button; it's loaded lazily when the trigger fires.
@export_file("*.tscn") var event_scene_path: String = ""

## Strategy that picks where the event is anchored, given the entity that fired it. Null
## means "at the source entity's position."
@export var spawn_locator: SpawnLocator


## Where the event should be anchored when this trigger fires on `source`.
func resolve_spawn_position(source: Entity, manager: ScenarioTriggerManager) -> Vector3:
	if spawn_locator != null:
		return spawn_locator.resolve(source, manager)
	return source.global_position
