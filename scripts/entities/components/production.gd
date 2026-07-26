class_name Production
extends Node

## Production component — owns the per-entity training queue and the
## "spawn a unit at the rally point" logic.
##
## Stage B of the Unit/Structure collapse. Previously Structure interleaved
## training-queue ticking, rally handling, train-bar UI updating, and unit
## spawning across its _process_commands, _update_state, _process, and a
## standalone train() method. All of that now lives here. Structure becomes
## a thin pass-through that hands Train commands to this component and asks
## it to tick once per physics frame.
##
## The component reads its parent entity for `commander`, `map`, and
## `global_position` when spawning. It assumes the parent is an Entity; on a
## non-Entity parent, spawning is a no-op.

#region Properties
## Path (relative to this node) to the TrainBar Node3D used to visualize
## training progress. Two-child contract: TrainBar must have a child
## "TrainBarFill" whose scale.x / position.x track progress. This mirrors the
## existing structure.tscn layout — when a future SpriteVisual / ProgressBar
## component takes over UI duty, this NodePath goes away.
@export var train_bar_path: NodePath

## The unit types this producer can train, configured per structure scene
## (e.g. Outpost → [UNIT_TECHNICIAN], Compound → [UNIT_IRREGULAR, UNIT_VANGUARD]).
## This component is the single source of truth for what an entity can produce —
## it replaces the old static Train.tool_applies_to table, so the capability
## lives with the component that actually performs the production. Callers that
## need to know what an entity can build (e.g. CommandContextParser building the
## HUD's train menu) inspect the entity's Production node rather than keying off
## its type in a command class.
@export var producible_types: Array[StringName] = []

## Each entry is [remaining_ticks, total_ticks, scene, type] — see the JOB_* indices.
## total_ticks is kept so the HUD/train bar can show real progress; type is kept so a
## cancelled job can refund its cost (see cancel()).
const JOB_REMAINING: int = 0
const JOB_TOTAL: int = 1
const JOB_SCENE: int = 2
const JOB_TYPE: int = 3
var training_queue: Array = []

## Build-rate fraction applied while the owning commander is vigor-strained (upkeep
## exceeds capacity) — production runs at half speed.
const STRAINED_RATE: float = 0.5

## Fractional build progress carried across ticks so a sub-1.0 rate (the strained
## penalty) still advances the integer countdown smoothly.
var _progress_accum: float = 0.0

var _train_bar: Node3D
#endregion

#region Lifecycle
func _ready() -> void:
	if not train_bar_path.is_empty():
		_train_bar = get_node_or_null(train_bar_path) as Node3D
#endregion

#region Public API
## Enqueue a new training job. Called by Structure when a Train command is
## accepted (resources confirmed and deducted). `unit_type` (an Entity.Type) is
## stored so cancel() can refund the job's cost; it's optional for callers/tests
## that don't need refunds.
func enqueue(creation_time: int, packed_scene: PackedScene, unit_type: Variant = null) -> void:
	training_queue.push_back([creation_time, creation_time, packed_scene, unit_type])

## Whether this producer can train the given unit type. Source of truth for the
## "what can this build" question across the codebase (HUD train menu, AI).
func can_produce(a_type: StringName) -> bool:
	return producible_types.has(a_type)

## Number of units queued (the first is actively training; the rest wait).
func job_count() -> int:
	return training_queue.size()

## The unit scene for queued job `i`.
func job_scene(i: int) -> PackedScene:
	return training_queue[i][JOB_SCENE] as PackedScene

## The Entity.Type for queued job `i` (used to refund cost on cancel). May be null
## if the job was enqueued without a type.
func job_type(i: int) -> Variant:
	return training_queue[i][JOB_TYPE]

## Cancel the queued job at `index`: remove it from the queue and refund its cost to
## the owning commander. A no-op (returns false) for an out-of-range index. Cancelling
## any job refunds the full cost — including the head job that's partway trained.
func cancel(index: int) -> bool:
	if index < 0 or index >= training_queue.size():
		return false
	var unit_type: Variant = training_queue[index][JOB_TYPE]
	training_queue.remove_at(index)
	# Removing the head job promotes the next one (its remaining is still full), so
	# clear the sub-tick accumulator to avoid leaking partial progress into it.
	if index == 0:
		_progress_accum = 0.0
	var entity: Entity = get_parent() as Entity
	if entity != null and entity.commander != null and unit_type != null:
		entity.commander.refund_resources_for(unit_type)
	return true

## Training progress (0..1) of queued job `i`: 0 when just enqueued, 1 when done.
## Only the head job (i == 0) actually advances; the rest sit at 0 until promoted.
func job_progress(i: int) -> float:
	var total: int = training_queue[i][JOB_TOTAL]
	if total <= 0:
		return 0.0
	return clampf(1.0 - float(training_queue[i][JOB_REMAINING]) / float(total), 0.0, 1.0)

## Advance the queue by one tick. Returns true if a unit was completed and
## spawned this call. Called once per physics frame from the parent's
## _update_state.
func tick() -> bool:
	if training_queue.is_empty(): return false
	# Advance by the current build rate (1.0 normally, STRAINED_RATE while the
	# commander is over its vigor upkeep). The fractional accumulator turns a 0.5
	# rate into "advance one tick of progress every other frame" = half speed.
	_progress_accum += _build_rate()
	if _progress_accum < 1.0:
		return false
	_progress_accum -= 1.0
	training_queue[0][0] -= 1
	if training_queue[0][0] <= 0:
		var spec: Variant = training_queue.pop_front()
		_spawn_unit(spec[JOB_SCENE])
		return true
	return false

## Normal speed, halved while the owning commander is vigor-strained.
func _build_rate() -> float:
	var entity: Entity = get_parent() as Entity
	if entity != null and entity.commander != null and entity.commander.is_vigor_strained():
		return STRAINED_RATE
	return 1.0

## Update the train bar's visibility and fill scale. Called from _process.
## `parent_scale_x` is the entity's scale.x — needed so the fill bar's
## position offset matches how the structure is rendered. (This duplicates
## the math that used to live inline in Structure._process; folding it into
## a dedicated TrainBar component is on the followups list.)
func update_bar(parent_scale_x: float) -> void:
	if _train_bar == null: return
	_train_bar.visible = !training_queue.is_empty()
	if not _train_bar.visible: return
	var fill: Node3D = _train_bar.get_node_or_null("TrainBarFill") as Node3D
	if fill == null: return
	# Fraction of training time remaining (bar shrinks toward completion), now
	# sourced from the job's own total tick count rather than a magic constant.
	var total: int = training_queue[0][JOB_TOTAL]
	fill.scale.x = float(training_queue[0][JOB_REMAINING]) / float(maxi(1, total))
	fill.position.x = -parent_scale_x * (1 - fill.scale.x)
#endregion

#region Private helpers
func _spawn_unit(scene: PackedScene) -> void:
	var entity: Entity = get_parent() as Entity
	if entity == null: return
	var owner_cmd: Commandable = entity as Commandable
	var rally: MoveCommand = owner_cmd.rally_destination() if owner_cmd != null else null
	var unit: Commandable = scene.instantiate() as Commandable
	var spawn_bias: Vector3 = (
		(rally.message.position - entity.global_position).normalized()
		if rally != null
		else Vector3.ZERO
	)
	unit.initialize(entity.map, entity.commander)
	unit.global_position = NavigationServer3D.map_get_closest_point(
		entity.get_world_3d().navigation_map,
		entity.global_position + spawn_bias
	)
	unit.update_commands(rally)
#endregion
