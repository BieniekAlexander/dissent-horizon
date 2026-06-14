class_name ConditionStructureBuilt
extends Condition

#region Properties
## -1 = any commander owns it.
@export var commander_id: int = -1
## UNDEFINED = any structure type.
@export var structure_type: Entity.Type = Entity.Type.UNDEFINED
## (-1,-1) = ignore location; otherwise the exact grid cell must be occupied.
@export var grid_cell: Vector2i = Vector2i(-1, -1)
#endregion

#region Public API
func evaluate(manager: ScenarioEventManager) -> bool:
	var map := manager.map
	if map == null:
		return false

	if grid_cell != Vector2i(-1, -1):
		if not map.grid_coordinates_in_bounds(grid_cell):
			return false
		var occupant = map.cell_grid[grid_cell.x][grid_cell.y]
		if occupant == null or not occupant is Commandable:
			return false
		var c := occupant as Commandable
		if structure_type != Entity.Type.UNDEFINED and c.type != structure_type:
			return false
		if commander_id >= 0 and c.commander_id != commander_id:
			return false
		return true

	# No cell constraint — check commander's structure_type_map.
	for commander: Commander in manager.scenario.commanders:
		if commander_id >= 0 and commander.id != commander_id:
			continue
		if structure_type == Entity.Type.UNDEFINED:
			for t: int in Entity.Type.values():
				if t < 0:
					continue
				if not commander.structure_type_map[t].is_empty():
					return true
		else:
			if not commander.structure_type_map[structure_type].is_empty():
				return true
	return false
#endregion
