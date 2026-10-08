class_name PlacementKnowledge
extends RefCounted

## What a commander KNOWS about the ground it is placing a structure on, so a refused
## placement never tells it what stands in the fog. Ground in vision is judged by the true
## grid; explored ground out of vision by what the commander last saw (its own and allied
## pieces, neutral ones, and the enemy structures its blackboard still believes); unexplored
## ground admits nothing. A placement accepted on stale knowledge is caught when the builder
## arrives (Build.fulfill_action).
## Rule and reasoning: gdd/systems/commands/construction.md §Placement is judged against what
## the commander knows.

var _commander: Commander
var _map: Map
## Cells covered by believed enemy structures, as last seen — so a structure destroyed out of
## sight still reads as standing there.
var _remembered: Dictionary


## The knowledge `a_commander` places by on `a_map`, or null for a caller that has no commander
## to know anything — which judges the true grid, as the debug spawner and scenario
## deployment do.
static func of(commander: Commander, map: Map) -> PlacementKnowledge:
	if commander == null or map == null:
		return null
	var knowledge := PlacementKnowledge.new()
	knowledge._commander = commander
	knowledge._map = map
	knowledge._remembered = (
		commander.blackboard.remembered_structure_cells() if commander.blackboard != null else {}
	)
	return knowledge


func is_explored(a_cell: Vector2i) -> bool:
	return _commander.has_explored(_map.grid_to_world(a_cell))


func is_in_vision(a_cell: Vector2i) -> bool:
	return _commander.has_vision_at(_map.grid_to_world(a_cell))


## Whether the commander would expect to find `a_entity` where it stands: anything not an
## enemy's is common knowledge, an enemy's only while in sight or still believed.
func knows_of(a_entity: Entity) -> bool:
	if a_entity == null:
		return false
	var owner_id: int = a_entity.commander_id
	if owner_id == 0 or owner_id == _commander.id:
		return true
	if _commander.has_vision_at(a_entity.global_position):
		return true
	return (
		_commander.blackboard == null or _commander.blackboard.believes(a_entity.get_instance_id())
	)


## Whether the commander believes a structure occupies `a_cell`. Unexplored ground is not
## asked: Fixture.cell_admits_structure refuses it before occupancy matters.
func believes_occupied(a_cell: Vector2i) -> bool:
	# Object, not Entity: the grid is untyped, and only a piece can be unknown — anything else
	# that holds a cell is common knowledge.
	var occupant: Object = _map.cell_grid[a_cell.x][a_cell.y]
	if occupant == null:
		return not is_in_vision(a_cell) and _remembered.has(a_cell)
	if is_in_vision(a_cell) or not occupant is Entity:
		return true
	return knows_of(occupant as Entity) or _remembered.has(a_cell)


## Whether the commander believes something is overlaid on `a_site` — the ExtractionSite case,
## where the site stays the cells' occupant and the extractor binds to it.
func believes_site_taken(a_site: ExtractionSite, a_cells: Array[Vector2i]) -> bool:
	if a_cells.any(is_in_vision):
		return a_site.extractor != null
	return (
		(a_site.extractor != null and knows_of(a_site.extractor))
		or a_cells.any(func(c: Vector2i) -> bool: return _remembered.has(c))
	)


## Whether the commander believes `a_body` already has its one extractor.
func believes_pond_taken(a_body: WaterBody) -> bool:
	return a_body.has_extractor() and knows_of(a_body.extractor as Entity)
