class_name SimulationSnapshot
extends RefCounted

## A POINT-IN-TIME SNAPSHOT of the whole simulation, taken between ticks, and its restore into a
## freshly built copy of the same scenario. gdd/systems/commands/saved-games.md §The snapshot.
##
## What it holds:
##   * every entity in play, in spawn-serial order — on the tree or held off it (a garrison's
##     occupant) — with its scene, its commander, whether it is registered on the grid, and the
##     state of every node in its subtree (script fields, transform, collision layers);
##   * every other scripted node under the scenario that is simulation rather than presentation:
##     the commanders and their bot brains, the trigger manager, its triggers and tactics;
##   * the scenario's and the stepper's own counters, and the static state the simulation keeps
##     (random streams, id counters, the clock's held frames, the avoidance bit pool);
##   * the object table every shared non-node object went into (StateCodec).
##
## The restore lays it over a scenario built from the same scene (Alex, 2026-10-27): an entity
## the snapshot names and the scene lacks is spawned, one the scene has and the snapshot lacks is
## freed, and then every field is set. The snapshot is the whole truth about state; the scene
## supplies only structure — the map, the scene-authored triggers, every piece's node layout.

## Bumped whenever what a snapshot holds changes shape. A save also carries the build's version
## stamp and is refused by it (ReplayFile), so this only guards a snapshot read by mistake.
const FORMAT: int = 1

## The engine properties of an avoidance agent and obstacle a snapshot carries: every stored one
## the simulation can change or read. The velocity is set separately, after them.
const _AGENT_PROPERTIES: Array[StringName] = [
	&"target_position",
	&"path_desired_distance",
	&"target_desired_distance",
	&"path_height_offset",
	&"path_max_distance",
	&"navigation_layers",
	&"avoidance_enabled",
	&"height",
	&"radius",
	&"neighbor_distance",
	&"max_neighbors",
	&"time_horizon_agents",
	&"time_horizon_obstacles",
	&"max_speed",
	&"use_3d_avoidance",
	&"keep_y_velocity",
	&"avoidance_layers",
	&"avoidance_mask",
	&"avoidance_priority",
]
const _OBSTACLE_PROPERTIES: Array[StringName] = [
	&"radius",
	&"height",
	&"vertices",
	&"avoidance_enabled",
	&"avoidance_layers",
	&"use_3d_avoidance"
]

## The entity fields that say how long it sleeps (Entity.sleep_until), put back after the restore's
## last tree change.
const _SLEEP_FIELDS: Array[String] = ["_wake_tick", "_watch_radius", "_slept_ticks"]

## Subtrees that are presentation, wiring or derived, and are never walked for state: the map and
## its terrain are rebuilt from the scene and the placements, the interface is the viewer's, and
## the recorder, order stream and stepper are saved by name or not at all.
const _UNWALKED_CLASSES: Array[StringName] = [
	&"Map",
	&"CanvasItem",
	&"CanvasLayer",
	&"Camera3D",
	&"Fog",
	&"ReplayRecorder",
	&"OrderStream",
	&"SaveResume",
	&"SimulationStepper",
	&"AudioStreamPlayer",
	&"AudioStreamPlayer3D",
	&"DebugMode",
	&"CatchUpGovernor",
	&"AlertCenter",
	&"BotDebugOverlay",
	&"ConditionPoller",
]
## A piece's components that only draw it: what they show follows from the piece's state, so a
## restored piece's are left as its rebuilt scene made them.
const _PRESENTATION_CLASSES: Array[StringName] = [
	&"Selectable",
	&"CommandLineIndicator",
	&"MeshVisual",
	&"AltitudeIndicator",
	&"StatusVisuals",
]


#region Capture
## The snapshot of `scenario` as it stands. Call it between ticks.
static func capture(scenario: Scenario) -> Dictionary:
	var codec := StateCodec.new(scenario)
	var entities: Array = scenario.stepper.entities().map(
		func(entity: Entity) -> Dictionary: return _capture_entity(codec, scenario, entity)
	)
	var holders: Array = []
	for node: Node in _holder_nodes(scenario):
		holders.append([String(scenario.get_path_to(node)), _capture_node(codec, node, scenario)])
	var snapshot: Dictionary = {
		"format": FORMAT,
		"scenario": codec.fields_of(scenario),
		"stepper": codec.fields_of(scenario.stepper),
		"globals": _capture_globals(codec),
		"entities": entities,
		"holders": holders,
		"navigation": scenario.map.nav_manager.snapshot_state(),
		"fog": _capture_fog(scenario),
		"passable": _passable_cells(scenario),
	}
	# Last: every capture above may have added to it.
	snapshot["objects"] = codec.objects
	return snapshot


static func _capture_entity(codec: StateCodec, scenario: Scenario, entity: Entity) -> Dictionary:
	# The yaw memo is derived from the basis but taken lazily: the rebuilt piece will have taken it,
	# and the two records should agree.
	entity.settle_yaw()
	var parent: Node = entity.get_parent()
	return {
		"serial": entity.spawn_serial,
		"scene": entity.scene_file_path,
		"commander": entity.commander_id,
		"parent": String(scenario.get_path_to(parent)) if parent != null else "",
		"grid": scenario.map.structure_cell_map.has(entity),
		"cells": codec.encode(Array(scenario.map.structure_cell_map.get(entity, []))),
		"index": entity.get_index() if parent != null else -1,
		"groups": _own_groups(entity),
		"velocity": codec.encode(entity.velocity, true),
		"nodes": _capture_nodes(codec, entity),
	}


## Every node of `entity`'s own as `[path, record]`, parents before children.
static func _capture_nodes(codec: StateCodec, entity: Entity) -> Array:
	var out: Array = []
	for node: Node in _entity_nodes(entity):
		out.append([String(entity.get_path_to(node)), _capture_node(codec, node, entity)])
	return out


## One node's state: its script fields, and the engine state the simulation reads off it. A node
## the piece's scene does not make (an effect applied in play) also says how to make it again.
static func _capture_node(codec: StateCodec, node: Node, root: Node) -> Dictionary:
	var record: Dictionary = {}
	if node.get_script() != null:
		record["f"] = codec.fields_of(node)
	if node is Node3D:
		record["xf"] = codec.encode((node as Node3D).transform, true)
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		record["layers"] = [body.collision_layer, body.collision_mask]
	if node is CollisionShape3D:
		var collision := node as CollisionShape3D
		record["disabled"] = collision.disabled
		record["shape"] = _capture_shape(codec, collision.shape)
	if node is NavigationAgent3D:
		record["agent"] = _capture_agent(codec, node)
	if node is NavigationObstacle3D:
		record["obstacle"] = _capture_obstacle(codec, node)
	if node != root and not _is_authored(node, root):
		record["new"] = {
			"name": String(node.name),
			"scene": node.scene_file_path,
			"script": StateCodec.script_key(node.get_script()),
			"class": node.get_class(),
		}
		# Another piece's Loadout, hoisted onto this one by a bunker: handed over again rather
		# than made.
		var lender: int = Garrison.lender_of(node)
		if lender != 0:
			record["new"]["hoisted_from"] = lender
	return record


## An avoidance agent's engine state: what it was given, and what the navigation server holds for
## it. A velocity handed to an agent reaches avoidance on the NEXT frame, so the one in flight at
## a save is part of the state, and the server's current velocity is what its neighbours avoid.
static func _capture_agent(codec: StateCodec, agent: NavigationAgent3D) -> Dictionary:
	var rid: RID = agent.get_rid()
	var avoidance := agent as AvoidanceAgent3D
	var current: Vector3 = (
		avoidance.last_safe_velocity
		if avoidance != null
		else NavigationServer3D.agent_get_velocity(rid)
	)
	return {
		"properties": _capture_properties(codec, agent, _AGENT_PROPERTIES),
		"velocity": codec.encode(agent.velocity, true),
		"server_velocity": codec.encode(current, true),
		"server_field": codec.encode(NavigationServer3D.agent_get_velocity(rid), true),
		"server_position": codec.encode(NavigationServer3D.agent_get_position(rid), true),
	}


## An avoidance obstacle's engine state, and the navigation server's.
static func _capture_obstacle(codec: StateCodec, obstacle: NavigationObstacle3D) -> Dictionary:
	var rid: RID = obstacle.get_rid()
	return {
		"properties": _capture_properties(codec, obstacle, _OBSTACLE_PROPERTIES),
		"velocity": codec.encode(obstacle.velocity, true),
		"server_velocity": codec.encode(NavigationServer3D.obstacle_get_velocity(rid), true),
		"server_position": codec.encode(NavigationServer3D.obstacle_get_position(rid), true),
	}


static func _capture_properties(
	codec: StateCodec, node: Node, names: Array[StringName]
) -> Dictionary:
	var out: Dictionary = {}
	for name: StringName in names:
		out[String(name)] = codec.encode(node.get(name), true)
	return out


## Set each saved property only where it differs: setting one re-registers an agent with the
## server, which drops the velocity it was handed this frame (measured 2026-10-27).
static func _restore_properties(codec: StateCodec, node: Node, saved: Dictionary) -> void:
	for name: String in saved:
		var current: Variant = node.get(StringName(name))
		var wanted: Variant = codec.decode(saved[name], current, typeof(current))
		if current != wanted:
			node.set(StringName(name), wanted)


## A collision shape: a file-backed or scene-built one by its path, one made in play (a range fitted
## to a piece's reach) by its class and dimensions, which the rebuilt piece need not have made the
## same way — the shape is what a scan measures by.
static func _capture_shape(codec: StateCodec, shape: Shape3D) -> Variant:
	if shape == null:
		return null
	if not shape.resource_path.is_empty():
		return {"path": shape.resource_path}
	var dimensions: Dictionary = {}
	for property: Dictionary in shape.get_property_list():
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_STORAGE) != 0 and (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			var name: String = property["name"]
			if not name.begins_with("resource_"):
				dimensions[name] = codec.encode(shape.get(name), false)
	return {"class": shape.get_class(), "dimensions": dimensions}


static func _restore_shape(codec: StateCodec, collision: CollisionShape3D, saved: Variant) -> void:
	if saved == null:
		collision.shape = null
		return
	var spec: Dictionary = saved
	if spec.has("path"):
		if collision.shape == null or collision.shape.resource_path != str(spec["path"]):
			collision.shape = load(str(spec["path"]))
		return
	var shape := ClassDB.instantiate(StringName(spec["class"])) as Shape3D
	var dimensions: Dictionary = spec["dimensions"]
	for name: String in dimensions:
		shape.set(name, codec.decode(dimensions[name], shape.get(name), typeof(shape.get(name))))
	collision.shape = shape


## Each commander's fog: what it has explored, which only the whole match's history made, and
## its sight — the per-pixel counts and each source's stamp. Bots read the fog BEFORE it updates
## in a tick, so the sight a restore must give them is the saved one, a tick behind the pieces,
## not one stamped from the pieces as they now stand.
static func _capture_fog(scenario: Scenario) -> Array:
	var out: Array = []
	for commander: Commander in scenario.commanders:
		var fog: Fog = Fog.for_commander(commander.id) if commander != null else null
		if fog == null:
			continue
		var raster: FogRaster = fog.raster()
		var stamps: Array = []
		for stamp: PackedInt64Array in raster.sight_stamps():
			var source: Entity = instance_from_id(stamp[0]) as Entity
			assert(source != null and source.spawn_serial > 0, "a fog stamp from an unsaved source")
			var record: Array = Array(stamp)
			record[0] = source.spawn_serial
			stamps.append(record)
		stamps.sort()
		(
			out
			. append(
				{
					"commander": commander.id,
					"explored": Marshalls.raw_to_base64(raster.explored_bytes()),
					"fog": Marshalls.raw_to_base64(raster.fog_bytes()),
					"counts": Marshalls.raw_to_base64(raster.sight_counts().to_byte_array()),
					"stamps": stamps,
				}
			)
		)
	return out


## Which cells are passable, as text. Derived — the grid is rebuilt from the placements — so a
## restore sets nothing from it: it is in the snapshot so that two snapshots of one moment show
## when the rebuilt grid is not the saved one.
static func _passable_cells(scenario: Scenario) -> String:
	var grid: TerrainGrid = scenario.map.terrain_grid
	return Marshalls.raw_to_base64(grid.navigable_mask(grid.get_bounds_rect(), 0, 1))


static func _restore_fog(codec: StateCodec, saved: Array) -> void:
	for record: Dictionary in saved:
		var fog: Fog = Fog.for_commander(int(record["commander"]))
		if fog == null:
			continue
		var raster: FogRaster = fog.raster()
		var explored: PackedByteArray = Marshalls.base64_to_raw(record["explored"])
		if raster.explored_bytes().size() != explored.size():
			continue
		raster.set_explored_bytes(explored)
		var stamps: Array = []
		for stamp: Array in record["stamps"]:
			var source: Entity = codec.entities_by_serial.get(int(stamp[0]))
			assert(source != null, "a fog stamp's source was not restored")
			var renumbered: PackedInt64Array = PackedInt64Array(stamp)
			renumbered[0] = source.get_instance_id()
			stamps.append(renumbered)
		raster.set_sight_state(
			Marshalls.base64_to_raw(record["counts"]).to_int32_array(),
			Marshalls.base64_to_raw(record["fog"]),
			stamps
		)


static func _capture_globals(codec: StateCodec) -> Dictionary:
	return {
		"rng": codec.encode(SU.rng),
		"purchase_next_id": PurchaseTransaction.next_id(),
		"stepper_round": SimulationStepper.current_round(),
		"physics_frame": SimulationClock.physics_frame(),
		"avoidance_bits": AvoidanceAgent3D.snapshot_pool(),
	}


#endregion


#region Restore
## The first half of a restore: give `scenario` the snapshot's STRUCTURE — free what it lacks,
## spawn what it has, make every node it names, and build the navigation mesh for the grid that
## leaves. A restore runs this some frames ahead of `restore` (SaveResume), because the navigation
## server takes up a newly spawned agent only over its next steps, and an agent the server has not
## taken up stands still for them.
static func prepare(scenario: Scenario, snapshot: Dictionary) -> void:
	assert(int(snapshot.get("format", 0)) == FORMAT, "SimulationSnapshot: unknown format")
	var records: Array = snapshot["entities"]
	# Spawning or freeing an entity runs code (accounting, registration) whose effects the saved
	# fields then overwrite, so this all happens before any field is set.
	_discard_unsaved(scenario, records)
	var entities: Dictionary = {}
	for record: Dictionary in records:
		entities[int(record["serial"])] = _entity_for(scenario, record)
	for record: Dictionary in records:
		_hoist_lent_nodes(entities, entities[int(record["serial"])], record["nodes"])
	for record: Dictionary in records:
		_ensure_nodes(entities[int(record["serial"])], record["nodes"])
	_order_entities(entities, records)
	_ensure_holders(scenario, snapshot["holders"])
	for holder: Node in _holder_nodes(scenario):
		if holder.has_method(&"prepare_snapshot_restore"):
			holder.call(&"prepare_snapshot_restore")
	scenario.map.nav_manager.rebuild_now()
	_prime_agents(entities, records)


## Make `scenario` — built from the same scene as the one `snapshot` was taken of, booted, given
## its structure (`prepare`), and between ticks — into the snapshot's state. Runs `prepare` again
## first, which finds nothing left to do unless it was skipped.
static func restore(scenario: Scenario, snapshot: Dictionary) -> void:
	prepare(scenario, snapshot)
	var codec := StateCodec.new(scenario)
	codec.objects = snapshot["objects"]
	var records: Array = snapshot["entities"]
	for record: Dictionary in records:
		codec.entities_by_serial[int(record["serial"])] = _entity_for(scenario, record)
	scenario.map.nav_manager.restore_snapshot_state(snapshot["navigation"])

	_adopt_all(codec, scenario, snapshot, records)
	codec.decode_into(scenario, snapshot["scenario"])
	codec.decode_into(scenario.stepper, snapshot["stepper"])
	for pair: Array in snapshot["holders"]:
		var holder: Node = scenario.get_node_or_null(NodePath(pair[0]))
		_restore_node(codec, holder, pair[1])
	for record: Dictionary in records:
		_restore_entity(codec, codec.entities_by_serial[int(record["serial"])], record)

	var manager: ScenarioTriggerManager = scenario.trigger_manager()
	if manager != null:
		manager.clear_for_restore()
	_restore_globals(codec, snapshot["globals"])
	if manager != null:
		manager.reraise_saved_dialogs()
	scenario.adopt_restored_entities(codec.entities_by_serial)
	# Off the tree last: a held entity was spawned and filled in the tree, like any other.
	for record: Dictionary in records:
		_hold_if_held(codec.entities_by_serial[int(record["serial"])], record)
	for entity: Entity in codec.entities_by_serial.values():
		_sync_physics_transforms(entity)
	scenario.stepper.index.rebuild(scenario.stepper.entities())
	_finish(codec, scenario, records)
	# Taking an entity off the tree, or handing a node back, wakes the pieces it touched: their
	# sleep is put back as it was saved.
	for record: Dictionary in records:
		_resettle(codec, codec.entities_by_serial[int(record["serial"])], record)
	# The server's avoidance list in its canonical order, as the saved match's was.
	AvoidanceAgent3D.settle_order(true)
	_restore_fog(codec, snapshot.get("fog", []))


## Hand the physics server every collision object's transform in `entity` now. A node passes
## its moved transform on only when the tree next flushes transform notifications, at the start
## of a physics frame — and the restore runs inside one, so a radius query this frame would
## otherwise find the piece where the rebuilt scene first put it.
static func _sync_physics_transforms(entity: Entity) -> void:
	if not entity.is_inside_tree():
		return
	var objects: Array[Node] = entity.find_children("*", "CollisionObject3D", true, false)
	objects.append(entity)
	for node: Node in objects:
		if node is Area3D:
			PhysicsServer3D.area_set_transform(
				(node as Area3D).get_rid(), (node as Area3D).global_transform
			)
		elif node is PhysicsBody3D:
			PhysicsServer3D.body_set_state(
				(node as PhysicsBody3D).get_rid(),
				PhysicsServer3D.BODY_STATE_TRANSFORM,
				(node as PhysicsBody3D).global_transform
			)


## The fields that say how long `entity` sleeps, set again as saved.
static func _resettle(codec: StateCodec, entity: Entity, record: Dictionary) -> void:
	var fields: Dictionary = (record["nodes"] as Array)[0][1].get("f", {})
	var sleep: Dictionary = {}
	for name: String in _SLEEP_FIELDS:
		if fields.has(name):
			sleep[name] = fields[name]
	codec.decode_into(entity, sleep)


## Call `finish_snapshot_restore` on everything restored that declares it: what needs the whole
## world in place first, such as redrawing a remembered image where its structure now stands.
static func _finish(codec: StateCodec, scenario: Scenario, records: Array) -> void:
	var restored: Array = codec.restored_objects() + _holder_nodes(scenario)
	for record: Dictionary in records:
		restored.append_array(_entity_nodes(codec.entities_by_serial[int(record["serial"])]))
	for target: Object in restored:
		if is_instance_valid(target) and target.has_method(&"finish_snapshot_restore"):
			target.call(&"finish_snapshot_restore")


## Bind every saved object to the rebuilt scene's own wherever it holds one
## (StateCodec.adopt_fields).
static func _adopt_all(
	codec: StateCodec, scenario: Scenario, snapshot: Dictionary, records: Array
) -> void:
	codec.adopt_fields(scenario, snapshot["scenario"])
	codec.adopt_fields(scenario.stepper, snapshot["stepper"])
	for pair: Array in snapshot["holders"]:
		if pair[1].has("f"):
			codec.adopt_fields(scenario.get_node(NodePath(pair[0])), pair[1]["f"])
	for record: Dictionary in records:
		var entity: Entity = codec.entities_by_serial[int(record["serial"])]
		for pair: Array in record["nodes"]:
			if pair[1].has("f"):
				codec.adopt_fields(entity.get_node(NodePath(pair[0])), pair[1]["f"])


## Free every entity the rebuilt scene put in play that the snapshot does not hold.
static func _discard_unsaved(scenario: Scenario, records: Array) -> void:
	var saved: Dictionary = {}
	for record: Dictionary in records:
		saved[int(record["serial"])] = true
	for entity: Entity in scenario.stepper.entities():
		if saved.has(entity.spawn_serial):
			continue
		if scenario.map.structure_cell_map.has(entity):
			scenario.map.remove_structure(entity)
		scenario.forget_entity(entity)
		if entity.get_parent() != null:
			entity.get_parent().remove_child(entity)
		entity.free()


## The rebuilt scene's entity with the record's serial, or one spawned from the record's scene
## and placed where the snapshot has it.
static func _entity_for(scenario: Scenario, record: Dictionary) -> Entity:
	var serial: int = record["serial"]
	var existing: Entity = scenario.stepper.entity_with_serial(serial)
	if existing != null:
		var owner_id: int = record["commander"]
		if existing.commander_id != owner_id:
			existing.commander = scenario.commanders[owner_id]
		_match_grid(scenario.map, existing, record)
		return existing
	var entity := (load(str(record["scene"])) as PackedScene).instantiate() as Entity
	# Taken before it enters the tree, so it keeps its own serial rather than the next one.
	entity.spawn_serial = serial
	var commander: Commander = scenario.commanders[int(record["commander"])]
	var root_state: Dictionary = (record["nodes"] as Array)[0][1]
	var transform: Transform3D = StateCodec.new().decode(root_state["xf"], null, TYPE_TRANSFORM3D)
	entity.transform = transform
	entity.initialize(scenario.map, commander)
	if bool(record["grid"]):
		_register_on_grid(scenario.map, entity, record)
	scenario.adopt_restored_entity(entity)
	return entity


## Put a piece the rebuilt scene already had on the grid, or off it, as the save had it: one that
## left the grid in play (a piece undeployed, a fixture freed of its cells) was put back on by the
## scene.
static func _match_grid(map: Map, entity: Entity, record: Dictionary) -> void:
	var is_on_grid: bool = map.structure_cell_map.has(entity)
	if bool(record["grid"]) == is_on_grid:
		return
	if is_on_grid:
		map.remove_structure(entity)
	else:
		_register_on_grid(map, entity, record)


## Register a spawned fixture as add_structure does, from where it stands; and where that gives
## other cells than the save held (a piece deployed off its footprint's centre), on the saved cells
## instead, without moving it.
static func _register_on_grid(map: Map, entity: Entity, record: Dictionary) -> void:
	var transform: Transform3D = entity.transform
	map.add_structure(entity, VU.in_xz(transform.origin))
	var saved: Array[Vector2i] = []
	saved.assign(StateCodec.new().decode(record["cells"], [], TYPE_ARRAY))
	var placed: Array = map.structure_cell_map.get(entity, [])
	if Array(saved) != placed:
		map.remove_structure(entity)
		map.register_saved_cells(entity, saved)
	entity.transform = transform


## Put every parent's entities in the order the snapshot had them, after its other children: code
## that walks a commander's children walks them in this order, and a piece that changed hands, or
## was spawned, came at the end of it in the saved match.
static func _order_entities(entities: Dictionary, records: Array) -> void:
	var placed: Array = records.filter(
		func(record: Dictionary) -> bool: return int(record.get("index", -1)) >= 0
	)
	placed.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"])
	)
	for record: Dictionary in placed:
		var entity: Entity = entities[int(record["serial"])]
		if entity.get_parent() != null:
			entity.get_parent().move_child(entity, -1)


## Hand `entity` every node its record says another piece lent it (a bunker holding an occupant's
## Loadout), under the name and parent it had, before any node is made or freed.
static func _hoist_lent_nodes(entities: Dictionary, entity: Entity, nodes: Array) -> void:
	for pair: Array in nodes:
		var spec: Dictionary = (pair[1] as Dictionary).get("new", {})
		var path: String = pair[0]
		if not spec.has("hoisted_from") or entity.has_node(NodePath(path)):
			continue
		var lender: Entity = entities.get(int(spec["hoisted_from"]))
		var lent := lender.weapon_inventory if lender != null else null
		if lent == null:
			continue
		lent.name = spec["name"]
		var parent_path: String = path.get_base_dir() if path.contains("/") else "."
		lent.reparent(entity.get_node(NodePath(parent_path)), false)


## Put the navigation server's own state for every agent back: where it stands for the server and
## what it is moving at. Done with the structure, frames ahead of the state, because the server
## takes what it is given only at its next step; the current velocity is put back again with the
## state, since avoidance moves it every step meanwhile.
static func _prime_agents(entities: Dictionary, records: Array) -> void:
	var codec := StateCodec.new()
	for record: Dictionary in records:
		var entity: Entity = entities[int(record["serial"])]
		for pair: Array in record["nodes"]:
			if (pair[1] as Dictionary).has("obstacle"):
				var obstacle := entity.get_node_or_null(NodePath(pair[0])) as NavigationObstacle3D
				var held: Dictionary = pair[1]["obstacle"]
				if obstacle != null:
					NavigationServer3D.obstacle_set_position(
						obstacle.get_rid(),
						codec.decode(held["server_position"], null, TYPE_VECTOR3)
					)
					NavigationServer3D.obstacle_set_velocity(
						obstacle.get_rid(),
						codec.decode(held["server_velocity"], null, TYPE_VECTOR3)
					)
			if not (pair[1] as Dictionary).has("agent"):
				continue
			var agent := entity.get_node_or_null(NodePath(pair[0])) as NavigationAgent3D
			if agent == null:
				continue
			var saved: Dictionary = pair[1]["agent"]
			var rid: RID = agent.get_rid()
			NavigationServer3D.agent_set_position(
				rid, codec.decode(saved["server_position"], null, TYPE_VECTOR3)
			)
			NavigationServer3D.agent_set_velocity_forced(
				rid, codec.decode(saved["server_velocity"], null, TYPE_VECTOR3)
			)


## Make every node the record names that `entity` lacks, and free every node it has that the
## record does not name. Parents come before children in the record.
static func _ensure_nodes(entity: Entity, nodes: Array) -> void:
	var named: Dictionary = {}
	for pair: Array in nodes:
		var path: String = pair[0]
		named[path] = true
		if entity.has_node(NodePath(path)):
			continue
		_make_node(entity, path, pair[1])
	for node: Node in _entity_nodes(entity):
		if not named.has(String(entity.get_path_to(node))) and is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	_order_like(entity, nodes)


## Put the children `nodes` names in the order it names them, after any it does not: a piece steps
## its nodes in tree order, and a node handed back in play (an occupant's Loadout) comes back
## last, not where its scene had it.
static func _order_like(root: Node, nodes: Array) -> void:
	for pair: Array in nodes:
		var path: String = pair[0]
		if path == ".":
			continue
		var node: Node = root.get_node_or_null(NodePath(path))
		if node != null:
			node.get_parent().move_child(node, -1)


static func _ensure_holders(scenario: Scenario, holders: Array) -> void:
	for pair: Array in holders:
		var path: String = pair[0]
		if not scenario.has_node(NodePath(path)):
			_make_node(scenario, path, pair[1])


static func _make_node(root: Node, path: String, record: Dictionary) -> void:
	assert(record.has("new"), "SimulationSnapshot: %s is missing and not made in play" % path)
	var spec: Dictionary = record["new"]
	var node: Node = null
	if not str(spec["scene"]).is_empty():
		node = (load(str(spec["scene"])) as PackedScene).instantiate()
	elif not str(spec["script"]).is_empty():
		node = StateCodec.instantiate(StateCodec.script_for_key(spec["script"]))
	else:
		node = ClassDB.instantiate(StringName(spec["class"]))
	node.name = spec["name"]
	var parent_path: String = path.get_base_dir() if path.contains("/") else "."
	root.get_node(NodePath(parent_path)).add_child(node)


static func _restore_entity(codec: StateCodec, entity: Entity, record: Dictionary) -> void:
	# Children first, the piece itself last: a component's setter may wake its piece (an order
	# given, hp changed), and the piece's own fields are what say whether it sleeps.
	var nodes: Array = (record["nodes"] as Array).duplicate()
	nodes.reverse()
	for pair: Array in nodes:
		_restore_node(codec, entity.get_node(NodePath(pair[0])), pair[1])
	entity.velocity = codec.decode(record["velocity"], entity.velocity, TYPE_VECTOR3)
	# Stepped by the scenario's stepper, never by itself (Entity._take_spawn_serial).
	entity.set_physics_process(false)
	var wanted: Array = record["groups"]
	for group: StringName in _own_groups(entity):
		if not wanted.has(String(group)):
			entity.remove_from_group(group)
	for group: String in wanted:
		entity.add_to_group(StringName(group))


static func _restore_node(codec: StateCodec, node: Node, record: Dictionary) -> void:
	if record.has("f"):
		codec.decode_into(node, record["f"])
	if record.has("xf"):
		(node as Node3D).transform = codec.decode(record["xf"], null, TYPE_TRANSFORM3D)
	if record.has("layers"):
		var body := node as CollisionObject3D
		body.collision_layer = int(record["layers"][0])
		body.collision_mask = int(record["layers"][1])
	if record.has("disabled"):
		(node as CollisionShape3D).disabled = bool(record["disabled"])
	if record.has("shape"):
		_restore_shape(codec, node, record["shape"])
	if record.has("agent"):
		_restore_agent(codec, node, record["agent"])
	if record.has("obstacle"):
		var obstacle := node as NavigationObstacle3D
		_restore_properties(codec, obstacle, record["obstacle"]["properties"])
		obstacle.velocity = codec.decode(record["obstacle"]["velocity"], null, TYPE_VECTOR3)


static func _restore_agent(codec: StateCodec, agent: NavigationAgent3D, saved: Dictionary) -> void:
	_restore_properties(codec, agent, saved["properties"])
	NavigationServer3D.agent_set_velocity_forced(
		agent.get_rid(), codec.decode(saved["server_velocity"], null, TYPE_VECTOR3)
	)
	agent.velocity = codec.decode(saved["velocity"], null, TYPE_VECTOR3)


static func _restore_globals(codec: StateCodec, globals: Dictionary) -> void:
	codec.decode(globals["rng"], SU.rng, TYPE_OBJECT)
	PurchaseTransaction.restore_next_id(int(globals["purchase_next_id"]))
	SimulationStepper.restore_round(int(globals["stepper_round"]))
	SimulationClock.restore_physics_frame(int(globals["physics_frame"]))
	AvoidanceAgent3D.restore_pool(globals["avoidance_bits"])


## Take `entity` off the tree when the snapshot had it held there (a garrison's occupant).
static func _hold_if_held(entity: Entity, record: Dictionary) -> void:
	if not str(record["parent"]).is_empty() or entity.get_parent() == null:
		return
	entity.get_parent().remove_child(entity)
	# Off the map, an agent keeps the velocity the server last held for it, and takes it back up as
	# what it wants when it rejoins — a released occupant is nudged by it. A spawned agent never
	# had one: it is handed the saved one.
	var codec := StateCodec.new()
	for pair: Array in record["nodes"]:
		var saved: Dictionary = (pair[1] as Dictionary).get("agent", {})
		var agent := entity.get_node_or_null(NodePath(pair[0])) as NavigationAgent3D
		if agent != null and saved.has("server_field"):
			NavigationServer3D.agent_set_velocity(
				agent.get_rid(), codec.decode(saved["server_field"], null, TYPE_VECTOR3)
			)


#endregion


#region Walks
## Every node of `entity`'s own, itself first and parents before children, stopping at any entity
## nested beneath it (which is its own record).
static func _entity_nodes(entity: Entity) -> Array[Node]:
	var out: Array[Node] = [entity]
	_collect(entity, out, _is_outside_piece_state)
	return out


static func _is_outside_piece_state(node: Node) -> bool:
	return (
		node is Entity
		or _PRESENTATION_CLASSES.any(
			func(class_id: StringName) -> bool: return _is_class(node, class_id)
		)
	)


## Every scripted node under the scenario that is neither an entity's nor presentation.
static func _holder_nodes(scenario: Scenario) -> Array:
	var out: Array[Node] = []
	_collect(scenario, out, _is_unwalked)
	return out.filter(func(node: Node) -> bool: return node.get_script() != null)


static func _collect(parent: Node, out: Array[Node], is_boundary: Callable) -> void:
	for child: Node in parent.get_children():
		if is_boundary.call(child):
			continue
		out.append(child)
		_collect(child, out, is_boundary)


static func _is_unwalked(node: Node) -> bool:
	if node is Entity:
		return true
	# A commander is state whatever node it is: the human player's rig is a Control.
	if node is Commander:
		return false
	return _UNWALKED_CLASSES.any(
		func(class_id: StringName) -> bool: return _is_class(node, class_id)
	)


static func _is_class(node: Node, class_id: StringName) -> bool:
	if node.is_class(class_id):
		return true
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == class_id:
			return true
		script = script.get_base_script()
	return false


## Whether `node` is part of what `root`'s own scene makes, rather than added in play: its owner
## chain reaches the root (a node inside an instanced component is owned by the component, which
## is owned by the root).
static func _is_authored(node: Node, root: Node) -> bool:
	var owner_node: Node = node.owner
	while owner_node != null:
		if owner_node == root:
			return true
		owner_node = owner_node.owner
	return false


## The groups `entity` is in that a script put it in, not the engine's internal ones.
static func _own_groups(entity: Entity) -> Array:
	# Sorted: membership is a set, and the engine keeps a group's own order by the tree.
	var groups: Array = (
		entity
		. get_groups()
		. filter(func(group: StringName) -> bool: return not String(group).begins_with("_"))
		. map(func(group: StringName) -> String: return String(group))
	)
	groups.sort()
	return groups
#endregion
