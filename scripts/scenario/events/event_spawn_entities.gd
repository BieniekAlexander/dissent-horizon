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
## Garrisoning spawned units, two ways (either fills a CLOSED garrison — a stock truck,
## a Compound — just as well as an open one; see _garrison_all):
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
## How many of EACH scene in `entity_scenes` to spawn — a plain number ("3"), or any
## expression (see ScenarioExpression). Blank means DEFAULT_COUNT.
##
## Resolved once per execution, so a repeating wave can grow: "2 + fires" spawns 2, then 3,
## then 4 …; "randi_range(2, 5)" varies each time. Clamped at 0 — a negative count is a
## typo, not a request to despawn.
##
## There is no separate numeric `count` field: "3" is already a valid expression, so a second
## export would only be a second place for the same number to live. Scenes authored before
## this are migrated by _set below.
@export_placeholder("1 — or e.g. 2 + fires") var count_expression: String = "":
	set(value):
		count_expression = value
		# Re-check the yellow warning in the Scene dock as the field is typed into.
		update_configuration_warnings()

## What a blank count_expression means, and the fallback when one doesn't evaluate. Matches
## the default of the `count` export this replaced, so an un-authored event is unchanged.
const DEFAULT_COUNT: int = 1

## Optional spawn-anchor override: spawn at this node's position instead of the event's
## own. Lets you point spawning at a marker elsewhere in the (inline) scene.
##
## If the assigned node has Node3D CHILDREN, one of them is picked at RANDOM per execution
## and used instead — so a handful of marker children turns one spawner into "arrive at any
## of these gates". The pick is per execution, not per entity, so a wave stays together;
## Map.add_entities already spreads the individual units around the chosen anchor.
@export var spawn_position: Node3D
## Optional pre-placed garrison host. When set, every spawned Commandable is garrisoned
## into it (see Garrison.garrison) instead of being placed at a world position.
@export var garrison_host: Commandable

## Scene-tree groups every entity this event spawns is added to.
##
## The point is to give one WAVE an identity the game's data model doesn't have. "The units
## commander 2 owns" is a type the engine already knows; "the three irregulars this ambush
## dropped" is not, and without a label a later check can only approximate it. Stamping a
## group here and reading it back with ConditionGroupCount lets a trigger talk about exactly
## the things one event produced — the wave that came out of THIS spawner, not a similar one
## somewhere else on the map.
##
## Applied to every entity the event creates, whichever way it is routed: commandables that
## go through Map.add_entities, other Entities, and bare VFX nodes alike. Groups land on the
## spawned root, not on its components.
@export var spawn_groups: Array[StringName] = []
#endregion

#region Tool
## Flag an unusable count_expression in the Scene dock, where the author is looking, rather
## than leaving it to a log line at run time — a bad expression silently spawns DEFAULT_COUNT,
## which reads as "the feature doesn't work" rather than "that variable doesn't exist".
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var problem: String = ScenarioExpression.validation_error(count_expression)
	if not problem.is_empty():
		warnings.append("Count Expression \"%s\" %s" % [count_expression, problem])
	return warnings


## Migrate scenes authored against the old integer `count` export.
##
## PackedScene applies every stored property through set(), and set() routes a name the class
## no longer declares to _set — so an old scene's `count = 6` lands in count_expression as
## "6" and re-saves in the new form. Returning true marks it handled, which is also what
## keeps the editor from reporting the removed property as an error.
##
## Guarded on count_expression still being blank, so if a scene somehow carries both keys the
## authored expression wins regardless of which order they are applied in.
func _set(a_property: StringName, a_value: Variant) -> bool:
	if a_property == &"count":
		if not ScenarioExpression.is_authored(count_expression):
			count_expression = str(a_value)
		return true
	return false


func _validate_property(a_property: Dictionary) -> void:
	match a_property.name:
		"ownership":
			# Editing ownership re-runs validation so commander_id's read-only state updates.
			a_property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"commander_id":
			if assignment == Assignment.INHERITED:
				commander_id = -1
				a_property.usage = a_property.usage | PROPERTY_USAGE_READ_ONLY
			else:
				a_property.usage = a_property.usage & ~PROPERTY_USAGE_READ_ONLY
#endregion

#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	# A child EventSpawnEntities only ever fires via its parent's explicit
	# _execute_with_hosts hand-off (see below) — the normal event-tree recursion
	# (ScenarioTriggerManager.run_event) reaching it here must no-op.
	if get_parent() is EventSpawnEntities:
		return
	var commander := _resolve_commander(a_manager)
	if commander == null:
		return
	var map := a_manager.map
	if map == null:
		return

	var anchor: Vector3 = resolve_spawn_anchor()
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
		issue_cmd.issue_commands_to(_exclude_garrisoned(commandables), a_manager, commander.id)


## Entry point for an EventSpawnEntities nested under another EventSpawnEntities. Spawns
## its own entities exactly as execute() does (ignoring `garrison_host` — the parent's
## `hosts` win instead), garrisons every spawned Commandable round-robin across `hosts`,
## then recurses into ITS OWN EventSpawnEntities children, passing down whichever of its
## spawned Commandables carry a Garrison component.
func _execute_with_hosts(a_hosts: Array[Commandable], a_map: Map, a_commander: Commander) -> void:
	var anchor: Vector3 = resolve_spawn_anchor()
	var anchor_xz := VU.inXZ(anchor)

	var commandables := _instantiate_all(a_map, a_commander, anchor, anchor_xz)
	if commandables.is_empty():
		return

	_garrison_all(commandables, a_hosts, a_map, a_commander)

	var my_hosts := _garrisonable(commandables)
	for child: Node in get_children():
		if child is EventSpawnEntities:
			(child as EventSpawnEntities)._execute_with_hosts(my_hosts, a_map, a_commander)
#endregion

#region Private helpers
## The commander spawned entities belong to: `commander_id` when SPECIFIED, or the source
## entity's commander when INHERITED. Null when INHERITED but there's no source entity
## (e.g. fired from a GlobalTrigger) — callers then skip spawning.
func _resolve_commander(a_manager: ScenarioTriggerManager) -> Commander:
	if assignment == Assignment.INHERITED:
		var source := a_manager.reaction_source
		if source == null:
			return null
		return a_manager.get_commander(source.commander_id)
	return a_manager.get_commander(commander_id)

func _find_issue_command() -> EventIssueCommand:
	for child: Node in get_children():
		if child is EventIssueCommand:
			return child as EventIssueCommand
	return null


#region Authoring helpers
## The world point this execution spawns at.
##
## Three cases, in order: `spawn_position` with Node3D CHILDREN picks one of them at random
## (a set of markers = "arrive at any of these gates"); `spawn_position` with none uses the
## node itself; unset falls back to this event's own position.
##
## Non-Node3D children are skipped rather than counted, so a plain Node or an attached
## helper sitting under the marker can't win the draw and spawn the wave at the origin.
##
## Called once per execution, so a wave lands together at ONE of the markers. Individual
## units are still spread around that anchor by Map.add_entities' non-overlapping placement.
func resolve_spawn_anchor() -> Vector3:
	if spawn_position == null:
		return global_position
	var options: Array[Node3D] = []
	for child: Node in spawn_position.get_children():
		var point := child as Node3D
		if point != null:
			options.append(point)
	if options.is_empty():
		return spawn_position.global_position
	return (options.pick_random() as Node3D).global_position


## How many of EACH scene to spawn this execution. Never negative: a negative result is a
## typo, and range() would simply spawn nothing, which reads as "the event didn't run".
func resolve_count() -> int:
	var resolved: int = ScenarioExpression.evaluate_int(
		count_expression, DEFAULT_COUNT, owning_manager(), owner_fire_count(),
		"EventSpawnEntities %s (count_expression)" % name
	)
	return maxi(resolved, 0)
#endregion


## Instances every scene in `entity_scenes` `count` times and routes each by kind.
## Commandables are returned uninitialized and out of tree — callers choose the
## placement path (a batched Map.add_entities, or an explicit initialize()-then-garrison).
## Non-Commandable Entities and bare nodes have no such choice to make, so they're placed
## immediately at `anchor`/`anchor_xz`.
func _instantiate_all(
	a_map: Map, a_commander: Commander, a_anchor: Vector3, a_anchor_xz: Vector2
) -> Array[Commandable]:
	var commandables: Array[Commandable] = []
	var spawn_count: int = resolve_count()
	for packed: PackedScene in entity_scenes:
		if packed == null:
			continue
		for _i in range(spawn_count):
			var inst := packed.instantiate()
			# Before any routing, so the label is on the node no matter which branch places it —
			# and before it enters the tree, so anything reacting to the group sees it complete.
			_apply_spawn_groups(inst)
			if inst is Commandable:
				commandables.append(inst)
			elif inst is Entity:
				a_map.add_entity(inst as Entity, a_anchor_xz, a_commander)
			else:
				a_map.add_child(inst)
				if inst is Node3D:
					(inst as Node3D).global_position = a_anchor
	return commandables


## Stamp this event's `spawn_groups` onto a freshly instanced node.
##
## Empty names are skipped: an Array export shows a blank row whenever you grow it in the
## inspector, and adding a node to the "" group would quietly pollute every check that ever
## forgets to set its own group name.
func _apply_spawn_groups(a_node: Node) -> void:
	for group: StringName in spawn_groups:
		if not group.is_empty():
			a_node.add_to_group(group)


## Places every one of `commandables` into a host from `hosts`, round-robin (index mod
## hosts.size()). Each unit is initialized (added to the tree under `commander`) first,
## so its components resolve and Garrison.garrison() operates on a fully-live unit,
## exactly as a normal world-placed spawn would be before Map.add_entities positions it.
## A host without room for the unit is an authoring error, not a runtime possibility —
## surfaced loudly (push_error + assertion) rather than silently dropping the unit.
##
## Only ROOM is checked, never the host's occupancy masks: authoring a starting load is
## an act of placement, not an Occupy order, so it fills a CLOSED garrison — a stock
## truck's cage, a Compound — exactly as readily as an open one. That is how a
## scenario starts a truck already carrying prisoners.
func _garrison_all(
	a_commandables: Array[Commandable], a_hosts: Array[Commandable], a_map: Map, a_commander: Commander
) -> void:
	if a_hosts.is_empty():
		push_error("EventSpawnEntities '%s': no garrison hosts to spawn into" % name)
		assert(false, "No garrison hosts available")
		return
	for i: int in a_commandables.size():
		var unit: Commandable = a_commandables[i]
		unit.initialize(a_map, a_commander)
		var host: Commandable = a_hosts[i % a_hosts.size()]
		if not host.garrison.has_room_for(unit):
			push_error("EventSpawnEntities '%s': garrison on '%s' has no room at spawn time" % [name, host.name])
			assert(false, "Garrison full at spawn time")
			continue
		host.garrison.garrison(unit)


## The subset of `commandables` that carry a Garrison component — the runtime hosts
## handed down to a nested EventSpawnEntities child (see _execute_with_hosts).
func _garrisonable(a_commandables: Array[Commandable]) -> Array[Commandable]:
	var result: Array[Commandable] = []
	for c: Commandable in a_commandables:
		if c.garrison != null:
			result.append(c)
	return result


## `commandables` minus any that garrisoning has since removed from the tree —
## EventIssueCommand.issue_commands_to expects live, in-tree units.
func _exclude_garrisoned(a_commandables: Array[Commandable]) -> Array[Commandable]:
	var result: Array[Commandable] = []
	for unit: Commandable in a_commandables:
		if unit.is_inside_tree():
			result.append(unit)
	return result
#endregion
