@tool
class_name GlobalTrigger
extends EditorMarkerSprite3D

## A scenario-wide ("global") Trigger: it owns a set of Conditions and, as inline child
## nodes, the AbstractEvents it runs when they're met. Extends EditorMarkerSprite3D (a
## Node3D) so the whole trigger shows a clickable, draggable marker in the editor and can be
## moved together with its child events (spawn anchors, command points, region shapes); the
## marker is hidden at runtime and the trigger holds no meaningful transform of its own
## (authored at identity, so child event world positions are unchanged).
##
## nodes, the AbstractEvents it runs when they're met. Rather than being polled, it ARMS
## its conditions (arm()) and fires reactively when a condition reports a change
## (Condition.state_changed) and the AND/OR aggregate crosses into satisfied. Each
## condition picks its own driver — push conditions ride a bus, pull conditions are ticked
## by the manager's ConditionPoller — but the trigger doesn't care which.
##
## On fire it runs each child AbstractEvent in place via ScenarioTriggerManager.run_event.
## Because the events live in this scene, their authored world positions (e.g. an
## EventSpawnEntities node, an EventCommandPoint) are used directly — that's how you point
## a global trigger at a location in the game world.
##
## Add these as children of a ScenarioTriggerManager, each with its own child events.

#region Signals
## Emitted after this trigger's events have run. The hook an ObjectiveChain advances on,
## and how a HUD learns an objective is complete without polling `enabled`.
signal fired

## Emitted whenever objective_state() would return something new — the cue for the objective
## HUD to repaint, and for the manager to re-check whether the scenario is finished. Fires
## on every trigger, but only ones with a `scope` are worth listening to.
signal objective_state_changed(trigger: GlobalTrigger)
#endregion

#region Properties
enum ConditionMode {
	## All conditions must be true to fire.
	AND,
	## Any one condition being true fires.
	OR
}

## How a trigger's `prerequisites` combine into "am I allowed to arm yet".
enum PrerequisiteMode {
	## Every prerequisite must have fired.
	ALL_OF,
	## Any one prerequisite having fired is enough.
	ANY_OF
}

## How a trigger presents itself in the objective HUD. PURELY a display decision — nothing
## about arming, firing or chaining reads it, and the scenario's own win/lose wiring is
## authored with prerequisites and EventWinLose as before. The one exception is
## ScenarioTriggerManager.all_objectives_complete(), which counts PRIMARY.
enum ObjectiveScope {
	## Machinery: spawn waves, ambushes, chaining. Never shown. The default, because most
	## triggers are this and the player should never see them as a task.
	NONE,
	## A task the player must do, drawn green and struck through once fulfilled. The scope that
	## counts toward scenario completion.
	PRIMARY,
	## An optional task, drawn amber. Struck through when fulfilled like a PRIMARY, but does
	## not hold up completion.
	SECONDARY,
	## A way to LOSE — drawn red, and as a bullet rather than a checkbox, because there is
	## nothing here for the player to tick off. Firing one is the scenario's business (author
	## an EventWinLose under it); this only says how it reads.
	FAILURE,
}

## How a trigger reads to the player, derived from `enabled` + whether it has ever fired
## rather than tracked separately — there is no way for the two to disagree.
enum ObjectiveState {
	## Not started: disabled and never fired, so it is waiting on another trigger to reveal
	## it. Hidden from the checklist — listing it would spoil what's coming.
	PENDING,
	## Live: armed and watching its conditions. Shown unchecked.
	ACTIVE,
	## Fulfilled at least once. Shown crossed off.
	COMPLETE,
}

## What this trigger waits for. LEAVING IT EMPTY IS MEANINGFUL: a trigger with nothing to wait
## for fires as soon as it arms — the way to say "run these events unconditionally, at the
## start of the scenario". A conditionless trigger is always one-shot (see `one_shot`).
##
## Blank rows are ignored rather than treated as an unmeetable condition, as in
## prerequisites_satisfied() and for the same reason: an Array export grows an empty row
## whenever you extend it in the inspector. Note the corollary — a trigger whose only row is
## blank counts as conditionless and fires immediately.
@export var conditions: Array[Condition] = []
@export var condition_mode: ConditionMode = ConditionMode.AND

## How this trigger reads in the HUD checklist — see ObjectiveScope. NONE by default, so a
## trigger stays machinery unless someone deliberately makes it player-facing.
@export var scope: ObjectiveScope = ObjectiveScope.NONE

## The line shown in the objective checklist, e.g. "Move your scout to the ridge". Only read
## when `scope` is not NONE.
@export_multiline var description: String = ""

## When true the trigger disables itself after firing once.
##
## IGNORED (treated as true) on a conditionless trigger, which would otherwise re-fire every
## other frame forever: its stand-in condition is true again the moment reset() clears the
## edge latch, and for a trigger carrying an EventSpawnEntities that is a runaway. Nothing is
## lost — an EventChainTrigger re-arming such a trigger fires it again either way, which is the
## on-demand case a repeating unconditional trigger would have been for. Authoring it false is
## reported as a configuration warning rather than silently honoured.
@export var one_shot: bool = true

## Triggers that must have fired before this one arms — the dependency edges of the
## scenario's objective DAG. Empty means nothing gates it.
##
## Declared on the DEPENDENT rather than pushed by the predecessor, which is the whole point:
## adding a step means pointing the new node at what it waits for, instead of remembering to
## add an EventChainTrigger child to every node that comes before it. A forgotten edge is
## then a visibly empty field on the thing that doesn't run, not a missing child node
## somewhere else in the tree.
##
## Edges are shared node references. SanctionUnlock used to share this any-of idiom and
## deliberately no longer does — a sanction has exactly ONE dependency (its `parent`), so a
## list there could only blur the chain it is meant to state. Godot serializes them as node
## paths and re-resolves on instantiate, so joins and fan-outs survive the round trip.
##
## An EventChainTrigger can still arm a trigger whose prerequisites are unmet, and can still
## disable one that is running: those are imperative overrides, and vetoing them would make
## the two mechanisms fight. But "starts switched off" is no longer a flag of its own —
## declare what the trigger waits for instead, which records WHY it is waiting rather than
## only that it is.
@export var prerequisites: Array[GlobalTrigger] = []

## How `prerequisites` combine. ALL_OF is the mission default — "do these, then this".
## ANY_OF is the sanction-DAG shape, where reaching a node by any route unlocks it.
@export var prerequisite_mode: PrerequisiteMode = PrerequisiteMode.ALL_OF

## Runtime state — not serialized. Whether this trigger is currently watching. Set from
## prerequisites_satisfied() by ScenarioTriggerManager when it arms; toggled by set_active().
var enabled: bool = true

## Runtime state — not serialized. Whether this trigger has ever fired. Needed because
## `enabled` alone can't tell PENDING from COMPLETE: a one-shot trigger disables itself on
## firing, so "not enabled" covers both "not revealed yet" and "already done".
var has_fired: bool = false

## Runtime state — not serialized. How many times this trigger has fired. `has_fired` only
## answers "ever", which is all the objective states need, but a REPEATING trigger driving a
## wave usually wants to know WHICH wave this is — so an authored expression can grow the
## spawn count or shorten the interval each cycle (see ScenarioExpression's `fires` input).
## Zero on the first fire, so "2 + fires" reads as 2, then 3, then 4.
var fire_count: int = 0

## The manager this trigger is armed against; null until armed.
var _manager: ScenarioTriggerManager
## Last aggregate satisfaction, for rising-edge firing.
var _was_satisfied: bool = false
## The stand-in watched when no conditions were authored; created on first use by _watched().
## Held rather than rebuilt per call because it carries the edge state the poller writes.
var _implicit_condition: ConditionAlways
#endregion


#region Authoring
## Surface each condition's authoring problems on THIS node in the Scene dock. Conditions are
## Resources and have no dock entry of their own, so without this a mistyped expression on a
## condition has nowhere visible to complain.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	# "Fires immediately, forever" is never what the author meant, and the flag is silently
	# overridden rather than obeyed — so say where the disagreement is, in the dock.
	if is_unconditional() and not one_shot:
		warnings.append(
			(
				"One Shot is off but there are no conditions. A trigger with nothing to wait for "
				+ "fires as soon as it arms, so it is treated as one-shot regardless."
			)
		)
	for condition: Condition in conditions:
		if condition == null:
			continue
		var problem: String = condition.configuration_warning()
		if not problem.is_empty():
			warnings.append(problem)
	return warnings


#endregion


#region Prerequisites
## Whether this trigger's dependencies are met and it may arm. True when it has none.
##
## Null entries are skipped rather than treated as unmet: an Array export shows a blank row
## whenever you grow it in the inspector, and a half-filled row shouldn't wedge the mission.
func prerequisites_satisfied() -> bool:
	var live: Array = prerequisites.filter(func(t: GlobalTrigger) -> bool: return t != null)
	if live.is_empty():
		return true
	if prerequisite_mode == PrerequisiteMode.ALL_OF:
		return live.all(func(t: GlobalTrigger) -> bool: return t.has_fired)
	return live.any(func(t: GlobalTrigger) -> bool: return t.has_fired)


## Whether anything gates this trigger at all — the check that separates "waiting on a
## dependency" from "waiting on an EventChainTrigger to switch me on".
func has_prerequisites() -> bool:
	return prerequisites.any(func(t: GlobalTrigger) -> bool: return t != null)


#endregion


#region Objectives
## How this trigger currently reads to the player. COMPLETE wins over everything: a
## REPEATING objective stays enabled after firing, and it should still tick off rather than
## sit unchecked forever.
func objective_state() -> ObjectiveState:
	if has_fired:
		return ObjectiveState.COMPLETE
	return ObjectiveState.ACTIVE if enabled else ObjectiveState.PENDING


## The checklist line for this trigger.
func objective_text() -> String:
	return description


## Whether the player ever sees this trigger at all.
func is_player_facing() -> bool:
	return scope != ObjectiveScope.NONE


## Whether ticking this off is part of finishing the scenario. PRIMARY only: a SECONDARY is
## optional by definition, and a FAILURE is a way to LOSE — requiring it would mean the
## scenario could only be won by losing.
func counts_toward_completion() -> bool:
	return scope == ObjectiveScope.PRIMARY


## True when this trigger counts toward scenario completion and is done.
func is_objective_complete() -> bool:
	return counts_toward_completion() and has_fired


## Announce a possible change in objective_state(). Called from the three places that can
## move it: arm, disarm, and fire.
func _notify_objective_state() -> void:
	objective_state_changed.emit(self)


#endregion


#region Conditions
## Whether nothing gates this trigger — no conditions were authored, so it fires on arming.
## Blank inspector rows don't count, exactly as in prerequisites_satisfied().
func is_unconditional() -> bool:
	return not conditions.any(func(c: Condition) -> bool: return c != null)


## The conditions actually watched: the authored ones with blank rows dropped, or a single
## always-true stand-in when there are none. Every path that reads `conditions` at runtime goes
## through here, which is what makes "no conditions" mean "fires immediately" rather than
## "never fires" — and incidentally makes a half-filled Array export harmless instead of an
## error the first time the aggregate calls is_met() on a null.
func _watched() -> Array[Condition]:
	var live: Array[Condition] = []
	for condition: Condition in conditions:
		if condition != null:
			live.append(condition)
	if live.is_empty():
		if _implicit_condition == null:
			_implicit_condition = ConditionAlways.new()
		live.append(_implicit_condition)
	return live


## Drop every authored condition's runtime state, so this trigger starts watching with
## nothing carried over. Called once per session by ScenarioTriggerManager — see
## _reset_session_conditions() there for why a Resource can arrive already dirty, and why
## this is NOT folded into arm().
func reset_conditions() -> void:
	_was_satisfied = false
	for condition: Condition in _watched():
		condition.reset()


#endregion


#region Arming
## Subscribe to this trigger's conditions so it fires reactively when they become
## satisfied — no per-tick polling of the trigger itself. Each condition arms its own
## driver (push: a bus; pull: the ConditionPoller); we re-check on its state_changed.
func arm(a_manager: ScenarioTriggerManager) -> void:
	_manager = a_manager
	_was_satisfied = false
	# An unconditional trigger re-armed by an EventChainTrigger has to fire again, and its
	# stand-in is still caching `true` from last time — a condition whose truth doesn't CHANGE
	# never emits state_changed. Dropping that latch makes the next poll a rising edge again.
	if _implicit_condition != null:
		_implicit_condition.reset()
	for condition: Condition in _watched():
		# A RegionAwareCondition only stores a NodePath (a Resource can't resolve one); resolve
		# it against this trigger and inject the live CollisionShape3D before the condition runs.
		if condition is RegionAwareCondition:
			var region_aware := condition as RegionAwareCondition
			region_aware.bind_region(
				get_node_or_null(region_aware.region_shape_path) as CollisionShape3D
			)
			# A region that was asked for but didn't resolve widens the check to the whole map
			# instead of failing, so say so loudly here rather than leaving it to be discovered
			# as "my trigger doesn't fire".
			region_aware.warn_about_missing_region(String(name))
		# Let the condition reach back to this trigger — how an authored expression gets at
		# `fires` (see ScenarioExpression). Before arm(), so a condition that resolves something
		# on its first evaluation already has it.
		condition.bind_trigger(self)
		# Every condition arms, not just the region-aware ones: this is what registers a pull
		# condition with the ConditionPoller, and a condition that never polls never emits
		# state_changed, so its trigger never fires.
		condition.arm(a_manager)
		if not condition.state_changed.is_connected(_on_condition_changed):
			condition.state_changed.connect(_on_condition_changed)
	# Now that the conditions are live, show what they're about. Deliberately after arming:
	# a highlight's target set is derived from the conditions, and a region-aware condition
	# only has its region bound by the loop above.
	_set_lifetime_highlights(true)
	# Arming is what moves an objective from PENDING to ACTIVE — i.e. what reveals it.
	_notify_objective_state()


## Undo arm(): disconnect from the conditions and let them tear down their drivers.
func disarm() -> void:
	if _manager == null:
		return
	_set_lifetime_highlights(false)
	for condition: Condition in _watched():
		if condition.state_changed.is_connected(_on_condition_changed):
			condition.state_changed.disconnect(_on_condition_changed)
		condition.disarm(_manager)
	_notify_objective_state()


## Enable/disable at runtime (EventChainTrigger). Arms a re-enabled trigger and disarms
## a disabled one. `manager` may be null when no manager is wired (e.g. a unit test just
## flipping the flag), in which case only the flag changes.
func set_active(a_active: bool, a_manager: ScenarioTriggerManager) -> void:
	enabled = a_active
	if a_manager == null:
		return
	if a_active:
		arm(a_manager)
	else:
		disarm()


#endregion


#region Firing
## Re-check on a condition's state_changed and fire on the rising edge of the AND/OR
## aggregate. Reads each condition's cached truth (Condition.is_met) rather than
## re-evaluating, so a side-effecting evaluate() runs at most once per frame (in poll()).
func _on_condition_changed() -> void:
	if not enabled:
		return
	var now: bool = _aggregate_met()
	if now == _was_satisfied:
		return
	_was_satisfied = now
	if now:
		fire(_manager)


## AND/OR aggregate over the watched conditions' cached truth (is_met). Never empty — an
## unauthored set is one always-true stand-in — so an unconditional trigger reads as satisfied.
func _aggregate_met() -> bool:
	var watched: Array[Condition] = _watched()
	if condition_mode == ConditionMode.AND:
		return watched.all(func(c: Condition) -> bool: return c.is_met())
	return watched.any(func(c: Condition) -> bool: return c.is_met())


## Live AND/OR aggregate over evaluate() — the direct query API (and what tests use).
## The firing path uses the cached _aggregate_met() instead, to avoid re-evaluating.
func is_satisfied(a_manager: ScenarioTriggerManager) -> bool:
	var watched: Array[Condition] = _watched()
	if condition_mode == ConditionMode.AND:
		return watched.all(func(c: Condition) -> bool: return c.evaluate(a_manager))
	return watched.any(func(c: Condition) -> bool: return c.evaluate(a_manager))


func fire(a_manager: ScenarioTriggerManager) -> void:
	# The objective is met, so its marks have served their purpose — drop them BEFORE the
	# events run, otherwise an event that hands the highlight on to the next objective would
	# be undone a moment later by this trigger's own teardown.
	_set_lifetime_highlights(false)
	# Run each inline child AbstractEvent in place (source = null: a global trigger isn't
	# tied to an entity). Events use their own authored positions.
	for child in get_children():
		if child is AbstractEvent:
			a_manager.run_event(child as AbstractEvent, null)
	# A conditionless trigger disables itself whatever `one_shot` says: resetting its stand-in
	# below would make it true again immediately, and it would re-fire every other frame forever.
	if one_shot or is_unconditional():
		enabled = false
		disarm()
	else:
		# Repeating: reset conditions and the edge latch so the next rising edge re-fires.
		_was_satisfied = false
		for condition: Condition in _watched():
			condition.reset()
		# A repeating trigger is watching again immediately, so its marks go back up.
		_set_lifetime_highlights(true)
	# Set before the signals so anything reacting to `fired` (an ObjectiveChain revealing the
	# next step, the manager re-checking whether every objective is done) already sees this
	# one as COMPLETE.
	has_fired = true
	# Counted AFTER the events ran, so an expression evaluated during this fire still sees the
	# index of the cycle it belongs to ("2 + fires" spawns 2 on the first fire, not 3).
	fire_count += 1
	_notify_objective_state()
	fired.emit()


#endregion


#region Highlights
## Raise or drop the child EventHighlights that track this trigger's armed state, so an
## objective's world markers are visible exactly while that objective is the live one. A
## highlight opting out (follow_trigger_lifetime = false) is driven by fire() as an ordinary
## event instead and is left alone here.
func _set_lifetime_highlights(a_visible_now: bool) -> void:
	if _manager == null:
		return
	for child in get_children():
		var highlight := child as EventHighlight
		if highlight == null or not highlight.follow_trigger_lifetime:
			continue
		if a_visible_now:
			highlight.show_highlight(_manager)
		else:
			highlight.hide_highlight()
#endregion
