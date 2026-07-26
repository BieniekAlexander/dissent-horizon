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
## Commandable that is still in the tree (garrisoned units are excluded — see below). If
## absent, spawned units receive no initial orders.
##
## Garrisoning spawned units, two ways:
## - `garrison_host`: a pre-placed (scene-authored) Commandable. Each spawned Commandable
##   is garrisoned into it directly instead of placed at a world position.
## - Nested EventSpawnEntities children: any of THIS event's spawned Commandables that
##   carry a Garrison component are passed down as runtime hosts, and the child spawns
##   its units straight into them (round-robin) instead of firing independently. A child
##   EventSpawnEntities therefore no-ops if run through the normal event tree — it only
##   spawns via the explicit hand-off from its parent (see _execute_with_hosts).

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
## Optional pre-placed garrison host. When set, every spawned Commandable is garrisoned
## into it (see Garrison.garrison) instead of being placed at a world position.
@export var garrison_host: Commandable
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
	# A child EventSpawnEntities only ever fires via its parent's explicit
	# _execute_with_hosts hand-off (see below) — the normal event-tree recursion
	# (ScenarioTriggerManager.run_event) reaching it here must no-op.
	if get_parent() is EventSpawnEntities:
		return
	var commander := _resolve_commander(manager)
	if commander == null:
		return
	var map := manager.map
	if map == null:
		return

	var anchor: Vector3 = spawn_position.global_position if spawn_position != null else global_position
	var anchor_xz := VU.inXZ(anchor)

	var commandables := _instantiate_all(map, commander, anchor, anchor_xz)

	if not commandables.is_empty():
		if garrison_host != null:
			_garrison_all(commandables, [garrison_host], map, commander)
		else:
			map.add_entities(commandables, anchor_xz, commander)

	var spawned_hosts := _garrisonable(commandables)
	for child: Node in get_children():
		if child is EventSpawnEntities:
			(child as EventSpawnEntities)._execute_with_hosts(spawned_hosts, map, commander)

	if commandables.is_empty():
		return

	var issue_cmd: EventIssueCommand = _find_issue_command()
	if issue_cmd != null:
		issue_cmd.issue_commands_to(_exclude_garrisoned(commandables), manager, commander.id)


## Entry point for an EventSpawnEntities nested under another EventSpawnEntities. Spawns
## its own entities exactly as execute() does (ignoring `garrison_host` — the parent's
## `hosts` win instead), garrisons every spawned Commandable round-robin across `hosts`,
## then recurses into ITS OWN EventSpawnEntities children, passing down whichever of its
## spawned Commandables carry a Garrison component.
func _execute_with_hosts(hosts: Array[Commandable], map: Map, commander: Commander) -> void:
	var anchor: Vector3 = spawn_position.global_position if spawn_position != null else global_position
	var anchor_xz := VU.inXZ(anchor)

	var commandables := _instantiate_all(map, commander, anchor, anchor_xz)
	if commandables.is_empty():
		return

	_garrison_all(commandables, hosts, map, commander)

	var my_hosts := _garrisonable(commandables)
	for child: Node in get_children():
		if child is EventSpawnEntities:
			(child as EventSpawnEntities)._execute_with_hosts(my_hosts, map, commander)
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


## Instances every scene in `entity_scenes` `count` times and routes each by kind.
## Commandables are returned uninitialized and out of tree — callers choose the
## placement path (a batched Map.add_entities, or an explicit initialize()-then-garrison).
## Non-Commandable Entities and bare nodes have no such choice to make, so they're placed
## immediately at `anchor`/`anchor_xz`.
func _instantiate_all(
	map: Map, commander: Commander, anchor: Vector3, anchor_xz: Vector2
) -> Array[Commandable]:
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
	return commandables


## Places every one of `commandables` into a host from `hosts`, round-robin (index mod
## hosts.size()). Each unit is initialized (added to the tree under `commander`) first,
## so its components resolve and Garrison.garrison() operates on a fully-live unit,
## exactly as a normal world-placed spawn would be before Map.add_entities positions it.
## A host at capacity is an authoring error, not a runtime possibility — surfaced loudly
## (push_error + assertion) rather than silently dropping the unit.
func _garrison_all(
	commandables: Array[Commandable], hosts: Array[Commandable], map: Map, commander: Commander
) -> void:
	if hosts.is_empty():
		push_error("EventSpawnEntities '%s': no garrison hosts to spawn into" % name)
		assert(false, "No garrison hosts available")
		return
	for i: int in commandables.size():
		var unit: Commandable = commandables[i]
		unit.initialize(map, commander)
		var host: Commandable = hosts[i % hosts.size()]
		if not host.garrison.can_garrison():
			push_error("EventSpawnEntities '%s': garrison on '%s' is full at spawn time" % [name, host.name])
			assert(false, "Garrison full at spawn time")
			continue
		host.garrison.garrison(unit)


## The subset of `commandables` that carry a Garrison component — the runtime hosts
## handed down to a nested EventSpawnEntities child (see _execute_with_hosts).
func _garrisonable(commandables: Array[Commandable]) -> Array[Commandable]:
	var result: Array[Commandable] = []
	for c: Commandable in commandables:
		if c.garrison != null:
			result.append(c)
	return result


## `commandables` minus any that garrisoning has since removed from the tree —
## EventIssueCommand.issue_commands_to expects live, in-tree units.
func _exclude_garrisoned(commandables: Array[Commandable]) -> Array[Commandable]:
	var result: Array[Commandable] = []
	for unit: Commandable in commandables:
		if unit.is_inside_tree():
			result.append(unit)
	return result
#endregion
