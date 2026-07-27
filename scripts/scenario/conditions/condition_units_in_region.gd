@tool
class_name ConditionUnitsInRegion
extends RegionAwareCondition

## Watches whether a commander's units are inside a region — "has the player reached the
## ridge", "has the escort left the corridor".
##
## The region is a CollisionShape3D in the scene, inherited from RegionAwareCondition
## (`region_shape_path`, resolved against the owning trigger at arm()). Authoring it as a
## real node rather than as numbers means it is visible and draggable in the 3D viewport, it
## MOVES WITH THE TRIGGER when the trigger's marker is dragged, and an EventHighlight can
## paint it for the player automatically — see RegionAwareCondition.highlight_shapes.
##
## Prefer ConditionUnitCount for plain "at least N units are here" checks; the reason to
## reach for this one is `check`, which adds ALL_INSIDE and the falling edge (ANY_EXIT).
##
## Note that a one-shot GlobalTrigger already fires on the RISING edge of its aggregate, so
## ANY_INSIDE is normally enough to mean "when a unit first arrives". ANY_ENTER exists for
## repeating triggers, where the aggregate latch is reset after every fire.

#region Properties
enum Check {
	## True every tick at least one matching unit is inside (level-triggered).
	ANY_INSIDE,
	## True on the tick any matching unit first enters the region (edge-triggered).
	ANY_ENTER,
	## True on the tick the region becomes empty after having a unit (edge-triggered).
	ANY_EXIT,
	## True every tick ALL matching units owned by the commander are inside.
	ALL_INSIDE
}

@export var commander_id: int = 1
## UNDEFINED matches any unit type.
@export var unit_type: StringName = &""
@export var check: Check = Check.ANY_INSIDE
## The region itself is inherited from RegionAwareCondition (region_shape_path).

## Whether a matching unit was inside as of the previous poll — the latch behind ANY_ENTER
## and ANY_EXIT. Advanced by poll(), never by evaluate(), so evaluate() stays idempotent.
var _was_inside: bool = false
#endregion

#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var units: Array = _matching_units(a_manager)
	var any_inside: bool = units.any(
		func(u: Commandable) -> bool: return region_contains(u.global_position)
	)
	match check:
		Check.ANY_INSIDE:
			return any_inside
		Check.ALL_INSIDE:
			return not units.is_empty() and units.all(
				func(u: Commandable) -> bool: return region_contains(u.global_position)
			)
		Check.ANY_ENTER:
			return any_inside and not _was_inside
		Check.ANY_EXIT:
			return not any_inside and _was_inside
	return false


## Advance the enter/exit latch after the base class has done its edge detection, so the
## `_was_inside` that evaluate() compared against is genuinely the PREVIOUS frame's.
##
## The latch lives here rather than inside evaluate() because Condition's contract requires
## evaluate() to be idempotent — GlobalTrigger.is_satisfied() calls it directly, and an
## evaluate() that consumed its own edge would report a spurious enter to whoever asked
## second.
func poll(a_manager: ScenarioTriggerManager) -> void:
	super(a_manager)
	if check == Check.ANY_ENTER or check == Check.ANY_EXIT:
		_was_inside = _matching_units(a_manager).any(
			func(u: Commandable) -> bool: return region_contains(u.global_position)
		)


func reset() -> void:
	super.reset()
	_was_inside = false
#endregion

#region Player-facing description (highlights)
## A region check is ABOUT its region, whichever way it is phrased, so the inherited
## footprint (RegionAwareCondition.highlight_shapes) is the whole story — there is nothing
## useful to mark on the units themselves.
#endregion

#region Internal
## The commander's units that pass the type filter, before any region test. Region filtering
## is left to the callers because each `check` mode combines it differently.
func _matching_units(a_manager: ScenarioTriggerManager) -> Array:
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		return []
	return commander.get_children().filter(
		func(n: Node) -> bool:
			return n is Commandable and (n as Commandable).is_in_group("unit") \
				and (unit_type == &"" or (n as Commandable).id == unit_type)
	)


## A region is the entire point of this check: without one, region_contains() would match
## everywhere and the trigger would fire the moment the commander owns any unit at all.
func _region_is_required() -> bool:
	return true
#endregion
