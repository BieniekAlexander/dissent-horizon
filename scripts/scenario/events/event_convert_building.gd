@tool
class_name EventConvertBuilding
extends AbstractEvent

## Turns a neutral building into an Anarchical Safehouse (an_infrastructure) for `commander_id`,
## in place, exactly as a builder's conversion does (Build.convert_building): the building
## keeps its footprint, HP and garrison, and takes the Safehouse's own properties from its
## piece scene at the moment it converts.
##
## Parked as a STARTING event directly under the neutral building, it converts it before the
## player's first order, so a mission can open with Safehouses already standing — with a
## sibling EventSpawnEntities after it (garrison_host "..") to fill one. That is why it exists
## rather than placing a converted building in the scene: a converted building packed into a
## mission would freeze the Safehouse's stats as they were that day, while this reads them
## when the mission runs. The building is the event's source entity (`reaction_source`), or
## `building` when set.

#region Properties
## Who owns the Safehouse.
@export var commander_id: int = 1
## The building to convert. Unset means the piece this event is parked under.
@export var building: NodePath
#endregion


#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	var target: Actor = a_manager.reaction_source as Actor
	if not building.is_empty():
		target = get_node_or_null(building) as Actor
	if target == null or target.id == EntityIds.AN_INFRASTRUCTURE:
		return
	if PieceFamilies.template(target.id) == null:
		push_error(
			"EventConvertBuilding: %s is not a neutral building a Safehouse is built from" % target
		)
		return
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		push_error("EventConvertBuilding: no commander %d" % commander_id)
		return
	Build.convert_building(target, commander)
#endregion
