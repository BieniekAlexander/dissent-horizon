@tool
class_name ConditionStructureBuilt
extends Condition

#region Properties
## -1 = any commander owns it.
@export var commander_id: int = -1
## UNDEFINED = any structure type.
@export var structure_type: StringName = &""
## (-1,-1) = ignore location; otherwise the exact grid cell must be occupied.
@export var grid_cell: Vector2i = Vector2i(-1, -1)
#endregion


#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var map := a_manager.map
	if map == null:
		return false

	if grid_cell != Vector2i(-1, -1):
		if not map.grid_coordinates_in_bounds(grid_cell):
			return false
		var occupant = map.cell_grid[grid_cell.x][grid_cell.y]
		if occupant == null or not occupant is Commandable:
			return false
		var c := occupant as Commandable
		if structure_type != &"" and c.id != structure_type:
			return false
		if commander_id >= 0 and c.commander_id != commander_id:
			return false
		return c.is_built

	# No cell constraint — check commander's structure_type_map.
	for commander: Commander in a_manager.scenario.commanders:
		if commander_id >= 0 and commander.id != commander_id:
			continue
		if structure_type == &"":
			for t: StringName in commander.structure_type_map:
				if commander.has_built_structure(t):
					return true
		else:
			if commander.has_built_structure(structure_type):
				return true
	return false


#endregion


#region Player-facing description (highlights)
## With a cell constraint, the cell itself is the instruction ("build it HERE") — paint the
## one-cell footprint. Without one the check is "build this ANYWHERE", which has no place
## to point at; highlight the producing structure explicitly with an EventHighlight carrying
## its own EntitySelector children instead.
func highlight_shapes(a_manager: ScenarioTriggerManager) -> Array[HighlightShape]:
	var result: Array[HighlightShape] = []
	if grid_cell == Vector2i(-1, -1) or a_manager.map == null:
		return result
	if not a_manager.map.grid_coordinates_in_bounds(grid_cell):
		return result
	var world: Vector3 = a_manager.map.grid_to_world(grid_cell)
	var half: float = Map.CELL_SIZE * 0.5
	result.append(HighlightShape.rect(VU.inXZ(world), Vector2(half, half)))
	return result
#endregion
