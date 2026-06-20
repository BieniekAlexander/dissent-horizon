@tool
class_name EventSpawnEntities
extends AbstractEvent

## Spawns entities into the game for `commander_id` at this event's spawn anchor — its
## own global_position, or `spawn_position`'s if one is assigned. For an EntityTrigger
## reaction the event is placed at the resolved location (by default the source entity)
## before it runs, so the same code serves both global and per-entity triggers.
##
## `entity_scenes` lists the PackedScenes to spawn; `count` multiplies EACH (two scenes
## with count = 3 → 3 of each). Routing by kind: Commandables (units AND structures) go
## through Map.add_entities (structures register on the grid); other Entities are placed
## via Map.add_entity; anything else (a pure VFX/SFX node) is parked at the anchor.
##
## An EventIssueCommand child node, if present, issues a command chain to every spawned
## Commandable. If absent, spawned units receive no initial orders.

#region Constants
const _SPAWN_RING_RADIUS := 1.0
#endregion

#region Properties
## How the spawned entities' owner is chosen.
enum Assignment {
	## Use `commander_id` directly. Right for events with no source entity (GlobalTriggers).
	SPECIFIED = 0,
	## Inherit the owner from the source entity — the one whose EntityTrigger fired.
	INHERITED = 1
}

@export var assignment: Assignment = Assignment.SPECIFIED
## The commander the spawned entities belong to when ownership == SPECIFIED. Forced to -1
## and made read-only when ownership == INHERITED (the owner comes from the source entity).
@export var commander_id: int = 2
## The PackedScenes to spawn. Each is instanced `count` times.
@export var entity_scenes: Array[PackedScene] = []
## How many of EACH scene in `entity_scenes` to spawn.
@export var count: int = 1
## Optional spawn-anchor override: spawn at this node's position instead of the event's
## own. Lets you point spawning at a marker elsewhere in the (inline) scene.
@export var spawn_position: Node3D
#endregion

#region Tool
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"ownership":
			# Editing ownership re-runs validation so commander_id's read-only state updates.
			property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"commander_id":
			if assignment == Assignment.INHERITED:
				commander_id = -1
				property.usage = property.usage | PROPERTY_USAGE_READ_ONLY
			else:
				property.usage = property.usage & ~PROPERTY_USAGE_READ_ONLY
#endregion

#region Public API
func execute(manager: ScenarioTriggerManager) -> void:
	var commander := _resolve_commander(manager)
	if commander == null:
		return
	var map := manager.map
	if map == null:
		return

	var anchor: Vector3 = spawn_position.global_position if spawn_position != null else global_position
	var anchor_xz := VU.inXZ(anchor)

	# Instance every scene `count` times and route each by kind. Commandables are
	# collected for a single batched add_entities (which spaces them out and handles
	# structures); everything else is placed individually.
	var commandables: Array[Commandable] = []
	for packed: PackedScene in entity_scenes:
		if packed == null:
			continue
		for _i in range(count):
			var inst := packed.instantiate()
			if inst is Commandable:
				commandables.append(inst)
			elif inst is Entity:
				map.add_entity(inst as Entity, anchor_xz, commander)
			else:
				map.add_child(inst)
				if inst is Node3D:
					(inst as Node3D).global_position = anchor

	if commandables.is_empty():
		return

	map.add_entities(commandables, anchor_xz, commander)

	var issue_cmd: EventIssueCommand = _find_issue_command()
	if issue_cmd != null:
		issue_cmd.issue_commands_to(commandables, manager, commander.id)
#endregion

#region Private helpers
## The commander spawned entities belong to: `commander_id` when SPECIFIED, or the source
## entity's commander when INHERITED. Null when INHERITED but there's no source entity
## (e.g. fired from a GlobalTrigger) — callers then skip spawning.
func _resolve_commander(manager: ScenarioTriggerManager) -> Commander:
	if assignment == Assignment.INHERITED:
		var source := manager.reaction_source
		if source == null:
			return null
		return manager.get_commander(source.commander_id)
	return manager.get_commander(commander_id)

func _find_issue_command() -> EventIssueCommand:
	for child: Node in get_children():
		if child is EventIssueCommand:
			return child as EventIssueCommand
	return null
#endregion

#region Editor gizmo
func _draw_editor_gizmo(verts: PackedVector3Array) -> void:
	_gizmo_ring(verts, Vector3.ZERO, _SPAWN_RING_RADIUS)
	# Polyline from the spawn point through each EventCommandPoint grandchild (those
	# inside the nested EventIssueCommand). EventCommandTarget nodes don't have a fixed
	# position so only waypoints are drawn.
	var path: Array[Vector3] = [Vector3.ZERO]
	for child: Node in get_children():
		if child is EventIssueCommand:
			for grandchild: Node in child.get_children():
				if grandchild is EventCommandPoint:
					path.append(to_local((grandchild as EventCommandPoint).global_position))
	_gizmo_polyline(verts, path)
#endregion
