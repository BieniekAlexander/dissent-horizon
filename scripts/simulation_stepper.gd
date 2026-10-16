class_name SimulationStepper
extends Node

## THE ONE LOOP THAT STEPS EVERY ENTITY IN A SCENARIO, in spawn-serial order: every entity
## decides, then every entity acts, then the tick's deaths resolve.
## gdd/systems/commands/the-simulation-step.md.
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

## The decide round: one per tick, and one per entity stepping itself outside a scenario. A
## decision is stamped with the round that made it and counts only in that round, so none is
## ever read on a later tick. Static because the commands holding decisions have no path to
## their stepper; it only ever grows, so no stamp can match a later round.
static var _round: int = 0


## Start a new decide round.
static func begin_round() -> void:
	_round += 1


## The round now running, which a decision made this tick is stamped with.
static func current_round() -> int:
	return _round


## Whether entities may sleep through ticks whose outcome is known
## (gdd/systems/commands/the-simulation-step.md §Sleepy updates). Off, every entity steps every
## tick — the same match, which is how the determinism probe proves sleeping changes nothing.
## Static: a process-wide switch for tools and tests, like the decide round.
static var is_sleep_enabled: bool = true

## Ticks this stepper has run, which entities' wake ticks are counted in.
var _tick: int = 0
## The pieces' hurtboxes as this tick starts, which the decide pass reads (SpatialIndex).
var index: SpatialIndex = SpatialIndex.new()

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


## One tick, in three passes over the entities in play, each in serial order: every entity
## decides, then every entity acts, then every death the tick dealt resolves. Public so a test
## can drive it.
func step(a_delta: float) -> void:
	begin_round()
	_tick += 1
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
	index.rebuild(stepping)
	_wake_watchers(stepping)
	SpatialIndex.reading = index
	for item: Variant in stepping:
		if is_instance_valid(item) and (item as Entity).is_inside_tree():
			var deciding: Entity = item
			if not deciding.is_asleep_at(_tick):
				deciding.decide_simulation()
	SpatialIndex.reading = null
	for item: Variant in stepping:
		if is_instance_valid(item) and (item as Entity).is_inside_tree():
			_act(item as Entity, a_delta)
	for item: Variant in stepping:
		if is_instance_valid(item) and (item as Entity).is_inside_tree():
			(item as Entity).resolve_death()


## Wake every sleeping entity with a hostile now within its watch radius, before anything
## decides, so it decides this tick exactly as it would have awake.
func _wake_watchers(a_stepping: Array) -> void:
	for item: Variant in a_stepping:
		var entity: Entity = item
		if entity.is_asleep_at(_tick) and entity.watch_radius() >= 0.0:
			if index.has_hostile_near(entity, entity.watch_radius()):
				entity.wake()


## One entity's act pass: skipped while it sleeps — counted, so it catches up on waking — and
## after it, how long it may sleep.
func _act(a_entity: Entity, a_delta: float) -> void:
	if a_entity.is_asleep_at(_tick):
		a_entity.note_slept_tick()
		return
	a_entity.catch_up_slept_ticks()
	a_entity.step_simulation(a_delta)
	var sleep: int = a_entity.step_sleep_ticks() if is_sleep_enabled else 0
	a_entity.sleep_until(_tick + 1 + sleep)


## A node joined or left some entity's subtree: that entity rebuilds the list of nodes it steps
## before its next tick.
func _on_tree_changed(a_node: Node) -> void:
	var entity: Entity = Entity.owning(a_node)
	if entity != null:
		entity.invalidate_step_list()
