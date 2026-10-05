class_name DebugPlacement
extends RefCounted

## Where the debug spawner may put a piece, and putting it there. See
## gdd/systems/ux/ui/debug-mode.md §The piece spawner.
##
## Placement is FREE and unconditional on the owner: no cost, no technology, no fog. What is
## kept is what the map itself needs — a fixture must fit the TRUE grid exactly as a Build
## would, and a ground unit must stand on its own size class's navmesh.
##
## The checks read a SOURCE instance: one instantiated from the piece's scene and never added
## to the tree, like Commander's build-preview instances. A placement always spawns a fresh
## instance.


## Whether `a_source` may be placed at `a_message`'s position, as the piece it is.
static func admits(a_source: Entity, a_message: CommandMessage) -> bool:
	if a_source == null or a_message == null or a_message.map == null:
		return false
	var structure := a_source.get_node_or_null("Structure") as Structure
	if structure != null and a_source.spawns_deployed():
		return fixture_admits(
			structure, Extractor.of(a_source) != null, a_message, Extractor.works_ponds(a_source)
		)
	return figure_admits(a_source, a_message.map, a_message.xz_position)


## The footprint rule Build applies, without its purchase: an extractor overlays a site or
## stands in a pond (when `a_works_ponds`), everything else needs in-bounds, empty, flat, dry
## cells.
static func fixture_admits(
	a_structure: Structure,
	a_is_extractor: bool,
	a_message: CommandMessage,
	a_works_ponds: bool = true
) -> bool:
	if a_is_extractor:
		return EnergyExtractor.valid_placement(
			a_message,
			a_structure.dimensions,
			a_structure.allow_uneven,
			a_structure.allow_submerged,
			a_works_ponds
		)
	return Structure.valid_placement(
		a_message, a_structure.dimensions, a_structure.allow_uneven, a_structure.allow_submerged
	)


## A flier may go anywhere on the map; a ground unit only where its own size class's navmesh
## reaches, so it is never dropped somewhere it cannot move.
static func figure_admits(a_source: Entity, a_map: Map, a_xz: Vector2) -> bool:
	var cell: Vector2i = a_map.world_to_grid(a_xz)
	if not a_map.grid_coordinates_in_bounds(cell):
		return false
	if Aerial.of(a_source) != null:
		return true
	var size: NavAgentClass.Size = NavAgentClass.class_for_radius(
		a_source.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION), Map.CELL_SIZE
	)
	return a_map.terrain_grid.is_navigable_for(
		cell,
		NavAgentClass.erosion_rings(size, Map.CELL_SIZE),
		NavAgentClass.required_clearance(size, Map.CELL_SIZE)
	)


## Put a new `a_scene` piece at `a_xz` for `a_commander`, finished, and return it. A unit
## that docks is sent to its owner's nearest airfield with a free pad, and without one holds
## over where it was put, as an aircraft whose deck was destroyed does.
static func spawn(
	a_scene: PackedScene, a_map: Map, a_commander: Commander, a_xz: Vector2
) -> Entity:
	var entity: Entity = a_scene.instantiate() as Entity
	if entity == null:
		return null
	var points: Array[Vector2] = [a_xz]
	a_map.add_entities([entity], a_xz, a_commander, points)
	_send_home(entity as Commandable)
	return entity


static func _send_home(a_unit: Commandable) -> void:
	if a_unit == null or a_unit.docking == null or a_unit.commander == null:
		return
	var bay: DockingBay = a_unit.commander.nearest_docking_bay_for(a_unit)
	var airfield: Commandable = (
		bay.owner_commandable() if bay != null and bay.has_free_pad() else null
	)
	if airfield != null:
		a_unit.update_commands(
			Rearm.new(CommandMessage.new(a_unit.map, airfield, null, airfield.global_position))
		)
	elif a_unit.aerial != null:
		a_unit.aerial.set_anchor(a_unit.global_position)
