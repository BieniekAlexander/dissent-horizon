class_name ConditionUnitsInRegion
extends Condition

#region Properties
enum RegionShape { RECT, CIRCLE }
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
@export var region_shape: RegionShape = RegionShape.RECT
## World-space XZ corners when region_shape == RECT.
@export var rect_min: Vector2 = Vector2.ZERO
@export var rect_max: Vector2 = Vector2(10.0, 10.0)
## World-space XZ centre when region_shape == CIRCLE.
@export var circle_center: Vector2 = Vector2.ZERO
@export var circle_radius: float = 2.5
@export var check: Check = Check.ANY_INSIDE

var _was_inside: bool = false
#endregion

#region Private helpers
func _in_region(xz: Vector2) -> bool:
	if region_shape == RegionShape.RECT:
		return xz.x >= rect_min.x and xz.x <= rect_max.x \
			and xz.y >= rect_min.y and xz.y <= rect_max.y
	return xz.distance_to(circle_center) <= circle_radius
#endregion

#region Public API
func evaluate(manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	var units: Array = commander.get_children().filter(
		func(n: Node) -> bool:
			return n is Commandable and (n as Commandable).is_in_group("unit") \
				and (unit_type == &"" or (n as Commandable).id == unit_type)
	)
	var any_inside := units.any(
		func(u: Commandable) -> bool: return _in_region(VU.inXZ(u.global_position))
	)
	match check:
		Check.ANY_INSIDE:
			return any_inside
		Check.ALL_INSIDE:
			return not units.is_empty() and units.all(
				func(u: Commandable) -> bool: return _in_region(VU.inXZ(u.global_position))
			)
		Check.ANY_ENTER:
			var entered := any_inside and not _was_inside
			_was_inside = any_inside
			return entered
		Check.ANY_EXIT:
			var exited := not any_inside and _was_inside
			_was_inside = any_inside
			return exited
	return false

func reset() -> void:
	super.reset()
	_was_inside = false
#endregion
