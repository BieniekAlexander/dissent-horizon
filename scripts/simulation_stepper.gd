class_name SimulationStepper
extends Node

## THE ONE LOOP THAT STEPS EVERY ENTITY IN A SCENARIO, in spawn-serial order, then resolves the
## tick's deaths. gdd/systems/commands/the-simulation-step.md.
##
## A node that does simulation work each tick defines `simulation_step(a_delta)` instead of
## `_physics_process`; its entity steps it (Entity.step_simulation), and this steps the entities.
## Serials are handed out in spawn order, the same on every run of a seed, so the order pieces
## act in no longer depends on where the scene tree happens to hold them.
##
## What a tick sees is fixed when it starts, as the engine's own process list is: an entity that
## enters play mid-tick, or a node added to an entity mid-tick, is first stepped on the next tick,
## and one that leaves the tree mid-tick is skipped.

## After every priority-0 system — the scenario's tick count, triggers, bots, fog — so orders
## those issue land before any piece acts on them; before Commander (100), whose production queue
## and blackboard read what the pieces did.
const STEP_PRIORITY: int = 50

## Every entity that has entered play, in serial order. Appending keeps it sorted, since serials
## only grow; freed entities are dropped as each tick snapshots it. UNTYPED: an entity can be
## freed outright mid-tick, and a freed object fails a typed read.
var _entities: Array = []
## The serial enlisted last, which the next must exceed.
var _last_serial: int = 0


func _init() -> void:
	name = "SimulationStepper"
	process_physics_priority = STEP_PRIORITY


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_tree_changed)
	get_tree().node_removed.disconnect(_on_tree_changed)


## Step `a_entity` from now on. Called once, as the entity takes its serial, so arrival order is
## serial order.
func enlist(a_entity: Entity) -> void:
	assert(a_entity.spawn_serial > _last_serial)
	_last_serial = a_entity.spawn_serial
	_entities.append(a_entity)


func _physics_process(a_delta: float) -> void:
	step(a_delta)


## One tick: every entity in play steps in serial order, then every death the tick dealt
## resolves, in the same order. Public so a test can drive it.
func step(a_delta: float) -> void:
	var stepping: Array = []
	var kept: Array = []
	for item: Variant in _entities:
		if not is_instance_valid(item):
			continue
		kept.append(item)
		var entity: Entity = item
		if entity.is_inside_tree() and entity.can_process():
			entity.prepare_step()
			stepping.append(entity)
	_entities = kept
	for item: Variant in stepping:
		if is_instance_valid(item) and (item as Entity).is_inside_tree():
			(item as Entity).step_simulation(a_delta)
	for item: Variant in stepping:
		if is_instance_valid(item) and (item as Entity).is_inside_tree():
			(item as Entity).resolve_death()


## A node joined or left some entity's subtree: that entity rebuilds the list of nodes it steps
## before its next tick.
func _on_tree_changed(a_node: Node) -> void:
	var entity: Entity = Entity.owning(a_node)
	if entity != null:
		entity.invalidate_step_list()
