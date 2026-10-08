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
## Emitted when an EventShowDialog fires: a pop-up the player must acknowledge.
## ScenarioDialogView draws it; the dialog itself carries the acknowledgement.
signal dialog_requested(dialog: ScenarioDialog)
## Emitted when an EventWinLose fires. won=true → player wins, false → loses.
signal game_over(won: bool)
## Emitted whenever any objective trigger changes state. The cue for the objective HUD to
## repaint; carries nothing because the checklist is rebuilt from objective_triggers().
signal objectives_changed
## Emitted once, the moment every PRIMARY trigger in the scene has fired. A scenario with no
## primary objectives never emits this — "zero of zero done" is not a finished mission.
signal scenario_completed
## Re-broadcasts every entity lifecycle occurrence (death, damage, …) reported by
## entities via report_entity_occurrence(). The central bus that signal-accumulating
## conditions (ConditionOccurrenceTally) subscribe to.
signal entity_occurrence(occurrence: Entity.EntityOccurrence, source: Entity)
#endregion

#region Properties
## Populated in _ready() from the GlobalTrigger child nodes, in scene-tree order. Also
## includes the triggers found inside ObjectiveChain children — a chain step is an ordinary
## trigger that merely happens to be gated, and the arming machinery treats it as one.
var global_triggers: Array[GlobalTrigger] = []

## Populated in _ready() from the ObjectiveChain child nodes, in scene-tree order. Each
## sequences its own steps.
var objective_chains: Array[ObjectiveChain] = []

## Populated in _ready() from the ScenarioTactic child nodes, in scene-tree order. Armed
## alongside the triggers, once the navmesh is ready — see _arm_scenario_tactics().
var scenario_tactics: Array[ScenarioTactic] = []

## Latches once scenario_completed has been emitted, so it announces exactly once even
## though a repeating objective can fire again afterwards.
var _completion_announced: bool = false

## Drives pull-based conditions each physics frame; created in _ready(). Push conditions
## ride signal buses (e.g. entity_occurrence) and never register here.
var condition_poller: ConditionPoller

## Owns "is the world simulating"; created in _ready(). Events that need the player to stop
## and act (EventShowDialog) take a hold on it. See SimulationClock.
var simulation_clock: SimulationClock

var scenario: Scenario
var map: Map

var _fog: Node  # fog.gd MeshInstance3D; cached on first get_fog() call

## The entity whose EntityTrigger is currently running its event, or null for a
## GlobalTrigger (whose events are independent of any entity). Available to events via
## the manager while they execute; saved/restored around nested events.
var reaction_source: Entity = null

## Every dialog raised and not yet resolved, by serial — how a recorded acknowledgement finds its
## dialog. Entries leave as their dialog is acknowledged.
var _open_dialogs: Dictionary = {}
var _next_dialog_serial: int = 1
#endregion


#region Lifecycle
func _ready() -> void:
	# Conditions must keep being evaluated while a SimulationClock hold freezes the world:
	# that is how a paused tutorial beat notices the player did the thing it was waiting for
	# and resumes. Everything under this node inherits it — the ConditionPoller, and the
	# trigger/event marker nodes (which have no per-frame work anyway).
	process_mode = Node.PROCESS_MODE_ALWAYS

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
		elif child is ObjectiveChain:
			# A chain's steps are triggers too; collecting them here is what puts them on the
			# normal arming path. The chain's own _ready has already run (children ready before
			# parents), so the dependency edges it adds are already in place.
			var chain := child as ObjectiveChain
			objective_chains.append(chain)
			global_triggers.append_array(chain.steps)
		elif child is ScenarioTactic:
			scenario_tactics.append(child)

	# Watch every trigger's objective state, so the HUD repaints and completion is re-checked
	# without anything polling. Connected for all of them rather than only the player-facing
	# ones, because `scope` can legitimately be changed at runtime.
	for trigger: GlobalTrigger in global_triggers:
		trigger.objective_state_changed.connect(_on_objective_state_changed)
		# A trigger firing can satisfy someone else's prerequisites, which is what advances the
		# objective DAG.
		trigger.fired.connect(_arm_satisfied_triggers)

	# Conditions are Resources shared with the PREVIOUS run of this scenario, so clear their
	# state before anything reads it.
	_reset_session_conditions()

	# Nothing else would notice a dependency loop: the triggers in it simply never arm, and
	# the scenario stalls with no error.
	_report_prerequisite_cycles()

	# Drives pull conditions; must exist before any trigger arms (arm() may register
	# pull conditions with it). Push conditions ride buses and ignore it.
	condition_poller = ConditionPoller.new()
	condition_poller.name = "ConditionPoller"
	condition_poller.manager = self
	add_child(condition_poller)

	# Owns simulation pause. Created here (not by Scenario) so every session has one —
	# including test scenarios and any scene that builds its own manager.
	simulation_clock = SimulationClock.new()
	simulation_clock.name = "SimulationClock"
	add_child(simulation_clock)

	# Arm triggers only once the navigation map has finished its first synchronization.
	# Events that query the nav map (EventSpawnEntities → Map.add_entities →
	# SU.get_nonoverlapping_points, EventCommandPoint → map_get_closest_point) fail if
	# they run before then ("navigation map query failed because it was made before
	# first map synchronization"), which silently drops frame-0 spawns. Gating here
	# means a trigger can safely fire at t=0 without any artificial timer delay.
	_arm_triggers_when_navmesh_ready()


## Clear every authored Condition's runtime state, once, at the start of this session.
##
## Why it works this way: gdd/systems/scenario-scripting/conditions-and-regions.md §Resetting
## conditions between sessions.
func _reset_session_conditions() -> void:
	for trigger: GlobalTrigger in global_triggers:
		trigger.reset_conditions()
	for tactic: ScenarioTactic in scenario_tactics:
		tactic.reset_conditions()


## Wait for the navmesh to be built and synced, then arm every enabled trigger. NavManager
## builds the mesh via call_deferred and the NavigationServer syncs it on a later step, so
## the map isn't queryable during _ready — it announces readiness via NavManager.navmesh_ready
## (which also force-syncs the first build). Until then, spawn/path events would silently fail.
func _arm_triggers_when_navmesh_ready() -> void:
	if map != null and map.nav_manager != null and not map.nav_manager.is_ready():
		await map.nav_manager.navmesh_ready
	run_starting_events()
	_arm_triggers()
	_arm_scenario_tactics()


## Arm every ScenarioTactic so its rules' conditions are live — same timing as the triggers,
## since a rule's EventCommand children query the navmesh exactly like an EventCommandPoint
## does.
func _arm_scenario_tactics() -> void:
	for tactic: ScenarioTactic in scenario_tactics:
		tactic.arm(self)


## Run every scene-authored STARTING event: an AbstractEvent placed as a DIRECT child of a
## commandable, executed once at scenario start with that commandable as its source.
##
## The third way an event runs, and the one for state that simply IS so from the first frame.
## Called AFTER the navmesh is ready and after editor-placed entities have auto-initialized,
## so each host already has its map and commander. The loop is deliberately UNTYPED — a stray
## non-Entity node in the group is skipped rather than aborting scenario boot.
## Where an event may be parked, and what each parking means:
## gdd/systems/scenario-scripting/triggers-and-events.md.
func run_starting_events() -> void:
	for node: Node in get_tree().get_nodes_in_group("piece"):
		var entity := node as Entity
		if entity == null:
			continue
		for child: Node in entity.get_children():
			if child is AbstractEvent:
				run_event(child as AbstractEvent, entity)


## Arm each enabled trigger so it watches its conditions reactively. There is no
## per-tick polling of triggers any more — a trigger fires when a condition reports a
## change (Condition.state_changed) and the aggregate crosses into satisfied.
func _arm_triggers() -> void:
	for e: GlobalTrigger in global_triggers:
		# One gate: a trigger is in the opening round unless something it depends on hasn't
		# happened yet.
		e.enabled = e.prerequisites_satisfied()
		if e.enabled:
			e.arm(self)


## Arm every trigger whose prerequisites have just become satisfied. Connected to each
## trigger's `fired`, so completing one step walks the DAG forward.
##
## Only triggers that actually declare prerequisites are considered, and that guard is doing
## real work: an ungated trigger switched OFF by an EventChainTrigger has nothing outstanding,
## so without it the next fire anywhere in the scenario would silently switch it back on.
func _arm_satisfied_triggers() -> void:
	for trigger: GlobalTrigger in global_triggers:
		if trigger.enabled or trigger.has_fired:
			continue
		if not trigger.has_prerequisites():
			continue
		if trigger.prerequisites_satisfied():
			trigger.set_active(true, self)


#endregion


#region Prerequisite validation
## Report any cycle in the prerequisite graph, naming the loop.
##
## A cycle isn't a crash, it's a silence: every trigger in it waits for another member to
## fire first, so none of them ever arms and the mission just stops with nothing in the log.
## Depth-first with a three-state mark — unvisited / on the current path / finished — where
## reaching a node that is still on the path IS the cycle.
func _report_prerequisite_cycles() -> void:
	var marks: Dictionary = {}
	for trigger: GlobalTrigger in global_triggers:
		_walk_prerequisites(trigger, marks, [])


func _walk_prerequisites(a_trigger: GlobalTrigger, a_marks: Dictionary, a_path: Array) -> void:
	if a_trigger == null:
		return
	var mark: int = int(a_marks.get(a_trigger, 0))
	if mark == 2:  # already cleared on an earlier walk
		return
	if mark == 1:  # still on the current path — we have come back around
		var start: int = a_path.find(a_trigger)
		var loop: Array = a_path.slice(start) if start >= 0 else [a_trigger]
		var names: Array = loop.map(func(t: GlobalTrigger) -> String: return String(t.name))
		names.append(String(a_trigger.name))
		push_error(
			(
				(
					"ScenarioTriggerManager: prerequisite cycle %s — every trigger in it waits on "
					% " -> ".join(names)
				)
				+ "another, so none of them will ever arm."
			)
		)
		return
	a_marks[a_trigger] = 1
	a_path.append(a_trigger)
	for prerequisite: GlobalTrigger in a_trigger.prerequisites:
		_walk_prerequisites(prerequisite, a_marks, a_path)
	a_path.pop_back()
	a_marks[a_trigger] = 2


#endregion


#region Public API
## Number of GlobalTriggers still active (enabled) — i.e. waiting to fire or able to
## re-fire. A one-shot event drops out of this count once it fires and disables
## itself. Used by ConditionNoPendingTriggers to detect "this is the last event."
func active_global_trigger_count() -> int:
	return global_triggers.filter(func(e: GlobalTrigger) -> bool: return e.enabled).size()


## Re-broadcast an entity lifecycle occurrence onto the manager's entity_occurrence bus.
## Called by Entity._fire_entity_occurrence so signal-accumulating conditions can tally.
func report_entity_occurrence(a_occurrence: Entity.EntityOccurrence, a_source: Entity) -> void:
	entity_occurrence.emit(a_occurrence, a_source)


## Return the Commander with the given id, or null.
func get_commander(a_id: int) -> Commander:
	if scenario == null:
		return null
	for c: Commander in scenario.commanders:
		if c.id == a_id:
			return c
	return null


## The order the checklist reads in: what can END the mission first, then what must be done,
## then what is optional. Deliberately not scene-tree order — a failure condition the player
## scrolls past is one they don't know about.
const SCOPE_DISPLAY_ORDER: Array[GlobalTrigger.ObjectiveScope] = [
	GlobalTrigger.ObjectiveScope.FAILURE,
	GlobalTrigger.ObjectiveScope.PRIMARY,
	GlobalTrigger.ObjectiveScope.SECONDARY,
]


## Every player-facing trigger (any `scope` but NONE), in scene-tree order. Chain steps appear
## inline at their chain's position, so authored order is the order WITHIN a scope group; see
## visible_objective_triggers() for the grouping the HUD actually draws.
func objective_triggers() -> Array[GlobalTrigger]:
	return global_triggers.filter(func(t: GlobalTrigger) -> bool: return t.is_player_facing())


## The player-facing triggers in a single scope, in scene-tree order.
func triggers_in_scope(a_scope: GlobalTrigger.ObjectiveScope) -> Array[GlobalTrigger]:
	return global_triggers.filter(func(t: GlobalTrigger) -> bool: return t.scope == a_scope)


## What the checklist shows, top to bottom: grouped by SCOPE_DISPLAY_ORDER and in authored
## order within each group, minus the ones still PENDING — those are hidden so an unrevealed
## step doesn't spoil what's coming.
##
## The grouping lives here rather than in ObjectiveView so the view's two readers (rows() and
## refresh()) can't disagree about the order, and so a test can assert it without a HUD.
func visible_objective_triggers() -> Array[GlobalTrigger]:
	var result: Array[GlobalTrigger] = []
	var is_revealed := func(t: GlobalTrigger) -> bool:
		return t.objective_state() != GlobalTrigger.ObjectiveState.PENDING
	for scope: GlobalTrigger.ObjectiveScope in SCOPE_DISPLAY_ORDER:
		result.append_array(triggers_in_scope(scope).filter(is_revealed))
	return result


## True once every PRIMARY trigger has fired. SECONDARY is optional by definition and FAILURE
## is a way to lose, so neither is a box that has to be ticked — see
## GlobalTrigger.counts_toward_completion(). A scenario that declares NO primary objectives is
## never "complete": an empty set would otherwise pass vacuously and finish every skirmish on
## frame one.
func all_objectives_complete() -> bool:
	var objectives: Array[GlobalTrigger] = global_triggers.filter(
		func(t: GlobalTrigger) -> bool: return t.counts_toward_completion()
	)
	return (
		not objectives.is_empty()
		and objectives.all(func(t: GlobalTrigger) -> bool: return t.has_fired)
	)


## Repaint the HUD, and announce completion the first time every objective is done.
func _on_objective_state_changed(_a_trigger: GlobalTrigger) -> void:
	objectives_changed.emit()
	if _completion_announced or not all_objectives_complete():
		return
	_completion_announced = true
	scenario_completed.emit()


## Where a ScenarioHighlight's world markers should be parented. The Map, so marker
## coordinates are world coordinates (the same place WaypointIndicators live); this node
## itself when there is no Map, which keeps headless tests working.
func highlight_parent() -> Node:
	return map if map != null else self


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
## Put `a_dialog` up: number it, keep it findable until it is resolved, and hand it to whoever
## draws dialogs (dialog_requested).
func raise_dialog(a_dialog: ScenarioDialog) -> void:
	a_dialog.serial = _next_dialog_serial
	_next_dialog_serial += 1
	_open_dialogs[a_dialog.serial] = a_dialog
	var serial: int = a_dialog.serial
	a_dialog.acknowledged.connect(func() -> void: _open_dialogs.erase(serial))
	dialog_requested.emit(a_dialog)


## The open dialog numbered `a_serial`, or null once it is resolved.
func dialog_by_serial(a_serial: int) -> ScenarioDialog:
	return _open_dialogs.get(a_serial)


func run_event(a_event: AbstractEvent, a_source: Entity = null) -> void:
	var prev_source := reaction_source
	reaction_source = a_source
	a_event.execute(self)
	for child in a_event.get_children():
		if child is AbstractEvent:
			run_event(child as AbstractEvent, a_source)
	reaction_source = prev_source
#endregion
