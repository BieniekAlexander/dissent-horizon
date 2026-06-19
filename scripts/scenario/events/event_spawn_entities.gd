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
## EventCommand children (EventCommandPoint / EventCommandTarget) add one follow-up
## command each, in scene-tree order, to the chain issued to every spawned Commandable.

#region Constants
const _SPAWN_RING_RADIUS := 1.0
#endregion

#region Properties
@export var commander_id: int = 2
## The PackedScenes to spawn. Each is instanced `count` times.
@export var entity_scenes: Array[PackedScene] = []
## How many of EACH scene in `entity_scenes` to spawn.
@export var count: int = 1
## Optional spawn-anchor override: spawn at this node's position instead of the event's
## own. Lets you point spawning at a marker elsewhere in the (inline) scene.
@export var spawn_position: Node3D
#endregion

#region Public API
func execute(manager: ScenarioTriggerManager) -> void:
	var commander := manager.get_commander(commander_id)
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

	# Follow-up command chain for the commandable spawns.
	var event_commands: Array[EventCommand] = _event_commands()
	if event_commands.is_empty():
		return

	for unit: Commandable in commandables:
		var chain: Array[Command] = []
		for ec: EventCommand in event_commands:
			var cmd: Command = ec.to_command(manager)
			if cmd != null:
				chain.append(cmd)
		if chain.is_empty():
			continue
		unit.update_commands(chain)
		# Prime the nav target immediately. CommandReceiver only calls load_destination
		# when the agent's target_position differs from the command's — but a freshly
		# spawned NavigationAgent3D defaults to (0,0,0). When the destination is the map
		# centre (also world origin) that guard skips the load and the unit treats
		# navigation as already finished, dropping the command on its first tick. Setting
		# the target explicitly here kicks off path computation so the unit advances.
		unit.load_destination(chain[0])
#endregion

#region Private helpers
## Direct EventCommand children, in scene-tree order.
func _event_commands() -> Array[EventCommand]:
	var result: Array[EventCommand] = []
	for child in get_children():
		if child is EventCommand:
			result.append(child)
	return result
#endregion

#region Editor gizmo
func _draw_editor_gizmo(verts: PackedVector3Array) -> void:
	_gizmo_ring(verts, Vector3.ZERO, _SPAWN_RING_RADIUS)
	# Polyline from the spawn point through each EventCommandPoint child (local space).
	# EventCommandTarget nodes don't have a fixed position, so only waypoints are drawn.
	var path: Array[Vector3] = [Vector3.ZERO]
	for child in get_children():
		if child is EventCommandPoint:
			path.append((child as EventCommandPoint).position)
	_gizmo_polyline(verts, path)
#endregion
