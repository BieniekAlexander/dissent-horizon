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
@export var producible_types: Array[Entity.Type] = []

## Each entry: [time_remaining_in_ticks: int, packed_scene: PackedScene].
var training_queue: Array = []

## The most recent rally command; trained units inherit this as their first
## command (so newly-spawned units walk toward the rally point).
var rally_command: Command = null

var _train_bar: Node3D
#endregion

#region Lifecycle
func _ready() -> void:
	if not train_bar_path.is_empty():
		_train_bar = get_node_or_null(train_bar_path) as Node3D
#endregion

#region Public API
## Enqueue a new training job. Called by Structure when a Train command is
## accepted (resources confirmed and deducted).
func enqueue(creation_time: int, packed_scene: PackedScene) -> void:
	training_queue.push_back([creation_time, packed_scene])

func set_rally(command: Command) -> void:
	rally_command = command

## Whether this producer can train the given unit type. Source of truth for the
## "what can this build" question across the codebase (HUD train menu, AI).
func can_produce(a_type: Entity.Type) -> bool:
	return producible_types.has(a_type)

## Advance the queue by one tick. Returns true if a unit was completed and
## spawned this call. Called once per physics frame from the parent's
## _update_state.
func tick() -> bool:
	if training_queue.is_empty(): return false
	training_queue[0][0] -= 1
	if training_queue[0][0] <= 0:
		var spec: Variant = training_queue.pop_front()
		_spawn_unit(spec[1])
		return true
	return false

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
	# 450 is the same magic number the previous inline code used; flagged as
	# a hardcode there too. A future cleanup should source this from the
	# job spec.
	fill.scale.x = float(training_queue[0][0]) / 450
	fill.position.x = -parent_scale_x * (1 - fill.scale.x)
#endregion

#region Private helpers
func _spawn_unit(scene: PackedScene) -> void:
	var entity: Entity = get_parent() as Entity
	if entity == null: return
	var unit: Commandable = scene.instantiate() as Commandable
	var spawn_bias: Vector3 = (
		(rally_command.message.position - entity.global_position).normalized()
		if rally_command != null
		else Vector3.ZERO
	)
	unit.initialize(entity.map, entity.commander)
	unit.global_position = NavigationServer3D.map_get_closest_point(
		entity.get_world_3d().navigation_map,
		entity.global_position + spawn_bias
	)
	unit.update_commands(rally_command)
#endregion
