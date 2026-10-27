@tool
class_name ConditionUnitCount
extends RegionAwareCondition

#region Properties
enum Comparison { AT_LEAST, AT_MOST, EXACTLY }

@export var commander_id: int = 1
## UNDEFINED matches units of any type.
@export var unit_type: StringName = &""
@export var comparison: Comparison = Comparison.AT_LEAST
@export var count: int = 1
## Also count units carried by this commander's own pieces: held in a building it occupies, or
## riding one of its transports. Off the tree, they would otherwise read as dead. A captive in
## someone else's prison is not counted. Ignored with a region, which a carried unit is not in.
@export var should_count_carried: bool = false
## Optional spatial scope is inherited from RegionAwareCondition (region_shape_path): when
## set, only units inside that CollisionShape3D are counted.
#endregion


#region Public API
func honours_perspective() -> bool:
	return true


func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var n: int = matching_units(a_manager).size()
	match comparison:
		Comparison.AT_LEAST:
			return n >= count
		Comparison.AT_MOST:
			return n <= count
		Comparison.EXACTLY:
			return n == count
	return false


#endregion


#region Player-facing description (highlights)
## AT_MOST is the "get rid of these" shape of the check — the matching units ARE the task,
## so mark them and let the marks vanish as they die. AT_LEAST / EXACTLY are waiting on
## units that don't exist yet, so there is nothing to point at; the inherited region
## footprint (RegionAwareCondition.highlight_shapes) carries "bring them HERE" instead.
func highlight_entities(a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	if comparison != Comparison.AT_MOST:
		return result
	result.assign(matching_units(a_manager))
	return result


#endregion


#region Internal
## Every unit the commander owns that passes the type and region filters — the set both
## evaluate() counts and highlight_entities() marks, so what the player sees marked can
## never drift from what the check is actually measuring.
func matching_units(a_manager: ScenarioTriggerManager) -> Array:
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		return []
	var units: Array = commander.get_children().filter(
		func(n: Node) -> bool:
			return (
				n is Actor
				and (n as Actor).is_in_group("unit")
				and _is_of_type(n as Actor)
				and _is_counted(a_manager, n as Actor)
			)
	)
	if should_count_carried and not has_region():
		for piece: Node in commander.get_children():
			if piece is Actor:
				units.append_array(carried_units(piece as Actor).filter(_is_of_type))
	return units


## Every unit `a_host` carries of its own commander, through any nesting of hosts.
static func carried_units(a_host: Actor) -> Array[Actor]:
	var result: Array[Actor] = []
	if a_host.garrison == null:
		return result
	for occupant: Actor in a_host.garrison.occupants():
		if is_instance_valid(occupant) and occupant.commander_id == a_host.commander_id:
			result.append(occupant)
			result.append_array(carried_units(occupant))
	return result


func _is_of_type(a_unit: Actor) -> bool:
	return unit_type == &"" or a_unit.id == unit_type


## Whether `a_unit` is where this check counts: in the region, at the position its perspective
## takes it to be — so a unit the alliance knows nothing of is not counted.
func _is_counted(a_manager: ScenarioTriggerManager, a_unit: Actor) -> bool:
	var at: Variant = perceived_position(a_manager, a_unit)
	return at != null and region_contains(at)
#endregion
