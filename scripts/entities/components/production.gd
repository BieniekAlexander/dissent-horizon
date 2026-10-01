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

## A structure builds ONE unit at a time. There is no per-structure queue: units waiting
## to be built wait in the commander's global ProductionQueue, where they can be seen,
## reordered and cancelled, and are handed to whichever eligible structure frees up first.
## Two producers of the same thing can therefore share a burden, which per-structure
## queues made impossible — that was the leftover contradiction with purchases being
## commander-global.
##
## `training_queue` is still an ARRAY, holding at most one job: the HUD, the rally
## indicator and the cancel path all address a job by index, and keeping that shape means
## the one-at-a-time rule is enforced in exactly one place (enqueue, via is_free) rather
## than spread across every reader. Nothing may push a second entry.
##
## Each entry is [remaining_ticks, total_ticks, scene, type, commands, transaction] — see
## the JOB_* indices. total_ticks is kept so the HUD/train bar can show real progress; type
## is kept so a cancelled job can refund its cost (see cancel()); commands is the PRE-ISSUED
## order chain the finished unit inherits, snapshotted from this structure's rally when the
## purchase was submitted (see PurchaseTransaction) rather than read live at spawn — so a
## unit carries out the rally that was standing when it was ORDERED, not whatever the
## structure's rally happens to be minutes later when it pops. An empty chain falls back
## to the structure's current rally (the path taken by scenario events and tests, which
## enqueue directly). transaction is the purchase this job is fulfilling, carried so the
## unit's appearance can be reported back through it (see _spawn_unit); it is null for the
## same direct-enqueue callers.
const JOB_REMAINING: int = 0
const JOB_TOTAL: int = 1
const JOB_SCENE: int = 2
const JOB_TYPE: int = 3
const JOB_COMMANDS: int = 4
const JOB_TRANSACTION: int = 5
var training_queue: Array = []

## Build-rate fraction applied while the owning commander is infrastructure-strained (upkeep
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
## Start a training job. Called by the commander's ProductionQueue when a purchase is
## dispatched here (cost confirmed and deducted). `unit_type` is stored so cancel() can
## refund the job's cost; it's optional for callers/tests that don't need refunds.
## `commands` is the pre-issued order chain the finished unit inherits — omit it to have
## the unit take this structure's rally as it stands when the unit appears. `transaction`
## is the purchase being fulfilled, and is what makes the finished unit's appearance an
## observable event on that purchase.
##
## Returns false, changing nothing, when this structure is already building something: one
## unit at a time is the rule, and the global queue holds the rest. The dispatcher asks
## is_free() first, so a refusal here means a caller went around it.
func enqueue(
	a_creation_time: int,
	a_packed_scene: PackedScene,
	a_unit_type: Variant = null,
	a_commands: Array = [],
	a_transaction: PurchaseTransaction = null
) -> bool:
	if not is_free():
		return false
	training_queue.push_back(
		[a_creation_time, a_creation_time, a_packed_scene, a_unit_type, a_commands, a_transaction]
	)
	return true

## Whether this producer can take a job right now — nothing is being built here.
func is_free() -> bool:
	return training_queue.is_empty()

## Whether this producer can train the given unit type. Source of truth for the
## "what can this build" question across the codebase (HUD train menu, AI).
func can_produce(a_type: StringName) -> bool:
	return producible_types.has(a_type)

## Whether anything this producer makes is a UNIT, as opposed to only researching upgrades.
## Ask this, not `production != null`, wherever the question is "does this train units": the
## rally point, the idle-producer hotkey, the bot's throughput buildings and a placement's need
## for a walkable side. A research-only structure (the Operations Center) has a Production
## component only because research runs as a job in the same queue.
##
## Only a RESEARCH-ONLY list says no. An empty one still reads as a producer, as every
## Production did before upgrades existed: a producer whose trainees are not authored yet.
func trains_units() -> bool:
	return producible_types.is_empty() \
		or producible_types.any(func(t: StringName) -> bool: return not UpgradeCatalog.is_upgrade(t))


## trains_units for any node that may carry a Production child: a live piece or an
## out-of-tree preview, whose @onready never resolved.
static func node_trains_units(a_node: Node) -> bool:
	var production: Production = a_node.get_node_or_null("Production") as Production \
		if a_node != null else null
	return production != null and production.trains_units()


## Whether the job running here is `a_type`. Read by Commander.is_research_taken, so an upgrade
## already being researched cannot be ordered again.
func is_producing(a_type: StringName) -> bool:
	return not training_queue.is_empty() and training_queue[0][JOB_TYPE] == a_type

## Number of units queued (the first is actively training; the rest wait).
func job_count() -> int:
	return training_queue.size()

## The unit scene for queued job `i`.
func job_scene(a_i: int) -> PackedScene:
	return training_queue[a_i][JOB_SCENE] as PackedScene

## The Entity.Type for queued job `i` (used to refund cost on cancel). May be null
## if the job was enqueued without a type.
func job_type(a_i: int) -> Variant:
	return training_queue[a_i][JOB_TYPE]

## The purchase job `a_i` came from, or null. The job is how a unit that is ALREADY BEING
## BUILT is reached — it has left the production queue, so its transaction is no longer in
## `ProductionQueue.entries` and the rail cannot show it. Read by the info panel so its job
## cards can select the unit that is coming (see PurchaseTransaction.awaits_its_unit).
func job_transaction(a_i: int) -> PurchaseTransaction:
	if a_i < 0 or a_i >= training_queue.size():
		return null
	return training_queue[a_i][JOB_TRANSACTION] as PurchaseTransaction


## The pre-issued order chain queued job `i` will hand its unit at spawn (see JOB_COMMANDS
## above). May be empty — that's not "no orders", it's "follow the structure's rally as it
## stands at spawn time"; a reader wanting the ORDERS THIS UNIT WILL ACTUALLY GET must fall
## back to the owning entity's rally_commands the same way _spawn_unit does.
func job_commands(a_i: int) -> Array:
	return training_queue[a_i][JOB_COMMANDS] as Array

## Cancel the queued job at `index`: remove it from the queue and refund its cost to
## the owning commander. A no-op (returns false) for an out-of-range index. Cancelling
## any job refunds the full cost — including the head job that's partway trained.
func cancel(a_index: int) -> bool:
	if a_index < 0 or a_index >= training_queue.size():
		return false
	var unit_type: Variant = training_queue[a_index][JOB_TYPE]
	# The purchase this job came from is CONSUMED, so it is past refunding itself; the
	# refund below is the one that applies. Marking it cancelled is what stops anything
	# still holding it from believing a unit is on the way.
	var transaction: PurchaseTransaction = training_queue[a_index][JOB_TRANSACTION] as PurchaseTransaction
	if transaction != null:
		transaction.state = PurchaseTransaction.State.CANCELLED
	training_queue.remove_at(a_index)
	# Removing the head job promotes the next one (its remaining is still full), so
	# clear the sub-tick accumulator to avoid leaking partial progress into it.
	if a_index == 0:
		_progress_accum = 0.0
	var entity: Entity = get_parent() as Entity
	if entity != null and entity.commander != null and unit_type != null:
		entity.commander.refund_resources_for(unit_type)
	return true

## Ticks of work left here — the active job's remaining ticks, or 0 when free. Still a sum
## because the job list is still an array (see training_queue), and correct either way.
## Deliberately ignores the infrastructure-strain rate, which applies to all of one commander's
## producers equally and so can't change their relative order.
func remaining_ticks() -> int:
	var total: int = 0
	for job: Array in training_queue:
		total += job[JOB_REMAINING] as int
	return total

## Training progress (0..1) of queued job `i`: 0 when just enqueued, 1 when done.
## Only the head job (i == 0) actually advances; the rest sit at 0 until promoted.
func job_progress(a_i: int) -> float:
	var total: int = training_queue[a_i][JOB_TOTAL]
	if total <= 0:
		return 0.0
	return clampf(1.0 - float(training_queue[a_i][JOB_REMAINING]) / float(total), 0.0, 1.0)

## Advance the queue by one tick. Returns true if a unit was completed and
## spawned this call. Called once per physics frame from the parent's
## _update_state.
func tick() -> bool:
	if training_queue.is_empty(): return false
	# Advance by the current build rate (1.0 normally, STRAINED_RATE while the
	# commander is over its infrastructure upkeep). The fractional accumulator turns a 0.5
	# rate into "advance one tick of progress every other frame" = half speed.
	_progress_accum += _build_rate()
	if _progress_accum < 1.0:
		return false
	_progress_accum -= 1.0
	training_queue[0][0] -= 1
	if training_queue[0][0] <= 0:
		var spec: Variant = training_queue.pop_front()
		if UpgradeCatalog.is_upgrade(spec[JOB_TYPE]):
			_complete_research(StringName(str(spec[JOB_TYPE])),
				spec[JOB_TRANSACTION] as PurchaseTransaction)
			return true
		_spawn_unit(
			spec[JOB_SCENE],
			spec[JOB_COMMANDS],
			spec[JOB_TRANSACTION] as PurchaseTransaction
		)
		return true
	return false

## Normal speed, halved while the owning commander is infrastructure-strained.
func _build_rate() -> float:
	var entity: Entity = get_parent() as Entity
	if entity != null and entity.commander != null and entity.commander.is_infrastructure_strained():
		return STRAINED_RATE
	return 1.0

## Update the train bar's visibility and fill scale. Called from _process.
## `parent_scale_x` is the entity's scale.x — needed so the fill bar's
## position offset matches how the structure is rendered. (This duplicates
## the math that used to live inline in Structure._process; folding it into
## a dedicated TrainBar component is on the followups list.)
func update_bar(a_parent_scale_x: float) -> void:
	if _train_bar == null: return
	_train_bar.visible = !training_queue.is_empty()
	if not _train_bar.visible: return
	var fill: Node3D = _train_bar.get_node_or_null("TrainBarFill") as Node3D
	if fill == null: return
	# Fraction of training time remaining (bar shrinks toward completion), now
	# sourced from the job's own total tick count rather than a magic constant.
	var total: int = training_queue[0][JOB_TOTAL]
	fill.scale.x = float(training_queue[0][JOB_REMAINING]) / float(maxi(1, total))
	fill.position.x = -a_parent_scale_x * (1 - fill.scale.x)
#endregion

#region Private helpers
## Spawn the finished unit and hand it its orders.
##
## TWO SOURCES, and this is where the precedence between them is applied. [a_commands] is
## whatever the PLAYER aimed at this specific purchase — empty for almost every unit — and an
## empty one falls through to the structure's rally **as it stands at this moment**. So a
## rally re-aimed while five units are queued sends all five to the new point, and only a
## unit the player singled out ignores it.
##
## That fall-through IS the rally mechanism; nothing is captured at submission any more.
## Why: gdd/systems/commands/construction.md §The rally is read at SPAWN.
##
## Either way the unit receives its OWN copies (see MoveCommand.duplicated), so several units
## off one rally never share command instances.
##
## This is the SINGLE FULFILMENT CHOKE POINT for a trained unit: `transaction.complete` below
## is the one place "the unit this purchase bought now exists" is announced.
func _spawn_unit(
	a_scene: PackedScene,
	a_commands: Array = [],
	a_transaction: PurchaseTransaction = null
) -> void:
	var entity: Entity = get_parent() as Entity
	if entity == null: return
	var owner_cmd: Commandable = entity as Commandable
	# READ AT SPAWN, not at dispatch: the player can select a unit that is already being built
	# and order it, so the transaction's orders are asked for HERE rather than trusted from the
	# copy taken when the job was enqueued. Same reason the rally is read here — see the note
	# above. [a_commands] is what the job was given, and remains the fallback.
	var orders: Array = a_transaction.player_commands \
		if a_transaction != null and not a_transaction.player_commands.is_empty() else a_commands
	var chain: Array[MoveCommand] = []
	for command: MoveCommand in orders:
		chain.append(command.duplicated())
	if chain.is_empty() and owner_cmd != null:
		chain = owner_cmd.rally_chain()
	var unit: Commandable = a_scene.instantiate() as Commandable
	# Bias the spawn toward the FIRST leg of the chain, so units emerge on the side they're
	# heading for rather than walking back around the building.
	var spawn_bias: Vector3 = (
		(chain[0].message.position - entity.global_position).normalized()
		if not chain.is_empty()
		else Vector3.ZERO
	)
	unit.initialize(entity.map, entity.commander)
	# An aircraft that rearms at this very airfield ROLLS OUT ONTO A PAD rather than
	# materialising in the air over it: the airfield is where it lives, and a new one
	# hanging in the sky above its own hangar reads as a spawn rather than a delivery.
	# Everything else goes to the nearest navigable ground, as before.
	if not _spawn_on_pad(owner_cmd, unit):
		unit.global_position = NavigationServer3D.map_get_closest_point(
			entity.get_world_3d().navigation_map,
			entity.global_position + spawn_bias
		)
	unit.update_commands(chain if not chain.is_empty() else null)
	if a_transaction != null:
		a_transaction.complete(unit)


## A finished RESEARCH job: nothing appears, the commander simply owns the upgrade. The
## transaction completes with no product, which is what its `fulfilled` signal allows.
## Why: gdd/systems/macroeconomics/upgrades.md.
func _complete_research(a_id: StringName, a_transaction: PurchaseTransaction) -> void:
	var entity: Entity = get_parent() as Entity
	if entity != null and entity.commander != null:
		entity.commander.complete_upgrade(a_id)
	if a_transaction != null:
		a_transaction.complete(null)


## Park `unit` on one of this structure's free docking pads, returning true when it did.
##
## Only for an aircraft the bay would ADMIT — the same test a returning one passes — so a
## transport or a ground unit built at the same airfield is untouched. False whenever there
## is no bay, the unit does not belong on it, or every pad is taken, and the caller falls
## back to the ordinary ground spawn.
##
## The unit is left GROUNDED on the deck, not airborne over it. It lifts off the moment
## something asks it to move (CommandReceiver takes a docked unit off the pad before
## driving it), so a rally chain still gets obeyed — it just gets obeyed by taxiing out and
## taking off, which is what an aircraft leaving an airfield does.
func _spawn_on_pad(a_structure: Commandable, a_unit: Commandable) -> bool:
	if a_structure == null:
		return false
	var bay: DockingBay = a_structure.get_node_or_null("DockingBay") as DockingBay
	if bay == null or not bay.admits(a_unit):
		return false
	var pad: DockingPad = bay.reserve(a_unit)
	if pad == null:
		return false
	var spot: Vector3 = pad.dock_position()
	if a_structure.map != null:
		spot.y = a_structure.map.terrain_height_at(VU.inXZ(spot))
	a_unit.global_position = spot
	a_unit.aerial.park_on_deck(pad.deck_height)
	a_unit.docking.docked_pad = pad
	return true
#endregion
