@tool
class_name Condition
extends Resource

## A boolean check on game state, owned by a GlobalTrigger. A Condition may be PULL- or
## PUSH-based, and which one is entirely the subclass's choice — the owning trigger
## consumes both identically:
##   * PULL: override evaluate() to compute truth live from game state. The DEFAULT
##     arm() registers the condition with the ScenarioTriggerManager's ConditionPoller,
##     which calls poll() every physics frame and emits state_changed on a truth edge.
##   * PUSH: override arm()/disarm() to (dis)connect a signal bus (e.g.
##     ScenarioTriggerManager.entity_occurrence), update truth in the handler, and emit
##     state_changed yourself. evaluate() then just reports the cached result.
## Either way evaluate() must be idempotent — it may be called more than once.

## Emitted when this condition's truth changes — the cue for an owning GlobalTrigger to
## re-check and (on a rising edge) fire. Named state_changed, not `changed`, to avoid
## colliding with Resource's built-in `changed` signal.
signal state_changed

## Whose knowledge a check reads. OMNISCIENT (the default, and every shipped mission) reads the
## live scene; ALLIANCE reads what `perspective_commander_id`'s alliance believes
## (AlliancePerspective) — the fog-limited reading for a check that decides on a computer
## commander's behalf. Only a check over pieces can honour it (honours_perspective); the owning
## trigger warns when it is set on one that cannot.
enum Perspective { OMNISCIENT, ALLIANCE }

@export var perspective: Perspective = Perspective.OMNISCIENT
## Any member of the alliance whose beliefs an ALLIANCE check reads.
@export var perspective_commander_id: int = 1


#region Public API
## Current truth, computed live. PULL subclasses inspect game state here; PUSH
## subclasses return cached state maintained by their bus handler. Must be idempotent.
func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
	return false


## Cached truth — the last value seen by poll() or a push handler. The owning trigger
## aggregates THIS rather than re-calling evaluate(), so a side-effecting evaluate()
## runs at most once per frame (inside poll()).
func is_met() -> bool:
	return _last


## Subscribe to whatever drives this condition. DEFAULT = pull: register with the
## manager's ConditionPoller. PUSH subclasses override to connect a bus instead.
func arm(a_manager: ScenarioTriggerManager) -> void:
	a_manager.condition_poller.add(self)


## Undo arm(). DEFAULT = pull: deregister from the poller. PUSH subclasses override to
## disconnect their bus.
func disarm(a_manager: ScenarioTriggerManager) -> void:
	a_manager.condition_poller.remove(self)


## Called once per session for every authored condition, armed or not, once the placed pieces
## are in the world and before any trigger arms. For a condition that must find its subject
## while it still exists: a trigger armed late (behind a prerequisite) otherwise looks for it
## only after play may have destroyed it (ConditionEntityKilled).
func prime(_a_manager: ScenarioTriggerManager) -> void:
	pass


## Called when the owning GlobalTrigger resets after firing (repeating triggers only).
## Override to clear per-fire state, and call super() to keep edge tracking consistent.
func reset() -> void:
	_last = false


## The trigger this condition belongs to, injected by GlobalTrigger.arm() — the same
## dependency-injection shape RegionAwareCondition.bind_region uses, and for the same reason:
## a Condition is a Resource, so it cannot reach its owner on its own.
##
## A Condition Resource SHARED between two triggers ends up bound to whichever armed last.
## Sharing one condition instance across triggers is already hazardous (disarming one
## deregisters it for both), so this doesn't add a new failure mode — but it is another
## reason to give each trigger its own condition.
func bind_trigger(a_trigger: GlobalTrigger) -> void:
	_trigger = a_trigger


## How many times the owning trigger has already fired — the `fires` input available to
## authored expressions. 0 when unbound, so an unowned condition still evaluates.
func owner_fire_count() -> int:
	return _trigger.fire_count if is_instance_valid(_trigger) else 0


## Where this check takes `a_piece` to stand: live under OMNISCIENT, the alliance's belief
## under ALLIANCE — null when the alliance knows of no such piece, and a check then leaves it out.
func perceived_position(a_manager: ScenarioTriggerManager, a_piece: Node3D) -> Variant:
	if perspective == Perspective.OMNISCIENT:
		return a_piece.global_position
	return AlliancePerspective.position_of(a_manager, perspective_commander_id, a_piece)


## Whether this check reads `perspective` — one over pieces does; a timer or a resource
## threshold has nothing an alliance could fail to see.
func honours_perspective() -> bool:
	return false


## The authoring problem with `perspective`, or "": an ALLIANCE check that cannot honour it would
## silently read the live scene.
func perspective_warning() -> String:
	if perspective == Perspective.OMNISCIENT or honours_perspective():
		return ""
	return (
		"%s reads the live scene whatever its Perspective; set it back to OMNISCIENT"
		% get_script().get_global_name()
	)


## An editor-time problem with how this condition is authored, or "" when it is fine.
##
## A Resource has no Scene dock entry of its own, so the OWNING TRIGGER collects these into
## its _get_configuration_warnings — which is why this is a plain method rather than an
## override of Godot's node-only hook.
func configuration_warning() -> String:
	return ""


#endregion


#region Player-facing description (highlights)
## The entities this condition is ABOUT, for an EventHighlight to mark in the world — e.g.
## the enemies a "kill everything here" check is waiting on, or the units a "select one of
## these" check will accept. Re-queried periodically while the highlight is up, so the
## marks follow units that move, spawn, or die.
##
## Return only entities the player still has something to DO with. A count check that wants
## MORE of something has nothing to point at yet (the units don't exist); it should return
## nothing here and let its region carry the message instead. The default is no entities.
func highlight_entities(_a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var none: Array[Entity] = []
	return none


## The ground footprints this condition is scoped to — the region a unit must reach, the
## cell a structure must occupy. Painted on the terrain by an EventHighlight. The default
## is no footprint (the condition isn't spatial).
func highlight_shapes(_a_manager: ScenarioTriggerManager) -> Array[HighlightShape]:
	var none: Array[HighlightShape] = []
	return none


#endregion

#region Pull plumbing
## Last truth seen, for edge detection and is_met().
var _last: bool = false

## The owning trigger, injected by bind_trigger() at arm time. Not serialized — a Resource
## must not hold a scene node across a save.
var _trigger: GlobalTrigger


## Edge-detected re-check, called once per physics frame by the ConditionPoller for pull
## conditions. Updates the cache and emits state_changed only on a transition — a steady
## condition costs one evaluate() per frame and nudges the trigger only on change.
func poll(a_manager: ScenarioTriggerManager) -> void:
	var now: bool = evaluate(a_manager)
	if now != _last:
		_last = now
		state_changed.emit()
#endregion
