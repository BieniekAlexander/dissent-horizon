@tool
class_name EntityTrigger
extends Node

## A per-entity Trigger: the reactive counterpart to GlobalTrigger. Add it as a child of
## an Entity and give it one or more child AbstractEvent nodes (the reaction). When
## `occurrence` fires on the owning entity, those child events run.
##
## Like GlobalTrigger, the events are inline child NODES, not a PackedScene reference —
## which both keeps the two trigger types symmetric and sidesteps the Godot editor crash
## that occurs when a PackedScene is assigned to a custom Resource's property. To author a
## reaction, drag an event scene (root = an AbstractEvent, e.g. EventSpawnEntities) from
## the FileSystem dock onto this node in the entity's scene tree.
##
## A GlobalTrigger is armed and fires when its Conditions hold; an EntityTrigger fires the
## moment its `occurrence` is emitted on the owning entity (the occurrence alone is the
## trigger — no extra conditions).

## Which lifecycle occurrence on the owning entity fires this reaction.
@export var occurrence: Entity.EntityOccurrence = Entity.EntityOccurrence.ON_DEATH

## Strategy that picks where the events are anchored, given the entity that fired them.
## Null means "at the source entity's position."
@export var spawn_locator: SpawnLocator


## Run this trigger's child events for `source` (the entity it fired on). Each child
## AbstractEvent is placed at the resolved spawn position, then executed via the manager.
func fire(manager: ScenarioTriggerManager, source: Entity) -> void:
	var position: Vector3 = _resolve_spawn_position(source, manager)
	for child in get_children():
		if child is AbstractEvent:
			(child as Node3D).global_position = position
			manager.run_event(child as AbstractEvent, source)


## Where the events should be anchored when this trigger fires on `source`.
func _resolve_spawn_position(source: Entity, manager: ScenarioTriggerManager) -> Vector3:
	if spawn_locator != null:
		return spawn_locator.resolve(source, manager)
	return source.global_position
