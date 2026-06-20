class_name ScenarioTriggerManager
extends Node

## Owns the scenario's GlobalTriggers (its GlobalTrigger child nodes) and the ConditionPoller
## that drives pull conditions. Add this as a direct child of the Scenario node, then add
## GlobalTrigger child nodes, each with its conditions and its own inline child AbstractEvents.
##
## It's the hub for the unified event model: both GlobalTriggers (source=null) and
## per-entity EntityTriggers (source=the entity) run their own inline child AbstractEvents
## via run_event(). Entities also report their lifecycle occurrences here
## (report_entity_occurrence → entity_occurrence signal) so cumulative conditions like
## ConditionOccurrenceTally ("N units have died") can accumulate them.

#region Signals
## Emitted when an EventShowMessage fires. Connect to HUD to display it.
signal message_requested(text: String)
## Emitted when an EventWinLose fires. won=true → player wins, false → loses.
signal game_over(won: bool)
## Re-broadcasts every entity lifecycle occurrence (death, damage, …) reported by
## entities via report_entity_occurrence(). The central bus that signal-accumulating
## conditions (ConditionOccurrenceTally) subscribe to.
signal entity_occurrence(occurrence: Entity.EntityOccurrence, source: Entity)
#endregion

#region Properties
## Populated in _ready() from the GlobalTrigger child nodes, in scene-tree order.
var global_triggers: Array[GlobalTrigger] = []

## Drives pull-based conditions each physics frame; created in _ready(). Push conditions
## ride signal buses (e.g. entity_occurrence) and never register here.
var condition_poller: ConditionPoller

var scenario: Scenario
var map: Map

var _fog: Node  # fog.gd MeshInstance3D; cached on first get_fog() call

## The entity whose EntityTrigger is currently running its event, or null for a
## GlobalTrigger (whose events are independent of any entity). Available to events via
## the manager while they execute; saved/restored around nested events.
var reaction_source: Entity = null
#endregion

#region Lifecycle
func _ready() -> void:
	var parent := get_parent()
	if parent is Scenario:
		scenario = parent as Scenario
		# Resolve the Map node directly rather than through Scenario's @onready
		# `map` property: a child's _ready() runs before its parent's, so the
		# parent's @onready vars aren't initialized yet at this point. The Map
		# node itself is already in the tree, so get_node finds it.
		map = scenario.get_node_or_null("Map") as Map
	else:
		push_warning("ScenarioTriggerManager: expected parent to be Scenario, got %s" % parent)

	for child in get_children():
		if child is GlobalTrigger:
			global_triggers.append(child)

	# Drives pull conditions; must exist before any trigger arms (arm() may register
	# pull conditions with it). Push conditions ride buses and ignore it.
	condition_poller = ConditionPoller.new()
	condition_poller.name = "ConditionPoller"
	condition_poller.manager = self
	add_child(condition_poller)

	# Arm triggers only once the navigation map has finished its first synchronization.
	# Events that query the nav map (EventSpawnEntities → Map.add_entities →
	# SU.get_nonoverlapping_points, EventCommandPoint → map_get_closest_point) fail if
	# they run before then ("navigation map query failed because it was made before
	# first map synchronization"), which silently drops frame-0 spawns. Gating here
	# means a trigger can safely fire at t=0 without any artificial timer delay.
	_arm_triggers_when_navmesh_ready()


## Wait for the navmesh to be built and synced, then arm every enabled trigger. NavManager
## builds the mesh via call_deferred and the NavigationServer syncs it on a later step, so
## the map isn't queryable during _ready — it announces readiness via NavManager.navmesh_ready
## (which also force-syncs the first build). Until then, spawn/path events would silently fail.
func _arm_triggers_when_navmesh_ready() -> void:
	if map != null and map.nav_manager != null and not map.nav_manager.is_ready():
		await map.nav_manager.navmesh_ready
	_arm_triggers()


## Arm each enabled trigger so it watches its conditions reactively. There is no
## per-tick polling of triggers any more — a trigger fires when a condition reports a
## change (Condition.state_changed) and the aggregate crosses into satisfied.
func _arm_triggers() -> void:
	for e: GlobalTrigger in global_triggers:
		e.enabled = not e.starts_disabled
		if e.enabled:
			e.arm(self)
#endregion

#region Public API
## Number of GlobalTriggers still active (enabled) — i.e. waiting to fire or able to
## re-fire. A one-shot event drops out of this count once it fires and disables
## itself. Used by ConditionNoPendingTriggers to detect "this is the last event."
func active_global_trigger_count() -> int:
	return global_triggers.filter(func(e: GlobalTrigger) -> bool: return e.enabled).size()


## Re-broadcast an entity lifecycle occurrence onto the manager's entity_occurrence bus.
## Called by Entity._fire_entity_occurrence so signal-accumulating conditions can tally.
func report_entity_occurrence(occurrence: Entity.EntityOccurrence, source: Entity) -> void:
	entity_occurrence.emit(occurrence, source)


## Return the Commander with the given id, or null.
func get_commander(id: int) -> Commander:
	if scenario == null:
		return null
	for c: Commander in scenario.commanders:
		if c.id == id:
			return c
	return null


## Return the Fog node (the one running fog.gd), or null if none exists.
## The Fog node lives in the player Commander's subtree (scenes/player.tscn).
func get_fog() -> Node:
	if _fog != null and is_instance_valid(_fog):
		return _fog
	_fog = get_tree().current_scene.find_child("Fog", true, false)
	return _fog
#endregion

#region Event execution
## Run an AbstractEvent that is already in the tree and positioned: execute it, then
## recurse into its child AbstractEvents (nested / container events, e.g. victory.tscn's
## message + win children). Non-event children — an event's own config nodes such as
## EventCommand — are left alone; entities reach the world via EventSpawnEntities, never
## realized directly. `source` is the entity an EntityTrigger fired on (null for a
## GlobalTrigger), exposed to events through reaction_source for the duration of the run.
func run_event(event: AbstractEvent, source: Entity = null) -> void:
	var prev_source := reaction_source
	reaction_source = source
	event.execute(self)
	for child in event.get_children():
		if child is AbstractEvent:
			run_event(child as AbstractEvent, source)
	reaction_source = prev_source
#endregion
